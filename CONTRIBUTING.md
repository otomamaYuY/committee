# Contributing

This repo dogfoods its own conventions:

- **Branches**: `feature/…`, `fix/…`, etc. — see [Conventional Branch](https://conventionalbranch.org).
  The `pre-push` hook checks this before anything leaves your machine.
- **Commits**: Conventional Commits — allowed types are in `.claude/git-conventions.yaml`
- **PR review comments**: Conventional Comments (`label: subject`)

## Workflow

1. Fork and branch from `main` (e.g. `feature/add-a-hook`).
2. Make your change with a matching commit message
   (e.g. `docs: clarify the install steps`).
3. Run `npm test` before opening the PR.
4. Open a PR — `conventions` and `test` run automatically on it.

## Tests

`npm test` runs two suites, neither of which needs a test framework:

- `tests/install_test.sh` — contract tests for `install.sh`: argument
  validation happens before anything is written, existing files in the target
  repo are never overwritten without `--force`, `core.hooksPath` is wired up
  without hijacking a repo that already routes hooks elsewhere, and — end to
  end, with real `git commit` calls — the type list in `git-conventions.yaml`
  is what the installed hook actually enforces.
- `tests/drift_test.js` — catches what rots without raising an error: the
  root files this repo dogfoods against their `templates/` counterparts, the
  claim that `.claude/git-conventions.yaml` is the single source of truth
  (it loads `commitlint.config.js` and checks the list commitlint will
  actually enforce), and the workflows' pinning, permissions and freedom
  from `${{ }}` interpolation inside `run:`.

Both failure modes are quiet in production — a stale `templates/` copy still
leaves CI green here while shipping the unfixed file to every adopting repo —
so please add a case rather than only fixing the symptom.

If you touch a shell file, also run
`shellcheck --severity=info install.sh tests/install_test.sh templates/githooks/*`;
CI does.

## The duplication is deliberate

Several files exist twice: once under `templates/` (what adopters receive)
and once at the repo root (what this repo runs on itself). **Change both.**
`npm test` fails if they drift, which is the only thing standing between a
root-only fix and shipping the unfixed file to every adopting repo.

`.claude/git-conventions.yaml` is the one exception — it is the adopter's
customization surface, so this repo's copy is free to differ from the
template.
