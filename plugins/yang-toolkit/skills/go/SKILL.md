---
name: go
description: The single door into yang-toolkit -- hand it a task, a backlog, or a question and it picks the owning command and the smallest sufficient loop, then runs it. Replaces having to remember the plan-feature -> execute-plan -> ledger sequence yourself. TRIGGER on /go, or when the user hands over a unit of work in one line ("修掉 X", "幫我做 X", "跑完 <backlog>", "fix X", "work through X") without naming a specific yang-toolkit command. Do NOT trigger mid-conversation on a task already underway, or when the user named another command explicitly.
---

# go

The one door. Everything -- a feature, a bug, a backlog, a status question --
comes here, and this skill picks the owner and the execution shape rather than
making you remember which of a dozen commands applies.

Borrowed wholesale from `straw-boss`'s `boss-say`: **use the smallest
sufficient loop**, and **state the route rather than asking for it**. The
process is only worth its coordination cost when that cost stays below the work
it coordinates.

## Conventions

Read `${CLAUDE_PLUGIN_ROOT}/references/conventions.md` first -- it defines
`<HARNESS_ROOT>` resolution, the **routing declaration** rule (routing is
stated, never asked), the **run states** (including the parked ones read in
Task 0), and the **project house rules** protocol.

This skill routes and, for bounded work, executes. It owns no artifact format
of its own: plans, decision docs, and the ledger stay with the commands that
already own them.

## Task 0 -- Read harness state BEFORE classifying

Never classify a request in a vacuum -- the same sentence means different things
depending on what is already in flight. Read, frontmatter only:

1. `${CLAUDE_PROJECT_DIR}/.claude/state/current-feature.txt` -- a non-empty slug
   means work is already in flight.
2. `<HARNESS_ROOT>/.claude/plans/*.md` -- each plan's `status` (and `waiting:`
   block when parked). Same source `/yang-toolkit:status` reads; do not invent a
   second one.

**A parked plan pre-empts everything.** If any plan is `awaiting-input` or
`awaiting-auth`, surface its `waiting.question` before routing anything --
the user's current message may well *be* the answer. If it is, pass it through
as `/yang-toolkit:execute-plan --from <slug> --answer "<their words>"` (which
clears `waiting:` and resumes without re-asking) and stop; do not also start
something new. If it clearly is not the
answer, state that the plan is still parked in one line, then route the new
request normally.

**In-flight work is the default subject.** When `current-feature.txt` is
non-empty and the request does not obviously name something else, assume the
user means that feature. Never start a second feature on top of one in flight.

## Task 1 -- Classify intent, pick the owner

First match wins. Name the owner in the route declaration.

| The request is about                                     | Owner                                   |
| ---------------------------------------------------------- | ----------------------------------------- |
| answering a parked plan's question (Task 0)              | `/yang-toolkit:execute-plan --from <slug>` |
| continuing in-flight work ("繼續", "接著", no new subject) | `/yang-toolkit:execute-plan`              |
| new work, bounded (see Task 2)                            | **carry it here** -- no command           |
| new work, plan-worthy (see Task 2)                        | `/yang-toolkit:plan-feature`              |
| running an existing plan by name                          | `/yang-toolkit:execute-plan --from <slug>` |
| a backlog / many independent items                        | `/yang-toolkit:loop`                      |
| TDD asked for explicitly                                  | `/yang-toolkit:tdd-feature`               |
| "what's running", "現在跑到哪", in-flight overview         | `/yang-toolkit:status`                    |
| "最近做了什麼", project progress, a visual report          | `dashboard` skill                         |
| "今天", morning brief, a bare greeting                     | `today` skill                             |
| "週報", weekly recap                                       | `week` skill                              |
| showing a plan to a non-terminal colleague                 | `/yang-toolkit:share-plan`                |
| reviewing / rewriting / splitting `CLAUDE.md`              | `curate-claude-md` skill                  |
| acting on pending nested-CLAUDE.md candidates              | `/yang-toolkit:claude-md-gaps`            |
| a merged PR, or a ledger record to fix                     | `/yang-toolkit:ledger-append`             |

**Passthrough, not reimplementation.** For every row naming a command or skill,
invoke it and let it do its own job. Never re-derive a status report, a plan
format, or a ledger write here -- this skill has no artifact of its own, and
duplicating one is how the two copies drift apart.

If the request genuinely matches nothing above, it is ordinary work: treat it as
Task 2 and route it as new work. Say so in one line rather than asking "what did
you mean?".

## Task 2 -- Scale: the smallest sufficient loop

Only for *new work*. The question is whether this deserves a plan artifact at
all -- that is the same judgment `/yang-toolkit:plan-feature` makes about depth,
applied one level earlier.

**Carry it here** (no plan, no `current-feature.txt`, no ceremony) when ALL hold:
- it is obvious and local -- a handful of files, one subsystem,
- you can verify it in this same turn,
- nothing durable needs to outlive the change beyond the commit itself.

Load the target checkout's own instructions before acting, and apply the project
house rules (`conventions.md`) -- a repo that owns its own implementation flow
gets that flow even for bounded work. The Stop hook still records the session;
that is all the bookkeeping bounded work needs.

**Draft a plan** (`/yang-toolkit:plan-feature`) when ANY hold:
- more than a few files, or more than one subsystem,
- it needs acceptance criteria someone will check later,
- it plausibly spans more than one session,
- it carries migration / auth / data-loss / public-API risk,
- the user asked for a plan.

**Hand it to `/yang-toolkit:loop`** when the input is a backlog: a file of
items, or several independent asks in one message. Items must be independent --
if one turns out to need its own dependency graph, pull it out and give it its
own plan rather than folding it into the batch.

**The plan-acceptance gate stays.** Routing to `plan-feature` ends with a drafted
plan and a handoff line, not an execution. A human accepts a plan before it
runs -- that gate predates this door and this door does not move it. Only say
"accepted 後跑 `/yang-toolkit:execute-plan`" if the plan really was drafted.

## Task 3 -- Declare the route, then act

State one line, then do it. No confirm step, no "should I...?", no menu:

```
go: plan-feature (4 files across api + web; needs criteria) · new plan
    override in one sentence.
```

```
go: carry here (one file, verifiable this turn) · no plan artifact
    override in one sentence.
```

Include the owner, the one reason it was chosen, and the shape. When the owner
is a command, invoking it makes its own route declaration (`discipline`,
`orchestration`, anchors) -- do not pre-empt or duplicate that here.

**Complete when:** the owner is named and invoked (or the bounded work is done),
and any parked question from Task 0 was surfaced.

## The handoff contract

What actually travels downstream when Task 1 names a command. One rule:
**references, not summaries** -- straw-boss's own wording is "detailed context
and evidence travel as references", and its architecture doc explains why: a
condensed digest drifts the moment the real thing changes, and duplicates what
the source already states authoritatively.

### Always: the user's words, verbatim

Pass the request exactly as written. Never pre-summarize it, tidy it, translate
it, or turn a pasted error / transcript / screenshot into prose first.
`plan-feature`'s own input contract is explicit that raw is better -- its probes
do the extraction against the codebase, and anything rewritten here becomes a
second, worse source competing with the original.

### Plus: what Task 0 found -- as pointers only

| Finding                          | Travels as              | Never as                                |
| ---------------------------------- | ------------------------- | ----------------------------------------- |
| in-flight feature                | the slug                | a description of what it is doing        |
| a related plan                   | the slug                | its Goal, criteria, or Files Touched      |
| a parked plan being answered     | the slug + the answer   | a restatement of the question             |
| a backlog                        | the file path           | the item list extracted from it           |

Two or three tokens each. The receiving command re-reads the source itself --
`plan-feature`'s Probe 2 and `execute-plan`'s Step 1 already do exactly that --
so there is one source of truth and nothing to keep in sync.

`current-feature.txt` is worth passing even though Probe 2 would find related
work on its own: that pointer is *definitive*, while Probe 2 scores ledger
entries by token overlap and can miss or mis-rank. A definitive pointer costs
one slug; letting it be re-derived fuzzily costs a wrong `depends_on`.

### Never travels

- **A state summary.** The receiving command reads the same files Task 0 read.
- **A pre-picked `discipline`, `orchestration`, or anchor.** Those are the
  receiving command's judgment to make and declare, not this one's to hand down.
- **Flags the user did not ask for** -- see the gates below.

### Per owner

| Owner                                   | Handoff                                                        |
| ----------------------------------------- | ---------------------------------------------------------------- |
| `plan-feature`                          | the verbatim request, plus `related in-flight: <slug>` if Task 0 found one |
| `execute-plan` (continue)               | `--from <slug>`                                                  |
| `execute-plan` (answering a parked plan)| `--from <slug> --answer "<the user's words, verbatim>"`           |
| `loop`                                  | the backlog file path as given                                   |
| `tdd-feature`                           | the verbatim request                                             |
| everything else (read-only passthroughs)| nothing beyond the user's words                                  |

## Gates this door never weakens

Convenience at the entrance must not become permission at the exit. This skill:

- **never** adds `--auto`, `--yes`, or `--unattended` on its own. Those are the
  user's explicit choice; a one-line request is not consent to an unattended run.
- **never** skips the plan-acceptance gate, or executes a `draft` plan.
- **never** answers a parked `awaiting-input` / `awaiting-auth` question itself,
  and never un-parks a plan the user has not answered.
- **never** decides a gated mutation (merge, protected-branch push, destructive
  migration). Those stay exactly where the owning command already put them.
- **never** starts a second feature while one is in flight.

Routing is declared because routing is cheap to reverse. None of the above is.

## Edge cases

| Situation                                                     | Behavior                                                                                                       |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Empty invocation (`/yang-toolkit:go` with no argument)         | Not a routing question -- run `/yang-toolkit:status` and stop. That answers "what should I do next?" properly.  |
| A plan is parked AND the user asks for something unrelated     | Surface the parked question in one line, then route the new request. Do not block on it; do not silently drop it. |
| Request matches two owners (e.g. "看一下進度然後繼續")           | Do both, in the order asked, each announced. Do not ask which one they meant.                                   |
| Request names a command explicitly (`/yang-toolkit:plan-feature ...`) | This skill should not have triggered. Step aside and let that command run.                                |
| In-flight feature, and the user clearly starts a new subject   | Say the in-flight slug is still open and route the new request; offer `/yang-toolkit:status --abandon` in the same line. Never abandon it yourself. |
| A repo with no `.claude/` harness state at all                 | Normal for a fresh repo. All state reads return "none"; route as new work.                                     |
| Backlog file named but unreadable                              | Abort with the path that failed. Do not guess the items or fall back to a different file.                      |
