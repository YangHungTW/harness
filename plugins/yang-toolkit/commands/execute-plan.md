---
description: Execute an accepted plan artifact. Reads .claude/plans/<slug>.md, validates criteria, resolves depends_on, builds a /goal condition, delegates to tdd-feature or feature-dev-tracked, and appends to ledger on completion.
---

# /yang-toolkit:execute-plan

You are running a plan artifact produced by `/yang-toolkit:plan-feature`.
This command is an **orchestrator** -- it parses, validates, sets `/goal`,
delegates the actual implementation to one of the existing feature
commands, and records the outcome. It does not write production code
directly.

## Inputs
- `$ARGUMENTS` -- empty, or any combination of:
  - `--from <slug>` -- explicit plan to run
  - `--single` / `--team` -- override `orchestration` from frontmatter
  - `--auto` -- enter auto mode for the duration of this run so the `/goal` loop runs unattended (otherwise each turn still pauses for tool approval)
  - `--no-goal` -- skip `/goal` setup (user wants manual turn-by-turn control)
  - `--ignore-deps` -- proceed even if `depends_on` items aren't `done`
  - `--dry-run` -- print parsed plan + assembled /goal + delegate target, do NOT execute

## Two entry modes

### Mode A -- continue / latest draft
Triggered when no `--from` flag is given.

1. Read `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`. If
   non-empty, set `slug` from it.
2. Otherwise list `${CLAUDE_PROJECT_DIR}/.claude/plans/*.md`, filter to
   `status: draft` or `status: accepted`, sort by mtime descending.
   - exactly one match -> confirm with the user, then use it
   - multiple -> show the list, ask which
   - none -> abort with "no plan to execute; run /yang-toolkit:plan-feature first."

### Mode B -- explicit
Triggered by `--from <slug>`.

1. Read `${CLAUDE_PROJECT_DIR}/.claude/plans/<slug>.md`. If missing,
   abort.

## Step 1 -- parse and validate

Parse the frontmatter and the sections. Required:

| Required                            | If missing                                                       |
| ----------------------------------- | ---------------------------------------------------------------- |
| frontmatter `slug`                  | abort: malformed plan                                            |
| frontmatter `discipline`            | abort: ask user to revise                                        |
| frontmatter `status`                | abort: malformed plan                                            |
| `# Goal` non-empty                  | abort with revision hint                                         |
| `# Acceptance Criteria` >= 1 block  | abort with revision hint                                         |
| `# Files Touched` >= 1 entry        | abort with revision hint                                         |

### Status gate
- `draft` or `accepted` -> proceed
- `executing` -> ask the user: **resume** (keep `started_at`, re-issue
  `/goal`) / **reset** to draft / **abort**
- `done` -> REFUSE. Tell user: "use `/yang-toolkit:plan-feature --revise <slug>`
  to open a new revision."
- `failed` -> ask: re-run as-is, or revise first?

### Acceptance Criteria parsing

Each criterion must match this structure exactly:

```
- [ ] **<name>**
  - Check: `<command>`
  - Pass: <pass condition>
```

For every criterion:
1. Extract `<name>`, `<command>`, `<pass>`.
2. `<command>` must be wrapped in backticks. If not, abort with the
   criterion name: "Criterion '<name>' Check is not a runnable command."
3. Run the **fuzzy-word lint** on `<pass>` (rules below). On any
   match, abort with: "Criterion '<name>' Pass uses fuzzy language
   ('<word>'). Replace with an observable condition."

### Fuzzy-word list

Default (hard-coded), case-insensitive whole-word match:

```
good, acceptable, nice, clean, mostly, properly, correctly,
robust, performant, scalable, maintainable, sufficient, reasonable
```

**Project override**: if
`${CLAUDE_PROJECT_DIR}/.claude/plans/.fuzzy-words` exists, REPLACE
the default with the file's contents (one entry per line, `#`
comments and blank lines ignored). Do not merge -- replacement keeps
the rule explicit and debuggable.

## Step 2 -- resolve depends_on

If frontmatter has `depends_on: [<slug>, ...]`:

1. **Cycle detection (always, even with --ignore-deps)**: build the
   directed graph by reading each `depends_on` chain recursively.
   Track visited slugs. If the current slug appears anywhere
   downstream, abort with the cycle path printed (e.g.
   `A -> B -> C -> A`).
2. For each direct dep, read its plan and check `status`:
   - `done` -> OK
   - `failed` -> abort: "dep '<dep>' failed; revise or remove."
   - `draft / accepted / executing` -> abort: "dep '<dep>' not done; finish it first or pass `--ignore-deps`."
   - plan file missing -> abort: "dep '<dep>' has no plan."
3. If `--ignore-deps` is passed, skip the status check (but the cycle
   check still ran). Record skipped deps for the ledger entry's
   `deps_ignored` field.
4. For each successfully-resolved dep, prepare a one-paragraph
   summary of its Goal + Files Touched, capped at ~100 tokens. These
   are injected as background context at execution start.

## Step 3 -- build the /goal condition (skip if --no-goal)

Assemble a single string:

```
All of the following hold:
- <criterion 1 name>: running `<command>` produces <pass>.
- <criterion 2 name>: running `<command>` produces <pass>.
...

AND no files outside [<comma-separated Files Touched entries>] have been created or modified.
AND <Out of Scope bullet 1>.
AND <Out of Scope bullet 2>.
...

OR stop after <time_budget>.
```

Rules:
- Skip the `OR stop after ...` clause if `time_budget` frontmatter is
  absent.
- Skip the `AND <Out of Scope ...>` lines if the section is empty.
- Total length MUST be <= 4000 characters. If over, abort and tell
  the user to either shrink criteria or split the plan into multiple
  linked via `depends_on`.

Print the assembled condition. **Ask the user to confirm** before
proceeding -- this is the autopilot guardrail.

### Auto mode (only if `--auto` is passed)

`/goal` removes per-turn prompts; **auto mode** removes per-tool
prompts. Either alone is half-automated; together they produce
unattended execution.

After the user confirms the /goal condition AND before issuing
`/goal`, attempt to enter auto mode for the session. The exact
mechanism is Claude-Code-version-specific (typically a `/auto` slash
command or an equivalent in-session toggle). If you cannot enable it
programmatically, prompt the user with the steps to enable it and
wait for confirmation before continuing.

If `--auto` was NOT passed, print this one-line note and proceed:

> Note: auto mode is not active. `/goal` will keep starting new
> turns, but each turn will pause for tool approval. Pass `--auto`
> next time to make the loop fully unattended.

Do not silently enter auto mode without `--auto`. Auto mode is
opt-in.

## Step 4 -- set state and status

1. Update plan frontmatter:
   - `status: executing`
   - `started_at: <ISO8601 UTC now>`
   - `executor: <session id if known, else 'main'>`
2. Write `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` <-
   bare slug.

## Step 5 -- decide orchestration and delegate

Read frontmatter `orchestration`; override with `--single` or `--team`
flag if passed.

### single
Branch on `discipline`:

- `tdd` -> compose a prompt that embeds the plan content (Goal +
  Acceptance Criteria + Files Touched + dep summaries), then invoke
  `/yang-toolkit:tdd-feature --from <slug>`. The downstream command
  will find/create the decision dir and start cycling.
- `normal` -> same approach with `/yang-toolkit:feature-dev-tracked`.
  Because that command does not yet accept `--from`, pass the plan's
  Goal as the natural-language argument; slug derivation is
  deterministic so the decision dir lines up. The state pointer set
  in Step 4 takes precedence.

### team
1. Verify the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` env var is set.
   If not, warn the user and fall back to `single`. Record the
   fallback in the eventual Execution Log.
2. Partition Files Touched into `team_size` disjoint groups by
   directory affinity (files sharing the longest common path prefix
   go together).
3. Compose a prompt for the team lead: spawn `team_size` teammates,
   each owning one partition, with the plan as shared context.
   Acceptance Criteria are global; Files Touched are per-teammate.
   Lead synthesizes results at the end.
4. Do NOT communicate with teammates directly -- always through the
   lead.

## Step 6 -- run

Issue `/goal <condition>` (unless `--no-goal`). Then send the opening
prompt that delegates to the chosen downstream command (or spawns the
team).

Monitor at session boundaries only; do not poll. When the session
ends -- by goal achievement, by user `/goal clear`, by error, or by
budget exhaustion -- proceed to Step 7.

## Step 7 -- close out

1. **Determine final outcome**:
   - goal evaluator returned achieved -> `done`
   - user `/goal clear` or explicit stop -> `abandoned` (in ledger;
     plan status stays `executing` so resume is the natural action)
   - turn budget exhausted -> `failed`
   - downstream command errored unrecoverably -> `failed`

2. **Update plan frontmatter**:
   - `status: done` or `status: failed` (NOT for abandoned)
   - `finished_at: <ISO8601 UTC now>`

3. **Append `## Execution Log` section** (extend if re-run). Include:
   - run number (1 if first)
   - `started_at`, `finished_at`, duration
   - outcome
   - goal evaluator's final reason, quoted verbatim
   - turn count and approx token count
   - whether any Files Touched scope-guard violations were observed
   - downstream command used

4. **Append ONE record** to `${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl`
   matching the feature-dev-tracked schema plus these extras:
   ```
   "plan_path":      ".claude/plans/<slug>.md",
   "goal_turns":     <int or null>,
   "orchestration":  "single" | "team",
   "deps_ignored":   [<slug>, ...]   // omit field entirely if empty
   ```
   `outcome` follows the controlled set
   `in-progress | merged | abandoned | failed`. Plan-status `done`
   maps to ledger `outcome: in-progress` by default (a PR isn't
   necessarily merged yet). Promote to `merged` only on explicit
   user confirmation in this session.

5. **Curate CLAUDE.md**: if the `/yang-toolkit:curate-claude-md`
   skill is available, invoke it so learnings get absorbed. If
   unavailable, skip and mention in the final report.

6. **Clear** `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`.

7. **Report** to the user:
   - plan path and final status
   - ledger line appended
   - whether the goal was achieved
   - any anomalies (deps_ignored, scope violations, status not
     changed because abandoned, etc.)

## --dry-run mode

After Step 3, instead of writing state or executing:
- print the parsed Acceptance Criteria
- print the assembled `/goal` condition
- print which downstream command would be invoked, with what arguments
- print resolved `depends_on` summaries
- exit

Do NOT change `status`. Do NOT write `current-feature.txt`. Do NOT
touch the ledger.

## Edge cases

| Situation                                                                          | Behavior                                                                                                                                          |
| ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Plan's Acceptance Criteria contains a fuzzy word                                   | Abort Step 1 with the offending word; ask user to revise via `/yang-toolkit:plan-feature --revise <slug>`.                                       |
| `depends_on` chain has a cycle                                                     | Abort Step 2 with the cycle path printed (e.g. `A -> B -> C -> A`).                                                                              |
| Goal evaluator runs > 50 turns with no resolution and no `time_budget` set        | Self-stop, mark `failed`, but do NOT delete the plan. User can `--revise` then re-run.                                                            |
| Team mode requested but env var not set                                            | Warn, fall back to single. Record in Execution Log: "team mode requested but disabled; ran single."                                              |
| Plan `status: executing` at invocation                                             | Ask resume / reset / abort. On resume, keep `started_at` but DO re-issue `/goal` (its evaluator clock resets on session resume regardless).      |
| Downstream command unavailable                                                     | Abort before `/goal` is set. Suggest installing the relevant plugin.                                                                              |
| Assembled `/goal` condition exceeds 4000 characters                                | Abort. Suggest shrinking criteria or splitting the plan into pieces linked via `depends_on`.                                                      |
| Files Touched scope violated during execution (only detectable if a hook is wired) | Continue, but record the violation in Execution Log. Scope-guard hooks are opt-in; absent hooks make this best-effort.                            |
| `/yang-toolkit:curate-claude-md` not installed                                     | Skip step 7.5; mention in final report. Do not abort.                                                                                             |
| `--auto` passed but auto mode cannot be enabled in this Claude Code version        | Warn, print manual enable steps, wait for user confirmation. Do NOT proceed silently as if auto mode were active.                                |

## Failure modes

- Plan file unreadable: abort.
- Ledger unwritable: complete execution and frontmatter updates, then
  surface "ledger write failed" with the exact JSON line that should
  have been appended, so the user can run
  `/yang-toolkit:ledger-append` manually.
- `current-feature.txt` cannot be written or cleared: warn but
  continue -- it's a convenience pointer, not a correctness gate.
