---
slug: heartbeat-loop
created_at: 2026-06-26T07:29:29Z
discipline: normal
orchestration: single
team_size: 3
time_budget: 25 turns
depends_on: []
status: done
started_at: 2026-07-06T03:10:14Z
finished_at: 2026-07-06T03:15:40Z
executor: 3bd17aca-9112-4822-bb8d-b2866d5851d5
---

# Goal
Add a toolkit-native `/yang-toolkit:loop` command: a self-paced in-session
"heartbeat" that each tick auto-discovers the next runnable plan, hands it to
`/yang-toolkit:execute-plan` behind an objective verification gate, persists the
outcome, and arms the next wake-up — propose-only by default, with a hard
token-budget cap, goal-drift mitigation, and a documented kill switch.

# Acceptance Criteria
<!-- machine-parsed by /yang-toolkit:execute-plan. Each item MUST follow:
- [ ] **<short name>**
  - Check: `<runnable command in backticks>`
  - Pass: <observable condition; no fuzzy words>
-->

- [ ] **Command exists with native structure**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; test -f "$f" && head -1 "$f" | grep -q '^---$' && grep -q '^# /yang-toolkit:loop' "$f" && grep -q '^## Conventions' "$f" && grep -q '^## Inputs' "$f" && grep -qE '^## Step 1' "$f" && echo OK`
  - Pass: prints `OK` (file present; frontmatter opens with `---`; H1 is `# /yang-toolkit:loop`; has `## Conventions`, `## Inputs`, and at least `## Step 1`).

- [ ] **Frontmatter is description-only native shape**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; awk '/^---$/{n++; next} n==1{print}' "$f" | grep -vqE '^(description:|model:)' && echo HASEXTRA || echo CLEAN`
  - Pass: prints `CLEAN` (frontmatter contains only `description:` and optionally `model:` keys — no invented `name`/`argument-hint`/`allowed-tools`).

- [ ] **Conventions referenced, not re-spelled**
  - Check: `grep -q 'references/conventions.md' plugins/yang-toolkit/commands/loop.md && echo OK`
  - Pass: prints `OK`.

- [ ] **Discovery is plans-only and reuses the status signal**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; grep -q '.claude/plans' "$f" && grep -qiE 'accepted|draft' "$f" && grep -qiE 'plans only|plans-only|only.*plan' "$f" && echo OK`
  - Pass: prints `OK` (Discovery step scans `.claude/plans/` for accepted/draft plans and states the plans-only v1 scope).

- [ ] **Objective verification gate, not LLM self-grading**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; grep -qiE 'acceptance criteri|Check command|criteria_pass|objective' "$f" && grep -qiE 'not.*self-?grad|not.*LLM' "$f" && echo OK`
  - Pass: prints `OK` (the Verify step requires running the plan's acceptance-criteria Check commands and explicitly forbids LLM self-grading as the gate).

- [ ] **Hard token-budget cap distinct from the turn cap**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; grep -qiE 'token budget|token cap|--max-tokens|token.*cap' "$f" && grep -qiE 'Ralph Wiggum|false.?completion|abort' "$f" && echo OK`
  - Pass: prints `OK` (documents a hard token-budget cap that aborts the loop, named as the Ralph-Wiggum / false-completion guard, separate from any turn limit).

- [ ] **Loop state file specified for cross-tick budget tracking**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; grep -qE 'loop-state|loop_state|loop-state.json' "$f" && grep -qiE 'iteration|tokens_spent|spent' "$f" && echo OK`
  - Pass: prints `OK` (a loop-state file holding at least an iteration counter and accumulated token/cost spend is specified, with its durable-vs-ephemeral home named).

- [ ] **Goal-drift mitigation: re-read base files each tick**
  - Check: `grep -qiE 're-?read.*(each|every)|(each|every).*tick.*re-?read' plugins/yang-toolkit/commands/loop.md && echo OK`
  - Pass: prints `OK` (each iteration re-reads conventions.md / the target plan rather than trusting drifting context).

- [ ] **Propose-only default with --unattended opt-in**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; grep -q '\-\-unattended' "$f" && grep -qiE 'propose-only|propose only|by default.*(stop|propose|suggest)' "$f" && grep -qiE 'opt-?in|never.*silent' "$f" && echo OK`
  - Pass: prints `OK` (default tick proposes/queues and stops; `--unattended` is the opt-in for auto execution and is never entered silently).

- [ ] **Kill switch documented**
  - Check: `grep -q 'CLAUDE_CODE_DISABLE_CRON' plugins/yang-toolkit/commands/loop.md && grep -qiE '\bEsc\b' plugins/yang-toolkit/commands/loop.md && echo OK`
  - Pass: prints `OK` (both `CLAUDE_CODE_DISABLE_CRON` and `Esc` named as stop controls).

- [ ] **Stop-hook double-write addressed**
  - Check: `f=plugins/yang-toolkit/commands/loop.md; grep -qiE 'current-feature' "$f" && grep -qiE 'double|stop-?hook|already append' "$f" && echo OK`
  - Pass: prints `OK` (the command explains how it avoids the Stop hook double-appending a ledger entry per tick given the `current-feature.txt` gate).

- [ ] **README lists the command**
  - Check: `grep -q 'yang-toolkit:loop' README.md && echo OK`
  - Pass: prints `OK` (the new command appears in the README command inventory / cheat sheet).

# Files Touched
- `plugins/yang-toolkit/commands/loop.md`            (new — the command spec)
- `plugins/yang-toolkit/references/conventions.md`   (add loop-state file to the durable/ephemeral split + any `loop_*` ledger extension fields)
- `README.md`                                        (list `/yang-toolkit:loop` in the contents + Anytime cheat-sheet)

# Out of Scope
- Cloud Routines (`/schedule`) and Desktop scheduled tasks as substrates — v1 is in-session self-paced `/loop` + `ScheduleWakeup` only. The tick body is written substrate-agnostic, but only the in-session arming path is specified/tested.
- Broader Discovery signals (open PRs needing rework, failing CI, pending `claude-md-candidates`, in-flight `current-feature.txt` continuation) — a later iteration.
- Any new ledger `outcome` value or dashboard change — the loop reuses the existing controlled vocabulary (new outcomes would require touching `skills/dashboard/SKILL.md` + `dashboard.html` first).
- Actually arming/running a live heartbeat against this repo — the deliverable is the command spec, mirroring how the other commands ship.

# Risks
- **Stop-hook double-write.** `hooks/append-ledger.sh` already appends an `in-progress`/`source:"stop-hook"` entry whenever `current-feature.txt` is non-empty. A naive loop that sets `current-feature.txt` would ledger twice per tick (its own record + the hook's). The command must reconcile this — e.g. let the Stop hook own the per-tick recency entry and have the loop write only on a state transition, or scope its own append to avoid overlap.
- **Name collision with the generic `/loop` skill.** A harness-level `/loop` already exists ("run a prompt on a recurring interval"). `/yang-toolkit:loop` must differentiate in its `description` as the plan/ledger-aware variant so users don't confuse them.
- **No built-in hard token cap (Probe 3).** Claude Code has no per-run token-budget abort; the cap is build-yourself and only as accurate as the cost signal we persist (e.g. `total_cost_usd` via `--output-format json`, or an approximate running counter). Treat the cap as best-effort and fail safe (stop) when the signal is unavailable.
- **In-session loops die on session close (Probe 3).** Self-paced `/loop` only survives via `--resume` within the 7-day task expiry. The command should document this limitation rather than imply always-on operation.
- **`/schedule` is disabled when `ANTHROPIC_API_KEY` is set (Probe 3).** Not relevant to the chosen in-session substrate, but worth a one-line note so a future "promote to cloud" iteration doesn't trip on it.

# Memory References
<!-- auto-generated below; remove individual lines if irrelevant.
Lines without <!--auto--> are preserved on --revise.
<type> is one of: ledger | decision | claude-md | plan | pattern | external.
For [external], <path> is a URL. -->

- <!--auto--> [pattern] plugins/yang-toolkit/commands/execute-plan.md — orchestrator template to mirror: `$ARGUMENTS` flag parsing, `/goal` assembly (≤4000 chars, user-confirm before issuing), `--auto` opt-in (never silent, :153-173), the 50-turn self-stop (:374), and the one-record ledger close-out (:318-333).
- <!--auto--> [pattern] plugins/yang-toolkit/commands/status.md — the four in-flight signals (:15-37); v1 Discovery reuses the plan-status scan (:20-24) and `current-feature.txt` read (:19).
- <!--auto--> [pattern] plugins/yang-toolkit/workflows/execute-plan-team.workflow.js — Phase 2 (:140-158) runs each acceptance-criterion Check command unmodified and reports pass/fail only; this is the objective verification seam the loop's gate mirrors.
- <!--auto--> [pattern] plugins/yang-toolkit/references/conventions.md — `<HARNESS_ROOT>` resolution, durable-vs-ephemeral path split (:21-26), ledger schema + outcome rules (:27-59), and the Read+Write append rule (:61-69) the command must obey (hooks are exempt; commands are not).
- <!--auto--> [pattern] plugins/yang-toolkit/hooks/append-ledger.sh — Stop-hook gate: appends only when `current-feature.txt` is non-empty (:29-35), tagging `source:"stop-hook"`; the source of the double-write risk above.
- <!--auto--> [external] https://code.claude.com/docs/en/tools-reference.md — `ScheduleWakeup` reschedules the next self-paced `/loop` iteration (delay 1 min–1 hr, called at end of each tick, surfaces in Stop-hook `session_crons`); `CronCreate` is fixed-cron, 5-field, 7-day expiry, 50/session.
- <!--auto--> [external] https://code.claude.com/docs/en/routines.md — cloud Routines (`/schedule`): 1-hour minimum, persistent, but run in a fresh clone with NO local file access — the reason v1 stays in-session rather than going cloud.
- <!--auto--> [external] https://code.claude.com/docs/en/permission-modes.md — `--permission-mode auto` / `acceptEdits` and the auto-mode classifier; the mechanism `--unattended` would lean on, with `permissions.deny` as the hard pre-classifier gate.
- <!--auto--> [external] https://code.claude.com/docs/en/scheduled-tasks.md — `CLAUDE_CODE_DISABLE_CRON=1` is the documented hard kill switch (disables the scheduler and stops already-scheduled tasks mid-session); `Esc` cancels a pending wake-up.

# Execution Log
<!-- filled by /yang-toolkit:execute-plan post-hoc. Leave empty in draft. -->

## Run 1
- **started_at**: 2026-07-06T03:10:14Z
- **finished_at**: 2026-07-06T03:15:40Z
- **duration**: ~5m 26s
- **outcome**: done
- **orchestration**: single (discipline: normal)
- **downstream**: ran inline as the single-mode completion-gated loop. `/goal`
  could not be issued programmatically (it is a user-facing slash command, not
  an agent tool), and delegating to `/yang-toolkit:feature-dev-tracked` would
  have written per-phase decision docs under `docs/decisions/`, tripping this
  plan's own "no files outside Files Touched" scope guard. So the orchestrator
  authored the three Files Touched directly and then evaluated the plan's
  acceptance-criteria Check commands as the objective gate -- the same
  verification `/goal` would have run.
- **acceptance criteria**: 12/12 Check commands pass (verified via the plan's
  own Check commands, run verbatim). One fuzzy-lint false positive was overridden
  during validation: criterion 2's Pass `prints CLEAN` -- `CLEAN` is a literal
  Check-output sentinel (`... || echo CLEAN`), not the vague quality word.
  Initial run failed criterion 1 only (`^## Step 1` expects an H2 heading; the
  tick steps were first written as `### Step N`); fixed by promoting the five
  tick steps to `## Step N`, after which all 12 passed.
- **scope guard**: clean. Working-tree changes limited to the three Files
  Touched (`commands/loop.md` new; `references/conventions.md` + `README.md`
  modified). No Out-of-Scope items introduced (no `/schedule` or Desktop
  substrate; no broader Discovery signals; no new ledger outcome / dashboard
  change; no live heartbeat armed against this repo).
- **goal_turns**: n/a (no `/goal` evaluator loop; ran inline).
