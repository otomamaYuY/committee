#!/usr/bin/env bash
# Contract tests for install.sh.
#
# These pin the three behaviours that a pre-merge review found broken, each of
# which fails silently rather than loudly if it regresses:
#   1. Existing files in the target repo are never overwritten without --force.
#   2. Arguments are validated before anything is written (the target directory
#      feeds rm -rf / mkdir / cp).
#   3. The toolchain substitutions actually took effect — sed exits 0 when it
#      matches nothing.
# Plus a happy-path check that the commit-type list in git-conventions.yaml is
# really what commitlint enforces.
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

# A throwaway git repo to install into.
new_repo() {
  _dir="$TMP_ROOT/$1"
  rm -rf "$_dir"
  mkdir -p "$_dir"
  git -C "$_dir" init -q
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
no "empty target is rejected"            "$INSTALL" ""
no "nonexistent target is rejected"      "$INSTALL" "$TMP_ROOT/does-not-exist"
no "--toolchain without a value is rejected" "$INSTALL" "$(new_repo argv1)" --toolchain
no "unknown toolchain is rejected"       "$INSTALL" "$(new_repo argv2)" --toolchain bogus
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

echo "== no-clobber"

REPO="$(new_repo clobber)"
mkdir -p "$REPO/.github/workflows"
printf 'MY REAL MAKEFILE\n' > "$REPO/Makefile"
printf 'my: real release\n' > "$REPO/.github/workflows/release.yml"
printf '{"name":"mine"}\n'  > "$REPO/package.json"

OUT="$("$INSTALL" "$REPO" --toolchain npm 2>&1)"

ok "pre-existing Makefile survives"     grep -qx 'MY REAL MAKEFILE' "$REPO/Makefile"
ok "pre-existing release.yml survives"  grep -qx 'my: real release' "$REPO/.github/workflows/release.yml"
ok "pre-existing package.json survives" grep -q  '"name":"mine"'    "$REPO/package.json"
ok "files absent from the target are installed" test -f "$REPO/commitlint.config.js"
ok "the Skill is installed"             test -f "$REPO/.claude/skills/git-conventions/SKILL.md"

case "$OUT" in
  *"Skipped (already present"*) pass "skipped files are reported" ;;
  *)                            fail "skipped files are not reported" ;;
esac
case "$OUT" in
  *"Re-run with --force"*) pass "the report says how to override" ;;
  *)                       fail "the report does not mention --force" ;;
esac

"$INSTALL" "$REPO" --toolchain npm --force >/dev/null 2>&1
ok "--force overwrites an existing file" grep -qx 'TOOLCHAIN ?= npm' "$REPO/Makefile"

echo "== toolchain substitution is verified, not assumed"

for tc in npm pnpm yarn pixi nix; do
  R="$(new_repo "tc-$tc")"
  if "$INSTALL" "$R" --toolchain "$tc" >/dev/null 2>&1; then
    ok "--toolchain $tc bakes the Makefile default" grep -qx "TOOLCHAIN ?= $tc" "$R/Makefile"
    ok "--toolchain $tc records the choice in git-conventions.yaml" \
       grep -qE "^toolchain: $tc( |\$)" "$R/.claude/git-conventions.yaml"
  else
    fail "--toolchain $tc install failed"
  fi
done

ok "git-conventions.yaml keeps its option-list comment" \
   grep -q '# npm | pnpm' "$TMP_ROOT/tc-pixi/.claude/git-conventions.yaml"

# commitlint is a Node program and commitlint.config.js requires js-yaml, so
# the JS dependencies are needed regardless of how Node itself is provisioned.
# pixi and nix used to skip them, leaving the hook failing on every commit.
echo "== every toolchain gets the Node dev dependencies"

for tc in npm pnpm yarn pixi nix; do
  R="$TMP_ROOT/tc-$tc"
  ok "--toolchain $tc installs a package.json" test -f "$R/package.json"
  for dep in @commitlint/cli @commitlint/config-conventional js-yaml husky; do
    ok "--toolchain $tc declares $dep" grep -q "\"$dep\"" "$R/package.json"
  done
  ok "--toolchain $tc defines an install command for 'make deps'" \
     grep -qE "^ *DEPS := .+" "$R/Makefile"
done

ok "pixi runs npm install inside its environment" \
   grep -q 'DEPS := pixi install && pixi run npm install' "$TMP_ROOT/tc-pixi/Makefile"
ok "nix runs npm install inside its environment" \
   grep -q 'DEPS := nix develop --command npm install' "$TMP_ROOT/tc-nix/Makefile"

echo "== a target that already has a package.json is warned, not left silent"

WARN_REPO="$(new_repo prewarn)"
printf '{"name":"mine"}\n' > "$WARN_REPO/package.json"
WARN_OUT="$("$INSTALL" "$WARN_REPO" --toolchain npm 2>&1)"
case "$WARN_OUT" in
  *"dev dependencies"*"NOT added"*) pass "an existing package.json produces a warning" ;;
  *)                                fail "an existing package.json is skipped silently" ;;
esac
ok "the warning names the packages the hook needs" \
   sh -c 'case "$1" in *"@commitlint/cli"*) exit 0 ;; *) exit 1 ;; esac' _ "$WARN_OUT"

echo "== the hook explains a missing commitlint instead of failing as npx"

HOOK_REPO="$(new_repo hookmsg)"
"$INSTALL" "$HOOK_REPO" --toolchain npm >/dev/null 2>&1
printf 'feat: x\n' > "$HOOK_REPO/msg"
HOOK_OUT="$(make -C "$HOOK_REPO" commit-lint MSG="$HOOK_REPO/msg" 2>&1 || true)"
case "$HOOK_OUT" in
  *"make deps"*) pass "a missing commitlint points at 'make deps'" ;;
  *)             fail "a missing commitlint gives no actionable message" ;;
esac

# The substitutions depend on the exact first-line spelling of two templates.
# sed exits 0 on a miss, so without verify_line() a reformat would install a
# silently wrong toolchain and surface much later as "commitlint: not found".
echo "== a reformatted template must abort the install, not pass silently"

KIT_COPY="$TMP_ROOT/kit-copy"
mkdir -p "$KIT_COPY"
tar -c -C "$KIT_DIR" --exclude .git --exclude node_modules . | tar -x -C "$KIT_COPY"

for target in templates/Makefile templates/git-conventions.yaml; do
  BROKEN="$TMP_ROOT/kit-broken"
  rm -rf "$BROKEN"
  cp -R "$KIT_COPY" "$BROKEN"
  # Squeeze out the spaces the substitution pattern depends on.
  sed -i.bak '1,6s/ *?= */?=/; 1,6s/^toolchain: /toolchain:/' "$BROKEN/$target"
  rm -f "$BROKEN/$target.bak"

  R="$(new_repo "drift-$(basename "$target")")"
  if OUT="$("$BROKEN/install.sh" "$R" --toolchain pixi 2>&1)"; then
    fail "reformatted $target still exited 0"
  else
    case "$OUT" in
      *"substitution did nothing"*) pass "reformatted $target aborts with a diagnostic" ;;
      *)                            fail "reformatted $target aborted without naming the cause" ;;
    esac
  fi
done

echo "== commitlint enforces the list in git-conventions.yaml"

FIXTURE_DIR="$TMP_ROOT/fixtures"
mkdir -p "$FIXTURE_DIR"
printf 'feat: a real feature\n' > "$FIXTURE_DIR/good"
printf 'no type here\n'         > "$FIXTURE_DIR/no-type"
printf 'wip: not an allowed type\n' > "$FIXTURE_DIR/bad-type"

if [ -x "$KIT_DIR/node_modules/.bin/commitlint" ]; then
  ok "a conventional subject passes"   make -C "$KIT_DIR" commit-lint MSG="$FIXTURE_DIR/good"
  no "a subject with no type fails"    make -C "$KIT_DIR" commit-lint MSG="$FIXTURE_DIR/no-type"
  no "a type absent from the yaml fails" make -C "$KIT_DIR" commit-lint MSG="$FIXTURE_DIR/bad-type"
else
  echo "  skip commitlint checks (run 'npm install' first)"
fi

echo
echo "install_test: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
