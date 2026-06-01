---
description: Draft a reviewable plan artifact for a feature. Pulls relevant context from ledger + CLAUDE.md, runs plan mode, emits .claude/plans/<slug>.md with auto-generated Memory References. Does NOT execute. Hand to /yang-toolkit:execute-plan when ready.
---

# /yang-toolkit:plan-feature

You are creating or revising a **plan artifact** -- a markdown file at
`${CLAUDE_PROJECT_DIR}/.claude/plans/<slug>.md` that the user will review
and `/yang-toolkit:execute-plan` will later parse and run.

Plans are deliberately decoupled from `docs/decisions/`: one plan can be
executed, fail, get revised, and re-executed without polluting the
decision-doc numbering.

## Inputs
- `$ARGUMENTS` -- one of:
  - natural-language feature description (Mode A -- fresh)
  - `--from <slug>` (Mode B -- replan an existing plan from scratch)
  - `--revise <slug>` (Mode C -- append a revision section, preserve original)

If `$ARGUMENTS` is empty, ask the user before doing anything else.

## Three entry modes

### Mode A -- fresh
Triggered when `$ARGUMENTS` is natural-language text (not `--from` or
`--revise`).

1. Derive a kebab-case `slug` from the description. Use the same rule
   `/yang-toolkit:feature-dev-tracked` uses so slugs are deterministic
   across commands.
2. Check `${CLAUDE_PROJECT_DIR}/.claude/plans/<slug>.md`. If it exists,
   STOP and ask the user: Mode B (replan from scratch) or Mode C
   (append a revision)? Do not silently overwrite.
3. Continue to **Memory recall** below.

### Mode B -- from existing (replan)
Triggered by `--from <slug>`.

1. Read `${CLAUDE_PROJECT_DIR}/.claude/plans/<slug>.md`. If missing,
   abort with "no such plan; check `ls .claude/plans/`".
2. Show the user the existing plan's Goal + Acceptance Criteria. Ask:
   "Replan from scratch will overwrite the whole file. Continue?"
3. On yes, continue to **Memory recall** with the existing plan
   content as additional context so the new draft can reference what
   was tried.

### Mode C -- revise (append)
Triggered by `--revise <slug>`.

1. Read the existing plan. If missing, abort.
2. Do NOT touch the existing content above `# Execution Log`. You will
   append a `## Revision N -- <ISO date>` block under the section(s)
   the user wants to change, and prepend a one-line note at the top.
3. Continue to **Memory recall** with the existing plan content as
   context.

## Memory recall (all modes, before drafting)

Pull four classes of past context. Cap each, do not dump full files.

1. **Ledger**: read `${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl` line
   by line. Score each entry by:
   - slug token overlap with the current slug
   - path/feature stem overlap (if the entry recorded any)
   - recency: 1.0 within 30 days, decaying linearly to 0 at 180 days
   Combined: `relevance * 0.6 + recency * 0.4`. Keep top 3.

2. **CLAUDE.md grep**: in every `CLAUDE.md` under the project root,
   search for lines mentioning any slug token or any path stem from
   the user's description. Keep up to 3 most relevant lines with
   `file:line` + the matching line.

3. **Decision dirs**: list `${CLAUDE_PROJECT_DIR}/docs/decisions/`,
   match dir names containing any slug token. For each match, read
   its `05-summary.md` (if present) and extract the first sentence.
   Keep top 2.

4. **Suggested depends_on** (auxiliary): if any ledger entry from
   step 1 has `outcome: in-progress` AND high relevance, surface it
   to the user as: "feature '<other-slug>' looks unfinished and
   related -- add to `depends_on`?" Only add to frontmatter if the
   user confirms. Never suggest `outcome: failed` entries (those
   belong in Risks, not depends_on).

If all four classes return nothing, do not invent. The Memory
References section will be left empty with a
`<!-- no prior context found -->` note.

## Draft the plan (Mode A and Mode B)

Enter plan mode if the session is not already in it. If plan mode is
unavailable for any reason, continue but mark the resulting file with
a `> ⚠ generated without plan mode; review more carefully.` blockquote
as the first body line.

Produce or overwrite `${CLAUDE_PROJECT_DIR}/.claude/plans/<slug>.md`
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
Lines without <!--auto--> are preserved on --revise. -->

- <!--auto--> [<type>] <path> -- <one-line takeaway>

# Execution Log
<!-- filled by /yang-toolkit:execute-plan post-hoc. Leave empty in draft. -->
```

Population rules:
- **Acceptance Criteria**: draft 2-5 criteria based on the user's
  description and recalled context. NEVER use fuzzy words in `Pass:`
  -- /execute-plan has a lint that will reject the plan. If you're
  unsure how to verify something, ASK the user; do not invent a
  command.
- **Files Touched**: best-effort prediction. User can correct on
  review.
- **Out of Scope**: list only feature-level scope cuts (specific
  subsystems, flows, schemas). Do NOT write "no changes outside Files
  Touched" -- /execute-plan enforces that automatically.
- **Memory References**: write the recall results from the previous
  section. Each auto line MUST start with `<!--auto-->` immediately
  after the dash so `--revise` can refresh it.

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
| Memory recall finds 0 hits across all four classes       | Leave Memory References empty with `<!-- no prior context found -->`. Do not fabricate.                                              |
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
