---
name: git-conventions
description: Use whenever creating a git branch, writing a commit message, tagging a release/version bump, or leaving PR/code review comments in this repo. Also use before running `git commit`, `git checkout -b`, `gh pr review`, or `gh pr comment`.
---

# Git Conventions

Allowed types/prefixes/labels are defined in `.claude/git-conventions.yaml`
— the single source of truth, also read by `commitlint.config.js` and the
`pre-push` hook. Read that file before constructing a branch name, commit
message, or review comment; do not assume a fixed list.

## Shape (from the specs themselves — rarely changes)

- **Branch** — [Conventional Branch](https://conventionalbranch.org):
  `<type>/<description>` (lowercase, hyphen-separated). Claude Code's own
  branches use the `claude/` prefix, so a reviewer can tell at a glance where
  a branch came from. `main`/`master`/`develop` need no prefix.
- **Commit** — [Conventional Commits](https://www.conventionalcommits.org):
  `<type>[optional scope]: <description>`. Breaking change: `!` after
  type/scope, or a `BREAKING CHANGE:` footer.
- **Version** — [SemVer](https://semver.org): MAJOR.MINOR.PATCH.
  feat→MINOR, fix→PATCH, BREAKING CHANGE→MAJOR. The commit type is what
  decides the next version, so pick it for what the change does, not for
  what is convenient.
- **Review comment** — [Conventional Comments](https://conventionalcomments.org):
  `<label> [decorations]: <subject>`.
  **No linter checks this one — this skill is the only safeguard.** Pick the
  type/label that actually matches the change, not just one that happens to
  be on the allowed list.

## When a hook rejects you

A `commit-msg` hook and a `pre-push` hook run automatically, and CI repeats
both. If one rejects you, read what it printed and fix the cause. Do **not**
pass `--no-verify`, and do not edit or disable a hook to get a commit
through — that turns off the layer these conventions rely on. If a type you
genuinely need is missing, add it to `.claude/git-conventions.yaml`: every
layer reads that file, so one edit changes what is allowed everywhere.

## Why this matters beyond formatting

The enforcement layer (commitlint and the git hooks) only validates that the
`type` string is on the allowed list — it cannot tell whether `feat` was the
*correct* choice for a given diff. The type is what a reader, a changelog
and any release tooling use to decide what changed and what the next
version should be, so a mislabeled commit misstates the change to everyone
downstream. Think about what the change actually does before picking a
type/label, not just which string is permitted.
