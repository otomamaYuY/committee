---
name: git-conventions
description: Use whenever creating a git branch, writing a commit message, tagging a release/version bump, or leaving PR/code review comments in this repo. Also use before running `git commit`, `git checkout -b`, `gh pr review`, or `gh pr comment`.
---

# Git Conventions

Allowed types/scopes/prefixes/labels are defined in
`.claude/git-conventions.yaml` — the single source of truth, also read by
`commitlint.config.js` and the `pre-push` hook. Read that file before
constructing a branch name, commit message, or review comment; do not assume
a fixed list.

## Shape (from the specs themselves — rarely changes)

- **Branch** — [Conventional Branch](https://conventionalbranch.org):
  `<type>/<description>` (lowercase, hyphen-separated). Claude Code's own
  branches use the `claude/` prefix, so a reviewer can tell at a glance where
  a branch came from. `main`/`master`/`develop` need no prefix.
- **Commit** — [Conventional Commits](https://www.conventionalcommits.org):
  `<type>[optional scope]: <description>`. Breaking change: `!` after
  type/scope, or a `BREAKING CHANGE:` footer.
- **Scope** — optional, and enforced only where the conventions file has a
  `scopes:` block. `feat` says what happened; `feat(hooks)` says where, which
  is what makes the history readable without the diffs. With no such block
  any scope is accepted. With one, a change that fits none of the listed
  scopes wants a new entry in that file — not a commit stripped of its
  scope to get through. A genuinely repo-wide change correctly has none.
- **Version** — [SemVer](https://semver.org): MAJOR.MINOR.PATCH.
  feat→MINOR, fix→PATCH, BREAKING CHANGE→MAJOR. The commit type is what
  decides the next version, so pick it for what the change does, not for
  what is convenient.
- **Review comment** — [Conventional Comments](https://conventionalcomments.org):
  `<label> [decorations]: <subject>`.
  **No linter checks this one — this skill is the only safeguard.** Pick the
  type/label that actually matches the change, not just one that happens to
  be on the allowed list. What blocks a merge is covered below.

## Leaving a review

**Blocking is carried by the decoration, never by the label.** A comment does
not stop a pull request being approved unless it carries `(blocking)`. If you
mean one to stop it, say so — no label does it for you. The decorations are
`(blocking)`, `(non-blocking)` and `(if-minor)`. Under this default
`(non-blocking)` is redundant and exists to be explicit when you want to be;
`(if-minor)` never blocks and leaves resolution to the author when the change
turns out to be trivial.

None of this depends on which label a comment carries — including a label the
conventions file does not list. Such a comment is malformed and should be
relabelled, but until it is, its decoration alone still decides whether it
blocks. Nothing is more blocking for sounding more serious.

Where the specification's own description of a label makes its comments a
prerequisite for acceptance — `chore:` is defined that way, for example —
decorate them `(blocking)` yourself. Which labels those are is answered by the
spec's own label descriptions, linked above, and deliberately not repeated
here. The default does not do it for you. That
is a deliberate departure from the spec, not a reading of it: stating it per
label would mean writing a second list of labels outside
`.claude/git-conventions.yaml`, which is the one thing this kit does not do.

**A comment is resolved when the person who left it says so** — they mark the
thread resolved, or reply agreeing it is addressed. A reply from the author,
or a new commit, does not resolve someone else's comment, and an author
clearing a `(blocking)` comment against themselves does not count, even where
the platform allows the click.

**Approve when no unresolved comment carries `(blocking)`.** Withholding
approval for any other reason is still yours to do. This says when a *comment*
stops a merge, not when *you* do.

**Leave praise where there is something to praise, and look for it before
concluding there is not.** Never write praise you do not mean: the spec warns
that false praise does damage, so an insincere one is worse than none. This is
guidance rather than a condition of approval — as a condition it would leave
manufacturing praise as the only way past a change with nothing to admire.

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
