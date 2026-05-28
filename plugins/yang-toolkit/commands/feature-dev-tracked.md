---
description: Wrap /feature-dev with per-phase persistence. Each phase emits a decision doc; the final phase appends a ledger record.
---

# /yang-toolkit:feature-dev-tracked

You are running the `feature-dev-tracked` workflow on behalf of the user. This is
a thin wrapper around the upstream `/feature-dev` flow that adds two persistence
guarantees:

1. **Per-phase decision docs** under
   `${CLAUDE_PROJECT_DIR}/docs/decisions/{YYYY-MM-DD}-{slug}/0X-{phase}.md`
2. **One ledger record** appended to
   `${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl` at the end (controlled-vocabulary
   schema -- see below).

## Inputs
- `$ARGUMENTS` -- a feature description in natural language. If empty, ask the
  user for it before doing anything else.

## Procedure

### Step 1 -- prepare
- Derive a kebab-case `slug` from the feature description.
- Compute `today = YYYY-MM-DD` (UTC).
- Create directory `${CLAUDE_PROJECT_DIR}/docs/decisions/{today}-{slug}/` (use
  the `Write` tool on a placeholder if Bash mkdir isn't available; do not skip).
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
- Write `0X-{phase}.md` into the decision directory (X = phase index, zero-padded).
- The file MUST contain: title, ISO8601 timestamp, the phase's deliverable, and
  any open questions surfaced.
- Use the `Write` tool. Do not silently skip a phase.

### Step 3 -- ledger append (only on `summary` phase)
At the end of `summary`, append exactly ONE line to
`${CLAUDE_PROJECT_DIR}/.claude/ledger.jsonl` matching this schema:

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

Append using `Write` in append mode (or `echo >>` via Bash). Each entry must
be a single line of compact JSON, terminated by `\n`.

### Step 4 -- report and clean up
- Clear the current-feature pointer: delete (or truncate to empty)
  `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt`. This signals that
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
