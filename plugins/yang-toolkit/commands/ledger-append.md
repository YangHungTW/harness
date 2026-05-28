---
description: Manually append one record to .claude/ledger.jsonl. For backfilling a missed session or correcting an automatic Stop-hook entry.
---

# /yang-toolkit:ledger-append

You are appending exactly ONE record to
`${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl`.

## Required fields -- ask the user before writing
Walk the user through these. If a value is given in `$ARGUMENTS` already, use it
without re-asking; otherwise ask:

1. `feature` -- short kebab-case slug
2. `phase` -- one of `discovery | architecture | implementation | review | summary`
3. `outcome` -- one of `in-progress | merged | abandoned | failed`
4. `agent` -- which agent / persona did the work (e.g. `rails-dev`,
   `solidity-dev`, `client-manager`, `devops`, or `unknown`)
5. `pr` -- PR URL, or "none" -> null
6. `commit` -- short SHA, or "none" -> null

**Do not invent any of these.** If the user gives an outcome outside the
controlled list, push back: list the allowed values and ask again.

## Optional fields -- best-effort, default if not provided
- `files` -> 0 if unknown
- `tokens` -> 0 if unknown
- `tools` -> `{}` if unknown

## Behavior
1. Build the record as a single compact JSON object, schema:
   ```
   {
     "ts": "<UTC ISO8601 of NOW>",
     "feature": "...",
     "phase": "...",
     "agent": "...",
     "outcome": "...",
     "files": 0,
     "tokens": 0,
     "tools": {},
     "pr": null,
     "commit": null
   }
   ```
2. Append to `${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl` (create the file +
   directory if missing). One line, terminated by `\n`.
3. Echo the exact line you wrote back to the user.

## Confirm
If the user types `--dry-run` in `$ARGUMENTS`, print the proposed record but
do NOT write the file.
