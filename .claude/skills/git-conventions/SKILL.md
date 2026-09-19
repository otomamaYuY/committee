---
name: git-conventions
description: Use whenever creating a git branch, writing a commit message, tagging a release/version bump, or leaving PR/code review comments in this repo. Also use before running `git commit`, `git checkout -b`, `gh pr review`, or `gh pr comment`.
---

# Git Conventions

Allowed types/scopes/prefixes/labels are defined in `.claude/git-conventions.yaml`
(the single source of truth, also consumed by commitlint and commit-check).
Read that file before constructing a branch name, commit message, or review
comment — do not assume a fixed list.

## Shape (from the specs themselves — rarely changes)

- **Branch** — [Conventional Branch](https://conventionalbranch.org):
  `<type>/<description>` (lowercase, hyphen-separated). Claude Code's own
  branches use the `claude/` prefix. `main`/`master`/`develop` need no prefix.
- **Commit** — [Conventional Commits](https://www.conventionalcommits.org):
  `<type>[optional scope]: <description>`. Breaking change: `!` after
  type/scope, or a `BREAKING CHANGE:` footer.
- **Version** — [SemVer](https://semver.org): MAJOR.MINOR.PATCH.
  feat→MINOR, fix→PATCH, BREAKING CHANGE→MAJOR. Automated by
  semantic-release from commit types — never hand-edit a version number.
- **Review comment** — [Conventional Comments](https://conventionalcomments.org):
  `<label> [decorations]: <subject>`.
  **No linter checks this one — this skill is the only safeguard.** Pick the
  type/label that actually matches the change, not just one that happens to
  be on the allowed list.

## Why this matters beyond formatting

The enforcement layer (commitlint / commit-check) only validates that the
`type` string is on the allowed list — it cannot tell whether `feat` was the
*correct* choice for a given diff. semantic-release trusts the type
literally when computing the next version, so a mislabeled commit ships the
wrong version number, which cannot be undone once released. Think about
what the change actually does before picking a type/label, not just which
string is permitted.
