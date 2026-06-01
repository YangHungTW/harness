# harness

YANG's personal Claude Code marketplace -- daily-ops skills and a four-tier
observability layer that travels with the plugin to any client repo.

> Personal use, no warranty.

## What's inside

One marketplace (`harness`) shipping one plugin (`yang-toolkit`).

### `yang-toolkit` -- contents

**Agents**: none bundled. Claude Code already routes between its built-in
agents (general-purpose, Explore, Plan, etc.) and any plugin- or repo-installed
agents on its own. The observability layer captures whichever subagent runs
(see `agent` in the ledger schema below) without prescribing names.

To bring an agent to a repo, either install a community plugin
(`/plugin install <name>`) or drop a per-repo definition in
`<client-repo>/.claude/agents/`. Both flow through the same `SubagentStop`
hook and show up in the statusline / dashboard automatically.

**Skills** (`plugins/yang-toolkit/skills/`)
- `today` -- daily digest across GitHub / Jira / Slack / per-repo ledgers
- `week` -- cross-repo weekly report from `~/.config/harness/repos.json`
- `dashboard` -- render ledger to HTML (timeline + kanban + stats)
- `curate-claude-md` -- audit + (re)generate nested `CLAUDE.md`

**Commands** (`plugins/yang-toolkit/commands/`)
- `/yang-toolkit:plan-feature` -- draft a reviewable plan artifact at
  `.claude/plans/<slug>.md` with auto-generated Memory References from
  ledger + CLAUDE.md + decision dirs. Does NOT execute; hand to
  `/execute-plan` when ready. Supports `--from <slug>` (replan) and
  `--revise <slug>` (append a revision section).
- `/yang-toolkit:execute-plan` -- parse + validate a plan, resolve
  `depends_on`, then run it per the plan's `orchestration`: `single`
  (assemble a `/goal` condition and delegate to `tdd-feature` /
  `feature-dev-tracked` by `discipline`), `workflow` (deterministic
  parallel fan-out via the built-in `Workflow` tool — see
  `workflows/execute-plan-team.workflow.js`), or `team` (experimental
  agent-teams). `--dry-run` shows the assembled /goal (or the workflow
  args + partition map) without executing.
- `/yang-toolkit:feature-dev-tracked` -- wraps `/feature-dev`, writes per-phase
  decision docs + one ledger summary
- `/yang-toolkit:tdd-feature` -- TDD-discipline sibling. Can continue from a
  paused `feature-dev-tracked` session (via `.claude/state/current-feature.txt`)
  or start fresh. Enforces red -> green -> refactor cycles, logs each cycle.
- `/yang-toolkit:ledger-append` -- manually backfill or correct ledger entries
- `/yang-toolkit:claude-md-gaps` -- review nested-folder CLAUDE.md gap candidates,
  delegate generation to the official `claude-md-management` plugin, gated on
  user confirmation (see "Nested CLAUDE.md gap detection" below)

**Workflows** (`plugins/yang-toolkit/workflows/`)
- `execute-plan-team.workflow.js` -- deterministic parallel fan-out for
  `/yang-toolkit:execute-plan` when a plan sets `orchestration: workflow`.
  Partitions Files Touched into disjoint slices by directory affinity,
  implements each slice concurrently (Phase 1), then verifies every
  Acceptance Criterion by running its Check command (Phase 2). Invoked
  via the built-in `Workflow` tool with the parsed plan passed as `args`
  (the script has no filesystem access; all I/O happens inside agents).

**Hooks** (`plugins/yang-toolkit/hooks/hooks.json`)
- `PreToolUse` -> `.claude/logs/session-{YYYYMMDD}.jsonl`
- `PostToolUse` (Edit|Write|MultiEdit) -> two passive checks:
  - score the touched folder for CLAUDE.md need; dedupe-append to
    `.claude/state/claude-md-candidates.jsonl`
  - test-parity nudge: if a production-code file was edited but no test
    mirror has been touched in this session, inject a reminder into Claude's
    next-turn context (see "Test parity reminder" below)
- `SubagentStop` -> `.claude/state/current-agent.txt`
- `Stop` -> append summary to `.claude/ledger.jsonl` (outcome=`in-progress`,
  user-correctable via `/ledger-append`)

**Statusline** (`plugins/yang-toolkit/statusline/statusline.sh`)
- bash 3.2 / BSD portable
- output: `[harness] {agent} . {phase} . {files}f . {tokens}t`
- graceful degrade when files are missing
- wired automatically as `subagentStatusLine`; to use as your main statusline,
  see "Install" below

## Install

```bash
# add the marketplace (one time per machine)
/plugin marketplace add YangHungTW/harness

# install the plugin
/plugin install yang-toolkit@harness
```

Installing `yang-toolkit` auto-installs five upstream dependencies from the
`claude-plugins-official` marketplace (which auto-loads in every Claude Code):

| Auto-installed dependency | Used by harness for |
| ------------------------- | ------------------- |
| `feature-dev`             | `/yang-toolkit:feature-dev-tracked` delegates to its `/feature-dev` command (7-phase workflow + 3 specialized agents) |
| `claude-md-management`    | `/yang-toolkit:claude-md-gaps` delegates to its `/revise-claude-md` for nested-folder generation |
| `code-review`             | natural review step inside the feature-dev flow; runs multi-agent confidence-scored review |
| `code-simplifier`         | post-review cleanup pass to simplify implementation code |
| `commit-commands`         | `/commit` / `/push` / `/create-pr` commands used at the tail of every feature |

Claude Code lists all five at the end of the install output. You can confirm
with `claude plugin list` afterward.

Explicitly NOT auto-installed (install separately if you want them):
`pr-review-toolkit` (overlaps with `code-review`), `frontend-design`
(domain-specific), `hookify` (one-shot meta tool), `claude-code-setup`
(one-shot meta tool), `remember` (operates on conversation memory, a
different layer from harness's tool-execution ledger).

To use `statusline.sh` as the **main** Claude Code statusline (it's already
wired as `subagentStatusLine`), add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/statusline/statusline.sh"
  }
}
```

(Note: `${CLAUDE_PLUGIN_ROOT}` is only resolved inside plugin-context settings.
For user settings you may need to expand the install path manually; see the
official statusline docs for the latest interpolation rules.)

## Cheat sheet -- one feature from 0 to merged

> Also available as a single-page HTML tutorial: `docs/usage.html`
> (or `docs/usage.zh.html` for 繁體中文). On macOS:
> `open docs/usage.html`. On Linux: `xdg-open`.

### Passive (no commands, just happens while you work)
- `PreToolUse` hook -> append every tool call to `.claude/logs/session-YYYYMMDD.jsonl`
- `PostToolUse` hook (Edit/Write/MultiEdit) -> score the touched folder, dedupe-append candidates to `.claude/state/claude-md-candidates.jsonl`
- `SubagentStop` hook -> write running agent name to `.claude/state/current-agent.txt` (drives the statusline + dashboard kanban badges)
- `Stop` hook -> append session summary to `.claude/ledger.jsonl` with outcome `in-progress`

### Active (the commands, in the order you'll usually run them)

Pick an entry point by how much pre-flight review you want and whether
TDD discipline matters:

- **0a / 0b**: jump straight into implementation. Fastest path.
- **0p + 0x**: write a plan artifact first, then execute. Use when the
  work is large, depends on other in-flight features, or you want a
  PR-reviewable plan before code lands.

| Step | Command | What it does |
| ---- | ------- | ------------ |
| 0p. Plan (optional pre-stage) | `/yang-toolkit:plan-feature "<description>"` | Enters plan mode, recalls past context (ledger + CLAUDE.md + decision dirs), writes `.claude/plans/<slug>.md`. Auto-suggests `depends_on` for related unfinished features. Review the file, edit if needed. |
| 0x. Execute the plan | `/yang-toolkit:execute-plan` (or `--from <slug>`, `--dry-run`, `--single` / `--team` / `--workflow`, `--auto` overrides) | Parses + validates the plan, then runs it one of three ways per the plan's `orchestration`: **single** (sequential `/goal` loop → `tdd-feature` / `feature-dev-tracked`), **workflow** (deterministic parallel fan-out via the built-in `Workflow` tool — partitions Files Touched into disjoint slices, implements them concurrently, then verifies each Acceptance Criterion), or **team** (experimental agent-teams). With `--auto` the `single`/`team` `/goal` loop runs unattended. Updates plan status + appends ledger at the end. |
| 0a. Start (regular flow, no plan stage) | `/yang-toolkit:feature-dev-tracked "<one-line description>"` | Wraps `/feature-dev`. Drives discovery -> architecture -> implementation -> review -> summary; writes one decision doc per phase under `docs/decisions/{date}-{slug}/`; appends a ledger summary at the end. |
| 0b. Start (TDD flow, no plan stage) | `/yang-toolkit:tdd-feature "<description>"` OR `/yang-toolkit:tdd-feature` (continues from a paused feature-dev-tracked) | Enforces red -> green -> refactor per test case; writes a `02b-test-plan.md` then a `03-tdd-cycles.md` log; shares the same decision dir and ledger schema as feature-dev-tracked. Adds a `cycles` field to the ledger entry. |
| 1. (during discovery, auto) | -- | `code-explorer` agent (ships with `feature-dev`) traces the codebase. No command needed. |
| 2. (during architecture, auto) | -- | `code-architect` agent designs the implementation. No command needed. |
| 3. (during review phase) | `/code-review` | Multi-agent review with confidence-scored findings. Use with `--fix` or `/simplify` to auto-apply small cleanups. |
| 4. (cleanup) | `/code-simplifier` | Refactor for clarity/consistency without changing behavior. |
| 5. (mid-stream, whenever) | `/yang-toolkit:claude-md-gaps` | Review nested-folder CLAUDE.md candidates the passive hook flagged. Delegates generation to `/revise-claude-md`. Always gated on your accept before any file is written. |
| 6. Commit | `/commit` | `commit-commands` plugin -- generates message from diff and commits. |
| 7. Push | `/push` | Push current branch. |
| 8. Open PR | `/create-pr` | Open a PR with a description derived from commits. |
| 9. After PR merges | `/yang-toolkit:ledger-append` | Update the session's ledger entry: flip outcome to `merged`, add PR URL + commit SHA. |

### Anytime

| Command | What it does |
| ------- | ------------ |
| `/yang-toolkit:dashboard` | Render `.claude/ledger.jsonl` to an HTML artifact (timeline + kanban + stats). |
| `/yang-toolkit:week` | Cross-repo weekly report from `~/.config/harness/repos.json`. |
| `/yang-toolkit:today` | Daily digest aggregating GitHub / external surfaces + every tracked repo's recent ledger entries. |
| `/yang-toolkit:ledger-append` | Manually backfill a ledger entry you forgot to capture. |
| `/yang-toolkit:curate-claude-md` | Audit + reorganize existing CLAUDE.md files (technical rules drift up, business rules drift down). |

### Concrete walk-through

```
$ /yang-toolkit:feature-dev-tracked Add cancellation policy UI to booking flow

   [code-explorer scans the repo]
   wrote docs/decisions/2026-05-28-cancellation-policy-ui/01-discovery.md

   [code-architect proposes architecture]
   wrote docs/decisions/2026-05-28-cancellation-policy-ui/02-architecture.md

   [implementation -- Edit/Write tools, hook accumulates gap candidates]
   wrote docs/decisions/2026-05-28-cancellation-policy-ui/03-implementation.md

$ # ALTERNATIVE: if you want TDD discipline, after architecture you can pause and pivot:
$ /yang-toolkit:tdd-feature              # picks up via .claude/state/current-feature.txt
   reads 01-discovery, 02-architecture, asks "continue with TDD?"
   wrote 02b-test-plan.md
   cycle 1: red -> green -> refactor (logged in 03-tdd-cycles.md)
   cycle 2: ...
   wrote 04-review.md (after /code-review)
   wrote 05-summary.md
   appended ledger (cycles=4)

$ # OR continue the non-TDD path:
$ /code-review
   ... review output, applied two small fixes ...

$ /yang-toolkit:claude-md-gaps
   Top candidate: app/booking/policies/ (score 0.78)
   Generate draft? [y/N] y
   ... draft shown ...
   Accept? [y/N] y
   wrote app/booking/policies/CLAUDE.md
   updated .claude/state/claude-md-candidates.jsonl
   appended .claude/ledger.jsonl (outcome=claude-md-created)

$ /commit
$ /push
$ /create-pr
   https://github.com/.../pull/123

   (later)

$ /yang-toolkit:ledger-append
   feature: cancellation-policy-ui
   outcome: merged
   pr: https://github.com/.../pull/123
   commit: a1b2c3d
   appended .claude/ledger.jsonl
```

### Plan-first variant

```
$ /yang-toolkit:plan-feature Add cancellation policy UI to booking flow
   recalled 2 prior ledger entries, 1 CLAUDE.md rule, 1 decision-dir summary
   suggested depends_on: ['booking-policy-engine'] (in-progress)  -> accepted
   wrote .claude/plans/cancellation-policy-ui.md (status: draft)

$ # user opens the plan, edits Acceptance Criteria, sets discipline: tdd

$ /yang-toolkit:execute-plan --dry-run
   parsed 4 acceptance criteria, all pass fuzzy-word lint
   resolved 1 dependency (booking-policy-engine: done)
   assembled /goal (847 chars)
   would delegate to: /yang-toolkit:tdd-feature --from cancellation-policy-ui

$ /yang-toolkit:execute-plan
   set /goal ...
   set status: executing, started_at: 2026-05-28T...Z
   delegated to /yang-toolkit:tdd-feature
   ... TDD cycles run ...
   /goal achieved at turn 18
   appended ## Execution Log block
   set status: done
   appended ledger (orchestration: single, goal_turns: 18)
```

## Observability -- four tiers

```
即時 (real-time)        statusline + .claude/logs/session-*.jsonl
                        |
                        v
單任務 (per-feature)    /feature-dev-tracked -> docs/decisions/{YYYY-MM-DD}-{slug}/
                        |
                        v
跨任務 (per-repo)       .claude/ledger.jsonl -> /dashboard (HTML)
                        |
                        v
跨專案 (cross-repo)     ~/.config/harness/repos.json -> /week, /today
```

Each tier is consumable by humans on its own; together they let you ask
"what did I do this week, across all my client repos?" without forensics.

## Nested CLAUDE.md gap detection

A two-stage flow that proposes nested CLAUDE.md files where the codebase needs
one but doesn't have one yet -- without auto-writing into the user's repo.

```
PostToolUse hook (Edit|Write|MultiEdit)
  -> scores the touched folder against gap heuristics
  -> appends/dedupes pending candidate to .claude/state/claude-md-candidates.jsonl
  -> NEVER writes a CLAUDE.md by itself

/yang-toolkit:claude-md-gaps  (on demand)
  -> lists pending candidates ranked by score
  -> delegates generation to /revise-claude-md (official claude-md-management plugin)
                or to /yang-toolkit:curate-claude-md as fallback
  -> shows draft -> waits for user accept
  -> only on accept: writes <dir>/CLAUDE.md + updates candidate + ledger entry
```

Heuristic (passive scoring): bounded-context naming, depth >= 2, file-count
threshold, recent edit activity from `.claude/logs/session-*.jsonl`, and
"folder not mentioned in any ancestor CLAUDE.md". Generated content stays
focused on **business logic / domain invariants** for that folder; technical
rules continue to live at the root. (DRY across the memory hierarchy --
ancestor CLAUDE.mds always load first, so duplication just wastes context.)

The official plugin is available out-of-the-box (the `claude-plugins-official`
marketplace auto-loads). Install once with:

```
/plugin install claude-md-management
```

## Test parity reminder

A second PostToolUse hook nudges Claude when production code is edited
without touching its test mirror in the same session. Designed to address
the common pattern where Claude fixes a `.rb`/`.go`/`.ts` file and forgets
the corresponding `_spec.rb` / `_test.go` / `.test.ts`.

**Flow**
1. PostToolUse hook fires on every Edit / Write / MultiEdit
2. Hook derives one or more "expected mirror" test paths from the edited file
   (per-language rules; see `hooks/test-parity-check.sh` for the full table)
3. Hook scans today's session log: did the same session touch any of those
   mirror paths via Edit / Write / MultiEdit?
4. If not, hook outputs a structured JSON reminder that gets injected into
   Claude's next-turn context (`hookSpecificOutput.additionalContext`) AND
   surfaced as a `systemMessage` so the user sees it too
5. Per-session dedupe via `.claude/state/test-parity-warned-YYYYMMDD.txt`
   -- one warning per (file, day), no spam

**Languages covered out of the box**

| Production file pattern         | Mirror candidates                                                                |
| ------------------------------- | -------------------------------------------------------------------------------- |
| `app/**/*.rb`                   | `spec/**/*_spec.rb`, `test/**/*_test.rb`                                         |
| `lib/**/*.rb`                   | `spec/lib/**/*_spec.rb`, `spec/**/*_spec.rb`                                     |
| `**/*.go`                       | `**/*_test.go` (same dir)                                                        |
| `**/*.{ts,tsx,js,jsx}`          | sibling `.test.X` / `.spec.X` and `__tests__/` subdir                            |
| `**/*.py`                       | `tests/test_*.py`, same-dir `test_*.py`                                          |
| `**/*.sol`                      | `test/*.t.sol`, `test/*.test.sol` (Foundry layout)                                |

Anything outside these patterns (or matching the negative-filter list:
migrations, config, views, assets, lockfiles, docs, dotenv files) is
silently skipped.

**Opt-out**

Set `HARNESS_DISABLE_TEST_PARITY=1` in your shell env or repo `.envrc` to
disable globally. Or per-repo: edit `.claude/settings.local.json` to add
`{ "env": { "HARNESS_DISABLE_TEST_PARITY": "1" } }`.

## Per-client-repo file convention

When you adopt `yang-toolkit` in a client repo, you'll accumulate:

```
client-repo/
|-- .claude/
|   |-- ledger.jsonl       # COMMIT this -- it's the project memory
|   |-- plans/             # COMMIT this -- reviewable plan artifacts
|   |     |-- <slug>.md                        # one per planned feature; status tracks lifecycle
|   |     `-- .fuzzy-words                     # OPTIONAL: project-local override of /execute-plan's fuzzy-word lint
|   |-- logs/              # gitignore -- noisy per-session tool calls
|   |-- state/             # gitignore -- ephemeral
|   |     |-- current-agent.txt
|   |     |-- current-feature.txt              # in-flight feature slug (set by feature-dev-tracked / execute-plan, read by tdd-feature)
|   |     |-- claude-md-candidates.jsonl       # pending CLAUDE.md gap proposals
|   |     `-- test-parity-warned-YYYYMMDD.txt  # files we've already nudged about today
|   `-- dashboard.html     # gitignore -- regenerable artifact
`-- docs/decisions/        # COMMIT this -- per-feature decision trail
```

Add to that repo's `.gitignore`:

```
.claude/logs/
.claude/state/
.claude/dashboard.html
```

## Cross-repo config

The `/week` and `/today` skills read:

```
~/.config/harness/repos.json
```

```json
{
  "repos": [
    { "client": "billing-entity", "name": "short-slug", "path": "/abs/path/to/repo", "active": true }
  ]
}
```

If the file is absent, `/week` will print a starter template and exit cleanly.

## Ledger schema (controlled vocabulary)

One line of `.claude/ledger.jsonl` =

```json
{
  "ts":      "2026-05-28T03:14:00Z",
  "feature": "feature-slug",
  "phase":   "discovery|architecture|implementation|review|summary",
  "agent":   "<whatever subagent ran, or 'main' if Claude's main thread, or 'unknown'>",
  "outcome": "in-progress|merged|abandoned|failed",
  "files":   3,
  "tokens":  18000,
  "tools":   { "Read": 12, "Write": 2, "Edit": 4, "Bash": 3 },
  "pr":      "https://github.com/...",
  "commit":  "a1b2c3d"
}
```

`outcome` and `phase` are closed sets. `agent` is intentionally **open** --
record whatever ran (Claude main thread, built-in subagent, plugin agent, or
community agent). Skills and the dashboard handle unknown agent names with a
generic fallback color. (Borrowed from `specaffold`'s verb-vocabulary
discipline, but applied only to outcomes/phases where aggregation requires it.)

The `claude-md-gaps` flow extends `outcome` with `"claude-md-created"` (used
only by `/yang-toolkit:claude-md-gaps`). When you add another such extension,
update `skills/dashboard/SKILL.md` and the legend in
`skills/dashboard/templates/dashboard.html` BEFORE shipping it.

## Local development

```bash
# load the plugin from this checkout without installing through a marketplace
claude --plugin-dir ./plugins/yang-toolkit

# after edits
/reload-plugins
```

## Status

`v0.5.0` -- functional. Commands, skills, hooks, statusline, and the
`execute-plan-team` workflow are all implemented and in personal use
(no warranty -- see the note at the top). Recent additions:

- `v0.5.0` -- `workflow` orchestration mode for `/execute-plan`
  (deterministic parallel fan-out via the built-in `Workflow` tool)
- `v0.4.x` -- plan-first flow (`/plan-feature` + `/execute-plan`),
  `--auto` execution
- `v0.3.0` -- test-parity reminder hook
- `v0.2.0` -- `/tdd-feature`

`harness-scaffolding-prompt.md` records the original generation spec for
reference; the live structure has since moved past it.

## License

MIT. See `LICENSE`.
