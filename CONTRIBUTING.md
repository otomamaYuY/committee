# Contributing

This repo dogfoods its own conventions:

- **Branches**: `feature/…`, `fix/…`, etc. — see [Conventional Branch](https://conventionalbranch.org)
- **Commits**: Conventional Commits — allowed types are in `.claude/git-conventions.yaml`
- **PR review comments**: Conventional Comments (`label: subject`)

## Workflow

1. Fork and branch from `main` (e.g. `feature/add-a-hook`).
2. Make your change with a matching commit message
   (e.g. `docs: clarify the install steps`).
3. Run `npm test` before opening the PR.
4. Open a PR — `commit-check` and `test` run automatically on it.

## Tests

`npm test` runs two suites, neither of which needs a test framework:

- `tests/install_test.sh` — contract tests for `install.sh`: argument
  validation happens before anything is written, existing files in the target
  repo are never overwritten without `--force`, `core.hooksPath` is wired up
  without hijacking a repo that already routes hooks elsewhere, and — end to
  end, with real `git commit` calls — the type list in `git-conventions.yaml`
  is what the installed hook actually enforces.
- `tests/drift_test.js` — catches the two duplications that rot silently: the
  root files this repo dogfoods against their `templates/` counterparts, and
  the type/branch lists in `.claude/git-conventions.yaml` against the regexes
  in `.commit-check.yml`, which cannot import YAML.

Both failure modes are quiet in production — a stale `templates/` copy still
leaves CI green here while shipping the unfixed file to every adopting repo —
so please add a case rather than only fixing the symptom.

If you touch `install.sh`, also run `shellcheck --severity=error install.sh`;
CI does.
