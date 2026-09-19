TOOLCHAIN ?= npm

# Every toolchain needs the same Node tools: commitlint is a Node program and
# commitlint.config.js requires js-yaml to read git-conventions.yaml. pixi and
# nix differ only in how Node itself is provisioned, so they run the same
# `npm install` inside their activated environment rather than skipping it.
ifeq ($(TOOLCHAIN),npm)
  JS_RUN := npx --no --
  PY_RUN :=
  DEPS := npm install
else ifeq ($(TOOLCHAIN),pnpm)
  JS_RUN := pnpm exec
  PY_RUN :=
  DEPS := pnpm install
else ifeq ($(TOOLCHAIN),yarn)
  JS_RUN := yarn
  PY_RUN :=
  DEPS := yarn install
else ifeq ($(TOOLCHAIN),pixi)
  JS_RUN := pixi run npx --no --
  PY_RUN := pixi run
  DEPS := pixi install && pixi run npm install
else ifeq ($(TOOLCHAIN),nix)
  JS_RUN := nix develop --command npx --no --
  PY_RUN := nix develop --command
  DEPS := nix develop --command npm install
endif

.PHONY: deps commit-lint check-branch

deps:
	$(DEPS)

# The hook calls this on every commit. When commitlint is missing, `npx --no`
# fails with a message about npx, not about this kit — and a developer whose
# every commit is rejected reaches for --no-verify, which disables the whole
# enforcement layer. Say what is wrong and how to fix it instead.
commit-lint:
	@$(JS_RUN) commitlint --version >/dev/null 2>&1 || { \
	  echo "commit-lint: commitlint is not available for toolchain '$(TOOLCHAIN)'." >&2; \
	  echo "             Install this repo's dev dependencies:  make deps" >&2; \
	  exit 1; }
	$(JS_RUN) commitlint --edit "$(MSG)"

check-branch:
	@command -v commit-check >/dev/null 2>&1 || [ -n "$(PY_RUN)" ] || { \
	  echo "check-branch: commit-check is not installed." >&2; \
	  echo "              It ships with the pixi and nix environments; on npm/pnpm/yarn" >&2; \
	  echo "              install it yourself, e.g.  pipx install commit-check" >&2; \
	  exit 1; }
	$(PY_RUN) commit-check --branch
