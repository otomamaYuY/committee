#!/usr/bin/env bash
# Contract tests for install.sh.
#
# The properties pinned here all fail quietly rather than loudly if they
# regress, which is what makes them worth a test:
#   1. Arguments are validated before anything is written — the target
#      directory feeds rm -rf / mkdir / cp.
#   2. Existing files in the target repo are never overwritten without --force.
#   3. The hooks are actually wired up (core.hooksPath), and a repo that
#      already routes hooks elsewhere is not hijacked.
#   4. A real commit in a real installed repo is accepted or rejected
#      according to the type list in git-conventions.yaml.
#
# Plain bash, no test framework: the kit must be testable in a repo that has
# not installed anything yet.

set -u

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$KIT_DIR/install.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }

# ok <description> <command...> — expects the command to succeed.
ok() { desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi; }
# no <description> <command...> — expects the command to fail.
no() { desc="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi; }
# has <description> <haystack> <needle>
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" ;; esac; }

new_repo() {
  _dir="$TMP_ROOT/$1"
  rm -rf "$_dir"
  mkdir -p "$_dir"
  git -C "$_dir" init -q
  git -C "$_dir" config user.email committee-test@example.invalid
  git -C "$_dir" config user.name "committee test"
  printf '%s' "$_dir"
}

echo "== argument validation (nothing may be written before the target is validated)"

ok "--help exits 0" "$INSTALL" --help
"$INSTALL" --help >/dev/null 2>&1
if [ -e "$PWD/--help" ] || [ -e "$TMP_ROOT/--help" ]; then
  fail "--help must not create a directory named --help"
else
  pass "--help creates no directory"
fi

no "unknown option is rejected"          "$INSTALL" --bogus
no "a removed option is rejected"        "$INSTALL" "$(new_repo argv0)" --toolchain npm
no "empty target is rejected"            "$INSTALL" ""
no "nonexistent target is rejected"      "$INSTALL" "$TMP_ROOT/does-not-exist"
no "two target directories are rejected" "$INSTALL" "$(new_repo argv3)" "$(new_repo argv4)"
no "installing into the kit's own source is rejected" "$INSTALL" "$KIT_DIR"

NOT_A_REPO="$TMP_ROOT/plain-dir"
mkdir -p "$NOT_A_REPO"
no "non-git directory is rejected" "$INSTALL" "$NOT_A_REPO"
if [ -z "$(ls -A "$NOT_A_REPO")" ]; then
  pass "rejected target is left untouched"
else
  fail "wrote into a target that was then rejected"
fi

echo "== a clean install puts every file where the docs say"

FRESH="$(new_repo fresh)"
FRESH_OUT="$("$INSTALL" "$FRESH" 2>&1)"

for f in .claude/git-conventions.yaml \
         .claude/skills/git-conventions/SKILL.md \
         commitlint.config.js \
         .githooks/commit-msg \
         .github/workflows/commit-check.yml \
         package.json; do
  ok "installs $f" test -f "$FRESH/$f"
done
ok "the commit-msg hook is executable" test -x "$FRESH/.githooks/commit-msg"
ok "core.hooksPath points at the tracked hooks" \
   sh -c '[ "$(git -C "$1" config --local --get core.hooksPath)" = ".githooks" ]' _ "$FRESH"
ok "package.json declares commitlint"  grep -q '@commitlint/cli' "$FRESH/package.json"
ok "package.json declares the config"  grep -q '@commitlint/config-conventional' "$FRESH/package.json"
ok "package.json declares js-yaml"     grep -q 'js-yaml' "$FRESH/package.json"
no "no Makefile is installed"          test -e "$FRESH/Makefile"
no "no release config is installed"    test -e "$FRESH/.releaserc.json"
no "nothing depends on husky"          grep -q 'husky' "$FRESH/package.json"

echo "== no-clobber"

REPO="$(new_repo clobber)"
mkdir -p "$REPO/.github/workflows"
printf 'name: my real workflow\n' > "$REPO/.github/workflows/commit-check.yml"
printf 'module.exports = { mine: true };\n' > "$REPO/commitlint.config.js"
printf '{"name":"mine"}\n' > "$REPO/package.json"

OUT="$("$INSTALL" "$REPO" 2>&1)"

ok "pre-existing workflow survives"    grep -qx 'name: my real workflow' "$REPO/.github/workflows/commit-check.yml"
ok "pre-existing config survives"      grep -q  'mine: true'             "$REPO/commitlint.config.js"
ok "pre-existing package.json survives" grep -q '"name":"mine"'          "$REPO/package.json"
ok "files absent from the target are still installed" test -f "$REPO/.githooks/commit-msg"
has "skipped files are reported"       "$OUT" "Skipped (already present"
has "the report says how to override"  "$OUT" "Re-run with --force"
has "a pre-existing package.json is warned about" "$OUT" "NOT added"
has "the warning names what the hook needs"       "$OUT" "@commitlint/cli"

"$INSTALL" "$REPO" --force >/dev/null 2>&1
ok "--force overwrites an existing file" grep -q 'git-conventions' "$REPO/commitlint.config.js"

echo "== a repo that already routes hooks elsewhere is not hijacked"

HOOKED="$(new_repo hooked)"
git -C "$HOOKED" config --local core.hooksPath .husky/_
HOOKED_OUT="$("$INSTALL" "$HOOKED" 2>&1)"
ok "the existing hooksPath is left alone" \
   sh -c '[ "$(git -C "$1" config --local --get core.hooksPath)" = ".husky/_" ]' _ "$HOOKED"
has "the collision is reported"        "$HOOKED_OUT" "already routes git hooks"
has "the report says how to switch"    "$HOOKED_OUT" "core.hooksPath .githooks"

echo "== the hook says what is missing when commitlint is absent"

BARE="$(new_repo bare)"
"$INSTALL" "$BARE" >/dev/null 2>&1
printf 'feat: x\n' > "$BARE/msg"
# git runs hooks with the repo root as cwd; npx resolves node_modules from
# there, so running the hook from anywhere else would find the wrong tree.
BARE_OUT="$(cd "$BARE" && ./.githooks/commit-msg msg 2>&1 || true)"
has "a missing commitlint names itself" "$BARE_OUT" "commitlint is not installed"
has "and says how to fix it"            "$BARE_OUT" "npm install"

echo "== end to end: a real commit in a real installed repo"

E2E="$(new_repo e2e)"
"$INSTALL" "$E2E" >/dev/null 2>&1
# Borrow the kit's own node_modules rather than reinstalling: this exercises
# the installed hook, not npm.
ln -s "$KIT_DIR/node_modules" "$E2E/node_modules"
echo hello > "$E2E/file.txt"
git -C "$E2E" add -A

if git -C "$E2E" commit -q -m "nope, not conventional" >/dev/null 2>&1; then
  fail "a non-conventional commit message is rejected"
else
  pass "a non-conventional commit message is rejected"
fi

if git -C "$E2E" commit -q -m "wip: a type that is not on the list" >/dev/null 2>&1; then
  fail "a type absent from git-conventions.yaml is rejected"
else
  pass "a type absent from git-conventions.yaml is rejected"
fi

if git -C "$E2E" commit -q -m "feat: a type that is on the list"; then
  pass "a conventional commit message is accepted"
else
  fail "a conventional commit message is accepted"
fi

# Prove the yaml is the source of truth, not a hardcoded list: add a type and
# the same message that was just rejected must now pass.
# Insert into the commit_types block, not at the end of the file (where the
# last block is comment_labels).
sed -i.bak 's/^commit_types:$/commit_types:\n  - wip/' "$E2E/.claude/git-conventions.yaml"
rm -f "$E2E/.claude/git-conventions.yaml.bak"
echo again > "$E2E/file.txt"
git -C "$E2E" add -A
if git -C "$E2E" commit -q -m "wip: now allowed by the yaml"; then
  pass "adding a type to git-conventions.yaml changes what the hook accepts"
else
  fail "adding a type to git-conventions.yaml changes what the hook accepts"
fi

echo
echo "install_test: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
