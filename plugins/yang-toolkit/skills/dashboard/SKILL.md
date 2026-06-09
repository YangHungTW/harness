---
name: dashboard
description: Read the current repo's `.claude/ledger.jsonl`, join it with the live git branch diff (this branch vs its base, including uncommitted changes), and render a paired artifact -- an interactive HTML view (timeline, feature kanban, per-agent tokens, and an in-browser code-review diff) plus a markdown view for review/AI. TRIGGER on /dashboard, "最近做了什麼", "本專案進度", "dashboard", "this project status".
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

Read the ledger from `<HARNESS_ROOT>/.claude/ledger.jsonl`. The rendered HTML/MD
are written to **`<HARNESS_ROOT>/.claude/`** as well -- i.e. the MAIN worktree,
NOT the current `${CLAUDE_PROJECT_DIR}`. This keeps the artifacts out of linked
worktrees (they don't clutter a temporary worktree and don't vanish when it is
removed), and co-locates them with the ledger they render. Output path:
`<HARNESS_ROOT>/.claude/dashboard-{TS}.html`, where `{TS}` is a compact UTC
timestamp (see "Timestamps" below). Each render is a new, timestamped snapshot --
previous renders are left in place, so the directory accumulates a history of
dashboards rather than overwriting one file.

(Note: the *git side-channel* below is still collected from the CURRENT worktree
`${CLAUDE_PROJECT_DIR}` -- that is where your working-tree changes live. Only the
written artifact is anchored to `<HARNESS_ROOT>`.)

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

The review surface is the **branch diff**: every file changed on this branch vs
its base, INCLUDING uncommitted edits, in one place. This is the key design point
-- the user commits as they go, so "only show uncommitted" would show nothing.
`git diff <base>` (no `...`) compares the base commit to the WORKING TREE, so it
captures committed-on-branch + staged + unstaged changes in a single diff.

1. **Availability.** `git -C "${CLAUDE_PROJECT_DIR}" rev-parse --is-inside-work-tree`.
   If it is not `true` (no git, bare, error): embed `{"unavailable": true}` in the
   git-data block and SKIP the rest of this section. The page degrades to a
   "no git data" note.
2. **Context.** `branch` = `git -C "$DIR" rev-parse --abbrev-ref HEAD`;
   `head` = `git -C "$DIR" rev-parse --short HEAD`;
   `repo` = basename of `git -C "$DIR" rev-parse --show-toplevel`;
   `dirty` = `git -C "$DIR" status --porcelain` is non-empty.
3. **Determine the base ref to diff against.** Try, in order:
   - the remote default: `git -C "$DIR" symbolic-ref --quiet refs/remotes/origin/HEAD`
     -> strip `refs/remotes/` (e.g. `origin/main`);
   - else `main`, else `master`, if such a ref exists.
   Resolve `base_sha = git -C "$DIR" merge-base HEAD <baseref>`. Set `base` to a
   short human label (e.g. `main`). If NO base can be found, or HEAD == base_sha
   (you are on the base branch with nothing ahead), set `base = null` and use
   `HEAD` as the diff target -- the review then shows just the uncommitted diff.
4. **Changes (the review).** Take `git -C "$DIR" diff --no-color <base_sha>` (or
   `git diff --no-color HEAD` when base is null) and split it per file. For stats,
   `git -C "$DIR" diff --numstat <base_sha>` gives `added  removed  file`; for
   status, `git -C "$DIR" diff --name-status <base_sha>` gives `M|A|D|R… file`.
   Build `changes:[{file, status, added, removed, patch}]`, one per changed file,
   where `patch` is that file's unified-diff hunk text.
5. **Commits ahead of base (context only).**
   `git -C "$DIR" log --no-merges --pretty=format:'%h%x09%an%x09%aI%x09%s' <base_sha>..HEAD`
   -> `commits:[{short, author, date, subject}]`. NO per-file patches here -- the
   diff in step 4 is the review; this list is just "what landed on the branch".
6. **Bounds (keep the artifact reasonable -- and `log()` anything you drop):**
   - per-file patch: cap ~800 lines; if longer, keep the first ~800 and append a
     line containing `... diff truncated (N more lines) ...` (the renderer styles
     any line containing "diff truncated" distinctly).
   - binary / rename-only files: empty `patch` (the renderer notes it).
   - total git payload target < ~2 MB. If over, drop the patch text of the
     LARGEST files first (keep their row + numstat so they still appear in the
     overview), and `log()` which files were dropped. Never silently omit a file.
7. **Privacy.** The patches embed real source into the artifact. That is fine for
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
   - The JSON array you inject (the ledger Edit below) is the **Rendered set** (a
     clean array of command/source-less entries). Do not embed stop-hook entries.
4. Compute `{TS}` ONCE (`date -u +%Y%m%dT%H%M%SZ`). **COPY the template
   verbatim** to the output path with a shell `cp` -- do NOT Read the template and
   Write it back, because reproducing the ~1100-line file by hand drops the
   `<style>` block and you ship an unstyled page (this is the #1 failure mode):

   ```
   cp "${CLAUDE_PLUGIN_ROOT}/skills/dashboard/templates/dashboard.html" \
      "<HARNESS_ROOT>/.claude/dashboard-{TS}.html"
   ```

   `cp` preserves every byte (all CSS/JS/markup); you then change ONLY the data.
   Write to `<HARNESS_ROOT>`, NOT `${CLAUDE_PROJECT_DIR}` -- the artifact is
   anchored to the main worktree.
5. Now make exactly **three targeted `Edit`s on the copied output file** (Read it
   first so Edit is allowed). Each replaces one token in place; you never retype
   the CSS/JS, so it cannot be lost. Use the surrounding tag as context so the
   match is unique (the bare token also appears in comments).

   **CRITICAL -- escape the JSON before injecting it.** Git diff patches routinely
   contain the literal string `</script>` (you are diffing HTML/JS files), which
   would close the data `<script>` block early and dump raw JSON onto the page. In
   BOTH JSON payloads below, after serializing, replace every `<` (U+003C) with
   the six-character escape `<` -- i.e. JS `json.replace(/</g, "\\u003c")`.
   `JSON.parse` restores it, but `<\/script>` can no longer terminate the tag, and
   `<!--` no longer opens a comment. (Optionally also escape `>` as `>`
   and `&` as `&`, but `<` is the one that matters.)
   - **Ledger** -- old:
     `<script type="application/json" id="ledger-data">`⏎`__LEDGER_DATA__`⏎`</script>`
     new: the same two tags wrapping the Rendered set as a single JSON ARRAY (not
     JSONL).
   - **Git** -- old:
     `<script type="application/json" id="git-data">`⏎`__GIT_DATA__`⏎`</script>`
     new: the same tags wrapping the git object from the side-channel section
     (or `{"unavailable": true}`).
   - **Generated-at** -- old: `<span id="generated-at">__GENERATED_AT__</span>`
     new: the same span wrapping the full ISO 8601 UTC content timestamp.

   Do NOT touch anything else. (If a token is somehow left unreplaced the page
   still renders -- the loaders degrade to empty states -- but always replace all
   three.)
6. Write the **markdown companion** to `<HARNESS_ROOT>/.claude/dashboard-{TS}.md`
   with the **Write** tool (it is small -- safe to Write directly), reusing the
   SAME `{TS}`, content timestamp, and Rendered set (see "Two views, one source"
   and the markdown layout below). The shared `{TS}` makes the `.html` and `.md` a
   guaranteed pair.
7. Report with a **clickable link**, not just a path. Resolve the ABSOLUTE path
   of the HTML and print it as a `file://` URL on its own line so the user can
   click it open directly (terminals render `file://` URLs as clickable):
   `file://<abs path>/.claude/dashboard-{TS}.html`
   Then also print the `.md` path, and offer the macOS fallback
   `open "<abs path>/.claude/dashboard-{TS}.html"` for anyone whose terminal does
   not linkify. Get the absolute path from the resolved `<HARNESS_ROOT>` (it is
   already absolute -- it came from `git worktree list`).

## Two views, one source (+ a read-only git join)
`ledger.jsonl` is the single source of truth for the observability layer. The
dashboard also *joins* a second, read-only source at render time -- the live git
branch diff (this branch vs base, uncommitted included) -- purely for display.
Neither artifact is written
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

## Changes (this branch vs <base>)
_branch <branch> vs <base> · HEAD <head> · <N> files · +<add>/-<del>
(includes uncommitted)_

```diff
<the full branch diff -- the same `git diff <base>` content as the HTML,
same bounds; "no changes vs <base>" if there is nothing to review>
```

## Commits on this branch
- <short> <subject>
  ...
```

Apply the same source-dedupe and `tokens:0 == unknown` rules as the HTML. Omit a
section (or show "none") if it has no data rather than emitting an empty heading.
For the markdown, inline the **full branch diff** (that is the change under
review) but list commits as one line each (subject only) -- the diff already
contains every change. If git is unavailable, replace both Changes sections with a
single line "_git unavailable at render time_".

## Output
Both written to `<HARNESS_ROOT>/.claude/` (the MAIN worktree), NOT the current
worktree:
- `<HARNESS_ROOT>/.claude/dashboard-{TS}.html` -- interactive human view
  (filters, focus, in-browser diff reviewer)
- `<HARNESS_ROOT>/.claude/dashboard-{TS}.md`   -- review / AI view
  (flat data + working-tree diff)
Both share one `{TS}` and are a guaranteed pair; new timestamped snapshots per
render, older renders preserved.

## Notes
- **Never reproduce the template by hand.** `cp` it, then `Edit` the three
  tokens. Re-typing the file via Read+Write is what drops the `<style>` block and
  ships an unstyled page -- the exact bug this skill is built to avoid.
- The template carries NO mock data: the data blocks hold the tokens
  `__LEDGER_DATA__` / `__GIT_DATA__`, and the footer holds `__GENERATED_AT__`.
  Replace all three. If you forget one, the loaders degrade to empty states (the
  page is still styled), but `__GENERATED_AT__` would show as literal text -- so
  always replace it too.
- Opening the bare template directly renders a fully-styled but EMPTY dashboard
  (the unreplaced tokens fail JSON.parse -> empty states). That is expected and is
  a quick way to eyeball the CSS.
- The "Changes" panel is the in-browser review surface: the FULL branch diff
  (this branch vs base, uncommitted included), one file per section, **expanded by
  default** with line numbers, a file overview to jump, and a collapse-all toggle.
  It shows your work whether or not you've committed it -- no IDE needed. The
  commit list below it is context only. Clicking a feature card/timeline block
  focuses that feature and dims commits not linked to it (by recorded `commit` SHA).
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
