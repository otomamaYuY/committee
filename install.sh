#!/usr/bin/env bash
# Installs the committee kit into a target repo.
# Usage: ./install.sh [target-dir] [--toolchain npm|pnpm|yarn|pixi|nix]

set -eu

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="."
TOOLCHAIN="npm"

while [ $# -gt 0 ]; do
  case "$1" in
    --toolchain) TOOLCHAIN="$2"; shift 2 ;;
    *) TARGET_DIR="$1"; shift ;;
  esac
done

case "$TOOLCHAIN" in
  npm|pnpm|yarn|pixi|nix) ;;
  *) echo "Unknown toolchain: $TOOLCHAIN (expected npm|pnpm|yarn|pixi|nix)" >&2; exit 1 ;;
esac

echo "Installing into: $TARGET_DIR (toolchain: $TOOLCHAIN)"

mkdir -p "$TARGET_DIR/.claude/skills"
rm -rf "$TARGET_DIR/.claude/skills/git-conventions"
cp -r "$SRC_DIR/skills/git-conventions" "$TARGET_DIR/.claude/skills/git-conventions"

# Never clobber an existing git-conventions.yaml — it's the user's own
# customization surface (type/branch/label lists). Only seed it on first
# install; re-running install.sh to pick up enforcement-layer updates must
# not silently wipe project-specific edits.
if [ -f "$TARGET_DIR/.claude/git-conventions.yaml" ]; then
  echo "Skipping .claude/git-conventions.yaml (already exists — not overwriting your customizations)"
else
  cp "$SRC_DIR/templates/git-conventions.yaml" "$TARGET_DIR/.claude/git-conventions.yaml"
  sed -i.bak "s/^toolchain: .*/toolchain: $TOOLCHAIN/" "$TARGET_DIR/.claude/git-conventions.yaml"
  rm -f "$TARGET_DIR/.claude/git-conventions.yaml.bak"
fi

cp "$SRC_DIR/templates/commitlint.config.js" "$TARGET_DIR/commitlint.config.js"
cp "$SRC_DIR/templates/.commit-check.yml" "$TARGET_DIR/.commit-check.yml"
cp "$SRC_DIR/templates/.releaserc.json" "$TARGET_DIR/.releaserc.json"
cp "$SRC_DIR/templates/Makefile" "$TARGET_DIR/Makefile"
# Bake the chosen toolchain into the Makefile's default. The git hook invokes
# `make` with no TOOLCHAIN in its environment, so a `toolchain:` set only in
# git-conventions.yaml would never reach the Makefile and every install would
# silently fall back to npm.
sed -i.bak "s/^TOOLCHAIN ?= .*/TOOLCHAIN ?= $TOOLCHAIN/" "$TARGET_DIR/Makefile"
rm -f "$TARGET_DIR/Makefile.bak"

mkdir -p "$TARGET_DIR/.husky"
cp "$SRC_DIR/templates/husky/commit-msg" "$TARGET_DIR/.husky/commit-msg"
chmod +x "$TARGET_DIR/.husky/commit-msg"

mkdir -p "$TARGET_DIR/.github/workflows"
cp "$SRC_DIR/templates/github-workflows/commit-check.yml" "$TARGET_DIR/.github/workflows/commit-check.yml"
cp "$SRC_DIR/templates/github-workflows/release.yml" "$TARGET_DIR/.github/workflows/release.yml"

case "$TOOLCHAIN" in
  pixi)
    cp "$SRC_DIR/templates/pixi.toml.example" "$TARGET_DIR/pixi.toml"
    ;;
  nix)
    cp "$SRC_DIR/templates/flake.nix.example" "$TARGET_DIR/flake.nix"
    cp "$SRC_DIR/templates/.envrc.example" "$TARGET_DIR/.envrc"
    ;;
  npm|pnpm|yarn)
    if [ ! -f "$TARGET_DIR/package.json" ]; then
      cp "$SRC_DIR/templates/package.json.example" "$TARGET_DIR/package.json"
    fi
    ;;
esac

cat << 'MSG'

Done. Next steps:
  1. Review .claude/git-conventions.yaml (type/branch/label lists).
  2. Install dependencies for your toolchain:
       npm/pnpm/yarn : npm install   (or pnpm/yarn install)
       pixi          : pixi install
       nix           : direnv allow   (or: nix develop)
  3. Enable hooks:
       npx husky init   # if not already set up in this repo
  4. Commit the new files.

MSG
