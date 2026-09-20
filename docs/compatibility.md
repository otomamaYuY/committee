# Compatibility

What has been verified, and what has not. Anything not listed as exercised
by CI is a claim nobody has checked — treat it as unknown.

## Requirements

**Node 22.12 or newer** — commitlint 21 requires it, and `package.json`
declares it — and a package manager that populates `node_modules/.bin`,
which is where the hooks resolve `commitlint` from.

npm, pnpm and Yarn Classic are each exercised by CI: the kit is installed
into a scratch repo, the dependencies are installed with that manager, and
a real commit and push are driven through the hooks
(`tests/package_manager_test.sh`).

**Yarn PnP is not supported and not tested** — it deliberately has no
`node_modules`, so `require.resolve` from the hook cannot find commitlint.
Use `nodeLinker: node-modules` if you are on PnP.

### Platforms

Linux in CI, macOS in development, and **Windows in CI** through Git Bash —
which is the same interpreter git itself uses to run hooks there, so the
job exercises the path a Windows user actually takes. It installs the kit,
installs the dependencies and drives a real commit and a real push through
the installed hooks.

One thing that job found is worth knowing if you are on Windows. The
runner has `core.autocrlf=true`, so before `.gitattributes` existed both
hooks were checked out with CRLF terminators — and they worked, because
Git Bash tolerates a trailing `\r`. That is the interpreter being
forgiving rather than the scripts being right: any other `sh` treats the
`\r` as part of the last argument and fails with an error naming neither
the line endings nor the hook. `.gitattributes` now pins every shell
script to LF, and the Windows job asserts it rather than assuming it.

`tests/install_test.sh` is **not** run on Windows: it uses `ln -s`, which
needs Developer Mode there. So the installer's argument handling and
no-clobber behaviour are covered on Linux and macOS only.

The whole kit is three dev dependencies: `@commitlint/cli`,
`@commitlint/config-conventional` and `js-yaml`.

Both hooks need those packages, and both say so plainly when they are
missing. They never run before `npm install` anyway: git only calls a hook
once `core.hooksPath` is set, and that is the `prepare` script's job.

## Verified where

| Claim | Backed by |
|---|---|
| `install.sh` behaviour | `tests/install_test.sh`, in CI |
| The config file is the only list | `tests/drift_test.js`, in CI |
| npm, pnpm, Yarn Classic | `tests/package_manager_test.sh`, a CI matrix |
| Node floor | `engines` in `package.json`, and CI runs Node 22 |
| Shell quality | `shellcheck --severity=info`, pinned to 0.11.0 in CI |
| `npx skills add …` | the skills CLI's published contract — read, not run |
| Yarn PnP | nothing: stated unsupported and untested |
| Windows, through Git Bash | `tests/package_manager_test.sh` on `windows-latest`, plus an assertion that the hooks arrive with LF endings |
| Windows, `install_test.sh` | nothing: excluded because it uses `ln -s` |
