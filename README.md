# committee

*Where the whole team — human or coding agent — agrees on how to commit,
branch, version and review.*

A small kit that makes a GitHub repository follow
[Conventional Commits](https://www.conventionalcommits.org),
[Conventional Branch](https://conventionalbranch.org),
[Semantic Versioning](https://semver.org) and
[Conventional Comments](https://conventionalcomments.org) — and keeps
following them when most of the commits are being written by Claude Code or
Codex.

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

## Install

### Just the Skill

```bash
npx skills add otomamaYuY/committee --skill git-conventions
```

### The whole kit

```bash
git clone https://github.com/otomamaYuY/committee.git /tmp/committee
/tmp/committee/install.sh /path/to/your/repo
cd /path/to/your/repo && npm install    # or pnpm install / yarn install
```

That is the entire setup. `install.sh` also points `core.hooksPath` at the
tracked `.githooks/` directory, so the hooks are live immediately — there is
no separate init step to forget and no hook manager to depend on.

The target must already exist and be a git repository; the hooks and the
workflow do nothing outside one.

**Existing files are never overwritten.** Install into a repo that already
has its own `commitlint.config.js`, `package.json` or `AGENTS.md` and those
are left untouched, listed under `Skipped`, and — where it matters, like a
skipped `package.json` whose dependencies the hook needs — called out in a
warning naming exactly what to add. Pass `--force` to overwrite instead. A
repo that already routes hooks elsewhere (husky, say) is detected and left
alone rather than hijacked.

The Skill is kit-owned and always refreshed, so re-running the installer
picks up Skill updates without touching your configuration.

## What you get

```
.claude/
  git-conventions.yaml              # the one file above
  skills/git-conventions/SKILL.md   # knowledge layer, Claude Code
AGENTS.md                           # knowledge layer, Codex and others
commitlint.config.js
.githooks/
  commit-msg                        # Conventional Commits, every commit
  pre-push                          # Conventional Branch, every push
.github/workflows/conventions.yml   # both checks again, on every PR
package.json                        # three dev dependencies
```

CI runs the *same* `pre-push` script developers run locally, rather than a
re-implementation of it, so the two cannot drift apart.

## Requirements

Node, and one of npm, pnpm or yarn. The hooks resolve `commitlint` from
`node_modules/.bin`, which all three populate. The whole kit is three dev
dependencies: `@commitlint/cli`, `@commitlint/config-conventional` and
`js-yaml`.

The `pre-push` hook parses the YAML with `sed`, so branch checking works in
a fresh clone before anything has been installed.

## What this kit does not do

- **It does not automate releases.** SemVer is explained to the agent, not
  automated by a pipeline. Adding `semantic-release` yourself is a handful
  of lines; having it in every adopting repo cost 502 of 565 transitive
  dependencies and shipped a workflow holding a `contents: write` token,
  which is a poor default for a conventions kit.
- **It does not enforce Conventional Comments.** No linter for it exists.
  The knowledge layer is the whole story there.
- **It does not manage your Node environment.** If you use pixi, nix or
  anything else, you have already solved that; the kit does not model it.

## This repo dogfoods itself

Scaffolded with its own `install.sh`. The root `.claude/`, `.githooks/`,
`AGENTS.md` and `commitlint.config.js` are the live example — and
`tests/drift_test.js` fails if any of them drifts from `templates/`, so the
example cannot quietly stop matching what you would install.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the test suites.

## License

MIT — see [LICENSE](LICENSE). The four specifications this kit implements
are each licensed separately by their own maintainers (see the linked
sites); this repo only links to and implements them, it doesn't redistribute
their text.
