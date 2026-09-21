# Carrying the review-comment rules, not just the label names

## Problem

The kit transcribes Conventional Comments' **label names** into
`.claude/git-conventions.yaml`, but not the **behaviour the specification
attaches to them**. Two things are observably missing.

First, the specification asks a reviewer to try to leave at least one
`praise:` comment per review, and warns that insincere praise is damaging
rather than neutral. Nothing in the kit's knowledge layer says so, so a
reviewer — person or agent — following the kit faithfully produces reviews
containing no praise at all, and for an agent the kit is the only thing it
reads.

Second, the specification defines decorations as organisation-specific and
asks each adopting organisation to fix a minimal, unambiguous set, including
whether comments are blocking by default. The kit names the format
`<label> [decorations]: <subject>` but never says which decorations exist or
which default applies.

The observable symptom is a question the kit cannot answer. A reviewer who
reads `SKILL.md`, `AGENTS.md` and `.claude/git-conventions.yaml` end to end
still cannot determine **whether an unresolved `suggestion:` comment stops
the pull request from being approved.** Neither can the author receiving it.
Both sides guess, and they can guess differently about the same comment.

## Constraints and non-goals

Constraints, all `[hard]`:

1. **No second list of labels, and no per-label mapping, outside the
   conventions file.** `CLAUDE.md` states that `.claude/git-conventions.yaml`
   is the only place a review label may be written down, and that a second
   list "is the bug"; `AGENTS.md:6-9` tells its own reader not to work from
   the examples below it because "they show the shape, not the list". A
   label-to-blocking-class table in prose is exactly that second list, and the
   first three drafts of this design contained one. Referring to a single
   label by name where a rule genuinely concerns that label is not a list and
   is not forbidden — the existing prose already does it — but a rule whose
   correctness depends on enumerating the label set is.
2. **Root/template parity.** `SKILL.md` and `AGENTS.md` each have a
   byte-identical counterpart enforced by `tests/drift_test.js`.
3. **Knowledge layer only.** Conventional Comments has no linter. No
   enforcement mechanism is available for any of this, and the kit must not be
   written as though one existed.
4. **Do not diverge from the specification silently.** Where this design
   decides something the spec leaves open, or departs from something the spec
   states, it must say which it is doing.
5. **No new dependency, and no new installed file**; and configuration surface
   answers the repo's standing question, *does every adopting repo need this?*
6. **The YAML is the adopter's customisation surface.** This is a preference
   here rather than a gate, and the earlier drafts overstated it. They argued
   that every existing key has a parser behind it — `commit_types` and
   `scopes` for `commitlint.config.js`, `branch_types` for
   `.githooks/pre-push` — and that a review key would therefore be inert.
   **That is false: `comment_labels` has no parser either.** It is read by the
   knowledge layer alone; `tests/drift_test.js:66` only checks that it is a
   non-empty list. A `review:` key would be no more inert than a key already
   in the file, so this constraint does not eliminate one. Constraint 7 does,
   and does it on its own.
7. **The knowledge layer must be correct against a YAML that predates it.**
   `install.sh:145-146` replaces the Skill unconditionally on every
   re-install; `install.sh:150` and `install.sh:157` route the conventions
   file and `AGENTS.md` through `install_file()`, which returns early when the
   destination exists. An existing adopter receives **a new Skill over an old
   YAML and an old `AGENTS.md`**, so no rule may depend on a YAML key that did
   not already exist.

Constraints 1 and 7 together are what shapes this design: a per-label policy
cannot be written in prose (1) and cannot be read from a new YAML key (7).
**The policy must therefore not be per-label at all.**

Non-goals, deliberately out of scope:

- Abbreviations such as LGTM, and the mapping between comment labels and
  GitHub's Approve / Request changes buttons. Deferred to a follow-up.
- Any automated checking of review comments. That is what would give a
  `review:` key a consumer; until it exists, constraint 3 stands.
- Changes to the commit, branch or version conventions, or to
  `comment_labels`.
- Fixing the `AGENTS.md` upgrade path. Recorded as a limitation in
  `## Risks and rollback`, with the user's confirmation, not solved here.

## Options considered

Both options state the same praise guidance and the same three decorations,
and neither contains a per-label mapping, so both satisfy constraint 1. They
differ on the single question the specification leaves to the adopting
organisation: **which way a comment points when it says nothing.**

### Option A — Comments do not block unless they say they do

*Sketch.* A comment does not stop approval. A reviewer who means one to stop
approval writes `(blocking)`. Approval is withheld while any unresolved
comment carries `(blocking)`. `(if-minor)` marks a comment the author may
resolve at their own discretion when the change turns out trivial. Nothing
else about a comment — least of all its label — changes whether it blocks.

*Key components.* Prose in `.claude/skills/git-conventions/SKILL.md` and
`AGENTS.md`, plus their two byte-identical twins. Four files. No YAML change,
no new test beyond the existing pair checks.

*How it meets each `[hard]` constraint.* It adds no list and no per-label
mapping (1). Both knowledge files keep their twins (2). The prose says plainly
that nothing enforces it (3). The specification explicitly anticipates this
default — it describes `(blocking)` as the decoration for organisations that
treat comments as non-blocking by default — so the default itself is a choice
the spec offers; where the spec's own text makes a label mandatory before
acceptance, the design declares the departure rather than glossing it (4).
Nothing new is installed (5), no key is added (6), and the rules ship inside
the Skill and depend on no YAML key (7).

*Where it is weak.* A reviewer who leaves a serious concern and forgets
`(blocking)` has written a comment the rules say does not stop the merge. The
label carries the severity and the decoration carries the force, and this
option lets those two come apart.

### Option B — Comments block unless they say they do not

*Sketch.* The mirror image. Every unresolved comment withholds approval; a
reviewer who means one not to writes `(non-blocking)`. The praise guidance,
`(if-minor)` and the definition of resolution are identical.

*Key components.* Identical: the same four files, the same absence of YAML
and test changes.

*How it meets each `[hard]` constraint.* Identically to Option A on every
count. The specification anticipates this default too — it describes
`(non-blocking)` as the decoration for organisations that treat comments as
blocking by default — and it has the smaller constraint-4 problem, since a
mandatory-by-spec label blocks here without anyone having to remember a
decoration.

*Where it is weak.* Every stray remark stops a merge until someone acts on it.
The kit exists because coding agents write most of the commits, and agent
reviewers are verbose; under this default, a reviewer who forgets
`(non-blocking)` on a passing thought has blocked the pull request, and the
cost is paid on the common case rather than the rare one.

## Trade-off table

Scored against the anchors in
`~/.claude/kitting/docs/architecture-decision-framework.md` **as published**.
Four criteria have nothing to grip on a change that ships only prose and are
marked `N/A` with the reason, at the user's direction, rather than being
scored on a substitute axis. Three earlier drafts of this document invented
such an axis — failure *visibility*, then failure *likelihood*, then
repo-convention consistency in the `Portfolio fit` column — and each time the
invented gap is what produced the conclusion. Scoring those four cells 3/3
instead of `N/A/N/A` would change nothing below, since the two options are
identical in them either way.

| Option | Reversibility | Blast radius | Security posture | Operational cost | Portfolio fit | Effort |
|---|---|---|---|---|---|---|
| **A — non-blocking by default** | 2 — undone by reverting the commit; no data to unwind, but a content revert, not a flag flip | 3 — contained to one repository's review process; the enforcement layer parses none of it | N/A — documentation-only: no new surface, secret, endpoint or credential | N/A — no runtime, no recurring spend, no capacity to tune | N/A — no technology, region or IaC choice is made | 3 — hours; four files, prose only |
| **B — blocking by default** | 2 — identical | 3 — identical | N/A — identical | N/A — identical | N/A — identical | 3 — identical |

**The table does not decide this.** The two options are the same change with
one word reversed, so they tie on every criterion the framework can score.
Recording that plainly is the point of filling it in: the decision below rests
on reasoning, not on a number, and no number was bent to supply one.

## Decision

**Option A — a comment does not block approval unless it carries
`(blocking)`.**

Per the framework's step 5, a genuine tie is decided as a documented judgment
call, and this rejection is recorded as one rather than against a table row.
Three reasons, in order:

1. **Constraint 3 decides which failure you can afford.** Nothing enforces
   any of this, so both defaults will be forgotten sometimes. Under Option A a
   forgotten decoration understates a comment's force, and the reviewer who
   cared still holds their approval — they simply do not give it. Under Option
   B a forgotten decoration blocks a pull request nobody meant to block, and
   the only remedy is another round-trip. The recoverable failure is the one
   where the person who made the mistake is also the person who can fix it
   immediately.
2. **The kit's premise is high comment volume.** It exists because most
   commits are written by coding agents, and agent reviewers are verbose.
   Option B taxes every remark; Option A taxes only the comments a reviewer
   feels strongly about, which are rarer. A convention whose cost scales with
   the thing the kit was built for will be abandoned.
3. **The decoration you must remember is the one you are already thinking
   about.** `(blocking)` is typed at the moment a reviewer has decided
   something matters. `(non-blocking)` would be typed at the moment they have
   decided something does not — which is exactly when attention is lowest.

### What the rules are

- **Praise.** Leave at least one `praise:` comment where there is something to
  praise, and look for it before concluding there is not. Never write praise
  you do not mean: the specification says false praise is damaging, so an
  insincere comment is worse than none. **This is guidance, not a gate** — it
  matches the specification's own "try to", and a review of a change with
  nothing sincere to praise is not thereby blocked. Making praise an approval
  condition would leave exactly one escape, which is to manufacture it.
- **Decorations.** `(blocking)`, `(non-blocking)`, `(if-minor)` — the three
  the specification proposes, adopted unchanged.
- **Blocking is carried by the decoration, never by the label.** A comment
  does not stop approval unless it carries `(blocking)`. A reviewer who wants
  one to stop approval must say so; no label does it for them.
  `(non-blocking)` is redundant under this default and is kept only because
  the specification lists it and a reviewer may want to be explicit.
  `(if-minor)` never blocks; it leaves resolution to the author when the
  change turns out to be trivial.
- **Where the specification's own text makes a label's comments mandatory
  before the change is accepted, decorate them `(blocking)` — this default
  does not do it for you.** This is a **declared departure** from the
  specification, not a reading of it: the spec makes some labels blocking by
  definition, and a decoration-only rule cannot express that without the
  per-label mapping constraint 1 forbids. The cost is one remembered
  decoration on the labels the spec already describes as prerequisites.
- **A comment is resolved when the reviewer who left it says it is** — marking
  the thread resolved on the hosting platform, or replying to agree it is
  addressed. **Resolution by the author does not count**, even though the
  platform permits it: on GitHub the *Resolve conversation* button is
  available to the author, and a rule that accepted it would let an author
  clear a `(blocking)` comment against themselves.
- **Approve when no unresolved comment carries `(blocking)`.**

Two consequences worth stating in the prose, because they are what a reader
will actually ask:

- The motivating question now has an answer. An unresolved `suggestion:`
  blocks approval **only if it carries `(blocking)`** — and a reviewer who
  meant it to block and did not say so has written the comment wrong, which is
  a thing the kit already tells them is their job rather than the linter's.
- Withholding approval is still the reviewer's to do for any reason. This rule
  governs when a *comment* stops a merge, not when a *reviewer* does.

### What this deliberately gives up

Per-label nuance. The specification calls some labels non-blocking by nature
and makes others prerequisites for acceptance, and a design that encoded that
would be a closer reading of it. Constraint 1 forbids writing that reading
down anywhere but the conventions file, and constraint 7 forbids putting it in
a new key there. The nuance is not rejected on its merits — it is unreachable
from where this repository stands, and the mandatory-label clause above is the
one place the gap was too wide to leave open.

## Rejected alternatives

**Option B — blocking by default.** It ties Option A on every scorable
criterion, so it is rejected on the documented judgment call above rather than
against a table row; claiming a row would be the fourth instance of the error
this document has already made three times. Its merit is real, and it is
larger than the tie suggests: it fails safe, and it would not need the
mandatory-label clause at all, because a spec-mandatory comment would block
without anyone remembering anything. That is the right trade for a small team
reviewing a few careful commits a week, and the wrong one for the high-volume
agent-authored workflow this kit exists to serve.

**A per-label blocking-class table, in prose or in a new `review:` key.**
Eliminated before the table because it is not shippable under either
placement: in prose it is the second list of labels `CLAUDE.md` calls a bug
(constraint 1), and in a new YAML key it never reaches a repo that has already
adopted the kit, because `install.sh:150` routes the conventions file through
`install_file()` while `install.sh:145-146` refreshes the Skill
unconditionally (constraint 7). Note that the *inertness* argument earlier
drafts used against a `review:` key does not hold — `comment_labels` is
equally inert — so constraint 7 is doing all the work here. This is the design
most readers will reach for first, and both failure modes are invisible unless
you read `CLAUDE.md` and `install.sh` respectively.

## Risks and rollback

| Risk | Mitigation / rollback |
|---|---|
| A serious comment is left undecorated and does not block, so a real problem merges | Accepted, and it is the cost the Decision names. The reviewer still holds their approval, so the recovery is immediate and belongs to the person who made the omission |
| A spec-mandatory comment is left undecorated, contradicting the specification the kit implements | The mandatory-label clause exists for exactly this and is stated as a declared departure. Residual: it depends on the reviewer knowing the spec's own text for the label they chose |
| **An automated merge is the one consumer this design does not address.** The kit ships hooks that gate pushes, and this user's workflow includes an auto-merge path | Named, not solved. The rules speak about approval, and an automated merge acts as an approval, so the same condition applies — but nothing reads the comments to apply it. Treat this as the strongest candidate for the automated-checking non-goal when it is taken up |
| **The rules never reach Codex-side reviewers in repos that already had an `AGENTS.md`.** `install.sh:157` skips an existing file | Accepted as a stated limitation, with the user's confirmation. `install.sh:227-234` already warns at install time that such a repo's `AGENTS.md` is not told about the conventions |
| **A repo that installed cleanly at an earlier version has an `AGENTS.md` that will never be refreshed**, so its Claude and Codex reviewers could answer the same question differently | Distinct from the row above. Out of scope to fix, but named so it is not discovered as a surprise; it is the strongest argument for taking up the `AGENTS.md` upgrade path next |
| Agents produce formulaic praise, which the spec calls damaging | Praise is guidance rather than a gate precisely so there is no incentive to manufacture it, and the sincerity warning is part of the rule |
| Nothing enforces any of this | Accepted and stated plainly; constraint 3 forbids implying otherwise |

**Rollback.** Revert the commit. Four prose files change, the conventions file
is untouched, and the enforcement layer parses none of it:
`commitlint.config.js` reads only `commit_types` and `scopes`,
`.githooks/pre-push` reads only `branch_types`. No data, no generated
artifact, no adopter migration.

## Verification plan

1. **`npm test` passes.** `tests/drift_test.js` proves `SKILL.md` and
   `AGENTS.md` still match their twins — the whole mechanical surface this
   design has, because it adds no list and therefore no list to check.
2. **The pair check bites on the new text.** Edit the review section in
   `SKILL.md` only, confirm `drift_test` goes red, and revert — the standard
   this repo holds its tests to, applied to the lines actually being added.
3. **The re-install path is exercised, not assumed.** Install into a throwaway
   repo from `main`, re-install from this branch over it, and confirm the
   conventions file is reported as skipped while the Skill is refreshed. The
   rules must read correctly in that state, which is why they depend on no
   YAML key.
4. **The motivating question is answerable.** Give a fresh agent only
   `SKILL.md` and an unmodified conventions file and ask: *does an unresolved
   `suggestion:` comment block approval?* It succeeds if the answer is "only
   if it carries `(blocking)`" and fails if the agent guesses or hedges. Then
   ask two more the rules must answer without a list: *does an unresolved
   `security:` comment block approval?* — naming a label the kit does not ship,
   where the same answer must come back — and *can the author resolve a
   `(blocking)` comment themselves?*, where the answer must be no.
5. **Failure signal, with a trigger.** At the next change to this kit, read the
   last ten merged pull requests here and count two things: reviews with no
   praise comment, and comments whose author plainly meant them to block but
   did not decorate. Either being common means the knowledge layer is not
   landing, and the answer is to revisit the design — not to add a second
   layer of prose saying it more loudly.
