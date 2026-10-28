# Roadmap

## Direction
Keep `prodicloud` as a pragmatic Azure VM operator toolkit with one clear mental model, strong validation before mutation, deterministic guest task execution, and documentation that is detailed enough for both operators and maintainers to work from the repository alone.

## Recently Delivered
- VC hardware resize now has a paged Intel/AMD and RAM wizard with a RAM exact-match toggle, region/subscription SKU filtering, family metadata, and a review-first apply step.
- VM disk resize now selects the OS or an attached data disk, expands Azure capacity and supported Windows/Linux guest filesystems, and offers guarded shrink through a temporary same-region `vc-helper` plus a replacement disk and rollback path.
- Windows disk shrink waits for Azure Guest Agent readiness, uses a temporary higher-throughput helper and parallelized file copy through asynchronous Managed Run Command, polls instance-view state and guest progress, retries one measured Robocopy idle or copy-error attempt, excludes only regenerated AppX alias and Docker runtime-socket directories from the offline OS copy, preserves hibernation by seeding the candidate from the exact hibernation-capable Marketplace image and setting `supportsHibernation`, clears that disposable image-based candidate before reconstructing the verified partition layout, restores and verifies WinRE after cutover, enforces a one-hour guest-step bound, and preserves the original disk until boot and guest verification succeed.
- Resize operations now print before/after state snapshots and verify the resulting VM SKU or OS disk size before persisting the requested configuration.
- Disk resize now reports Azure capacity, guest raw capacity, partition/unallocated space, and per-volume filesystem used/free space. Shrink remeasures the isolated source clone and verifies candidate used/free headroom before cutover, then reports a fresh post-resize inventory.
- Windows shrink normalizes exactly one small, empty leading MSR partition into the standard four-partition replacement layout; helper scripts use temporary `@file` arguments to avoid process-length failures. Windows expansion now repairs a guest volume when Azure capacity already matches the requested target, and checks only the selected volume filesystem.
- Managed group inventory includes the active marker, Azure location, and provisioning state; `show` can export a redacted JSON report.
- A versioned source release packager writes a build manifest and SHA256 sidecar, with clean-tree, version, and tracked-secret guards.
- Local task history records isolated task/package outcomes, workflow stage summaries, and deferred app-state work without recording guest output or credentials.
- The `pd.cmd` launcher preserves command-line arguments while loading the shared runtime.
- VM SKU validation checks the active subscription's offered SKU list before lifecycle changes, so restricted sizes fail before deallocation.
- The interactive power/status menu now sends only options accepted by the `do` command contract.
- The TUI now reuses a subscription-scoped managed inventory snapshot, with ETag/content change detection, time-based validation, explicit refresh, and mutation/subscription invalidation.
- A hidden read-only worker now keeps that inventory snapshot fresh across TUI screens and runs, and asynchronously warms per-VC package status; bounded retries, persisted refresh requests, and short-lived SSH bootstrap reuse reduce repeated Azure and remote calls.
- TUI startup now reads the saved subscription and active VC profile without waiting for inventory warmup. The first two console rows show the live screen, VC, subscription, operation, and cache status; inventory refresh requests are coalesced while the read-only worker remains independent of menu navigation.
- The optional TUI status strip is controlled by `TOP_STATUS_LINES` (default false); when enabled it avoids redundant writes and keeps `Ready` stable for screen readers.
- Nested-virtualization precheck now uses documented unsupported B-series family data if Azure omits the feature from the SKU capability response, preventing a guaranteed post-deploy guest-validation failure.
- Create review, the `set` command, VC details, and `show` now distinguish the Prodicloud nested-virtualization request from Azure settings and guest CPU-extension availability. Incomplete guest evidence stays unknown; outer-hypervisor presence and an enabled Windows feature no longer create false positives.
- VC creation now uses a numbered, paged wizard with visible defaults and validated OS disk-size and TCP port-range inputs; task selection and inventory group filtering are also numbered and paged.
- These pragmatic items were implemented and verified with fixture-backed tests only. No VC was provisioned or rebuilt.

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
- Continue improving long-running operation progress and cutover summaries; resize state snapshots and Azure readback verification are now in place.
- Make rollback-state visibility more obvious when a long-running Azure action fails mid-flight.
- Expand state-aware diagnostics for power, connection, and guest-task related failures.

### Richer Inspection
- Continue improving `show`, `group`, and related inspection paths while keeping output focused; managed-group metadata and redacted JSON export are now available.
- Make task catalogs easier to inspect directly from the CLI, especially for isolated init/update reruns.

### Better Maintainer Ergonomics
- Keep local hooks fast and focused.
- Tighten static contract checks when command/help/docs/config drift appears.
- Continue removing stale references and legacy names as soon as the repo has fully cut over.

## Later Value Band

### Release And Distribution
- Improve release-note generation and historical reporting with more repo-owned helpers and less manual reconstruction.
- Keep the versioned source package and checksum workflow aligned with future release needs without weakening the current local-first workflow.

### Task Metadata And Replayability
- Extend the new script-local task metadata model only where it creates real operator value, such as explicit prerequisites, reboot expectations, or task intent summaries.
- Consider lightweight replay or diagnostic bundles that help reproduce guest-task problems without destructive live loops.

## Opportunistic Work
- Optional policy-style checks for naming, logging, docs, and task-catalog hygiene.
- Read-only reporting/export is available through the managed report and redacted JSON output.
- Optional UI or dashboard layers remain conditional and should be considered only if they preserve the current repo-first, script-first operating model and meet the promotion rules.

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
