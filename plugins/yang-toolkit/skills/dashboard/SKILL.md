---
name: dashboard
description: Read the current repo's `.claude/ledger.jsonl` and render an HTML artifact -- timeline + feature kanban + per-agent token distribution. TRIGGER on /dashboard, "最近做了什麼", "本專案進度", "dashboard", "this project status".
---

# dashboard

## Purpose
Visualize the cross-task observability layer for the current repo. Inputs are
ledger entries written by the Stop hook (or backfilled via /ledger-append).

## Harness root (worktree-aware)

The ledger is **durable** state and lives in the **MAIN** git worktree so it is
shared across worktrees and survives worktree deletion. Resolve it once:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command yields nothing (no git, or not
a repo), fall back to `<HARNESS_ROOT>` = `${CLAUDE_PROJECT_DIR}`. In the main
worktree the two are identical, so non-worktree users see no change.

Read the ledger from `<HARNESS_ROOT>/.claude/ledger.jsonl`. The rendered HTML is
a per-worktree artifact and stays at `${CLAUDE_PROJECT_DIR}/.claude/dashboard.html`.

## Input contract
A single file: `<HARNESS_ROOT>/.claude/ledger.jsonl`.
Each line is a JSON object with these fields (controlled vocabulary):

```
{
  "ts":      ISO8601 string,
  "feature": string,                                              // feature slug
  "phase":   "discovery"|"architecture"|"implementation"|"review"|"summary",
  "agent":   string,                                              // agent name
  "outcome": "in-progress"|"merged"|"abandoned"|"failed",
  "files":   number,
  "tokens":  number,                                              // 0 == UNKNOWN, not "zero tokens"
  "tools":   { [tool_name: string]: number },
  "pr":      string | null,
  "commit":  string | null,
  "source":  "stop-hook" | "command" (OPTIONAL)                   // missing == "command"
}
```

The OPTIONAL `"source"` field distinguishes how an entry was written:
- `"command"` (or absent) -- authoritative, written by a /yang-toolkit command.
- `"stop-hook"` -- low-trust/supplementary, appended automatically by the Stop
  hook. These carry `outcome:"in-progress"`, `tokens:0`, and exist mainly as a
  recency signal. They MUST NOT be counted in stats or kanban (see Behavior).

`"tokens": 0` means UNKNOWN (the Stop hook cannot get a portable token count),
not "zero tokens". Treat 0 as "no token data" wherever it would mislead.

## Behavior
1. Read `<HARNESS_ROOT>/.claude/ledger.jsonl`. If the file is missing,
   tell the user there is no ledger yet and to run `/feature-dev-tracked` or
   `/ledger-append` first, then STOP (do not write any HTML).
2. Parse the file line by line as JSONL. For each line:
   - Skip blank/whitespace-only lines silently.
   - `try` to JSON-parse the line. If a line is malformed, emit a short warning
     naming the line number, skip that line, and continue with the rest. A few
     bad lines must never abort the whole render.
3. Apply the SHARED CONTRACT source-dedupe rule. Split the parsed entries:
   - **Rendered set** = every entry whose `"source"` is `"command"` OR whose
     `"source"` key is absent (back-compat). This set drives ALL stats, token
     sums, the timeline, and the feature kanban.
   - **Stop-hook set** = entries with `"source":"stop-hook"`. Use these ONLY as
     a per-feature "last active" recency signal: for each feature, note the most
     recent `ts` across BOTH sets so a feature that has only seen Stop-hook
     activity since its last command entry still shows as recently touched.
     NEVER add stop-hook entries to outcome counts, token sums, or kanban cards
     -- doing so would double-count. If you cannot express recency in the
     template, simply drop the stop-hook entries; never fold them into stats.
   - The JSON array you embed in step 4 is the **Rendered set** (a clean array
     of command/source-less entries). Do not embed stop-hook entries.
4. Read the template at
   `${CLAUDE_PLUGIN_ROOT}/skills/dashboard/templates/dashboard.html`.
   Find the `<script type="application/json" id="ledger-data"> ... </script>`
   block and REPLACE the entire contents between the opening and closing tags
   with the Rendered set serialized as a single JSON ARRAY (not JSONL). Leave
   the rest of the template (CSS/JS/markup) byte-for-byte unchanged. Never
   append to the template or to the existing data block -- always REPLACE the
   block payload. Write the result to `${CLAUDE_PROJECT_DIR}/.claude/dashboard.html`
   (overwriting any previous render), then offer to open it -- on macOS run
   `open "${CLAUDE_PROJECT_DIR}/.claude/dashboard.html"`.

## Output
- `${CLAUDE_PROJECT_DIR}/.claude/dashboard.html` (overwrites previous render)

## Notes
- The template ships with 8-12 rows of mock data (with `__T-N__` placeholder
  timestamps) so it previews correctly before any real ledger exists. Always
  REPLACE that block; never append.
- Do not modify CSS / JS in the template from this skill -- if the user wants
  styling changes, edit the template directly.
- The optional `"source"` field gates what counts: stats/kanban use only
  `"command"`/source-less entries; `"source":"stop-hook"` entries are recency
  only and are excluded from the embedded array.
- `"tokens": 0` is UNKNOWN, not zero -- avoid presenting it as a real "0 tokens"
  measurement; it commonly appears on stop-hook (and back-filled) entries.
