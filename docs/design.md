# Why the kit is shaped this way

The reasoning behind the two layers, the single config file, and the things
this kit deliberately does not do. [README](../README.md) is the short
version.

## Why two layers

You can tell an agent the conventions. A `CLAUDE.md`, an `AGENTS.md`, a
Skill — all of it is *context*: the agent usually complies, and "usually" is
not a guarantee you can put in a changelog. You can also just add a linter,
but a linter cannot tell that a bug fix was labelled `feat:`.

So the kit ships both, and neither is decoration:

| Layer | What it does | How |
|---|---|---|
| **Knowledge** | Explains the conventions and *why* a given type fits a change — the judgment a regex cannot make | A Claude Code [Skill](https://code.claude.com/docs/en/skills), and an `AGENTS.md` for Codex and other agents |
| **Enforcement** | Rejects a malformed branch or commit regardless of what any agent or human decided | `commitlint`, two git hooks, one GitHub Actions workflow |

The enforcement layer only checks **shape**. `feat: fix the null check`
passes every rule in this repo, and the type is what a reader, a changelog
and any release tooling use to understand what changed — so a mislabelled
commit misstates the change to everyone downstream. That judgment is what
the knowledge layer is for.

And [Conventional Comments](https://conventionalcomments.org) has no linter
anywhere. For review comments, the knowledge layer is the only thing there
is.

## One file decides everything

`.claude/git-conventions.yaml` holds the allowed commit types, branch
prefixes and review labels. Nothing else restates them:

```
.claude/git-conventions.yaml
        │
        ├──► .claude/skills/git-conventions/  the Skill quotes it to Claude Code
        ├──► AGENTS.md                        points Codex at it
        ├──► commitlint.config.js             loads commit_types into type-enum
        └──► .githooks/pre-push               parses branch_types out of it
```

Add a type there and it is allowed everywhere at once — locally and in CI,
with no second list to remember and no way for the hook and the pipeline to
disagree.

## What this kit does not do

- **It does not automate releases.** SemVer is explained to the agent, not
  automated by a pipeline. Adding `semantic-release` yourself is a handful
  of lines; having it in every adopting repo meant ~480 transitive
  dependencies against this kit's 95, and a workflow holding a
  `contents: write` token — a poor default for a conventions kit.
- **It does not enforce Conventional Comments.** No linter for it exists.
  The knowledge layer is the whole story there.
- **It does not manage your Node environment.** If you use pixi, nix or
  anything else, you have already solved that; the kit does not model it.

## This repo dogfoods itself

Scaffolded with its own `install.sh`. The root `.claude/`, `.githooks/`,
`AGENTS.md` and `commitlint.config.js` are the live example — and
`tests/drift_test.js` fails if any of them drifts from `templates/`, so the
example cannot quietly stop matching what you would install.
