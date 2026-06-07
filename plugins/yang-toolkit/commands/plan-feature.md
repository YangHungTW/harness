---
description: Draft a reviewable plan artifact for a feature. Runs a parallel research fan-out (codebase patterns + project history/ledger + conditional recency-grounded external research via deep-research), then plan mode, emitting .claude/plans/<slug>.md with auto-generated, typed Memory References. Does NOT execute. Hand to /yang-toolkit:execute-plan when ready.
---

# /yang-toolkit:plan-feature

You are creating or revising a **plan artifact** -- a markdown file at
`<HARNESS_ROOT>/.claude/plans/<slug>.md` that the user will review
and `/yang-toolkit:execute-plan` will later parse and run.

Plans are deliberately decoupled from `docs/decisions/`: one plan can be
executed, fail, get revised, and re-executed without polluting the
decision-doc numbering.

## Harness root (worktree-aware)

Durable state (plans, ledger) must live in the MAIN git worktree so it
survives deletion of any linked worktree and is shared across worktrees.
Resolve it once at the start:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command yields nothing or this is
not a git repo, fall back to `${CLAUDE_PROJECT_DIR}`. In the main worktree
the two are identical, so non-worktree users see no change.

Use `<HARNESS_ROOT>` for durable paths only:
- `<HARNESS_ROOT>/.claude/plans/...`
- `<HARNESS_ROOT>/.claude/ledger.jsonl`

Keep `${CLAUDE_PROJECT_DIR}` for ephemeral / branch-local paths:
`docs/decisions/`, logs, and `.claude/state/current-feature.txt`.

## Inputs
- `$ARGUMENTS` -- one of:
  - **any captured context** describing what you want (Mode A -- fresh): a plain
    description, a pasted terminal error, a bug / GitHub issue URL, a design
    mockup or screenshot (attach the image to the message), a Slack / meeting
    transcript, or a half-formed idea. You do NOT need a clean spec -- the
    research fan-out turns rough input into a grounded plan. If an image or a long
    transcript is attached, treat it as the PRIMARY source and mine it; do not ask
    the user to re-type or pre-summarize it (raw is better -- let the probes do
    the extraction against your codebase and history).
  - `--from <slug>` (Mode B -- replan an existing plan from scratch)
  - `--revise <slug>` (Mode C -- append a revision section, preserve original)
- Optional modifier (combine with Mode A): **`--deep`** -- for large or fuzzy
  efforts. It (a) forces Probe 3 (external recency research) on, and (b) applies
  the "plan for the plan" discipline: before drafting, first write down HOW you
  will research and structure this plan, then execute that. Asking the agent to
  plan its own approach before producing the deliverable is the single best trick
  for stopping it from cutting corners on a big task. The deliverable is still the
  `plan.md`.

If `$ARGUMENTS` is empty AND no image/transcript is attached, ask the user before
doing anything else.

## Three entry modes

### Mode A -- fresh
Triggered when `$ARGUMENTS` is natural-language text (not `--from` or
`--revise`).

1. Derive a kebab-case `slug` from the description (or, for image / transcript
   input, from the feature you infer from it). Use the same rule
   `/yang-toolkit:feature-dev-tracked` uses so slugs are deterministic
   across commands.
2. Check `<HARNESS_ROOT>/.claude/plans/<slug>.md`. If it exists,
   STOP and ask the user: Mode B (replan from scratch) or Mode C
   (append a revision)? Do not silently overwrite.
3. Continue to **Research fan-out** below.

### Mode B -- from existing (replan)
Triggered by `--from <slug>`.

1. Read `<HARNESS_ROOT>/.claude/plans/<slug>.md`. If missing,
   abort with "no such plan; check `ls .claude/plans/`".
2. Show the user the existing plan's Goal + Acceptance Criteria. Ask:
   "Replan from scratch will overwrite the whole file. Continue?"
3. On yes, continue to **Research fan-out** with the existing plan
   content as additional context so the new draft can reference what
   was tried.

### Mode C -- revise (append)
Triggered by `--revise <slug>`.

1. Read the existing plan. If missing, abort.
2. Do NOT touch the existing content above `# Execution Log`. You will
   append a `## Revision N -- <ISO date>` block under the section(s)
   the user wants to change, and prepend a one-line note at the top.
3. Continue to **Research fan-out** with the existing plan content as
   context.

## Research fan-out (all modes, before drafting)

Ground the plan in **your repo, your history, and what the community knows right
now** -- not generic training-data advice. Do this by running several research
probes **in parallel** (issue the Agent/Task calls in a single message so they
run concurrently), then consolidating. Each probe returns a short structured
digest; cap each, never dump full files.

Spawn these probes concurrently:

**Probe 1 -- Codebase patterns (always).** Explore the current repo for existing
patterns, conventions, and integration points relevant to the feature. Prefer the
`Explore` agent (read excerpts, not whole files). Return:
- 2-4 files whose structure the new work should mirror (`path -- why`)
- the naming / layering / test conventions to follow
- the seams where the feature plugs in (entry points, interfaces, configs)

**Probe 2 -- Project history & learnings (always).** Mine durable state for what
was already tried (this is your equivalent of "search my past solutions"):
- `<HARNESS_ROOT>/.claude/ledger.jsonl`, line by line. Score each entry by
  slug-token overlap, path/feature-stem overlap, and recency (1.0 within 30 days,
  decaying linearly to 0 at 180 days). Combined `relevance*0.6 + recency*0.4`;
  keep top 3.
- prior plans `<HARNESS_ROOT>/.claude/plans/*.md` whose slug tokens overlap;
  extract each one's Goal and any Risks that actually bit. Keep top 2.
- `${CLAUDE_PROJECT_DIR}/docs/decisions/` -- dir names containing a slug token;
  read `05-summary.md` (if present), first sentence. Keep top 2.
- every `CLAUDE.md` under the project root -- lines mentioning a slug token or
  path stem; keep up to 3 with `file:line` + the matching line.
Tag any related entry with `outcome: in-progress` as a depends_on candidate, and
any with `outcome: failed` as a Risk (never a depends_on).

**Probe 3 -- External recency research (conditional).** Run it when the feature
touches an external library / framework / API / unfamiliar tech, OR whenever
`--deep` is set. SKIP it for purely internal refactors (unless `--deep`) and say
you skipped it. Invoke the `deep-research`
skill (or a focused web search if that skill is unavailable) for *current* best
practices and recent pitfalls, the point being to beat six-month-old training
data. Return 2-4 grounded findings, each with a source link, plus any "people are
moving away from X" signals.

**Consolidate.** Merge the probe digests, de-dupe, and route the results:
- **Memory References** <- internal hits (ledger / decision / claude-md / prior
  plan) AND codebase patterns to mirror AND external findings -- each as one
  auto line, typed (see types below).
- **Risks** <- failed past attempts (Probe 2) + external pitfalls (Probe 3).
- **Files Touched** <- informed by Probe 1's integration points.
- **depends_on suggestion** <- any in-progress related work: surface it as
  "feature '<other-slug>' looks unfinished and related -- add to `depends_on`?"
  and add to frontmatter ONLY if the user confirms.

If every probe returns nothing, do not invent. The Memory References section is
left empty with a `<!-- no prior context found -->` note.

## Draft the plan (Mode A and Mode B)

Enter plan mode if the session is not already in it. If plan mode is
unavailable for any reason, continue but mark the resulting file with
a `> ⚠ generated without plan mode; review more carefully.` blockquote
as the first body line.

Produce or overwrite `<HARNESS_ROOT>/.claude/plans/<slug>.md`
using this exact skeleton:

```markdown
---
slug: <slug>
created_at: <ISO8601 UTC now>
discipline: <tdd | normal>           # ask user; default normal
orchestration: <single | team | workflow>  # ask user; default single
team_size: 3                          # parallel workers; used by team AND workflow
time_budget: 25 turns                 # optional; default 25
depends_on: []                        # filled only if user confirmed any
status: draft
---

# Goal
<one sentence>

# Acceptance Criteria
<!-- machine-parsed by /yang-toolkit:execute-plan. Each item MUST follow:
- [ ] **<short name>**
  - Check: `<runnable command in backticks>`
  - Pass: <observable condition; no fuzzy words>
-->

- [ ] **<criterion 1>**
  - Check: `<command>`
  - Pass: <observable condition>

# Files Touched
- <path or glob>

# Out of Scope
- <thing that must not change>

# Risks
- <narrative; not enforced>

# Memory References
<!-- auto-generated below; remove individual lines if irrelevant.
Lines without <!--auto--> are preserved on --revise.
<type> is one of: ledger | decision | claude-md | plan | pattern | external.
For [external], <path> is a URL. -->

- <!--auto--> [<type>] <path> -- <one-line takeaway>

# Execution Log
<!-- filled by /yang-toolkit:execute-plan post-hoc. Leave empty in draft. -->
```

Population rules:
- **Acceptance Criteria**: draft 2-5 criteria based on the user's
  description and the research findings. NEVER use fuzzy words in `Pass:`
  -- /execute-plan has a lint that will reject the plan. If you're
  unsure how to verify something, ASK the user; do not invent a
  command.
- **Files Touched**: best-effort prediction, informed by Probe 1's
  integration points. User can correct on review.
- **Risks**: include failed past attempts (Probe 2) and external
  pitfalls / "moving away from X" signals (Probe 3).
- **Out of Scope**: list only feature-level scope cuts (specific
  subsystems, flows, schemas). Do NOT write "no changes outside Files
  Touched" -- /execute-plan enforces that automatically.
- **Memory References**: write the consolidated research findings from
  the previous section, each typed (ledger / decision / claude-md /
  plan / pattern / external). Each auto line MUST start with
  `<!--auto-->` immediately after the dash so `--revise` can refresh it.

## Mode C (revise) differences

Do NOT overwrite the file. Instead:

1. **Refresh Memory References**: read the existing section, drop
   every line containing `<!--auto-->`, keep all other lines, then
   append freshly-recalled auto lines (also marked `<!--auto-->`).
2. **Append revision blocks**: add `## Revision <N> -- <ISO date>`
   under whichever section(s) the user wants to change. `N` = highest
   existing Revision number + 1, or 1 if none.
3. **Prepend top note**: immediately after the frontmatter, insert a
   `> Revision <N>: <one-line reason>` blockquote so reviewers see
   the change at a glance.
4. **Do NOT modify `status`**. If `status: done`, warn the user that
   the next `/yang-toolkit:execute-plan` run will produce a NEW
   ledger entry and a NEW `## Execution Log` block, but prior
   Execution Log entries are preserved.

## Handoff (no execution)

When the draft is written:
- Print the file path.
- Print a one-line research summary: which probes ran, and which were
  skipped or degraded (e.g. "external research skipped -- internal refactor").
- Print the list of auto-suggested `depends_on` slugs (if any) and
  whether each was accepted.
- Tell the user: "Review the plan. When ready, run
  `/yang-toolkit:execute-plan` or `/yang-toolkit:execute-plan --from <slug>`."
- Do NOT write `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`.
  That pointer is owned by `/execute-plan` once the plan is accepted.

## Edge cases

| Situation                                                | Behavior                                                                                                                              |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Mode A slug collides with an existing plan               | Stop, offer Mode B or Mode C. Never silently overwrite.                                                                              |
| All research probes return 0 hits                        | Leave Memory References empty with `<!-- no prior context found -->`. Do not fabricate.                                              |
| `deep-research` skill unavailable (Probe 3)              | Fall back to a focused web search; if that is also unavailable, skip Probe 3 and note "external research skipped" in the report.      |
| A parallel probe errors or times out                     | Continue with whatever the other probes returned; mention the degraded probe in the final report. Never block drafting on one probe. |
| User declines plan mode (or it errors)                   | Continue with the warning banner. Do not abort -- a flagged draft is still useful.                                                   |
| `depends_on` suggestion is an `outcome: failed` entry    | Do not suggest. Surface it as a Risks bullet instead.                                                                                |
| Mode C on a plan with no prior `<!--auto-->` lines       | Refresh produces a clean auto block. All previous user-added lines are preserved.                                                    |
| `.claude/plans/` cannot be created                       | Abort with the path that failed. Do NOT fall back to `/tmp`.                                                                          |

## Failure modes

- `.claude/plans/` cannot be created: abort, surface the error.
- Ledger contains a structurally invalid JSON line: skip it, continue,
  mention the line number in the final report.
- `CLAUDE.md` files exceed ~200 KB total: cap recall reads at the
  first 2000 lines per file and mention truncation in the report.
