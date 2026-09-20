#!/usr/bin/env node
// Drift tests for the things that rot without producing a runtime error.
//
//   1. The repo dogfoods its own kit, so several files exist twice — once at
//      the root (the copy a contributor can actually run) and once under
//      templates/ (the copy every adopting repo receives). Fixing only the
//      root leaves CI green here while shipping the unfixed file to everyone.
//
//   2. git-conventions.yaml is supposed to be the single source of truth. If
//      commitlint.config.js or the pre-push hook ever stopped deriving their
//      lists from it, both would still work — they would just quietly
//      disagree about what is allowed.
//
//   3. A workflow pinned to a mutable tag, with no permissions block, or
//      interpolating an event value into a shell command is a supply-chain
//      hole that no passing test run will ever surface.

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
// .github/workflows/test.yml is absent too — it tests the kit itself and is
// not shipped to adopters.
const PAIRS = [
  ['AGENTS.md',                               'templates/AGENTS.md'],
  ['commitlint.config.js',                    'templates/commitlint.config.js'],
  ['.githooks/commit-msg',                    'templates/githooks/commit-msg'],
  ['.githooks/pre-push',                      'templates/githooks/pre-push'],
  ['.github/workflows/conventions.yml',       'templates/github-workflows/conventions.yml'],
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

// --- 2. git-conventions.yaml really is the single source of truth ------------
console.log('== the conventions file drives the tools that enforce it');

const conventions = yaml.load(read('.claude/git-conventions.yaml'));

for (const key of ['commit_types', 'branch_types', 'comment_labels']) {
  if (Array.isArray(conventions[key]) && conventions[key].length > 0) {
    ok(`git-conventions.yaml defines ${key}`);
  } else {
    no(`git-conventions.yaml defines ${key}`, `got ${JSON.stringify(conventions[key])}`);
  }
}

// Load the real config the way commitlint does, rather than reading it as
// text: this fails if the file stops deriving its list from the yaml, even
// though both files would still be individually valid.
const commitlintConfig = require(path.join(ROOT, 'commitlint.config.js'));
const typeEnum = commitlintConfig.rules && commitlintConfig.rules['type-enum']
  ? commitlintConfig.rules['type-enum'][2]
  : undefined;

if (!Array.isArray(typeEnum)) {
  no('commitlint.config.js exposes a type-enum rule', `got ${JSON.stringify(typeEnum)}`);
} else if (JSON.stringify(typeEnum) === JSON.stringify(conventions.commit_types)) {
  ok('commitlint enforces exactly the yaml commit_types');
} else {
  no('commitlint enforces exactly the yaml commit_types',
     `yaml:       ${conventions.commit_types.join(', ')}\n       commitlint: ${typeEnum.join(', ')}`);
}

// The pre-push hook must read the yaml rather than restate it — a second
// copy of the list is how the local hook and CI start disagreeing.
const prePush = read('.githooks/pre-push');
if (prePush.includes('git-conventions.yaml')) ok('pre-push reads the conventions file');
else no('pre-push reads the conventions file', 'it appears to hardcode its own list');

const hardcoded = conventions.branch_types.filter(
  t => new RegExp(`[|'"(]${t}[|'")]`).test(prePush)
);
if (hardcoded.length === 0) ok('pre-push hardcodes no branch types');
else no('pre-push hardcodes no branch types',
        `found ${hardcoded.join(', ')} — the list belongs in git-conventions.yaml only`);

// Both knowledge-layer files must point agents at the config rather than
// carrying their own copy of the lists, or an edit to the yaml silently
// stops matching what the agent was told.
for (const doc of ['AGENTS.md', 'skills/git-conventions/SKILL.md']) {
  if (read(doc).includes('git-conventions.yaml')) ok(`${doc} points at the conventions file`);
  else no(`${doc} points at the conventions file`, 'it appears to carry its own list');
}

// Every template must be accounted for: drift-checked against a root copy or
// deliberately exempt, and actually referenced by the installer. A template
// missing from PAIRS is never drift-checked; one missing from install.sh
// ships to nobody.
console.log('== every template is drift-checked and installed');

// Files with no root counterpart, and why.
const UNPAIRED = {
  'templates/git-conventions.yaml': "the root copy is this repo's own customization surface",
  'templates/package.json.example': 'the root package.json is the kit itself, not an adopter',
};

function walk(dir) {
  return fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true }).flatMap(e =>
    e.isDirectory() ? walk(path.join(dir, e.name)) : [path.join(dir, e.name)]
  );
}

const paired = new Set(PAIRS.map(([, tpl]) => tpl));
const installer = read('install.sh');

for (const tpl of walk('templates').sort()) {
  if (paired.has(tpl) || tpl in UNPAIRED) ok(`${tpl} is accounted for`);
  else no(`${tpl} is accounted for`,
          'add it to PAIRS with a root copy, or to UNPAIRED with a reason');

  // The hooks are installed through a loop over their basenames.
  const referenced = installer.includes(tpl)
    || installer.includes(path.dirname(tpl) + '/$_hook');
  if (referenced) ok(`${tpl} is referenced by install.sh`);
  else no(`${tpl} is referenced by install.sh`, 'it would ship to nobody');
}

// Splitting the README into docs/ created a new way for the docs to rot: a
// link that points at nothing, or a page nothing points at. Neither breaks
// anything at runtime, so nothing else would catch it.
console.log('== the docs link to each other and to files that exist');

const MARKDOWN = ['README.md', 'CONTRIBUTING.md', 'CLAUDE.md', 'AGENTS.md', 'SECURITY.md']
  .concat(fs.readdirSync(path.join(ROOT, 'docs')).map(f => path.join('docs', f)));

const linked = new Set();

for (const file of MARKDOWN) {
  const text = read(file);
  for (const m of text.matchAll(/\]\(([^)#][^)]*)\)/g)) {
    const target = m[1];
    if (/^[a-z]+:/.test(target)) continue;            // external
    const resolved = path.normalize(path.join(path.dirname(file), target.split('#')[0]));
    linked.add(resolved);
    if (fs.existsSync(path.join(ROOT, resolved))) ok(`${file} -> ${target}`);
    else no(`${file} -> ${target}`, 'the link points at nothing');
  }
}

for (const doc of fs.readdirSync(path.join(ROOT, 'docs'))) {
  const rel = path.join('docs', doc);
  if (linked.has(rel)) ok(`${rel} is reachable`);
  else no(`${rel} is reachable`, 'nothing links to it, so nobody will find it');
}

// --- 3. workflows are pinned, scoped, and injection-free ---------------------
console.log('== workflows are pinned and scoped');

const WORKFLOW_DIRS = ['.github/workflows', 'templates/github-workflows'];

for (const dir of WORKFLOW_DIRS) {
  for (const name of fs.readdirSync(path.join(ROOT, dir)).sort()) {
    const rel = path.join(dir, name);
    const text = read(rel);

    // A tag is mutable: `@v1` resolves at run time to whatever that
    // repository's maintainer — or whoever compromises it — has v1 pointing
    // at. Actions under actions/ are GitHub's own and stay on a major tag.
    for (const m of text.matchAll(/uses:\s*(\S+)/g)) {
      const ref = m[1];
      if (ref.startsWith('actions/')) continue;
      const desc = `${rel}: ${ref.split('@')[0]}`;
      if (/@[0-9a-f]{40}$/.test(ref)) ok(`${desc} is SHA-pinned`);
      else no(`${desc} is SHA-pinned`, `pinned to "${ref.split('@')[1]}" — a mutable tag`);
    }

    const wf = yaml.load(text);
    const jobs = Object.values(wf.jobs || {});

    // Presence is not enough: `permissions: write-all` would satisfy a
    // key-exists check while granting exactly what the check exists to stop.
    const scopeSets = wf.permissions !== undefined
      ? [wf.permissions]
      : jobs.map(j => j.permissions);

    if (jobs.length === 0) {
      no(`${rel} defines at least one job`, 'an empty jobs map would pass every check below vacuously');
    } else if (scopeSets.some(s => s === undefined)) {
      no(`${rel} declares permissions`,
         'without it the job inherits the repository default, which may be read-write');
    } else {
      const offenders = [];
      for (const scopes of scopeSets) {
        if (typeof scopes === 'string') {
          if (scopes !== 'read-all') offenders.push(scopes);
          continue;
        }
        for (const [scope, level] of Object.entries(scopes)) {
          if (level !== 'read' && level !== 'none') offenders.push(`${scope}: ${level}`);
        }
      }
      if (offenders.length === 0) ok(`${rel} grants only read scopes`);
      else no(`${rel} grants only read scopes`,
              `found ${offenders.join(', ')} — if a write scope is genuinely needed, ` +
              'add it to this allowlist deliberately rather than loosening the check');
    }

    // A `${{ }}` expression inside a run: body is how a workflow becomes a
    // script-injection sink. Read the parsed step, so the multi-line
    // `run: |` form — the shape most real injections take — is covered too.
    const injected = [];
    for (const job of jobs) {
      for (const step of job.steps || []) {
        if (typeof step.run === 'string' && step.run.includes('${{')) {
          injected.push(step.name || step.run.split('\n')[0].slice(0, 40));
        }
      }
    }
    if (injected.length === 0) ok(`${rel} keeps event values out of run: bodies`);
    else no(`${rel} keeps event values out of run: bodies`,
            `step(s) interpolating an expression: ${injected.join('; ')} — pass them through env:`);
  }
}

console.log(`\ndrift_test: ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
