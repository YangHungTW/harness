---
description: Execute an accepted plan artifact. Reads .claude/plans/<slug>.md, validates criteria, resolves depends_on, builds a /goal condition, picks orchestration (auto by default), delegates to the project's own workflow skills where they own a phase and otherwise to tdd-feature or feature-dev-tracked, and appends to ledger on completion.
---

# /yang-toolkit:execute-plan

You are running a plan artifact produced by `/yang-toolkit:plan-feature`.
This command is an **orchestrator** -- it parses, validates, sets `/goal`,
delegates the actual implementation to one of the existing feature
commands, and records the outcome. It does not write production code
directly.

## Conventions

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` first -- it defines
`<HARNESS_ROOT>` resolution, the durable-vs-ephemeral path split, the ledger
schema, the Read+Write append rule, the **project house rules**
discovery/delegation protocol consumed in Step 5, the **routing declaration**
rule (routing is stated, never asked), the **reality anchors**, and the
**run states**. Plans (incl. `.fuzzy-words`)
and the ledger live under `<HARNESS_ROOT>`; `current-feature.txt` stays on
`${CLAUDE_PROJECT_DIR}`.

## Inputs
- `$ARGUMENTS` -- empty, or any combination of:
  - `--from <slug>` -- explicit plan to run
  - `--single` / `--team` / `--workflow` -- pin the orchestration mode, overriding
    `orchestration` from frontmatter (including the `auto` default, whose
    resolution is then skipped)
  - `--ignore-house-rules` -- ignore `delegate_to` and skip house-rules
    re-discovery; run every phase with yang-toolkit's own flow
  - `--auto` -- enter auto mode for the duration of this run so the `/goal` loop runs unattended (otherwise each turn still pauses for tool approval)
  - `--yes` -- non-interactive: skip the confirm-and-proceed prompts (the
    Step 3 `/goal`-condition confirm, and Mode A's single-match confirm).
    Prompts that are genuine decisions are NOT skipped -- they resolve to a
    documented safe default or abort (see "--yes resolution table"). Intended
    for callers like `/yang-toolkit:loop --unattended`; combine with `--auto`
    for fully unattended execution.
  - `--answer "<text>"` -- resume a **parked** plan (`awaiting-input` /
    `awaiting-auth`) with an answer the caller already has, instead of
    re-presenting the question. Used by `/yang-toolkit:go` when the user's own
    message was the answer. Ignored (with a one-line note) on a plan that is not
    parked -- never treat it as an instruction to skip a gate
  - `--no-goal` -- skip `/goal` setup (user wants manual turn-by-turn control)
  - `--ignore-deps` -- proceed even if `depends_on` items aren't `done`
  - `--dry-run` -- print parsed plan + assembled /goal + delegate target, do NOT execute

### --yes resolution table

`--yes` never invents a choice. Confirm-and-proceed prompts are skipped;
prompts that pick between materially different outcomes resolve as follows
(fail safe -- when in doubt, abort with a message rather than guess):

| Interactive point                                        | Without `--yes`              | With `--yes`                                          |
| -------------------------------------------------------- | ---------------------------- | ----------------------------------------------------- |
| Step 3: confirm assembled `/goal` condition              | ask, then proceed            | print the condition, proceed                          |
| Mode A: exactly one runnable plan found                  | confirm, then use it         | use it                                                |
| Mode A: multiple runnable plans found                    | show list, ask which         | abort: "multiple candidates; pass `--from <slug>`"    |
| Status gate: plan is `executing`                         | ask resume / reset / abort   | resume (keep `started_at`, re-issue `/goal`)          |
| Status gate: plan is `failed`                            | ask re-run / revise          | abort: "plan previously failed; re-run or revise interactively" |
| `--auto` passed but auto mode cannot be enabled          | warn, print steps, wait      | abort (do NOT proceed half-attended)                  |
| Step 5a: two project skills claim the same phase         | ask which one owns it        | leave the phase undelegated, run yang-toolkit's own flow, record it |
| Status gate: plan is parked (`awaiting-*`)               | present the one question     | abort with the question quoted -- UNLESS `--answer` supplied it, then resume |

Every `--yes` auto-resolution is recorded in the Execution Log so an
unattended run stays auditable.

## Two entry modes

### Mode A -- continue / latest draft
Triggered when no `--from` flag is given.

1. Read `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`. If
   non-empty, set `slug` from it.
2. Otherwise list `<HARNESS_ROOT>/.claude/plans/*.md`, filter to
   `status: draft` or `status: accepted`, sort by mtime descending.
   - exactly one match -> confirm with the user, then use it (`--yes`:
     skip the confirm)
   - multiple -> show the list, ask which (`--yes`: abort, require `--from`)
   - none -> abort with "no plan to execute; run /yang-toolkit:plan-feature first."

### Mode B -- explicit
Triggered by `--from <slug>`.

1. Read `<HARNESS_ROOT>/.claude/plans/<slug>.md`. If missing,
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
  `/goal`) / **reset** to draft / **abort**. `--yes`: resume.
- `done` -> REFUSE. Tell user: "use `/yang-toolkit:plan-feature --revise <slug>`
  to open a new revision."
- `failed` -> ask: re-run as-is, or revise first? `--yes`: abort (a failed
  plan needs a human look before an unattended re-run).
- `awaiting-input` / `awaiting-auth` -> a previous run parked a question in the
  plan's `waiting:` block. Read it and present that ONE question (the pending
  work is real; do not restart the plan around it). On an answer: clear
  `waiting:`, set `status: executing`, and resume from where the run stopped,
  carrying the answer into the downstream prompt. `--yes`: do NOT answer it --
  abort with the parked question quoted, since guessing it is exactly what the
  state exists to prevent.
  - With `--answer "<text>"`: the caller already has the user's answer, so do
    **not** re-present the question -- apply the text as the answer and resume.
    Echo the question and the supplied answer together in one line first, so a
    misrouted answer is visible rather than silently absorbed, and record both
    verbatim in the Execution Log. `--answer` supplies a *user's* answer; it is
    not an agent's own judgment and never satisfies an `awaiting-auth`
    authorization that the user did not actually give.
  - `--answer` is the ONE case where `--yes` may proceed on a parked plan: the
    answer came from the user, so nothing is being guessed.

### Acceptance Criteria parsing

A criterion takes one of two shapes, selected by its **reality anchor** (see
`conventions.md`). `Anchor:` is optional for back-compat -- a criterion with no
`Anchor:` line is treated as `testing`.

**Machine-checkable** (`Anchor: testing` or `pseudo-human`, or no anchor line):

```
- [ ] **<name>**
  - Anchor: testing
  - Check: `<command>`
  - Pass: <pass condition>
```

1. Extract `<name>`, `<command>`, `<pass>`.
2. `<command>` must be wrapped in backticks. If not, abort with the
   criterion name: "Criterion '<name>' Check is not a runnable command."
3. Run the **fuzzy-word lint** on `<pass>` (rules below). On any
   match, abort with: "Criterion '<name>' Pass uses fuzzy language
   ('<word>'). Replace with an observable condition."

**Judgment checkpoint** (`Anchor: human` or `adversarial-review`):

```
- [ ] **<name>**
  - Anchor: adversarial-review
  - Judge: <who judges>
  - Artifact: <the concrete thing judged>
  - Pass: <what a pass looks like>
```

1. `Check:` must be ABSENT. If a judgment-anchored criterion carries one,
   abort: "Criterion '<name>' is anchored to <anchor> but has a Check command;
   re-anchor it to testing or drop the Check."
2. `Judge:` and `Artifact:` are both required. Abort naming whichever is missing.
3. **The fuzzy-word lint does NOT run** on these -- a judgment criterion is
   allowed to say "reads clearly" precisely because a person or a review agent,
   not a regex, is the check. `Judge:` must name a concrete judge (`the user`,
   or a review agent), never "someone" or "we".
4. An unknown `Anchor:` value aborts, listing the four valid ones.

A plan whose criteria are ALL judgment checkpoints is valid (a docs-only or
prose-only plan) -- it simply produces no `/goal` command clauses in Step 3.

### Fuzzy-word list

Default (hard-coded), case-insensitive whole-word match:

```
good, acceptable, nice, clean, mostly, properly, correctly,
robust, performant, scalable, maintainable, sufficient, reasonable
```

**Project override**: if
`<HARNESS_ROOT>/.claude/plans/.fuzzy-words` exists, REPLACE
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
- **Only machine-checkable criteria become command clauses.** A `human` or
  `adversarial-review` criterion has no runnable command, so it contributes no
  `running \`...\`` line. List those separately, after the command clauses, as:
  `AND <name>: <Judge> has judged <Artifact> and it <Pass>.` The goal evaluator
  cannot self-satisfy these -- they are closed in Step 6's checkpoint pass.
- If EVERY criterion is a judgment checkpoint, skip `/goal` entirely for this
  run (treat as `--no-goal`) and say so: there is nothing for the evaluator to
  poll, and the checkpoints are the completion test.
- Skip the `OR stop after ...` clause if `time_budget` frontmatter is
  absent.
- Skip the `AND <Out of Scope ...>` lines if the section is empty.
- Total length MUST be <= 4000 characters. If over, abort and tell
  the user to either shrink criteria or split the plan into multiple
  linked via `depends_on`.

Print the assembled condition. **Ask the user to confirm** before
proceeding -- this is the autopilot guardrail. With `--yes`, print the
condition but skip the confirm and proceed: the guardrail moves upstream
to the plan's `accepted` status (a human reviewed the criteria when
accepting the plan) and to `permissions.deny` as the hard floor.

### Auto mode (only if `--auto` is passed)

`/goal` removes per-turn prompts; **auto mode** removes per-tool
prompts. Either alone is half-automated; together they produce
unattended execution.

After the /goal condition is confirmed (or auto-confirmed via `--yes`)
AND before issuing `/goal`, attempt to enter auto mode for the session.
The exact mechanism is Claude-Code-version-specific (typically a `/auto`
slash command or an equivalent in-session toggle). If you cannot enable
it programmatically, prompt the user with the steps to enable it and
wait for confirmation before continuing (`--yes`: abort instead of
waiting -- never proceed half-attended).

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
2. Write the bare slug to
   `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` with the **Write**
   tool (it creates parent dirs). Do not `echo >` / `cd` -- use the Write tool.

## Step 5 -- resolve house rules, decide orchestration, delegate

### 5a -- resolve house rules

Skip this whole sub-step if `--ignore-house-rules` was passed; say so in the
Execution Log.

1. Read the plan's `delegate_to` frontmatter (written by
   `/yang-toolkit:plan-feature`'s Probe 0). If the key is absent -- an older
   plan, or one drafted elsewhere -- run the cheap discovery scan from the
   **Project house rules** section of `conventions.md` now, so plans predating
   this feature still get the benefit.
2. Verify each named skill/command still exists in this working tree. A stale
   entry (the project removed the skill) is dropped with a one-line note; never
   abort over it.
3. For every surviving entry, build a **house-rules digest** (~10 lines):
   which project skill owns which phase, plus the format conventions the
   project uses for artifacts written into its own tree.
4. **Announce** the delegation plan to the user before running anything:
   which phases go to project skills, which stay with yang-toolkit. This is a
   notice, not a prompt -- do not block on it (with `--yes`, identical).

The digest is injected as background context into whatever runs in Step 6, in
every orchestration mode. The bookkeeping -- plan artifact, `/goal` gate,
Acceptance Criteria verification, Execution Log, ledger -- is **never**
delegated, regardless of what the project's own skills claim to cover.

### 5b -- resolve orchestration

Read frontmatter `orchestration` (default `auto` when absent). A `--single`,
`--team`, or `--workflow` flag pins the mode outright and skips resolution.

`auto` resolves at run time from the plan's Files Touched -- the same
disjointness judgment that `workflow` mode requires anyway:

| Condition (first match wins)                                              | Resolves to |
| -------------------------------------------------------------------------- | ------------- |
| Step 5a found an implementation-phase owner                                | `single` -- only that mode can delegate to it |
| Fewer than 2 Files Touched entries, or 0                                   | `single`      |
| `discipline: tdd`                                                          | `single` -- red/green/refactor is inherently sequential |
| Entries collapse to fewer than 2 disjoint directory-affinity buckets       | `single`      |
| Buckets overlap on a shared module every worker would need to edit         | `single`      |
| >= 2 disjoint buckets, cleanly separable                                   | `workflow`    |

`auto` never resolves to `team`; that mode stays explicit (frontmatter or
`--team`), because long-lived teammates are a deliberate choice, not a
fallback. Print the resolved mode and the one-line reason before delegating,
and record both in the Execution Log and the ledger
(`orchestration` = resolved value, `orchestration_auto: true`).

**Declare, never ask.** This resolution is a routing decision, so it is stated
and then acted on -- there is no confirm step, no "single or team?" question,
and no offer to switch. The user overrides it in one sentence (or with a flag)
on the next run. The same applies to `discipline`, which the plan already
carries as a judgment, not an answer.

Four modes:
- `auto` -- resolve per the table above. **Default.**
- `single` -- sequential `/goal` loop, delegates to one downstream
  command. Best for tightly-coupled changes.
- `workflow` -- deterministic parallel fan-out via the built-in
  `Workflow` tool. Best when Files Touched split cleanly into
  **disjoint** slices (different dirs/subsystems) that can be built
  concurrently. This is the recommended parallel mode.
- `team` -- experimental agent-teams (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`).
  Kept for back-compat; prefer `workflow` unless you specifically want
  long-lived teammates that message each other.

### single

**House-rules delegation first.** If Step 5a produced an owner for the
implementation phase, compose the same plan-context prompt described below but
invoke **that project skill/command** instead of the yang-toolkit downstream
command, with the house-rules digest attached. The `/goal` condition still
gates the run and Step 7 still closes it out -- only the implementer changes.
Record the delegate name for the ledger's `delegated_to`. If the project skill
errors or is unavailable at invocation time, fall back to the branch below and
note the fallback in the Execution Log.

Otherwise, branch on `discipline`:

- `tdd` -> compose a prompt that embeds the plan content (Goal +
  Acceptance Criteria + Files Touched + dep summaries), then invoke
  `/yang-toolkit:tdd-feature --from <slug>`. The downstream command
  will find/create the decision dir and start cycling.
- `normal` -> same approach with `/yang-toolkit:feature-dev-tracked`.
  Because that command does not yet accept `--from`, pass the plan's
  Goal as the natural-language argument; slug derivation is
  deterministic so the decision dir lines up. The state pointer set
  in Step 4 takes precedence.

### workflow

Delegate to the bundled deterministic fan-out script instead of the
`/goal` loop. The script lives in the plugin at
`${CLAUDE_PLUGIN_ROOT}/workflows/execute-plan-team.workflow.js`.

1. **Do NOT issue `/goal`** in this mode -- the workflow's Verify phase
   is the completion check, so skip Step 3's `/goal` setup (treat it as
   `--no-goal`). If `--auto` was passed, still apply auto mode so the
   workflow's agents don't pause for per-tool approval.
2. Invoke the `Workflow` tool with `scriptPath` set to the absolute
   path of `execute-plan-team.workflow.js` (resolve `${CLAUDE_PLUGIN_ROOT}`
   yourself) and `args` set to the parsed plan as a JSON value:
   ```
   {
     "slug": "<slug>",
     "goal": "<# Goal text>",
     "acceptanceCriteria": [ { "name": "...", "check": "...", "pass": "..." }, ... ],
     "filesTouched": [ "<path or glob>", ... ],
     "outOfScope": [ "<bullet>", ... ],
     "depSummaries": [ "<~100-token dep blurb>", ... ],
     "houseRules": [ "<one format convention per line>", ... ],
     "teamSize": <frontmatter team_size, default 3>
   }
   ```
   Pass `args` as an actual JSON object, never a stringified blob.
   `houseRules` carries Step 5a's format conventions (omit or pass `[]` when
   there are none) so every worker writes project-shaped artifacts. Phase
   *ownership* is not expressible here -- the workflow's agents are the
   implementers -- which is why `auto` resolves to `single` whenever an
   implementation-phase owner exists. If `workflow` was pinned explicitly
   (frontmatter or `--workflow`) while an owner exists, honor the pin but warn
   once that the project's implementation skill will be bypassed this run.
3. **Disjointness precondition**: the workflow partitions Files Touched
   into disjoint slices and runs them concurrently in the working tree
   (no worktree isolation). Before invoking, sanity-check that the plan's
   Files Touched are reasonably separable by directory. If they look
   heavily overlapping (e.g. many globs over one file, or every worker
   would need the same shared module), **state** that this run may produce
   `scopeViolations` and proceed -- routing is declared, not asked. (This only
   ever happens on an explicit `--workflow` / frontmatter pin; `auto` resolves
   overlapping Files Touched to `single` before reaching here.) Surface any
   `scopeViolations` afterwards per Step 7 and recommend a `--single` re-run
   then, when there is an actual result to judge.
4. The workflow returns a result object (see Step 7's workflow branch).
   Do not poll; the tool re-invokes you when it finishes.

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

**`single` / `team` modes**: issue `/goal <condition>` (unless
`--no-goal`), then send the opening prompt that delegates to the chosen
downstream command (or spawns the team). Monitor at session boundaries
only; do not poll. When the session ends -- by goal achievement, by
user `/goal clear`, by error, or by budget exhaustion -- proceed to
Step 7.

**`workflow` mode**: the `Workflow` tool invocation in Step 5 already
launched the run. It executes in the background and re-invokes you on
completion with the result object -- do not poll. When the result
arrives, proceed to Step 7's workflow branch.

### Anchor checkpoints (before Step 7)

Machine-checkable criteria are closed by the `/goal` evaluator (or the
workflow's Verify phase). Judgment criteria are closed here, once
implementation is done:

- **`adversarial-review`** -- run the review against the named `Artifact`, with
  fresh context (a subagent, or `/code-review` if installed). It attacks the
  result against the plan's Goal and the criterion's `Pass`. Correctness and
  contract findings go back into the working loop and the run continues;
  nits close with an explicit one-line disposition. Record the review once
  against the run. This is agent work, not a user question -- never park it.
- **`human`** -- this one genuinely needs the user. Present the `Artifact` and
  the `Pass` condition and ask. If the session cannot wait (unattended, or the
  user is not present), **park it** per the rule below rather than guessing.

### Parking a decision instead of failing

A run that hits something only the user can settle -- a `human` anchor with no
user present, a substantive work question, or a gated mutation (a merge, a push
outside the task's branch, a destructive migration) -- writes the plan's
frontmatter to `awaiting-input` or `awaiting-auth` with a `waiting:` block:

```yaml
status: awaiting-input        # or awaiting-auth
waiting:
  since: <ISO8601 UTC now>
  run: <run number>
  kind: human-anchor | work-question | authorization
  question: <the one question, in one sentence>
  artifact: <path or reference the user needs to look at, if any>
```

Then stop cleanly: append the Execution Log for the partial run, keep
`current-feature.txt` pointing at the slug (the run is not over), and append a
ledger record with `outcome: in-progress` -- **`waiting` is not `failed`**, and
it consumes no controlled-vocabulary outcome. Report the question to the user
as the last thing the run says.

Parking is a last resort for the *unattended* case. An interactive run asks the
question directly and carries on; there is no reason to park what can be
answered in the same turn. Never park a routing decision -- routing is declared.

### Delegated review / archive phases

If Step 5a produced an owner for the **review** phase, invoke it once
implementation finishes and before Step 7, passing the plan's Goal and the
files actually changed. Surface its findings to the user verbatim; they do
**not** override the Acceptance Criteria verdict, which remains the sole
outcome gate. If it reports blocking issues while every criterion passed, say
so plainly and let the user decide.

If Step 5a produced an owner for the **archive / close** phase, invoke it after
Step 7's plan-status and ledger updates -- never before, so the harness record
is written even if the project's archive step fails.

Record each delegated phase (and any that errored) in the Execution Log and in
the ledger's `delegated_to`.

## Step 7 -- close out

1. **Determine final outcome**:

   Any mode, checked FIRST:
   - the run parked a decision (Step 6) -> plan `status: awaiting-input` /
     `awaiting-auth`, ledger `outcome: in-progress`. Skip steps 2 and 6 below:
     do NOT set `done`/`failed`, and do NOT clear `current-feature.txt`.
   - a judgment criterion is still unclosed and was not parked -> `failed`;
     name the criterion. A judgment checkpoint is never silently assumed passed.

   `single` / `team` modes:
   - goal evaluator returned achieved -> `done`
   - user `/goal clear` or explicit stop -> `abandoned` (in ledger;
     plan status stays `executing` so resume is the natural action)
   - turn budget exhausted -> `failed`
   - downstream command errored unrecoverably -> `failed`

   `workflow` mode (read the returned result object):
   - `result.achieved === true` (every criterion passed, no failures)
     -> `done`
   - any `result.criteria.failed > 0` -> `failed`; quote each failing
     verdict's `name` + `evidence` to the user
   - `result.error` set (e.g. `no-files-touched`) -> `failed`
   - `result.scopeViolations` non-empty -> still use the criteria
     verdict for outcome, but ALWAYS surface the violations: partitions
     overlapped, so the parallel result may be unreliable. Recommend a
     `--single` re-run if any criterion also failed.

2. **Update plan frontmatter**:
   - `status: done` or `status: failed` (NOT for abandoned)
   - `finished_at: <ISO8601 UTC now>`

3. **Append `## Execution Log` section** to the plan file (extend if re-run).
   Use the **Edit** tool to splice the section into the plan markdown (or
   Read → modify → Write the whole file). Never shell-redirect into the plan.
   Include:
   - run number (1 if first)
   - `started_at`, `finished_at`, duration
   - outcome
   - orchestration mode used -- and, when it came from `auto`, the resolution
     reason quoted from Step 5b
   - house rules: which phases were delegated to which project skill, any
     stale/failed delegate, or "none found" / "ignored by flag"
   - per-criterion anchor and how it closed: a Check command's result, the
     adversarial review's disposition, or the user's judgment
   - if the run parked: the `waiting:` kind and question, verbatim
   - `single` / `team`: goal evaluator's final reason quoted verbatim,
     turn count, approx token count, downstream command used
   - `workflow`: worker count + partition map, per-criterion pass/fail
     table from `result.verdicts` (quote failing `evidence` verbatim),
     and any `result.scopeViolations`
   - whether any Files Touched scope-guard violations were observed

4. **Append ONE record** to `<HARNESS_ROOT>/.claude/ledger.jsonl` per the
   conventions append rule (Read+Write, never shell redirection). The record
   matches the base ledger schema plus these extras:
   ```
   "plan_path":      ".claude/plans/<slug>.md",
   "goal_turns":     <int or null>,                 // null in workflow mode (no /goal loop)
   "orchestration":  "single" | "team" | "workflow", // the RESOLVED mode, never "auto"
   "orchestration_auto": true,        // omit unless `auto` resolved the mode this run
   "workers":        <int>,                          // workflow mode only: result.workers
   "criteria_pass":  <int>,                           // workflow mode only: result.criteria.passed
   "criteria_fail":  <int>,                           // workflow mode only: result.criteria.failed
   "deps_ignored":   [<slug>, ...],  // omit field entirely if empty
   "delegated_to":   { "<phase>": "<project skill/command>", ... },  // omit if no delegation happened
   "anchors":        { "testing": <int>, "adversarial-review": <int>, ... },  // criteria per anchor; omit if all testing
   "waiting":        "human-anchor" | "work-question" | "authorization"  // omit unless the run parked
   ```
   `outcome` follows the conventions controlled set. Plan-status `done`
   maps to ledger `outcome: in-progress` by default (a PR isn't necessarily
   merged yet); promote to `merged` after the merge via
   `/yang-toolkit:ledger-append --close <slug>`.

5. **Curate CLAUDE.md**: if the `/yang-toolkit:curate-claude-md`
   skill is available, invoke it so learnings get absorbed. If
   unavailable, skip and mention in the final report.

6. **Clear** `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` by
   writing an empty string to it with the **Write** tool (do NOT `rm` /
   `truncate` / `> file`).

7. **Report** to the user:
   - plan path and final status
   - ledger line appended
   - whether the goal was achieved
   - any anomalies (deps_ignored, scope violations, status not
     changed because abandoned, etc.)
   - if outcome is `in-progress` and a PR will follow: remind them to run
     `/yang-toolkit:ledger-append --close <slug>` after it merges.

## --dry-run mode

After Step 3, instead of writing state or executing:
- print the parsed Acceptance Criteria
- print resolved `depends_on` summaries
- print the Step 5a house-rules digest and the phase -> delegate map
- print the Step 5b resolved orchestration mode and the reason it was chosen
  (so `auto` can be inspected without committing to a run)
- `single` / `team`: print the assembled `/goal` condition and which
  downstream command would be invoked, with what arguments
- `workflow`: print the `args` object that would be passed to
  `execute-plan-team.workflow.js`, and the directory-affinity partition
  of Files Touched into `team_size` buckets (so the user can eyeball
  whether the slices are actually disjoint before a real run)
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
| Plan has no `orchestration` key at all (pre-0.17.0 plan)                            | Treat as `auto` and resolve per Step 5b. Note it in the Execution Log; do not rewrite the plan's frontmatter.                                    |
| `auto` resolves to `workflow` but the user expected sequential work                | The resolution reason is printed before delegating; they can stop and re-run with `--single`. Never resolve silently.                            |
| Plan has `delegate_to` but the named skill no longer exists in the repo            | Drop that entry with a one-line note, run the phase with yang-toolkit's own flow, and record the drop in the Execution Log. Never abort.         |
| Delegated project skill errors mid-phase                                           | Fall back to yang-toolkit's own flow for that phase, record the fallback in the Execution Log and in `delegated_to` (suffix the value `(failed)`). |
| Project skill claims to own the plan/ledger/verification itself                     | Ignore that claim -- bookkeeping is never delegated. Delegate only the implementation/review/archive work.                                       |
| Criterion has `Anchor:` with no `Check:` and no `Judge:`/`Artifact:`                | Abort Step 1 naming the criterion; the plan is malformed either way. Point at `/yang-toolkit:plan-feature --revise <slug>`.                       |
| Every criterion is a judgment checkpoint (docs/prose-only plan)                    | Valid. Skip `/goal` (nothing to poll), run the Step 6 checkpoint pass, close out normally.                                                       |
| `human` anchor reached in an unattended run (`--yes` / loop)                        | Park as `awaiting-input`, kind `human-anchor`. Never self-judge a human anchor, and never downgrade it to `adversarial-review` to avoid parking.  |
| Plan already `awaiting-input`/`awaiting-auth` and the user answers                  | Clear `waiting:`, set `status: executing`, resume the run with the answer in the downstream prompt. Do NOT restart from Step 1's status gate again. |
| `--answer` passed but the plan is not parked                                        | Ignore it with a one-line note and run normally. An answer to a question nobody asked is a routing mistake upstream, never a reason to skip a step.  |
| `--answer` passed for an `awaiting-auth` plan and the text does not actually authorize | Treat it as not authorized: re-park (or keep parked) and say why. An ambiguous answer is not consent to a gated mutation.                         |
| A parked plan sits unanswered across many loop ticks                                | The loop stays quiet on it (see `/yang-toolkit:loop`); it is not a failure and must not be retried, re-parked, or counted against the budget.     |
| Workflow mode but Files Touched are not separable into disjoint slices             | Only reachable on an explicit `--workflow`/frontmatter pin (`auto` resolves this to `single`). State the `scopeViolations` risk and proceed — do not ask. Surface any violations from the result afterwards and recommend a `--single` re-run then. |
| Workflow mode but plan has 0 Files Touched                                          | Script returns `{ error: 'no-files-touched' }`; mark outcome `failed`, tell user to add Files Touched and re-run.                                |
| Workflow result has failing criteria                                               | Mark `failed`; quote each failing verdict's `name` + `evidence`. Plan status -> `failed`; user can `--revise` then re-run.                       |
| `execute-plan-team.workflow.js` not found at `${CLAUDE_PLUGIN_ROOT}/workflows/`     | Abort before launch; tell user the plugin install may be incomplete. Suggest `--single` as a fallback for this run.                              |
| Plan `status: executing` at invocation                                             | Ask resume / reset / abort. On resume, keep `started_at` but DO re-issue `/goal` (its evaluator clock resets on session resume regardless).      |
| Downstream command unavailable                                                     | Abort before `/goal` is set. Suggest installing the relevant plugin.                                                                              |
| Assembled `/goal` condition exceeds 4000 characters                                | Abort. Suggest shrinking criteria or splitting the plan into pieces linked via `depends_on`.                                                      |
| Files Touched scope violated during execution (only detectable if a hook is wired) | Continue, but record the violation in Execution Log. Scope-guard hooks are opt-in; absent hooks make this best-effort.                            |
| `/yang-toolkit:curate-claude-md` not installed                                     | Skip step 7.5; mention in final report. Do not abort.                                                                                             |
| `--auto` passed but auto mode cannot be enabled in this Claude Code version        | Warn, print manual enable steps, wait for user confirmation. Do NOT proceed silently as if auto mode were active. With `--yes`, abort instead of waiting. |

## Failure modes

- Plan file unreadable: abort.
- Ledger unwritable: complete execution and frontmatter updates, then
  surface "ledger write failed" with the exact JSON line that should
  have been appended, so the user can run
  `/yang-toolkit:ledger-append` manually.
- `current-feature.txt` cannot be written or cleared: warn but
  continue -- it's a convenience pointer, not a correctness gate.
