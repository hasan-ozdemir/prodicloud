# Roadmap

## Direction
Keep `clagnos` as a pragmatic Azure VM operator toolkit with one clear mental model, strong validation before mutation, deterministic guest task execution, and documentation that is detailed enough for both operators and maintainers to work from the repository alone.

## Working Style
- Prefer business value over feature count.
- Prefer safer operator workflows over convenience shortcuts.
- Prefer explicit contracts over compatibility clutter.
- Prefer a relaxed, sustainable delivery rhythm over calendar pressure.
- Promote work only when docs, tests, and runtime behavior can stay aligned in the same change.

## Near-Term Value

### Operator Reliability
- Keep tightening validation around Azure mutation paths such as create, update, move, resize, set, and delete.
- Continue reducing ambiguous runtime output so operators can tell what happened, why it happened, and what to do next.
- Keep isolated `exec` flows fast and dependable so failed guest tasks can be rerun without broad rebuild loops.

### Windows And Linux Parity
- Close the most important parity gaps whenever a feature lands first on one platform.
- Preserve one command surface and one set of operator expectations even when guest implementation differs.
- Keep task-catalog semantics identical across platforms even when the task bodies diverge.

### Documentation As A Real Interface
- Keep README, help text, AGENTS, changelog, release notes, roadmap, and prompt history synchronized.
- Make the command guide and architecture documentation complete enough that new contributors do not need hidden chat context to understand the system.
- Keep English-only maintained documentation and user-facing messaging as a first-class contract.

## Next Value Band

### Safer Change Operations
- Improve move and resize observability with clearer progress checkpoints, cutover summaries, and post-action state snapshots.
- Make rollback-state visibility more obvious when a long-running Azure action fails mid-flight.
- Expand state-aware diagnostics for power, connection, and guest-task related failures.

### Richer Inspection
- Improve `show`, `group`, and related inspection paths so they expose more useful metadata without becoming noisy.
- Make task catalogs easier to inspect directly from the CLI, especially for isolated init/update reruns.
- Add more actionable status summaries for managed resource groups and current VM context.

### Better Maintainer Ergonomics
- Keep local hooks fast and focused.
- Tighten static contract checks when command/help/docs/config drift appears.
- Continue removing stale references and legacy names as soon as the repo has fully cut over.

## Later Value Band

### Release And Distribution
- Introduce a cleaner release packaging story once the command surface and documentation stabilize further.
- Improve release-note generation and historical reporting with more repo-owned helpers and less manual reconstruction.
- Make versioned release artifacts easier to consume without weakening the current local-first workflow.

### Task Metadata And Replayability
- Extend the new script-local task metadata model only where it creates real operator value, such as explicit prerequisites, reboot expectations, or task intent summaries.
- Improve historical task-result and deferred-work visibility so post-failure diagnosis is faster.
- Consider lightweight replay or diagnostic bundles that help reproduce guest-task problems without destructive live loops.

## Opportunistic Work
- Read-only reporting or export paths for teams that also manage Azure resources with other tooling.
- Optional policy-style checks for naming, logging, docs, and task-catalog hygiene.
- Optional UI or dashboard layers only if they preserve the current repo-first, script-first operating model.

## Promotion Rules
An item is ready to move from idea to implementation only when:
- the operator value is clear
- the contract impact is understood
- the validation story is non-destructive or intentionally bounded
- docs, tests, and runtime updates can land together

## Done Criteria
Work is complete only when it includes:
- runtime or configuration changes where applicable
- aligned docs
- aligned tests or contract checks
- updated `CHANGELOG.md`
- updated `release-notes.md`
- prompt-history continuity for the delivered prompt
