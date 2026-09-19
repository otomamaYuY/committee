# committee

*Where the whole team — human or Claude Code — agrees on how to commit, branch, version, and review.*

A Claude Code toolkit that adopts [Conventional Branch](https://conventionalbranch.org),
[Conventional Commits](https://www.conventionalcommits.org),
[Semantic Versioning](https://semver.org), and
[Conventional Comments](https://conventionalcomments.org) in a GitHub
repository — with Claude Code following them automatically.

## Why two layers

Instructions given to an LLM agent (a `CLAUDE.md` file, or a Skill) are
*context*, not enforced configuration — the agent usually follows them, but
there's no hard guarantee. This kit combines two layers so the conventions
hold up even when "usually" isn't good enough:

| Layer | What it does | Mechanism |
|---|---|---|
| **Knowledge** | Teaches Claude Code the conventions and *why* a given type/label fits a change (semantic judgment) | A Claude Code [Skill](https://code.claude.com/docs/en/skills) that loads on demand, not every session |
| **Enforcement** | Rejects malformed branch names/commit messages no matter what Claude (or a human) decides; computes the version number automatically | `commitlint`, `commit-check`, `semantic-release`, git hooks, GitHub Actions |

Neither layer alone is enough:

- The enforcement layer only checks **shape** (does the string match an
  allowed pattern?). It cannot tell that a bug fix was mislabeled `feat:` —
  that still passes every regex, and since `semantic-release` trusts the type
  literally, a mislabeled commit ships the wrong version number, which is
  **irreversible once released** (see
  [semver.org rule 3](https://semver.org/#spec-item-3)).
- **Conventional Comments has no standard linter at all.** The Skill is the
  only safeguard for review-comment formatting.

## What's included

```
skills/git-conventions/SKILL.md   # knowledge layer (Agent Skill)
templates/
├── git-conventions.yaml          # single source of truth: allowed types/labels + toolchain choice
├── commitlint.config.js          # reads git-conventions.yaml directly
├── .commit-check.yml             # branch-name + commit-message regex (manually synced — see comment)
├── .releaserc.json               # semantic-release config
├── Makefile                      # one entry point across npm/pnpm/yarn/pixi/nix
├── package.json.example
├── pixi.toml.example
├── flake.nix.example / .envrc.example
├── husky/commit-msg
└── github-workflows/{commit-check,release}.yml
install.sh                        # copies the above into a target repo
```

## Install

### Skill only (Agent Skills open standard)

```bash
npx skills add otomamaYuY/committee --skill git-conventions
```

### Full kit (knowledge + enforcement)

```bash
git clone https://github.com/otomamaYuY/committee.git /tmp/committee
/tmp/committee/install.sh /path/to/your/repo --toolchain npm   # or pnpm | yarn | pixi | nix
```

This copies the Skill into `.claude/skills/git-conventions/`, the config
files into your repo root, and sets `toolchain:` in
`.claude/git-conventions.yaml`. The script prints next steps (installing
dependencies, enabling the git hook) when it finishes.

The target must already exist and be a git repository — the commit hook and
the workflows do nothing outside one.

**Existing files are never overwritten.** Installing into a repo that already
has its own `Makefile`, `package.json` or `.github/workflows/release.yml`
leaves those untouched and lists them under `Skipped` at the end, so you can
merge what you need by hand. Pass `--force` to overwrite them instead, once
you have checked you don't need their current contents. The Skill itself is
kit-owned and always refreshed, so re-running the installer picks up Skill
updates without touching your configuration.

## Configuring conventions

Edit `.claude/git-conventions.yaml` after install — the type/branch/label
lists there drive both the Skill and `commitlint.config.js`. `.commit-check.yml`
can't import YAML, so it's kept in manual sync (called out in a comment in
that file); low-churn in practice since most projects stick to the default
`@commitlint/config-conventional` type set.

## Picking a toolchain

`--toolchain` selects how `Makefile` runs the underlying tools: `npm` /
`pnpm` / `yarn` run them directly; `pixi` / `nix` first activate a
provisioned environment (Node + Python) and then run the same tools inside
it. `install.sh` records the choice in two places — `toolchain:` in
`.claude/git-conventions.yaml` (documentation, read by humans and the Skill)
and the `TOOLCHAIN ?=` default at the top of `Makefile` (the value that
actually takes effect). The git hook runs `make` with no environment of its
own, so the `Makefile` default is what routes; override it per-invocation
with `make commit-lint TOOLCHAIN=pixi` if you need to.

The choice is invisible to Claude Code — it only ever runs plain
`git commit` / `git checkout -b`; the git hook and `Makefile` route to the
right runtime underneath.

## This repo dogfoods itself

This repo was scaffolded with its own `install.sh --toolchain npm`. See the
root `.claude/`, `Makefile`, and `commitlint.config.js` for a live example.

## License

MIT — see [LICENSE](LICENSE). The four specifications this kit implements
are each licensed separately by their own maintainers (see the linked
sites); this repo only links to and implements them, it doesn't redistribute
their text.
