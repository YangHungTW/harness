---
name: week
description: Cross-repo weekly report. Scans every harness-tracked client repo's `.claude/ledger.jsonl`, produces a markdown weekly recap grouped by client AND by feature. TRIGGER on /week, "週報", "weekly report".
model: haiku
---

# week

## Purpose
Roll up cross-project activity from the last 7 days. Uses the controlled-vocabulary
ledger schema so outcomes are aggregatable (`merged` count vs `abandoned`, etc.).

## Configuration

This skill reads its tracked-repo list from:

```
~/.config/harness/repos.json
```

Shape (this is the contract — produce/consume exactly this):

```json
{
  "repos": [
    {
      "client":  "string -- billing entity / engagement name",
      "name":    "string -- short slug, used in headings",
      "path":    "absolute path to the repo on disk",
      "active":  true
    }
  ]
}
```

A missing config file is treated as an empty list -- the skill walks the user
through creating it (see step 1 below).

## Ledger source-dedupe rule (REQUIRED)
Ledger entries MAY carry a `"source"` field:
- `"stop-hook"` — written automatically by the Stop hook. Low-trust / supplementary.
- `"command"` — written by a /yang-toolkit command. Authoritative.
- Entries with NO `"source"` key are treated as `"command"` (back-compat).

When computing **outcome breakdowns, token sums, hours-proxy, and feature
phase/outcome state**, EXCLUDE entries with `"source":"stop-hook"`. Use
stop-hook entries ONLY as a "last touched" recency signal — never count their
outcomes or sum their tokens. State this in the rendered report so the reader
knows which numbers are authoritative.

## Behavior
Execute these steps in order. Degrade gracefully — never abort on a single bad
file or line.

1. **Load config.** Read `~/.config/harness/repos.json`.
   - If the file is absent or unreadable, print this starter template to stdout
     and stop (do not error):

     ````
     No tracked repos yet. Create ~/.config/harness/repos.json:

     ```json
     {
       "repos": [
         {
           "client": "Acme Corp",
           "name": "acme-api",
           "path": "/absolute/path/to/acme-api",
           "active": true
         }
       ]
     }
     ```
     ````
   - Parse the JSON. If `jq` is available use it; otherwise read the structure
     directly. Keep only entries where `active` is `true`.
   - If the `repos` array is empty (or no entry is active), print "No active
     repos configured." and stop.

2. **Collect entries per repo.** For each active repo, read
   `<path>/.claude/ledger.jsonl`:
   - If the file is missing or empty, remember the repo under a
     **"no activity captured"** list and move on.
   - Read it line by line. Each line is one JSON object. If a line fails to
     parse, skip it and emit a single warning line to stderr of the form
     `warning: <path>/.claude/ledger.jsonl:<lineno> malformed, skipped` — do not
     abort the repo or the run.
   - Tag each parsed entry with its repo's `client` and `name` for later
     grouping.

3. **Filter to the last 7 days (UTC).** Compute the cutoff as `now - 7 days` in
   UTC. Keep entries whose `ts` (ISO-8601 UTC timestamp) is at or after the
   cutoff. Drop entries with a missing/unparseable `ts`. If a repo has zero
   in-window entries but had a ledger, treat it as "no activity captured" for
   this week.

4. **Split authoritative vs recency.** Partition the in-window entries:
   - **Authoritative** = entries where `source` is absent OR equals `"command"`.
   - **Recency-only** = entries where `source == "stop-hook"`.
   Per the source-dedupe rule above, ALL counts and sums below use the
   authoritative set only. The recency-only set contributes a single
   `lastTouched` timestamp per repo/feature: the max `ts` across BOTH sets
   (so a repo only touched by the Stop hook still shows recent activity).

5. **Build the two views.**

   - **By client** — one section per client (alphabetical). Within a client,
     aggregate across its repos:
     - list each distinct `feature` slug seen this week;
     - **hours-proxy**: sum `tokens` over authoritative entries (token sum is a
       coarse effort proxy). Render `tokens=0` / unknown sums as `-`, not `0`.
     - collect PR links from authoritative entries (any `pr`/`pr_url` field);
     - **outcome breakdown**: count authoritative entries by `outcome`
       (e.g. `merged`, `abandoned`, `in-progress`, etc.);
     - show `lastTouched` (from step 4).

   - **By feature** — one row per distinct `feature` slug across all clients
     (alphabetical). For each: owning client, latest **phase** and latest
     **outcome** taken from the most recent authoritative entry for that
     feature; and `lastTouched`. If a feature has only recency-only entries this
     week, mark its phase/outcome as `—` (no authoritative data) but still list
     it with its `lastTouched`.

6. **Render + emit.** Produce a single markdown document with this structure and
   write it to stdout:

   ```
   # Weekly Report — <YYYY-WW>
   _Generated: <now UTC, ISO 8601>._
   _Window: <cutoff UTC> .. <now UTC>. Stats from authoritative
   (command) ledger entries only; stop-hook entries used for recency only._

   ## By Client
   ### <client>
   - **Features:** <slugs>
   - **Hours-proxy (token sum):** <sum or ->
   - **Outcomes:** merged N, abandoned N, in-progress N, ...
   - **PRs:** <links>
   - **Last touched:** <ts>

   ## By Feature
   | Feature | Client | Phase | Outcome | Last touched |
   |---------|--------|-------|---------|--------------|
   | ...     | ...    | ...   | ...     | ...          |

   ## No activity captured
   - <name> (<client>)
   ```

   Omit the "No activity captured" section if that list is empty.

7. **Optional write.** If invoked with `--write`, also save the same markdown to
   `~/notes/weekly/<YYYY-WW>-<TS>.md` (create the `~/notes/weekly/` directory if
   needed), using ISO week numbering for `<YYYY-WW>` and a compact UTC timestamp
   for `<TS>` (`date -u +%Y%m%dT%H%M%SZ` -> e.g. `20260605T031421Z`). The week
   number keeps files grouped; the `<TS>` suffix makes each regeneration a
   distinct, sortable snapshot instead of overwriting the week's file. Print the
   saved path.

## Notes
- Be resilient: a malformed JSONL line is skipped with a warning, never aborts.
- A repo with no ledger (or no in-window entries) goes under "no activity captured".
- `jq` is optional throughout; when absent, fall back to direct parsing.
