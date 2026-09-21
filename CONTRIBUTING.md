# Contributing

This repo dogfoods its own conventions:

- **Branches**: `feature/…`, `fix/…`, etc. — see [Conventional Branch](https://conventionalbranch.org).
  The `pre-push` hook checks this before anything leaves your machine.
- **Commits**: Conventional Commits — allowed types and scopes are in `.claude/git-conventions.yaml`
- **PR review comments**: Conventional Comments (`label: subject`)

## Workflow

1. Fork and branch from `main` (e.g. `feature/add-a-hook`).
2. Make your change with a matching commit message
   (e.g. `docs: clarify the install steps`).
3. Run `npm test` before opening the PR.
4. Open a PR. Give it a Conventional Commits title: this repo merges with a
   merge commit whose subject is the PR title, so it lands on `main` verbatim
   — CI checks it. Your individual commits are preserved rather than squashed
   away, so each one has to stand on its own too.
5. `conventions` and `test` run automatically.

`git log --first-parent` gives one line per merged PR, which is the summary
view a squash workflow would have left behind. `git bisect --first-parent`
(git 2.29 or newer) is worth knowing about for the case where a PR's
intermediate commits do not build: it walks the merges instead, and you bisect
inside the one it lands on by hand.

## Tests

`npm test` runs two suites, neither of which needs a test framework:

- `tests/install_test.sh` — contract tests for `install.sh`: argument
  validation happens before anything is written, the adopter's files are
  never overwritten without `--force` while the two regions the kit owns are
  refreshed, `core.hooksPath` is wired up
  without hijacking a repo that already routes hooks elsewhere, and — end to
  end, with real `git commit` calls — the type and scope lists in
  `git-conventions.yaml` are what the installed hook actually enforces.
- `tests/eval_harness_test.js` — the knowledge-layer eval cannot run in CI
  (it needs an agent and is not deterministic), so this drives it with stub
  responders and checks the grader reaches the right verdict. A grader that
  silently passed everything would look exactly like a knowledge layer that
  works. See [evals/README.md](evals/README.md) for the eval itself and how to
  run it with `npm run eval`.
- `tests/drift_test.js` — catches what rots without raising an error: the
  root files this repo dogfoods against their `templates/` counterparts, the
  claim that `.claude/git-conventions.yaml` is the single source of truth
  (it loads `commitlint.config.js` and checks the list commitlint will
  actually enforce), and the workflows' pinning, permissions and freedom
  from `${{ }}` interpolation inside `run:`.

Both failure modes are quiet in production — a stale `templates/` copy still
leaves CI green here while shipping the unfixed file to every adopting repo —
so please add a case rather than only fixing the symptom.

A third suite, `tests/package_manager_test.sh`, is not in `npm test`: it
installs the kit into a scratch repo, installs the dependencies with one
package manager, and drives a real commit and push through the hooks. Run it
for npm locally; CI runs it for pnpm and Yarn Classic, which is what lets the
README name those two instead of reasoning about them.

```bash
bash tests/package_manager_test.sh npm
```

If you touch a shell file, run what CI runs:

```bash
shellcheck --severity=info install.sh tests/*.sh templates/githooks/*
```

`info` rather than `warning`, because SC2086 — an unquoted expansion —
reports at `info`, and `install.sh` runs `rm -rf` against a path its caller
supplied.

**CI pins shellcheck 0.11.0**, and your local version should match. Earlier
it used whatever `ubuntu-latest` shipped, and the versions disagreed:
0.11.0 no longer reports SC2016 on `sh -c '... "$1" ...'`, so a contributor
could be clean locally and fail here with nothing to reproduce. `brew
install shellcheck` currently gives 0.11.0.

## The lockfile

Regenerate it from scratch, never incrementally:

```bash
rm -rf node_modules package-lock.json && npm install
```

`npm install` on top of an existing `node_modules` silently drops the
optional platform packages a clean resolve produces — about 360 lines that
look like a deliberate deletion in a diff. Nothing breaks, because they are
optional, which is exactly why it would go unnoticed. CI compares the
committed lockfile against a clean resolve and fails if they differ.

## The duplication is deliberate

Several files exist twice: once under `templates/` (what adopters receive)
and once at the repo root (what this repo runs on itself). **Change both.**
`npm test` fails if they drift, which is the only thing standing between a
root-only fix and shipping the unfixed file to every adopting repo.

`.claude/git-conventions.yaml` is the one exception — it is the adopter's
customization surface, so this repo's copy is free to differ from the
template.
