---
description: Review pending nested-folder CLAUDE.md candidates, delegate generation to the official claude-md-management plugin, gate on user confirmation, then write the file and ledger the result.
---

# /yang-toolkit:claude-md-gaps

You are running the **nested-CLAUDE.md gap-resolution flow**. Your job is to
review folders that the passive PostToolUse hook flagged as "probably needs a
CLAUDE.md", delegate the actual content generation to the official
`claude-md-management` plugin, and write the file ONLY after the user explicitly
confirms.

## Harness root (worktree-aware)

Durable harness state (the candidates queue and the ledger) lives in the **MAIN**
git worktree so it is shared across worktrees and survives worktree deletion.
Resolve it once:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command yields nothing (no git, or not
a repo), fall back to `<HARNESS_ROOT>` = `${CLAUDE_PROJECT_DIR}`. In the main
worktree the two are identical, so non-worktree users see no change.

Use `<HARNESS_ROOT>` for durable state:
- `<HARNESS_ROOT>/.claude/state/claude-md-candidates.jsonl`
- `<HARNESS_ROOT>/.claude/ledger.jsonl`

Keep `${CLAUDE_PROJECT_DIR}` for ephemeral, per-worktree state: the
`.claude/logs/session-*.jsonl` recent-activity read, the written CLAUDE.md
target, and any `docs/decisions/` reference.

## Hard rules (read before doing anything)

1. **You never write CLAUDE.md content yourself.** Generation belongs to the
   official plugin's `/revise-claude-md` (preferred) or to this repo's
   `/yang-toolkit:curate-claude-md` skill as a fallback.
2. **You never write to the user's repo until the user says OK to a specific
   draft.** Always: show draft -> wait for confirmation -> then write.
3. **Scope is nested folders only.** Refuse if the target is the repo root or a
   path outside the project. Root CLAUDE.md is explicitly out of scope.
4. **Honor the layered-discipline rule** when prompting the generator:
   - The nested CLAUDE.md should focus on **business logic, domain invariants,
     and folder-local conventions** -- not on technical rules (formatter,
     linter, language version) that belong in the root CLAUDE.md.
   - **Do not repeat ancestor CLAUDE.md content.** Reference it with one
     sentence and an `@../CLAUDE.md` import if needed -- never duplicate.
5. **Target length**: keep generated drafts under ~120 lines (well below the
   200-line soft limit).

## Argument forms

- No arguments -> review-mode: list pending candidates from
  `<HARNESS_ROOT>/.claude/state/claude-md-candidates.jsonl`, ranked by
  score descending. Ask the user which one(s) to act on.
- `--dir <path>` -> direct-mode: skip the candidate list and run the
  generate-review-write flow for the given folder. Verify it is a real
  subdirectory of `${CLAUDE_PROJECT_DIR}` and that no `CLAUDE.md` already exists
  there (if one does, switch to "audit-existing" suggestion -- do not overwrite).

## Procedure

### Step 1 -- gather

1. Determine `${CLAUDE_PROJECT_DIR}` (the user's repo). If unset, infer from
   cwd and tell the user what you inferred.
2. **Review mode** (no `--dir` arg):
   - Read `<HARNESS_ROOT>/.claude/state/claude-md-candidates.jsonl`.
   - If the file is missing or empty, say: "No candidates recorded yet -- the
     passive hook only fires on Edit/Write/MultiEdit. Either edit a few files
     in a nested folder, or run with `--dir <path>` to nominate one directly."
     and STOP.
   - Filter to `status == "pending"` entries.
   - Sort by `score` descending, then `ts` descending (newest first as
     tie-breaker).
   - Render a markdown table with columns: `#`, `dir`, `score`, `signals`,
     `last seen`. Use the relative `dir` exactly as recorded. Truncate
     signals list to ~3 visible.
   - Ask the user: which row number(s) to act on, or `skip` / `dismiss <#>`
     (sets status to "dismissed", does NOT generate). Wait for input.
3. **Direct mode** (`--dir <path>`):
   - Normalize the path against `${CLAUDE_PROJECT_DIR}`. Reject absolute paths
     pointing outside the repo. Reject the repo root itself.
   - If the folder doesn't exist or has no source files, refuse politely.
   - If a CLAUDE.md already exists there, suggest running the
     `claude-md-improver` skill (audit) instead of `/claude-md-gaps`, and STOP.

### Step 2 -- assemble the delegation context

For each user-selected folder, build a context bundle the generator can use:

- `target_dir` -- relative path inside the repo
- `ancestor_summary` -- a 5-15 line digest of every CLAUDE.md from repo root
  down to the parent of `target_dir`, so the generator knows what NOT to
  repeat. Read those CLAUDE.md files yourself; do not invent.
- `recent_activity` -- a short summary of what's been edited in the folder
  recently. Source this from `${CLAUDE_PROJECT_DIR}/.claude/logs/session-*.jsonl`
  (last 7 days) and `<HARNESS_ROOT>/.claude/ledger.jsonl` if present. Plain
  prose, 5-10 bullets.
- `domain_hints` -- file listing of the folder (one-pass, depth 1), grouped
  by extension. This is signal for what kind of code lives there.

Render this bundle to the user as a collapsed preview before delegating, so
they can correct mis-attributions.

### Step 3 -- delegate to the official plugin

Check if `claude-md-management` is installed:

- If yes, invoke its command:
  ```
  /revise-claude-md
  ```
  with a prompt envelope that includes the four-field bundle from Step 2 plus
  these explicit instructions to the official command:
  - "Produce a draft CLAUDE.md focused on `${target_dir}`."
  - "Stay under ~120 lines."
  - "Do NOT restate technical rules already present in the ancestor summary."
  - "Focus on: business invariants, state-machine rules, units / numeric
    boundaries, naming conventions specific to this folder, edge cases
    surfaced in the recent activity."
  - "Return the draft as a fenced markdown block. Do not write any file."

- If the official plugin is not available, fall back to:
  ```
  /yang-toolkit:curate-claude-md
  ```
  with the same envelope, and remind the user this is the fallback path
  (see `skills/curate-claude-md/SKILL.md` for the agreement that this skill
  honors the same layered-discipline rule).

- If neither is available (very unusual), stop and instruct the user how to
  install: `/plugin install claude-md-management` (the
  `claude-plugins-official` marketplace is auto-loaded so no
  `marketplace add` is required).

### Step 4 -- review with the user

1. Render the returned draft inline. Don't write yet.
2. Surface anything suspicious:
   - lines that overlap an ancestor CLAUDE.md (quote both, side by side)
   - any sentence that reads as a technical rule (formatter, linter, build
     command) -- those belong in the root CLAUDE.md, not here
3. Ask the user one of: `accept` / `accept after edits: <notes>` / `reject`.
4. If `accept after edits`, apply the user's edits to the draft and re-show.
5. Repeat until `accept` or `reject`.

### Step 5 -- write (only on accept)

On `accept`:

1. Use the `Write` tool to write the draft to
   `${CLAUDE_PROJECT_DIR}/${target_dir}/CLAUDE.md`.
2. Update the candidate record's `status` from `"pending"` to `"created"` in
   `<HARNESS_ROOT>/.claude/state/claude-md-candidates.jsonl`. Preserve all other
   fields: Read the file, change the one line in memory, and Write the whole
   file back with the **Write** tool. Do not use `sed` / `echo >` redirection.
3. Append a record to `<HARNESS_ROOT>/.claude/ledger.jsonl` **via Read+Write,
   never shell redirection**: Read the current file (treat missing as empty),
   concatenate your one-line compact JSON plus a trailing `\n`, and Write the
   whole file back with the **Write** tool. Do NOT use `echo >>`, `>`, `tee`, or
   `cd <dir> && …`. Use the harness ledger schema, this exact shape:
   ```
   {
     "ts":      <ISO8601 now, UTC>,
     "feature": "claude-md-gap:<target_dir>",
     "phase":   "summary",
     "agent":   "<whichever generator actually ran -- 'claude-md-management', 'curate-claude-md', or 'main' if Claude main thread did it inline>",
     "outcome": "claude-md-created",
     "files":   1,
     "tokens":  0,
     "tools":   { "Write": 1 },
     "pr":      null,
     "commit":  null
   }
   ```
   Note: `outcome` uses the controlled-vocabulary extension
   `"claude-md-created"`. If you ever introduce a different outcome here, update
   the ledger schema documentation in `skills/dashboard/SKILL.md` and
   `dashboard.html` FIRST -- this is the project's hard rule on outcomes.
4. Confirm to the user: target file path, candidate status update, ledger
   line written. Done.

On `reject`:

1. Update the candidate record's status to `"dismissed"`.
2. Append nothing to the ledger.
3. Tell the user.

## Failure modes

- The candidates file is unreadable: tell the user, ask whether to
  `--dir`-target manually.
- The official plugin returns a draft that's empty or a single sentence:
  do not auto-write. Surface the empty draft and let the user decide.
- The user goes silent mid-review: do not assume consent. Stop without writing.

## Quick reference

| Step                              | Who runs it                              | Side effect                                                                  |
| --------------------------------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| Record candidate                  | PostToolUse hook                         | Append/dedupe `.claude/state/claude-md-candidates.jsonl`                     |
| Review list                       | This command (review mode)               | Read-only                                                                    |
| Build delegation bundle           | This command                             | Read-only (reads ancestor CLAUDE.mds, logs, ledger)                          |
| Generate draft                    | `/revise-claude-md` or fallback skill    | None -- draft only returns to chat                                           |
| Approve draft                     | User                                     | Required gate before any write                                               |
| Write CLAUDE.md                   | This command                             | One `Write` call                                                             |
| Update candidate status + ledger  | This command                             | Two appends                                                                  |
