# Git conventions

Applies to every branch, commit message and review comment in this repo —
whether written by a person or by a coding agent.

The allowed types, branch prefixes and review labels live in
`.claude/git-conventions.yaml`. **Read that file before writing a branch
name, a commit message or a review comment.** Do not work from the examples
below: they show the shape, not the list.

| What | Format | Spec |
|---|---|---|
| Branch | `<type>/<short-description>`, lowercase, hyphen-separated | [Conventional Branch](https://conventionalbranch.org) |
| Commit | `<type>[optional scope]: <description>` | [Conventional Commits](https://www.conventionalcommits.org) |
| Version | MAJOR.MINOR.PATCH — feat→MINOR, fix→PATCH, breaking→MAJOR | [SemVer](https://semver.org) |
| Review comment | `<label> [decorations]: <subject>` | [Conventional Comments](https://conventionalcomments.org) |

`main`, `master` and `develop` need no branch prefix. A breaking change is
marked with `!` after the type/scope, or a `BREAKING CHANGE:` footer.

## Picking the right type is your job, not the linter's

A commit-msg hook and a pre-push hook run automatically, and CI repeats
both. They check **shape**: that the string matches an allowed pattern.

They cannot tell that a bug fix was labelled `feat:`. That passes every
check, and the type is what a reader, a changelog and any release tooling
rely on to know what changed — so a mislabelled commit misstates the change
to everyone downstream.

Conventional Comments has no linter at all. Nothing but your judgment
checks a review comment's label.

So choose the type or label that matches what the change actually does, not
the first one on the list that would be accepted.

## When a hook rejects you

Read what it printed and fix the cause. Do **not** pass `--no-verify`, and
do not edit or disable the hooks to get a commit through. If a type you
genuinely need is missing, add it to `.claude/git-conventions.yaml` — every
layer reads that file, so one edit changes what is allowed everywhere.
