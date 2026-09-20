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

Linux and macOS are what CI and development cover. **Windows is untested.**
The hooks are POSIX `sh`, which git for Windows provides, and the `prepare`
script goes through node rather than a shell idiom — but nobody has run it
there, so treat it as unknown rather than working.

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
| Windows | nothing: stated untested |
