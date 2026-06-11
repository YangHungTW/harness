---
description: Manually append one record to .claude/ledger.jsonl. For backfilling a missed session, correcting an automatic Stop-hook entry, or (--close) auto-closing a merged feature from gh PR state.
---

# /yang-toolkit:ledger-append

You are appending exactly ONE record to `<HARNESS_ROOT>/.claude/ledger.jsonl`.

## Conventions

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` first -- it defines
`<HARNESS_ROOT>` resolution, the full ledger schema, the controlled `outcome`
vocabulary, and the Read+Write append rule. Everything below assumes it.

## Mode 1 (default) -- manual record

Walk the user through the schema's required fields. If a value is given in
`$ARGUMENTS` already, use it without re-asking; otherwise ask:

1. `feature` -- short kebab-case slug
2. `phase` -- controlled vocabulary per conventions
3. `outcome` -- controlled vocabulary per conventions
4. `agent` -- which agent / persona did the work (or `unknown`)
5. `pr` -- PR URL, or "none" -> null
6. `commit` -- short SHA, or "none" -> null

**Do not invent any of these.** If the user gives a value outside a controlled
list, push back: list the allowed values and ask again. Optional fields
default per the schema (`files`/`tokens` -> 0, `tools` -> `{}`).

## Mode 2 -- `--close [<slug>]` (auto-close after PR merge)

Flips a feature's outcome to `merged` using `gh` as evidence instead of
interrogating the user.

1. Resolve `<slug>`: the argument; else `current-feature.txt`; else the most
   recent ledger entry with `outcome: "in-progress"`. None found -> abort:
   "nothing to close; pass a slug."
2. Find the PR: prefer the `pr` URL already on that feature's latest ledger
   entry; else `gh pr list --state merged --search "<slug>" --json url,mergeCommit,mergedAt --limit 5`
   (also try the current branch via `gh pr view`). Show the candidate(s) and
   confirm with the user if more than one or none is an exact match.
3. Check merge state via `gh pr view <url> --json state,mergeCommit,mergedAt`:
   - `MERGED` -> build the record: copy `feature` from the slug,
     `phase: "summary"`, `outcome: "merged"`, `pr` = URL, `commit` = short
     merge SHA, `agent: "main"`, `ts` = now.
   - not merged -> report the actual state, do NOT write anything.
   - `gh` unavailable / not authenticated -> fall back to Mode 1 questions
     for `pr` + `commit`, with `outcome: merged` only on user confirmation.
4. Append per the conventions append rule. This is a NEW corrective line;
   never edit prior lines.

## Output

Print the exact line you wrote back to the user (in your reply text -- do not
`echo` it via Bash). If `--dry-run` is in `$ARGUMENTS`, print the proposed
record but do NOT write the file.
