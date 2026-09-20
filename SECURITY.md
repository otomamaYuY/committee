# Security

## Reporting a vulnerability

Report privately through GitHub's
[security advisory form](https://github.com/otomamaYuY/committee/security/advisories/new).
Please do not open a public issue for a vulnerability.

Include what an attacker gains, and the smallest steps that demonstrate it.
Expect a first response within a week.

## What counts as a vulnerability here

This kit runs in two places that matter, and a defect in either reaches
every repository that installed it:

- **`install.sh`** runs on a developer's machine with their permissions,
  takes a path from its caller, and deletes and writes files under it.
  Anything that makes it write or delete outside the target repository, or
  act on a path it was not given, is a vulnerability.
- **`.github/workflows/conventions.yml`** runs in every adopting repository's
  CI on `pull_request`, which means it runs against content a pull request
  controls. Anything that turns a pull request's own data into commands on
  the runner, or that reaches a token or secret it should not, is a
  vulnerability.

The git hooks run locally on content the developer already has, so a defect
there is usually a correctness bug rather than a security one — unless it
lets a crafted branch name, commit message or config file execute something.

## What does not

- A commit or branch that passes the checks but is *semantically* wrong — a
  bug fix labelled `feat:`, say. The enforcement layer validates shape only;
  judging the type is what the knowledge layer is for, and it is advisory by
  design. See the README's "Why two layers".
- Bypassing the hooks with `--no-verify`, or by editing the hooks. Local
  hooks are a convenience for the person running them, not a control against
  that person. The CI workflow is the check that does not depend on
  cooperation — protect your default branch with it.
- Vulnerabilities in commitlint or its dependencies. Report those upstream;
  tell us if this kit's configuration makes one reachable that otherwise
  would not be.

## Supported versions

The default branch. This kit is small enough that fixes land there rather
than being backported.
