# Changelog

All notable changes to the **yang-toolkit** plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions track `plugins/yang-toolkit/.claude-plugin/plugin.json`.

## [0.19.0] - 2026-09-15

### Added
- **`/yang-toolkit:go` -- one door for the whole toolkit.** Until now the
  toolkit was one-flow-per-trigger: you had to know that new work means
  `plan-feature`, then review, then `execute-plan`, and that a backlog means
  `loop`. `go` takes any one-line request -- a task, a backlog, or a question --
  picks the owning command and the **smallest sufficient loop**, declares the
  route with its reason, and runs it. Modeled on `straw-boss`'s `boss-say`,
  including its "state the route, don't ask for it" rule (already the toolkit's
  own convention since 0.18.0).
  - **Reads harness state before classifying** (Task 0), because the same
    sentence means different things depending on what is in flight. A **parked**
    plan (`awaiting-input` / `awaiting-auth`, added in 0.18.0) pre-empts
    everything: its question is surfaced first, since the user's message may be
    the answer. In-flight work is the default subject, and a second feature is
    never started on top of one.
  - **Smallest sufficient loop** (Task 2): bounded, locally-verifiable work is
    carried directly with **no plan artifact at all**; a real feature (multi-file,
    needs criteria, spans sessions, or carries migration/auth/data risk) goes to
    `plan-feature`; a backlog goes to `loop`. Not every task deserves a plan --
    that was the straw-boss idea worth taking.
  - **Passthrough, never reimplementation**: status/report/CLAUDE.md/ledger
    requests invoke the command or skill that already owns them. `go` owns no
    artifact format of its own, so there is nothing to drift.
  - **A handoff contract of references, not summaries.** The user's words travel
    verbatim (never pre-summarized -- `plan-feature`'s probes want the raw
    input), and Task 0's findings travel as bare pointers: a slug, a plan slug,
    a backlog path. The receiving command re-reads the source itself, so there
    is one source of truth. A state summary, a pre-picked
    `discipline`/`orchestration`/anchor, and any flag the user did not ask for
    explicitly never travel. `current-feature.txt` is passed anyway even though
    `plan-feature`'s Probe 2 would find related work on its own: that pointer is
    definitive, while Probe 2 scores by token overlap and can mis-rank.
  - Available both as `/yang-toolkit:go` and implicitly, when a one-line
    handover is given with no command named. It deliberately does not trigger
    mid-conversation on a task already underway.
- **Gates are unchanged at the exit.** `go` adds convenience at the entrance and
  no permission anywhere: it never adds `--auto` / `--yes` / `--unattended` on
  its own, never skips the plan-acceptance gate or runs a `draft`, never answers
  or un-parks a waiting question, and never decides a gated mutation. Routing is
  declared because routing is cheap to reverse; none of those are.

- **`/yang-toolkit:execute-plan --answer "<text>"`** -- resume a parked plan with
  an answer the caller already holds, instead of re-presenting the question.
  Without it, `go` routing a user's answer to `execute-plan` would have made the
  command ask the very question the user had just answered. The question and the
  supplied answer are echoed together before resuming (so a misrouted answer is
  visible, not silently absorbed) and both are recorded verbatim in the Execution
  Log. It carries a *user's* answer, never an agent's judgment: it is ignored on
  a plan that is not parked, and an ambiguous reply to an `awaiting-auth` plan
  keeps the plan parked rather than counting as consent to a gated mutation. This
  is also the one case where `--yes` may proceed on a parked plan -- nothing is
  being guessed.

### Fixed
- `/yang-toolkit:status` now groups the two **parked** statuses introduced in
  0.18.0. They previously fell through its `executing`/`accepted`/`draft`/`failed`
  grouping unsorted -- so the one plan actually blocked on the user was the one
  the status screen could fail to mention. Parked plans now lead the section with
  their `waiting.question` verbatim, and "answer it" is the first next-step
  suggestion.

## [0.18.0] - 2026-09-07

Four ideas ported from [straw-boss](https://github.com/wayne930242/straw-boss)
after studying its coordination model.

### Changed
- **Routing is declared, never asked.** straw-boss's "both are stated, not
  asked" rule now governs every routing field. `discipline` is judged from repo
  test evidence and the change's testable seam (rules in `conventions.md`)
  instead of being asked; `orchestration` was already `auto`; both are announced
  in a one-line **route declaration** with their reasons, and the user overrides
  in one sentence. `/execute-plan` no longer offers `--single` when Files
  Touched look overlapping — it states the risk and proceeds. Plan *content*
  (goal, criteria, scope) is unaffected and still reviewed as before.

### Added
- **Reality anchors** on every acceptance criterion — `testing` (default),
  `pseudo-human`, `human`, `adversarial-review`. The anchor fixes the category
  of proof and its checkpoint; the seam, cases, and tool stay with whoever
  implements it ("naming the anchor is not naming the tests"). Machine-checkable
  anchors keep the runnable `Check:` and the fuzzy-word lint; judgment anchors
  replace `Check:` with `Judge:` + `Artifact:` and are exempt from the lint,
  since a person or a review agent — not a regex — is the check. This closes the
  long-standing hole where prose-only work had to invent a fake `Check:`
  command; its honest anchor is `adversarial-review`. A plan whose criteria are
  all judgment checkpoints is valid and skips `/goal` entirely. Criteria with no
  `Anchor:` line are treated as `testing`, so existing plans keep working.
- **Non-terminal parked run states** — `awaiting-input` and `awaiting-auth`,
  with a `waiting:` frontmatter block naming the one question. An unattended run
  that meets a `human` anchor, a substantive work question, or a gated mutation
  now *holds* the decision instead of guessing it or dying as `failed`.
  Answering clears the block and resumes. Neither state writes a terminal ledger
  record — `outcome` stays `in-progress` — so the controlled outcome vocabulary
  is unchanged and the dashboard needs no update. `--yes` deliberately refuses
  to answer a parked question: guessing it is exactly what the state prevents.
  `/yang-toolkit:loop` reports a newly parked plan once and then goes quiet
  (unchanged idleness is confirmation, not a delta), never re-runs or re-charges
  it, and keeps a slow heartbeat rather than stopping, so it resumes the moment
  the question is answered (`stopped_reason: all-parked`).
- **`Stop` checkpoint guard** (`hooks/execution-checkpoint-guard.sh`), ported
  from `dispatched-agent-stop-guard.py`: refuses to let a turn end silently with
  the tracked plan still `status: executing` and no Execution Log entry for the
  run — the exact state that previously stranded a plan and needed
  `/status --abandon` by hand. Terminal (`done`/`failed`) and parked statuses
  pass through untouched. Nudges by default; `HARNESS_STRICT_CHECKPOINT=1`
  blocks the stop so an unattended `/goal` or `/loop` run is forced back in to
  finish the close-out. Re-entrancy safe (`stop_hook_active`); opt-out
  `HARNESS_DISABLE_CHECKPOINT_GUARD=1`.
- Ledger gains optional `anchors` (criteria count per anchor) and `waiting`
  (park kind) fields on execute-plan records.

### Not ported
- straw-boss's **contract digest** (an immutable, SHA-256-verified instruction
  handed to a dispatched worker). It secures a boundary yang-toolkit does not
  have: the toolkit delegates in-session rather than launching separate CLI
  sessions, so there is no cross-process instruction to tamper with.

## [0.17.0] - 2026-08-31

### Added
- **Project house rules** — a shared discovery + delegation protocol in
  `references/conventions.md`. yang-toolkit now behaves as a guest in repos that
  ship their own development workflow (`openspec-*` skills + `/opsx`,
  `ai-sdlc-*` skill sets, project agents): it discovers them from a cheap
  frontmatter-only scan of `.claude/skills/`, `.claude/commands/`,
  `.claude/agents/`, `AGENTS.md`, `.cursor/rules/` and any spec directory, then
  **delegates the phase the project owns** (implementation / review / archive)
  while keeping the plan artifact, acceptance-criteria gate, Execution Log and
  ledger for itself. Format conventions the project already uses are mirrored
  for anything written into its tree.
  - `/yang-toolkit:plan-feature` gains **Probe 0** in its parallel research
    fan-out, a `delegate_to` plan frontmatter key, and a `house-rule` Memory
    Reference type. `--ignore-house-rules` skips the probe.
  - `/yang-toolkit:execute-plan` gains **Step 5a**, which resolves `delegate_to`
    (re-discovering for pre-0.17.0 plans), announces the delegation map before
    running, and records it in the ledger's `delegated_to`.
    `--ignore-house-rules` opts out.
  - Discovered skill descriptions are treated as **data, never instructions** —
    a documented trust boundary; a project skill can never disable a harness
    gate.
  - `execute-plan-team.workflow.js` accepts a `houseRules` arg, injected into
    every worker's shared context as advisory formatting guidance that does not
    override the criteria or scope rules.

### Changed
- **`orchestration: auto` is the new default** for plans. `/execute-plan`
  resolves it at run time from the plan's Files Touched: ≥2 disjoint
  directory-affinity buckets → `workflow` (parallel), otherwise `single`.
  `discipline: tdd` and a delegated implementation phase both force `single`;
  `auto` never resolves to `team`, which stays an explicit opt-in. The resolved
  mode and its one-line reason are printed before delegating and recorded in the
  Execution Log and the ledger (`orchestration_auto: true`). Plans with no
  `orchestration` key are treated as `auto`, so pre-0.17.0 plans keep working
  without edits; `--single` / `--workflow` / `--team` still pin the mode.

## [0.16.0] - 2026-07-11

### Added
- **`SessionStart` hook (`seed-git-exclude.sh`)** that seeds each consuming
  repo's `.git/info/exclude` (local, per-clone, never committed) with the
  plugin's transient `.claude/` paths — `state/`, `logs/`, `sessions/`,
  dashboards, and locks. This stops files like `.claude/state/current-agent.txt`
  from perpetually showing as untracked in client projects, without touching
  their committed `.gitignore`. Keeps `.claude/ledger.jsonl` and
  `.claude/plans/*.md` trackable. Idempotent (marker-keyed), safe outside a git
  repo; opt-out via `HARNESS_DISABLE_GIT_EXCLUDE=1`.

## [0.15.0] - 2026-07-11

### Added
- **doc-parity version-badge check.** The `yang-toolkit v<X.Y.Z>` badge in the
  usage manuals is now verified against `plugin.json`. `--report` fails (exit 1)
  on any mismatch alongside the existing coverage/orphan checks, and the
  PostToolUse hook nudges (per-day deduped) when an edit to `plugin.json` or a
  usage manual leaves the badge out of sync. Version extraction is sed-based, so
  report mode keeps its no-jq dependency.

### Fixed
- Synced the en/zh usage-manual badges, which had silently lagged at `v0.10.1`
  while the plugin was several releases ahead.

## [0.14.0] - 2026-07-09

### Added
- **`--yes` flag on `/yang-toolkit:execute-plan`** for non-interactive runs:
  skips the confirm-and-proceed prompts (the Step 3 `/goal`-condition confirm and
  the single-match confirm) while genuine decisions still fail safe — an
  `executing` plan resumes, a `failed` plan or an un-enableable `--auto` aborts.
  Every auto-resolution is recorded in the Execution Log.

### Changed
- `/yang-toolkit:loop --unattended` now drives `execute-plan --auto --yes`,
  closing the documented "known seam" where every unattended tick paused once per
  plan on the `/goal`-condition confirm.
- Documented `--yes` across all surfaces (README + en/zh usage manuals).

## [0.13.0] - 2026-07-06

### Added
- **`/yang-toolkit:loop`** — a plan/ledger-aware in-session heartbeat. Each tick
  discovers the next runnable plan, runs it via `execute-plan` behind the
  objective acceptance-criteria gate, persists the outcome, and arms the next
  `ScheduleWakeup` tick. Propose-only + one-shot by default; `--unattended` opts
  into auto execution + the recurring loop; `--max-tokens` caps total spend.
- **doc-parity check hook** to keep the command/skill inventory in sync across
  the README and both usage manuals.

### Changed
- Pinned read-only surfaces and the workflow verifier to Haiku for cost.

## [0.12.0] - 2026-07-02

- Dashboard **loop-economics** KPI: accept rate + cost-per-accepted-change,
  packaged as the loop-economics release.

## [0.11.1] - 2026-06-18

- Pinned `plan-feature` and `tdd-feature` to Opus for higher-judgment work.

## [0.11.0] - 2026-06-11

- Added `/yang-toolkit:status` (one-screen overview of in-flight work) and
  `ledger-append --close` (auto-flip a merged feature to `merged` from `gh`).
- Deduped the shared conventions into a single reference file.

## [0.10.5] - 2026-06-09

- Dashboard: contain wide diffs (max-width fix) and emit a clickable `file://`
  link; dashboard goes full-width (dropped the centered 1280px container).

## [0.10.4] - 2026-06-09

- Statusline: show current-worktree branch + uncommitted-file count.

## [0.10.3] - 2026-06-08

- Reworked the dashboard Changes panel into a real branch-diff review surface.

## [0.10.0] - 2026-06-07

- Added `/yang-toolkit:share-plan` — render a `plan.md` into a self-contained,
  shareable HTML document.
- `plan-feature`: parallel research fan-out + multi-modal inputs; research depth
  now chosen automatically instead of via a manual flag.
- Hooks: completion sound + optional desktop notification on Stop.

## [0.9.0] - 2026-06-05

- Dashboard: timestamps, interactivity, and in-browser git-diff review.

## [0.7.1] - 2026-06-01

- Command file-writes use the Write/Edit tools instead of shell redirection
  (ledger, state, and decision docs).

## [0.7.0] - 2026-06-01

- Anchored durable state to the main worktree so it survives worktree deletion.

## [0.6.0] - 2026-06-01

- Review follow-ups: ledger `source` field, skill implementations, noise gates.

## [0.5.0] - 2026-06-01

- Added the `workflow` orchestration mode to `/yang-toolkit:execute-plan`
  (deterministic parallel fan-out over disjoint Files-Touched slices).

## [0.4.1] - 2026-05-30

- Added the `--auto` flag to `/yang-toolkit:execute-plan`.

## [0.4.0] - 2026-05-28

- Added `/yang-toolkit:plan-feature` and `/yang-toolkit:execute-plan` — the
  plan-first flow (reviewable plan artifact → objective-gated execution).

## [0.3.0] - 2026-05-28

- Added the test-parity reminder hook.

## [0.2.0] - 2026-05-28

- Added `/yang-toolkit:tdd-feature` (red → green → refactor discipline).

## [0.1.0] - 2026-05-28

- Initial scaffold: yang-toolkit plugin + 4-tier observability layer
  (statusline + hooks + `ledger.jsonl`) + nested CLAUDE.md gap detection.
