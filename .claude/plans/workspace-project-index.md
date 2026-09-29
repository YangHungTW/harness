---
slug: workspace-project-index
created_at: 2026-09-29T00:00:00Z
discipline: normal
orchestration: auto
team_size: 3
time_budget: 25 turns
depends_on: []
delegate_to: {}
status: awaiting-input
started_at: 2026-09-29T01:53:20Z
executor: main
waiting:
  since: 2026-09-29T02:18:49Z
  run: 1
  kind: human-anchor
  question: In a session launched in ~/Projects with this branch's plugin loaded, run /yang-toolkit:go for requests (a) (b) (c) from the "real-workspace init and routing" criterion (see its Revision 1) — do the results pass?
  artifact: ~/Projects/.claude/workspace.json, the managed block in ~/Projects/CLAUDE.md, and the three go routing declarations
---

> Revision 1: user direction (2026-09-29) — registration is automatic: `go` runs `workspace-init` on first use and whenever projects are added or removed, the agent names aliases itself, nothing is asked; the user sees a folder list and corrects in plain words.

# Goal
When Claude is launched in a workspace directory (e.g. `~/Projects`: not a git repo, but containing many projects), `/yang-toolkit:go` resolves a plain-language request to the right project(s) against a **user-confirmed `workspace.json`**. It confirms each candidate against that project's own instruction files, read in place, and asks at most one question when the match is ambiguous.

# Context
This is step 1 of porting straw-boss's model (https://github.com/wayne930242/straw-boss) into yang-toolkit. The user chose "port the concepts into yang-toolkit, then optimize the flow and prompts" over installing straw-boss: Herdr isn't installed, and straw-boss assumes the root is a git repo, which `~/Projects` isn't.

Roadmap:

| Step | Scope |
|---|---|
| **1 (this plan)** | workspace registry + resolving |
| 2 | app-rooted workers in tmux panes, rooted in each project so they load its own `.claude/skills`, hooks, and settings; status/checkpoint files; facts-only peer Q&A |
| 3 | `choosing-graph`-style graph pick (single-loop / fan-out / orchestrator-worker); orchestrator plan; Alert/Warn/Info report; gated merge |

Why this replaces the earlier "capability card" draft: straw-boss's core argument is that a condensed summary of a project drifts from the project's real rules and duplicates files that are already authoritative. Separate research found the same (LLM-written repo overviews lowered task success). So:
- The registry holds only **routing facts the user confirmed**: name, dir, match phrases, a few policy fields.
- Everything else is read **live** from the project's own CLAUDE.md, AGENTS.md, or README at resolve time.
- No model-written summaries are persisted. This also removes most of the prompt-injection surface.

Declared decision (override in one sentence): step 1 ends at a **routing declaration**. That is target(s) plus reasons plus the exact next command: for one target, `cd "<dir>" && claude "/yang-toolkit:go <request>"`; for several, a note that orchestration arrives in step 3.

**Flow and prompt optimizations over straw-boss** (the user's "優化流程跟 prompt"):
- **Fewer surfaces.** Straw-boss's 17 skills collapse to one new user skill (`workspace-init`) and one shared reference (`references/workspace.md`) that `go` reads. No separate `resolving-app` skill for the model to route to.
- **Proposals come from the machine, the user only confirms.** `init` proposes every field from structure (dir name, manifest name, README H1 as a short token list, rule-derived risk). The user confirms once in a single review table, instead of being asked per app.
- **Every prompt ends with a `Complete when:` line** (kept from straw-boss) and returns a fixed output shape. Resolving returns `{targets:[{name,dir,why,confidence}], question|null}`.
- **Rules are stated once.** Workspace rules live in `references/workspace.md`. `go` and the hook point to it instead of restating it (straw-boss repeats rules across skills).
- **Deterministic work goes in scripts, judgment goes in prompts.** Discovery, proposals, and validation are shell scripts with tests; the model only matches and confirms.

# Design

**Workspace detection.** Workspace mode applies when `CLAUDE_PROJECT_DIR` is not inside a git work tree and discovery finds ≥2 projects. That directory is `<WORKSPACE_ROOT>`.

Where workspace files live:
- Registry: `<WORKSPACE_ROOT>/.claude/workspace.json`
- Plans and ledger: `<WORKSPACE_ROOT>/.claude/`, via the existing HARNESS_ROOT fallback
- Generated routing block: `<WORKSPACE_ROOT>/CLAUDE.md`, a managed section between `<!-- yang-toolkit:workspace -->` markers, so the routing table is in context at launch

Nothing is ever written inside a project.

**`scripts/workspace/discover.sh`.**
- Scans to depth ≤2.
- A directory is a project if it has `.git` (dir or file), `.claude/`, `CLAUDE.md`, or `AGENTS.md`. Stop descending once one is found.
- Skips hidden dirs, `node_modules`, `vendor`, and `.venv`.
- NUL-safe, handling paths like `ProgramTrading/Program Trading` and `SDESString/SDESString`.
- Output is TSV: dir, kind (git|dir).

**`scripts/workspace/propose.sh`.** Prints a proposed `workspace.json` to stdout and writes nothing. Per project:

| Field | How it is proposed |
|---|---|
| `name` | slug of the dir |
| `match[]` | dir name, the manifest `name`, and the README/CLAUDE.md H1 split into ≤6 short tokens (≤24 chars each) |
| `risk[]` | rule table: `live-money` (broker/exchange SDK deps: shioaji, ccxt, ib_insync, alpaca), `pii` (student/guardian/user tables in the schema), `prod-deploy` (vercel.json, fly.toml, deploy workflows) |
| `forbidDirectCommit` | true when `risk` is non-empty |
| `localFiles[]` | detected `.env*` files, `sensitive: true` |

Non-git dirs with no code are proposed under `ignored[]`.

**`workspace.json` v1 schema (trimmed from straw-boss's `apps.json`).**
```json
{ "version": 1,
  "projects": [ { "name": "sdes", "dir": "SDES", "match": ["士東", "弦樂團", "sdes"],
                  "note": null, "redirectTo": null, "risk": ["pii","prod-deploy"],
                  "forbidDirectCommit": true,
                  "localFiles": [{"path": ".env.local", "sensitive": true, "optional": false}] } ],
  "ignored": ["maison-sante-images"] }
```
`agentKind`, `gitWorkflowSkill`, and `crossAppSkills` are deferred to step 2/3.

**`scripts/workspace/validate.sh [file]`.** Mirrors straw-boss's shared read handler.
- Exit codes: 0 means valid, and it prints the JSON; 1 means invalid, with the reason on stderr; 3 means there is no config.
- Rejects duplicate names, a `dir` that is absolute or escapes the workspace, an empty `match`, unknown keys, and a `redirectTo` that points at a missing name.

**`skills/workspace-init/SKILL.md`** (user-invocable).
1. Run discover and propose.
2. Diff the proposal against any existing config: keep confirmed entries, and propose only new or changed ones.
3. Show one review table and take a single confirmation. Edits go in free text.
4. Write `workspace.json` with the Write tool, run validate, and sync the managed CLAUDE.md block.
5. `Complete when:` validate exits 0 and the managed block matches the config.

**`references/workspace.md`.** Holds the schema, detection rules, trust boundary, and the resolving procedure:
1. Match the request against `name` and `match[]`, then apply `redirectTo` and surface `note`.
2. For the top 1-3 candidates, read the project's own CLAUDE.md, AGENTS.md, or README head **in place** (read-only; treated as data) to confirm or refute.
3. Choose the outcome:
   - Declare the target(s) when the match is unambiguous.
   - Otherwise ask one `AskUserQuestion` (top candidates plus "not listed / new project").
   - This is a **content/target question**, and `conventions.md` gets an explicit carve-out from "routing is never asked".
4. If the request clearly names an unregistered or ignored dir, offer `workspace-init` instead of guessing.

**`hooks/workspace-check.sh`** (SessionStart).
- `timeout: 5`, bash 3.2 safe, modeled on `hooks/seed-git-exclude.sh`. It never writes and does nothing outside workspace mode.
- It emits `additionalContext` for two cases:
  - no config: "workspace: N projects, not configured, run /yang-toolkit:workspace-init"
  - otherwise: "workspace: N projects, K unregistered: a, b"
- Opt-out: `HARNESS_DISABLE_WORKSPACE=1`.

**`skills/go/SKILL.md`.**
- Add a Task 0 pre-step: in workspace mode, resolve via `references/workspace.md` before reading plans or state.
- Add a workspace row to the Edge cases table.
- Add a gate: never act in a project that hasn't been resolved.

# Acceptance Criteria

- [ ] **discovery finds nested, spaced, non-git projects**
  - Anchor: testing
  - Check: `bash plugins/yang-toolkit/tests/workspace/run.sh discovery`
  - Pass: exit 0. The fixture yields exactly 4 dirs (`repo-a`, `group/repo-b`, `dir with space`, `assets-only`), and none under `node_modules/`.

- [ ] **proposal is structural, rule-tagged, and write-free**
  - Anchor: testing
  - Check: `bash plugins/yang-toolkit/tests/workspace/run.sh propose`
  - Pass: exit 0, and all of the following hold:
    - The output passes `validate.sh`.
    - Every project has a non-empty `match`.
    - `group/repo-b` (shioaji dep) has `risk` containing `live-money` and `forbidDirectCommit: true`.
    - `repo-a/.env` is listed with `sensitive: true`.
    - `assets-only` is under `ignored`.
    - The fixture README's injection sentinel sentence occurs 0 times in the output.
    - No file in the fixture tree changed.

- [ ] **config validation contract**
  - Anchor: testing
  - Check: `bash plugins/yang-toolkit/tests/workspace/run.sh validate`
  - Pass: exit 0. `validate.sh` returns:

    | Input | Exit |
    |---|---|
    | a valid file | 0 |
    | a missing file | 3 |
    | a duplicate name | 1 |
    | `dir: "../x"` | 1 |
    | empty `match` | 1 |
    | an unknown key | 1 |
    | a dangling `redirectTo` | 1 |

- [ ] **SessionStart hook: fast, read-only, silent outside workspaces**
  - Anchor: testing
  - Check: `bash plugins/yang-toolkit/tests/workspace/run.sh hook`
  - Pass: exit 0, and all of the following hold:
    - With no config, the output is `jq`-valid and its `additionalContext` contains `workspace-init`.
    - With a config registering 2 of 3 code projects, `additionalContext` contains `1 unregistered`.
    - Inside a git repo it prints nothing.
    - With `HARNESS_DISABLE_WORKSPACE=1` it prints nothing.
    - Each run is under 2 s and exits 0.
    - The fixture tree is unchanged.

- [ ] **doc + version parity**
  - Anchor: testing
  - Check: `bash plugins/yang-toolkit/hooks/doc-parity-check.sh --report`
  - Pass: exit 0 (`workspace-init` is listed in README + both usage manuals; badge equals plugin.json `0.20.0`).

- [ ] **real-workspace init and routing**
  - Anchor: human
  - Judge: the user
  - Artifact: a session launched in `~/Projects` that runs `/yang-toolkit:workspace-init`, then `/yang-toolkit:go` for three requests:
    - (a) 「SDES 繳費頁加一個欄位」
    - (b) 「Trading 的 killswitch 門檻調整」
    - (c) 「讓士東樂團的網站能跟自動化交易對接」
  - Pass:
    - init asks for confirmation exactly once, and the resulting `workspace.json` includes `SDESString/SDESString` and `ProgramTrading/Program Trading`.
    - (a) resolves to SDES, or asks one question that lists SDES.
    - (b) resolves to Trading.
    - (c) resolves to SDES + Trading, each with a reason citing the project's own files, and includes the step-3 note.
    - No request asks more than one question.

- [ ] **adversarial review of the change-set**
  - Anchor: adversarial-review
  - Judge: a fresh-context review agent
  - Artifact: the branch diff, including `references/workspace.md`, `skills/workspace-init/SKILL.md`, and `skills/go/SKILL.md`
  - Pass: no unresolved correctness or contract findings on:
    - no writes inside projects
    - no persisted model-written summaries
    - project files treated as data
    - only the target question is ever asked
    - the hook never writes
    - bash 3.2 portability
    - rules stated once, not duplicated across files

## Revision 1 -- 2026-09-29 (Acceptance Criteria)
The **real-workspace init and routing** criterion is superseded:
- Artifact: a fresh session in `~/Projects` (no `workspace.json` yet) running `/yang-toolkit:go` for requests (a), (b), (c) — no manual `workspace-init`.
- Pass: the first `go` registers the workspace itself (one announcement line + folder list, **zero** questions) and the resulting `workspace.json` includes `SDESString/SDESString` and `ProgramTrading/Program Trading`, with SDES carrying an alias such as 士東; (a) resolves to SDES or asks one question listing SDES; (b) resolves to Trading; (c) resolves to SDES + Trading each with a reason citing the project's own files, plus the step-3 note; no request asks more than one question.

# Files Touched

## Revision 1 -- 2026-09-29
Added: `plugins/yang-toolkit/scripts/workspace/status.sh` (one-call registry state shared by the hook and `go`) and `plugins/yang-toolkit/scripts/workspace/heads.sh` (one call reads every project head as quoted data), because auto-registration makes both called on every workspace `go`. Also `plugins/yang-toolkit/scripts/workspace/alias.jq` (single alias rule set for propose + validate), added after the delta review.

Superseded by this revision (kept above for history): Goal's "user-confirmed", Context's "routing facts the user confirmed" and "the user only confirms", Design's workspace-init steps 2-3 (review table + single confirmation), and "resolve before reading plans or state" (go now resolves after Task 0/1).

- plugins/yang-toolkit/scripts/workspace/discover.sh
- plugins/yang-toolkit/scripts/workspace/propose.sh
- plugins/yang-toolkit/scripts/workspace/validate.sh
- plugins/yang-toolkit/skills/workspace-init/SKILL.md
- plugins/yang-toolkit/references/workspace.md
- plugins/yang-toolkit/references/conventions.md
- plugins/yang-toolkit/skills/go/SKILL.md
- plugins/yang-toolkit/hooks/workspace-check.sh
- plugins/yang-toolkit/hooks/hooks.json
- plugins/yang-toolkit/tests/workspace/run.sh
- plugins/yang-toolkit/.claude-plugin/plugin.json
- README.md
- docs/usage.html
- docs/usage.zh.html
- CHANGELOG.md

# Out of Scope
- App-rooted worker dispatch, tmux panes, status/checkpoint files, peer messaging (step 2).
- Graph choice, orchestrator plans, Alert/Warn/Info reporting, merge gating across repos (step 3).
- Running yang-toolkit commands against a target project from the workspace session.
- Any persisted LLM-written project summary, embeddings, or vector index.
- `~/.config/harness/repos.json` and `/week` + `/today` (unchanged; unifying them with `workspace.json` is a later decision).
- Writing anything inside a registered project, including `.git/info/exclude`.

# Risks
- **Match phrases go stale when a project is renamed or repurposed.** Mitigations: the hook reports unregistered dirs; `workspace-init` re-runs as a diff; resolving always confirms against the project's live files.
- **Prompt injection via project files read at resolve time.** They are read as data, and only the top 1-3 heads are read. Nothing is persisted, and the propose script takes H1 tokens only, never prose.
- **The managed CLAUDE.md block in `~/Projects` is loaded at every launch there.** Keep it to about one line per project. With a CLAUDE.md present, the same level's AGENTS.md is no longer loaded by default (not an issue today).
- **Hook latency.** discover is `find`-bounded at depth 2 and runs no `git status`.
- **Permission prompts.** Each script call is a distinct Bash string. The README documents allow rules for `<WORKSPACE_ROOT>/.claude/settings.json`; nothing auto-writes them.
- **First test infrastructure in this repo.** `tests/workspace/run.sh` sets a convention: plain bash, `mktemp -d` fixtures, cleanup via trap.
- **`CLAUDE_PROJECT_DIR` in a non-git launch dir is undocumented.** It is expected to be the launch dir, with `$PWD` as fallback. Verify on the first real run.
- **A future step may reverse the tmux-for-Herdr choice.** Step 1 has no pane dependency, so it survives either choice.

# Memory References
<!-- auto-generated below; remove individual lines if irrelevant.
Lines without <!--auto--> are preserved on --revise.
<type> is one of: ledger | decision | claude-md | plan | pattern | external | house-rule.
For [external], <path> is a URL. -->

- <!--auto--> [external] https://github.com/wayne930242/straw-boss/blob/main/docs/architecture.md -- app-rooted workrooms instead of condensed summaries. The app list is confirmed project config. Smallest sufficient loop. Merge is always gated.
- <!--auto--> [external] https://github.com/wayne930242/straw-boss/blob/main/skills/init/references/apps-config-schema.md -- `apps.json` fields (name/dir/match/redirectTo/note/forbidDirectCommit/localFiles). Read handler exit codes 0/1/3.
- <!--auto--> [external] https://github.com/wayne930242/straw-boss/blob/main/skills/resolving-app/SKILL.md -- match against name+match. Clarify only when ambiguous. Return names+dirs; "Complete when" contract.
- <!--auto--> [pattern] plugins/yang-toolkit/skills/week/SKILL.md -- multi-repo skill precedent. A `## Configuration` contract; a missing config degrades with a printed template.
- <!--auto--> [pattern] plugins/yang-toolkit/hooks/seed-git-exclude.sh -- SessionStart template: `set -u`, `CLAUDE_PROJECT_DIR:-$PWD`, exit 0 on failure, `HARNESS_DISABLE_*` opt-out, bash 3.2 safe. Its git-work-tree guard is the inverse of workspace detection.
- <!--auto--> [pattern] plugins/yang-toolkit/skills/go/SKILL.md -- Task 0 (L28-50) is where the workspace pre-step goes. Edge-case table L204-214. Handoff passes references, not summaries (L139-143).
- <!--auto--> [pattern] plugins/yang-toolkit/references/conventions.md -- HARNESS_ROOT fallback outside git (L17-19). The durable-state table (L21-27) and the routing rule (L155-195) need a target-question carve-out.
- <!--auto--> [pattern] plugins/yang-toolkit/hooks/doc-parity-check.sh -- a new skill must be listed in README + both usage manuals, and the badge must match plugin.json. `--report` is runnable.
- <!--auto--> [ledger] .claude/ledger.jsonl#1 heartbeat-loop -- the only entry. Stale `in-progress`; unrelated, so not a depends_on.
- <!--auto--> [external] https://arxiv.org/abs/2602.11988 -- LLM-generated repo overviews lower success and raise cost. Keep context to non-obvious rules/commands.
- <!--auto--> [external] https://labs.cloudsecurityalliance.org/wp-content/uploads/2026/03/CSA_research_note_readme_instruction_injection_ai_coding_agents_20260317-csa-styled.pdf -- README injection is effective. Never persist README prose into shared state.
- <!--auto--> [external] https://code.claude.com/docs/en/memory -- a parent-dir launch loads that dir's CLAUDE.md at startup, but child CLAUDE.md only on file access. This justifies the managed routing block.
- <!--auto--> [external] https://code.claude.com/docs/en/hooks -- SessionStart `additionalContext`. Set a small explicit timeout.

# Execution Log
<!-- filled by /yang-toolkit:execute-plan post-hoc. Leave empty in draft. -->

## Run 1

**Timing:** started 2026-09-29T01:53:20Z. Parked at 2026-09-29T02:18:49Z, about 25 min in.

**Outcome:** parked as `awaiting-input`, kind `human-anchor`. The run is not finished. The ledger records `in-progress`.

**Setup:**
- **Orchestration:** `single`, resolved from `auto`. The reason: Files Touched span several directories, but they all depend on one shared contract: discover's TSV output, validate's exit codes 0/1/3, and the workspace.json schema. `tests/run.sh`, the hook, and `workspace-init` are all built on it, so parallel workers would each invent their own reading of it.
- **Discipline:** `normal`, with the implementation delegated to `/yang-toolkit:feature-dev-tracked`.
- **House rules:** none found.
- **`/goal`:** not set. The user chose "開始，不設 /goal". The agent can't type built-in slash commands, so the five testing Checks served as the completion gate, run at close-out.
- **Branch:** `feat/workspace-project-index`. Nothing is committed.

**Criteria:**

| Criterion | Anchor | How it closed |
|---|---|---|
| discovery finds nested, spaced, non-git projects | testing | `run.sh discovery`: exit 0 |
| proposal is structural, rule-tagged, and write-free | testing | `run.sh propose`: exit 0 |
| config validation contract | testing | `run.sh validate`: exit 0 |
| SessionStart hook: fast, read-only, silent outside workspaces | testing | `run.sh hook`: exit 0 (29-54 ms per run) |
| doc + version parity | testing | `doc-parity-check.sh --report`: exit 0, "badge in sync" |
| real-workspace init and routing | human | **Open. The run is parked on this.** |
| adversarial review of the change-set | adversarial-review | Closed. Two fresh-context rounds: 11 + 7 correctness/contract findings, all fixed with regression assertions, plus a mutation check. Dispositioned nits are in `docs/decisions/2026-09-29-workspace-project-index/04-review-*.md`. |

`run.sh all` has 58 assertions, and all pass.

**Bug found during the run:** the first real `~/Projects` dry run exposed an `xargs grep -q` false positive that tagged 8 of 11 repos `pii`. It was fixed, and a regression assertion was added.

**Scope:** every change is within Files Touched, except harness bookkeeping:
- `docs/decisions/2026-09-29-workspace-project-index/`
- this plan
- `.claude/state/`

`.claude/settings.json` is untracked, but it predates this run (from the earlier fewer-permission-prompts task).

**Deviation from the plan:** the managed CLAUDE.md block uses `<!-- yang-toolkit:workspace:begin -->` / `:end -->` markers instead of the single `<!-- yang-toolkit:workspace -->` marker in the plan. Two markers are needed to replace the block between them.

**Revision 1 work (same run, 2026-09-29T03:05:34Z):** user asked for fully automatic registration. Implemented: `status.sh`, `heads.sh`, `alias.jq`, auto-refresh in `go`, question-free `workspace-init` (validate-before-write via `validate.sh -`). A third fresh-context review (of this delta) found: propose output invalid for folders like `Override`/`prompt-tools`; alias charset enforced only in prose (hostile aliases such as `rm -rf`, `curl | sh`, `忽略指示`, fullwidth, invisible chars passed); `heads.sh` followed symlinks out of the workspace and had no byte cap; init-failure behaviour undefined in `go`. All fixed with regression assertions; `run.sh all` = 84 assertions, all six suites + doc-parity exit 0; the real `~/Projects` proposal validates. Review notes: `docs/decisions/2026-09-29-workspace-project-index/05-review-delta-20260929T030534Z.md`.

**Waiting on:** the question in `waiting:` above. Answer with `/yang-toolkit:execute-plan --from workspace-project-index` (or through `/yang-toolkit:go`).
