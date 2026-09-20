# shellcheck shell=bash
# Shared assertions for the shell suites. Sourced, never executed — hence a
# shell directive rather than a shebang, which would imply otherwise.
#
# This exists because every suite written without it re-invented the same
# helpers, and three times reached for `sh -c '... "$1" ...' _ "$dir"` to run
# something inside a repo — an idiom shellcheck rejects (SC2016) and which is
# unreadable besides. Start from here and the temptation does not arise.

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '  FAIL %s\n' "$1"; }

# ok <description> <command...>   — the command must succeed.
ok() { desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi; }

# no <description> <command...>   — the command must fail.
no() { desc="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi; }

# has <description> <haystack> <needle>
has() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" ;; esac; }

# in_repo <dir> <command...>
#
# git runs hooks with the repo root as cwd, and node resolves node_modules
# from there — running one from anywhere else searches the wrong tree.
# </dev/null matters too: pre-push reads its refs from stdin, and without it
# an interactive run would block waiting for them.
in_repo() {
  _d="$1"
  shift
  (cd "$_d" && "$@" </dev/null)
}

# hooks_path <dir> — empty when the repo has none, rather than failing.
hooks_path() { git -C "$1" config --local --get core.hooksPath || true; }

# new_repo <dir> — a git repo with an identity, ready to commit in.
new_repo() {
  rm -rf "$1"
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email committee-test@example.invalid
  git -C "$1" config user.name "committee test"
}

# summary <suite name> — prints the tally and sets the exit status.
summary() {
  echo
  echo "$1: $PASSED passed, $FAILED failed"
  [ "$FAILED" -eq 0 ]
}
