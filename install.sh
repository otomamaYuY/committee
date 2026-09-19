#!/usr/bin/env bash
# Installs the committee kit into a target repo.
# Usage: ./install.sh [target-dir] [--force]

set -eu

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""
FORCE="no"

usage() {
  cat << 'USAGE'
Usage: install.sh [target-dir] [--force]

  target-dir    Repository to install into. Must already exist and be a git
                repository. Defaults to the current directory.
  --force       Overwrite files that already exist in the target. Without it,
                existing files are left untouched and listed at the end.
  -h, --help    Show this message.

The kit needs Node. Any of npm, pnpm or yarn can install its dev
dependencies; the hook resolves commitlint from node_modules/.bin either way.
USAGE
}

# Parse arguments strictly. An unrecognized flag must never fall through to
# TARGET_DIR: that value feeds rm -rf / mkdir / cp below, so `install.sh
# --help` silently installing into a directory named "--help" — or an unset
# shell variable expanding to "" and targeting the filesystem root — has to be
# rejected here rather than acted on.
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage; exit 0 ;;
    --force)
      FORCE="yes"; shift ;;
    -*)
      echo "Error: unknown option: $1" >&2
      echo "Run 'install.sh --help' for usage." >&2
      exit 1 ;;
    *)
      if [ -n "$TARGET_DIR" ]; then
        echo "Error: more than one target directory given ('$TARGET_DIR' and '$1')" >&2
        exit 1
      fi
      if [ -z "$1" ]; then
        echo "Error: target directory is empty" >&2
        exit 1
      fi
      TARGET_DIR="$1"; shift ;;
  esac
done

[ -n "$TARGET_DIR" ] || TARGET_DIR="."

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

# Resolve to an absolute path before any destructive operation, so every path
# built below is anchored to a directory that was verified to exist.
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# The kit installs git hooks and a GitHub workflow, both of which are inert
# outside a repository. `.git` is a directory in a normal clone and a file in a
# worktree, hence -e rather than -d.
if [ ! -e "$TARGET_DIR/.git" ]; then
  echo "Error: not a git repository: $TARGET_DIR" >&2
  echo "       The hooks and workflow have no effect outside one." >&2
  echo "       Run 'git init' there first, then re-run this installer." >&2
  exit 1
fi

if [ "$TARGET_DIR" = "$SRC_DIR" ]; then
  echo "Error: refusing to install the kit into its own source directory" >&2
  exit 1
fi

echo "Installing into: $TARGET_DIR (force: $FORCE)"

WRITTEN=""
SKIPPED=""
MISSING_DEPS="no"
MISSING_AGENTS="no"
HOOKS_PATH_NOTE=""

# Copy src -> dest unless dest already exists. Returns 1 (skipped) so callers
# can gate follow-up work on the copy having actually happened. Always call
# inside an `if` or with `|| true`, never bare: a bare call that returns 1
# would abort the script under `set -e`.
install_file() {
  _src="$1"
  _dest="$2"
  if [ -e "$_dest" ] && [ "$FORCE" != "yes" ]; then
    SKIPPED="${SKIPPED}  ${_dest#"$TARGET_DIR"/}"$'\n'
    return 1
  fi
  # An `install_file ... || true` caller suppresses `set -e` for this body, so
  # a failed copy would otherwise be reported as written. Check it explicitly.
  if ! cp "$_src" "$_dest"; then
    echo "Error: failed to copy $_src -> $_dest" >&2
    exit 1
  fi
  WRITTEN="${WRITTEN}  ${_dest#"$TARGET_DIR"/}"$'\n'
  return 0
}

# --- Skill (kit-owned, always refreshed) ------------------------------------
# This is the knowledge layer shipped by the kit, not a user customization
# surface, so re-running the installer to pick up an updated Skill replaces it.
mkdir -p "$TARGET_DIR/.claude/skills"
rm -rf "$TARGET_DIR/.claude/skills/git-conventions"
cp -r "$SRC_DIR/skills/git-conventions" "$TARGET_DIR/.claude/skills/git-conventions"
WRITTEN="${WRITTEN}  .claude/skills/git-conventions/ (refreshed)"$'\n'

# --- Conventions config -----------------------------------------------------
install_file "$SRC_DIR/templates/git-conventions.yaml" "$TARGET_DIR/.claude/git-conventions.yaml" || true
install_file "$SRC_DIR/templates/commitlint.config.js" "$TARGET_DIR/commitlint.config.js" || true

# The knowledge layer for agents that read AGENTS.md (Codex and others).
# Claude Code gets the same content as a Skill, above. Plenty of repos
# already have an AGENTS.md, so a skipped one is called out at the end
# rather than left to be discovered later.
if ! install_file "$SRC_DIR/templates/AGENTS.md" "$TARGET_DIR/AGENTS.md"; then
  MISSING_AGENTS="yes"
fi

# --- Git hooks --------------------------------------------------------------
mkdir -p "$TARGET_DIR/.githooks"
for _hook in commit-msg pre-push; do
  if install_file "$SRC_DIR/templates/githooks/$_hook" "$TARGET_DIR/.githooks/$_hook"; then
    chmod +x "$TARGET_DIR/.githooks/$_hook"
  fi
done

# Point git at the hooks. Tracked hooks plus core.hooksPath is all that is
# needed here — no hook-manager dependency, and no manual init step that a
# user can skip and be left with silently inert hooks.
#
# A repo that already routes hooks elsewhere (husky sets .husky/_) is left
# alone: silently repointing it would disable every hook that repo already
# relies on.
EXISTING_HOOKS_PATH="$(git -C "$TARGET_DIR" config --local --get core.hooksPath || true)"
if [ -z "$EXISTING_HOOKS_PATH" ] || [ "$EXISTING_HOOKS_PATH" = ".githooks" ]; then
  git -C "$TARGET_DIR" config --local core.hooksPath .githooks
  WRITTEN="${WRITTEN}  (git config core.hooksPath = .githooks)"$'\n'
else
  HOOKS_PATH_NOTE="$EXISTING_HOOKS_PATH"
fi

# --- CI ---------------------------------------------------------------------
mkdir -p "$TARGET_DIR/.github/workflows"
install_file "$SRC_DIR/templates/github-workflows/conventions.yml" "$TARGET_DIR/.github/workflows/conventions.yml" || true

# --- Dev dependencies -------------------------------------------------------
# commitlint is a Node program and commitlint.config.js requires js-yaml to
# read git-conventions.yaml, so the target needs both declared somewhere.
if ! install_file "$SRC_DIR/templates/package.json.example" "$TARGET_DIR/package.json"; then
  MISSING_DEPS="yes"
fi

# --- Report -----------------------------------------------------------------
echo
echo "Written:"
printf '%s' "$WRITTEN"

if [ -n "$SKIPPED" ]; then
  echo
  echo "Skipped (already present — left untouched):"
  printf '%s' "$SKIPPED"
  echo
  echo "  Re-run with --force to overwrite these, after checking you do not"
  echo "  need their current contents."
fi

if [ -n "$HOOKS_PATH_NOTE" ]; then
  cat << WARN

Warning: this repo already routes git hooks to '$HOOKS_PATH_NOTE', so
  core.hooksPath was left alone and .githooks/commit-msg will NOT run.
  Either call it from your existing hook, or move to the kit's hooks with:

      git config --local core.hooksPath .githooks
WARN
fi

if [ "$MISSING_AGENTS" = "yes" ]; then
  cat << 'WARN'

Warning: this repo already has an AGENTS.md, so the conventions section was
  NOT added. Agents that read AGENTS.md (Codex and others) will not be told
  about the conventions, and will hit the hooks instead of following them.
  Copy templates/AGENTS.md from the kit into a section of your own file.
WARN
fi

if [ "$MISSING_DEPS" = "yes" ]; then
  cat << 'WARN'

Warning: this repo already has a package.json, so two things were NOT added.

  1. The dev dependencies the hooks need:

         @commitlint/cli  @commitlint/config-conventional  js-yaml

     Without them every commit is rejected with a module-resolution error
     that names none of this, and the PR workflow fails the same way.

  2. A prepare script, which is what wires the hooks up for everyone else:

         "scripts": { "prepare": "git config --local core.hooksPath .githooks" }

     core.hooksPath lives in .git/config and is never committed, so without
     this every teammate and every fresh clone has the hook FILES but no
     hooks running. Add it, or each of them must run that command by hand.

  See package.json.example in the kit for both.
WARN
fi

cat << 'MSG'

Next steps:
  1. Review .claude/git-conventions.yaml (type/branch/label lists).
  2. Install the dev dependencies:
       npm install      (or: pnpm install / yarn install)
  3. Commit the new files.

Hooks are active here now. For everyone else they are activated by the
prepare script in package.json, which runs on their first `npm install` —
core.hooksPath lives in .git/config and is never committed, so a fresh
clone has the hook files but nothing running them until then.

MSG
