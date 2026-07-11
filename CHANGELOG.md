# Changelog

All notable changes to the **yang-toolkit** plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Versions track `plugins/yang-toolkit/.claude-plugin/plugin.json`.

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
