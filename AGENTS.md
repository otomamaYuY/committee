# Git conventions

Applies to every branch, commit message and review comment in this repo —
whether written by a person or by a coding agent.

The allowed types, scopes, branch prefixes and review labels live in
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

## Scopes, when the repo defines them

A scope names the part of the repo a change touches: `feat` says what
happened, `feat(hooks)` says where. The two together are what let anyone —
or any tool — read the history without reading the diffs.

`scopes:` is optional. If the file has no such block, any scope is accepted
and the choice is yours. If it does, a scope outside the list is rejected,
and a change that genuinely does not fit any of them wants a new entry in
that file rather than a commit without a scope. A repo-wide change that
belongs to no single scope correctly has none.

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

Read what it printed and fix the cause. Do **not** pass `--no-verify`, and
do not edit or disable the hooks to get a commit through. If a type you
genuinely need is missing, add it to `.claude/git-conventions.yaml` — every
layer reads that file, so one edit changes what is allowed everywhere.
