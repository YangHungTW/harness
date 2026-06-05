---
name: dashboard
description: Read the current repo's `.claude/ledger.jsonl`, join it with the live git working tree + recent commits, and render a paired artifact -- an interactive HTML view (timeline, feature kanban, per-agent tokens, and an in-browser diff reviewer) plus a markdown view for review/AI. TRIGGER on /dashboard, "最近做了什麼", "本專案進度", "dashboard", "this project status".
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
a per-worktree artifact written to
`${CLAUDE_PROJECT_DIR}/.claude/dashboard-{TS}.html`, where `{TS}` is a compact
UTC timestamp (see "Timestamps" below). Each render is a new, timestamped
snapshot -- previous renders are left in place, so the directory accumulates a
history of dashboards rather than overwriting one file.

## Timestamps
Compute both with a single `date` call each, just before writing:
- **Filename `{TS}`** -- compact basic-ISO, filesystem-safe (no colons),
  lexically sortable: `date -u +%Y%m%dT%H%M%SZ` -> e.g. `20260605T031421Z`.
- **Content timestamp** -- full ISO 8601 UTC embedded in the page:
  `date -u +%Y-%m-%dT%H:%M:%SZ` -> e.g. `2026-06-05T03:14:21Z`.

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

## Git side-channel (a SECOND read-only source, joined at render time)
The dashboard also embeds real git data so the change can be **reviewed in the
browser without opening an IDE**. This is collected fresh at render time and
embedded into the page; it is NEVER written back to `ledger.jsonl`. Git commits
do not map onto the ledger's `feature/phase/agent/outcome` schema, and a second
writer to the ledger would create a real sync problem -- so the dashboard *joins*
the two sources at render time instead. Commits appear here even if they never
went through a /yang-toolkit flow (this is how "git history 自動補" is satisfied).

Use the CURRENT worktree (`${CLAUDE_PROJECT_DIR}`) -- that is where uncommitted
changes live. All commands are READ-ONLY; tolerate any failure (skip that piece).

1. **Availability.** `git -C "${CLAUDE_PROJECT_DIR}" rev-parse --is-inside-work-tree`.
   If it is not `true` (no git, bare, error): embed `{"unavailable": true}` in the
   git-data block and SKIP the rest of this section. The page degrades to a
   "no git data" note.
2. **Context.** `branch` = `git -C "$DIR" rev-parse --abbrev-ref HEAD`;
   `head` = `git -C "$DIR" rev-parse --short HEAD`;
   `repo` = basename of `git -C "$DIR" rev-parse --show-toplevel`.
3. **Working tree (the "this change" the user most wants).**
   `git -C "$DIR" status --porcelain=v1`. `dirty` = (any output). For each entry
   build one `working[]` item `{file, status, staged, patch}`:
   - `status` = first status char (`M`/`A`/`D`/`R`/`?`); `staged` = true if the
     index column (first column) is non-space.
   - `patch`: staged change -> `git -C "$DIR" diff --cached -- <file>`; unstaged
     change -> `git -C "$DIR" diff -- <file>`. Untracked (`??`) -> leave `patch`
     empty (the renderer shows a placeholder). A file changed in BOTH index and
     worktree: emit two items (one staged, one unstaged).
4. **Recent commits.**
   `git -C "$DIR" log --since="14 days ago" --max-count=30 --no-merges --pretty=format:'%H%x09%h%x09%an%x09%aI%x09%s'`.
   Tab-split into `{sha, short, author, date, subject}`. For each commit, per-file
   stats + patch from `git -C "$DIR" show <sha> --no-color --format= --numstat`
   (gives `added  removed  file`) and `git -C "$DIR" show <sha> --no-color
   --format= -- <file>` (or split one `git show <sha>` patch by `diff --git`).
   Build `files:[{file, added, removed, patch}]`.
5. **Bounds (keep the artifact reasonable -- and `log()` anything you drop):**
   - commits: 14-day window, max 30 (already in the command).
   - per-file patch: cap ~400 lines; if longer, truncate and append a line
     containing `... diff truncated (N more lines) ...` (the renderer styles any
     line containing "diff truncated" distinctly).
   - binary files: no patch -- leave it empty.
   - total git payload target < ~1 MB. If over: first drop OLDEST commit patches
     (keep their row + numstat), then drop all commit patches; ALWAYS keep the
     working-tree diffs (that is the change being reviewed).
6. **Privacy.** The patches embed real source into the artifact. That is fine for
   the local, git-ignored `.claude/` output, but do not paste the artifact
   somewhere public assuming it is just metadata.

Embed the assembled object (shape documented in the template's `git-data`
comment) by REPLACING the contents of the
`<script type="application/json" id="git-data"> ... </script>` block.

## Behavior
1. Read `<HARNESS_ROOT>/.claude/ledger.jsonl`. If the file is missing,
   tell the user there is no ledger yet and to run `/feature-dev-tracked` or
   `/ledger-append` first, then STOP (do not write any artifact -- neither the
   HTML nor the markdown).
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
   block payload.
5. Collect the git side-channel (see that section) and REPLACE the contents of
   the `<script type="application/json" id="git-data"> ... </script>` block with
   the assembled JSON object (or `{"unavailable": true}`). Like the ledger block:
   REPLACE the payload, never append, and leave all other markup unchanged.
6. REPLACE the `__GENERATED_AT__` placeholder (inside the
   `<span id="generated-at">` footer) with the full ISO 8601 UTC content
   timestamp from "Timestamps". This is a plain text substitution -- do not
   touch any other markup.
7. Compute `{TS}` ONCE for this render (`date -u +%Y%m%dT%H%M%SZ`) and write the
   HTML to `${CLAUDE_PROJECT_DIR}/.claude/dashboard-{TS}.html` (a NEW file each
   run; do not overwrite older snapshots).
8. Write the **markdown companion** to
   `${CLAUDE_PROJECT_DIR}/.claude/dashboard-{TS}.md`, reusing the SAME `{TS}` and
   the SAME content timestamp and the SAME Rendered set from steps 3-5 (see
   "Two views, one source" and the markdown layout below). The shared `{TS}`
   makes the `.html` and `.md` a guaranteed pair.
9. Tell the user both paths, and offer to open the HTML -- on macOS run
   `open "${CLAUDE_PROJECT_DIR}/.claude/dashboard-{TS}.html"` with the same
   `{TS}`.

## Two views, one source (+ a read-only git join)
`ledger.jsonl` is the single source of truth for the observability layer. The
dashboard also *joins* a second, read-only source at render time -- the live git
working tree + recent commits -- purely for display. Neither artifact is written
back to either source. BOTH the `.html` and the `.md` are *pure renders* of the
same Rendered set (+ the same git snapshot) -- neither is data, neither is
authoritative, and they are NOT kept in sync with each other. They cannot drift
**as long as you always emit them together in one run, from the same parsed
entries and the same git read, stamped with the same `{TS}`**. The git join adds
no persistence, so it adds no sync surface: every render re-reads git fresh.
Rules:
- Always write the `.md` whenever you write the `.html` (and vice versa). Never
  regenerate just one.
- The `.html` is for humans; the `.md` is the review-/AI-friendly view (greppable,
  diffable, terminal-readable). A reader who wants raw data still reads
  `ledger.jsonl` directly.
- The `.html` is NOT a markdown-to-HTML conversion -- it is a self-contained
  client-side app that embeds the Rendered set and is interactive (outcome-toggle
  chips, a feature/agent search box, and click-a-feature-to-focus that re-renders
  every panel). The `.md` is the flat snapshot of the same data. Both still come
  from the one ledger; the interactivity lives entirely in the browser and adds
  no new data.
- Never hand-edit either file -- corrections go to the ledger, layout changes go
  to the HTML template or to the markdown layout in this skill.
- If an `.html` and `.md` ever show different `{TS}` values, the older one is
  stale; regenerate to get a matching pair.

## Markdown companion layout
Generate the `.md` directly from the Rendered set (no template file) so it mirrors
the HTML sections in plain text:

```
# harness // dashboard -- <repo name>
_Generated: <content timestamp, ISO 8601 UTC>._

- Last update: <most recent ts in Rendered set>
- Sessions this week: <count of Rendered entries in last 7d>
- Tokens this week: <sum of tokens over those entries, or "-" if all unknown>

## Timeline -- last 14 days
- <YYYY-MM-DD>: <feature> / <phase> / <outcome> (<agent>)   [most recent first]
  ...

## Feature status
- **<feature>** -- <latest phase> / <latest outcome> -- last touched <ts>
  ...

## Token use by agent (this week)
- <agent>: <tokens or ->

## Tool call heat (top 5)
- <tool>: <count>

## Changes (working tree)
_branch <branch> · HEAD <head> · <N> uncommitted_

```diff
<the uncommitted unified diff, same bounds as the HTML; "working tree clean"
if nothing is uncommitted>
```

## Recent commits (last 14 days)
- <short> <subject> (+<added>/-<removed>)
  ...
```

Apply the same source-dedupe and `tokens:0 == unknown` rules as the HTML. Omit a
section (or show "none") if it has no data rather than emitting an empty heading.
For the markdown, inline the **working-tree** diff (that is the change under
review) but list commits as one line each with their shortstat -- do NOT inline
every commit's full patch (it bloats the file; the full patches live in the
interactive `.html`). If git is unavailable, replace both Changes sections with a
single line "_git unavailable at render time_".

## Output
- `${CLAUDE_PROJECT_DIR}/.claude/dashboard-{TS}.html` -- interactive human view
  (filters, focus, in-browser diff reviewer)
- `${CLAUDE_PROJECT_DIR}/.claude/dashboard-{TS}.md`   -- review / AI view
  (flat data + working-tree diff)
Both share one `{TS}` and are a guaranteed pair; new timestamped snapshots per
render, older renders preserved.

## Notes
- The template ships with 8-12 rows of mock data (with `__T-N__` placeholder
  timestamps) so it previews correctly before any real ledger exists. Always
  REPLACE that block; never append.
- The template also carries a `__GENERATED_AT__` placeholder in the footer.
  Always substitute it with the real render time; if you forget, the raw
  placeholder text would ship in the page.
- The template carries a `<script ... id="git-data">` block with MOCK git data so
  it previews standalone. Always REPLACE its payload with the real git snapshot
  (or `{"unavailable": true}`); never leave the mock in a real render.
- The "Changes" panel is the in-browser review surface: the working tree and each
  commit expand to a colorized diff on click. It is for reading the change, not
  editing it -- no IDE needed. Clicking a feature card/timeline block focuses that
  feature and dims commits not linked to it (by recorded `commit` SHA).
- Filenames are timestamped, so renders accumulate under `.claude/`. To find the
  newest, sort by name (the `{TS}` format sorts lexically = chronologically) or
  glob `dashboard-*.html` / `dashboard-*.md`. The newest `.html` and `.md` with
  the same `{TS}` are the current pair.
- The `.md` companion needs no template -- generate it inline from the Rendered
  set per "Markdown companion layout". Keep its content equivalent to the HTML;
  layout may differ, data must not.
- Do not modify CSS / JS in the template from this skill -- if the user wants
  styling changes, edit the template directly.
- The optional `"source"` field gates what counts: stats/kanban use only
  `"command"`/source-less entries; `"source":"stop-hook"` entries are recency
  only and are excluded from the embedded array.
- `"tokens": 0` is UNKNOWN, not zero -- avoid presenting it as a real "0 tokens"
  measurement; it commonly appears on stop-hook (and back-filled) entries.
