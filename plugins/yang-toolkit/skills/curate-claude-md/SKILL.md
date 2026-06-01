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

Goal: audit every CLAUDE.md in the current repo, classify each rule as
technical (belongs at the root) or business (belongs in the nearest meaningful
sub-directory), detect drift against the actual code, and present a unified
diff for the user to confirm. **Write nothing until the user says yes.**

Execute these steps in order:

**Step 1 -- Discover every CLAUDE.md.**
- List candidates without descending into noise dirs. Prefer:
  `git ls-files '**/CLAUDE.md' 'CLAUDE.md'` when inside a git repo (respects
  `.gitignore`). If that returns nothing or git is unavailable, fall back to:
  `find . -name CLAUDE.md -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/dist/*' -not -path '*/build/*'`.
- Read each discovered file with the Read tool. Note its directory (root vs
  which sub-tree) -- that is its current "layer".
- **Never read or touch `~/.claude/CLAUDE.md`.** If a path resolves to the
  user's home `~/.claude/CLAUDE.md`, skip it silently.
- If the discovery finds NO CLAUDE.md anywhere, jump to Step 5 (scaffold).

**Step 2 -- Classify each line / bullet.**
For every meaningful line (skip blank lines, headings, and pure prose), tag it
**technical** or **business** using these signals:
- *Technical (belongs at root)* -- mentions a formatter (prettier, black,
  gofmt, rustfmt), a test runner (jest, pytest, vitest, go test), a linter
  (eslint, ruff, flake8, clippy), build/package tooling (npm, yarn, pnpm,
  poetry, cargo, make), branch / PR / commit conventions, CI, or a
  language/runtime version pin (e.g. "Node 20", "Python 3.11", "Go 1.22").
- *Business (belongs in a sub-directory)* -- names a domain object or entity,
  a money/unit convention (cents vs dollars, currency, rounding), a status
  enum or state machine, a permission / authorization boundary, an
  invariant tied to one module, or a module-specific gotcha.
- If a line matches neither list, leave it where it is and do not propose a
  move (low confidence; only move what the signals justify).

**Step 3 -- Propose moves.**
- A **business** line currently in the root (or an ancestor) -> move it DOWN to
  the nearest sub-directory that actually owns that concept. Infer the target
  by matching the domain term to a directory name, an import path seen in
  `recent-activity`, or where files of that concern live (e.g. a rule about
  "Order totals" -> `src/orders/CLAUDE.md`). If no clear owner exists, leave it
  and note "no obvious owner directory" rather than guessing.
- A **technical** line currently in a sub-directory CLAUDE.md -> move it UP to
  the root CLAUDE.md.
- Apply the DRY rule from the layered-discipline section above: if a moved
  business rule restates something the ancestor already says, replace the
  duplicate body with a one-line reference (and optionally `@../CLAUDE.md`)
  instead of copying.

**Step 4 -- Detect drift against the actual code.**
Cross-check each technical claim against repo reality and flag mismatches:
- Package manager: if a CLAUDE.md says "use yarn" but only `package-lock.json`
  exists -> flag (similarly pnpm vs `pnpm-lock.yaml`, npm vs `yarn.lock`).
- Language/runtime version: compare a pinned version against `.nvmrc`,
  `engines` in `package.json`, `pyproject.toml` / `.python-version`,
  `go.mod`, `rust-toolchain*` -- flag contradictions.
- Tooling presence: if it names a tool (e.g. "run `make test`") that has no
  corresponding config/target/dependency in the repo -> flag as stale.
- Report each drift item as a one-line warning alongside the move it relates
  to; the user decides whether to fix the doc or the code.

**Step 5 -- Emit the result. Write nothing yet.**
- If at least one CLAUDE.md exists: present a single **unified diff** (one
  hunk per file touched, using standard `--- a/path` / `+++ b/path` /
  `@@` format) covering every proposed move and DRY rewrite, followed by a
  short **per-move rationale** list (one line each: what moved, from -> to,
  why, plus any drift flag). Then ask the user to confirm before any write.
- If NO CLAUDE.md exists at all: do not audit. Instead propose a minimal
  root-`CLAUDE.md` scaffold (as a fenced block) containing just the technical
  essentials you can verify from the repo -- detected package manager, test
  command, lint/format command, language version, branch/PR convention if
  discoverable -- and nothing speculative. Present it and ask to confirm.
- Only after explicit user confirmation do you apply the diff / write the
  scaffold. Never mutate `~/.claude/CLAUDE.md` in either case.

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
