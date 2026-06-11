---
description: One-screen overview of in-flight work -- current feature, plan statuses, recent ledger tail. --abandon closes out an in-flight feature in one step (state + ledger + plan).
---

# /yang-toolkit:status

Read-only overview of the harness state, plus one mutating sub-action
(`--abandon`). Keep the whole report to one screen.

## Conventions

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` first -- it defines
`<HARNESS_ROOT>` resolution, the ledger schema, and the append rule used below.

## Default (no args) -- report

Gather, then render as a compact markdown report:

1. **In-flight feature**: `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`
   (non-empty -> show slug + matching decision dir under
   `docs/decisions/*-<slug>/` if any; empty/missing -> "none").
2. **Plans**: for each `<HARNESS_ROOT>/.claude/plans/*.md`, read frontmatter
   only; group by `status` (`executing` first, then `accepted`, `draft`,
   `failed`; collapse `done` to a count). Show `slug -- Goal first sentence`.
3. **Ledger tail**: last 5 lines of `<HARNESS_ROOT>/.claude/ledger.jsonl`
   (skip unparseable lines silently) as `ts . feature . phase . outcome`.
4. **Pending CLAUDE.md candidates**: count of lines in
   `<HARNESS_ROOT>/.claude/state/claude-md-candidates.jsonl` not marked
   handled, if the file exists.

End with ONE next-step suggestion, picked by state (first match wins):
- a feature is in flight -> "continue it, or `/yang-toolkit:status --abandon`"
- a plan is `accepted` or `draft` -> "run `/yang-toolkit:execute-plan --from <slug>`"
- a recent ledger entry is `in-progress` with a `pr` -> "after merge, run `/yang-toolkit:ledger-append --close <slug>`"
- otherwise -> no suggestion.

Missing files are normal (fresh repo): render the section as "none", never abort.

## --abandon [<slug>] -- close out an in-flight feature

Bundles the three-place manual cleanup into one confirmed step.

1. Resolve `<slug>`: from the argument, else from `current-feature.txt`. If
   neither yields one, abort: "nothing in flight; pass a slug explicitly."
2. Show what will happen and **ask for confirmation** (this is destructive of
   intent, not of files):
   - append a ledger record: schema per conventions, `phase: "summary"`,
     `outcome: "abandoned"`, `agent: "main"`, plus a short free-text reason
     the user supplies (store as `"note"`).
   - clear `current-feature.txt` (Write empty string).
   - if `<HARNESS_ROOT>/.claude/plans/<slug>.md` exists with
     `status: executing`, ask: reset to `draft` (resumable later) or mark
     `failed`. Other statuses are left untouched.
3. Apply, then print exactly what changed (ledger line, pointer cleared,
   plan status old -> new). Decision docs are never deleted.
