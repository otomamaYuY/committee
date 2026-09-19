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
| **Enforcement** | Rejects malformed branch names/commit messages no matter what Claude (or a human) decides | `commitlint`, `commit-check`, git hooks, GitHub Actions |

Neither layer alone is enough:

- The enforcement layer only checks **shape** (does the string match an
  allowed pattern?). It cannot tell that a bug fix was mislabeled `feat:` —
  that still passes every regex. The type is what a reader, a changelog
  generator or a release tool uses to decide the next version, so a
  mislabeled commit misstates the change to everyone downstream (see
  [semver.org rule 3](https://semver.org/#spec-item-3)).
- **Conventional Comments has no standard linter at all.** The Skill is the
  only safeguard for review-comment formatting.

## What's included

```
skills/git-conventions/SKILL.md   # knowledge layer (Agent Skill)
templates/
├── git-conventions.yaml          # single source of truth: allowed types/labels
├── commitlint.config.js          # reads git-conventions.yaml directly
├── .commit-check.yml             # branch-name + commit-message regex (manually synced — see comment)
├── package.json.example
├── githooks/commit-msg
└── github-workflows/commit-check.yml
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
/tmp/committee/install.sh /path/to/your/repo
```

This copies the Skill into `.claude/skills/git-conventions/`, the config
files into your repo root, and points `core.hooksPath` at the tracked
`.githooks/` directory — so the hook is live with no separate init step to
forget. The script prints next steps when it finishes.

The target must already exist and be a git repository — the commit hook and
the workflows do nothing outside one.

**Existing files are never overwritten.** Installing into a repo that already
has its own `commitlint.config.js`, `package.json` or workflow of the same name
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

## This repo dogfoods itself

This repo was scaffolded with its own `install.sh`. See the root `.claude/`,
`.githooks/`, and `commitlint.config.js` for a live example — and
`tests/drift_test.js`, which fails if those copies ever drift from
`templates/`.

## License

MIT — see [LICENSE](LICENSE). The four specifications this kit implements
are each licensed separately by their own maintainers (see the linked
sites); this repo only links to and implements them, it doesn't redistribute
their text.
