export const meta = {
  name: 'execute-plan-team',
  description:
    'Parallel multi-agent execution of an accepted yang-toolkit plan: partition Files Touched into disjoint slices, implement each slice concurrently, then verify every (global) Acceptance Criterion.',
  phases: [
    { title: 'Implement', detail: 'one agent per file-partition, editing disjoint paths in parallel' },
    { title: 'Verify', detail: 'one agent per Acceptance Criterion; runs its Check command and reports pass/fail' },
  ],
}

// ---------------------------------------------------------------------------
// args is supplied by /yang-toolkit:execute-plan after it has parsed + linted
// the plan. The workflow itself has NO filesystem access, so everything the
// script needs must arrive through args; all file I/O happens inside agents.
//
// args = {
//   slug:               string,
//   goal:               string,
//   acceptanceCriteria: [{ name, check, pass }],   // check is a runnable command
//   filesTouched:       [string],                  // paths or globs, disjoint by intent
//   outOfScope:         [string],
//   depSummaries:       [string],                  // ~100-token blurbs, may be empty
//   teamSize:           number,                    // desired parallel workers (default 3)
// }
// ---------------------------------------------------------------------------

const a = args || {}
const criteria = a.acceptanceCriteria || []
const files = a.filesTouched || []

if (!files.length) {
  log('No Files Touched in the plan — nothing to partition. Aborting workflow.')
  return { slug: a.slug, error: 'no-files-touched', achieved: false }
}

const teamSize = Math.max(1, Math.min(a.teamSize || 3, files.length))

// --- partition files by directory affinity --------------------------------
// Group paths by their parent directory, then greedily pack the largest groups
// into the currently-smallest bucket so workers get balanced, contiguous slices.
function dirOf(p) {
  const i = p.lastIndexOf('/')
  return i === -1 ? '' : p.slice(0, i)
}

const byDir = {}
for (const f of files) {
  const d = dirOf(f)
  ;(byDir[d] = byDir[d] || []).push(f)
}

const buckets = Array.from({ length: teamSize }, () => [])
const groups = Object.values(byDir).sort((x, y) => y.length - x.length)
for (const g of groups) {
  let min = 0
  for (let i = 1; i < buckets.length; i++) {
    if (buckets[i].length < buckets[min].length) min = i
  }
  buckets[min].push(...g)
}
const partitions = buckets.filter((b) => b.length)

log(`Partitioned ${files.length} path(s) into ${partitions.length} worker(s) by directory affinity`)

// --- shared context every implementer + verifier sees ----------------------
const sharedContext = [
  `## Goal`,
  a.goal || '(none stated)',
  ``,
  `## Acceptance Criteria (GLOBAL — every one of these must hold once ALL workers finish)`,
  ...criteria.map((c) => `- **${c.name}**: \`${c.check}\` → ${c.pass}`),
  a.outOfScope && a.outOfScope.length
    ? `\n## Out of Scope (must NOT change)\n${a.outOfScope.map((s) => `- ${s}`).join('\n')}`
    : '',
  a.depSummaries && a.depSummaries.length
    ? `\n## Dependency context\n${a.depSummaries.join('\n')}`
    : '',
]
  .filter(Boolean)
  .join('\n')

// --- Phase 1: implement, in parallel, on DISJOINT file sets ----------------
// Disjoint partitions are what makes the parallel writes safe without worktree
// isolation. If a worker reports a scopeViolation it means partitions overlapped
// or a shared file was needed — surfaced back to execute-plan, not silently eaten.
const IMPL_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['filesWritten', 'summary'],
  properties: {
    filesWritten: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    scopeViolations: {
      type: 'array',
      items: { type: 'string' },
      description: 'paths this worker had to touch that were NOT in its assigned slice',
    },
  },
}

const impl = (
  await parallel(
    partitions.map((bucket, i) => () =>
      agent(
        [
          `You are worker ${i + 1} of ${partitions.length} implementing ONE slice of a planned feature.`,
          ``,
          sharedContext,
          ``,
          `## YOUR files — edit ONLY these. Touching anything else is a scope violation you must report.`,
          ...bucket.map((f) => `- ${f}`),
          ``,
          `Rules:`,
          `- Implement only your slice toward the Goal and the criteria that depend on your files.`,
          `- Other workers are editing the OTHER files concurrently; do not touch theirs.`,
          `- Do NOT run git commands and do NOT commit.`,
          `- If you genuinely cannot finish without editing a file outside your slice, do the minimum and list that path in scopeViolations.`,
        ].join('\n'),
        { label: `impl:${bucket[0]}`, phase: 'Implement', schema: IMPL_SCHEMA }
      )
    )
  )
).filter(Boolean)

// --- Phase 2: verify each GLOBAL criterion ---------------------------------
// Barrier is correct here: criteria are global, so verification can only run
// once every implementer has finished. One agent per criterion, runs the real
// Check command, reports only (no fixing).
const VERIFY_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['name', 'passed', 'evidence'],
  properties: {
    name: { type: 'string' },
    passed: { type: 'boolean' },
    evidence: { type: 'string', description: 'the observed command output or state that justifies the verdict' },
  },
}

const verdicts = (
  await parallel(
    criteria.map((c) => () =>
      agent(
        [
          `Verify ONE acceptance criterion for the feature that was just implemented.`,
          ``,
          `Criterion: ${c.name}`,
          `Run exactly this check, unmodified: \`${c.check}\``,
          `Pass condition: ${c.pass}`,
          ``,
          `Run the command, observe the REAL output, and report whether the pass condition actually holds.`,
          `Do not fix or edit anything — report only. If the command cannot run, set passed=false and explain in evidence.`,
        ].join('\n'),
        // Independent, cheap verifier: a criterion's Check command is mechanical
        // (run it, observe output, report pass/fail) -- Haiku at low effort is the
        // right tier, and keeping the verifier a cheaper model than the implementer
        // enforces maker/checker separation on cost as well as identity.
        { label: `verify:${c.name}`, phase: 'Verify', schema: VERIFY_SCHEMA, model: 'haiku', effort: 'low' }
      )
    )
  )
).filter(Boolean)

const failed = verdicts.filter((v) => !v.passed)
const scopeViolations = [...new Set(impl.flatMap((r) => r.scopeViolations || []))]

return {
  slug: a.slug,
  workers: partitions.length,
  partitions,
  filesWritten: [...new Set(impl.flatMap((r) => r.filesWritten || []))],
  workerSummaries: impl.map((r) => r.summary),
  criteria: { total: criteria.length, passed: verdicts.length - failed.length, failed: failed.length },
  verdicts,
  scopeViolations,
  // achieved only when there is at least one criterion and every one passed
  achieved: criteria.length > 0 && failed.length === 0,
}
