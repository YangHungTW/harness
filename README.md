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
- `/yang-toolkit:feature-dev-tracked` -- wraps `/feature-dev`, writes per-phase
  decision docs + one ledger summary
- `/yang-toolkit:ledger-append` -- manually backfill or correct ledger entries
- `/yang-toolkit:claude-md-gaps` -- review nested-folder CLAUDE.md gap candidates,
  delegate generation to the official `claude-md-management` plugin, gated on
  user confirmation (see "Nested CLAUDE.md gap detection" below)

**Hooks** (`plugins/yang-toolkit/hooks/hooks.json`)
- `PreToolUse` -> `.claude/logs/session-{YYYYMMDD}.jsonl`
- `PostToolUse` (Edit|Write|MultiEdit) -> passive: score the touched folder
  for CLAUDE.md need, dedupe-append to `.claude/state/claude-md-candidates.jsonl`
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

### Passive (no commands, just happens while you work)
- `PreToolUse` hook -> append every tool call to `.claude/logs/session-YYYYMMDD.jsonl`
- `PostToolUse` hook (Edit/Write/MultiEdit) -> score the touched folder, dedupe-append candidates to `.claude/state/claude-md-candidates.jsonl`
- `SubagentStop` hook -> write running agent name to `.claude/state/current-agent.txt` (drives the statusline + dashboard kanban badges)
- `Stop` hook -> append session summary to `.claude/ledger.jsonl` with outcome `in-progress`

### Active (the commands, in the order you'll usually run them)

| Step | Command | What it does |
| ---- | ------- | ------------ |
| 0. Start the feature | `/yang-toolkit:feature-dev-tracked "<one-line description>"` | Wraps `/feature-dev`. Drives discovery -> architecture -> implementation -> review -> summary; writes one decision doc per phase under `docs/decisions/{date}-{slug}/`; appends a ledger summary at the end. |
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

## Per-client-repo file convention

When you adopt `yang-toolkit` in a client repo, you'll accumulate:

```
client-repo/
|-- .claude/
|   |-- ledger.jsonl       # COMMIT this -- it's the project memory
|   |-- logs/              # gitignore -- noisy per-session tool calls
|   |-- state/             # gitignore -- ephemeral
|   |     |-- current-agent.txt
|   |     `-- claude-md-candidates.jsonl  # pending CLAUDE.md gap proposals
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

`v0.1.0` -- scaffolded structure. Agents, skills, commands, and hooks are
stubbed with TODOs; the dashboard HTML template is the only file complete
enough to render on its own. See `harness-scaffolding-prompt.md` for the
generation spec.

## License

MIT. See `LICENSE`.
