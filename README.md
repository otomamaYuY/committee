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

Through the [skills](https://github.com/vercel-labs/skills) CLI, whose
documented discovery covers this repo's `skills/<name>/SKILL.md` layout and
which installs to `.claude/skills/` for Claude Code. That is checked against
the CLI's documentation, not by running it here — if it does not work for
you, please open an issue.

This path gives you the knowledge layer only. Nothing stops an agent that
ignores it; for that, install the whole kit.

### The whole kit

```bash
git clone https://github.com/otomamaYuY/committee.git /tmp/committee
/tmp/committee/install.sh /path/to/your/repo
cd /path/to/your/repo && npm install    # or pnpm install / yarn install
```

That is the entire setup. `install.sh` points `core.hooksPath` at the
tracked `.githooks/` directory, so the hooks are live on your machine right
away.

**For everyone else, `npm install` is what activates them.** `core.hooksPath`
lives in `.git/config`, which is never committed, so a teammate's fresh clone
has the hook *files* but nothing running them. The `prepare` script in
`package.json` runs `git config --local core.hooksPath .githooks` on their
first install and wires it up — husky's idiom without the dependency. It
goes through `node` so that a checkout without a `.git` directory, such as a
Docker build, gets a warning instead of a failed install.

If your repo already had a `package.json`, the installer tells you to add
that script yourself. Skip it and the hooks run for exactly one person on
the team, silently.

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
.github/workflows/conventions.yml   # all three again, on every PR
package.json                        # three dev dependencies
```

On a pull request CI checks the commit messages, the branch name, and the
**pull request title** — which matters more than it sounds: a squash merge
puts the PR title on your default branch and discards the commits, so on a
squash workflow it is the only subject that survives.

The branch check is the *same* `pre-push` script developers run locally,
driven through git's own protocol rather than re-implemented, so the two
cannot drift apart.

## Requirements

**Node 22.12 or newer** — commitlint 21 requires it, and `package.json`
declares it — and a package manager that populates `node_modules/.bin`,
which is where the hooks resolve `commitlint` from.

npm, pnpm and Yarn Classic are each exercised by CI: the kit is installed
into a scratch repo, the dependencies are installed with that manager, and
a real commit and push are driven through the hooks
(`tests/package_manager_test.sh`).

**Yarn PnP is not supported and not tested** — it deliberately has no
`node_modules`, so `require.resolve` from the hook cannot find commitlint.
Use `nodeLinker: node-modules` if you are on PnP.

Linux and macOS are what CI and development cover. **Windows is untested.**
The hooks are POSIX `sh`, which git for Windows provides, and the `prepare`
script goes through node rather than a shell idiom — but nobody has run it
there, so treat it as unknown rather than working.

The whole kit is three dev dependencies: `@commitlint/cli`,
`@commitlint/config-conventional` and `js-yaml`.

Both hooks need those packages, and both say so plainly when they are
missing. They never run before `npm install` anyway: git only calls a hook
once `core.hooksPath` is set, and that is the `prepare` script's job.

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

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) covers the test suites and how to run
what CI runs. `main` is protected: changes go through a pull request, and
the `conventions` and `test` checks must pass. Report security issues
privately — see [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE). The four specifications this kit implements
are each licensed separately by their own maintainers (see the linked
sites); this repo only links to and implements them, it doesn't redistribute
their text.
