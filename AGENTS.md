# AGENTS.md - clagnos Engineering Contract

## Purpose
This repository manages Azure VM provisioning and lifecycle operations for Windows and Linux through one PowerShell orchestration entrypoint plus an interactive menu frontend. The project optimizes for parity, deterministic behavior, strong validation before mutation, and operator-visible outcomes.

## Source of Truth Hierarchy
Use these sources in this order when maintaining the repo:
1. Current code and task-folder manifests for runtime behavior.
2. Current CLI/help output for command-surface truth.
3. Current `.env.example` for committed configuration contract.
4. Current local `.env` only when a user explicitly states that their local runtime configuration is the temporary source of truth for alignment work.
5. Git history for project evolution.
6. Relevant `.codex` session JSONL files for workflow, decision, and prompt-history reconstruction.

## Repository Context Assimilation Rule
- For every user prompt implementation, scan the current repo context before coding:
  - codebase structure (`modules/`, task directories, tools, tests)
  - active documentation contract (`AGENTS.md`, `README.md`, `CHANGELOG.md`, `release-notes.md`, `docs/prompt-history.md`)
  - test and quality entrypoints
- Treat this scan as mandatory pre-work, not optional discovery.
- Implement changes so they align with:
  - existing architecture and naming conventions
  - current command and configuration contracts
  - established workflow and validation patterns
- Do not introduce behavior that conflicts with repository standards when a compatible approach already exists in the codebase.
- At the start of a new coding session, the assistant must re-assimilate repository context (code, docs, tests, recent history) before making edits.
- Prefer extending existing patterns over creating parallel patterns.
- Respect repository continuity: keep behavior and terminology coherent with prior development unless the user explicitly requests a contract-breaking change.

## Repository Map
- `cg.cmd`: elevated interactive launcher for Windows operators.
- `scripts/clagnos-cli.ps1`: numbered and lettered Clagnos menu frontend.
- `clagnos.ps1`: unified orchestration and direct-command entrypoint used by the menu.
- `modules/`: runtime modules grouped by domain.
- `packages/builtin/<platform>/` and `packages/custom/<platform>/`: isolated standard and operator-authored package catalogs with `package.json` manifests and per-package installers.
- `windows/init/`, `windows/update/`: Windows stage roots with portable task folders at the root, portable disabled task folders under `disabled/`, and portable local-only task folders under `local/` and `local/disabled/`.
- `linux/init/`, `linux/update/`: Linux stage roots with portable task folders at the root, portable disabled task folders under `disabled/`, and portable local-only task folders under `local/` and `local/disabled/`.
- `tools/`: helper tooling, pyssh bootstrap, git-hook toggles, and support scripts.
- `tests/`: static, compatibility, audit, and contract checks.
- `docs/prompt-history.md`: human-readable prompt ledger for this repo.

## Architecture Invariants
- Keep one Azure orchestration entrypoint: `clagnos.ps1`; `scripts/clagnos-cli.ps1` is a frontend and must dispatch through the shared command/resource handlers.
- Keep Linux and Windows flow and wording as identical as possible.
- Allow differences only where platform requirements genuinely differ:
  - image selection and guest OS behavior
  - init/update task language
  - Windows-only RDP and Windows service configuration
- Prefer explicit orchestration steps over hidden side effects.
- Prefer portable task folders plus `task.json` manifests over hard-coded ad hoc execution order.
- Keep command behavior deterministic across interactive and auto flows.

## Command-Surface Rules
- Current public commands are: `configure`, `create`, `initialize`, `update`, `list`, `show`, `do`, `task`, `package`, `component`, `connect`, `move`, `resize`, `set`, `exec`, `delete`, `help`.
- Do not preserve removed commands or aliases once the repo has cut over to a new surface.
- If a command or option is renamed, remove the old form cleanly and update all docs/tests in the same change.
- When a public option is renamed, rename the owning parameter files, manifest entries, parser lookups, help text, README examples, and smoke coverage in the same change; do not leave retired parameter-module filenames behind.
- Use `step` for top-level orchestration phases and `task` for guest task execution.
- Keep help output, README examples, and runtime messages aligned with the actual parser contract.
- Canonical target selectors are `--group` / `-g`, `--vm-name` / `-v`, and `--subscription-id` / `-s`.
- Value-taking options must accept both `--option=value` and `--option value`, plus short-form `-x=value` and `-x value` when a short alias exists.
- `task` owns task inventory, explicit task enable/disable, isolated `vm-init` / `vm-update` task runs, and task-scoped app-state save/restore.
- `task --save-app-state` defaults to `--source=vm`; `task --restore-app-state` defaults to `--target=vm`; both default to `--user=.all.`.
- `task --save-app-state` / `--restore-app-state` accept `--user=.all.`, `--user=.current.`, one explicit user, or a comma-separated user list.
- Local-machine task app-state save/restore is Windows-host-only, must validate the current `task.json` allow-list before local restore, and must write task-adjacent backup snapshots plus both `restore-journal.json` and `verify-report.json` before mutating the operator machine.
- `exec` is SSH-only: it may open an interactive shell or run one remote command through `--command` / `-c`, but it must not own isolated task execution.
- `connect` owns interactive/test connection flows and requires exactly one transport flag: `--ssh` or `--rdp`.
- `create` is fresh-only: it creates one new managed resource group plus one new managed VM target and must not be documented or wired as an existing-resource reuse path. It creates the initial network and does not run `vm-init`, `vm-update`, or package installation operations.
- `initialize` runs enabled `vm-init` tasks for one existing managed VM and does not create infrastructure.
- `update` is existing-managed-target only: it requires one existing managed resource group plus one existing VM and must not fall through to implicit fresh-create behavior. It runs enabled `vm-update` maintenance tasks; packages are isolated under `package` catalogs and never discovered as stage tasks.
- `package` owns status, install/update, uninstall, and availability for validated packages in the isolated `builtin` and `custom` catalogs. Every operation names exactly one catalog.
- `component` owns CRUD for Clagnos-managed resource groups, VMs, managed disks, VNets, subnets, NICs, public IPs, NSGs, and NSG rules. It must not expose generic CRUD for unrelated subscription resources.
- `configure` is the interactive `.env` frontend: it must stay focused on reviewing, editing, validating, previewing, and saving supported `.env` values, and it must not sync `.env` from a live Azure target.
- `configure` must recover softly for blank-permitted fields: stale or empty picker-backed values should guide the operator back to a valid choice when possible, otherwise clear the staged value and continue; save may be blocked only by unresolved create-critical values.
- Azure-touching commands support `--subscription-id` plus `-s`; resolution precedence is CLI override -> `.env` `SELECTED_AZURE_SUBSCRIPTION_ID` -> active Azure CLI subscription.
- Azure-touching commands require an authenticated Azure CLI session; help, README, and runtime errors must say `az login` is required. `configure` is the exception: it may open without `az login`, but Azure-backed configure fields must stay read-only until Azure validation is available.
- Interactive `create` and `update` must prompt for Azure subscription selection when `--subscription-id` is omitted.
- Interactive `initialize` must also prompt for Azure subscription selection when `--subscription-id` is omitted.
- The TUI `Cloud subscriptions` menu must list every accessible Azure subscription, mark both the Clagnos-selected subscription and Azure CLI active default, and allow numeric selection. A selection must update `az account set` and persist `SELECTED_AZURE_SUBSCRIPTION_ID` so all later TUI operations use the selected subscription.
- `list` is the managed inventory command: it must stay Azure-read-only, must not mutate Azure resources, and must expose managed resource listings through `--type` plus optional exact `--group` filtering.
- Managed inventory and target validation recognize both `managed-by=clagnos` and the legacy `managed-by=az-vm` tag until the interactive first-inventory migration is accepted and completed. New groups use `managed-by=clagnos`.
- Component deletion must show every resource in the dependency chain before mutation, delete dependents before dependencies, verify Azure resource absence, and attempt provider-specific purge only where supported. Never claim universal immediate name reuse when Azure retention or provider rules prevent it.
- Auto-mode strictness is part of the public contract: `create --auto` must resolve platform, VM name, Azure region, and platform VM size from CLI or `SELECTED_*` plus platform defaults in `.env`; `update --auto` must resolve one managed target from CLI or the selected target values in `.env`.
- `resize --disk-size` requires exactly one intent flag, `--expand` or `--shrink`; shrink remains a non-mutating guidance path when Azure cannot perform the requested change safely.

## Configuration Rules
- Runtime precedence is: CLI override > `.env` value > hard-coded default.
- `.env` is local-only and must remain untracked.
- `.env.example` is the committed configuration contract and must stay current.
- Keep app-wide customization, secrets, operator identity, and reusable overrides in `.env`.
- Keep task-only customization in a clearly labeled config block at the top of the owning `vm-init` or `vm-update` script.
- Do not hard-code personal, company-specific, or secret fallback values in runtime code or shared orchestration paths.
- Use generic env keys whenever possible.
- Treat `SELECTED_*` keys as the only persisted active-selection contract in `.env`.
- Use `SELECTED_AZURE_SUBSCRIPTION_ID` as the shared default Azure subscription selector for Azure-touching commands.
- Use `SELECTED_COMPANY_NAME` for repo-managed Windows business web shortcuts and `SELECTED_EMPLOYEE_EMAIL_ADDRESS` local-part for repo-managed Windows personal web shortcuts.
- Normalize repo-managed Windows Chrome `--profile-directory` values to lowercase even when `.env` casing differs.
- Keep `SELECTED_EMPLOYEE_FULL_NAME` in `.env` as required operator identity metadata for the Windows public desktop shortcut contract.
- Use shared keys such as `VM_ENABLE_HIBERNATION` and `VM_ENABLE_NESTED_VIRTUALIZATION` for cross-platform VM feature intent instead of inventing platform-specific duplicates.
- Use `WIN_` or `LIN_` keys only for true platform-specific settings.
- Remove deprecated env keys instead of keeping compatibility fallbacks.
- Validate region, VM naming, SKU, image, and other mutation-critical config before Azure create/update/delete operations.

## Naming and Resource Rules
- `SELECTED_VM_NAME` is the persisted naming seed.
- Template-driven resource names must derive from the effective `SELECTED_VM_NAME` runtime value, region code, and the committed templates.
- Resource-group uniqueness is suffix-based and deterministic.
- Managed resource name generation must remain explicit, predictable, and validation-backed.
- Managed resource group ids use a globally increasing `gX` suffix across all managed groups, regardless of region.
- Managed resource ids use a globally increasing `nX` suffix across all generated managed resources; one generated `nX` must not be reused by another managed resource, even across resource types.
- If naming rules change, update README, tests, and any naming-related summaries in the same change.

## Task Folder Rules
- Each task lives in a portable folder named `<task-number>-verb-noun-target`.
- Each task folder must contain one same-named task script plus one `task.json`.
- Task-number bands are:
  - `01-99` for `initial`
  - `101-999` for `normal`
  - `1001-9999` for intentionally local-only tasks
  - `10001-10099` for `final`
- `task.json` is the execution-order, enable-state, timeout, asset, and app-state source of truth for tracked and local-only task folders.
- Intentionally local-only tasks live under `local/` as portable task folders and are discovered from disk at runtime.
- Intentionally local-only disabled tasks live under `local/disabled/` and remain disabled by location.
- Root `disabled/` remains for tracked disabled tasks.
- A missing task folder must be treated as absent; init/update execution must continue cleanly as if that task never existed.
- Malformed task folders must warn and skip instead of aborting the stage, unless duplicate names or duplicate effective priorities make execution order ambiguous.
- The only allowed task app-state source is the owning task or package plugin zip `<task-folder>/app-state/app-state.zip` or `<package-folder>/app-state/app-state.zip`.
- Builtin and local-only init/update task folders must use the same post-process app-state contract and the same exact task-local plugin path rule.
- Task-local `app-state/` folders are untracked and git-ignored; missing task plugins must log a skip and continue instead of failing the stage.
- Sanitized package-local `app-state/app-state.zip` snapshots are versioned with their owning package manifests. Before adding or updating a snapshot, validate its allow-listed payload, generalized target paths, and absence of credentials or machine identity with `tests/package-app-state-contract-check.ps1` and the sensitive-content audit.
- Task- or catalog-adjacent `backup-app-states/` folders are untracked and git-ignored; local-machine restore must write backups under the owning task-stage or package-catalog root, verify the restored content, and roll back from that backup root if verification fails.
- Stage-root shared `app-states/`, task-side helper folders outside the owning task folder, and any legacy overlay paths must not be used as alternate app-state storage locations.
- Managed app-state save and restore must target only the `manager` and `assistant` OS profiles. Do not capture or replay `default` or arbitrary local user profiles.
- App-state capture is settings-first. Exclude generated installers, models, telemetry trees, caches, and other low-value runtime artifacts unless a task explicitly proves they are durable required state.
- `task.json` supplies task-only ordering, enable state, timeout, assets, app-state, and dependencies. It must not define package metadata.
- Each package lives under exactly one of `packages/builtin/<platform>/<package-id>/` or `packages/custom/<platform>/<package-id>/` and contains one `package.json` plus one platform installer (`install.ps1` or `install.sh`). The folder id must match the manifest id. Builtin and custom catalogs are discovered and operated independently.
- `package.json` owns package identity, display name, category, enabled state, installer timeout, validated status and uninstall actions, package assets, optional app-state policy, and optional post-install tasks. Runtime discovery must not write package manifests; only explicit `package --action enable|disable` may update `enabled` after typed confirmation, preserving other metadata and verifying the result.
- Package app-state identity may use `appStateKey` to preserve previously captured package snapshots when a package folder or public id is migrated.
- Package app-state archives must contain only portable preferences selected by `package.json`; do not capture credentials, authenticated browser profiles, tokens, caches, histories, workspace databases, or licensing/activation registry state.
- Generalize source-user and machine paths in captured package app-state with the supported `%CLAGNOS_*%` tokens. Capture normalizes known profile paths, SIDs, drive roots, Visual Studio instance ids, host names, and source addresses; restore resolves tokens against the target VM and selected `manager`/`assistant` profile immediately before replay. Unknown or unavailable tokens must fail before replay.
- Supported package app-state placeholders include `%CLAGNOS_COMPUTER_NAME%`, `%CLAGNOS_SYSTEM_DRIVE%`, `%CLAGNOS_SYSTEM_ROOT%`, `%CLAGNOS_WINDOWS_DIRECTORY%`, `%CLAGNOS_PROGRAM_DATA%`, `%CLAGNOS_PROGRAM_FILES%`, `%CLAGNOS_PROGRAM_FILES_X86%`, `%CLAGNOS_PRIMARY_IPV4_ADDRESS%`, `%CLAGNOS_TARGET_CPU_COUNT%`, `%CLAGNOS_TARGET_MEMORY_GB%`, `%CLAGNOS_VM_ADMIN_USER%`, `%CLAGNOS_ASSISTANT_USER%`, `%CLAGNOS_TARGET_USER%`, `%CLAGNOS_TARGET_PROFILE_PATH%`, `%CLAGNOS_TARGET_HOME%`, `%CLAGNOS_TARGET_UID%`, `%CLAGNOS_TARGET_GID%`, `%CLAGNOS_TARGET_USER_SID%`, `%CLAGNOS_VM_ADMIN_PROFILE_PATH%`, `%CLAGNOS_ASSISTANT_PROFILE_PATH%`, `%CLAGNOS_VM_ADMIN_HOME%`, `%CLAGNOS_ASSISTANT_HOME%`, `%CLAGNOS_VM_ADMIN_UID%`, `%CLAGNOS_ASSISTANT_UID%`, `%CLAGNOS_VM_ADMIN_GID%`, `%CLAGNOS_ASSISTANT_GID%`, `%CLAGNOS_VM_ADMIN_USER_SID%`, `%CLAGNOS_ASSISTANT_USER_SID%`, `%CLAGNOS_LOCAL_APP_DATA%`, `%CLAGNOS_ROAMING_APP_DATA%`, and `%CLAGNOS_VS_INSTANCE_DIRECTORY%`.
- `%CLAGNOS_SYSTEM_DRIVE%`, `%CLAGNOS_WINDOWS_DIRECTORY%`, `%CLAGNOS_TARGET_USER_SID%`, `%CLAGNOS_VM_ADMIN_USER_SID%`, `%CLAGNOS_ASSISTANT_USER_SID%`, and `%CLAGNOS_VS_INSTANCE_DIRECTORY%` are Windows-only. `%CLAGNOS_SYSTEM_ROOT%`, `%CLAGNOS_TARGET_HOME%`, `%CLAGNOS_TARGET_UID%`, `%CLAGNOS_TARGET_GID%`, `%CLAGNOS_VM_ADMIN_HOME%`, `%CLAGNOS_ASSISTANT_HOME%`, `%CLAGNOS_VM_ADMIN_UID%`, `%CLAGNOS_ASSISTANT_UID%`, `%CLAGNOS_VM_ADMIN_GID%`, and `%CLAGNOS_ASSISTANT_GID%` are Linux-only. The shared capture and replay code must reject a token that has no value on the selected guest OS.
- `tools/maintain-package-app-state.ps1` reports its planned package app-state policy by default and rewrites builtin package snapshot policies and payloads only with `-Apply`. Keep its allow-list aligned with `tests/package-app-state-contract-check.ps1`.
- Task priority precedence is: `task.json priority` -> filename task number -> deterministic fallback within the current task-number band.
- Runtime discovery and execution must not auto-write, auto-sync, or auto-reconcile task or package manifests. The explicit `task --enable` / `task --disable` operation may change only the task's `enabled` field after typed confirmation, must preserve all other metadata, and must verify the resulting catalog state; location-disabled folders must move only between their matching active and `disabled/` roots.
- For task folders with missing `priority`, default to the filename task number when available, otherwise `1000`.
- For task folders with missing `timeout`, default to `180`.
- Disabled tasks belong under `disabled/` and must be ignored by execution logic.
- Package manifests must supply a display name, category, an installed-state check, and an explicit allow-listed uninstall action. Packages must not be embedded in `task.json` or task-stage folders.
- The Manage Programs screen must offer separate builtin and custom catalog paths and label each row `[builtin]` or `[custom]`. Disabled packages display `(disabled)`; `e`/`d` change package availability, status and uninstall remain available while disabled, and install/update is blocked until re-enabled.
- Init and update task inventories may diverge by platform, but the orchestration model should remain parallel in concept.

## Reliability and Error-Handling Rules
- Validate before mutating Azure resources.
- Keep component create/update/delete forms scoped to validated fields and the active Clagnos-managed resource group.
- If Azure cannot purge a resource or release its name immediately, report the provider's result and do not claim the name is reusable.
- Prefer fast, filtered Azure checks over broad slow listings.
- If Azure does not support a requested operation safely, fail before mutation with the explicit platform reason and list the supported alternatives.
- When lifecycle or connection flows find a VM stuck in provisioning state `Updating`, use one explicit bounded `az vm redeploy` repair attempt before failing the operation.
- Fail gracefully with:
  - a short reason
  - a precise corrective hint
  - no ambiguous extra noise
- Avoid retry storms. Retry policies must stay explicit and intentionally bounded.
- Prefer isolated diagnosis and targeted reruns over destructive full rebuild loops unless the user explicitly wants a rebuild.

## Logging and UX Rules
- Keep user-facing strings, comments, help text, and UI wording in English.
- Keep maintained repository documentation in English.
- The only allowed language exception is for literal user-defined display labels or product/site names that are intentionally preserved as-is, such as specific desktop shortcut titles.
- Keep Linux and Windows wording aligned for equivalent behavior.
- Keep logs contextual, singular, and readable.
- Before every Azure CLI request, VM lifecycle operation, remote guest command, task, package install/status/uninstall, and long wait, print an English `Doing: <action>` progress message; never leave the operator waiting without a current action label.
- For blocking Azure CLI or Azure REST waits, emit a bounded progress heartbeat at least every 30 seconds. Do not include passwords, tokens, or other secret argument values in progress labels.
- Explicit `exec --quiet` suppresses remote command chatter but still prints local `Doing:` progress labels and wait heartbeats.
- Do not emit duplicate informational lines without a real state change.
- Show durations for long-running operations when the feature exists, but avoid noisy transcript spam.
- When a stage produces warnings, failures, or reboot requests, summarize them clearly at stage end.
- Interactive `create`, `initialize`, and `update` are review-first flows: `create` reviews `group` and `vm-deploy`; `initialize` reviews `vm-init`; `update` reviews `vm-update`.
- `configure` and `vm-summary` must always render without confirmation, even when partial step selection skips interior mutation stages.

## Windows Package and Path Rules
- Bootstrap Chocolatey unattended when missing.
- Enable `allowGlobalConfirmation` exactly once immediately after Chocolatey bootstrap.
- Call `refreshenv.cmd` after Chocolatey bootstrap and after each package installation verification step that depends on updated PATH resolution.
- Keep package-install behavior explicit. Do not add silent fallback installers unless the user explicitly requests them.
- Repo-managed Windows shortcuts must resolve to a real executable path, a validated embedded command path, or a valid `shell:AppsFolder\\<AUMID>` launch target; otherwise the shortcut must be skipped with a warning and stale managed aliases cleaned up.
- When a Windows task writes startup shortcuts or startup registry entries, it must verify the written artifact immediately instead of assuming startup registration succeeded.

## Python Tooling Rules
- Repo-managed Python execution must not generate `__pycache__`, `.pyc`, or `.pyo` artifacts.
- Use repo-owned execution wrappers and environment guards for Python-based helpers.
- Keep pyssh tooling self-contained under `tools/pyssh` and bootstrappable from the repo.

## Testing and Quality Rules
- Maintain PowerShell 5.1 and PowerShell 7 compatibility.
- Keep non-live quality checks runnable locally.
- Keep CI non-destructive and non-live; do not run real Azure provisioning in GitHub Actions.
- Maintain a local hook path and a GitHub Actions quality gate together.
- No commit may introduce concrete secrets, contact-style values, personal identifiers, organization identifiers, or live-target sample values into tracked code, docs, examples, tests, or commit messages.
- Maintain an always-on sensitive-content audit in local hooks and CI; update that audit in the same change whenever new committed surfaces or new leak-prone example formats are introduced.
- Keep sanitized package app-state snapshots in Git and run their tracking, portability, and sensitive-payload contract check in the non-live quality gate. Keep the explicit live Azure acceptance script gated by `-RunLive` and out of CI.
- For live publish or release-readiness claims, require one successful end-to-end live acceptance cycle against the active profile: clean `create` when safe, full natural-order `update`, `show` redaction check, `do --vm-action=status`, connection tests, and enabled feature verification.
- Update audit/contract checks when command names, docs, env keys, or task-folder behavior change.
- Maintain a TUI operation-coverage check: every public command and registered component/package action must be reachable from a numbered or lettered menu path.

## Documentation Responsibilities
- `AGENTS.md`: engineering contract and collaboration rules.
- `README.md`: operator and contributor guide.
- `LICENSE`: repository licensing terms.
- `CONTRIBUTING.md`: contributor workflow, expectations, and review hygiene.
- `SUPPORT.md`: operator/support routing and escalation guidance.
- `SECURITY.md`: vulnerability-reporting policy and private disclosure path.
- `CODE_OF_CONDUCT.md`: participation expectations for repository spaces.
- `CHANGELOG.md`: full project history from first day to today.
- `release-notes.md`: current release-oriented summary.
- `roadmap.md`: forward-looking project plan.
- `docs/prompt-history.md`: human-readable prompt ledger with English-normalized user prompts and assistant summaries.
- When maintained repository documentation records a time-of-day, record it in UTC.

## Release Versioning Rule
- `CHANGELOG.md` and `release-notes.md` must use `YYYY.M.D.N`.
- `N` is the cumulative repository commit count at the documented release point.
- Keep changelog and release-notes version labels aligned for the current documented release.

## Prompt-History Rule
- Do not auto-record very short approval, confirmation, interruption, or follow-up prompts such as `yes`, `no`, `ok`, `continue`, `I stopped it halfway`, or similarly short action nudges.
- Do not auto-record non-mutating user prompts that only ask questions, request analysis, or request investigation without causing repo file changes.
- For those excluded prompt types, the assistant must answer normally and end with a short hint that the prompt can be recorded on request.
- Record every other completed user prompt in `docs/prompt-history.md`, including substantive repo-changing prompts and substantive operational prompts, together with the assistant's final summary.
- If the user replies yes or gives another clearly positive confirmation, append the most recent user-assistant dialog to `docs/prompt-history.md` and create the corresponding git commit as a special exception.
- Maintain full two-way dialog continuity for recorded turns.
- Do not omit completed substantive turns that changed repo files.
- Keep the file appendable, chronologically ordered, and human-readable.
- Record prompt-history entries in English.
- Record prompt-history timestamps as `### YYYY-MM-DD HH:MM UTC`.
- If the original user prompt or assistant summary is not English, translate it to English before recording it in `docs/prompt-history.md`.
- If the original user prompt or assistant summary is already English, record it unchanged.
- Use the relevant `.codex` JSONL files as the primary source when reconstructing past turns.

## Commit and Change Discipline
- Make small, contextual, developer-friendly English commits.
- Use prefixes such as `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- Reflect the real scope of the change.
- Do not batch unrelated changes into one commit.
- Before creating the final commit for a repo-changing prompt, update `CHANGELOG.md` and `release-notes.md` in the same final change set whenever the prompt changed shipped behavior, docs, configuration contract, workflow, or engineering process.
- Treat that changelog/release-notes update as part of the same prompt deliverable, not as a new follow-up change that triggers another recursive documentation pass.
- Before presenting the final summary to the user, create the commit for the completed prompt.
- Use `tools/enable-git-hooks.ps1` and `tools/disable-git-hooks.ps1` for local hook management; do not reintroduce one-way hook installers.

## Required Assistant Workflow
- Explore before mutating.
- Prefer `rg` / `rg --files` for search.
- Use non-interactive git commands.
- Never use destructive git resets or checkouts unless explicitly requested.
- If unexpected third-party edits appear, stop and ask the user how to proceed.
- When a change affects docs, config contract, or command surface, update the corresponding contract files in the same prompt.
