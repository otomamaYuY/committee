<!--
The title of this pull request must follow Conventional Commits:

    <type>[optional scope]: <description>        e.g. fix(install): stop clobbering the target's Makefile

This is not a formality. This repo merges with a merge commit whose subject
is the pull request title, so the title lands on the default branch verbatim,
and CI checks it. The commits on your branch are preserved rather than
squashed away — write each one as if it will be read alone, because it will.

Allowed types are in .claude/git-conventions.yaml.
-->

## What changes

<!-- The behaviour that is different afterwards, not a list of files. -->

## Why

<!-- What was wrong, or what this makes possible. Link an issue if there is one. -->

## How it was verified

<!--
What you ran, and what it showed. If you added a guard, say how you confirmed
it fails when its subject breaks — a test that has never been seen to fail is
indistinguishable from one that checks nothing.
-->

- [ ] `npm test`
- [ ] `shellcheck --severity=info install.sh tests/install_test.sh templates/githooks/*` (if a shell file changed)
- [ ] Both copies updated, if this touched a file that exists at the root *and* under `templates/` (see CLAUDE.md)
