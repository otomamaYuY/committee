const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

// The allowed types — and the optional scopes — live in
// .claude/git-conventions.yaml, not in this file.
// Every failure below is therefore reported against THAT file. Left to
// itself commitlint blames this one instead — a missing config produces
// "Please add rules to your commitlint.config.js", and a typo in the
// commit_types key produces "type must be one of []", which rejects every
// commit while naming neither the real file nor the real mistake.
const CONFIG = path.join(__dirname, '.claude', 'git-conventions.yaml');

function fail(problem, fix) {
  throw new Error(
    `commitlint.config.js: ${problem}\n` +
    `  file: ${CONFIG}\n` +
    `  fix:  ${fix}`
  );
}

let raw;
try {
  raw = fs.readFileSync(CONFIG, 'utf8');
} catch (e) {
  fail(
    `cannot read the conventions file (${e.code || e.message})`,
    're-run the committee install.sh, or restore the file from version control'
  );
}

let parsed;
try {
  parsed = yaml.load(raw);
} catch (e) {
  fail(
    `the conventions file is not valid YAML — ${e.reason || e.message}`,
    'check the indentation near the line named above'
  );
}

const commitTypes = parsed && parsed.commit_types;
if (!Array.isArray(commitTypes) || commitTypes.length === 0) {
  fail(
    'no non-empty "commit_types:" list found in the conventions file',
    'add a commit_types: block listing the allowed types — and check the key for a typo'
  );
}

const rules = {
  'type-enum': [2, 'always', commitTypes],
};

// "scopes:" is optional, and absent from the shipped template. A list of
// scopes names the seams of one particular repo, so a default could only be
// a guess — and every wrong guess rejects a correct commit, which is the
// pressure that ends in --no-verify. The rule therefore exists only once a
// repo has written its own list. Conventional Commits keeps the scope itself
// optional, so a listed repo can still commit without one.
const scopes = parsed.scopes;

if (scopes !== undefined && scopes !== null) {
  const usable = Array.isArray(scopes) && scopes.length > 0 &&
    scopes.every(s => typeof s === 'string' && s.trim() !== '');
  if (!usable) {
    fail(
      'a "scopes:" key is present but is not a non-empty list of names',
      'list the allowed scopes under it, or delete the key to accept any scope'
    );
  }
  rules['scope-enum'] = [2, 'always', scopes];
}

module.exports = {
  extends: ['@commitlint/config-conventional'],
  rules,
};
