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

# shellcheck source=tests/lib.sh
. "$KIT_DIR/tests/lib.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# The suites differ here: this one names repos and wants the path back.
new_repo() {
  _dir="$TMP_ROOT/$1"
  rm -rf "$_dir"
  mkdir -p "$_dir"
  git -C "$_dir" init -q
  git -C "$_dir" config user.email committee-test@example.invalid
  git -C "$_dir" config user.name "committee test"
  printf '%s' "$_dir"
}

# A repo with the kit already installed. `--with-deps` borrows the kit's own
# node_modules so the hooks can actually run, which exercises the installed
# hook rather than npm.
installed_repo() {
  _dir="$(new_repo "$1")"
  "$INSTALL" "$_dir" >/dev/null 2>&1
  if [ "${2:-}" = "--with-deps" ]; then
    ln -s "$KIT_DIR/node_modules" "$_dir/node_modules"
  fi
  printf '%s' "$_dir"
}

ZERO_SHA=0000000000000000000000000000000000000000
SOME_SHA=1111111111111111111111111111111111111111

# Feed the hook git's own pre-push protocol — one "<local ref> <local sha>
# <remote ref> <remote sha>" line per ref — rather than a side channel.
push_refs() {
  _d="$1"
  shift
  printf '%s\n' "$@" | (cd "$_d" && ./.githooks/pre-push)
}

check_branch() {
  push_refs "$1" "refs/heads/$2 $SOME_SHA refs/heads/$2 $ZERO_SHA"
}

# Exactly what `npm install` would run as prepare, read from the template
# rather than restated here — a second copy would be free to drift.
prepare_script() {
  node -e 'const fs = require("fs");
           process.stdout.write(JSON.parse(fs.readFileSync(process.argv[1], "utf8")).scripts.prepare)' \
       "$KIT_DIR/templates/package.json.example"
}

echo "== argument validation (nothing may be written before the target is validated)"

ok "--help exits 0"                      "$INSTALL" --help
no "--help creates no directory here"    test -e "$PWD/--help"
no "--help creates no directory in tmp"  test -e "$TMP_ROOT/--help"

no "unknown option is rejected"          "$INSTALL" --bogus
no "a removed option is rejected"        "$INSTALL" "$(new_repo argv0)" --toolchain npm
no "empty target is rejected"            "$INSTALL" ""
no "nonexistent target is rejected"      "$INSTALL" "$TMP_ROOT/does-not-exist"
no "two target directories are rejected" "$INSTALL" "$(new_repo argv3)" "$(new_repo argv4)"
no "installing into the kit's own source is rejected" "$INSTALL" "$KIT_DIR"

NOT_A_REPO="$TMP_ROOT/plain-dir"
mkdir -p "$NOT_A_REPO"
no "non-git directory is rejected" "$INSTALL" "$NOT_A_REPO"
ok "rejected target is left untouched" test -z "$(ls -A "$NOT_A_REPO")"

echo "== a clean install puts every file where the docs say"

FRESH="$(new_repo fresh)"
FRESH_OUT="$("$INSTALL" "$FRESH" 2>&1)"

for f in .claude/git-conventions.yaml \
         .claude/skills/git-conventions/SKILL.md \
         commitlint.config.js \
         AGENTS.md \
         .githooks/commit-msg \
         .githooks/pre-push \
         .github/workflows/conventions.yml \
         package.json; do
  ok "installs $f" test -f "$FRESH/$f"
done
ok "the commit-msg hook is executable" test -x "$FRESH/.githooks/commit-msg"
ok "the pre-push hook is executable"   test -x "$FRESH/.githooks/pre-push"
ok "core.hooksPath points at the tracked hooks" test "$(hooks_path "$FRESH")" = ".githooks"
ok "package.json declares commitlint"  grep -q '@commitlint/cli' "$FRESH/package.json"
ok "package.json declares the config"  grep -q '@commitlint/config-conventional' "$FRESH/package.json"
ok "package.json declares js-yaml"     grep -q 'js-yaml' "$FRESH/package.json"
no "no Makefile is installed"          test -e "$FRESH/Makefile"
no "no release config is installed"    test -e "$FRESH/.releaserc.json"
no "nothing depends on husky"          grep -q 'husky' "$FRESH/package.json"

echo "== no-clobber"

REPO="$(new_repo clobber)"
mkdir -p "$REPO/.github/workflows"
printf 'name: my real workflow\n' > "$REPO/.github/workflows/conventions.yml"
printf 'module.exports = { mine: true };\n' > "$REPO/commitlint.config.js"
printf '{"name":"mine"}\n' > "$REPO/package.json"

OUT="$("$INSTALL" "$REPO" 2>&1)"

ok "pre-existing workflow survives"    grep -qx 'name: my real workflow' "$REPO/.github/workflows/conventions.yml"
ok "pre-existing config survives"      grep -q  'mine: true'             "$REPO/commitlint.config.js"
ok "pre-existing package.json survives" grep -q '"name":"mine"'          "$REPO/package.json"
ok "files absent from the target are still installed" test -f "$REPO/.githooks/commit-msg"
has "skipped files are reported"       "$OUT" "Skipped (already present"
has "the report says how to override"  "$OUT" "Re-run with --force"
has "a pre-existing package.json is warned about" "$OUT" "NOT added"
has "the Codex knowledge layer is installed too" "$FRESH_OUT" "AGENTS.md"
has "the warning names what the hook needs"       "$OUT" "@commitlint/cli"

"$INSTALL" "$REPO" --force >/dev/null 2>&1
ok "--force overwrites an existing file" grep -q 'git-conventions' "$REPO/commitlint.config.js"

# grep -v is per-line, so it cannot express "this file contains no such line".
not_grep() { ! grep -qx "$1" "$2"; }

# The report lists AGENTS.md under Written or under Skipped, never both. The
# refresh path must not also claim it was left untouched.
test_no_skipped_agents() {
  ! printf '%s' "$1" | awk '/^Skipped/ { s = 1; next } /^$/ { s = 0 } s && /AGENTS\.md/ { found = 1 } END { exit !found }'
}

echo "== an existing AGENTS.md is preserved and called out"

AG="$(new_repo agents)"
printf '# my own agent notes\n' > "$AG/AGENTS.md"
AG_OUT="$("$INSTALL" "$AG" 2>&1)"
ok "a pre-existing AGENTS.md survives" grep -qx '# my own agent notes' "$AG/AGENTS.md"
has "the unmarked AGENTS.md is warned about" "$AG_OUT" "no committee markers"
has "the warning says what to do"            "$AG_OUT" "templates/AGENTS.md"
has "the warning explains why markers matter" "$AG_OUT" "refresh that section"

echo "== a marked AGENTS.md has its section refreshed, and only that section"

# The whole point of the markers: a repo that installed once must keep
# receiving corrections to the conventions, without the installer touching a
# line the adopter wrote. A stale conventions section is how a repo's Codex
# reviewers end up disagreeing with its Claude ones.
MK="$(new_repo marked)"
{
  printf '# House notes\n\nSomething of my own, above.\n\n'
  cat "$KIT_DIR/templates/AGENTS.md"
  printf '\n## My own section\n\nSomething of my own, below.\n'
} > "$MK/AGENTS.md"
# Make the kit's region stale, the way an older install would be.
sed -i.orig 's/^# Git conventions$/# Git conventions (stale)/' "$MK/AGENTS.md" && rm -f "$MK/AGENTS.md.orig"
MK_OUT="$("$INSTALL" "$MK" 2>&1)"

ok "text above the markers survives"  grep -qx 'Something of my own, above.' "$MK/AGENTS.md"
ok "text below the markers survives"  grep -qx 'Something of my own, below.' "$MK/AGENTS.md"
ok "the stale section is replaced"    not_grep '# Git conventions (stale)' "$MK/AGENTS.md"
ok "the current section is installed" grep -q 'Blocking is carried by the decoration' "$MK/AGENTS.md"
ok "the previous file is kept"        test -f "$MK/AGENTS.md.bak"
ok "the backup has the stale section" grep -qx '# Git conventions (stale)' "$MK/AGENTS.md.bak"
has "the refresh is reported"         "$MK_OUT" "conventions section refreshed"
ok "the file is not listed as skipped" test_no_skipped_agents "$MK_OUT"

echo "== a marked AGENTS.md that is already current is left alone"

CUR="$(new_repo current)"
cp "$KIT_DIR/templates/AGENTS.md" "$CUR/AGENTS.md"
CUR_OUT="$("$INSTALL" "$CUR" 2>&1)"
has "an already-current section says so" "$CUR_OUT" "already current"
ok "no needless backup is left"          test ! -f "$CUR/AGENTS.md.bak"

echo "== an AGENTS.md with confused markers is not spliced"

# Two starts, or an end before a start, means the installer cannot tell which
# region is the kit's. Guessing would edit the adopter's prose.
BAD="$(new_repo badmarkers)"
{
  printf '<!-- committee:end -->\n'
  printf '# mine\n'
  printf '<!-- committee:start -->\n'
} > "$BAD/AGENTS.md"
BAD_OUT="$("$INSTALL" "$BAD" 2>&1)"
ok "a confusingly marked file is untouched" grep -qx '# mine' "$BAD/AGENTS.md"
has "and is warned about like any other"    "$BAD_OUT" "no committee markers"

echo "== a repo that already routes hooks elsewhere is not hijacked"

HOOKED="$(new_repo hooked)"
git -C "$HOOKED" config --local core.hooksPath .husky/_
HOOKED_OUT="$("$INSTALL" "$HOOKED" 2>&1)"
ok "the existing hooksPath is left alone" test "$(hooks_path "$HOOKED")" = ".husky/_"
has "the collision is reported"        "$HOOKED_OUT" "already routes git hooks"
has "the report says how to switch"    "$HOOKED_OUT" "core.hooksPath .githooks"

echo "== the hook says what is missing when commitlint is absent"

BARE="$(new_repo bare)"
"$INSTALL" "$BARE" >/dev/null 2>&1
printf 'feat: x\n' > "$BARE/msg"
# git runs hooks with the repo root as cwd; npx resolves node_modules from
# there, so running the hook from anywhere else would find the wrong tree.
BARE_OUT="$(in_repo "$BARE" ./.githooks/commit-msg msg 2>&1 || true)"
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

no "a non-conventional commit message is rejected" \
   git -C "$E2E" commit -q -m "nope, not conventional"
no "a type absent from git-conventions.yaml is rejected" \
   git -C "$E2E" commit -q -m "wip: a type that is not on the list"
ok "a conventional commit message is accepted" \
   git -C "$E2E" commit -q -m "feat: a type that is on the list"

# Prove the yaml is the source of truth, not a hardcoded list: add a type and
# the same message that was just rejected must now pass.
# Insert into the commit_types block, not at the end of the file (where the
# last block is comment_labels).
sed -i.bak 's/^commit_types:$/commit_types:\n  - wip/' "$E2E/.claude/git-conventions.yaml"
rm -f "$E2E/.claude/git-conventions.yaml.bak"
echo again > "$E2E/file.txt"
git -C "$E2E" add -A
ok "adding a type to git-conventions.yaml changes what the hook accepts" \
   git -C "$E2E" commit -q -m "wip: now allowed by the yaml"

echo "== scopes are opt-in, and enforced once opted in"

# The template ships no scopes list on purpose: the kit cannot know an
# adopter's seams, and a guessed list would reject correct commits in every
# repo that installs it. So a fresh install must accept any scope at all --
# and the only way to be sure is to commit one the kit has never heard of.
SC="$(installed_repo scopes --with-deps)"
echo one > "$SC/file.txt"
git -C "$SC" add -A
ok "a fresh install accepts a scope it was never told about" \
   git -C "$SC" commit -q -m "feat(anything-at-all): scopes are not enforced yet"

# Opting in: the same list mechanism as commit_types, in the same file.
printf '\nscopes:\n  - api\n  - web\n' >> "$SC/.claude/git-conventions.yaml"
echo two > "$SC/file.txt"
git -C "$SC" add -A

no "a scope absent from the list is now rejected" \
   git -C "$SC" commit -q -m "feat(anything-at-all): no longer allowed"
ok "a scope on the list is accepted" \
   git -C "$SC" commit -q -m "feat(api): on the list"

# Conventional Commits keeps the scope itself optional, and a repo-wide
# change genuinely has none. Opting in must not quietly make it mandatory.
echo three > "$SC/file.txt"
git -C "$SC" add -A
ok "a commit with no scope at all is still accepted" \
   git -C "$SC" commit -q -m "chore: no scope, and none needed"

# A scopes: key holding something that is not a list would otherwise reach
# commitlint as a rule value it cannot use, and the reader would be sent to
# commitlint.config.js rather than to the file they actually mistyped. A repo
# of its own, because a second scopes: key in $SC would be caught earlier as
# a duplicate mapping key and never reach the check under test.
BADSC="$(installed_repo scopes-malformed --with-deps)"
cp "$BADSC/.claude/git-conventions.yaml" "$BADSC/healthy.yaml"
printf '\nscopes: not-a-list\n' >> "$BADSC/.claude/git-conventions.yaml"
printf 'feat(api): x\n' > "$BADSC/msg"
SC_OUT="$(in_repo "$BADSC" ./.githooks/commit-msg msg 2>&1 || true)"
has "a malformed scopes: block is named"  "$SC_OUT" '"scopes:" key is present'
has "and the conventions file is blamed"  "$SC_OUT" "git-conventions.yaml"
has "and deleting the key is offered"     "$SC_OUT" "accept any scope"

# An empty list is the same mistake wearing different clothes: it would make
# commitlint reject every scope in the repo while looking deliberate.
cp "$BADSC/healthy.yaml" "$BADSC/.claude/git-conventions.yaml"
printf '\nscopes: []\n' >> "$BADSC/.claude/git-conventions.yaml"
no "an empty scopes list is refused rather than enforced" \
   in_repo "$BADSC" ./.githooks/commit-msg msg

cp "$BADSC/healthy.yaml" "$BADSC/.claude/git-conventions.yaml"
ok "the shipped file, which lists no scopes, accepts one anyway" \
   in_repo "$BADSC" ./.githooks/commit-msg msg

echo "== branch names are judged against git-conventions.yaml"

BR="$(installed_repo branch --with-deps)"

# Each of these goes through the hook the way git would drive it on a push.
for good in main master develop feature/add-oauth-login claude/scaffold-the-kit fix/off-by-one chore/bump-deps; do
  ok "accepts '$good'" check_branch "$BR" "$good"
done

# docs/ and perf/ are commit_types, note/ and question/ are comment_labels.
# All four live in the same YAML file, so only reading branch_types
# specifically keeps them out of the branch list.
#
# A name containing a space is not listed: git refuses such a ref itself, so
# it cannot reach the hook through the push protocol. The description regex
# still rejects it; there is simply no way to get one here.
for bad in Feature/Capitalized feature/Has-Capitals feature/trailing- feature/double--hyphen \
           nosuchtype/thing no-slash-at-all feature/ \
           docs/only-a-commit-type perf/only-a-commit-type \
           note/only-a-comment-label question/only-a-comment-label; do
  no "rejects '$bad'" check_branch "$BR" "$bad"
done

BR_OUT="$(check_branch "$BR" nosuchtype/thing 2>&1 || true)"
has "the rejection explains the expected shape" "$BR_OUT" "<type>/<description>"
has "the rejection lists the allowed types"     "$BR_OUT" "feature"
has "the rejection says how to fix it"          "$BR_OUT" "git branch -m"

# Source of truth, again: the hook must follow the yaml, not a baked-in list.
sed -i.bak 's|^branch_types:$|branch_types:\n  - spike|' "$BR/.claude/git-conventions.yaml"
rm -f "$BR/.claude/git-conventions.yaml.bak"
ok "a type added to the yaml becomes acceptable" check_branch "$BR" spike/try-something

# A detached HEAD has no branch to judge; the hook must not block the push.
git -C "$BR" commit -q --allow-empty -m "chore: something to detach from"
git -C "$BR" checkout -q --detach HEAD
ok "a detached HEAD is not blocked" in_repo "$BR" ./.githooks/pre-push
# A deletion and a tag push carry no branch name to judge either.
ok "a branch deletion is not blocked" \
   push_refs "$BR" "refs/heads/Bad_Name $ZERO_SHA refs/heads/Bad_Name $SOME_SHA"
ok "a tag push is not blocked" \
   push_refs "$BR" "refs/tags/v1.0 $SOME_SHA refs/tags/v1.0 $ZERO_SHA"

# Reading the refs being pushed rather than HEAD is what makes this work:
# `git push origin a b` from a good branch used to be judged on HEAD alone,
# so a bad second branch went through unexamined.
no "a bad branch is caught even when it is not the one checked out" \
   push_refs "$BR" "refs/heads/feature/fine $SOME_SHA refs/heads/feature/fine $ZERO_SHA" \
                   "refs/heads/Bad_Second $SOME_SHA refs/heads/Bad_Second $ZERO_SHA"

echo "== end to end: a real push through the installed hook"

REMOTE="$TMP_ROOT/remote.git"
git init -q --bare "$REMOTE"
PUSH="$(new_repo push)"
"$INSTALL" "$PUSH" >/dev/null 2>&1
ln -s "$KIT_DIR/node_modules" "$PUSH/node_modules"
git -C "$PUSH" remote add origin "$REMOTE"
echo hello > "$PUSH/file.txt"
git -C "$PUSH" add -A
git -C "$PUSH" commit -q -m "feat: add a file"

git -C "$PUSH" checkout -q -b Not_Conventional
no "a malformed branch name is rejected on push" git -C "$PUSH" push -q origin Not_Conventional
git -C "$PUSH" checkout -q -b feature/properly-named
ok "a conventional branch name pushes"           git -C "$PUSH" push -q origin feature/properly-named

echo "== a broken conventions file blames itself, not commitlint.config.js"

# Left to itself commitlint reports "Please add rules to your
# commitlint.config.js" for a missing config and "type must be one of []" for
# a typo'd key — both send the reader to edit the wrong file.
CFG="$(new_repo cfg)"
"$INSTALL" "$CFG" >/dev/null 2>&1
ln -s "$KIT_DIR/node_modules" "$CFG/node_modules"
printf 'feat: x\n' > "$CFG/msg"
cp "$CFG/.claude/git-conventions.yaml" "$CFG/healthy.yaml"

run_hook() { in_repo "$CFG" ./.githooks/commit-msg msg 2>&1 || true; }

rm "$CFG/.claude/git-conventions.yaml"
CFG_OUT="$(run_hook)"
has "a missing conventions file is named"      "$CFG_OUT" "cannot read the conventions file"
has "and the path is printed"                  "$CFG_OUT" "git-conventions.yaml"
has "and a fix is offered"                     "$CFG_OUT" "install.sh"

cp "$CFG/healthy.yaml" "$CFG/.claude/git-conventions.yaml"
sed -i.bak 's/^commit_types:/commit_type:/' "$CFG/.claude/git-conventions.yaml"
CFG_OUT="$(run_hook)"
has "a typo in the commit_types key is named"  "$CFG_OUT" 'no non-empty "commit_types:" list'
has "and the typo is suggested as the cause"   "$CFG_OUT" "typo"

cp "$CFG/healthy.yaml" "$CFG/.claude/git-conventions.yaml"
printf '\n  bad: [unclosed\n' >> "$CFG/.claude/git-conventions.yaml"
CFG_OUT="$(run_hook)"
has "malformed YAML is reported as YAML"       "$CFG_OUT" "not valid YAML"

cp "$CFG/healthy.yaml" "$CFG/.claude/git-conventions.yaml"
ok "a healthy config still accepts a good message" in_repo "$CFG" ./.githooks/commit-msg msg

echo "== the hooks reach a teammate's clone, not just the installer's machine"

# core.hooksPath lives in .git/config and is never committed. Without the
# prepare script the hook FILES arrive in every clone and nothing runs them,
# so the kit would enforce its conventions for exactly one person.
ok "package.json.example ships a prepare script" \
   grep -q 'core.hooksPath .githooks' "$KIT_DIR/templates/package.json.example"
ok "package.json.example declares the Node floor commitlint needs" \
   grep -q '">=22' "$KIT_DIR/templates/package.json.example"

PREPARE="$(prepare_script)"

# A prepare script that aborts npm install outside a git repo breaks Docker
# builds and tarball checkouts, which copy sources without .git.
NONGIT="$TMP_ROOT/nongit"
rm -rf "$NONGIT"
mkdir -p "$NONGIT"
cp "$KIT_DIR/templates/package.json.example" "$NONGIT/package.json"
NONGIT_OUT="$(in_repo "$NONGIT" sh -c "$PREPARE" 2>&1 || true)"
ok "the prepare script does not fail outside a git repo" \
   in_repo "$NONGIT" sh -c "$PREPARE"
has "and says why the hooks are not wired" "$NONGIT_OUT" "not a git repository"

LEAD="$(new_repo lead)"
"$INSTALL" "$LEAD" >/dev/null 2>&1
git -C "$LEAD" add -A
git -C "$LEAD" -c core.hooksPath=/dev/null commit -q -m "chore: adopt the kit"

MATE="$TMP_ROOT/teammate"
rm -rf "$MATE"
git clone -q "$LEAD" "$MATE"
git -C "$MATE" config user.email m@example.invalid
git -C "$MATE" config user.name mate

ok "a fresh clone receives the hook files" test -x "$MATE/.githooks/commit-msg"
ok "a fresh clone starts with no hooksPath (this is why prepare exists)" \
   test -z "$(hooks_path "$MATE")"

# Run exactly what `npm install` would run as prepare.
in_repo "$MATE" sh -c "$PREPARE"
ok "the prepare script wires the clone up" test "$(hooks_path "$MATE")" = ".githooks"

ln -s "$KIT_DIR/node_modules" "$MATE/node_modules"
echo x > "$MATE/f.txt"
git -C "$MATE" add -A
no "the teammate's bad commit is now rejected" \
   git -C "$MATE" commit -q -m "totally unconventional"
ok "and a good one is accepted" \
   git -C "$MATE" commit -q -m "feat: something conventional"

echo "== an unreadable conventions file fails closed, always"

# There is no lenient path any more: the hook needs node and js-yaml, which
# are present whenever it can run at all, so a config it cannot read is a
# real misconfiguration rather than a state to wave through.
STRICT="$(installed_repo strict --with-deps)"
cp "$STRICT/.claude/git-conventions.yaml" "$STRICT/healthy.yaml"

rm "$STRICT/.claude/git-conventions.yaml"
no "a missing config is refused" check_branch "$STRICT" feature/x

printf 'commit_types:
  - feat
' > "$STRICT/.claude/git-conventions.yaml"
no "a config with no branch_types is refused" check_branch "$STRICT" feature/x
STRICT_OUT="$(check_branch "$STRICT" feature/x 2>&1 || true)"
has "and says what it could not read" "$STRICT_OUT" "branch_types"

cp "$STRICT/healthy.yaml" "$STRICT/.claude/git-conventions.yaml"
ok "a healthy config passes" check_branch "$STRICT" feature/x


echo "== the Skill is refreshed on re-install, and only the Skill"

SK="$(new_repo skill)"
"$INSTALL" "$SK" >/dev/null 2>&1
echo "STALE MARKER" >> "$SK/.claude/skills/git-conventions/SKILL.md"
mkdir -p "$SK/.claude/skills/my-own-skill"
printf 'mine\n' > "$SK/.claude/skills/my-own-skill/SKILL.md"
"$INSTALL" "$SK" >/dev/null 2>&1   # no --force: the Skill refreshes anyway

no "a stale Skill is replaced without --force" \
   grep -q 'STALE MARKER' "$SK/.claude/skills/git-conventions/SKILL.md"
ok "a neighbouring skill is left alone" test -f "$SK/.claude/skills/my-own-skill/SKILL.md"
ok "the replaced copy is kept as a backup" \
   grep -q 'STALE MARKER' "$SK/.claude/skills/git-conventions.bak/SKILL.md"

SK2="$(new_repo skill-clean)"
"$INSTALL" "$SK2" >/dev/null 2>&1
"$INSTALL" "$SK2" >/dev/null 2>&1
no "an unmodified Skill leaves no stray backup" test -e "$SK2/.claude/skills/git-conventions.bak"

echo "== the installer refuses to delete through a symlink"

SYM="$(new_repo symlink)"
OUTSIDE="$TMP_ROOT/outside-the-repo"
mkdir -p "$OUTSIDE/git-conventions"
printf 'precious\n' > "$OUTSIDE/git-conventions/SKILL.md"
mkdir -p "$SYM/.claude"
ln -s "$OUTSIDE" "$SYM/.claude/skills"
no "installing through a symlinked skills dir is refused" "$INSTALL" "$SYM"
ok "the directory it pointed at is untouched" grep -qx 'precious' "$OUTSIDE/git-conventions/SKILL.md"

echo "== a git worktree is a valid target"

# install.sh checks `-e .git` rather than `-d` precisely for this case: in a
# worktree .git is a file. Nothing else in this suite creates one.
WTBASE="$(new_repo wtbase)"
echo seed > "$WTBASE/seed.txt"
git -C "$WTBASE" add -A
git -C "$WTBASE" -c core.hooksPath=/dev/null commit -q -m "chore: seed"
WT="$TMP_ROOT/worktree"
git -C "$WTBASE" worktree add -q "$WT" -b feature/from-a-worktree
ok "installing into a worktree succeeds" "$INSTALL" "$WT"
ok "and the hooks land there"            test -x "$WT/.githooks/commit-msg"

echo "== the installed package.json is named after the repo"

NAMED="$(new_repo my-service)"
"$INSTALL" "$NAMED" >/dev/null 2>&1
ok "the placeholder name is substituted" grep -q '"name": "my-service"' "$NAMED/package.json"
no "no placeholder survives"             grep -q 'your-project' "$NAMED/package.json"

summary install_test
