---
name: curate-claude-md
description: Audit and (re)generate nested CLAUDE.md files across the current repo. Upper-level CLAUDE.md holds technical rules; sub-directory CLAUDE.md files hold business logic and domain invariants. Also serves as the FALLBACK generator for /yang-toolkit:claude-md-gaps when the official claude-md-management plugin is not installed. TRIGGER on /curate-claude-md, or when the user asks to "review CLAUDE.md", "rewrite CLAUDE.md", or "split CLAUDE.md".
---

# curate-claude-md

## Architectural rule (the layered discipline this skill enforces)
- **Upper-level** (`<repo>/CLAUDE.md`, or any ancestor loaded at session start):
  technical rules -- formatter, test runner, language version, dependency
  policy, branch / PR conventions.
- **Sub-directory** (`<repo>/<area>/CLAUDE.md`, lazy-loaded when Claude reads
  files in that area): business logic, domain invariants, module-specific
  gotchas. Move anything that names a business concept down.
- **DRY across layers**: a nested CLAUDE.md must NOT restate ancestor content.
  Reference with one sentence and optionally an `@../CLAUDE.md` import, never
  copy. The official memory loader concatenates root-to-cwd, so duplication
  just wastes context tokens.

## Two operating modes

### Mode A -- standalone curate (the original purpose)
Triggered by `/curate-claude-md` or the natural-language phrases above.

1. Walk the repo, find every existing CLAUDE.md (root + nested).
2. Classify each line: technical-rule vs business-rule.
3. Propose moves: business rules drift down to the nearest meaningful
   sub-directory; technical rules drift up to the root.
4. Detect drift against code: if CLAUDE.md says "use yarn" but the lockfile is
   `package-lock.json`, flag it.
5. Emit a unified diff with per-move rationale. **Do not write anything until
   the user confirms.**

<!-- TODO: implement the audit walk + classifier + diff renderer.
     Suggested classifier signal: words like "formatter", "test", "lint",
     "branch", "PR", language/runtime names -> technical (upper). Words that
     name domain objects, money units, status enums, permission boundaries
     -> business (nested). -->

### Mode B -- fallback generator for /yang-toolkit:claude-md-gaps
Triggered when `/yang-toolkit:claude-md-gaps` delegates here because the
official `claude-md-management` plugin (specifically `/revise-claude-md`)
is not installed.

The caller passes a four-field bundle (see `commands/claude-md-gaps.md`
Step 2): `target_dir`, `ancestor_summary`, `recent_activity`, `domain_hints`.

When invoked in this mode:

1. Treat the bundle as the **only** input. Do not re-scan the repo.
2. Produce a single CLAUDE.md draft for `target_dir`, under ~120 lines,
   focused exclusively on business logic and domain invariants observable
   from `recent_activity` and `domain_hints`.
3. **Explicitly avoid** any sentence that overlaps `ancestor_summary`. If
   a rule appears in both ancestor and this folder's natural scope,
   reference the ancestor (`@../CLAUDE.md`) instead of restating.
4. Return the draft as a fenced markdown block. **Do not write the file.**
   Writing is the orchestrator's (`/claude-md-gaps`) responsibility, gated
   on user confirmation.
5. If the bundle is too thin to write anything meaningful, return an empty
   draft with a one-line note ("insufficient signal -- recommend editing a
   few more files in this folder, then retry"). The orchestrator will
   surface this to the user as-is.

## Inputs (per mode)

| Mode | Inputs |
| ---- | ------ |
| A (standalone) | Repo root cwd, every existing CLAUDE.md, optional `~/.claude/CLAUDE.md` (read-only). |
| B (fallback)   | The four-field bundle from `/claude-md-gaps`. Nothing else. |

## Output (per mode)

| Mode | Output |
| ---- | ------ |
| A | A unified diff + rationale, presented to chat. No file writes until user confirms. |
| B | One fenced markdown block (the draft). Caller writes it after user gates. |

## Notes
- Never mutate `~/.claude/CLAUDE.md`.
- If the repo has no CLAUDE.md at all in Mode A, propose a minimal root
  scaffold instead of auditing.
- Mode B never reads files outside the bundle -- this is to keep the
  fallback path deterministic and quick. If you find yourself wanting more
  context, that's a sign Mode A (a full curate pass) is the right tool.
