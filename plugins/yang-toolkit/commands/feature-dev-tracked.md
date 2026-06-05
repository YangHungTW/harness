---
description: Wrap /feature-dev with per-phase persistence. Each phase emits a decision doc; the final phase appends a ledger record.
---

# /yang-toolkit:feature-dev-tracked

You are running the `feature-dev-tracked` workflow on behalf of the user. This is
a thin wrapper around the upstream `/feature-dev` flow that adds two persistence
guarantees:

1. **Per-phase decision docs** under
   `${CLAUDE_PROJECT_DIR}/docs/decisions/{YYYY-MM-DD}-{slug}/0X-{phase}-{TS}.md`
   where `{TS}` is a compact UTC timestamp (see "Timestamps" below).
2. **One ledger record** appended to
   `<HARNESS_ROOT>/.claude/ledger.jsonl` at the end (controlled-vocabulary
   schema -- see below).

## Harness root (worktree-aware)

Durable state (the ledger) must live in the MAIN git worktree so it survives
worktree deletion and is shared across worktrees. Resolve it once:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command is empty or this is not a git
repo, fall back to `<HARNESS_ROOT>` = `${CLAUDE_PROJECT_DIR}`. In the main
worktree these are identical, so non-worktree users see no change.

Use `<HARNESS_ROOT>` ONLY for `<HARNESS_ROOT>/.claude/ledger.jsonl`. Keep
everything else -- `docs/decisions/...` and
`.claude/state/current-feature.txt` -- on `${CLAUDE_PROJECT_DIR}` (decision
docs belong with the feature branch).

## Timestamps
Two granularities, both UTC. Compute each with a single `date` call when you need
it (do NOT hardcode or reuse a stale value across phases):
- **Filename timestamp `{TS}`** -- compact basic-ISO, filesystem-safe (no colons),
  lexically sortable: `date -u +%Y%m%dT%H%M%SZ` -> e.g. `20260605T031421Z`.
- **Content timestamp** -- full ISO 8601 UTC for inside the doc body:
  `date -u +%Y-%m-%dT%H:%M:%SZ` -> e.g. `2026-06-05T03:14:21Z`.

## Inputs
- `$ARGUMENTS` -- a feature description in natural language. If empty, ask the
  user for it before doing anything else.

## Procedure

### Step 1 -- prepare
- Derive a kebab-case `slug` from the feature description.
- Compute `today = YYYY-MM-DD` (UTC).
- The decision directory `${CLAUDE_PROJECT_DIR}/docs/decisions/{today}-{slug}/`
  is created implicitly when you Write the first `0X-{phase}.md` into it -- the
  **Write** tool creates parent directories. Do NOT run `mkdir` or `cd` to make
  it; those shell calls trigger permission prompts. Just Write the file.
- **Set the current-feature pointer**: write the bare slug (no date prefix,
  no newline beyond a trailing `\n`) to
  `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`. This lets
  `/yang-toolkit:tdd-feature` pick up where this command left off if the user
  decides mid-flow to switch into TDD discipline. Create the parent directory
  if missing. If you cannot write the file (read-only fs, etc.), surface a
  warning but continue -- it's a convenience, not a correctness requirement.

### Step 2 -- run phases
Run the standard feature-dev phases in order:

  1. discovery
  2. architecture
  3. implementation
  4. review
  5. summary  (always last)

After each phase, **before** moving to the next:
- Compute a fresh `{TS}` (`date -u +%Y%m%dT%H%M%SZ`) and a content timestamp
  (`date -u +%Y-%m-%dT%H:%M:%SZ`) at the moment the phase completes.
- Write `0X-{phase}-{TS}.md` into the decision directory (X = phase index,
  zero-padded; `{TS}` = the compact filename timestamp). The zero-padded index
  keeps phases ordered; the timestamp records when each was written.
- The file MUST contain, as the first lines of the body: a `# <title>` heading
  and a `Generated: <content timestamp>` line, followed by the phase's
  deliverable and any open questions surfaced.
- Use the `Write` tool. Do not silently skip a phase.

### Step 3 -- ledger append (only on `summary` phase)
At the end of `summary`, append exactly ONE line to
`<HARNESS_ROOT>/.claude/ledger.jsonl` matching this schema:

```
{
  "ts":      ISO8601 string,
  "feature": "<slug>",
  "phase":   "summary",
  "agent":   "<the agent that did the bulk of the work, or 'unknown'>",
  "outcome": "in-progress" | "merged" | "abandoned" | "failed",
  "files":   <number of distinct files touched>,
  "tokens":  <approx total tokens, 0 if unknown>,
  "tools":   { "<tool_name>": <count>, ... },
  "pr":      "<URL or null>",
  "commit":  "<short SHA or null>"
}
```

**Rules for `outcome`**:
- Default to `in-progress`.
- Set to `merged` only if the user confirms a PR has merged in this session.
- Set to `abandoned` if the user explicitly stopped the feature mid-flow.
- Set to `failed` if a phase produced an unrecoverable error and you did not
  recover.
- Never invent any other value.

**Append via Read+Write, never shell redirection.** Read the current
`ledger.jsonl` (treat a missing file as empty), concatenate your one-line
compact JSON record plus a trailing `\n` onto the existing contents, and Write
the whole file back with the **Write** tool (it creates parent directories).
Do NOT use `echo >>`, `>`, `tee`, `printf >`, or `cd <dir> && …` -- each
distinct shell string re-triggers a permission prompt; the Write tool does not.

### Step 4 -- report and clean up
- Clear the current-feature pointer: Write an empty string to
  `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` with the **Write**
  tool (do NOT `rm`, `truncate`, or `> file`). This signals that
  the feature has reached `summary` and tdd-feature should NOT try to continue
  it -- starting TDD on a summarized feature requires a new slug.
- Tell the user:
  - The decision directory you created.
  - That one ledger record was appended.
  - If anything was skipped or degraded, say so explicitly.

## Failure modes
- If `${CLAUDE_PROJECT_DIR}/docs/decisions/` cannot be created, abort with a
  clear message -- do not silently write to `/tmp`.
- If the ledger file is locked or unwritable, still finish the phases but
  surface the failure at the end.
