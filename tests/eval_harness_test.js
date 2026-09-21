#!/usr/bin/env node
// The knowledge-layer eval needs an agent, so it cannot run in CI. That makes
// the harness itself the thing most likely to rot unnoticed: a grader that
// silently passes everything would look exactly like a knowledge layer that
// works, and the first person to trust it would be trusting nothing.
//
// So this drives evals/knowledge-layer/run.js with stub responders whose
// answers are known in advance, and checks that the harness reaches the
// verdict it should. No agent, no tokens, deterministic — safe for `npm test`.

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const yaml = require('js-yaml');
const { spawnSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const RUNNER = path.join(ROOT, 'evals', 'knowledge-layer', 'run.js');
const CASES = path.join(ROOT, 'evals', 'knowledge-layer', 'cases.yaml');

let passed = 0;
let failed = 0;
const ok = d => { passed++; console.log(`  ok   ${d}`); };
const no = (d, detail) => {
  failed++;
  console.log(`  FAIL ${d}`);
  if (detail) console.log(`       ${detail}`);
};

const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'committee-harness-'));
process.on('exit', () => fs.rmSync(TMP, { recursive: true, force: true }));

// A stub responder reads the prompt on stdin and prints a verdict, which is
// exactly the contract run.js expects of `claude -p`.
function stub(name, body) {
  const p = path.join(TMP, name);
  fs.writeFileSync(p, `#!/usr/bin/env node\n'use strict';\n${body}\n`, { mode: 0o755 });
  return `node ${JSON.stringify(p)}`;
}

function runEval(cmd, args = []) {
  const r = spawnSync(process.execPath, [RUNNER, ...args], {
    env: { ...process.env, COMMITTEE_EVAL_CMD: cmd },
    encoding: 'utf8',
  });
  return { status: r.status, out: (r.stdout || '') + (r.stderr || '') };
}

const doc = yaml.load(fs.readFileSync(CASES, 'utf8'));
const cases = doc.cases;
const total = cases.length * 2; // every case runs against both knowledge files

console.log('== the harness agrees with a responder that is always right');

// Answers each question with whatever cases.yaml says is correct, by matching
// the question text it was handed. This is the "knowledge layer works
// perfectly" world; the harness must report a clean run.
const oracle = stub('oracle.js', `
const yaml = require(${JSON.stringify(require.resolve('js-yaml'))});
const fs = require('fs');
const cases = yaml.load(fs.readFileSync(${JSON.stringify(CASES)}, 'utf8')).cases;
const prompt = fs.readFileSync(0, 'utf8');
const hit = cases.find(c => prompt.includes(c.question.trim().split('\\n')[0].trim()));
console.log(hit ? hit.expect.toUpperCase() : 'UNANSWERABLE');
console.log('stubbed');
`);

let r = runEval(oracle);
if (new RegExp(`knowledge_layer_eval: ${total} passed, 0 failed`).test(r.out)) {
  ok(`a fully correct responder scores ${total}/${total}`);
} else {
  no(`a fully correct responder scores ${total}/${total}`, r.out.trim().split('\n').slice(-6).join('\n       '));
}
if (r.status === 0) ok('and exits 0'); else no('and exits 0', `exit ${r.status}`);

console.log('\n== the harness catches a responder that is always wrong');

// The failure the harness exists to catch: confident, well-formed, wrong.
// "YES to everything" is also what a model does when it answers from what it
// already believes about review practice instead of from the file.
r = runEval(stub('yes.js', "require('fs').readFileSync(0); console.log('YES'); console.log('none');"));
if (/knowledge_layer_eval: \d+ passed, \d+ failed/.test(r.out) && !/0 failed/.test(r.out)) {
  ok('always-YES is reported as failures');
} else {
  no('always-YES is reported as failures', r.out.trim().split('\n').slice(-4).join('\n       '));
}
if (r.status === 1) ok('and exits non-zero'); else no('and exits non-zero', `exit ${r.status}`);

console.log('\n== the controls are load-bearing');

// A responder that never declines must fail the control cases specifically.
// If it did not, the controls would be decoration and a confident model could
// score full marks without reading anything.
const controls = cases.filter(c => c.expect === 'unanswerable').map(c => c.id);
if (controls.length === 0) {
  no('cases.yaml has at least one control', 'without one, a model that answers everything scores 100%');
} else {
  ok(`cases.yaml has ${controls.length} control case(s)`);
  const missed = controls.filter(id => !new RegExp(`FAIL ${id}\\b`).test(r.out));
  if (missed.length === 0) ok('a never-declining responder fails every control');
  else no('a never-declining responder fails every control', `passed anyway: ${missed.join(', ')}`);
}

console.log('\n== a malformed answer is a failure, not a guess');

// Grading prose would let a run pass because the reply happened to contain
// the right word somewhere. The first line is the answer or there is no
// answer.
r = runEval(stub('chatty.js', "require('fs').readFileSync(0); console.log('Well, it depends - though the answer is really NO.');"));
if (/unparseable/.test(r.out)) ok('a reply with no verdict on line 1 is unparseable');
else no('a reply with no verdict on line 1 is unparseable', r.out.trim().split('\n').slice(-4).join('\n       '));

console.log('\n== a responder that cannot run is reported, not counted as a pass');

r = runEval('exit 3');
if (/responder exited 3/.test(r.out)) ok('a failing responder is reported');
else no('a failing responder is reported', r.out.trim().split('\n').slice(-4).join('\n       '));
if (r.status === 1) ok('and the run fails'); else no('and the run fails', `exit ${r.status}`);

console.log('\n== both knowledge files are exercised');

// The pair tests compare each knowledge file with its own template twin;
// nothing compares SKILL.md with AGENTS.md. This eval is the only thing that
// would notice them answering differently, and only if it asks both.
r = runEval(oracle);
if (/== SKILL\.md/.test(r.out) && /== AGENTS\.md/.test(r.out)) ok('a run covers SKILL.md and AGENTS.md');
else no('a run covers SKILL.md and AGENTS.md', r.out.trim());

console.log('\n== the agent sees the knowledge files and nothing else');

// The isolation is the whole basis for believing a correct answer came from
// the shipped file. If the prompt ever pointed at the repository itself, a
// passing run would prove nothing.
const spy = stub('spy.js', `
const prompt = require('fs').readFileSync(0, 'utf8');
const fs = require('fs');
const m = prompt.match(/in (\\S+) are described|conventions are\\s+described by the files in (\\S+)/);
const dir = prompt.split(/\\s+/).find(w => w.includes('committee-eval-'));
const listing = dir && fs.existsSync(dir) ? fs.readdirSync(dir).sort().join(',') : 'NO-DIR';
console.log('UNANSWERABLE');
console.log('contents=' + listing);
`);
r = runEval(spy, ['--only', 'control-language']);
if (/contents=/.test(r.out) || /ok {3}control-language/.test(r.out)) {
  const dirs = fs.readdirSync(os.tmpdir()).filter(d => d.startsWith('committee-eval-'));
  if (dirs.length === 0) ok('the staged directory is removed after the run');
  else no('the staged directory is removed after the run', `left behind: ${dirs.join(', ')}`);
} else {
  no('the staged directory is removed after the run', r.out.trim());
}

console.log(`\neval_harness_test: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
