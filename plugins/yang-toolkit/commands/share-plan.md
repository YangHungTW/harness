---
description: Render a plan.md (or any plan-shaped markdown) into a clean, self-contained, shareable HTML document for a non-terminal colleague to read. Read-only snapshot; does NOT modify the plan. Pairs with /yang-toolkit:plan-feature.
---

# /yang-toolkit:share-plan

A `plan.md` is perfect for you in a terminal and useless to hand to someone who
lives in Slack and a browser. This command renders a plan into a **clean,
self-contained HTML document** you can send: it opens like a normal doc, shows
the frontmatter as a header, and renders acceptance criteria as checkboxes.

It is a **point-in-time export**, not a live view. The `plan.md` stays the source
of truth; the HTML is a timestamped snapshot. (Inline comments / reviewer
round-trip are out of scope -- that needs a hosted service; this is for reading.)

## Conventions

Resolve `<HARNESS_ROOT>` per
`${CLAUDE_PLUGIN_ROOT}/references/conventions.md`. Plans live at
`<HARNESS_ROOT>/.claude/plans/`.

## Inputs
- `$ARGUMENTS` -- one of:
  - a plan **slug** -> render `<HARNESS_ROOT>/.claude/plans/<slug>.md`
  - a **path** to any markdown file -> render that file (e.g. a decision doc)
- If empty: list `<HARNESS_ROOT>/.claude/plans/*.md` and ask which to share.

## Timestamp
Compute once, just before writing (same convention as the dashboard):
- `{TS}` = `date -u +%Y%m%dT%H%M%SZ` (compact UTC, filesystem-safe, sortable).
- content timestamp = `date -u +%Y-%m-%dT%H:%M:%SZ` (full ISO 8601 UTC).

## Procedure
1. **Resolve + read** the source markdown. If the slug/path does not exist, abort
   with "no such plan; check `ls .claude/plans/`". Do NOT create anything.
2. **Read the template** at `${CLAUDE_PLUGIN_ROOT}/templates/plan.html`.
3. **Substitute three things**, leaving all other markup byte-for-byte unchanged
   (the page renders the markdown client-side, so you do NOT convert it yourself):
   - REPLACE the contents of the `<script type="text/markdown" id="plan-md">
     ... </script>` block with the **raw** source markdown, frontmatter and all.
     Do not escape it, do not convert it -- paste it verbatim. (If the markdown
     itself contains the literal `</script>`, which a normal plan never does,
     split it as `</scr` + `ipt>` so it cannot close the block early.)
   - REPLACE `__GENERATED_AT__` with the content timestamp.
   - REPLACE `__SOURCE__` with the source path (e.g. `.claude/plans/<slug>.md`).
4. **Write** the result to `<HARNESS_ROOT>/.claude/plans/<slug>-{TS}.html` (a new
   timestamped snapshot; never overwrite the `.md`, never overwrite older
   snapshots). For a non-slug path input, derive the output basename from the
   source filename.
5. **Report**: print the output path and offer to open it -- on macOS
   `open "<HARNESS_ROOT>/.claude/plans/<slug>-{TS}.html"`. Mention it is a
   self-contained file safe to send/airdrop (no server needed).

## Notes
- The template ships with a mock plan so it previews standalone; always REPLACE
  the `plan-md` block payload, never append.
- The embedded renderer covers the plan markdown subset (headings, task lists with
  nested Check/Pass bullets, code, blockquotes, links, frontmatter -> header). It
  intentionally strips internal `<!--auto-->` / comment markers from the output.
- This command is read-only on the plan. Revisions go through
  `/yang-toolkit:plan-feature --revise <slug>`, then re-run `/share-plan` to
  produce a fresh snapshot.

## Failure modes
- Template missing/unreadable: abort with the path that failed.
- `.claude/plans/` cannot be written: abort with the path; do NOT fall back to
  `/tmp`.
