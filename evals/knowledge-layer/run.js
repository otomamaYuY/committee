#!/usr/bin/env node
// Measures whether the knowledge layer actually answers the questions it
// exists to answer — the kit's central claim, and the one thing no other
// test here touches.
//
// The enforcement layer is checked by tests/install_test.sh: a hook either
// rejects a commit or it does not. The knowledge layer has no such test,
// because "did an agent understand this" is not a property a regex can read.
// So this asks one.
//
// Two things make it a measurement rather than a demo:
//
//   1. The agent is given ONLY the knowledge files, copied into an empty
//      directory outside this repository. No CLAUDE.md, no git history, no
//      design document, nothing else to infer from. If it answers correctly
//      it is because the shipped file said so.
//
//   2. Answers are graded mechanically against the first line of the reply.
//      No model judges another model's answer.
//
// It is deliberately NOT part of `npm test`: it needs an agent, it costs
// tokens, and it is not deterministic, so it must never be able to fail a
// pull request. `tests/eval_harness_test.js` covers the harness itself, which
// is deterministic and is in `npm test`.
//
// Usage:  node evals/knowledge-layer/run.js [--only <id>] [--file <path>]
// The responder is `claude -p` unless COMMITTEE_EVAL_CMD says otherwise; the
// prompt arrives on stdin and the reply is read from stdout.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const yaml = require('js-yaml');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..', '..');
const CASES = path.join(__dirname, 'cases.yaml');

// Both halves of the knowledge layer carry the same rules in their own voice,
// and nothing checks that they agree — the pair tests only compare each file
// with its own template twin. Running every case against both is what would
// catch them drifting apart.
const SUBJECTS = [
  { name: 'SKILL.md', file: '.claude/skills/git-conventions/SKILL.md' },
  { name: 'AGENTS.md', file: 'AGENTS.md' },
];

const CONVENTIONS = '.claude/git-conventions.yaml';
const VERDICTS = ['yes', 'no', 'unanswerable'];

const argv = process.argv.slice(2);
const only = argv.includes('--only') ? argv[argv.indexOf('--only') + 1] : null;
const onlyFile = argv.includes('--file') ? argv[argv.indexOf('--file') + 1] : null;

const responder = process.env.COMMITTEE_EVAL_CMD || 'claude -p';

function prompt(knowledgeDir, question) {
  return `You are a code reviewer working in a repository whose conventions are
described by the files in ${knowledgeDir}. Read them.

Answer using those files and nothing else. Do not use anything you already
know about Conventional Comments or about review practice in general — if the
files do not settle the question, that is itself the answer.

Question: ${question.trim()}

Reply in exactly this form:

  Line 1: one word - YES, NO, or UNANSWERABLE
          UNANSWERABLE means the files do not settle it.
  Line 2: the sentence from the files you based it on, or "none".

Nothing else.`;
}

function ask(text) {
  const r = spawnSync('sh', ['-c', responder], {
    input: text,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
  });
  if (r.error) return { ok: false, detail: r.error.message };
  if (r.status !== 0) {
    return { ok: false, detail: `responder exited ${r.status}: ${(r.stderr || '').trim().slice(0, 300)}` };
  }
  return { ok: true, reply: r.stdout };
}

// The first non-empty line, reduced to a verdict. Anything that is not one of
// the three words is a malformed answer and is reported as such rather than
// being guessed at — a grader that "helpfully" interprets a stray reply is
// how an eval starts passing for the wrong reason.
function verdictOf(reply) {
  const first = (reply || '').split('\n').map(l => l.trim()).find(l => l.length > 0) || '';
  const word = first.replace(/[^A-Za-z-]/g, ' ').trim().split(/\s+/)[0] || '';
  const v = word.toLowerCase();
  return VERDICTS.includes(v) ? v : null;
}

function stageKnowledge(subject) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'committee-eval-'));
  fs.copyFileSync(path.join(ROOT, subject.file), path.join(dir, path.basename(subject.file)));
  fs.copyFileSync(path.join(ROOT, CONVENTIONS), path.join(dir, path.basename(CONVENTIONS)));
  return dir;
}

function main() {
  const doc = yaml.load(fs.readFileSync(CASES, 'utf8'));
  let cases = (doc && doc.cases) || [];
  if (only) cases = cases.filter(c => c.id === only);
  if (cases.length === 0) {
    console.error(only ? `no case with id "${only}"` : 'no cases found');
    process.exit(2);
  }

  const subjects = onlyFile ? SUBJECTS.filter(s => s.name === onlyFile || s.file === onlyFile) : SUBJECTS;
  if (subjects.length === 0) {
    console.error(`no knowledge file matching "${onlyFile}"`);
    process.exit(2);
  }

  console.log(`responder: ${responder}`);
  let passed = 0;
  let failed = 0;
  const wrong = [];

  for (const subject of subjects) {
    console.log(`\n== ${subject.name} + ${path.basename(CONVENTIONS)}`);
    const dir = stageKnowledge(subject);
    try {
      for (const c of cases) {
        const res = ask(prompt(dir, c.question));
        if (!res.ok) {
          failed++;
          wrong.push({ subject: subject.name, id: c.id, got: 'no answer', want: c.expect, note: res.detail });
          console.log(`  FAIL ${c.id} - ${res.detail}`);
          continue;
        }
        const got = verdictOf(res.reply);
        if (got === c.expect) {
          passed++;
          console.log(`  ok   ${c.id}`);
        } else {
          failed++;
          const shown = got || `unparseable (${JSON.stringify((res.reply || '').trim().slice(0, 60))})`;
          wrong.push({ subject: subject.name, id: c.id, got: shown, want: c.expect, note: (c.tests || '').trim() });
          console.log(`  FAIL ${c.id} - expected ${c.expect}, got ${shown}`);
        }
      }
    } finally {
      fs.rmSync(dir, { recursive: true, force: true });
    }
  }

  if (wrong.length > 0) {
    console.log('\nWhat each failure means the shipped file did not convey:');
    for (const w of wrong) {
      console.log(`  ${w.subject} ${w.id}: wanted ${w.want}, got ${w.got}`);
      if (w.note) console.log(`    ${w.note}`);
    }
  }

  console.log(`\nknowledge_layer_eval: ${passed} passed, ${failed} failed`);
  // A failure here is a finding about the prose, not a broken build. The exit
  // code is for a human running it deliberately, and nothing in CI reads it.
  process.exit(failed === 0 ? 0 : 1);
}

main();
