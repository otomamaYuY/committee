#!/usr/bin/env bash
# Checks the README's claim that any package manager which populates
# node_modules/.bin works, by installing the kit into a scratch repo,
# installing the dev dependencies with the manager under test, and driving a
# real commit and a real push through the installed hooks.
#
# Usage: package_manager_test.sh [npm|pnpm|yarn|yarn-pnp]
#
# npm runs locally; pnpm and yarn run in CI, where corepack provides them.
# The claim is only worth making for managers this has actually exercised.

set -u

PM="${1:-npm}"

# yarn-pnp is yarn with node_modules switched off — a different install
# shape, not a different manager, so the binary to probe for is still yarn.
case "$PM" in
  yarn-pnp) PM_BIN=yarn ;;
  *)        PM_BIN="$PM" ;;
esac
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=tests/lib.sh
. "$KIT_DIR/tests/lib.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

command -v "$PM_BIN" >/dev/null 2>&1 || {
  echo "package_manager_test: $PM_BIN is not installed — nothing verified" >&2
  exit 127
}

echo "== $PM: $("$PM_BIN" --version 2>/dev/null)"

REPO="$TMP_ROOT/repo"
new_repo "$REPO"

"$KIT_DIR/install.sh" "$REPO" >/dev/null 2>&1 || {
  echo "package_manager_test: install.sh failed" >&2
  exit 1
}

# No --frozen-lockfile anywhere: the point is a fresh adopter who has just
# run install.sh and has no lockfile yet.
( cd "$REPO" && case "$PM" in
    npm)  npm install --no-audit --no-fund ;;
    pnpm) pnpm install ;;
    yarn) yarn install ;;
    yarn-pnp)
      yarn set version berry
      yarn config set nodeLinker pnp
      # Yarn 4 quarantines very recently published versions. That is its
      # supply-chain policy, not something this kit is testing.
      yarn config set npmMinimalAgeGate 0 2>/dev/null || true
      yarn install
      ;;
    *)    echo "unknown package manager: $PM" >&2; exit 2 ;;
  esac ) >/dev/null 2>&1 || fail "$PM install succeeded"

# PnP deliberately has no node_modules; the hooks branch to `yarn` there,
# which is the whole point of covering it.
if [ "$PM" = yarn-pnp ]; then
  ok "PnP produced a .pnp.cjs" test -f "$REPO/.pnp.cjs"
  no "PnP produced no node_modules" test -d "$REPO/node_modules"
  ok "yarn resolves commitlint under PnP" \
     in_repo "$REPO" yarn commitlint --version
else
  ok "$PM populates node_modules/.bin/commitlint" test -x "$REPO/node_modules/.bin/commitlint"
  ok "the hook's own resolution finds commitlint" \
     in_repo "$REPO" node -e 'require.resolve("@commitlint/cli")'
fi

# prepare runs on install for all three managers; without it the hooks are
# inert no matter which one was used.
ok "the prepare script wired core.hooksPath" test "$(hooks_path "$REPO")" = ".githooks"

echo hello > "$REPO/file.txt"
git -C "$REPO" add -A

no "a non-conventional commit is rejected" \
   git -C "$REPO" commit -q -m "nope, not conventional"
no "a type absent from the yaml is rejected" \
   git -C "$REPO" commit -q -m "wip: not on the list"
ok "a conventional commit is accepted" \
   git -C "$REPO" commit -q -m "feat: something conventional"

REMOTE="$TMP_ROOT/remote.git"
git init -q --bare "$REMOTE"
git -C "$REPO" remote add origin "$REMOTE"

git -C "$REPO" checkout -q -b Not_Conventional
no "a malformed branch name is refused on push" git -C "$REPO" push -q origin Not_Conventional
git -C "$REPO" checkout -q -b feature/properly-named
ok "a conventional branch name pushes"           git -C "$REPO" push -q origin feature/properly-named

summary "package_manager_test ($PM)"
