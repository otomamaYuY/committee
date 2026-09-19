#!/usr/bin/env bash
# Installs the committee kit into a target repo.
# Usage: ./install.sh [target-dir] [--toolchain npm|pnpm|yarn|pixi|nix] [--force]

set -eu

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR=""
TOOLCHAIN="npm"
FORCE="no"

usage() {
  cat << 'USAGE'
Usage: install.sh [target-dir] [--toolchain npm|pnpm|yarn|pixi|nix] [--force]

  target-dir    Repository to install into. Must already exist and be a git
                repository. Defaults to the current directory.
  --toolchain   How the Makefile runs the underlying tools. Baked into the
                installed Makefile's TOOLCHAIN default. Default: npm.
  --force       Overwrite files that already exist in the target. Without it,
                existing files are left untouched and listed at the end.
  -h, --help    Show this message.
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
    --toolchain)
      if [ $# -lt 2 ]; then
        echo "Error: --toolchain requires a value (npm|pnpm|yarn|pixi|nix)" >&2
        exit 1
      fi
      TOOLCHAIN="$2"; shift 2 ;;
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

case "$TOOLCHAIN" in
  npm|pnpm|yarn|pixi|nix) ;;
  *) echo "Error: unknown toolchain: $TOOLCHAIN (expected npm|pnpm|yarn|pixi|nix)" >&2; exit 1 ;;
esac

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

# Resolve to an absolute path before any destructive operation, so every path
# built below is anchored to a directory that was verified to exist.
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# The kit installs git hooks and GitHub workflows, both of which are inert
# outside a repository. `.git` is a directory in a normal clone and a file in a
# worktree, hence -e rather than -d.
if [ ! -e "$TARGET_DIR/.git" ]; then
  echo "Error: not a git repository: $TARGET_DIR" >&2
  echo "       The commit hook and workflows have no effect outside one." >&2
  echo "       Run 'git init' there first, then re-run this installer." >&2
  exit 1
fi

if [ "$TARGET_DIR" = "$SRC_DIR" ]; then
  echo "Error: refusing to install the kit into its own source directory" >&2
  exit 1
fi

echo "Installing into: $TARGET_DIR (toolchain: $TOOLCHAIN, force: $FORCE)"

WRITTEN=""
SKIPPED=""
MISSING_DEPS="no"

# Copy src -> dest unless dest already exists. Returns 1 (skipped) so callers
# can gate follow-up work such as a toolchain substitution on the copy having
# actually happened. Always call inside an `if`, never bare: a bare call that
# returns 1 would abort the script under `set -e`.
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

# sed exits 0 when its pattern matches nothing, so `set -e` cannot catch a
# substitution that silently did nothing after a template's line format
# changed. Assert the result instead: a wrong toolchain surfaces later as
# "commitlint: not found" on every commit, which points at the wrong problem.
verify_line() {
  _file="$1"
  _pattern="$2"
  _what="$3"
  if ! grep -qE "$_pattern" "$_file"; then
    echo "Error: failed to set $_what in $_file" >&2
    echo "       The template's line format changed and the substitution did nothing." >&2
    exit 1
  fi
}

# --- Skill (kit-owned, always refreshed) ------------------------------------
# This is the knowledge layer shipped by the kit, not a user customization
# surface, so re-running the installer to pick up an updated Skill replaces it.
mkdir -p "$TARGET_DIR/.claude/skills"
rm -rf "$TARGET_DIR/.claude/skills/git-conventions"
cp -r "$SRC_DIR/skills/git-conventions" "$TARGET_DIR/.claude/skills/git-conventions"
WRITTEN="${WRITTEN}  .claude/skills/git-conventions/ (refreshed)"$'\n'

# --- Conventions config -----------------------------------------------------
if install_file "$SRC_DIR/templates/git-conventions.yaml" "$TARGET_DIR/.claude/git-conventions.yaml"; then
  # Substitute only the value so the trailing "# npm | pnpm | ..." comment
  # survives into the installed file.
  sed -i.bak "s/^toolchain: [a-z]*/toolchain: $TOOLCHAIN/" "$TARGET_DIR/.claude/git-conventions.yaml"
  rm -f "$TARGET_DIR/.claude/git-conventions.yaml.bak"
  verify_line "$TARGET_DIR/.claude/git-conventions.yaml" "^toolchain: $TOOLCHAIN( |\$)" "toolchain"
fi

install_file "$SRC_DIR/templates/commitlint.config.js" "$TARGET_DIR/commitlint.config.js" || true
install_file "$SRC_DIR/templates/.commit-check.yml"    "$TARGET_DIR/.commit-check.yml"    || true

if install_file "$SRC_DIR/templates/Makefile" "$TARGET_DIR/Makefile"; then
  # Bake the chosen toolchain into the Makefile's default. The git hook invokes
  # `make` with no TOOLCHAIN in its environment, so a `toolchain:` set only in
  # git-conventions.yaml would never reach the Makefile and every install would
  # silently fall back to npm.
  sed -i.bak "s/^TOOLCHAIN ?= .*/TOOLCHAIN ?= $TOOLCHAIN/" "$TARGET_DIR/Makefile"
  rm -f "$TARGET_DIR/Makefile.bak"
  verify_line "$TARGET_DIR/Makefile" "^TOOLCHAIN \\?= $TOOLCHAIN\$" "TOOLCHAIN default"
fi

# --- Git hook ---------------------------------------------------------------
mkdir -p "$TARGET_DIR/.husky"
if install_file "$SRC_DIR/templates/husky/commit-msg" "$TARGET_DIR/.husky/commit-msg"; then
  chmod +x "$TARGET_DIR/.husky/commit-msg"
fi

# --- CI ---------------------------------------------------------------------
mkdir -p "$TARGET_DIR/.github/workflows"
install_file "$SRC_DIR/templates/github-workflows/commit-check.yml" "$TARGET_DIR/.github/workflows/commit-check.yml" || true

# --- Toolchain-specific environment ----------------------------------------
case "$TOOLCHAIN" in
  pixi)
    install_file "$SRC_DIR/templates/pixi.toml.example" "$TARGET_DIR/pixi.toml" || true
    ;;
  nix)
    install_file "$SRC_DIR/templates/flake.nix.example" "$TARGET_DIR/flake.nix" || true
    install_file "$SRC_DIR/templates/.envrc.example"    "$TARGET_DIR/.envrc"    || true
    ;;
esac

# Every toolchain needs the Node dev dependencies, not just the JS ones:
# commitlint is a Node program and commitlint.config.js requires js-yaml to
# read git-conventions.yaml. pixi and nix provision Node itself and then run
# the same `npm install` inside their environment. Skipping this on those two
# paths left the commit hook failing on every commit.
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

if [ "$MISSING_DEPS" = "yes" ]; then
  cat << 'WARN'

Warning: this repo already has a package.json, so the kit's dev dependencies
  were NOT added. The commit hook needs all of these:

      @commitlint/cli  @commitlint/config-conventional  js-yaml  husky

  Add them yourself before committing, or every commit will be rejected with a
  module-resolution error that names none of this. See package.json.example in
  the kit for the versions it expects.
WARN
fi

cat << 'MSG'

Next steps:
  1. Review .claude/git-conventions.yaml (type/branch/label lists).
  2. Install dependencies:
       make deps
     This runs the right command for the toolchain baked into the Makefile —
     including inside the pixi or nix environment, which still need the Node
     packages that commitlint and commitlint.config.js depend on.
  3. Enable hooks:
       npx husky init   # if not already set up in this repo
  4. Commit the new files.

MSG
