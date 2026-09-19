TOOLCHAIN ?= npm

ifeq ($(TOOLCHAIN),npm)
  JS_RUN := npx --no --
  PY_RUN :=
else ifeq ($(TOOLCHAIN),pnpm)
  JS_RUN := pnpm exec
  PY_RUN :=
else ifeq ($(TOOLCHAIN),yarn)
  JS_RUN := yarn
  PY_RUN :=
else ifeq ($(TOOLCHAIN),pixi)
  JS_RUN := pixi run npx --no --
  PY_RUN := pixi run
else ifeq ($(TOOLCHAIN),nix)
  JS_RUN := nix develop --command npx --no --
  PY_RUN := nix develop --command
endif

.PHONY: commit-lint check-branch release

commit-lint:
	$(JS_RUN) commitlint --edit $(MSG)

check-branch:
	$(PY_RUN) commit-check --branch

release:
	$(JS_RUN) semantic-release
