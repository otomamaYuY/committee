# Measuring the knowledge layer

The enforcement layer is easy to test: a hook either rejects a commit or it
does not, and `tests/install_test.sh` drives real `git commit` calls to prove
which. The knowledge layer had no equivalent. Its claim — that an agent
reading `SKILL.md` or `AGENTS.md` comes away able to apply the conventions —
was the one load-bearing thing in this repository nothing measured.

This directory measures it.

## What it does

`knowledge-layer/run.js` copies **only** a knowledge file and
`.claude/git-conventions.yaml` into an empty directory outside this
repository, hands an agent one question at a time, and grades the first line
of the reply against `knowledge-layer/cases.yaml`.

Two properties make it a measurement rather than a demonstration:

- **Isolation.** No `CLAUDE.md`, no git history, no design document, no
  README — nothing but the two files an adopter would actually have. A
  correct answer therefore came from the shipped prose or from nowhere.
- **Mechanical grading.** The first line is `YES`, `NO` or `UNANSWERABLE`, and
  anything else is reported as unparseable rather than interpreted. No model
  judges another model's answer.

Every case runs against **both** `SKILL.md` and `AGENTS.md`. The pair tests in
`tests/drift_test.js` compare each knowledge file with its own `templates/`
twin; nothing compares the two knowledge files with each other. A run that
answers differently for Claude and for Codex is the failure that matters most,
and this is the only thing that would see it.

### The control cases

`cases.yaml` contains questions the files genuinely do not answer, and the
expected result is `UNANSWERABLE`. They are not padding. A model that answers
everything confidently — from what it already knows about Conventional
Comments rather than from the file — scores full marks without them, and the
run would be measuring the model instead of the prose.

## Running it

```bash
npm run eval
```

The responder is `claude -p` by default, which must be authenticated. Override
it with any command that reads a prompt on stdin and writes a reply to stdout:

```bash
COMMITTEE_EVAL_CMD='some-other-agent --print' npm run eval
node evals/knowledge-layer/run.js --only author-resolves --file AGENTS.md
```

**It is deliberately not part of `npm test`.** It needs an agent, it costs
tokens, and it is not deterministic, so it must never be able to fail a pull
request. A failure here is a finding about the prose — one sentence did not
land — not a broken build.

## What *is* in `npm test`

`tests/eval_harness_test.js`, which drives `run.js` with stub responders whose
answers are known in advance and checks that the harness reaches the right
verdict: a perfect responder scores full marks, an always-`YES` responder
fails and fails the controls specifically, a chatty reply is unparseable
rather than guessed at, a responder that cannot start is reported instead of
counted as a pass, and both knowledge files are exercised.

That division is the point. The measurement is manual because it has to be;
the measuring instrument is tested automatically because otherwise a grader
that silently passed everything would look exactly like a knowledge layer that
works.

## Reading a failure

A failing case names the sentence that did not carry. Fix the prose, not the
case — a case that is edited to match what the file happens to say measures
nothing. Adding a case is right when the rules grow a new question they have
to answer; changing an `expect` is right only when the intended rule itself
changed, and then the design document should change with it.

## Recorded runs

| Date | Responder | SKILL.md | AGENTS.md | Notes |
|---|---|---|---|---|
| 2026-09-21 | Claude Opus 5, driven by hand (see note) | 9/9 | 9/9 | First run. Both files agreed on every case, including the two controls, which they correctly refused to answer |

Note on the first run: the `claude` CLI could not authenticate on the machine
used, so the same staged directories and the same prompts were driven through
subagents rather than through `run.js`. The measurement is the one described
above; `run.js` itself was exercised only against stubs that day. Anyone with
a working CLI should re-run it properly and add a row.

A run recorded here is evidence about the prose on that date, not a guarantee
about any other model or any later edit. Re-run it after changing either
knowledge file.
