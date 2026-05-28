---
name: dashboard
description: Read the current repo's `.claude/ledger.jsonl` and render an HTML artifact -- timeline + feature kanban + per-agent token distribution. TRIGGER on /dashboard, "最近做了什麼", "本專案進度", "dashboard", "this project status".
---

# dashboard

## Purpose
Visualize the cross-task observability layer for the current repo. Inputs are
ledger entries written by the Stop hook (or backfilled via /ledger-append).

## Input contract
A single file: `${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl`.
Each line is a JSON object with these fields (controlled vocabulary):

```
{
  "ts":      ISO8601 string,
  "feature": string,                                              // feature slug
  "phase":   "discovery"|"architecture"|"implementation"|"review"|"summary",
  "agent":   string,                                              // agent name
  "outcome": "in-progress"|"merged"|"abandoned"|"failed",
  "files":   number,
  "tokens":  number,
  "tools":   { [tool_name: string]: number },
  "pr":      string | null,
  "commit":  string | null
}
```

## Behavior
1. Read `.claude/ledger.jsonl`. If missing, report "no ledger yet" with a hint
   to run `/feature-dev-tracked` or `/ledger-append`.
2. Load the HTML template at
   `${CLAUDE_PLUGIN_ROOT}/skills/dashboard/templates/dashboard.html`.
3. Replace the contents of the `<script type="application/json" id="ledger-data">`
   block with the actual ledger entries (one JSON array, not JSONL).
4. Write the rendered HTML to `${CLAUDE_PROJECT_DIR}/.claude/dashboard.html`
   and offer to open it (`open` on macOS).

## Output
- `${CLAUDE_PROJECT_DIR}/.claude/dashboard.html` (overwrites previous render)

## Notes
- The template ships with 8-12 rows of mock data so it previews correctly
  before any real ledger exists. Always REPLACE that block; never append.
- Do not modify CSS / JS in the template from this skill -- if the user wants
  styling changes, edit the template directly.

<!-- TODO: implement the actual replace step (read template, regex/replace the
     script block payload, write to .claude/dashboard.html). -->
