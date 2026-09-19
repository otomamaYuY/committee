#!/usr/bin/env node
// Drift tests for the kit's duplicated sources of truth.
//
// Two kinds of duplication exist here by design, and both can rot silently:
//
//   1. The repo dogfoods its own kit, so several files exist twice — once at
//      the root (the copy a contributor can actually run) and once under
//      templates/ (the copy every adopting repo receives). Fixing only the
//      root leaves CI green while shipping the unfixed version to everyone.
//
//   2. commitlint reads the type list from .claude/git-conventions.yaml at
//      runtime, but commit-check cannot import YAML, so .commit-check.yml
//      restates the same lists as regex alternations. When they disagree, a
//      commit passes the local hook and fails in CI with no local repro.
//
// Neither has a runtime failure mode that points at the duplication, which is
// what makes a test worth more here than a comment.

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const ROOT = path.join(__dirname, '..');

let passed = 0;
let failed = 0;

function ok(desc) { passed++; console.log(`  ok   ${desc}`); }
function no(desc, detail) {
  failed++;
  console.log(`  FAIL ${desc}`);
  if (detail) console.log(`       ${detail}`);
}

function read(rel) { return fs.readFileSync(path.join(ROOT, rel), 'utf8'); }

// --- 1. root <-> templates/ must stay byte-identical -------------------------
// .claude/git-conventions.yaml is deliberately absent: it is the adopter's
// customization surface, so this repo is free to diverge from the template.
const PAIRS = [
  ['commitlint.config.js',                 'templates/commitlint.config.js'],
  ['.commit-check.yml',                    'templates/.commit-check.yml'],
  ['.githooks/commit-msg',                  'templates/githooks/commit-msg'],
  ['.github/workflows/commit-check.yml',   'templates/github-workflows/commit-check.yml'],
  ['.claude/skills/git-conventions/SKILL.md', 'skills/git-conventions/SKILL.md'],
];

console.log('== the dogfooded copy matches the distributed copy');
for (const [rootFile, templateFile] of PAIRS) {
  const desc = `${rootFile} == ${templateFile}`;
  try {
    if (read(rootFile) === read(templateFile)) ok(desc);
    else no(desc, 'contents differ — fix both copies, or delete the root duplicate');
  } catch (e) {
    no(desc, e.message);
  }
}

// --- 2. git-conventions.yaml <-> .commit-check.yml regexes -------------------
console.log('== commit-check regexes match git-conventions.yaml');

const conventions = yaml.load(read('.claude/git-conventions.yaml'));

// Pull the lowercase alternations out of a regex: `(feat|fix|docs)` matches,
// while `(\(.+\))?` and the branch regex's mixed outer group do not.
function alternations(regex) {
  return [...regex.matchAll(/\(([a-z|]+)\)/g)].map(m => m[1].split('|'));
}

function sameSet(a, b) {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

for (const file of ['.commit-check.yml', 'templates/.commit-check.yml']) {
  const checks = yaml.load(read(file)).checks;

  const messageCheck = checks.find(c => c.check === 'message');
  const branchCheck = checks.find(c => c.check === 'branch');

  if (!messageCheck || !branchCheck) {
    no(`${file} defines a message and a branch check`);
    continue;
  }

  const messageGroups = alternations(messageCheck.regex);
  const branchGroups = alternations(branchCheck.regex);

  if (messageGroups.length !== 1) {
    no(`${file} message regex has exactly one type alternation`,
       `found ${messageGroups.length}`);
  } else if (sameSet(messageGroups[0], conventions.commit_types)) {
    ok(`${file} message regex lists the same commit_types`);
  } else {
    no(`${file} message regex lists the same commit_types`,
       `yaml: ${conventions.commit_types.join('|')}\n       regex: ${messageGroups[0].join('|')}`);
  }

  if (branchGroups.length !== 1) {
    no(`${file} branch regex has exactly one prefix alternation`,
       `found ${branchGroups.length}`);
  } else if (sameSet(branchGroups[0], conventions.branch_types)) {
    ok(`${file} branch regex lists the same branch_types`);
  } else {
    no(`${file} branch regex lists the same branch_types`,
       `yaml: ${conventions.branch_types.join('|')}\n       regex: ${branchGroups[0].join('|')}`);
  }
}

// --- 3. the regexes accept and reject what the conventions describe ----------
console.log('== the branch regex behaves as the conventions describe');

const branchRegex = new RegExp(
  yaml.load(read('.commit-check.yml')).checks.find(c => c.check === 'branch').regex
);

const branchCases = [
  ['main', true], ['develop', true],
  ['feature/add-pnpm-example', true],
  ['claude/scaffold-kit', true],
  ['Feature/Capitalized', false],
  ['feature/Trailing-', false],
  ['nosuchtype/thing', false],
];

for (const [name, expected] of branchCases) {
  const got = branchRegex.test(name);
  if (got === expected) ok(`branch "${name}" is ${expected ? 'accepted' : 'rejected'}`);
  else no(`branch "${name}" should be ${expected ? 'accepted' : 'rejected'}`);
}

// --- 4. third-party actions must be pinned to a commit ----------------------
// A tag is mutable: `@v1` resolves at run time to whatever that repository's
// maintainer — or whoever compromises it — has v1 pointing at. Actions under
// actions/ are GitHub's own and are left on their major tag deliberately.
console.log('== third-party actions are pinned to a commit SHA');

const WORKFLOW_DIRS = ['.github/workflows', 'templates/github-workflows'];

for (const dir of WORKFLOW_DIRS) {
  for (const name of fs.readdirSync(path.join(ROOT, dir)).sort()) {
    const text = read(path.join(dir, name));
    for (const m of text.matchAll(/uses:\s*(\S+)/g)) {
      const ref = m[1];
      if (ref.startsWith('actions/')) continue;
      const desc = `${dir}/${name}: ${ref.split('@')[0]}`;
      if (/@[0-9a-f]{40}$/.test(ref)) ok(`${desc} is SHA-pinned`);
      else no(`${desc} is SHA-pinned`, `pinned to "${ref.split('@')[1]}" — a mutable tag`);
    }
  }
}

// --- 5. workflows declare their token scope ---------------------------------
console.log('== workflows declare permissions explicitly');

for (const dir of WORKFLOW_DIRS) {
  for (const name of fs.readdirSync(path.join(ROOT, dir)).sort()) {
    const wf = yaml.load(read(path.join(dir, name)));
    const declared = wf.permissions !== undefined
      || Object.values(wf.jobs || {}).every(j => j.permissions !== undefined);
    if (declared) ok(`${dir}/${name} declares permissions`);
    else no(`${dir}/${name} declares permissions`,
            'without it the job inherits the repository default, which may be read-write');
  }
}

console.log(`\ndrift_test: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
