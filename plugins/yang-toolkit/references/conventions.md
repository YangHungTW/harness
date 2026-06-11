# yang-toolkit conventions

Canonical definitions shared by every yang-toolkit command. Commands reference
this file instead of repeating these blocks. (Hook shell scripts intentionally
inline equivalent logic for portability -- keep them in sync when editing here.)

## Harness root (worktree-aware)

Durable state (plans, ledger, claude-md candidates queue) must live in the
MAIN git worktree so it survives deletion of any linked worktree and is shared
across worktrees. Resolve it once at the start:

```
git -C "${CLAUDE_PROJECT_DIR}" worktree list --porcelain | awk '/^worktree /{print $2; exit}'
```

Call the result `<HARNESS_ROOT>`. If that command yields nothing or this is
not a git repo, fall back to `${CLAUDE_PROJECT_DIR}`. In the main worktree the
two are identical, so non-worktree users see no change.

**Durable** (always `<HARNESS_ROOT>`): `.claude/plans/` (incl. `.fuzzy-words`),
`.claude/ledger.jsonl`, `.claude/state/claude-md-candidates.jsonl`.

**Ephemeral / branch-local** (always `${CLAUDE_PROJECT_DIR}`):
`docs/decisions/`, `.claude/logs/`, `.claude/state/current-feature.txt`.

## Ledger schema

One compact JSON object per line in `<HARNESS_ROOT>/.claude/ledger.jsonl`:

```
{
  "ts":      "<ISO8601 UTC>",
  "feature": "<kebab-case slug>",
  "phase":   "discovery" | "architecture" | "implementation" | "review" | "summary",
  "agent":   "<agent that did the bulk of the work, or 'main' / 'unknown'>",
  "outcome": "in-progress" | "merged" | "abandoned" | "failed",
  "files":   <int, 0 if unknown>,
  "tokens":  <int approx, 0 if unknown>,
  "tools":   { "<tool>": <count>, ... },
  "pr":      "<URL or null>",
  "commit":  "<short SHA or null>"
}
```

Per-command extensions (optional fields; dashboard treats absence as default):

| Field | Written by | Meaning |
| ----- | ---------- | ------- |
| `cycles` | tdd-feature | completed red-green-refactor cycles |
| `plan_path`, `goal_turns`, `orchestration`, `workers`, `criteria_pass`, `criteria_fail`, `deps_ignored` | execute-plan | plan-run metadata (see that command) |
| `source: "stop-hook"` | Stop hook | auto-appended supplementary entry |

**Outcome rules**: default `in-progress`. `merged` only on confirmed PR merge
(user confirmation in-session, or `gh` evidence via `/ledger-append --close`).
`abandoned` when the user explicitly stopped mid-flow. `failed` on
unrecoverable error. Sole sanctioned extension: `claude-md-created`
(claude-md-gaps only). Never invent any other value -- new outcomes require
updating `skills/dashboard/SKILL.md` + `dashboard.html` FIRST.

## Ledger / state-file append rule

Append **via Read+Write, never shell redirection**: Read the current file
(treat missing as empty), concatenate your one-line compact JSON plus a
trailing `\n`, and Write the whole file back with the **Write** tool (it
creates parent directories). Do NOT use `echo >>`, `>`, `tee`, `printf >`, or
`cd <dir> && …` -- each distinct shell string re-triggers a permission prompt;
the Write tool does not. The same rule applies to clearing
`current-feature.txt` (Write an empty string; never `rm` / `truncate` / `> file`).

## Slug derivation

Kebab-case the feature description: lowercase, strip punctuation, join the
3-6 most distinctive words with `-`. Deterministic -- the same description
must yield the same slug across plan-feature / feature-dev-tracked /
tdd-feature so plans, decision dirs, and state pointers line up.

## Timestamps

Both UTC; compute fresh with `date` when needed, never reuse a stale value:
- filename `{TS}` (compact, fs-safe, sortable): `date -u +%Y%m%dT%H%M%SZ`
- content timestamp (full ISO 8601): `date -u +%Y-%m-%dT%H:%M:%SZ`
