---
description: Manually append one record to .claude/ledger.jsonl. For backfilling a missed session or correcting an automatic Stop-hook entry.
---

# /yang-toolkit:ledger-append

You are appending exactly ONE record to
`<HARNESS_ROOT>/.claude/ledger.jsonl`.

## Harness root (worktree-aware)

The ledger is durable state and must live in the MAIN git worktree so it
survives worktree deletion and is shared across worktrees. Resolve it once:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command is empty or this is not a git
repo, fall back to `<HARNESS_ROOT>` = `${CLAUDE_PROJECT_DIR}`. In the main
worktree these are identical, so non-worktree users see no change. Use
`<HARNESS_ROOT>` for the ledger path below.

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
2. Append the record **via Read+Write, never shell redirection**: Read the
   current `<HARNESS_ROOT>/.claude/ledger.jsonl` (treat a missing file as
   empty), concatenate your one-line compact JSON plus a trailing `\n` onto the
   existing contents, and Write the whole file back with the **Write** tool (it
   creates the parent directory). Do NOT use `echo >>`, `>`, `tee`, or
   `cd <dir> && …` -- each distinct shell string re-triggers a permission
   prompt; the Write tool does not.
3. Print the exact line you wrote back to the user (in your reply text -- do not
   `echo` it via Bash).

## Confirm
If the user types `--dry-run` in `$ARGUMENTS`, print the proposed record but
do NOT write the file.
