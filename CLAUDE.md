# committee — working in this repo

This repo *is* a git-conventions kit, so it holds itself to what it ships.
`AGENTS.md` and `.claude/skills/git-conventions/` state the conventions
themselves; this file is about changing the kit.

## Several files exist twice — change both

`templates/` is what adopters receive. The repo root is what this repo runs
on itself. They are byte-identical by design:

| Root | Template |
|---|---|
| `AGENTS.md` | `templates/AGENTS.md` |
| `commitlint.config.js` | `templates/commitlint.config.js` |
| `.githooks/commit-msg` | `templates/githooks/commit-msg` |
| `.githooks/pre-push` | `templates/githooks/pre-push` |
| `.github/workflows/conventions.yml` | `templates/github-workflows/conventions.yml` |
| `.claude/skills/git-conventions/SKILL.md` | `skills/git-conventions/SKILL.md` |

Editing only the root leaves every test green here while shipping the
unfixed file to every adopting repo. `npm test` is what catches it.

`.claude/git-conventions.yaml` is the exception: it is the adopter's
customization surface, so this repo's copy may differ from the template.

`.github/workflows/test.yml` has no template — it tests the kit and is not
shipped.

## Run the tests

```bash
npm test
```

`tests/install_test.sh` installs into throwaway repos and drives real
`git commit` and `git push` calls; `tests/drift_test.js` checks the pairs
above and the workflows. Both are plain bash/node — do not add a test
framework for them.

A test here is only worth having if it fails when its subject breaks.
Before claiming one works, break the thing on purpose and watch it go red.

## Keep the single source of truth single

`.claude/git-conventions.yaml` is the only place a commit type, branch
prefix or review label may be written down. The Skill, `AGENTS.md`,
`commitlint.config.js` and `.githooks/pre-push` all read it. If you find
yourself adding a second list anywhere, that is the bug — the manual-sync
version of this design is what the kit replaced.

`pre-push` parses the YAML with `sed`, deliberately: it has to work in a
fresh clone before `npm install` has ever run. Keep it dependency-free.

## Do not weaken the enforcement to get a change through

If a hook rejects you, fix the cause. Never `--no-verify`, never edit a hook
to make your own commit pass. A type you genuinely need goes in
`.claude/git-conventions.yaml`.

## Scope

The kit stays small on purpose. It does not automate releases, does not
manage Node environments, and depends on three packages. Adding a dependency
or a new installed file needs a reason that survives the question "does
every adopting repo need this?"
