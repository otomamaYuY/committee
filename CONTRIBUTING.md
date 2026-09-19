# Contributing

This repo dogfoods its own conventions:

- **Branches**: `feature/…`, `fix/…`, etc. — see [Conventional Branch](https://conventionalbranch.org)
- **Commits**: Conventional Commits — allowed types are in `.claude/git-conventions.yaml`
- **PR review comments**: Conventional Comments (`label: subject`)

## Workflow

1. Fork and branch from `main` (e.g. `feature/add-pnpm-example`).
2. Make your change with a matching commit message
   (e.g. `docs: clarify pixi install steps`).
3. Open a PR — `commit-check` runs automatically on it.
4. Merges to `main` trigger `semantic-release`; you don't need to bump any
   version number yourself.
