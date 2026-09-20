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
4. Open a PR. Give it a Conventional Commits title: merges here are squashed,
   so the PR title becomes the commit subject on `main` — CI checks it.
5. `conventions` and `test` run automatically.

## Tests

`npm test` runs two suites, neither of which needs a test framework:

- `tests/install_test.sh` — contract tests for `install.sh`: argument
  validation happens before anything is written, existing files in the target
  repo are never overwritten without `--force`, `core.hooksPath` is wired up
  without hijacking a repo that already routes hooks elsewhere, and — end to
  end, with real `git commit` calls — the type and scope lists in
  `git-conventions.yaml` are what the installed hook actually enforces.
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
