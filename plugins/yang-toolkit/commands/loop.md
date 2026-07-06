---
description: Plan/ledger-aware in-session heartbeat. Each tick auto-discovers the next runnable plan, hands it to /yang-toolkit:execute-plan behind an objective acceptance-criteria gate, persists the outcome, and arms the next wake-up. Propose-only by default; --unattended opts into auto execution. Hard token-budget cap, goal-drift mitigation, documented kill switch.
---

# /yang-toolkit:loop

A self-paced in-session **heartbeat** that replaces you sitting there typing
"do the next thing". Each tick it finds the next runnable plan, runs it behind
the same objective verification gate `/yang-toolkit:execute-plan` uses, records
what happened in the ledger, and schedules the next wake-up with
`ScheduleWakeup`. It stops the moment there is no runnable work, the token
budget is exhausted, or you hit the kill switch.

This is the plan/ledger-aware variant of the generic harness `/loop` skill.
The generic `/loop` re-runs an arbitrary prompt on a fixed interval and knows
nothing about your plans or ledger; `/yang-toolkit:loop` is opinionated: its
unit of work is a plan artifact, its completion test is that plan's acceptance
criteria, and its accounting lands in `ledger.jsonl`. Reach for the generic one
to poll a build; reach for this one to grind down a plan backlog.

## Conventions

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` first -- it defines
`<HARNESS_ROOT>` resolution, the durable-vs-ephemeral path split, the ledger
schema, and the Read+Write append rule. Plans and the ledger live under
`<HARNESS_ROOT>`; `current-feature.txt` and the loop-state file stay on
`${CLAUDE_PROJECT_DIR}`. This command references those definitions rather than
restating them -- keep them in one place.

## Inputs
- `$ARGUMENTS` -- empty, or any combination of:
  - `--unattended` -- opt into auto execution AND the recurring heartbeat: each
    tick actually runs the selected plan and arms the next wake-up. Without it
    the loop is propose-only and one-shot. Never entered silently (see
    "Propose-only vs --unattended").
  - `--max-tokens <N>` -- hard token-budget cap for the whole loop across all
    ticks (see "Token budget cap"). Default: 200000 (a conservative built-in
    ceiling; a single unattended plan run can spend a large fraction of it).
  - `--interval <dur>` -- hint for the next wake-up delay (1 min -- 1 hr). The
    loop is self-paced; absent this it picks a delay itself.
  - `--once` -- run exactly one tick, then stop (do not arm a wake-up). Useful
    for dipping a toe in before committing to a standing heartbeat.
  - `--dry-run` -- run Discovery + Select and print what the next tick WOULD do
    (plan, gate, budget), but change no state and arm no wake-up.

## How the loop is built (the four minimum-viable pieces)

One automation (the `ScheduleWakeup` heartbeat) + one skill (the plan +
`execute-plan` it delegates to) + one state file (the loop-state file below) +
one gate (the plan's acceptance criteria). Everything else is safety rails on
top of those four.

## The tick

One iteration of the heartbeat runs the five steps below in order.

## Step 1 -- Discovery (plans-only, v1)

Scan `<HARNESS_ROOT>/.claude/plans/*.md`, read frontmatter only, and collect
every plan whose `status` is `accepted` or `draft` -- these are the runnable
ones. Reuse the exact status signal `/yang-toolkit:status` surfaces; do not
invent a second source of truth. **v1 is plans-only**: the loop's only unit of
work is a plan artifact under `.claude/plans/`. Broader discovery signals (open
PRs needing rework, failing CI, pending `claude-md-candidates`, an in-flight
`current-feature.txt` continuation) are explicitly out of scope for v1 and
listed below.

Also read `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`: if it is
non-empty, a feature is already in flight -- prefer resuming that plan over
starting a new one, and never start a second one on top of it.

## Step 2 -- Select

Pick one runnable plan. Order: an in-flight `current-feature.txt` slug first,
else the oldest `accepted`, else (propose-only only) the oldest `draft`. Skip
any plan whose `depends_on` chain is unmet (let `execute-plan` be the authority
on that).

**`--unattended` runs `accepted` plans only.** A `draft` is by definition not
yet reviewed, so it is never auto-executed: unattended selection filters to
`accepted`, and any `draft` is surfaced as a proposal for you to accept first.
This keeps the human on the accept/reject decision, per the "don't let the loop
touch judgment work" rule. Propose-only mode may surface a `draft`; it just will
not run it.

If nothing is runnable, the backlog is empty -- **stop the loop** and report; do
not arm another wake-up to spin on an empty queue.

## Step 3 -- Execute behind the objective gate

Hand the selected plan to `/yang-toolkit:execute-plan --from <slug>` (in
`--unattended` mode, `... --from <slug> --auto`, so execute-plan's own `/goal`
loop runs without per-turn prompts). The completion test is that plan's
**acceptance criteria**: each criterion's `Check` command is run and its `Pass`
condition observed. The gate is these Check commands -- **not LLM self-grading**.
An agent (this loop included) declaring "done" in prose is never the gate; a
green Check command is. This is the Ralph-Wiggum / silent-failure guard at the
correctness layer: without an objective, runnable pass condition a loop will
happily announce success and keep burning tokens on nothing.

**Known seam (v1).** execute-plan's own Step 3 asks you to confirm the assembled
`/goal` condition before it runs, and that confirmation is interactive even
under `--auto` (auto mode removes per-tool prompts, not this deliberate
guardrail). So a `--unattended` tick still pauses once per plan at that single
confirm. Closing it fully needs a non-interactive flag on execute-plan (e.g. a
future `--yes`) that does not exist yet; until then, "unattended" means "no
per-turn / per-tool prompts", not "zero prompts". Documented rather than faked.

In propose-only mode (the default) this step stops before mutating anything --
see below.

## Step 4 -- Persist outcome

`execute-plan` already appends the authoritative per-run ledger record and
updates the plan's `status` / `Execution Log`. This loop does **not** duplicate
that write. It only updates the loop-state file (Step 5) with the tick result
so the next tick, or a resumed session, can continue rather than restart.

## Step 5 -- Budget check + arm the next wake-up

Add this tick's spend to the loop-state file and compare against `--max-tokens`.
**Only `--unattended` arms a wake-up at all** -- propose-only is one-shot and
stops here (it proposed; the ball is in your court). In unattended mode, if
there is budget remaining and runnable work left, call `ScheduleWakeup`
(honoring `--interval`) to fire the next tick; if `--once` was passed, run this
one tick and stop without arming. Whenever the loop halts, record why in the
loop-state `stopped_reason` (`empty-backlog` / `budget-exhausted` /
`kill-switch` / `once`). Re-read the loop-state file at the START of every tick
so budget accounting survives a session resume.

## Loop-state file

`${CLAUDE_PROJECT_DIR}/.claude/state/loop-state.json` -- branch-local and
ephemeral, living alongside `current-feature.txt` (a standing heartbeat is tied
to one working session; it is not durable cross-worktree state, so it does NOT
belong under `<HARNESS_ROOT>` with the plans and ledger). It holds at least:

```
{
  "iteration":      <int>,      // tick counter, incremented each tick
  "tokens_spent":   <int>,      // accumulated approx token/cost spend across ticks
  "max_tokens":     <int|null>, // the cap from --max-tokens, for resume
  "last_slug":      "<slug|null>",
  "last_outcome":   "<in-progress|merged|abandoned|failed|null>", // ledger vocab
  "unattended":     <bool>,
  "stopped_reason": "<empty-backlog|budget-exhausted|kill-switch|once|null>"
}
```

Written via the Read+Write append rule (never shell redirection), same as the
ledger. It is the memory that lets each tick continue instead of starting over.

## Token budget cap (Ralph-Wiggum guard)

`--max-tokens <N>` is a **hard token-budget cap** for the entire loop, tracked
cumulatively in `tokens_spent` across every tick and checked in Step 5. When
`tokens_spent >= max_tokens` the loop **aborts**: it arms no further wake-up and
reports the overrun. This cap is deliberately **separate from any per-run turn
limit** (e.g. execute-plan's 25-turn / 50-turn self-stop): the turn cap bounds a
single plan run; this token cap bounds the standing heartbeat across all of
them. It is the money-pit backstop for the "loop quietly declares success and
keeps spending" (Ralph-Wiggum / false-completion) failure mode. Claude Code has
no built-in per-run token abort, so treat the cap as best-effort: if the cost
signal is unavailable, fail safe and stop rather than run uncapped.

## Propose-only vs --unattended

**Default is propose-only, and one-shot.** A tick runs Discovery + Select, then
STOPS and reports the plan it would run and the gate it would check -- it queues
the work, hands control back to you, and does NOT arm a recurring wake-up.
Default `/yang-toolkit:loop` therefore answers "what would the heartbeat do
next?" exactly once; it does not itself become a standing heartbeat. This keeps
a human on architecture-, auth-, and money-touching decisions.

`--unattended` is the explicit opt-in that (a) lets a tick actually execute the
selected plan end to end and (b) arms the recurring heartbeat. It is **never
entered silently**: the flag must be passed, and the loop echoes that it is
running unattended on the first tick. Even unattended, the objective gate and
the token cap still apply.

**The hard floor is `permissions.deny`.** Auto mode's classifier and this loop's
propose-only default are soft guards; the non-negotiable gate is the
`permissions.deny` list in settings -- a denied tool cannot run even under
`--auto --unattended`. Treat an unattended loop as an unattended attack surface
(the article's "security tax"): scope `permissions.deny` to forbid anything that
touches auth, money, or secrets before arming one, and keep `--max-tokens` tight
so a runaway is bounded in cost as well as in blast radius.

## Goal drift

Long-running loops drift as context accumulates and the original intent blurs.
Mitigation: **re-read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` and the
target plan at the start of each tick** rather than trusting the drifting
in-context copy. Every tick re-grounds itself in the on-disk source of truth
before it acts.

## Stop-hook double-write

`hooks/append-ledger.sh` already appends a supplementary `source:"stop-hook"`
ledger entry whenever `current-feature.txt` is non-empty at session stop. If
this loop also wrote its own per-tick ledger record while `current-feature.txt`
was set, the ledger would be **double**-appended per tick. It avoids this by not
writing ledger records itself at all: the authoritative per-run record is
`execute-plan`'s (Step 4), and the Stop hook owns the recency entry. The loop
touches only the loop-state file, so there is no overlap and nothing is appended
twice.

## Kill switch

Two documented stops:
- **`Esc`** cancels the currently pending `ScheduleWakeup`, ending the loop
  after the current tick without arming the next.
- **`CLAUDE_CODE_DISABLE_CRON=1`** hard-disables the scheduler entirely,
  stopping already-scheduled wake-ups mid-session -- the nuclear option.

## Out of scope (v1)

- Cloud Routines (`/schedule`) and Desktop scheduled tasks as substrates -- v1
  is in-session self-paced heartbeat via `ScheduleWakeup` only. In-session loops
  die on session close (they survive only via `--resume` within task expiry);
  this is a documented limitation, not an always-on guarantee.
- Broader Discovery signals beyond `.claude/plans/` (open PRs, failing CI,
  `claude-md-candidates`, `current-feature.txt` continuation as a first-class
  source) -- a later iteration.
- Any new ledger `outcome` value or dashboard change -- the loop reuses the
  existing controlled vocabulary via `execute-plan`.
