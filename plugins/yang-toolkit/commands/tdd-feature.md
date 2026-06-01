---
description: TDD-driven feature workflow. Either continues from an in-flight /yang-toolkit:feature-dev-tracked session, picks up an explicit slug, or starts fresh. Enforces red -> green -> refactor cycles, writes a tdd-cycles log, and finishes with the standard ledger summary.
---

# /yang-toolkit:tdd-feature

You are running the **TDD-discipline** feature workflow. This is a sibling to
`/yang-toolkit:feature-dev-tracked`; the two share the same decision-doc
directory and ledger schema, so they're interoperable.

## Harness root (worktree-aware)

Durable state (the ledger) must live in the MAIN git worktree so it survives
worktree deletion and is shared across worktrees. Resolve it once:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command is empty or this is not a git
repo, fall back to `<HARNESS_ROOT>` = `${CLAUDE_PROJECT_DIR}`. In the main
worktree these are identical, so non-worktree users see no change.

Use `<HARNESS_ROOT>` ONLY for `<HARNESS_ROOT>/.claude/ledger.jsonl`. Keep
everything else -- `docs/decisions/...` and
`.claude/state/current-feature.txt` -- on `${CLAUDE_PROJECT_DIR}` (decision
docs belong with the feature branch).

## The hard rule

Every production code change in this workflow must be **driven by a failing
test that you have already shown to the user as failing**. The order is
non-negotiable:

1. **Red** -- write the test, run it, show it failing for the right reason.
2. **Green** -- write the smallest production code to make the test pass.
3. **Refactor** -- clean up either the test or production code (or both);
   the test must still pass after.

If a step would write production code WITHOUT a failing test pointing at it,
stop and ask the user. The only legitimate skip is when the user explicitly
says `--no-tdd` or "this cycle is exploratory only" in their prompt.

## Three entry modes

### Mode A -- continue from feature-dev-tracked (most common)
Triggered when:
- `$ARGUMENTS` is empty OR is exactly `--continue`
- `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` exists and is non-empty

Read the slug from `current-feature.txt`. Find the matching decision dir:

```
${CLAUDE_PROJECT_DIR}/docs/decisions/*-<slug>/
```

If multiple dates match (re-using a slug), pick the most recent. If none match,
fall back to Mode C asking the user for a fresh description.

Read every `0X-*.md` already in that directory. Show the user a 5-bullet
summary of what was decided, ask: "Continue this feature with TDD?"

If yes -> proceed to **Step 1 below**, numbering subsequent files starting
from the next index after the highest existing `0X-` prefix.

### Mode B -- explicit slug (resume an older feature)
Triggered when:
- `$ARGUMENTS` matches `--from <slug>` (no quotes, kebab-case)

Treat `<slug>` as the canonical slug. Locate
`${CLAUDE_PROJECT_DIR}/docs/decisions/*-<slug>/`. If not found, abort with
"no such feature; check `ls docs/decisions/`".

If the dir already contains `05-summary.md`, REFUSE: the feature has been
summarized; TDD against it would mean writing post-hoc tests, not driving
new design. Suggest the user open a new feature with a new slug.

Otherwise: same as Mode A from "Read every `0X-*.md` ..." onward.

### Mode C -- fresh feature, no prior feature-dev-tracked
Triggered when:
- `$ARGUMENTS` is a natural-language description (not `--continue`, not
  `--from <slug>`)

Derive a kebab-case `slug` from the description (same rule
feature-dev-tracked uses, so the slugs are deterministic).

Compute `today = YYYY-MM-DD` (UTC). Create
`${CLAUDE_PROJECT_DIR}/docs/decisions/{today}-{slug}/`.

Write the current-feature pointer:
`${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` <- bare slug.

Then run a **mini-discovery** + **mini-architecture** (kept short -- if the
user wanted deep planning they'd have used feature-dev-tracked):

- `01-discovery.md` (brief: what's being built, where in the codebase)
- `02-architecture.md` (brief: what's the smallest design that supports
  the upcoming test cases)

Then continue to Step 1 below.

## Procedure -- the TDD loop

### Step 1 -- test plan
Write `02b-test-plan.md` (always `02b` regardless of which mode you came from;
this slots between architecture and the first cycle).

Content:
- A numbered list of test cases that will drive the implementation
- For each: one-line description + the behavior it pins down
- Order them from "highest leverage / most fundamental" to "edge case"

Show the plan to the user. Ask: "ready to start cycling?" Wait for `yes` or
edits. Apply edits, re-show, repeat until yes.

### Step 2 -- red-green-refactor cycles

For each test case in the plan, in order:

1. **Red**:
   - Write the test in the appropriate test file (`*.test.ts`, `*_test.go`,
     `*_spec.rb`, etc. -- match repo convention).
   - Run the test command (`npm test`, `pytest`, `go test`, `rspec`, etc.).
   - **Confirm the test fails AND fails for the right reason** (not a syntax
     error, not a missing import). Quote the failure output.
   - If the failure is wrong-reason, fix the test before continuing.

2. **Green**:
   - Write the smallest production code that makes this test pass.
   - Run the test command. Quote the passing output.
   - If other tests broke, revert / fix until everything is green.

3. **Refactor** (optional but offer it):
   - Suggest a small refactor (rename, extract, deduplicate). The test must
     still pass after.
   - If nothing to refactor, say so and move on.

Each cycle appends one line to `03-tdd-cycles.md`. Schema (markdown table):

```
| # | test name                             | red ts              | green ts            | refactored?                    |
|---|---------------------------------------|---------------------|---------------------|--------------------------------|
| 1 | `BookingPolicy refuses past dates`    | 2026-05-28T03:14Z   | 2026-05-28T03:21Z   | yes -- extracted PolicyClock   |
```

The file should be initialized with this header on the FIRST cycle.

After all planned cycles complete, ask the user: "test plan done. New cycles
needed (you spotted new cases mid-flow)?" If yes, extend the plan and continue;
if no, proceed to Step 3.

### Step 3 -- review and summary

- Run `/code-review` (from `code-review` plugin). Capture findings into
  `04-review.md`. Apply fixes if user accepts; if the fixes are non-trivial,
  start new cycles for them (don't blindly Edit production code without a
  failing test).
- Write `05-summary.md`:
  - what shipped
  - test count, cycle count
  - what was abandoned and why (if anything)
  - open follow-ups

### Step 4 -- ledger append

Append ONE line to `<HARNESS_ROOT>/.claude/ledger.jsonl`:

```
{
  "ts":       <ISO8601 now, UTC>,
  "feature":  "<slug>",
  "phase":    "summary",
  "agent":    "<whoever ran most cycles, or 'main' if Claude main thread>",
  "outcome":  "in-progress",
  "files":    <distinct files touched>,
  "tokens":   <approx, 0 if unknown>,
  "tools":    { "<tool>": <count>, ... },
  "cycles":   <number of completed red-green-refactor cycles>,
  "pr":       null,
  "commit":   null
}
```

The `cycles` field is a TDD-only extension to the ledger schema. The dashboard
will treat it as optional (default 0 for non-TDD features). Outcome stays in
the controlled set `in-progress | merged | abandoned | failed`.

### Step 5 -- clean up and report

- Clear `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` (delete or
  truncate to empty).
- Tell the user:
  - decision dir path
  - cycle count
  - test count
  - that one ledger entry was appended

## Edge cases

| Situation                                                   | Behavior                                                                                                                                |
| ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| User said `--no-tdd` in args                                 | Hard error: "you ran tdd-feature with --no-tdd; use /yang-toolkit:feature-dev-tracked instead". Do NOT silently skip TDD.             |
| Repo has no test framework detected                          | Abort Mode C; suggest user set up testing first OR use feature-dev-tracked. In Mode A/B, ask the user which command sets it up.        |
| User wants to skip Red on one specific cycle                 | Ask for explicit confirmation ("are you adding code without a test?"). If user re-confirms, log it in `03-tdd-cycles.md` with `red: skipped (user override)` and a one-line reason. |
| Mid-cycle interruption (Ctrl-C, session crash)               | Files-on-disk are authoritative. Re-running tdd-feature should detect the partial state and offer to "resume from cycle N+1".          |
| User starts in Mode C but `current-feature.txt` already exists | Warn: "another feature is in flight (<existing slug>). Finish or cancel that one first." Refuse unless `--force` passed.               |

## Failure modes

- Cannot write to `docs/decisions/...`: abort with a clear message before
  touching production code.
- Test command fails for environmental reason (e.g., DB not running): pause,
  ask user to fix, don't start cycling until tests are runnable.
- The user goes silent during a cycle: do NOT silently move on. TDD requires
  per-cycle confirmation that red is "the right red".
