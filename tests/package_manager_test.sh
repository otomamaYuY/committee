#!/usr/bin/env bash
# Checks the README's claim that any package manager which populates
# node_modules/.bin works, by installing the kit into a scratch repo,
# installing the dev dependencies with the manager under test, and driving a
# real commit and a real push through the installed hooks.
#
# Usage: package_manager_test.sh [npm|pnpm|yarn]
#
# npm runs locally; pnpm and yarn run in CI, where corepack provides them.
# The claim is only worth making for managers this has actually exercised.

set -u

PM="${1:-npm}"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }
ok()   { desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi; }
no()   { desc="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi; }

command -v "$PM" >/dev/null 2>&1 || {
  echo "package_manager_test: $PM is not installed — nothing verified" >&2
  exit 127
}

echo "== $PM: $("$PM" --version 2>/dev/null)"

REPO="$TMP_ROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email committee-test@example.invalid
git -C "$REPO" config user.name "committee test"

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
    *)    echo "unknown package manager: $PM" >&2; exit 2 ;;
  esac ) >/dev/null 2>&1 || fail "$PM install succeeded"

# This is the mechanism the README names, and what both hooks depend on.
ok "$PM populates node_modules/.bin/commitlint" test -x "$REPO/node_modules/.bin/commitlint"
ok "the hook's own resolution finds commitlint" \
   sh -c 'cd "$1" && node -e "require.resolve(\"@commitlint/cli\")"' _ "$REPO"

# prepare runs on install for all three managers; without it the hooks are
# inert no matter which one was used.
ok "the prepare script wired core.hooksPath" \
   sh -c '[ "$(git -C "$1" config --local --get core.hooksPath)" = ".githooks" ]' _ "$REPO"

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

echo
echo "package_manager_test ($PM): $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
