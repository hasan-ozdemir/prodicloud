# Changelog

All notable changes to `clagnos` are documented here. The structure follows a Keep a Changelog style, while the content is curated from the repository commit history and the reconstructed Codex development record.
Documented versions use `YYYY.M.D.N`, where `N` is the cumulative repository commit count at the documented release point.

## [2026.10.14.415] - 2026-10-14

### Fixed
- When the Azure Compute SKU response omits nested-virtualization capability metadata, Clagnos now treats documented unsupported Bv1, Bsv2, Basv2, and Bpsv2 families as known negatives. With nested virtualization enabled, create/update stops during configuration review before resource-group or VM deployment and identifies the SKU/family plus the setting to change.

### Validation
- Added fixture coverage for `Standard_B2s_v2` with an omitted capability row and the other documented unsupported B families. Windows PowerShell 5.1 and PowerShell 7+ each passed 191 smoke checks and 173 TUI scenarios; repository quality checks passed. No live Azure operation was run.

## [2026.10.14.414] - 2026-10-14

### Improved
- Added a hidden, read-only cache worker that refreshes subscription-scoped resource groups, resource rows, and detailed VM state every 60 seconds without blocking the TUI welcome screen. An exclusive per-subscription lock avoids duplicate scans across concurrent TUI instances. It publishes atomic snapshots, honors refresh requests across CLI restarts, refuses snapshots older than five minutes, and backs off failed Azure reads.
- Manage Programs now warms builtin/custom package status asynchronously, reuses complete local/disk snapshots for 45 seconds, and shares VM target/endpoint data from a fresh inventory snapshot. Package install/uninstall reuse the resolved target/runtime, and successful SSH bootstraps are cached for 20 seconds to avoid an extra probe connection.
- Flattened Azure JSON root arrays explicitly in the worker so Windows PowerShell 5.1 publishes usable group, resource, and VM arrays.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ each passed 190 smoke checks and 173 fixture-backed TUI scenarios, including actual `cg.cmd` output, worker snapshot publication, persisted-refresh recovery, package-cache TTL, and SSH bootstrap reuse.
- Repository quality checks passed for PowerShell parsing, documentation, sensitive content, package app-state, release packaging, Python syntax/artifact hygiene, and CLI help. Fixture logs showed no native Azure calls, mutations, or real Clagnos dispatches; no live Azure operations were performed.

## [2026.10.14.413] - 2026-10-14

### Added
- The interactive CLI now builds a subscription-scoped managed resource snapshot at startup, reuses it across inventory/component/VC screens, and reconciles after its 60-second freshness window, explicit refresh, subscription changes, and possible Azure mutations. Snapshot signatures compare group/resource ETags and use resource content when ETags are absent.
- Added a numbered, paged create wizard with visible configured defaults, `p/n/g/f/t` page navigation, `s/k/a/l/c` step controls, and a review step before the shared create workflow.
- Added validated OS disk-size text in `MB`, `GB`, or `TB` and inbound TCP port input with comma-separated ports and ranges such as `3000-3300`. Added numbered task and inventory-group selection, app-state username validation, and additional TUI typed-input checks.

### Validation
- Compatibility checks passed under Windows PowerShell 5.1 and PowerShell 7+: 189 smoke checks and 172 fixture-backed TUI scenarios per runtime. TUI coverage includes the real `cg.cmd` process test, cache command-count checks, change detection, wizard navigation, invalid defaults, invalid-entry retries, and canceled report-path input.
- The suite blocked native Azure and the real dispatcher; no Azure resources were created or changed.
- Repository quality checks passed, including documentation, sensitive-content, package app-state, release-package, and Python artifact audits.

## [2026.10.13.412] - 2026-10-13

### Fixed
- Fixed interactive VM inventory and detail screens reporting `Unknown` when Azure CLI returned the documented nested `instanceView.statuses` response. The TUI now reads CLI and direct REST response shapes and normalizes power-state codes when Azure omits `displayStatus`.

### Validation
- Opened the real `cg.cmd` without parameters and confirmed the `vc1` inventory row displayed `VM running` using a read-only Azure request.
- The detail screen uses the same corrected power-state resolver; no VM or related resource was mutated.

## [2026.10.13.411] - 2026-10-13

### Fixed
- Removed Windows/Linux platform flags from interactive `do` actions; the power and status menu now dispatches options accepted by the shared command contract.

### Validation
- TUI coverage passed 160/160, including every lifecycle action and a check that `do` receives no unsupported platform flags.
- PowerShell compatibility and quality checks passed under Windows PowerShell 5.1 and PowerShell 7+.
- A no-argument `cg.cmd` interactive journey resized `vc1` to `Standard_B2s_v2`, read back the new size, and confirmed the VM was running through the menu status action. Disk and network resources were unchanged.

## [2026.10.13.410] - 2026-10-13

### Fixed
- Fixed `cg.cmd` command mode losing forwarded arguments when the interactive frontend dot-sourced the shared runtime; added a real-launcher `help resize` regression check.
- Extended VM size prechecks to honor active-subscription SKU restrictions before resize or other VM changes can begin.

### Validation
- PowerShell compatibility matrix passed under Windows PowerShell 5.1 and PowerShell 7+: 188 smoke checks and 160 TUI scenarios per runtime.
- The launcher and restricted-SKU regression checks used fixture environments; no resource mutations were attempted.

## [2026.10.13.409] - 2026-10-13

### Added
- Added a versioned source release packager that includes a build manifest and SHA256 sidecar and rejects dirty trees, version/count mismatches, and tracked `.env` files.
- Added local task execution history for isolated task/package operations and full init/update stage summaries, including deferred app-state work without guest output or credentials.
- Added a redacted JSON export option to `show`; existing report files require explicit `--overwrite`.

### Changed
- Resize operations now show before/after lifecycle snapshots, read the resulting VM SKU or OS disk size back from Azure, and persist the requested setting only after the readback matches.
- Managed group inventory now displays the active marker, Azure location, and provisioning state.

### Validation
- PowerShell compatibility matrix passed under Windows PowerShell 5.1 and PowerShell 7+: 187 smoke checks and 160 TUI scenarios per runtime.
- The real `cg.cmd` TUI process used fixture Azure reads only: zero native Azure CLI calls, zero real dispatcher calls, and no resource mutations.
- Quality audit passed, including documentation, package app-state, release package, sensitive-content, syntax, and CLI help checks.

## [2026.10.13.408] - 2026-10-13

### Added
- Added Windows-only `connect --powershell` with an interactive persistent PSSession prompt, one-shot `--command`, and authenticated `--test` modes; exposed these paths in the selected VC Operations menu and VC connection details.
- Added direct command examples to the workflow summary and CLI help. The connection flow uses WinRM Negotiate on TCP 5985 and keeps credentials inside a PSCredential object.

### Changed
- Extended the existing enabled Windows init task `06-configure-powershell-remoting` to grant both manager and assistant accounts access through Remote Management Users. WinRM Basic authentication and unencrypted transport remain disabled.
- Expanded non-live command and TUI coverage for PowerShell connect selection, command execution, session testing, Linux rejection, and actual `cg.cmd` screen output.

### Validation
- PowerShell compatibility matrix passed: 179 smoke checks and 158 TUI scenarios under Windows PowerShell 5.1 and PowerShell 7+.
- TUI tests used fixture Azure reads only: zero native Azure CLI calls, zero real dispatcher calls, and no Azure mutations.

## [2026.10.13.407] - 2026-10-13

### Changed
- Added a process-level TUI acceptance scenario that launches the actual `cg.cmd` and Clagnos UI/runtime source in a temporary sandbox, scripts stdin choices, and checks captured console output.
- Added a fixture Azure CLI and launcher elevation shim. The fixture returns read-only subscription/VM/resource data and rejects Azure mutation verbs; the process test uses a sanitized temporary `.env` and never reads the operator's credentials.

### Validation
- TUI suite passed 154/154 scenarios in Windows PowerShell 5.1 and PowerShell 7+.
- The real-launcher scenario verified main navigation, selected VC details/credentials, package catalog, components, operations, inventory, and subscriptions. It reported zero native Azure CLI calls, zero real dispatcher calls, and no mutation attempts.

## [2026.10.12.406] - 2026-10-12

### Added
- Added a fixture-driven TUI suite under `tests/tui/` that exercises all visible menu screens and action routes, including virtual computers, subscriptions, inventory, package catalogs, components, tasks, VM operations, confirmations, and VC detail rendering.
- Blocked native Azure CLI and the real command dispatcher in the TUI harness; test runs assert zero native Azure calls and zero dispatched backend operations.
- Included TUI tests in the PowerShell compatibility matrix and GitHub quality gate.

### Validation
- TUI suite passed 153/153 scenarios in Windows PowerShell 5.1 and PowerShell 7+.
- Both runs reported zero native Azure CLI calls and zero real dispatcher calls; no Azure resources were mutated.

## [2026.10.12.405] - 2026-10-12

### Added
- Expanded the selected VC detail screen with VM identity, image, disk settings, NIC/VNet/subnet/NSG, public IP and DNS, security and feature settings, tags, and attached-resource details.
- Added SSH and RDP endpoints with the configured manager and assistant usernames/passwords from local `.env`. Passwords are displayed in the interactive detail view and are not included in progress or operation log messages.

## [2026.10.12.404] - 2026-10-12

### Added
- Added visible `Doing: <action>` progress messages and 30-second heartbeats across Azure CLI/REST calls, VM lifecycle waits, guest processes, SSH tasks, and other long-running operations. `exec --quiet` now suppresses remote chatter while keeping local progress visible.
- Added the selected VC's `o: operations` menu with numbered status, start, graceful shutdown, both hibernation paths, resume, restart, immediate power-off, force reset, deallocation, reapply, redeploy, compute/disk resize, VM feature toggles, connection, task, component, move, and report actions.
- Added `do` actions for hibernation-only resume, graceful shutdown, immediate power-off, and force reset. Force power-off and reset require typed confirmation in the interactive menu.
- Added a resumable live VC E2E acceptance script and tracked all eight sanitized builtin package app-state archives.
- Added the JAWS install step that stops `jfw.exe`, copies the archive's `update-files` payload into the JAWS 2025 directory, and verifies each copied file.

### Tests
- Live E2E passed for `vc1`: 8 init tasks, 10 update tasks, 36 enabled packages, hibernation, nested virtualization, full VM/resource summary and redaction, SSH, RDP, and hibernate/resume. The VM was left running.
- PowerShell compatibility passed with 174/174 smoke checks under Windows PowerShell 5.1 and PowerShell 7+.
- Code quality, documentation, sensitive-content, package app-state, and Bash syntax checks passed.

## [2026.10.12.403] - 2026-10-12

### Changed
- Audited every builtin package app-state policy and repository snapshot. Replaced whole-profile, browser-session, cloud-auth, cache, history, workspace, and license/activation state with narrow preference-file policies or no app-state policy where the state is identity-bound.
- Generalized Windows package snapshots for profile paths, host names, IP addresses, system drives, and Visual Studio instance folders; added fail-closed target resolution for `%CLAGNOS_*%` placeholders immediately before replay.
- Added capture-time secret-field stripping and Linux SSH capture/replay portability for home directories, UIDs/GIDs, host names, IP addresses, CPU count, and memory size.
- Added a repeatable builtin package app-state maintenance script and snapshot contract checks for builtin and custom catalogs.

### Tests
- Added package snapshot checks for scoped preference files, generalized paths, secret/session exclusions, and supported placeholders.
- Added Linux placeholder capture/replay round-trip coverage and Windows profile, disk, CPU, and memory placeholder checks.
- Revalidated PowerShell compatibility, code quality, docs, Bash syntax, sensitive-content, and release-document checks. No Azure resources were changed.

## [2026.10.12.402] - 2026-10-12

### Changed
- Replaced the task-backed program catalog with the `package` command and package-specific runtime entities.
- Moved 36 standard Windows installers into `packages/builtin/windows/<package-id>/`, renamed each installer to `install.ps1`, and converted metadata to `package.json`.
- Added physically separate builtin and custom package catalogs for Windows and Linux. Manage Programs now offers a catalog selector and labels rows `[builtin]` or `[custom]`.
- Added package-specific enable/disable, status, install/update, uninstall, and app-state selection. Disabled packages remain visible; install/update is blocked until enabled.
- Kept package installers out of `windows/update` task discovery and moved Store shortcut refresh follow-ups into `package.json` post-install declarations.
- Preserved existing app-state archives without opening or rewriting them by carrying their identity in `appStateKey`.

### Tests
- Validated catalog isolation, same-id packages across catalogs, typed availability changes, disabled-install blocking, package assets, app-state identity, and synchronous post-install tasks.
- Revalidated task/runtime compatibility, documentation, code quality, Bash syntax, and sensitive-content checks under PowerShell 5.1 and PowerShell 7+.

## [2026.10.12.401] - 2026-10-12

### Changed
- Added explicit task-catalog enable/disable actions for init, update, and program tasks through the `task` command and the VM task menu.
- Updated the program catalog to retain disabled entries. The Manage programs list marks them `(disabled)` and exposes enable, disable, uninstall, install/update, and status actions; install/update is blocked until the task is enabled.
- Labeled every Manage programs entry with its lifecycle type (`initial` or `add-on`) and execution target (`local` or `remote`); local-only task-catalog entries receive a separate `[local catalog]` marker.
- Added typed confirmation and verification for catalog changes. Disabling moves the task folder under its matching disabled root; enabling restores it and sets `task.json` `enabled=true` while preserving other metadata.
- Clarified that availability changes affect future runs across VMs using the shared repository and do not change an already-running VM.

### Tests
- Revalidated the 168-check Clagnos smoke suite under Windows PowerShell 5.1 and PowerShell 7+.
- Revalidated code quality, documentation contracts, Bash syntax, and sensitive-content checks.
- Added temporary-catalog coverage for disable, enable, explicit manifest re-enable, metadata preservation, and rejected confirmation.

## [2026.10.12.400] - 2026-10-12

### Changed
- Added the `Cloud subscriptions` menu. It refreshes all Azure CLI subscription rows, marks the Clagnos selection and CLI active default, and numeric selection updates both `az account set` and `.env` `SELECTED_AZURE_SUBSCRIPTION_ID`.
- Completed interactive access to read-only resource inventory, component details, disabled task inventory, and numeric lifecycle/resize/feature actions; region changes use the shared Azure region picker.
- Corrected command help so `create`, `initialize`, and `update` accurately describe their separate infrastructure, bootstrap, and maintenance stages.

### Operational Result
- Audited accessible enabled subscriptions for legacy `managed-by=az-vm` resource groups. No eligible groups were found, so no Azure resource-group tags were changed.
- Aligned the Azure CLI active default with the Clagnos-selected subscription. No Azure resource mutations were performed.

### Tests
- Revalidated the 167-check Clagnos smoke suite under Windows PowerShell 5.1 and PowerShell 7+.
- Revalidated code quality, documentation contracts, Bash syntax, and sensitive-content checks.

## [2026.10.12.399] - 2026-10-12

### Changed
- Renamed the public application, runtime modules, launch surface, repository paths, docs, and tests from az-vm to Clagnos; `cg.cmd` now opens the interactive PowerShell CLI and continues to forward direct commands.
- Added the numbered and lettered virtual-computer menus for subscription selection, create/list/show, initialization, maintenance, programs, components, VM lifecycle, connections, tasks, app-state, reports, and deletion.
- Split fresh infrastructure creation, existing-VM initialization, and non-program maintenance into distinct `create`, `initialize`, and `update` flows.
- Added validated task-catalog program status/install/uninstall operations and Azure component CRUD for resource groups, VMs, disks, VNets, subnets, NICs, public IPs, NSGs, and NSG rules, including dependency-reviewed deletion.
- Kept existing `managed-by=az-vm` resource groups discoverable and added an explicit first-inventory migration to the new `managed-by=clagnos` tag.

### Tests
- Revalidated the 167-check Clagnos smoke suite under Windows PowerShell 5.1 and PowerShell 7+.
- Revalidated the documentation contract, PowerShell parsing and quality checks, Bash syntax checks through Git Bash, and sensitive-content audit.
- No live Azure operations were run for this change.

## [2026.3.23.397] - 2026-03-23

### Changed
- Documented the completed zero-warning live Windows publish cycle for the current managed profile. The maintained release record now reflects that the final fresh `create`, isolated `10005-copy-user-settings` rerun, natural-order `update`, `show`, `do --vm-action=status`, `connect --ssh --test`, and `connect --rdp --test` all completed successfully on the final managed VM.
- Recorded the full production publish loop and fix-and-recreate sequence in `docs/prompt-history.md`, including the final state where no live warning or error remained.

### Tests
- Revalidated the final live acceptance evidence at the documentation layer: the final fresh `create --auto --windows --perf` completed with `warning=0`, the isolated live `task --run-vm-update 10005` rerun completed with `warning=0`, and the final natural-order `update --auto --windows --perf` completed with `warning=0`, `signal-warning=0`, and `error=0`.
- Revalidated the final operational checks on the published VM: `show` kept `VM_ADMIN_PASS` and `VM_ASSISTANT_PASS` redacted, `do --vm-action=status` reported `VM running` with `hibernation-enabled = true`, `connect --ssh --test` passed for `manager`, and `connect --rdp --test` passed for `assistant`.

## [2026.3.22.395] - 2026-03-22

### Fixed
- Fixed the next live acceptance blocker in the shared task restart helper. After the refreshed create loop succeeded, a natural-order `update --auto --windows --perf` rerun reached `136-configure-language-settings`, requested a reboot correctly, and then failed because the Azure CLI `az vm restart` call hit the default 300-second timeout before Azure finished the restart operation.
- Hardened `Invoke-ClagnosRestartAndWait` so task-triggered Azure restarts now run under an explicit extended Azure CLI timeout budget. The helper keeps the existing post-restart power-state, provisioning, and SSH recovery checks unchanged, but no longer aborts early on slower guest restarts triggered by heavy Windows configuration tasks.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 166, Failed: 0` after adding a shared contract check that task-triggered Azure restarts run through `Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds 900`.
- Revalidated `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the task-restart timeout hardening.

## [2026.3.22.394] - 2026-03-22

### Fixed
- Fixed the next live zero-warning blocker in `10003-create-public-desktop-shortcuts`. A natural-order `update --auto --windows --perf` rerun on the freshly created VM stopped when `C:\Users\Public\Desktop\s7TikTok Business.lnk` was temporarily locked by another process during managed Public Desktop cleanup.
- Hardened Public Desktop cleanup with a bounded locked-file retry path and an already-normalized keep path. Managed shortcuts that are briefly locked but already match the current spec are now retained without inflating warnings, while truly stale managed shortcuts still fail deterministically after the retry budget is exhausted.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 165, Failed: 0` after extending the Public Desktop shortcut contract to cover locked-shortcut retry/retain behavior.
- Revalidated `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the Public Desktop cleanup hardening.

## [2026.3.22.393] - 2026-03-22

### Fixed
- Fixed the next zero-warning full-create blocker in the Windows npm CLI tasks. Even with `--loglevel error`, fresh `vm-update` runs could still surface `npm notice` lines from `124-install-openai-codex-tool` as transcript warnings under one-shot SSH execution.
- Hardened `124-install-openai-codex-tool`, `125-install-github-copilot-tool`, and `126-install-google-gemini-tool` so each task now captures merged npm output with a temporary local `ErrorActionPreference='Continue'` guard, filters only the known benign `npm notice` and `npm warn deprecated` chatter before replay, and still fails strictly from the real npm exit code.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 165, Failed: 0` after extending the npm task contract to cover the local merged-output capture/filter path.
- Revalidated `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the npm task warning-suppression hardening.

## [2026.3.22.392] - 2026-03-22

### Fixed
- Fixed the remaining full-create `121-install-wsl-feature` warning path by hardening `Test-WslReady`. The readiness probe now captures `wsl.exe --version` output with a local `ErrorActionPreference='Continue'` guard, filters the known benign bootstrap lines before they reach the transcript, and returns readiness strictly from the native exit code.
- This closes the next live zero-warning blocker found immediately after the previous WSL transcript fix: the latest fresh `create --auto --windows --perf` rerun still stopped at `121-install-wsl-feature` because the readiness probe emitted plain `WARNING: The Windows Subsystem for Linux is not installed...` lines before the winget bootstrap.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 165, Failed: 0` after extending the WSL task contract to cover the quiet readiness-probe path.
- Revalidated `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the `Test-WslReady` warning-suppression change.
- Revalidated live in isolation on the active managed Windows VM with `task --run-vm-update 121 --windows --perf`; `121-install-wsl-feature` completed with `success=1`, `warning=0`, `signal-warning=0`, `error=0`, and `reboot=1`.

## [2026.3.22.391] - 2026-03-22

### Fixed
- Hardened `121-install-wsl-feature` so first-run `wsl.exe --install --no-distribution` stderr no longer aborts the task as a PowerShell `NativeCommandError` record. The task now captures native output with `ErrorActionPreference='Continue'`, restores the prior preference immediately afterward, and still honors the real command exit code plus the existing local bootstrap-line filter.
- Extended the shared SSH task-output noise filter to suppress the split-line WSL bootstrap transcript shape observed during the latest live create rerun, including the `wsl.exe : ...`, call-site, and `FullyQualifiedErrorId : NativeCommandError` metadata lines that were inflating `vm-update` warnings even though WSL installation was progressing normally.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 165, Failed: 0` after adding coverage for the split WSL bootstrap lines and the temporary `ErrorActionPreference` downgrade inside `121-install-wsl-feature`.
- Revalidated live in isolation on the active managed Windows VM with `task --run-vm-update 121 --windows --perf`; `121-install-wsl-feature` completed with `success=1`, `warning=0`, `signal-warning=0`, `error=0`, and `reboot=1`.

## [2026.3.22.390] - 2026-03-22

### Fixed
- Hardened Windows one-shot SSH task execution so task asset copies now run inside the task retry loop instead of outside it. A transient SSH failure during pre-task asset upload no longer aborts the entire `vm-update` stage before the task retry policy can engage.
- Added one bounded one-shot SSH recovery path before retrying a failed task attempt: the runner now rechecks VM provisioning health, waits for TCP reachability on the SSH port, and reboots the pyssh connection bootstrap before retrying after transient banner or transport drops.
- This specifically fixes the live `create --auto --windows --perf` failure seen at `114-install-teams-application`, where copying `clagnos-store-install-state.psm1` failed with `paramiko.ssh_exception.SSHException: Error reading SSH protocol banner` and aborted the run even though the VM itself remained healthy.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 165, Failed: 0` after adding coverage for one-shot SSH asset copy retry-and-recovery behavior.
- Revalidated `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the SSH runner recovery change.

## [2026.3.22.389] - 2026-03-22

### Fixed
- Suppressed benign WSL bootstrap warnings in `121-install-wsl-feature` by capturing merged native output, filtering the known first-run `wsl.exe` bootstrap lines before they are relayed back into the task stream, and keeping real failures unchanged.
- Suppressed benign npm chatter in the global CLI install tasks by running `npm install -g` with `--loglevel error` for `124-install-openai-codex-tool`, `125-install-github-copilot-tool`, and `126-install-google-gemini-tool`, so live `vm-update` runs stop surfacing `npm notice` and `npm warn deprecated` lines as stage warnings.
- Extended the SSH task-output noise filter so stderr-prefixed relayed lines are normalized before pattern matching and the known benign WSL/npm warning lines are discarded consistently during remote task execution.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0` after adding coverage for stderr-prefixed WSL bootstrap warnings, benign npm warning suppression, the merged-output WSL task path, and the new npm `--loglevel error` contract.
- Re-ran isolated live `vm-update` task checks against the active managed VM for `121-install-wsl-feature`, `124-install-openai-codex-tool`, `125-install-github-copilot-tool`, `126-install-google-gemini-tool`, and `10005-copy-user-settings`; each completed with `warning=0`, `signal-warning=0`, and `error=0`.

## [2026.3.22.388] - 2026-03-22

### Fixed
- Fixed the last live `10005-copy-user-settings` warning by excluding the non-portable `UsrClass` AppModel repository branch during assistant/default classes-hive mirroring. The task no longer tries to recreate protected `Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\...` keys inside the mounted target hive, so the live run stops surfacing `New-Item` access-denied warnings from that branch.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Revalidated `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the classes-hive exclusion fix.

## [2026.3.22.387] - 2026-03-22

### Fixed
- Fixed the remaining assistant-hive regression in `10005-copy-user-settings`: the post-copy cleanup path inside `Invoke-RobocopyBranch` now also uses the dedicated target-prune exclusion set instead of falling back to the broader source exclusion list. This closes the last path that could still delete `C:\Users\assistant\NTUSER.DAT*` and `UsrClass.dat*` during live profile mirroring.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Extended smoke coverage so the copy-user-settings script asserts the `Remove-StaleExcludedTargetPaths` call itself uses `TargetPruneExcludedDirectories` and `TargetPruneExcludedFiles`.

## [2026.3.22.386] - 2026-03-22

### Fixed
- Fixed the Windows SCP host-key fallback path so expected host-key discovery failures now resolve through a non-throwing helper before switching to `pyssh`. This removes the repeated `PS>TerminatingError()` transcript noise that still leaked through the first live rerun even though the copy itself succeeded.
- Fixed Windows task-output noise matching for the Chocolatey bootstrap shell warnings by accepting the real split-line forms emitted during first-run install. This prevents `01-install-choco-tool` from contributing `signal-warning` counts in otherwise healthy `vm-update` runs.
- Fixed `10005-copy-user-settings` so the portable-profile mirror no longer prunes target-owned `NTUSER.DAT*` and `UsrClass.dat*` files. Source copy exclusions stay intact, but the assistant and default target hives are now preserved for the later registry-mirror and vm-summary checks.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Extended smoke coverage so the Windows SCP helper exposes a non-throwing host-key resolution path and the copy-user-settings profile mirror asserts a dedicated target-prune exclusion set that preserves target-owned hives.

## [2026.3.22.385] - 2026-03-22

### Fixed
- Fixed Windows SSH task warning classification so known package-manager, WSL, Docker, and SCP host-key fallback noise is normalized or suppressed before live relay, warning-signal counting, and transcript readback. This keeps benign task chatter out of the `vm-update` warning summary while preserving real failures.
- Fixed the Windows assistant-profile copy flow so `10005-copy-user-settings` no longer treats a partial profile directory as materialized. The task now waits for `NTUSER.DAT` readiness and fails clearly if the assistant hive never appears.
- Fixed the Windows Ollama and language task readiness model for fresh-create runs. `135-install-ollama-tool` now treats process, port, and API health as the decisive runtime gates and records deferred `ollama ls` detail without warninging on cold starts, while `136-configure-language-settings` now accepts deferred capability verification when installs are queued for completion after the next restart or sign-in.
- Fixed the Windows vm-summary Ollama readback so healthy managed startup shortcuts extend the API wait budget and trigger one more `ollama ls` probe after the API becomes reachable, reducing immediate post-reboot false negatives.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Revalidated `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally after the live-warning fix set.
- Extended smoke coverage so the SSH relay/readback filters, Windows SCP fallback behavior, assistant profile hive readiness, deferred language verification, and Ollama cold-start readiness/readback contracts are asserted explicitly.

## [2026.3.22.384] - 2026-03-22

### Fixed
- Fixed the Windows Azure Run Command payload wrapper so generated guest-task scripts no longer risk malformed inline Base64 assignment when the task body contains quote-heavy content. The wrapper now writes the decoded task payload to a temporary `.payload.ps1`, passes that path into the nested hidden `powershell.exe`, and relays merged task output through stdout before the explicit `CLAGNOS_NESTED_RESULT:success|error` marker is emitted.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Revalidated `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed locally before branch alignment and publish.
- Extended smoke coverage so the generated Windows run-command wrapper is asserted from `New-ClagnosRunCommandTaskWrapperScript`, including the `.payload.ps1` handoff and the removal of the earlier uninterpolated Base64 assignment fragment.

## [2026.3.22.383] - 2026-03-22

### Fixed
- Fixed the Windows Azure Run Command timeout wrapper follow-up so successful guest tasks are no longer misclassified as `task-result` warnings when the nested hidden `powershell.exe` process finishes cleanly. The nested child script now emits explicit `CLAGNOS_NESTED_RESULT:success|error` markers, and the outer wrapper now classifies success from that structured marker instead of trusting the raw child exit code alone.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Added smoke coverage that proves the Windows run-command wrapper now carries the explicit nested result markers and the missing-marker failure text used by the live false-negative fix.

## [2026.3.22.382] - 2026-03-22

### Fixed
- Fixed the Windows Azure Run Command task wrapper so the guest-side task timeout now applies to the actual PowerShell task process instead of only extending the outer Azure CLI deadline. Windows isolated task execution now writes the decoded task body to a temporary `.ps1`, starts a nested hidden `powershell.exe`, captures stdout/stderr, forces termination when the task exceeds its manifest timeout, and returns the guest failure text cleanly instead of hanging the entire init/update stage.
- Reduced the Windows `07-configure-all-users` interactive profile-materialization wait budget from 180 seconds to a task-configured 20 seconds so the task respects its 120-second manifest timeout during fresh-create runs and stops blocking later init tasks behind the Azure Run Command single-flight lock.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Extended smoke coverage so the Windows run-command wrapper contract now proves the nested process timeout enforcement fragments are present and the `configure-all-users` task contract now proves the shorter interactive materialization budget is wired through task config.

## [2026.3.22.381] - 2026-03-22

### Fixed
- Fixed the create/update precheck so known-unsupported VM feature combinations now fail before Azure mutation instead of after `az vm create` has already produced a managed VM. `Assert-ClagnosFeaturePreconditions` now checks the selected region, VM size, security type, `VM_ENABLE_HIBERNATION`, and `VM_ENABLE_NESTED_VIRTUALIZATION` combination during Step 1 and blocks Azure-known unsupported hibernation or nested-virtualization requests up front.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 164, Failed: 0`.
- Added smoke coverage that proves unsupported hibernation now stops precheck before Azure mutation, that Trusted Launch plus nested virtualization fails fast during precheck, and that `Invoke-ClagnosPrecheckStep` now invokes feature compatibility validation after the existing image/SKU/disk/security checks.

## [2026.3.22.378] - 2026-03-22

### Changed
- Changed the Windows `135-install-ollama-tool` update task to prefer a clean Chocolatey-based install and bounded runtime validation: it now uninstalls stale winget/choco footprints when a reinstall is needed, runs `choco install ollama -y --no-progress --ignore-detected-reboot`, bootstraps Ollama through `cmd.exe /c start "" "<ollama.exe>" ls`, and falls back to a detached `Start-Process "<ollama.exe>" serve` path only when the headless `ls` bootstrap does not leave a durable process and API listener.
- Narrowed the Windows Ollama task-local app-state contract to config files only, so future managed app-state exports no longer replay low-value runtime payloads such as local databases, WAL files, PID markers, updater trees, or embedded WebView caches.
- Changed the Windows vm-summary readback so the Ollama health block performs a quiet bounded `ollama ls` probe plus a short API wait before it reports process, port, and API readiness, which prevents the earlier cold-start false negative that the March 20 logs still showed immediately after reboot.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 161, Failed: 0`.
- Revalidated `tests\sensitive-content-check.ps1`, `tests\documentation-contract-check.ps1`, and `tools\scripts\app-state-audit.ps1`; all passed locally after the Ollama install, summary, and app-state contract changes.
- Revalidated a live clean-uninstall cycle on the active managed Windows target via `exec`; the final cleanup confirmed `wingetExit=0`, `chocoExit=0`, `ollamaExeExists=False`, `processCount=0`, and `port11434=False`.
- Revalidated live isolated `task --run-vm-update 135 --windows --perf`; `135-install-ollama-tool` completed with `success=1`, `warning=0`, `signal-warning=0`, `error=0`, and reported `ollama-ls-ready`, `ollama-process-ready`, `ollama-port-ready`, and `ollama-api-ready` after the clean Chocolatey install.
- Revalidated the post-install startup path live with isolated `task --run-vm-update 10002 --windows --perf`, an explicit VM restart, and `update --step vm-summary --windows --perf`; the final transcript `clagnos-log-22mar26-111959.txt` now records `ollama-ls-probe => success=True`, `ollama-process-count => 2`, `ollama-port-11434-open => True`, and `ollama-api-probe => success=True; timed-out=False`.

## [2026.3.22.377] - 2026-03-22

### Changed
- Added the Windows `07-configure-all-users` init task immediately after local-account provisioning so existing managed local users are materialized before later init and update work depends on per-user profile files or registry hives.
- Shifted the tracked Windows init priorities so `07-configure-all-users` runs before the existing RDP, OpenSSH, firewall, and PowerShell remoting configuration tasks without renaming the established task folders.

### Fixed
- Fixed the Windows temporary-profile repair path so a user stuck on a live `C:\Users\TEMP` mapping is repaired in place by exporting the loaded user hives, copying the stable registry values back to the live SID registration, and tolerating locked transaction-log artifacts as explicit info-only skips instead of failing the task.
- Fixed the assistant-side JAWS replay prerequisite on the managed Windows flow: the new init task now seeds `C:\Users\assistant\NTUSER.DAT`, repairs the active `ProfileList` mapping back to `C:\Users\assistant`, and removes the earlier `assistant => no-hive-file` registry replay skip that the March 20 live logs recorded for `133-install-jaws-application`.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 161, Failed: 0`.
- Revalidated live isolated `task --run-vm-init 07 --windows --perf` on the active managed Windows target; it completed with `success=1`, `warning=0`, `error=0`, and reported `assistant => C:\Users\assistant` plus `manager => C:\Users\manager`.
- Revalidated the repaired assistant profile state live over SSH and confirmed the active SID mapping now resolves to `C:\Users\assistant`, `State=0`, `RefCount=0`, `.bak` is absent, and `C:\Users\assistant\NTUSER.DAT` exists.
- Revalidated live isolated `task --run-vm-update 133 --windows --perf` on the active managed Windows target; `133-install-jaws-application` completed successfully and its app-state replay finished with `profiles=2`, `user-registry=2`, `skipped=0`, and no assistant hive warning.

## [2026.3.20.376] - 2026-03-20

### Fixed
- Fixed the Windows `06-configure-powershell-remoting` init task so idempotent reruns no longer degrade into a false vm-init warning when the managed admin account is already a member of `Remote Management Users`; the task now verifies membership first and uses a quiet bounded fallback path when the legacy `net localgroup` route is required.
- Fixed managed public DNS label resolution for existing managed public IPs so full `update` runs preserve the current DNS label instead of inventing a new `vm{id}` suffix on every maintenance pass.
- Fixed the Windows `136-configure-language-settings` post-worker verification so a language that is already installed no longer fails just because optional image-managed capability packages still report non-satisfied states.
- Fixed the Windows `10003-create-public-desktop-shortcuts` verification path so Unicode shortcut labels that normalize to an existing written `.lnk` file are reconciled and accepted instead of raising a false missing-shortcut warning.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 160, Failed: 0`.
- Revalidated live isolated `task --run-vm-init 06` on the active managed Windows target; it completed with `warning=0`, `error=0`, and confirmed WinRM listener readiness.
- Revalidated a full live `update --auto --windows --perf` acceptance run after the fixes and confirmed `VM init stage summary: success=6, failed=0, warning=0, error=0, reboot=0` plus `VM update stage summary: success=45, failed=0, warning=0, signal-warning=0, error=0, reboot=2, final-restart=1`.
- Revalidated `show`, `do --vm-action=status`, `connect --ssh --test`, `connect --rdp --test`, and a real WinRM `Invoke-Command`; all succeeded against the active managed Windows target after the final acceptance run.

## [2026.3.19.375] - 2026-03-19

### Changed
- Changed the Windows app-state replay contract so optional locked, in-use, access-denied, missing-parent, and unavailable-hive surfaces are now treated as info-only skips instead of warning-producing failures, with skip-aware verification and rollback behavior.
- Changed the default Windows TCP port contract and summary rendering so managed Windows flows now include WinRM over `5985` and print ready-to-run PowerShell remoting commands beside the existing SSH and RDP commands.
- Changed the Windows advanced-settings contract so UAC notifications are silenced through a Store-safe policy model instead of disabling `EnableLUA`, which preserves Microsoft Store and AppX compatibility.

### Fixed
- Fixed stale task-local app-state replay drift across the warning-producing Windows update tasks by refreshing capture precedence, removing stale fetched zips before live saves, and normalizing the maintained plugin manifests for OneDrive, AnyDesk, Teams, WhatsApp, Google Drive, and JAWS to the current portable replay model.
- Fixed the Windows `10004-configure-windows-experience` and Windows summary readback paths so optional mounted-hive and missing-assistant-hive cases now degrade to explicit info output instead of false warning noise.
- Fixed the Windows `10002-configure-startup-settings` registry-unload cleanup path so isolated and full runs no longer emit the stray `The parameter is incorrect` warning while processing mounted profile hives.
- Fixed the Windows `10003-create-public-desktop-shortcuts` Store AppID repair path with a bounded retry so the assistant-side Teams registration no longer causes a signal-warning during a full natural-order `vm-update` run.
- Fixed the Windows init catalog by adding `06-configure-powershell-remoting`, which enables WinRM over HTTP `5985`, keeps local-account remoting usable for `manager`, and verifies listener and service readiness inside `vm-init`.
- Fixed the Windows Docker Desktop, Ollama, and language-maintenance follow-up paths so Docker no longer fails only because the interactive process is not yet visible, Ollama version probes use a more reliable TCP-gated HTTP read path, and the language task accepts queued background install state sooner after a shorter bounded wait.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 160, Failed: 0`.
- Revalidated `tests\powershell-compatibility-check.ps1`, `tests\code-quality-check.ps1`, and `tests\documentation-contract-check.ps1`; all passed locally after the replay, WinRM, and UAC contract changes.
- Revalidated live isolated runs for `vm-init` tasks `05` and `06`, plus `vm-update` tasks `10001`, `10002`, `10003`, `10004`, `104`, `109`, `114`, `119`, `129`, and `133`; each completed with `warning=0`, `signal-warning=0`, and `error=0`.
- Revalidated a full live `update --auto --windows --perf --step-from=vm-update --step-to=vm-summary` run on the active managed Windows target and confirmed `VM update stage summary: success=45, failed=0, warning=0, signal-warning=0, error=0, reboot=2, final-restart=1`, with WinRM remoting verified afterward through a successful `Invoke-Command`.

## [2026.3.19.374] - 2026-03-19

### Fixed
- Fixed the Windows SSH asset-copy path for fresh managed Windows VMs whose OpenSSH host-key scan cannot negotiate the newest server-first KEX set with the local `ssh-keyscan.exe` build. The Windows asset transport now keeps `pscp.exe` plus trusted host-key discovery as the primary path, but falls back to the existing pyssh copy/fetch transport for Windows paths when host-key fingerprint discovery cannot be resolved locally.
- Fixed the Windows asset-copy cleanup path so fallback executions no longer attempt to delete an empty SCP password-file path after a pyssh-only transfer.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite still passed with `Passed: 157, Failed: 0`.
- Revalidated `tests\code-quality-check.ps1`; the maintained Windows static audit still passed locally.
- Revalidated a live isolated `task --run-vm-update 01` against the active managed Windows target and confirmed the Windows asset-copy path falls back cleanly to pyssh, after which the task completed successfully.

## [2026.3.19.373] - 2026-03-19

### Fixed
- Fixed the Windows startup-profile JSON decode path so PowerShell 5.1 now enumerates approved startup-profile arrays the same way as PowerShell 7+ in `10002-configure-startup-settings`, the Windows summary readback, and the maintained smoke coverage.
- Fixed the maintained non-live quality gate on `main` by aligning the startup-profile smoke assertions with the shared PowerShell 5.1-safe JSON-array handling instead of relying on host-version-specific `ConvertFrom-Json` behavior.
- Fixed the tracked release/documentation surface so the sensitive-content audit no longer trips on concrete managed-target identifiers in release notes, changelog entries, or prompt-history summaries.

### Tests
- Revalidated `tests\sensitive-content-check.ps1`; the tracked sensitive-content audit now passes again.
- Revalidated `tests\clagnos-smoke-tests.ps1` in Windows PowerShell 5.1; the maintained smoke suite passed with `Passed: 157, Failed: 0`.
- Revalidated `tests\powershell-compatibility-check.ps1`; the compatibility matrix now passes on both Windows PowerShell 5.1 and PowerShell 7+.
- Revalidated `tests\code-quality-check.ps1`; the full Windows static audit now passes locally.

## [2026.3.19.372] - 2026-03-19

### Changed
- Changed the Windows `10002-configure-startup-settings` task so its managed auto-start contract is now driven by a task-local startup profile inside `app-state/app-state.zip` instead of a hardcoded app list inside the task script.
- Changed the Windows startup runtime so task metadata now carries task extensions through catalog discovery and materialization, which lets isolated task runs inject task-specific startup-profile payloads cleanly.
- Changed the Windows auto-start application model so `manager` keeps native current-user `Run` entries where practical, while `assistant` now uses a portable current-user Startup folder path for the same managed current-user apps to avoid profile-hive drift and keep the artifacts durable across reboots.

### Fixed
- Fixed the Windows `10002` task so it now seeds and materializes the `assistant` profile hive when needed, applies the approved managed startup set to both `manager` and `assistant`, and keeps missing-target handling as info-only instead of warning or failure.
- Fixed the Windows task materialization path so startup-profile tasks can generate and deploy their own task-local plugin zip through `task --save-app-state --source=lm`, with the correct `extensions/startup-profile.json` payload and manifest.
- Fixed the Windows startup write path so mounted profile hives no longer degrade isolated `10002` runs into false warning exits; assistant-side current-user artifacts are now written through the profile filesystem path when registry-backed persistence is not the right portable surface.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passed with `Passed: 157, Failed: 0`.
- Revalidated `task --save-app-state --source=lm --user=.current. --vm-update-task=10002 --windows` and confirmed the generated task-local plugin zip includes the startup-profile payload.
- Revalidated `task --run-vm-update 10002` live in isolation on the active managed Windows target; the final rerun completed with `warning=0`, `signal-warning=0`, and `error=0`.
- Revalidated the managed Windows VM after an explicit restart and confirmed the machine startup entries, the `manager` startup artifacts, and the `assistant` startup artifacts all persisted; post-reboot process evidence remained partial for some apps and is reported as informational follow-up rather than task failure.

## [2026.3.19.371] - 2026-03-19

### Changed
- Changed the tracked Windows init and update task manifests so the current timeout budgets and the Ollama task priority match the operator-approved live-tuned values.
- Changed the `exec` command surface so one-shot SSH execution can now read the remote command body from a local script file through `--file` / `-f`, with help and README examples aligned to the new contract.
- Changed the Windows language and user-settings maintenance tasks so the language worker can recover already-satisfied queued states faster and the user-settings copy path skips more non-portable profile content instead of spending time inside avoidable lag loops.

### Fixed
- Fixed the `exec` parser and runtime contract drift by wiring `--file` through the runtime manifest, option contract, help surface, and one-shot remote command wrapper.
- Fixed the Windows Docker Desktop recovery flow so the task now repairs stale uninstall registration, tolerates `net start` gaps such as `vmcompute` on guest images where native `Start-Service` already succeeded, and keeps the daemon bring-up contract aligned with the live-tested path.
- Fixed the Windows `10005-copy-user-settings` flow so ACL-protected, reparse-point, packaged-app, and other non-portable profile artifacts are skipped explicitly instead of degrading the run into long avoidable waits.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1` after the selective manifest, exec, Docker, language, and copy-settings commits; the suite passed with `Passed: 156, Failed: 0`.
- Added smoke coverage for `exec --file`, the current Windows timeout contract, the Docker stale-registration repair path, and the language/copy-settings refinements that were already validated live in isolation.

## [2026.3.19.364] - 2026-03-19

### Changed
- Changed the Windows Public Desktop social and business-web shortcut contract so `10003-create-public-desktop-shortcuts` can read optional local `.env` override URLs for the managed `s1-s18` web shortcut set instead of relying only on tracked generic fallback URLs.
- Changed the runtime context, task materialization, and interactive `configure` surface so the new Windows shortcut URL override keys are carried consistently from `.env` into isolated task runs and normal create/update flows.

### Fixed
- Fixed the Windows Public Desktop shortcut flow so missing social override values now fall back cleanly to generic non-broken URLs instead of depending on account-specific tracked code.
- Fixed the `configure` schema drift introduced by the new shortcut override keys by exposing and validating every supported social and business-web URL field in the interactive editor.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1` and confirmed the new `.env` shortcut URL contract, task token materialization, and `10003` shortcut surface pass; the remaining red assertions are the pre-existing unrelated `exec --file` parse contract and the tracked timeout drift for `102-configure-autologon-settings`.
- Revalidated `tests\documentation-contract-check.ps1`.
- Revalidated `task --run-vm-update 10003` live in isolation on the active managed Windows target and confirmed `warning=0`, `signal-warning=0`, and `error=0` after the env-backed shortcut URL changes.

## [2026.3.19.363] - 2026-03-19

### Changed
- Changed the Windows Public Desktop shortcut contract so Turkish managed shortcut labels are now built from PowerShell-safe Unicode code points instead of raw non-ASCII source literals, which keeps Windows PowerShell 5.1 and PowerShell 7+ aligned on the same visible shortcut names.
- Changed the tracked quick-access shortcut label from `q1SourTimes` to `q1EkşiSözlük` while keeping cleanup aliases for the older English and ASCII spellings.
- Changed the shared shortcut launcher helper and the Windows summary readback script to use the same Unicode-safe normalization and ASCII-safe launcher-slug generation for Turkish shortcut names.

### Fixed
- Fixed the Windows Public Desktop shortcut normalization drift where mojibake names such as `r13Ã‡iÃ§ekSepeti Business` could survive cleanup instead of being reconciled back to `r13ÇiçekSepeti Business`.
- Fixed the managed launcher-path generation contract so Turkish shortcut names now resolve to stable ASCII-safe launcher filenames like `q1eksisozluk.cmd` without losing the visible UTF-8 desktop label.
- Fixed the Windows summary readback inventory so the shipped Public Desktop validation surface now tracks the corrected `q1EkşiSözlük`, `r13ÇiçekSepeti Business`, and `r14ÇiçekSepeti Personal` names consistently.

### Tests
- Revalidated `tests\code-quality-check.ps1`.
- Revalidated `tests\clagnos-smoke-tests.ps1`; the Turkish shortcut changes passed and only the pre-existing unrelated `exec --file` parse assertion plus one tracked timeout-contract drift remained red.
- Revalidated `task --run-vm-update 10003` live in isolation and confirmed zero warnings plus corrected `q1EkşiSözlük` and `ÇiçekSepeti` shortcut readback on the managed Windows VM.

## [2026.3.18.362] - 2026-03-18

### Changed
- Changed `Resolve-ClagnosPublicDnsLabel` so an explicitly provided empty managed public IP list is now treated as an explicit test/runtime override instead of falling through to live Azure inventory reads.
- Changed the OpenSSH live-validation changelog note to use generic managed-target wording instead of committing a concrete managed VM name.

### Fixed
- Fixed the remaining GitHub Actions smoke and compatibility failure where the managed public DNS label test still tried to read live Azure inventory in CI when the test intentionally passed an empty managed public IP list.
- Fixed the sensitive-content audit regression caused by recording a concrete managed VM name in the top changelog entry.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\code-quality-check.ps1`.

## [2026.3.18.361] - 2026-03-18

### Changed
- Changed the maintained Windows update task manifests back to the live timeout budgets that the compatibility matrix expects for `110`, `111`, `113`, `115`, `119`, `122`, `123`, `126`, `127`, `128`, `129`, `130`, `132`, and `133`.

### Fixed
- Fixed the remaining `quality-gate` contract drift on `main`, where the tracked Windows update manifests still carried shorter timeouts than the validated live task budgets and caused the smoke and compatibility jobs to fail remotely.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`, `tests\powershell-compatibility-check.ps1`, `tests\code-quality-check.ps1`, and `tests\documentation-contract-check.ps1`.

## [2026.3.18.360] - 2026-03-18

### Changed
- Changed the Windows `03-install-openssh-service` init task to bootstrap OpenSSH Server from the official Win32-OpenSSH MSI instead of waiting on the Windows capability download path during `az vm run-command`.
- Changed the OpenSSH init smoke contract so it now asserts the MSI bootstrap fragments in addition to the existing service-recovery paths.

### Fixed
- Fixed the slow and unreliable Windows `vm-init` OpenSSH bootstrap path that could leave fresh Windows 11 builds stuck for minutes in Azure Run Command while `Add-WindowsCapability` waited on servicing.
- Fixed the `03-install-openssh-service` ready-state log so the task now refreshes and reports the live `sshd` service state after starting it.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`, `tests\powershell-compatibility-check.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the live Windows bootstrap path on the current managed Windows VM with isolated `task --run-vm-init 03`, isolated `task --run-vm-init 04`, and `connect --ssh --test`.

## [2026.3.18.359] - 2026-03-18

### Changed
- Changed the maintained Windows GitHub CLI task back to the tracked 180-second timeout so the compatibility matrix matches the live task contract again.
- Changed the latest prompt-history workflow-fix entry to remove the banned personal token from tracked documentation.

### Fixed
- Fixed the latest failing `quality-gate` run on `main`, which was still failing in the sensitive-content audit and the compatibility matrix because `docs/prompt-history.md` contained a banned token and `107-install-gh-tool` still carried the old 30-second timeout in `HEAD`.

### Tests
- Revalidated `tests\code-quality-check.ps1`; the sensitive-content audit now passes again.
- Revalidated `tests\powershell-compatibility-check.ps1`; the tracked Windows compatibility matrix now sees `107-install-gh-tool` at 180 seconds.

## [2026.3.18.358] - 2026-03-18

### Changed
- Changed partial `create` step windows that start at `vm-init`, `vm-update`, or `vm-summary` so they now lock onto the existing managed VM target instead of generating a fresh `gX` resource group name during step-1 resolution.
- Changed `Invoke-ClagnosMain` so `create` can keep the create banner and action plan while resolving its step-1 context through existing-target semantics when a partial resume window requires it.

### Fixed
- Fixed the live publish resume bug where `create --step-from vm-init` could fail with `ResourceGroupNotFound` by generating a new managed resource group name even though the interrupted create had already provisioned `group`, `network`, and `vm-deploy` successfully.
- Fixed the maintained smoke contract so partial create resume windows now prove they reuse the existing managed resource names and Azure location instead of trying to re-enter fresh-create naming rules.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite now includes a regression test for `create --step-from vm-init` existing-target reuse and passes fully.

## [2026.3.18.357] - 2026-03-18

### Changed
- Changed `106-install-7zip-tool` so its tracked timeout matches the current install-task budget again.
- Changed `121-install-wsl-feature` so `wsl --install --no-distribution` is now followed by an explicit `Test-WslBootstrapSatisfied` readiness check that accepts the feature-enabled state when the live `wsl` probe is still catching up.
- Changed `135-install-ollama-tool` so its installer-process filter is narrowed to the live package manager surfaces and its `ollama --version` readback is normalized through a warning-filtered helper.

### Fixed
- Fixed the Windows PowerShell 5.1 compatibility failure in the maintained smoke matrix by restoring the tracked `106` timeout contract and by making the WSL and Ollama task readbacks resilient enough to pass in both Windows PowerShell 5.1 and PowerShell 7+.
- Fixed the latest failing GitHub Actions `quality-gate` run on `main`, which had been failing in the non-live smoke and compatibility jobs because the committed contracts still lagged behind the intended `106`, `121`, and `135` task behavior.

### Tests
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passes fully.
- Revalidated `tests\powershell-compatibility-check.ps1`; the compatibility matrix now passes on both Windows PowerShell 5.1 and PowerShell 7+.

## [2026.3.18.356] - 2026-03-18

### Changed
- Changed `130-install-azure-cli-tool` so it now repairs an unhealthy existing Azure CLI without `--force`, verifies the uninstall result through Chocolatey package readback, and ensures the resolved Azure CLI command directory is written back into machine PATH even when the task short-circuits on an already-healthy install.
- Changed `134-install-docker-desktop-application` so its bounded winget source recovery now uses `winget source reset` without `--force`.

### Fixed
- Fixed the remaining tracked Windows `vm-update` `--force` drift that was still failing the maintained smoke contract, including the Azure CLI reinstall path and the Docker Desktop winget source repair path.
- Fixed a live Azure CLI path drift where `130-install-azure-cli-tool` could succeed through a direct executable fallback while later fresh `cmd` sessions still failed to resolve `az`.

### Tests
- Revalidated the no-force Windows update contract with `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite now passes fully.
- Revalidated `130-install-azure-cli-tool` live in isolation on the active managed Windows VM by uninstalling Azure CLI to clean state, rerunning `task --run-vm-update 130`, and confirming a fresh `cmd /c az version` succeeds afterward with the task summary at `warning=0`, `signal-warning=0`, and `error=0`.

## [2026.3.18.355] - 2026-03-18

### Changed
- Changed `10003-create-public-desktop-shortcuts` so its classic application target discovery now mirrors the stronger install-task logic for Visual Studio 2022 Community and JAWS. The shortcut task now resolves `devenv.exe` through `vswhere.exe` plus canonical fallback paths and resolves `jfw.exe` through the Freedom Scientific registry roots before falling back to the canonical install paths.

### Fixed
- Fixed a shortcut-contract drift where `10003-create-public-desktop-shortcuts` could lag behind the hardened installers and miss a valid `VS2022` or `JAWS` target even though `132-install-vs2022community-application` or `133-install-jaws-application` had already verified the application successfully.
- Fixed the public desktop shortcut smoke contract so the maintained test suite now pins the new `VS2022` and `JAWS` resolver fragments directly instead of trusting only the older hard-coded path assumptions.

### Tests
- Revalidated the non-live shortcut contract with `tests\clagnos-smoke-tests.ps1`. The `10003` shortcut coverage assertions passed with the new resolvers, while the suite still reports one unrelated pre-existing failure in `130-install-azure-cli-tool.ps1` about `--force`.

## [2026.3.18.354] - 2026-03-18

### Changed
- Changed `132-install-vs2022community-application` so its post-install verification now resolves `devenv.exe` through both canonical install paths and `vswhere.exe`, and can tolerate transient non-standard Chocolatey exits when Visual Studio 2022 Community has already materialized correctly.
- Changed `133-install-jaws-application` so its bounded winget repair and verification path now tolerates known noisy exit codes when the package has actually registered, resolves `jfw.exe` recursively under the installed root, and rechecks package/source health before deciding failure.
- Changed the portable local app-state save path for tracked task-local plugins so current-user profile directories and HKCU registry payloads are captured before later normalization to the managed `manager` profile contract.
- Changed guest app-state replay so a managed user registry import is skipped cleanly when the target profile has no replayable hive surface, instead of scheduling a doomed replay operation that later degrades the task into a signal warning.

### Fixed
- Fixed the remaining isolated warning path in `132-install-vs2022community-application` on the active managed Windows VM where transient Chocolatey feed or exit noise could still leave the task warning even though `devenv.exe` had landed correctly.
- Fixed the remaining isolated warning path in `133-install-jaws-application` by hardening winget source/output handling, accepting the observed `0x80070002`-style noisy exit when the package was actually installed, and treating the real success condition as a launchable `jfw.exe`.
- Fixed the JAWS task-local app-state capture workflow so the rebuilt local snapshot now includes both the Freedom Scientific HKCU state and the managed portable settings payload derived from `AppData\Roaming\Freedom Scientific\JAWS\2025\Settings`.
- Fixed the final JAWS follow-up isolated sweep by preventing no-hive `assistant` registry replay attempts from generating non-actionable app-state signal warnings during the tracked guest app-state replay path.

### Tests
- Revalidated live in isolation on the active managed Windows VM by uninstalling Visual Studio 2022 Community and JAWS, rerunning `task --run-vm-update 132` and `133` clean-state, then rerunning the JAWS follow-up tasks `1001` and `10002`; the final stage summaries reached `warning=0`, `signal-warning=0`, and `error=0`.
- Revalidated the updated non-live contracts in `tests\clagnos-smoke-tests.ps1`, including the new portable capture-plan rewrite and the no-hive guest app-state replay skip. The suite still reports one unrelated pre-existing failure in `130-install-azure-cli-tool.ps1` about `--force`.

## [2026.3.18.353] - 2026-03-18

### Changed
- Changed `134-install-docker-desktop-application` so its WSL2 readiness path now mirrors the working local Desktop pattern more closely: the task brings up `vmcompute`, `hns`, and `wslservice` when present, seeds the managed Docker profile with the accepted Desktop license/settings state, keeps `com.docker.service` in the manual/stopped WSL2-oriented mode, and then explicitly requests `docker desktop start` before the bounded `docker desktop status` / `docker info` probes.

### Fixed
- Fixed the live Windows Docker Desktop regression on the active managed VM where the interactive frontend was visible but the backend stayed in `starting` and `docker info` kept returning HTTP 500 against `dockerDesktopLinuxEngine`. The missing bootstrap step was the Desktop CLI start request after the interactive launch; once added, the task could materialize the `docker-desktop` WSL engine and pass `docker info` again.
- Fixed the last remaining Docker Desktop isolated-task noise by removing the stale tracked task-local app-state plugin zip for `134-install-docker-desktop-application`. The task now relies on its in-script managed profile seeding instead of replaying a lockfile-heavy Desktop payload that produced a non-actionable app-state signal warning on every healthy rerun.

### Tests
- Revalidated the Docker Desktop smoke contract in `tests\clagnos-smoke-tests.ps1`; the Docker-specific assertions passed, while the suite still reports one pre-existing unrelated failure in `130-install-azure-cli-tool.ps1` about `--force`.
- Revalidated live in isolation on the active managed Windows VM by checking `docker desktop status`, `docker info`, and `wsl -l -v`, then rerunning `task --run-vm-update 134 --perf` against that target until the stage summary reached `warning=0`, `signal-warning=0`, `error=0`.

## [2026.3.18.352] - 2026-03-18

### Changed
- Changed the create/update workflow so `vm-init` no longer starts immediately after VM deploy if Azure still reports the VM in provisioning state `Updating`. The pipeline now waits for provisioning recovery and can trigger the existing bounded Azure redeploy repair before the first init task runs.
- Changed the shared provisioning-repair helper so its Azure redeploy action now uses an extended Azure CLI timeout budget instead of inheriting the generic `300` second command timeout.

### Fixed
- Fixed the fresh Windows publish retry path on 2026-03-18 where `03-install-openssh-service` kept timing out on newly created VMs even though the same task passed on a later disposable retry. The key difference was provisioning readiness: the full workflow entered `vm-init` while Azure still reported the VM as `Updating`, whereas the later isolated retry ran only after the guest had stabilized.
- Fixed the downstream repair path so a provisioning recovery redeploy is no longer cut off at `300` seconds while the VM is still converging.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1` and `tests\code-quality-check.ps1`.
- Added smoke coverage that pins both contracts: create waits for provisioning recovery before `vm-init`, and provisioning-repair redeploys use the extended Azure CLI timeout helper.

## [2026.3.18.351] - 2026-03-18

### Changed
- Changed the Windows PowerShell Azure Run Command wrapper so tracked `vm-init` tasks no longer execute inside a nested background job before the guest script runs. The wrapper now writes the decoded task script to a temp file, invokes it directly in the same Run Command PowerShell session, relays the output, and lets the outer Azure CLI timeout override enforce the task budget.
- Changed `03-install-openssh-service` again so its tracked first-install timeout budget now reflects the measured behavior of the active Windows image under the simplified wrapper path.

### Fixed
- Fixed the remaining OpenSSH bootstrap blocker on the 2026-03-18 live publish retry path: nested `Start-Job` execution inside the Windows Run Command wrapper was stretching or destabilizing `Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0`, which kept the capability at `NotPresent` even with the earlier Azure CLI timeout override in place.
- Fixed first-install OpenSSH recovery on the active Windows image by combining the direct PowerShell Run Command execution path with the raised `03-install-openssh-service` task budget; after that change, a disposable live VM could remove the OpenSSH Server capability, rerun `03`, then rerun `04` and pass `connect --ssh --test` successfully.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated live in isolation on the disposable managed Windows VM by explicitly removing `OpenSSH.Server~~~~0.0.1.0`, rerunning `task --run-vm-init 03`, rerunning `task --run-vm-init 04`, and then passing `connect --ssh --test`.

## [2026.3.18.350] - 2026-03-18

### Changed
- Changed the Azure Run Command execution path for `vm-init` so the Azure CLI timeout is no longer capped by the global `AZURE_COMMAND_TIMEOUT_SECONDS` value when a specific init task legitimately needs more time. `modules/tasks/run-command/runner.ps1` now raises the Azure CLI timeout to at least `task-timeout + 120s` for each isolated or workflow-driven Run Command task invocation and restores the previous global timeout immediately afterward.

### Fixed
- Fixed the fresh Windows publish retry path on 2026-03-18 where `03-install-openssh-service` still failed during the second clean `create` attempt even after the OpenSSH guest bootstrap fix, because Azure CLI terminated `az vm run-command invoke` after `300` seconds while the guest task itself was correctly budgeted for `360` seconds.
- Fixed the follow-on Run Command conflict chain in `vm-init`: by keeping the Azure CLI transport alive through the whole guest task budget, `03-install-openssh-service` can now complete naturally instead of leaving `04-configure-sshd-service` and `05-configure-firewall-settings` to collide with an already-running Run Command extension instance.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Added smoke and compatibility coverage for the temporary Azure CLI timeout override that protects long Windows Run Command init tasks.

## [2026.3.18.349] - 2026-03-18

### Changed
- Changed the Windows OpenSSH `vm-init` bootstrap again so `03-install-openssh-service` now has a realistic first-install timeout budget for Azure Run Command and no longer depends on an `install-sshd.ps1` script being present on the guest image before the task can finish the first create.

### Fixed
- Fixed the fresh Windows `create --auto --windows --perf` failure observed on 2026-03-18 where `03-install-openssh-service` timed out during the first OpenSSH capability install, `04-configure-sshd-service` then ran before the `sshd` service registration had settled, and the later SSH transport bootstrap failed because no host key could be resolved on port `444`.
- Fixed both Windows OpenSSH init tasks so they now recover from inbox-capability installs that provide `sshd.exe` and `ssh-keygen.exe` but not `install-sshd.ps1`: `03-install-openssh-service` can register `sshd` directly from the OpenSSH executable when needed and can mark the task as reboot-required when servicing is still pending, while `04-configure-sshd-service` now uses the same direct-recovery path before editing `sshd_config`.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated live in isolation on the active managed Windows VM through `task --run-vm-init 03`, `task --run-vm-init 04`, and `connect --ssh --test` against the fresh managed target, confirming that the repaired init chain leaves `sshd` registered and reachable on port `444`.

## [2026.3.18.348] - 2026-03-18

### Changed
- Changed the active Windows `vm-init` and `vm-update` task catalog to use a consistent `[verb]-[entity]-[target-type]` naming contract instead of the older mixed `-system`, `-app`, `-cli`, and ad hoc suffix set. The tracked Windows catalog now exposes names such as `01-install-choco-tool`, `114-install-teams-application`, `124-install-openai-codex-tool`, `134-install-docker-desktop-application`, and `10003-create-public-desktop-shortcuts`.
- Changed Windows `vm-init` so Chocolatey is no longer a dependency of the OpenSSH bootstrap path. `03-install-openssh-service` now installs the Windows OpenSSH Server capability through capability servicing with an inbox `install-sshd.ps1` fallback, while Chocolatey bootstrap moved to the `vm-update` initial band as `01-install-choco-tool`.
- Changed the old combined Windows npm bootstrap task into three standalone tracked tasks with separate task-local plugin zips and separate app-state manifests: `124-install-openai-codex-tool`, `125-install-github-copilot-tool`, and `126-install-google-gemini-tool`.
- Changed the Windows PATH refresh contract so the tracked init/update surface no longer shells through `refreshenv.cmd`. The repo now ships a shared registry-backed session helper at `modules/core/tasks/clagnos-session-environment.psm1`, and the touched Windows task scripts, store-state helper, and summary readback now use that helper instead of the old `refreshenv` path.
- Changed `121-install-wsl-feature` so it now starts with `wsl --install --no-distribution` before the existing DISM/feature reconciliation, WSL update, and default-version flow.
- Changed `134-install-docker-desktop-application` so it now requires bounded daemon readiness before success: the task detached-starts Docker Desktop, then waits until both `docker desktop status` and `docker info` return healthy instead of warning and continuing while the engine is still cold.
- Changed `136-configure-language-settings` so it now always emits a reboot-required marker on success, logs final capability summaries for `en-US` and `tr-TR`, and short-circuits the long-running Turkish scheduled-task worker when the Windows capability state is already satisfied even if the worker never writes its own result file.

### Fixed
- Fixed the active Windows task manifest, runtime lookup, shortcut, help, test, and task-local plugin surfaces so the renumbered and renamed Windows tasks now resolve through one consistent catalog without stale current-name drift.
- Fixed the tracked Windows task-local app-state zip manifests so their embedded `taskName` values now match the owning folder names after the Windows task renumber and naming pass, including the three split CLI tasks.
- Fixed isolated live validation of `136-configure-language-settings` on the active managed Windows VM by treating “capability state already satisfied” as a valid completion path for the lingering Turkish install worker instead of surfacing a warning after the SSH transport is closed by the guest.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, `tests\documentation-contract-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated live in isolation on the active managed Windows VM through `task --run-vm-init 03`, `task --run-vm-init 04`, `task --run-vm-update 01`, `task --run-vm-update 121`, `task --run-vm-update 124`, `task --run-vm-update 125`, `task --run-vm-update 126`, `task --run-vm-update 134`, and a fixed rerun of `task --run-vm-update 136`.
- Verified live follow-up state after the language-task fix: the VM returned to SSH cleanly after the reboot-signaled rerun of `136`, the system preferred UI language read back as `en-US`, and the Turkish language capability surface read back as installed.

## [2026.3.18.347] - 2026-03-18

### Changed
- Changed `tools/scripts/clagnos-interactive-session-helper.ps1` so it now exposes a reusable AppX registration repair worker that can run under a selected managed user through the existing scheduled-task automation path and verify `shell:AppsFolder` visibility by AppID pattern instead of only relying on the current SSH session.
- Changed `10003-create-shortcuts-public-desktop` so it now copies the interactive-session helper as a tracked task asset, repairs Store-backed AppsFolder registrations for both managed users before shortcut normalization, and keeps the task budget aligned with that extra work by raising its tracked timeout to `120` seconds.
- Changed the same Public Desktop task so user-scoped shortcut commands that are meant to follow the current profile now keep `%UserProfile%` or `%LocalAppData%` in the managed shortcut contract instead of collapsing those paths into whichever managed user happened to run the task.

### Fixed
- Fixed the active managed Windows shortcut surface so `o2Teams`, `a3Be My Eyes`, `a2CodexApp`, `a4WhatsApp Business`, and `d4ICloud` now repair and verify usable AppsFolder launch targets for both `manager` and `assistant`, not just for the currently active shortcut-refresh session.
- Fixed the Public Desktop normalization path so rerunning `10003-create-shortcuts-public-desktop` now rewrites stale launcher-backed and console-backed shortcuts such as `k1Codex CLI` and `k2Gemini CLI` back to the intended user-relative contract instead of preserving hard-coded `C:\Users\<name>\...` arguments from older generations.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated live in isolation on the active managed Windows VM through repeated reruns of `task --run-vm-update 10003`, confirming password-logon AppID repair success for both `manager` and `assistant` across Teams, Be My Eyes, Codex, WhatsApp Business, and iCloud with no stage warnings.
- Rechecked the live Public Desktop shortcut definitions after the repair runs and confirmed that the critical user-scoped shortcuts now keep `%UserProfile%` or `%LocalAppData%` in their raw `.lnk` or managed-launcher contract instead of storing a concrete managed username path.

## [2026.3.18.346] - 2026-03-18

### Changed
- Changed `105-install-teams-system` so the Microsoft Teams Store install now follows the same interactive-desktop and persisted Store-state contract already used by the other Windows `winget -s msstore` update tasks, including launch-target validation and legacy state-file alias recovery.
- Changed isolated Windows Store-backed `task --run-vm-update` reruns so selecting `105`, `115`, `116`, `117`, or `122` now automatically appends `10003-create-shortcuts-public-desktop` in the same isolated execution plan instead of leaving Public Desktop shortcut refresh as a separate manual follow-up.
- Changed `10003-create-shortcuts-public-desktop` so the Teams shortcut now uses the same Store-managed shortcut recovery path as the other Microsoft Store apps, which keeps all repo-managed Store app shortcuts aligned on `explorer.exe` plus `shell:AppsFolder\<AUMID>` when a live AppID is available.

### Fixed
- Fixed the shared Store install-state helper so the current Teams task can still read pre-renumber state files from the older Teams task names instead of losing existing Store state on upgraded VMs.
- Fixed the active managed Windows VM shortcut surface so isolated reruns of the Store-backed tasks now leave `o2Teams`, `a2CodexApp`, `a3Be My Eyes`, `a4WhatsApp Business`, and `d4ICloud` present on the Public Desktop with `C:\Windows\explorer.exe` launch targets and `shell:AppsFolder\...` arguments.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated live in isolation on the active managed Windows VM through reruns of Windows update tasks `105`, `115`, `116`, `117`, and `122`, confirming that each isolated Store-backed task also ran `10003-create-shortcuts-public-desktop`, finished with `final-restart=0`, and left the expected Store-backed Public Desktop shortcuts readable through remote `exec`.

## [2026.3.18.345] - 2026-03-18

### Changed
- Changed the shared Windows interactive-session helper and the Store-backed update tasks for Be My Eyes, WhatsApp, Codex App, and iCloud so they now distinguish `autologon-disabled`, `autologon-different-user`, pending autologon desktop, and `explorer.exe`-not-ready states instead of collapsing every missing desktop into one generic warning.
- Changed the same four Store-backed tasks so they now log an explicit interactive desktop status line before warning or installing, and they perform one short bounded wait only when autologon is already configured for the manager user but the post-boot desktop is still coming up.
- Changed the tracked timeouts for `115-install-be-my-eyes`, `116-install-whatsapp-system`, and `117-install-codex-app` from `60/75/75` seconds to `90` seconds so the bounded desktop-readiness wait still fits inside the isolated task budget.

### Fixed
- Fixed the shared interactive-session helper so missing Winlogon values no longer throw under strict mode when autologon has been disabled and the related registry values are absent.
- Fixed the live no-autologon Windows Store path so isolated reruns of `115`, `116`, `117`, and `122` now persist degraded Store state with explicit guidance to run `102-autologon-manager-user` and restart, instead of failing with a registry-property crash or a vague desktop-missing warning.
- Fixed the live post-autologon Windows Store path so the same four tasks succeed again after `102-autologon-manager-user` triggers its reboot and the manager desktop comes back, with launch-ready Store state restored for all four apps.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated live on the active managed Windows VM through one explicit no-autologon cycle and one post-autologon cycle: remote cleanup of the four Store apps, a restart into `AutoAdminLogon=0`, isolated reruns of `115`, `116`, `117`, and `122` to confirm the new warning path, an isolated rerun of `102-autologon-manager-user`, and fresh isolated reruns of `115`, `116`, `117`, and `122` to confirm successful reinstall plus final `exec` AppID readback for all four apps.

## [2026.3.18.344] - 2026-03-18

### Changed
- Changed the Windows Store-backed update tasks for Be My Eyes, WhatsApp, Codex App, and iCloud so they now run the Microsoft Store `winget install` step through the manager interactive desktop token when that desktop is available, instead of relying on the SSH/service session for the actual Store acquisition.
- Changed the same Store-backed tasks so a missing manager interactive desktop is now recorded as a degraded install state and left as a warning-producing outcome instead of being silently suppressed as a clean skip.
- Changed the Public Desktop shortcut task so stale non-installed Store state no longer blocks shortcut recovery when the live VM can already resolve a real AppsFolder AppID or a launch-ready executable.

### Fixed
- Fixed `116-install-whatsapp-system` and `117-install-codex-app` so they now follow the same interactive-desktop automation model already used by the other Store-backed tasks, while still persisting explicit Store install-state records.
- Fixed `10003-create-shortcuts-public-desktop` so it can recover Store-backed shortcuts for Codex, Be My Eyes, WhatsApp, and iCloud from live AppsFolder targets even when an older degraded/skipped state record is still present.
- Fixed the Store-backed shortcut surface on the active managed Windows VM so `a2CodexApp`, `a3Be My Eyes`, `a4WhatsApp Business`, and `d4ICloud` now resolve through `C:\Windows\explorer.exe` plus `shell:AppsFolder\<AUMID>`.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated live through `exec` readback plus isolated reruns of Windows update tasks `115`, `116`, `117`, `122`, and `10003` on the active managed Windows VM, confirming launch-ready Store state for all four apps and warning-free shortcut refresh with `final-restart=0`.

## [2026.3.17.343] - 2026-03-17

### Changed
- Changed the Windows public desktop shortcut task so optional unresolved app and console launch targets now log informational `public-shortcut-skip` lines instead of warning lines, which keeps partially installed isolated-task reruns from reporting false-positive shortcut warnings.
- Changed the isolated `task --run-vm-update` contract so it still honors task-signaled immediate restarts but skips the workflow-only final Windows `vm-update` restart; end-to-end `create` and `update` remain the only flows that request that final restart before `vm-summary`.

### Fixed
- Fixed the Windows public desktop shortcut task so non-launch-ready Store app shortcuts such as Be My Eyes, WhatsApp Business, and iCloud no longer duplicate the earlier Store-task warning/degraded outcome during `10003-create-shortcuts-public-desktop`.
- Fixed the shared Store install state reader so existing VMs can still read legacy pre-renumber state files for Be My Eyes, WhatsApp, Codex App, and iCloud while the runtime continues using the current canonical task names.
- Fixed the documentation and help contract so README, detailed help, smoke coverage, and documentation-contract checks now describe the workflow-only final Windows `vm-update` restart correctly.

### Tests
- Revalidated non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated live only through an isolated rerun of `task --run-vm-update 10003` on the active managed Windows VM, which completed with `warning=0`, `signal-warning=0`, and `final-restart=0`.

## [2026.3.17.342] - 2026-03-17

### Added
- Added managed public DNS label allocation based on the effective VM name plus a managed attached-public-IP index, so new managed Windows VMs now receive labels such as `test-vm1` and `test-vm2` instead of labels derived from the public IP resource name.
- Added live public-IP DNS-settings fallback for VM detail readback so `show` can recover the real FQDN even when `az vm show -d` omits `fqdns`.

### Changed
- Changed the Windows normal `vm-update` catalog so `101-install-sysinternals-suite` now runs first, `102-autologon-manager-user` runs immediately after it, and the remaining normal-band tasks shift upward while preserving their relative order.
- Changed Windows Store-backed update tasks to require an interactive manager session before attempting `msstore` installs; when no interactive session is ready they now record a non-warning `skipped` store state, log one informational skip line, and exit cleanly.
- Changed `105-install-teams-system` to use a `75` second timeout while keeping the unattended `winget install "Microsoft Teams" -s msstore` install path and its agreement flags.
- Changed tracked Windows task manifests so helper assets are declared explicitly in `task.json` instead of being injected through the shared run-command template.

### Fixed
- Fixed Windows task-catalog ordering so dependency-safe ready-task selection now respects `priority` as the primary comparator instead of letting timeout-first ordering run higher-numbered tasks such as `vm-update #106` before lower-priority ready tasks.
- Fixed the Windows renumber drift across shipped `app-state.zip` payloads, runtime app-state/export maps, summary readback, browser preflight checks, and public-shortcut task references so live task names now match the current canonical folder names.
- Fixed `102-autologon-manager-user` so it now reports interactive-logon readiness and emits the standard reboot-required marker, which lets isolated task runs and the shared SSH runner restart the VM immediately before later Store-backed tasks continue.
- Fixed the successful isolated-task cleanup path so completed tasks such as `126-install-google-drive` no longer fall into the PowerShell debugger during transcript shutdown.

### Tests
- Revalidated the full non-live gate with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the affected Windows update flow live only through isolated task runs on the active managed VM for `101`, `102`, `105`, `115`, `116`, `117`, `122`, `126`, and `10003`; no full end-to-end live `create` run was performed in this change set.

## [2026.3.17.341] - 2026-03-17

### Added
- Added a shared task-restart helper for `vm-init`, `vm-update`, isolated task runs, and the main workflow so reboot-signaling tasks can restart the VM immediately, wait for recovery, and then continue with the next task.
- Added `dependsOn`-aware task-catalog ordering plus observed-duration metadata so runtime discovery can sort tasks dependency-safe inside each band before using timeout and alphabetical tie-breaks.
- Added `vm-summary` readback helpers and platform-specific summary scripts so the final summary now begins with a read-only guest health/state probe instead of relying on a dedicated late update task.

### Changed
- Changed the shared VM task timeout contract so every tracked and local `vm-init` / `vm-update` task now uses a minimum `30` seconds and rounds up in `15`-second increments, with the runtime helper enforcing the same normalization centrally.
- Changed the Windows init/update task catalogs by reordering and renumbering them inside their existing `initial`, `normal`, `local`, and `final` bands, moving `autologon-manager-user` into the final update band and keeping it as the last final Windows update task.
- Changed `vm-update` restart orchestration so reboot-signaling tasks restart immediately after completion, while the Windows `vm-update` stage still performs one additional final restart before `vm-summary`.
- Changed `10005-copy-settings-user` so it is now a pure portable mirror of `manager` state into `assistant`, the default profile, and `HKEY_USERS\.DEFAULT`; the old curated per-app copy model is no longer part of the active task behavior.
- Changed the operator documentation and CLI help so create/update now describe task-immediate restarts, the final Windows `vm-update` restart, and the new `vm-summary` readback-first flow.

### Removed
- Removed `windows/update/10006-capture-snapshot-health` and `linux/update/10001-capture-snapshot-health` from the active task inventories.
- Removed the remaining dead curated-copy helper block from `10005-copy-settings-user.ps1`.

### Fixed
- Fixed the smoke-contract surface so it now resolves the renumbered task folders, checks dependency-safe Windows update ordering without overfitting to one exact timeout-tie order, and validates the new portable-mirror `copy-settings-user` contract.

### Tests
- Revalidated the full non-live gate with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.

## [2026.3.17.340] - 2026-03-17

### Changed
- Changed the create/update workflow wrapper so Step 6 now returns the real `vm-update` stage result to the caller; the conditional post-`vm-update` restart barrier can now see `RebootRequired` reliably instead of falling through to `vm-summary` without restarting.
- Changed the shared SSH task-stage accounting so continue-mode task issues are kept in the warning bucket and returned as `WarningTasks`, which keeps warning-only `vm-update` runs from being summarized as failed-task runs.
- Changed `10003-configure-ux-windows` verification so it now trusts persisted regional state and logs the effective current-session culture for evidence, instead of warning just because `Get-Culture` in the same process still reports the preexisting culture.

### Fixed
- Fixed `123-install-vlc-system` so its post-install verification now invokes `winget list --id VideoLAN.VLC` through the resolved executable path correctly; the task no longer throws the invalid call-operator object warning during fresh create runs.
- Fixed the workflow step wrapper contract in `Invoke-Step`; callers now receive the wrapped action result instead of only seeing timing/log output side effects.

### Tests
- Revalidated the workflow and task repairs non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the affected Windows update surfaces live in isolation on the active managed VM with `task --run-vm-update 123`, `task --run-vm-update 10003`, and `task --run-vm-update 10006`.

## [2026.3.17.339] - 2026-03-17

### Changed
- Changed the interactive `configure` editor so blank-permitted picker-backed fields now recover softly instead of aborting the session: stale current values can no longer be kept silently, filterable numbered pickers are reused for subscription, region, and managed resource-group selection, and `SELECTED_RESOURCE_GROUP` is now cleared automatically when the current subscription has no managed resource groups.
- Changed the configure save contract so `.env` writes are blocked only when create-critical values remain unresolved; blank-permitted fields can now be cleared and the editor continues with explicit guidance instead of exiting on the first stale Azure-backed value.
- Changed the operator and documentation surface so AGENTS, README, CLI help, smoke tests, and documentation-contract checks now describe the new configure recovery model, including the no-managed-resource-group guidance path.

### Fixed
- Fixed the stale `SELECTED_RESOURCE_GROUP` Enter path in `configure`; keeping an outdated managed resource group no longer throws `Resource group check failed before configure` and terminates the editor.

### Tests
- Revalidated the configure recovery update non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.

## [2026.3.17.338] - 2026-03-17

### Added
- Added a new interactive configure-editor module that turns `clagnos configure` into a sectioned `.env` frontend with picker-backed multi-option fields, staged validation, next-create preview, and one-shot save behavior for the full supported dotenv contract.
- Added `show --vm-name` so `show` can focus one managed VM and render a read-only target-derived configuration section without writing `.env`.

### Changed
- Changed the `configure` command contract so it now accepts only `--help` and `--perf`, opens without `az login`, keeps Azure-backed fields read-only when Azure validation is unavailable, and rejects the retired targeting flags with a configure-specific guidance error.
- Changed the repo documentation and contract tests so AGENTS, README, help text, and smoke/documentation checks now describe `configure` as the interactive `.env` frontend and `show` as the read-only home for live target-derived configuration.
- Changed dotenv persistence so supported `.env` keys can now be written back in one final save pass while preserving the committed contract order and filtering out unsupported key assignments.

### Tests
- Revalidated the configure/frontend contract non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.

## [2026.3.17.337] - 2026-03-17

### Changed
- Changed Windows language readback wording in `132-configure-language-settings` and `10006-capture-snapshot-health` so operator-visible logs now say Windows did not report component details instead of emitting the raw `metadata-unavailable` token.
- Changed nested-virtualization feature fallback messaging so create/update logs now say Azure did not report the capability clearly and that guest validation will be used, instead of the older metadata-centric phrasing.

### Fixed
- Fixed `101-install-powershell-core` so fresh Windows create runs no longer warn just because PowerShell 7 installation takes longer than the old `53s` timeout; the task now uses a `120s` tracked timeout, accepts Chocolatey reboot-style success, and short-circuits healthy installs by resolving the real `pwsh.exe` path directly.
- Fixed the Windows smoke contract so the tracked `101-install-powershell-core` timeout matches the shipped task manifest again.

### Tests
- Revalidated the updated PowerShell task and operator-message cleanup non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated `101-install-powershell-core` live in isolation on the partially created managed Windows VM and confirmed that the managed Azure inventory is now clean and ready for the next full end-to-end create attempt.

## [2026.3.17.336] - 2026-03-17

### Changed
- Changed the Windows mixed language-and-region contract so `10003-configure-ux-windows` now restores the system locale target to `en-US` while still keeping Turkish Q input, Turkish regional formats, Istanbul time zone, and UTF-8 code-page intent enabled across the managed system.
- Changed the Windows regional task flow so `10003-configure-ux-windows` now reasserts the intended `en-US` system locale after welcome-screen and new-user propagation, preventing locale drift while preserving Turkish user-format state.

### Tests
- Revalidated the updated locale contract non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the updated Windows regional flow live in isolation on the active managed Windows VM with `task --run-vm-update 10003`, `task --run-vm-update 10006`, and direct `exec -q` readbacks for system preferred UI language, system locale, time zone, UTF-8 code pages, and managed-user input/culture state.

## [2026.3.17.335] - 2026-03-17

### Added
- Added tracked Windows `vm-update` tasks `133-install-sysinternals-suite` and `134-autologon-manager-user` by moving the old tracked init responsibilities into the Windows update stage with their own portable task folders.
- Added finer-grained progress lines for the Windows language and regional configuration flow so long-running update steps surface visible phase transitions instead of behaving like a single opaque block.

### Changed
- Changed the Windows update catalog and timeout contract so the tracked init catalog now ends at `06`, the tracked update catalog now includes `133` and `134`, and the current Windows init/update task timeouts are recalibrated from the latest live create evidence with the regional UX task expanded further after its ownership split.
- Changed the Windows language pipeline so `132-configure-language-settings` now owns language-package and UI-language work only, while `10003-configure-ux-windows` now owns system locale, Turkish Q input, Turkish regional formats, Istanbul time zone, UTF-8 code-page intent, and welcome-screen/new-user propagation.
- Changed the Windows create/update workflow contract so the planned restart at the start of `vm-update` is removed; the workflow now keeps only the conditional post-`vm-update` restart when a reboot request is actually raised.

### Fixed
- Fixed `123-install-vlc-system` so bounded winget waits now keep a visible `winget list --id VideoLAN.VLC` verification fallback, avoid stale `refreshenv`/`wmic` noise, and complete cleanly on healthy reruns instead of warning after a short timeout.
- Fixed `10003-configure-ux-windows` by skipping already-correct heavy regional cmdlets on reruns, extending its timeout for the expanded responsibility set, and hardening default-profile hive unload handling so regional propagation no longer fails with registry-hive cleanup warnings.
- Fixed `10006-capture-snapshot-health` default-user language readback by switching its temporary hive mount/unmount path to the same quiet checked registry helper model, removing the old `ERROR: The parameter is incorrect.` warning from successful health snapshots.

### Tests
- Revalidated the updated Windows task flow non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the affected live tasks in isolation on the active managed Windows VM with `task --run-vm-update 132`, `10003`, `123`, `133`, `134`, and `10006`, plus direct `exec -q` readbacks for system locale, time zone, VLC presence, and Winlogon autologon state.

## [2026.3.16.333] - 2026-03-16

### Added
- Added a commandless global `clagnos --version` fast path that prints only `clagnos version <current-release>` and exits before the normal banner and runtime-dispatch workflow.
- Added operator-visible guest output relay for task execution: Windows `vm-update` now streams guest stdout and stderr live over SSH, while `vm-init` now replays the full guest transcript immediately after each Azure Run Command task completes.

### Changed
- Changed the Windows `create` and `update` workflow so `vm-update` now begins after one planned restart at the start of Step 6, and any reboot request raised by an update task now triggers one automatic workflow-owned restart before `vm-summary`.
- Changed top-level step labels and feature-enablement messaging so create/update progress now reads as stable step names and plain action/result messages instead of future-tense or ambiguous nested-virtualization wording.
- Changed the operator and documentation surface so `README.md` and CLI help now document `--version`, the wrapped `vm-update` restart behavior, guest output relay, and the requirement that the pushed `main` SHA must complete the GitHub Actions quality gate green before a release push is considered done.

### Fixed
- Fixed the CLI entrypoint so `clagnos.ps1` still loads the full runtime manifest when dot-sourced while also keeping the new `--version` path banner-free and pre-dispatch.
- Fixed Windows-friendly prompt-history UTC heading validation in `tests\documentation-contract-check.ps1` by accepting `CRLF` line endings instead of falsely failing on valid `### YYYY-MM-DD HH:MM UTC` headings.
- Fixed run-command task failure reporting so guest output is relayed before the task throws, and a clear `Task completed ... - error` line is emitted for the failing task.

### Tests
- Revalidated the release non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.

## [2026.3.16.332] - 2026-03-16

### Changed
- Hardened `132-configure-language-settings` so Windows language capability verification now treats `InstallPending` as a valid queued state for the requested language surface when reboot-pending servicing prevents immediate completion, while still requiring the requested language capabilities to be present and in an acceptable state.

### Fixed
- Fixed the `132-configure-language-settings` false failure path that occurred when `Install-Language tr-TR` returned a partial-install error while the requested `Language.Basic`, `Language.Handwriting`, `Language.OCR`, and `Language.TextToSpeech` capabilities had already been staged as `InstallPending` behind an earlier reboot requirement.
- Fixed the post-install verification path for `132-configure-language-settings` so the task now falls back to Windows capability-state validation when `Get-InstalledLanguage` is still empty before reboot, instead of failing the entire task even though the language installation has already been queued correctly.

### Tests
- Revalidated the pending-language capability contract non-live with `tests\clagnos-smoke-tests.ps1`, `tests\powershell-compatibility-check.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.

## [2026.3.16.331] - 2026-03-16

### Added
- Added tracked Windows `vm-update` task `132-configure-language-settings`, which installs and verifies the `en-US` plus `tr-TR` language surface, applies English UI with Turkish locale/region/timezone/24-hour formats, forces Turkish Q as the default input method, enables the UTF-8 system code page intent, and copies the final international state to the welcome screen and new-user profile defaults.
- Added `exec --quiet` / `exec -q` as an explicit one-shot SSH command mode that suppresses banner, diagnostics, and remote information-stream chatter so the command prints only the remote result stream.

### Changed
- Moved the remaining builtin language, keyboard, locale, timezone, and regional-format ownership out of `10005-copy-settings-user` and into `132-configure-language-settings`, while keeping `10005` responsible only for non-language user-state propagation.
- Kept both `10005-copy-settings-user` and `10006-capture-snapshot-health` fully on-the-fly by removing their task-local app-state contract and skipping any app-state replay for those tasks.
- Extended the Windows health snapshot language readback so managed-user status now includes the effective default input method in addition to the language list, keyboard preload, UI language, locale, and format values.
- Tightened quiet one-shot exec wrapping so Windows remote commands now suppress information-stream `Write-Host` chatter with an encoded PowerShell wrapper that redirects stream `6` to `$null`.

### Fixed
- Fixed `exec -c "<command>"` parsing at the launcher entrypoint so the short `-c` form survives raw-token forwarding and Windows one-shot commands such as `Get-Date` are wrapped into a PowerShell command instead of being sent raw to `cmd.exe`.
- Fixed Windows one-shot exec timeout handling so remote command execution now uses `SSH_TASK_TIMEOUT_SECONDS` instead of the shorter SSH connect timeout, avoiding false failures during longer isolated validation commands.
- Fixed `132-configure-language-settings` user-language assembly by adding the real secondary `WinUserLanguage` entry instead of passing the full secondary list object into `.Add(...)`.
- Fixed `132-configure-language-settings` welcome-screen and new-user normalization by adding the missing registry hive mount/unmount helpers directly into the task, removing the live failure that occurred at `Dismount-RegistryHive` during the final welcome-screen step.

### Tests
- Revalidated the parser, quiet exec wrapper, language task contract, and health output non-live with `tests\clagnos-smoke-tests.ps1`.
- Revalidated `exec --quiet` live with direct one-shot `Get-Date` and interactive helper readback commands on the active managed Windows VM.
- Revalidated `132-configure-language-settings` live step by step with isolated `exec -q` system, manager, assistant, welcome-screen, and new-user readbacks before rerunning `task --run-vm-update 132 --windows --perf`.
- Revalidated the final live runner path with isolated `task --run-vm-update 132`, `task --run-vm-update 10005`, and `task --run-vm-update 10006`, followed by direct manager, assistant, welcome-screen, and default-profile readbacks that confirmed English UI, Turkish locale/format state, Turkish Q preload `0000041f`, and default input method `041F:0000041F`.

## [2026.3.16.330] - 2026-03-16

### Changed
- Updated the Windows managed shortcut-launcher invocation contract so launcher-backed Public Desktop shortcuts now call their generated `.cmd` files through `cmd.exe /c call "<launcher-path>"` instead of invoking the launcher path directly.

### Fixed
- Fixed launcher-backed Public Desktop shortcut targets so long browser entries such as `q2Spotify` now use the explicit `call` form requested for every over-limit launcher-backed shortcut, while direct-safe entries continue to bypass the launcher path entirely.

### Tests
- Revalidated the launcher invocation contract non-live with `tests\clagnos-smoke-tests.ps1` and `tests\powershell-compatibility-check.ps1`.
- Revalidated the updated invocation shape live in isolation on the active managed Windows VM with `task --run-vm-update 10002 --windows --perf` plus `exec` readbacks that confirmed `q2Spotify` now points to `cmd.exe /c call "C:\ProgramData\clagnos\shortcut-launchers\public-desktop\q2spotify.cmd"` while `z1Google Account Setup` remains a direct `chrome.exe` shortcut.

## [2026.3.16.329] - 2026-03-16

### Changed
- Removed task-local app-state ownership from `10002-create-shortcuts-public-desktop`, so the Windows Public Desktop shortcut task now stays fully on-the-fly and no longer restores stale `.lnk` or launcher artifacts from a saved payload after it finishes.
- Kept the shipped shortcut launcher boundary unchanged in runtime behavior: direct `.lnk` targets remain in place when the combined `TargetPath + Arguments` invocation length is `<= 259`, and only true over-limit shortcuts continue to resolve through managed launcher `.cmd` files.

### Fixed
- Fixed the live Public Desktop regeneration path so rerunning `10002-create-shortcuts-public-desktop` no longer replays an old task-local `app-state.zip` over freshly generated shortcuts, which had been leaving direct-safe entries such as `z1Google Account Setup`, `i1Internet Business`, and `a11MS Edge` stuck on older `cmd.exe`-wrapped shapes.

### Tests
- Revalidated the updated Public Desktop task non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the live shortcut behavior in isolation on the active managed Windows VM with `task --run-vm-update 10002 --windows --perf` plus `exec` readbacks that confirmed `z1Google Account Setup`, `i1Internet Business`, and `a11MS Edge` now resolve directly to their browser executables while over-limit entries such as `q2Spotify` still use managed launcher `.cmd` files.

## [2026.3.16.328] - 2026-03-16

### Changed
- Added a dedicated `tools/scripts/normalize-app-state-zips.ps1` maintenance helper that scans every task-local `app-state.zip`, rewrites foreign local-source profile tokens to the canonical `manager` payload token, merges duplicate profile trees by `newer timestamp -> larger size -> lexical token`, and rewrites embedded `C:\Users\<name>` registry literals to `manager`.
- Extended the manual `tools/scripts/app-state-audit.ps1` report so it now surfaces foreign source-profile tokens and embedded foreign registry-user literals, not just foreign manifest `targetProfiles`.
- Made the Windows Public Desktop shortcut launcher threshold explicit in the shipped contract: the task now keeps direct `.lnk` target plus arguments when the combined invocation length is `<= 259`, and only emits a managed launcher `.cmd` when the combined invocation length exceeds that boundary.

### Fixed
- Fixed profile-generic local app-state saves so they normalize reusable payload source paths to `manager` even when the owning task uses the generic empty-`targetProfiles` contract rather than the older explicit `portableProfilePayload` flag.
- Fixed the remaining task-local app-state payloads that still carried foreign user markers or embedded local user paths, including `10005-copy-settings-user`, `116-install-codex-app`, `117-install-teams-system`, `120-install-whatsapp-system`, and `125-install-be-my-eyes`.
- Fixed the shortcut launcher helper export surface so the combined invocation-length helper is now available to smoke coverage and future runtime callers.

### Tests
- Revalidated the app-state normalization tool, the local-save canonical-manager path, and the Public Desktop launcher threshold non-live with `tests\clagnos-smoke-tests.ps1`.
- Re-audited the live task-local payload set with `tools\scripts\app-state-audit.ps1` after normalization and confirmed that no remaining `app-state.zip` payload reports foreign source users or embedded foreign registry-user literals.

## [2026.3.16.327] - 2026-03-16

### Changed
- Moved the builtin JAWS settings replay ownership fully onto `131-install-jaws-screen-reader`, so the task-local app-state payload now carries the full `Freedom Scientific` machine and user registry surface plus the full JAWS 2025 settings tree, while JAWS auto-start remains isolated in `10001-configure-apps-startup`.
- Marked the JAWS task payload as a portable profile snapshot and normalized local-machine saves to one canonical managed-profile shape, rewriting task-local app-state source paths, payload folder names, and user-registry profile path markers from the local source profile to `manager`.
- Extended the Windows health snapshot readback with explicit JAWS settings and registry presence checks for both managed profiles plus the HKLM and WOW6432 `Freedom Scientific` trees.

### Fixed
- Fixed portable task-local app-state saves so a JAWS payload captured from the local operator machine no longer preserves the source-machine profile token inside the zip manifest, profile payload folders, or HKCU registry export paths.
- Fixed the portable payload normalization contract by carrying the `portableProfilePayload` flag through task discovery/runtime materialization and by validating the `manager` canonicalization path with dedicated smoke coverage.

### Tests
- Revalidated the portable JAWS payload normalization non-live with `tests\clagnos-smoke-tests.ps1` and `tests\powershell-compatibility-check.ps1`.
- Regenerated `windows/update/131-install-jaws-screen-reader/app-state/app-state.zip` from the local machine with `task --save-app-state --source=lm --user=.current. --vm-update-task=131 --windows --perf` and verified that the task-local zip now uses `manager` instead of the local source profile token.
- Revalidated the shipped JAWS replay path live in isolation on the active managed VM with `task --run-vm-update 131 --windows --perf`, `task --run-vm-update 10006 --windows --perf`, and direct `exec` readbacks that confirmed manager/assistant settings plus HKLM/HKCU `Freedom Scientific` presence on the target VM.

## [2026.3.16.326] - 2026-03-16

### Changed
- Promoted Windows task asset transport to a host-key-validated `pscp.exe` SCP path with remote size and SHA-256 verification, replacing the slower base64 chunk upload path that was inflating live `create --auto --windows --perf` runs.
- Tightened task-scoped app-state capture and replay path handling so file payloads preserve their exact relative destinations, wildcard restore targets expand deterministically on both local-machine and guest replay paths, and the managed WhatsApp app-state contract excludes large transfer and AppCenter residue that was bloating uploads.
- Raised the short timeout ceilings for `103-install-python-system`, `106-install-gh-cli`, `107-install-7zip-system`, and `127-install-rclone-system` so healthy first installs no longer trip warning states purely because the default timeout band was too narrow.

### Fixed
- Fixed step review diagnostics so password-, secret-, and token-shaped keys are always shown as `[redacted]` in the effective configuration block and review output, preventing plaintext credential leakage during live `create` review stages.
- Fixed configuration template validation so unresolved placeholder tokens in resource-group and generated-resource naming templates now fail early with a precise corrective hint instead of flowing silently into runtime naming.
- Fixed task-scoped app-state replay for single-file overlays such as the local JAWS `version.dll` payload by preserving the exact destination file path rather than appending duplicate file extensions during capture or replay.

### Tests
- Revalidated the transport, diagnostics, timeout, and app-state changes non-live with `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, and `tests\powershell-compatibility-check.ps1`.
- Revalidated the Python timeout fix live in isolation with `task --run-vm-update 103 --windows --group <resource-group> --vm-name <vm-name> --perf`, then completed one full live Windows publish cycle with the exact command `create --auto --windows --perf`, followed by `show`, `do --vm-action=status`, `connect --ssh --test`, and `connect --rdp --test`.

## [2026.3.16.325] - 2026-03-16

### Changed
- Removed the remaining on-disk disabled `vm-init` / `vm-update` task folders so the active repository no longer keeps stale disabled task implementations under the stage trees.
- Standardized empty `disabled/` roots across Linux and Windows stage trees, keeping only placeholder `.gitkeep` files where the directory contract needs to remain visible.

### Fixed
- Fixed the Windows local disabled task inventory so stale disabled task folders no longer linger on disk and reappear in discovery or cleanup workflows after newer local task work adds different priorities.

### Tests
- Revalidated disabled-task cleanup non-live with direct `task --list --disabled` inventory checks across Windows and Linux init/update stages, plus the smoke, documentation-contract, and release-doc gates.

## [2026.3.16.324] - 2026-03-16

### Changed
- Reworked `task --restore-app-state` safety so local-machine restore no longer stages backups under temp-only paths; it now writes task-adjacent snapshots under `backup-app-states/<task-name>/` or `local/backup-app-states/<task-name>/`, alongside `restore-journal.json` and `verify-report.json`.
- Extended local-machine restore to verify every restored file, directory, and declared registry subtree after replay, and to roll back automatically from the task-adjacent backup root when replay or verification fails.
- Extended Windows guest VM restore to back up touched files and registry paths in guest-side temporary staging, verify the replayed content after restore, and roll back automatically when verification detects drift.

### Fixed
- Fixed local restore bookkeeping so tracked and local-only task folders now resolve their backup roots deterministically from the portable task folder location instead of using opaque temp-only directories.
- Fixed restore verification visibility so smoke coverage, README guidance, and AGENTS rules now describe the current `backup-app-states`, `restore-journal.json`, and `verify-report.json` contract without colliding with the retired stage-local `app-states/` wording.

### Tests
- Revalidated the app-state restore backup, verify, and rollback contract non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, and `tests\powershell-compatibility-check.ps1`.

## [2026.3.16.323] - 2026-03-16

### Added
- Added tracked Windows `vm-update` task `131-install-jaws-screen-reader`, which installs JAWS 2025 through `winget`, verifies the `jfw.exe` install path, and carries a task-local app-state contract for the JAWS 2025 settings directory plus the full `Freedom Scientific` HKCU/HKLM/WOW6432 registry subtrees.

### Changed
- Extended the Windows managed startup contract with one explicit accessibility exception: JAWS is now always written as a machine `Run` entry with `/run`, matching the current local-machine contract instead of depending on host startup-profile mirroring.
- Extended the Windows Public Desktop and local app-state export contracts so JAWS now gets a managed `j0Jaws` shortcut with `Ctrl+Shift+J`, duplicate-alias cleanup, health readback, and local app-state export coverage.

### Tests
- Revalidated the JAWS task, managed startup exception, Public Desktop shortcut, health snapshot, and app-state capture contract non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.

## [2026.3.16.322] - 2026-03-16

### Changed
- Replaced the old flat stage-root task files plus stage-root catalog JSON files with portable task folders across Windows and Linux init/update stages, so each task now owns one same-named script, one `task.json`, optional helper assets, and its own task-local app-state contract.
- Renumbered the tracked Windows and Linux task inventories within their stage bands so init and update flows no longer carry numbering gaps after the portable-folder cutover.
- Reworked task discovery, runtime help, pipeline wording, README guidance, and documentation contracts around the new portable task-folder model, including hot-swap-safe missing-folder handling and task-local `<task-folder>/app-state/app-state.zip` ownership.
- Extended `task --save-app-state` and `task --restore-app-state` with a split `--source=vm|lm` / `--target=vm|lm` surface, keeping VM behavior as the default while adding Windows local-machine capture and replay through the same task-owned app-state model.
- Standardized maintained repository time-of-day documentation on UTC, updated the repo rules to require UTC headings in `docs/prompt-history.md`, and converted the existing prompt-history timestamps to UTC.

### Fixed
- Fixed task-scoped app-state runtime resolution so both VM and local-machine save/restore now read the current task folder manifest, honor the same normalized allow-list, and resolve multi-user local targets consistently from `.all.`, `.current.`, or explicit comma-separated usernames.
- Fixed local-machine app-state restore safety so the replay path now validates the current `task.json` contract before mutation, writes a lightweight backup plus restore journal per target user, and can roll back the in-flight local user safely on failure.
- Fixed the remaining runtime and documentation surfaces that still emitted retired stage-root catalog/app-state terminology after the task-folder cutover.

### Tests
- Revalidated the portable task-folder loader, task-local app-state paths, local-machine app-state capture/restore, and UTC documentation contract non-live with `tests\clagnos-smoke-tests.ps1`, `tests\documentation-contract-check.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Deferred live isolated task reruns because the active managed VM target was deleted during this prompt; this change set was validated non-live only.

## [2026.3.16.321] - 2026-03-16

### Changed
- Cut the runtime over to the current selected-only configuration contract so orchestration, naming templates, task materialization, target selection, and runtime persistence now read and write only the current `SELECTED_*` and `AZURE_COMMAND_TIMEOUT_SECONDS` keys instead of synthesizing retired `.env` names.
- Reworked runtime diagnostics so create, update, configure, and task flows now print one canonical effective-configuration block where each resolved key appears once as `KEY=value (source)` instead of repeating the same values across multiple snapshots.
- Replaced the Windows SSH asset-transfer fallback model with one primary Windows `windows-base64` upload path that stages files over bounded command-text chunks, reports grouped progress and completion, and reuses remote hash metadata instead of spamming per-chunk pyssh lines.
- Tightened the managed browser app-state contract so Chrome and Edge app-state capture now keeps lightweight settings files instead of broad profile trees and low-value registry payloads.

### Fixed
- Fixed Windows SSH process execution so pyssh stdout and stderr are now captured directly without the PowerShell-native CLIXML noise that previously obscured real transport failures such as timeout and command-length errors.
- Fixed Windows task and app-state runners that previously leaked copy-result objects into task results, causing array-shaped failures and hiding the true task outcome.
- Fixed Windows app-state replay staging so each restore uses a unique remote zip path, waits for the uploaded zip to become readable, logs replay phases clearly, and surfaces remote replay output when a task restore fails.
- Fixed the Windows `vm-init` `108-install-sysinternals-suite` timeout ceiling so the isolated init rerun no longer fails on a cold run because of the previous short timeout.

### Tests
- Revalidated the selected-only runtime and diagnostics changes with `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\pre-commit-release-doc-check.ps1`.
- Revalidated the Windows transport and app-state path live in isolation against the active managed Windows target with `task --run-vm-init 108 --windows --group <resource-group> --vm-name <vm-name> --perf`, `task --run-vm-update 02 --windows --group <resource-group> --vm-name <vm-name> --perf`, `task --run-vm-update 111 --windows --group <resource-group> --vm-name <vm-name> --perf`, and `task --run-vm-update 110 --windows --group <resource-group> --vm-name <vm-name> --perf`.

## [2026.3.16.320] - 2026-03-16

### Changed
- Aligned the maintained README, smoke suite, and documentation-contract checks with the selected-only config contract by documenting `SELECTED_*` public names, `{SELECTED_VM_NAME}` managed-resource templates, `__SELECTED_*__` task placeholders, `AZURE_COMMAND_TIMEOUT_SECONDS`, and the current Windows shortcut validation wording.

### Tests
- Updated smoke assertions for create override keys, `.env.example` naming templates, task token replacement, and the Windows `vm-init` `108-install-sysinternals-suite` timeout so the non-live contract checks match the current selected-only runtime surface.

## [2026.3.15.319] - 2026-03-15

### Changed
- Reworked the Windows SSH asset-transfer helper so Windows `vm-update` and other SSH-stage asset uploads now retry SFTP briefly and then fall back to a chunked PowerShell `exec` transfer when the Windows OpenSSH SFTP subsystem is present but fails negotiation.

### Fixed
- Fixed Windows post-init update flows that previously aborted on `paramiko.ssh_exception.SSHException: EOF during negotiation` during `pyssh copy asset`, which blocked one-shot fallback tasks and task-owned helper-module staging even though normal SSH command execution was healthy.
- Fixed the Windows no-SFTP asset fallback so larger inline uploads no longer hit the remote `The command line is too long.` failure; the fallback now sends smaller bounded chunks and finalizes the remote file successfully.

### Tests
- Revalidated the new Windows asset fallback live against the active Azure target by deleting the existing clagnos-managed resource groups, reprovisioning `clagnos create --auto --windows --perf`, syncing the resulting target with `configure`, and confirming `do --vm-action=status`, `connect --ssh --test`, and `connect --rdp --test` against the new managed VM.

## [2026.3.15.318] - 2026-03-15

### Added
- Added an unconditional CLI welcome banner at the `clagnos.ps1` entrypoint so every invocation now starts with `CLAGNOS CLI V<version>` plus a two-line feature summary before parsing or dispatching the command.

### Changed
- Reworked the Azure Run Command init task runner so vm-init tasks now execute one-by-one instead of as one combined batch, which lets the runtime apply the same post-task app-state restore contract after each init task when a matching stage-local plugin zip exists.
- Expanded the shared app-state restore helper with a run-command transport so init-stage post-task replay and `task --restore-app-state --vm-init-task ...` now reuse the same plugin resolver and guest replay path that update-stage restore already used over SSH.
- Updated AGENTS and README so the documented task/app-state contract now covers both vm-init and vm-update post-task replay instead of describing the plugin behavior as update-only.

### Fixed
- Fixed task-scoped init restore consistency so `task --restore-app-state` for vm-init no longer depends on SSH readiness and instead routes through the shared run-command transport, matching the new vm-init post-task replay behavior.

### Tests
- Revalidated the new init restore and banner behavior with `tests\\clagnos-smoke-tests.ps1` and `tests\\documentation-contract-check.ps1` before the full non-live validation sweep.

## [2026.3.15.317] - 2026-03-15

### Added
- Added `do --vm-action=redeploy` as an explicit Azure host-repair action that operators can invoke directly against an existing managed VM instead of relying only on the automatic redeploy repair paths inside update and lifecycle recovery helpers.

### Changed
- Expanded the `do` lifecycle contract across runtime, help text, README, and smoke coverage so `redeploy` now sits beside `reapply`, `hibernate-stop`, and `hibernate-deallocate` as a first-class operator action.

### Fixed
- Fixed the `do` command so a manual redeploy now waits for provisioning recovery and then restores the original started/stopped lifecycle state when Azure reports it deterministically after `az vm redeploy`.

### Tests
- Revalidated the new lifecycle action with isolated smoke coverage in `tests\\clagnos-smoke-tests.ps1`, plus the standard documentation and release-doc contract checks.

## [2026.3.15.316] - 2026-03-15

### Changed
- Reworked the committed `.env` contract so the persisted active-selection surface is now `SELECTED_*` only, including the new `SELECTED_RESOURCE_GROUP` selector for existing-target flows and the renamed shared timeout/pricing keys `AZURE_COMMAND_TIMEOUT_SECONDS` and `VM_PRICE_COUNT_HOURS`.
- Updated the shared runtime resolution model so CLI overrides still win, but the internal canonical runtime fields are now populated from `.env` `SELECTED_*` values instead of the retired persisted keys.
- Reworked `create --auto` so it can resolve platform, VM name, Azure region, and VM size entirely from `.env` `SELECTED_*` values plus the platform-specific VM defaults, without requiring explicit CLI `--vm-name`, `--vm-region`, `--vm-size`, or platform flags.
- Reworked configure, update, move, set, delete, list, and the shared managed-target helpers so persisted targeting now reads and writes only the selected `.env` keys instead of the old resource-output key set.

### Fixed
- Fixed platform selection resolution so `.env` `SELECTED_VM_OS` now drives unattended platform selection consistently in both direct resolution and prompted interactive flows.
- Fixed auto-update validation and messaging so the unattended existing-target path now fails against the real selected-group contract and explains missing `SELECTED_RESOURCE_GROUP` state precisely.
- Fixed `.env` writeback so retired persisted keys are removed after configure/create/update/move/set flows instead of lingering beside the selected-only contract.

### Docs
- Rewrote `.env.example`, README, AGENTS, help text, smoke/docs contract coverage, and sensitive-content placeholder assertions around the selected-only configuration contract.
- Updated the operator guidance so unattended `create --auto` is now documented as a `.env`-driven flow when the selected values and platform defaults are complete.

### Tests
- Revalidated the full non-live gate with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.

## [2026.3.15.315] - 2026-03-15

### Added
- Added `tools\scripts\app-state-audit.ps1` as a manual helper that scans the stage-local `app-state.zip` payloads, reports remaining foreign profile targets, and lists the heaviest entries so payload cleanup can stay evidence-based instead of guess-driven.

### Changed
- Narrowed the shared app-state capture and replay contract so managed save/restore now targets only the `manager` and `assistant` OS profiles on both Windows and Linux, with no `default` profile and no arbitrary local-user enumeration.
- Tightened the tracked Windows app-state capture specs so the managed save path now prunes heavyweight generated content such as browser model stores and cache trees, installer/update payloads, telemetry trees, embedded WebView runtime caches, offline Office bundles, and other low-value runtime artifacts while preserving durable settings and registry state.
- Refined the stage-local ignored app-state payloads in place so the current `windows\update\app-states\*\app-state.zip` set now follows the same pruned contract, removes legacy foreign-profile targets, and keeps only the managed `manager` / `assistant` OS-user targets.

### Fixed
- Fixed legacy app-state plan merging so foreign user-target rules can no longer re-enter the managed capture plan after cleanup.
- Fixed the current ignored payload set so the Ollama task no longer carries `.ollama\models` or installer-update payloads, the azd task no longer carries `bin` or `telemetry`, and the heaviest browser, Docker Desktop, Office, GitHub CLI, and Visual Studio payload drifts are reduced to the settings-first baseline.
- Fixed the manual app-state audit helper so it stays an on-demand report and no longer emits raw object output unless `-PassThru` is requested explicitly.

### Tests
- Revalidated the shared app-state cleanup with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.
- Re-ran the manual payload inspection with `tools\\scripts\\app-state-audit.ps1` after the zip cleanup to confirm that the managed payload set no longer contains foreign profile targets.

## [2026.3.15.314] - 2026-03-15

### Added
- Added `connect` as the new public connection command, with explicit `--ssh` and `--rdp` transport flags plus `--test` support for both transport paths.
- Added `task --run-vm-init` and `task --run-vm-update` so isolated guest-task execution now lives under `task` instead of `exec`.
- Added shared `--command` / `-c` parameter support for `exec`, and expanded the option-spec metadata so value-taking options can support both `--option=value` and `--option value` plus short-form equivalents.

### Changed
- Reworked `exec` into an SSH-only shell surface: it now either opens the interactive remote shell or runs one remote command snippet, and no longer owns isolated task execution.
- Standardized the public target selector contract around `--group` / `-g`, `--vm-name` / `-v`, and `--subscription-id` / `-s`, and updated AGENTS, README, help output, and parser behavior to keep that contract aligned.
- Updated the runtime manifest, parser, dispatcher, help topics, command matrix, and smoke/docs coverage so the new public surface is now `configure`, `create`, `update`, `list`, `show`, `do`, `task`, `connect`, `move`, `resize`, `set`, `exec`, `delete`, `help`.

### Fixed
- Fixed the `resize --disk-size` option metadata so the generic parser now accepts `--disk-size <value>` in addition to `--disk-size=<value>`.
- Fixed the dispatcher and smoke/runtime coverage so `exec` now uses its reduced one-parameter entry contract consistently after the task-run cutover.
- Fixed remaining docs-contract gaps so README and AGENTS now reject the retired standalone `ssh` / `rdp` command surface and the retired `exec --init-task` / `exec --update-task` examples.
- Fixed the automated sensitive-content gate flow so local code-quality and commit-message checks stay focused on the current tree and the current commit message, while the full reachable-history audit remains available through a direct `tests\sensitive-content-check.ps1` run.

### Tests
- Revalidated the cutover with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.

## [2026.3.15.313] - 2026-03-15

### Added
- Added live `task --save-app-state` and `task --restore-app-state` maintenance flows for task-owned app-state payloads, with new shared parameter modules and help/README coverage for both init and update selectors.
- Added the tracked capture-spec registry and shared capture engine under `modules/core/tasks/`, plus SSH fetch support in `tools/pyssh/ssh_client.py`, so live Windows and Linux task state can now be captured into the existing per-task `app-state.zip` contract.
- Added committed `.env.example` placeholders for `company_web_address` and `company_email_address`, and documented the derived default VM naming rule based on the `employee_email_address` local-part plus `-vm`.

### Changed
- Reworked task-owned app-state maintenance so update-stage save/restore now uses one shared zip contract, one shared guest helper, one shared timeout policy, and one shared target-resolution path instead of ad hoc task-specific handling.
- Updated the Windows public desktop shortcut contract so `i1Internet Business` now derives its URL from `company_web_address`, `k1Codex CLI` now uses the richer Codex CLI launch arguments, and the iCloud shortcut uses the real iCloud launch contract instead of the old File Picker fallback.
- Updated the Windows app-state capture model so task `115-install-npm-packages-global` now captures full per-user `.codex` state alongside the other CLI configuration roots, and current registry capture prefers authoritative current specs over stale legacy registry entries when both exist.
- Updated the Chrome app-state restore path so task `02-check-install-chrome` now closes open Chrome windows before replay begins, reducing file-in-use conflicts during restore.

### Fixed
- Fixed task app-state capture-plan merging so ordered-hashtable capture specs no longer collapse into empty profile and registry collections during live save operations.
- Fixed Windows app-state capture scratch paths so deep `.codex` trees can be zipped without losing files to overlong temporary paths.
- Fixed registry export directory creation and legacy registry-path normalization during app-state save, and narrowed legacy registry carry-forward so stale mounted-hive roots no longer keep polluting new payloads.
- Fixed the current tracked tree so the banned historical literals requested for cleanup stay out of source/docs/tests while leaving local `.env` and ignored binary payloads untouched.

### Tests
- Revalidated the command and documentation contract with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, and `tests\\bash-syntax-check.ps1`.
- Revalidated the new live task app-state save/restore surface on the active managed Windows VM with isolated runs for `115-install-npm-packages-global` save/restore and repeated `02-check-install-chrome` save/restore verification after the Chrome pre-restore close hook was added.

## [2026.3.14.312] - 2026-03-14

### Added
- Added `modules/core/tasks/clagnos-shortcut-launcher.psm1` so Windows public desktop shortcut creation and health readback can share one managed short-launcher contract for overlong shortcut invocations.
- Added `tools/scripts/retro-log-audit.ps1` as an on-demand maintenance helper that can rescan local `clagnos-log-*.txt` transcripts without being part of the default quality gate.

### Changed
- Reworked `10002-create-shortcuts-public-desktop.ps1` so Chrome- and Edge-style shortcuts that would exceed the 259-character limit now rewrite themselves through managed short launchers under `C:\ProgramData\clagnos\shortcut-launchers\public-desktop` while keeping the same effective target, URL, profile, and argument contract.
- Updated `10099-capture-snapshot-health.ps1` so wrapper-backed shortcuts now read back their launcher path plus their effective target and arguments, and `a11MS Edge` keeps its argument contract even when the shortcut is launcher-backed.
- Consolidated the ignored local screen-reader update flow into one self-contained task, backed by one matching local helper module and one matching per-task app-state plugin path.
- Removed the automatic retro-log-audit reference from the default non-live gate and retired the old automatic test-path location.

### Fixed
- Fixed long browser-style Public Desktop shortcuts so they no longer fail because of overlong literal shortcut command lines.
- Fixed the local screen-reader save/restore naming contract so the merged single local task and its export helper now point to the same per-task app-state plugin name.
- Cleaned the current untracked `clagnos-log-*.txt` transcript set from the repo working tree while keeping the existing `.gitignore` protection in place.

### Tests
- Revalidated the non-live gate with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.
- Revalidated the manual retro-audit helper with `tools\\scripts\\retro-log-audit.ps1` after the working-tree transcript cleanup.
- Revalidated the touched live Windows tasks in isolation on the active managed Windows VM with `exec --update-task=1001`, `10002`, and `10099`, confirming the merged local screen-reader task, the short-launcher-backed Public Desktop shortcuts, and the refreshed shortcut health report.

## [2026.3.14.311] - 2026-03-14

### Added
- Added `modules/core/tasks/clagnos-store-install-state.psm1` as a shared one-shot Store-install helper module for Windows vm-update tasks, including centralized PATH refresh, portable `winget` resolution, explicit Store install-state persistence, and stale RunOnce cleanup helpers.
- Added a deterministic retro-log audit helper so the repo can rescan the historical `clagnos-log-*.txt` transcript set for known noisy or degraded patterns during future maintenance passes.

### Changed
- Reworked the Store-backed Windows install tasks (`117`, `121`, `126`, `131`) so they now use one explicit one-shot install-state contract instead of leaving any next-boot or next-sign-in repair work behind.
- Updated `10001-configure-apps-startup.ps1` so Teams startup now uses the same packaged-app launch contract as the healthy Store shortcut surface, preferring `explorer.exe shell:AppsFolder\<AUMID>` over brittle executable guesses.
- Updated `10002-create-shortcuts-public-desktop.ps1` so Store-backed shortcut generation can trust the recorded install-state launch contract when a later resolver cannot rediscover the same app-id or executable path immediately, which keeps shortcut eligibility aligned with the install task outcome.
- Updated `10099-capture-snapshot-health.ps1` so the late health report now reads back the shared Store install-state ledger, reports the current Store-install classification for the affected apps, and inventories the richer Docker/Teams/iCloud/shortcut state after the retro-log hardening pass.
- Updated the SSH vm-update runner so final stage summaries now distinguish task-level signal warnings from outright failures and no longer hide in-task warning signals behind a misleading all-green summary.
- Implemented Linux app-state replay support in the shared plugin manager for the supported file-copy contract, replacing the old placeholder warning that Linux replay was not implemented.

### Fixed
- Eliminated the remaining `refreshenv.cmd` / `wmic` transcript noise in the touched SSH task flows by centralizing PATH refresh through the shared Store helper and protocol-side benign-output normalization.
- Fixed Python install verification so `103-install-python-system.ps1` now pins a real Python executable path and avoids Windows Store alias noise during verification.
- Fixed the iCloud health contract so install-state, shortcut eligibility, and health reporting now use a tighter launch-ready predicate and a consistent recorded launch contract instead of treating package registration alone as success.
- Fixed `10005-copy-settings-user.ps1` so every emitted skip condition now contributes to the same skip-evidence ledger, which keeps the summary consistent with the detailed skip lines.
- Fixed local screen-reader autostart verification so the local verify step now performs a bounded repair-and-reverify pass before deciding whether a warning is still necessary.
- Fixed Windows Store banner normalization so the repeated benign Microsoft Store seizure warning no longer pollutes SSH task transcripts.

### Tests
- Revalidated the non-live gate with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.
- Revalidated the touched live Windows tasks in isolation on the active managed Windows VM with `exec --update-task=103`, `114`, `117`, `118`, `121`, `126`, `131`, `10001`, `10002`, `10005`, `10099`, plus the relevant local-only screen-reader tasks, confirming the one-shot Store-install path, Teams startup, iCloud shortcut recovery, Docker readiness, and screen-reader autostart repair.

## [2026.3.14.310] - 2026-03-14

### Added
- Added a shared vm-update app-state plugin manager under `modules/core/tasks/` that now resolves per-task app-state payloads only from stage-local `app-states/<task-name>/app-state.zip`, validates the embedded manifest, stages the zip to the guest, and replays it as a non-blocking post-process after builtin and local-only vm-update tasks.
- Added `docs/windows-store-migration-audit.md` to capture the current Windows installer-source matrix, explicitly separating Store-backed apps, approval-gated `winget + msstore` migration candidates, and apps that should stay on their current installer source.

### Changed
- Replaced the old tracked restore-task plus local overlay layout with one strict app-state contract: builtin and local vm-update tasks now share the same git-ignored stage-local plugin root, `.../update/app-states/<task-name>/app-state.zip`, and no other app-state source path is considered valid.
- Reorganized the local Windows app-state disk layout around per-task zip plugins, migrated the current ignored payloads into `windows/update/app-states/`, removed the old `app-state-overlays` restore path, and retired the dedicated local overlay replay task.
- Moved the local app-state export helper into `modules/core/tasks/` so builtin and local-only vm-update tasks now share one repo-level app-state orchestration path instead of mixing stage-local helper locations with the shared post-process.
- Reworked `10002-create-shortcuts-public-desktop.ps1` so Store-backed public desktop shortcuts now prefer `explorer.exe` plus `shell:AppsFolder\<AUMID>` launch contracts, while `a11MS Edge` stays a direct `msedge.exe` shortcut with the repo-managed shared argument profile rooted at `C:\Users\Public\AppData\Local\Microsoft\msedge\userdata`.
- Hardened shortcut reconciliation so same-name legacy `.lnk` files are no longer treated as healthy by name alone; normalization now rechecks target and argument contracts, which allowed Codex, WhatsApp Business, Edge, and Google Drive shortcuts to self-heal on the live VM.
- Hardened `113-install-wsl2-system.ps1` and `10099-capture-snapshot-health.ps1` so the repo now logs explicit WSL feature-state evidence, surfaces Docker Desktop prerequisite readiness, and verifies the refreshed Edge shortcut contract in the live health snapshot.
- Refreshed the README business/outcome story and documentation set so the current docs now mention Store-aware shortcuts, per-task git-ignored app-state zip plugins, Docker/WSL readiness hardening, and the dedicated Store migration audit document.

### Fixed
- Narrowed the local-only WSL save/restore payload so only the `docker-desktop` distro registry state is exported and replayed; non-Docker WSL distro entries are now excluded from the payload and purged during local overlay replay before the filtered Lxss state is imported.
- Hardened the SSH task transport so persistent-session task execution now falls back to one-shot execution when bootstrap or mid-task CLR/session failures occur, while still applying the same per-task app-state post-process contract afterward.
- Added a bounded lifecycle repair path for VMs that stay in provisioning state `Updating`: connection/runtime flows now trigger one explicit `az vm redeploy` repair attempt before failing.
- Relaxed guest-side app-state replay so locked or in-use payload files are logged as copy skips instead of breaking the whole replay, which keeps live app-state deployment non-blocking for actively running desktop apps.

### Tests
- Revalidated the tracked non-live gate with `tests\\clagnos-smoke-tests.ps1`, `tests\\documentation-contract-check.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.
- Revalidated the full live isolated Windows vm-update task set on the active VM with per-task `exec --update-task=...` runs across builtin and local-only tasks after the shared post-task app-state plugin hook, SSH transport fallback, and provisioning-repair path were wired into the runtime.

## [2026.3.13.308] - 2026-03-13

### Changed
- Reframed the top of `README.md` around the repo's current Windows flagship outcome: a near-zero-touch remote workstation experience with curated apps, startup behavior, desktop shortcuts, UX tuning, advanced settings, and user-preference carryover where the current task catalogs already provide it.
- Strengthened the first four README sections with audience-specific value language for employees, administrative teams, workers, developers, customers, operators, visitors, and sponsors, while keeping Linux positioned honestly as a stable and fully extensible lighter path.
- Added proof-oriented PoC / PoE narratives and expanded the delivered-outcome matrix so the public README shows concrete end-user and business value rather than only command-surface depth.

### Tests
- Revalidated the documentation refresh with `tests\\documentation-contract-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\clagnos-smoke-tests.ps1`, `tests\\powershell-compatibility-check.ps1`, `tests\\bash-syntax-check.ps1`, and `tests\\pre-commit-release-doc-check.ps1`.

## [2026.3.13.307] - 2026-03-13

### Changed
- Refined the prompt-history contract so very short approval/follow-up prompts and non-mutating question or analysis turns are no longer auto-recorded, while every other substantive prompt remains a mandatory English-normalized prompt-history entry.
- Updated `AGENTS.md`, `README.md`, and the documentation contract to require a short opt-in recording hint for excluded prompt types and to keep prompt-history focused on substantive work.

### Tests
- Revalidated the prompt-history contract update with `tests\\documentation-contract-check.ps1`, `tests\\code-quality-check.ps1`, `tests\\clagnos-smoke-tests.ps1`, `tests\\powershell-compatibility-check.ps1`, and `tests\\bash-syntax-check.ps1`.

## [2026.3.13.306] - 2026-03-13

### Changed
- Added a repo-wide sensitive-content guardrail for future work: local hooks, the non-live quality gate, and the engineering contract now require a dedicated audit that blocks obvious contact-style values, concrete identity leaks, and non-placeholder sensitive config drift before commits and pushes are shared.
- Added a dedicated `commit-msg` hook plus `tests/sensitive-content-check.ps1` so both repo-authored tracked files and commit messages receive the same high-signal hygiene checks.
- Documented the new guardrail in `AGENTS.md`, `README.md`, and the documentation contract so the rule stays visible and enforceable as part of normal developer workflow.

### Tests
- Revalidated the updated process guardrails with `tests\sensitive-content-check.ps1`, `tests\code-quality-check.ps1`, `tests\documentation-contract-check.ps1`, `tests\powershell-compatibility-check.ps1`, `tests\clagnos-smoke-tests.ps1`, and `tests\bash-syntax-check.ps1`.

## [2026.3.13.305] - 2026-03-13

### Changed
- Polished the post-cleanup maintained docs so the current repository surface no longer restates retired tokens, removed sample values, or replacement metadata explicitly in release-facing text.
- Reworded the reconstructed prompt ledger entry for the repository-wide cleanup pass so the current tracked documentation stays aligned with the sanitized public surface.

### Tests
- Revalidated the maintained tip with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.13.304] - 2026-03-13

### Changed
- Removed the retired destructive-rebuild shortcut from the create contract, runtime wiring, help output, tests, and maintained docs. Rebuild guidance is now expressed consistently as an explicit `delete` followed by `create`.
- Redacted the current tracked repository surface so concrete contact-style values, secret samples, organization-style example names, live acceptance target names, and real subscription identifiers no longer remain in shared code, docs, or tests. The remaining examples are now generic placeholders or neutral sample targets.
- Tightened the current docs and smoke contracts so the cleaned public surface stays aligned with the repo's current command contract and no longer reintroduces retired rebuild wording or legacy product residue.

### Security
- Rewrote the reachable git history in a controlled offline clone with the same replacement map applied to blob contents and commit messages, removing retired wording, legacy product residue, and concrete sensitive-looking sample values from reachable history.
- Standardized rewritten author and committer metadata to the configured maintainer identity while preserving original commit timestamps for the rewritten repository history.

### Tests
- Revalidated the rewritten current tip with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.13.302] - 2026-03-13

### Changed
- Reorganized `README.md` into an audience-first flow that now opens with a stronger at-a-glance introduction, a merged `Quick Start Guide`, `Customer Business Value`, `Executive Summary`, `Value By Audience`, and a richer delivered-outcome matrix before the deeper technical sections.
- Added a new top-level `Operational Command Matrix` to `README.md` so operators, customers, executives, developers, visitors, and sponsors can scan every public command, global option, and practical command variation from tables before diving into the deeper narrative guide.
- Polished the README presentation end to end so the same document now works better as an operator manual, stakeholder-facing overview, and public project landing page without reducing the underlying technical depth.

### Tests
- Updated `tests/documentation-contract-check.ps1` to enforce the new README heading hierarchy and the merged quick-start plus command-matrix structure.
- Revalidated the non-live documentation-facing gate with `tests/documentation-contract-check.ps1`, `tests/clagnos-smoke-tests.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.13.301] - 2026-03-13

### Changed
- Narrowed `10005-copy-settings-user.ps1` so the Windows user-settings mirror now copies only explicit user roots and selected app-state paths instead of sweeping broad `AppData\Roaming` and `AppData\Local` trees. The managed copy set is now limited to known profile folders plus targeted Task Manager, VS Code, Chrome, and repo-managed CLI-wrapper settings.
- Hardened the Windows live create/update path around fresh-VM findings: the OpenSSH init tasks now recover missing `sshd` registration on clean builds, the persistent SSH task runner restores dead sessions between update tasks, the portable winget bootstrap keeps a stable path for later package tasks, and the health snapshot now refreshes PATH plus resolves `az`, `docker`, and `ollama` through explicit fallback paths before probing them.
- Tightened the long-running Windows package contracts so Ollama now probes both `127.0.0.1` and `localhost` with a longer cold-start readiness window, and VLC now follows the same bounded winget-install plus post-install verification model already used for noninteractive AnyDesk and WhatsApp installs.

### Fixed
- Fixed fresh-create validation so duplicate VM names in other managed resource groups no longer block a fresh create in the new target group; only the target managed group is now treated as a hard conflict.
- Fixed the Azure location/SKU discovery path under forced subscription targeting by bypassing injected `--subscription` on Azure CLI account-level location lookups, preventing false region validation failures during `create` and managed-name generation.
- Fixed `104-install-node-system.ps1` so `refreshenv` output can no longer pollute the post-install `node.exe` verification path, which previously caused a false "command not recognized" failure on fresh VMs.
- Fixed `116-install-ollama-system.ps1` so it no longer shadows PowerShell's built-in `$Host`, and so first-run API readiness has enough bounded time to survive the clean-install cold-start path.
- Fixed `124-install-vlc-system.ps1` so a clean `winget install VideoLAN.VLC` no longer times out against an unrealistically short task budget; the task now verifies the resulting executable or package registration before deciding success or failure.
- Fixed `10099-capture-snapshot-health.ps1` formatting and command-resolution issues so the Ollama API JSON echo, Docker CLI probes, and general path readback no longer produce false negatives during late-stage health capture.

### Tests
- Revalidated the non-live gate with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.
- Completed the exact live Windows release-bar acceptance on subscription `<subscription-guid>`: cleaned drifted `rg-examplevm-ate1-g2`, reran fresh `create --auto --windows --vm-name=examplevm --vm-region=austriaeast --vm-size=Standard_D4as_v5`, validated `show`, VM status, SSH, and RDP, applied the required post-create restart barrier, and then completed `update --auto --windows --group=rg-examplevm-ate1-g2 --vm-name=examplevm` with zero failed tasks.

## [2026.3.13.300] - 2026-03-13

### Changed
- Added shared Azure subscription targeting across every Azure-touching public command: `create`, `update`, `configure`, `list`, `show`, `do`, `move`, `resize`, `set`, `exec`, `ssh`, `rdp`, and `delete` now support `--subscription-id=<subscription-guid>` plus `-s <subscription-guid>` / `-s=<subscription-guid>`.
- Added a shared Azure subscription resolver with the committed precedence `CLI --subscription-id/-s -> .env azure_subscription_id -> active Azure CLI subscription`, and updated interactive `create` and `update` so they prompt for subscription selection before any Azure-backed discovery when no CLI subscription override is supplied.
- Updated the shared Azure CLI wrapper, diagnostics, create/update review summaries, `configure`, `list`, quick help, README, AGENTS, and `.env.example` so the resolved subscription context is visible, `azure_subscription_id` is documented as the repo-local default selector, and Azure-touching commands now state explicitly that `az login` is required.

### Fixed
- Fixed the shared `subscription-id` option validator so it only enforces a value when the option is actually present, instead of tripping unrelated command contracts that omitted `-s`.
- Fixed subscription precedence resolution so stale in-memory overrides no longer outrank `.env azure_subscription_id` during later command resolution or smoke testing.
- Fixed the smoke contract for subscription-aware commands so `delete` is validated with its required `--target` option while `task` and `help` continue to reject subscription targeting.

### Tests
- Revalidated the non-live gate with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.13.299] - 2026-03-13

### Changed
- Reworked `configure` into the managed target-selection and `.env` synchronization command: it now selects one clagnos-managed VM target, reads actual Azure state, validates optional platform flags against the real VM OS type, and writes only target-derived values back to `.env`.
- Added the new read-only `list` command and removed the public `group` command. Managed inventory is now exposed through `clagnos list` with `--type=group,vm,disk,vnet,subnet,nic,ip,nsg,nsg-rule` plus optional exact `--group` filtering.
- Updated interactive `create` so the VM OS choice is prompted first whenever `--windows` or `--linux` is omitted, and the platform-specific size, disk, and image defaults now flow from that explicit selection instead of silently reusing `.env VM_OS_TYPE`.

### Fixed
- Fixed the configure command entry so it no longer relies on the retired step-1 precheck/preview path or the removed `Get-ClagnosConfigPersistenceMap` helper.
- Fixed the command surface cutover by removing the retired `group` command files and shared `select` option module from the runtime manifest after the new `list` command took over the managed inventory role.

### Tests
- Revalidated the non-live gate with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.13.298] - 2026-03-13

### Changed
- Split the interactive lifecycle contract more strictly: `create` now stays fresh-only with new managed target generation, while `update` stays existing-target-only with managed-target validation and review-first execution through the shared main workflow.
- Hardened managed naming so resource groups keep a globally increasing `gX` suffix and every generated managed resource now consumes a globally unique `nX` suffix across all resource types without reusing ids.
- Moved `108-install-sysinternals-suite` and `130-autologon-manager-user` into the Windows `vm-init` catalog and kept the Windows main flow restart barrier between `vm-init` and `vm-update`.
- Reworked the Windows startup, public-shortcut, copy-user, Docker Desktop, Ollama, and snapshot-health tasks around live-VM findings so orphan managed shortcuts are skipped, startup artifacts are verified after writing, excluded profile-cache targets are pruned safely on reruns, and the health snapshot reports richer target-health, startup, Docker, Ollama, WSL, and autologon state.

### Fixed
- Fixed fresh create naming so configure-time managed resource-group generation now uses the real next global `gX` suffix instead of falling back to `g1` when the template still contains `{N}`.
- Fixed fresh create resource naming so persisted `.env` managed resource names no longer leak into new-create planning unless they were explicitly overridden for the current invocation.
- Fixed the managed `nX` allocator registration path so a logical resource can re-register its own reserved id idempotently without falsely colliding with itself.
- Fixed `10005-copy-settings-user.ps1` rerun safety by pruning stale excluded target files and directories before and after the robocopy branch, preventing stale locked-cache content from surviving into later verification steps.
- Fixed the autologon health contract so Sysinternals Autologon and visible Winlogon password storage are both reported accurately instead of producing false negative health output.

### Tests
- Revalidated the non-live gate with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, and `tests/bash-syntax-check.ps1`.
- Revalidated the hardened live Windows path with isolated task/task-group runs on `rg-examplevm-sec1-g1/examplevm`, including `exec --init-task=108`, `exec --init-task=130`, `exec --update-task=114`, `exec --update-task=116`, `exec --update-task=10001`, `exec --update-task=10002`, `exec --update-task=10005`, and `exec --update-task=10099`, plus non-mutating `create --step=configure` and `update --step=configure` contract probes.

## [2026.3.13.297] - 2026-03-13

### Changed
- Realigned the maintained help and README contract with the current create/update/resize behavior: `create` is documented as fresh-only, `update` is documented as existing-managed-target only, `create --auto` and `update --auto` now document their strict required option sets explicitly, and the review-first UX now states that only `group`, `vm-deploy`, `vm-init`, and `vm-update` ask `yes/no/cancel` while `configure` and `vm-summary` always render.
- Updated the maintained naming contract so managed resource groups now describe globally increasing `gX` suffixes and managed resources now describe globally increasing `nX` suffixes that are never reused across resource types.
- Tightened the resize help/docs wording so `--disk-size` is documented as requiring exactly one intent flag, with `--shrink` remaining a non-mutating Azure-guidance path.

### Tests
- Refreshed the smoke and documentation-contract checks to enforce the fresh-only create contract, existing-only update contract, strict auto-mode wording, global `gX`/`nX` naming language, and the current autologon health snapshot contract without expecting yet-unimplemented `DefaultPasswordPresent` output from the health task.

## [2026.3.12.296] - 2026-03-12

### Fixed
- Fixed `tests/clagnos-smoke-tests.ps1` so the CI-facing smoke doubles now shadow runtime functions in the active test scope instead of leaking to the real Azure/.env-backed implementations through `global:` declarations.
- Restored the non-live smoke gate to the expected fast path by removing the accidental real Azure CLI calls from the create, update, resize, reapply, and hibernate-stop smoke scenarios that GitHub Actions was waiting on.

### Tests
- Revalidated the full non-live gate with `tests/clagnos-smoke-tests.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/code-quality-check.ps1`, `tests/bash-syntax-check.ps1`, and `tests/pre-commit-release-doc-check.ps1`.

## [2026.3.12.295] - 2026-03-12

### Fixed
- Fixed `.github/workflows/quality-gate.yml` so every checkout now uses `fetch-depth: 0`, allowing the commit-count-based changelog and release-notes contract to validate correctly on GitHub Actions instead of seeing a shallow-history count of `1`.

### Release
- Published the repository to the public GitHub remote, pushed aligned `main` and `dev`, and removed all remaining local backup/preserve branches so only the two canonical branches remain.

## [2026.3.12.294] - 2026-03-12

### Fixed
- Closed the remaining live Windows publish blockers by raising the tracked timeout budgets for `104-install-node-system` and `111-install-edge-browser`, then hardening both tasks with bounded post-install verification so first-time installs can finish without weakening the healthy-install contract.
- Hardened `10005-copy-settings-user.ps1` so `AppData\Local\Microsoft\Windows\WebCacheLock.dat` is excluded consistently during profile replication and the robocopy fallback now tolerates the same live lock signature across the observed error return codes.

### Tests
- Revalidated the non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/bash-syntax-check.ps1`.
- Revalidated live Windows behavior on `rg-examplevm-sec1-g1/examplevm` with isolated `exec --update-task=104`, `exec --update-task=111`, and `exec --update-task=10005` runs, then a full `update --auto --windows --perf` pass that finished `success=45, failed=0, warning=0, error=0, reboot=0`, followed by `show`, `do --vm-action=status`, `ssh --test`, and `rdp --test`.

## [2026.3.12.293] - 2026-03-12

### Added
- Added explicit managed OS disk resize intent flags for `resize`: `--disk-size=<number>gb|mb --expand` now performs the supported in-place OS disk growth path, while `--disk-size=<number>gb|mb --shrink` stops before mutation and prints supported rebuild and migration alternatives because Azure does not support shrinking an existing managed OS disk in place.
- Standardized destructive rebuild guidance around an explicit `delete` followed by `create` flow so rebuild intent stays separate from the default fresh-create path.

### Changed
- Renamed the public step selectors for `create` and `update` from `--single-step`, `--from-step`, and `--to-step` to `--step`, `--step-from`, and `--step-to`, then removed the retired forms from the parser, manifest, parameter modules, help output, README examples, and smoke coverage.
- Continued the command-surface refresh around `create` and `update`, keeping destructive rebuild guidance explicit while the managed-target contract moved toward the current fresh-only `create` model.
- Changed `update` so it now requires an existing managed resource group and existing VM before orchestration begins, and the VM deploy stage now redeploys an existing VM after the create-or-update pass.
- Refreshed README, AGENTS, changelog wording, release notes, and prompt-history normalization so the maintained documentation now reflects the current release surface with stronger business-value, developer-benefit, and publish-readiness guidance.

### Tests
- Revalidated the non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.12.291] - 2026-03-12

### Changed
- Synchronized the publish-facing repository surface with the current release-readiness contract by updating the GitHub issue templates, pull-request template, README guidance, contributing guidance, and support guidance around live Azure acceptance and public release reporting.
- Extended `.github/workflows/quality-gate.yml` with an explicit `documentation-contract` job so the existing documentation contract check now runs in GitHub Actions alongside the rest of the non-live gate.
- Hardened `Invoke-ClagnosVmCreateStep` so transient non-zero `az vm create` results now trigger a bounded VM-presence probe before failing, reducing false negatives when Azure finishes the deployment shortly after the CLI returns a temporary error code.

### Tests
- Revalidated the non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/bash-syntax-check.ps1`.

## [2026.3.12.290] - 2026-03-12

### Changed
- Completed a second Windows `vm-update` performance-tuning pass focused on the remaining slow paths from live perf logs, using bounded noninteractive behavior instead of repeated waits and retries.
- Reworked `114-install-docker-desktop.ps1` again so already-installed Docker Desktop no longer burns time on daemon retry probes inside SSH sessions. The task now verifies the client, starts Docker Desktop once, and immediately registers an interactive `RunOnce` start instead of retrying engine readiness in a noninteractive guest session.
- Reworked `121-install-whatsapp-system.ps1` so it checks fast local Store-registration evidence before expensive `winget list` calls and short-circuits immediately when a deferred `RunOnce` install is already registered, preventing the same failed Store install attempt from being repeated on every update run.
- Shortened the registry-hive unload waits in `10001-configure-apps-startup.ps1` and `10099-capture-snapshot-health.ps1`, and shortened the Task Manager / Explorer settle waits in `10003-configure-ux-windows.ps1`, keeping those tasks bounded without retry-heavy idle time.
- Updated the Windows smoke contract so Docker Desktop is now validated against the new bounded noninteractive deferred-start model rather than the retired daemon-probe loop.

### Performance
- Revalidated live Windows behavior on `rg-examplevm-sec1-g1/examplevm` and confirmed concrete improvements: `114-install-docker-desktop` dropped from about `16.2s` to about `3.2s`, `121-install-whatsapp-system` dropped from about `9.8s` to about `3.5s` on deferred reruns, `10099-capture-snapshot-health` dropped from about `9.8s` to about `6.1s`, and the full `vm-update` step dropped from about `234.7s` to about `198.0s`.

### Tests
- Revalidated live Windows task behavior with targeted `exec --update-task=114`, `121`, `10003`, `10001`, and `10099` runs plus a full `update --step=vm-update --auto --windows --perf` pass on `rg-examplevm-sec1-g1/examplevm`.
- Revalidated the non-live gate with `tests/powershell-compatibility-check.ps1` and `tests/clagnos-smoke-tests.ps1`.

## [2026.3.12.288] - 2026-03-12

### Added
- Added `do --vm-action=hibernate-stop`, which resolves the managed VM target, verifies SSH reachability, runs `shutdown /h /f` through the repo-managed pyssh path, and waits until the guest is no longer running without Azure deallocation.

### Changed
- Renamed the Azure-backed hibernation action from `do --vm-action=hibernate` to `do --vm-action=hibernate-deallocate` so the public command surface now states explicitly that Azure hibernation still uses the deallocation-based path.
- Updated the `do` parser, interactive action picker, validation rules, CLI help, README examples, and smoke coverage so the old `hibernate` action is rejected with a direct migration hint to `hibernate-deallocate` or `hibernate-stop`.

### Tests
- Revalidated the non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/clagnos-smoke-tests.ps1`.

## [2026.3.12.287] - 2026-03-12

### Changed
- Tuned `114-install-docker-desktop.ps1` for noninteractive Windows guest sessions by replacing the old longer daemon wait path with two short bounded `docker version` probes, removing the blocking `docker info` readiness gate, shortening stale-installer cleanup waits, and falling back immediately to a deferred interactive `RunOnce` start when the engine is not yet ready.
- Tuned `10005-copy-settings-user.ps1` by replacing the old fixed five-second wait with a short settle loop that watches user sessions and processes, cutting registry-hive unload retries and wait intervals, and keeping the copy path bounded instead of retry-heavy.
- Fixed `10002-create-shortcuts-public-desktop.ps1` so Public Desktop inspection no longer exits the whole task early on unrelated shortcut entries, added a no-op fast path for already-normalized desktops, and expanded duplicate cleanup coverage to installer-created `AnyDesk`, `Windscribe`, `VLC media player`, `iTunes`, `IObit Unlocker`, and `NVDA` shortcuts.
- Removed every `--force` command-line flag from tracked Windows `vm-update` task scripts and shifted the install tasks to explicit install-if-missing / skip-if-healthy behavior, including the winget bootstrap path which now avoids forceful source reset and uses only one bounded source-update recovery attempt.

### Tests
- Revalidated the non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/clagnos-smoke-tests.ps1`.
- Revalidated live Windows behavior on `rg-examplevm-sec1-g1/examplevm` with targeted `exec --update-task=114`, `exec --update-task=10005`, `exec --update-task=10002`, `exec --update-task=10099`, and a full `update --step=vm-update --auto --windows` pass. The tuned tasks now complete quickly, and the latest Public Desktop readback leaves only the intentionally unmanaged local-only accessibility shortcuts outside the tracked managed set.

## [2026.3.12.286] - 2026-03-12

### Added
- Restored tracked Public Desktop shortcuts `q1SourTimes`, `s15{TitleCase(company_name)} Web`, and `s16{TitleCase(company_name)} Blog` so the managed shortcut set again owns those browser entry points explicitly.

### Changed
- Renamed the tracked Windows Public Desktop web/app labels from the old Turkish `Kurumsal`/`Bireysel` wording to the approved English `Business`/`Personal` contract, including the approved brand-specific overrides such as `s18NextSosyal Business`, `r13CicekSepeti Business`, `r14CicekSepeti Personal`, `r17PTTAVM Business`, and `r18PTTAVM Personal`.
- Renamed the remaining approved quick-access labels to `m1Digital Tax Office`, `q4eGovernment`, `q6AJet Flights`, `q7TCDD Train`, and `q8OBilet Bus`, while keeping `q2Spotify` and `q3Netflix` unchanged.
- Reworked `10002-create-shortcuts-public-desktop` so Chrome profile routing is metadata-based instead of name-text-based, and both `company_name` and `employee_email_address` local-part values are normalized to lowercase before being written into `--profile-directory`.
- Hardened Public Desktop normalization so the tracked shortcut task now removes semantic duplicates by name alias, target executable, and browser destination matching for installer-created overlaps such as Google Chrome, Microsoft Edge, AnyDesk, and Visual Studio 2022, while preserving unrelated unmanaged Public Desktop shortcuts.
- Moved `clagnos-interactive-session-helper.ps1` from `tools/windows/` to `tools/scripts/` and updated runtime asset resolution to use the new helper location without changing the guest-side remote helper path.
- Updated the tracked health snapshot, `.env.example`, README, AGENTS contract, and smoke coverage to enforce the new English shortcut labels, lowercase Chrome profile normalization, restored shortcuts, and semantic duplicate-cleanup model.

### Tests
- Revalidated the non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/clagnos-smoke-tests.ps1`.

## [2026.3.12.284] - 2026-03-12

### Added
- Added `clagnos do --vm-action=reapply`, which calls `az vm reapply` for the resolved managed VM target and then prints a refreshed lifecycle status snapshot.

### Changed
- Expanded the `do` command contract so parser hints, interactive action selection, CLI help, and README examples all include `reapply` as a first-class lifecycle action.
- Kept `reapply` available as the Azure repair path even when provisioning is not currently in the succeeded state, while the existing power-action validation rules remain unchanged for `start`, `restart`, `stop`, `deallocate`, and `hibernate`.

### Tests
- Revalidated the full non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/clagnos-smoke-tests.ps1`.

## [2026.3.12.283] - 2026-03-12

### Added
- Added committed `employee_email_address` and `employee_full_name` config placeholders, plus runtime token materialization for employee identity and generic host autostart discovery data used by operator-local flows.
- Added tracked Windows task `132-install-vs2022community.ps1` and extended tracked npm bootstrap task `115-install-npm-packages-global.ps1` to install the GitHub Copilot CLI prerequisite.

### Changed
- Expanded the tracked Public Desktop shortcut contract so Windows update now creates `i1Internet Kurumsal`, `i2Internet Bireysel`, `r11-r22`, `k3Github Copilot CLI`, `v1VS2022Com`, and the renamed `t10Azd CLI`, while `e1Mail` and every Chrome shortcut labeled `Bireysel` now derive their personal profile routing from the employee email local-part.
- Updated tracked shortcut health capture, smoke assertions, README contract, and engineering contract rules so the new employee-based Chrome profile behavior, renamed shortcuts, new task timeouts, and new prerequisite tasks are all enforced explicitly.
- Shifted the tracked startup/profile-copy surface to a generic local-accessibility ownership model by removing vendor-specific behavior from startup mirroring, tracked profile-copy exclusions, tracked startup configuration, and maintained docs; tracked code now only provides generic host autostart discovery and unmanaged-shortcut preservation for one private local-only accessibility flow.

### Tests
- Revalidated the full non-live gate with `tests/code-quality-check.ps1`, `tests/documentation-contract-check.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/clagnos-smoke-tests.ps1`.
- Completed live Windows acceptance on `rg-examplevm-sec1-g1/examplevm`: isolated `exec --update-task=1001..1005` reruns for one private local-only accessibility flow, a full `update --step=vm-update --auto --windows` pass with `success=45, failed=0, warning=0, error=0, reboot=0`, `do --vm-action=restart`, SSH/RDP connectivity checks, and post-reboot guest readback confirming the manager startup shortcut, automatic utility service, active console session, and running local accessibility processes.

## [2026.3.11.282] - 2026-03-11

### Changed
- Changed the `Invoke-ClagnosMain` startup banner so `script description:` is rendered on a single line instead of opening a multi-line bullet block.
- Added an explicit live release-acceptance requirement to `README.md`, `AGENTS.md`, and the documentation contract: release-readiness now requires a real create/update/status/show/connection verification cycle when live confidence is part of the claim.

### Fixed
- Fixed the post-deploy provisioning readiness check so existing-VM feature verification now reads `az vm get-instance-view` from `instanceView.statuses` and honors the top-level `provisioningState`, removing the false blank retry loop seen during live create/update runs.
- Fixed `10005-copy-settings-user` so live Windows update runs now classify required profile roots separately, skip deterministic blocker aliases and reparse-point shell paths, tolerate missing HKCU source branches during assistant hive seeding, and ignore access/in-use failures only for best-effort profile artifacts instead of failing the whole stage.

### Tests
- Revalidated the runtime and docs with `tests/clagnos-smoke-tests.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/documentation-contract-check.ps1`.
- Completed a live Windows acceptance rerun with `clagnos update --auto --windows`; the full natural-order `vm-update` stage finished `success=41, failed=0, warning=0, error=0, reboot=0`.

## [2026.3.11.281] - 2026-03-11

### Changed
- Removed the transitional root loader layer from `modules/` so `clagnos.ps1` now loads a single ordered `modules/clagnos-runtime-manifest.ps1` and dot-sources the refactored leaf files directly.
- Deleted the old root runtime wrapper files under `modules/core/`, `modules/config/`, `modules/tasks/`, `modules/ui/`, and `modules/commands/`, so the active runtime now executes only the modern modular tree.
- Refreshed the smoke contract and current architecture documentation so they enforce the manifest-based direct-load model and fail fast if any legacy root loader path reappears.

### Tests
- Revalidated the direct-load cutover with `tests/code-quality-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/powershell-compatibility-check.ps1`.

## [2026.3.11.280] - 2026-03-11

### Changed
- Refactored the `modules/` runtime into compatibility loaders plus a deeper domain tree under `modules/core/`, `modules/config/`, `modules/commands/`, `modules/ui/`, and `modules/tasks/`, keeping the existing root import paths and public function surface intact while moving implementation into smaller leaf files.
- Split the public command runtime by command ownership so each supported command now lives under its own subtree with `entry.ps1`, `contract.ps1`, `runtime.ps1`, and command-scoped `parameters/` files, while shared create/update orchestration now lives in dedicated `context`, `steps`, `features`, `pipeline`, and shared-runtime helpers.
- Restricted `modules/ui/` to prompts, selection flows, show/report rendering, and connection presentation concerns, and moved non-UI command/runtime logic out of the former monolithic UI/runtime paths.
- Updated the operator and release documentation to describe the new modular runtime layout and the compatibility-loader contract accurately.

### Tests
- Revalidated the refactor with `tests/code-quality-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/powershell-compatibility-check.ps1`, and refreshed the smoke assertions so they target the new leaf-file locations instead of the old monolithic root files.

## [2026.3.11.279] - 2026-03-11

### Added
- Added non-interactive connection test modes for `clagnos ssh --test` and `clagnos rdp --test`, so the repo can validate SSH authentication and RDP reachability without launching external clients.

### Changed
- Changed post-deploy feature handling so `create`, `update`, and `set` now treat `VM_ENABLE_HIBERNATION=true` and `VM_ENABLE_NESTED_VIRTUALIZATION=true` as verified desired outcomes: hibernation is checked through Azure instance state, while nested virtualization is validated from inside the running guest instead of relying on the removed single-VM Azure property path.
- Changed `clagnos show` so password-bearing config values are redacted in the rendered report and running-VM inventory now includes guest-validated nested-virtualization status plus supporting evidence.
- Refreshed the README and documentation contract to document the natural `vm-init` / `vm-update` order as builtin `initial`, builtin `normal`, local untracked tasks, then builtin `final`, and to describe the new connection-test and feature-validation behavior accurately.
- Hardened the Windows interactive-session helper and Store-backed tasks so Be My Eyes and iCloud now detect whether an interactive desktop is available, fall back to deferred `RunOnce` registration when needed, and use interactive-token execution when a user desktop is already active.
- Hardened several Windows update tasks and UX helpers by quieting registry hive load/unload noise, improving shell-sort validation, excluding unstable Ollama WebView cache paths from profile copies, retrying or settling installer descendants where needed, and normalizing non-fatal native exit codes in Docker Desktop and AnyDesk flows.
- Raised the tracked timeouts for `126-install-be-my-eyes` and `10005-copy-settings-user` to match the longer real-world execution windows observed in the refreshed task implementations.

### Fixed
- Fixed `az vm create` argument selection during create-or-update paths so security-type create arguments are omitted automatically when the target VM already exists, avoiding Azure failures on existing managed VMs.

### Tests
- Kept the smoke and documentation contracts aligned with the new runtime surface, including connection-test parsing, show redaction, nested-virtualization guest validation, task-order guarantees, and the hardened Windows task contracts.

## [2026.3.11.278] - 2026-03-11

### Fixed
- Fixed an avoidable compatibility-matrix slowdown in `tests/clagnos-smoke-tests.ps1`: the two post-deploy feature-enable smoke tests now stub `az vm get-instance-view` as `Provisioning succeeded` immediately, so the compatibility run no longer burns minutes inside artificial provisioning waits after the new feature-verification gate was added.

### Tests
- Revalidated the compatibility path with `tests/clagnos-smoke-tests.ps1` and `tests/powershell-compatibility-check.ps1`; the smoke suite now completes in seconds and the compatibility matrix no longer times out due to the synthetic wait loop.

## [2026.3.11.277] - 2026-03-11

### Added
- Added short-help alias support across the public CLI so `clagnos -h` and `clagnos <command> -h` now work alongside the existing `--help` contract.
- Added a publish-facing GitHub community surface with `CONTRIBUTING.md`, `SUPPORT.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates, and a pull-request template aligned to the repo's contact-first contribution model and custom non-commercial license.

### Changed
- Refreshed the public help and README contract so command examples, global options, support paths, and publish-facing workflow guidance now reflect the current runtime and the new `-h` shorthand.
- Extended `.github/workflows/quality-gate.yml` so GitHub Actions now also runs the non-live `tests/clagnos-smoke-tests.ps1` suite in addition to the existing static and compatibility checks.
- Redacted publish-inappropriate literals in maintained history docs, replacing environment-specific VM names, profile names, local paths, and similar concrete examples with neutral placeholders while preserving chronology and technical meaning.
- Normalized tracked Linux `.sh` files to LF and pinned that expectation in `.gitattributes` so the repository's bash-syntax gate passes consistently across environments.

### Tests
- Expanded CLI parse and help smoke coverage for `-h`, updated documentation-contract checks for the new community files and GitHub workflow coverage, and kept the existing non-live validation gates aligned with the refreshed publish surface.

## [2026.3.11.276] - 2026-03-11

### Changed
- Changed `10002-create-shortcuts-public-desktop` from a full Public Desktop mirror into a managed-shortcut reconcile pass, so it now removes and recreates only the tracked shortcut names while preserving unmanaged Public Desktop entries such as local-only accessibility shortcuts; the same task still clears the manager, assistant, and default desktop roots.
- Restored host startup-profile discovery in `clagnos-core-foundation`, replaced the static Windows auto-start snapshot with host-driven method mirroring in `10001-configure-apps-startup`, and added a guest compatibility layer for LocalMachine startup apps so the guest now applies the host-observed startup surfaces and approval state instead of relying on a hard-coded list.
- Expanded `10099-capture-snapshot-health` so Windows late-stage health snapshots now inventory unmanaged Public Desktop shortcuts and host-driven startup entries instead of treating extra Public Desktop shortcuts as unexpected removable artifacts.

### Tests
- Extended the Windows smoke and compatibility contracts so the host startup-profile token flow, the managed-only Public Desktop cleanup behavior, the unmanaged shortcut inventory, and the startup compatibility scaffolding are all enforced together with the existing task contracts.

## [2026.3.11.275] - 2026-03-11

### Changed
- Expanded `10002-create-shortcuts-public-desktop` so the managed Public Desktop set now also adds the requested `g1-g4` developer links and `q2-q8` quick-access web shortcuts, all using the same Chrome launcher contract as `i1Internet`.
- Expanded `10099-capture-snapshot-health` so the late-stage Windows health snapshot now inventories the new `g` and `q` shortcut names together with the rest of the managed Public Desktop set.

### Tests
- Extended the Windows public-desktop smoke contract so the new shortcut names and URLs are enforced together with the existing launcher fragments and health inventory expectations.

## [2026.3.11.274] - 2026-03-11

### Changed
- Added the tracked Windows `130-autologon-manager-user` update task immediately after `129-configure-unlocker-io`, moved the tracked iCloud install task to `131-install-icloud-system`, and configured the new task to validate the `manager` credentials locally before calling Sysinternals `autologon /accepteula <user> . <password>`.
- Expanded `10099-capture-snapshot-health` so Windows late-stage health snapshots now inventory the Winlogon autologon state for the `manager` user in addition to the existing UX and Public Desktop state.

### Tests
- Extended the Windows tracked-task timeout contract, the install-task contract, and the late-stage health contract so the new autologon task, the renumbered iCloud task, and the new autologon health readback are all enforced.

## [2026.3.11.273] - 2026-03-11

### Changed
- Expanded `10002-create-shortcuts-public-desktop` again so the managed Public Desktop set now also restores the requested `e1`, `m1`, `n1`, `r1-r10`, and `u7Network and Sharing` shortcuts while preserving the existing Chrome-profile, run-maximized, run-as-admin, full-mirror, and per-user desktop cleanup contracts.

### Tests
- Extended the Windows public-desktop smoke contract and health inventory expectations so the new `e/m/n/r/u7` shortcuts and their launcher fragments are validated together with the existing Public Desktop set.

## [2026.3.11.272] - 2026-03-11

### Changed
- Moved the per-user desktop cleanup into `10002-create-shortcuts-public-desktop` itself, so the Public Desktop mirroring task now also removes lingering entries from the manager, assistant, and default desktop roots instead of relying on later tasks to restore that contract.

### Tests
- Tightened the Windows public-desktop smoke contract so `10002-create-shortcuts-public-desktop` must own the manager/assistant/default desktop cleanup path in addition to the Public Desktop mirror.

## [2026.3.11.271] - 2026-03-11

### Changed
- Updated `10002-create-shortcuts-public-desktop` so `z1Google Account Setup` now launches Chrome through `C:\Windows\System32\cmd.exe /c start "" ...` with the requested shared Public Desktop Chrome user-data directory and direct `chrome://settings/syncSetup` target, instead of binding the shortcut directly to `chrome.exe`.

### Tests
- Tightened the Windows public-desktop smoke contract so `z1Google Account Setup` must target `cmd.exe` and carry the requested `start "" "chrome.exe" ... syncSetup` argument shape.

## [2026.3.11.270] - 2026-03-11

### Added
- Added the tracked Windows update task `130-install-icloud-system` so the Store-backed iCloud install now follows the repo's unattended `winget` pattern and resolves `iCloudHome.exe` for shortcut and health-readback use.

### Changed
- Reworked the Windows final update flow so `10002-create-shortcuts-public-desktop`, `10003-configure-ux-windows`, `10005-copy-settings-user`, and `10099-capture-snapshot-health` now enforce the new public-desktop contract: `company_name` is required with no `VM_NAME` fallback, the shortcut set uses the requested 1-based naming scheme, managed `.lnk` files are rebuilt with full Public Desktop mirroring, and per-user desktops are kept empty.
- Expanded the public shortcut manifest to the requested final `a/b/c/d/i/k/o/s/t/u/v/z` layout, including iCloud, dynamic `s15/s16` company shortcuts, the new `s17/s18` web entries, updated CLI targets, NVDA hotkey handling, run-maximized defaults, run-as-admin link flags, and `%UserProfile%` start-in handling for console shortcuts.
- Extended Windows UX tuning to disable System Restore and existing shadow copies, keep RDP NLA off for maximum compatibility, suppress `desktop.ini` / `Thumbs.db` artifacts on known desktop roots, hide shell-managed desktop icons in favor of custom `u1/u2/u3` shortcuts, and reinforce Explorer details/no-group defaults across seeded user hives.
- Reworked `10005-copy-settings-user` so the assistant/default profile propagation now uses deterministic hive-based registry seeding and stricter file-copy exclusions instead of the slower interactive HKCU path, and raised the late-stage Windows task timeouts to match observed exec runtimes.

### Documentation
- Updated `.env.example`, `README.md`, release history, and prompt history to reflect the required `company_name` contract and the new Windows UX/public desktop update behavior.

### Tests
- Expanded smoke and compatibility coverage for the iCloud task contract, the no-fallback `company_name` requirement, the final shortcut manifest and timeout values, and explicit hidden shell desktop icon propagation checks.
- Validated the Windows update changes live with isolated `exec` reruns of `130`, `10003`, `10002`, `10005`, and `10099`, plus idempotency reruns of `10002` and `10003`.

## [2026.3.11.269] - 2026-03-11

### Added
- Added the read-only `task` command so operators can list the real discovered `vm-init` and `vm-update` inventory in execution order, filter by stage, and inspect disabled tracked/local tasks before running orchestration.

### Changed
- Reworked the task-number contract across Windows and Linux so tracked tasks now use the shared bands `01-99` (`initial`), `101-999` (`normal`), and `10001-10099` (`final`), while intentionally local-only tasks use `1001-9999`.
- Renamed the tracked Linux init/update files and the tracked Windows update files to the new banded numbering scheme, including moving the Windows health snapshot task to `10099-capture-snapshot-health`.
- Updated tracked task catalogs on all four stage roots so they now carry explicit `taskType` values alongside the new band-aligned priorities and existing timeout values.
- Updated task discovery so local-only priority resolution now follows `script metadata -> filename task number -> deterministic auto-detect`, instead of treating local metadata as the only ordering source.
- Standardized tracked task fallback defaults end to end so missing catalog entries and catalog entries without explicit priority now resolve to `priority=1000`, while all missing timeout values continue to resolve to `180` for both tracked and local task paths.
- Updated runtime help, `exec` task selection, and the regional move health gate so variable-length task numbers now work consistently across direct execution, diagnostics, and move cutover validation.

### Documentation
- Updated `AGENTS.md` and `README.md` to document the new 2-5 digit task-number bands, the `task` command, and the revised tracked/local task-priority rules.

### Tests
- Refreshed smoke coverage for variable-length task selection, the new `task` command listing path, the new tracked Windows/Linux task names, and the updated local-task priority precedence.

## [2026.3.10.267] - 2026-03-10

### Changed
- Moved intentionally local-only stage tasks under `local/` and local-only disabled tasks under `local/disabled/`, while keeping tracked root tasks catalog-driven.
- Restored the Windows local accessibility asset layout under the update local subtree and kept local asset resolution relative to the local task file directory.
- Extended task discovery so stage roots now accept `local/*` and `local/disabled/*` script locations, ignore catalog state for local-only tasks, and fail fast on duplicate tracked/local task names.

### Documentation
- Updated the repository contract and operator guide to document the new `local/` / `local/disabled/` layout, the metadata-only behavior of local tasks, and the relative asset-resolution rule for local task payloads.

### Tests
- Refreshed smoke coverage for local-only task discovery, duplicate-name detection, nested-path rejection, and local asset resolution.
- Simplified `.gitignore` so stage-specific ignore rules now target only the init/update `local/` trees.

## [2026.3.10.266] - 2026-03-10

### Fixed
- Completed the Windows `vm-update` `31/32` swap by renaming the tracked task files as well as the catalog entries, so `31-configure-unlocker-io` now owns the IObit Unlocker task and `32-configure-apps-startup` now owns the startup-configuration task.

### Documentation
- Updated release history and prompt-history records to reflect the final `31=unlocker`, `32=app-startup` naming contract.

### Tests
- Updated smoke coverage so the tracked Windows update order and startup-task path assertions now target `31-configure-unlocker-io` and `32-configure-apps-startup`.

## [2026.3.10.265] - 2026-03-10

### Fixed
- Swapped the Windows `vm-update` execution priorities of `31-configure-apps-startup` and `32-configure-unlocker-io` so the unlocker task now runs first while both tasks keep their existing timeout values.

### Tests
- Updated smoke coverage so the tracked Windows update order assertion now expects `32-configure-unlocker-io` before `31-configure-apps-startup`.

## [2026.3.10.264] - 2026-03-10

### Changed
- Renamed the tracked Windows `vm-init` and `vm-update` scripts to the normalized `NN-verb-noun-target` pattern and rebuilt the tracked Windows update order around tooling-first early tasks plus the requested late-stage UX, user-settings, and health tasks.
- Moved selected private local-only Windows tasks and payloads out of source control while keeping them available on disk through ignored local-only files and script-local metadata.

### Refactoring
- Added generic script-local task metadata parsing for intentionally local-only Windows tasks, including `priority`, `enabled`, `timeout`, and asset declarations, while keeping tracked catalog values authoritative whenever both exist.
- Replaced the old task-specific Windows asset-copy special case with metadata-driven asset resolution so tracked runtime code no longer needs custom knowledge of local-only private payloads.
- Rewrote the active `main` and `dev` histories to remove the selected private local-only Windows paths and scrub their tracked textual references, while leaving the backup branches untouched.

### Documentation
- Updated `AGENTS.md`, `README.md`, `roadmap.md`, `CHANGELOG.md`, `release-notes.md`, and `docs/prompt-history.md` to describe the normalized Windows task naming scheme and the local-only metadata model without carrying the removed tracked identifiers.

### Tests
- Expanded smoke and documentation-contract coverage for normalized Windows task ordering, script-local metadata discovery, generic asset resolution, and the absence of the removed tracked task identifiers from the maintained repo surface.

## [2026.3.10.263] - 2026-03-10

### Fixed
- Simplified the `set` command so it now resolves the target VM directly instead of depending on the heavier Step-1 command runtime path, which removes unrelated configuration requirements from feature-toggle updates.
- Ensured `set` now persists the resolved `RESOURCE_GROUP`, `VM_NAME`, and any successfully applied `VM_ENABLE_HIBERNATION` / `VM_ENABLE_NESTED_VIRTUALIZATION` changes back into the local `.env` file.

### Documentation
- Updated `README.md` and command help text so the `set` command now explicitly documents its direct-target behavior and `.env` synchronization semantics.

### Tests
- Added smoke coverage that verifies `set` applies both Azure toggle updates, persists the changed values to `.env`, and keeps `.env` aligned even when one later toggle update fails after an earlier success.

## [2026.3.10.262] - 2026-03-10

### Changed
- Changed the committed pyssh client default so `PYSSH_CLIENT_PATH` now resolves to the repo-relative `tools/pyssh/ssh_client.py` path instead of starting empty in the `.env` contract.
- Standardized the default NSG rule naming prefix across the repo on `nsg-rule-`, including the committed template defaults and sample/test contracts.
- Added shared `.env` feature-intent keys `VM_ENABLE_HIBERNATION` and `VM_ENABLE_NESTED_VIRTUALIZATION` so create/update flows can explicitly enable or skip those post-deploy feature paths with `true` or `false`.

### Refactoring
- Updated orchestration and UI runtime defaults to consume the shared non-empty pyssh client default instead of duplicating empty `PYSSH_CLIENT_PATH` fallbacks.
- Extended post-deploy feature enablement so hibernation and nested virtualization can now be skipped cleanly when the shared `.env` feature toggles are set to `false`, while preserving the current Azure enablement path when they are `true`.

### Documentation
- Updated `README.md`, `AGENTS.md`, and `.env.example` to document the new shared VM feature toggles, the non-empty pyssh client default, and the `nsg-rule-` naming contract.

### Tests
- Expanded smoke and documentation checks to enforce the new pyssh default path, the shared feature-toggle env keys, and the `nsg-rule-` template contract.

## [2026.3.10.261] - 2026-03-10

### Changed
- Removed shared runtime fallback defaults for committed VM identity and credential values such as the old sample VM names and demo passwords; non-interactive flows now fail fast when `VM_NAME`, `VM_ADMIN_USER`, `VM_ADMIN_PASS`, `VM_ASSISTANT_USER`, or `VM_ASSISTANT_PASS` are missing or left on placeholder values.
- Centralized shared default resolution for SSH port, RDP port, and default TCP port lists so the orchestration and UI runtimes stop duplicating mutable network defaults.
- Changed `tools/install-pyssh-tool.ps1` so its optional test-host derivation now depends only on real `.env` values instead of inventing a committed VM/region fallback.

### Documentation
- Clarified the configuration split across `AGENTS.md`, `README.md`, and `.env.example`: app-wide identity, secrets, and reusable operator overrides belong in `.env`, while task-only literals belong in a clearly labeled config block at the top of the owning task script.
- Updated `.env.example` to require explicit VM identity and credential placeholders, removed the old committed password examples, and documented `company_name` with a neutral example.

### Refactoring
- Introduced shared config-validation helpers in `modules/core/clagnos-core-foundation.ps1` so orchestration and UI contexts can reject empty or placeholder-sensitive values consistently.
- Refactored key Windows update tasks to move task-specific constants into top-of-file config blocks instead of scattering mutable literals through task bodies, including private local-only accessibility work, Ollama, Docker Desktop, VS Code, Be My Eyes, OneDrive, auto-start apps, and public desktop shortcuts.
- Moved the repo-managed Windows public web-shortcut bundles into the shortcut task's local config section so company-specific and user-specific web targets are isolated from shared runtime code.

### Tests
- Expanded smoke coverage to verify the new required-config helper behavior, confirm that shared runtime modules no longer carry the old personal/demo defaults, and align Docker Desktop task assertions with the new task-local config structure.

## [2026.3.10.260] - 2026-03-10

### Documentation
- Rewrote `README.md` into a much broader operator and contributor manual with a hierarchical table of contents, quick-start flow, architecture narrative, command guide, task model, troubleshooting guidance, developer workflow notes, and license/sponsorship coverage.
- Reworked `roadmap.md` around business value, relaxed delivery horizons, explicit promotion rules, and concrete done criteria.
- Added a root `LICENSE` file with the repository's custom non-commercial terms, including learning/teaching/evaluation allowance, private non-commercial modification allowance, commercial-use restrictions, and sponsorship/contact language.
- Updated `AGENTS.md` so maintained docs, help text, comments, and user-facing runtime wording must stay in English, while explicit literal display-label exceptions remain allowed.
- Switched `docs/prompt-history.md` from a raw-language ledger to an English-normalized ledger and translated the existing historical entries into English while preserving structure and chronology.

### Tests
- Added `tests/pre-commit-release-doc-check.ps1` and wired it into `.githooks/pre-commit` so repo-changing staged work now requires `CHANGELOG.md` and `release-notes.md` in the same final change set, without recursing on release-history-only updates.
- Expanded `tests/documentation-contract-check.ps1` to require `LICENSE`, enforce the English documentation contract, validate the English-normalized prompt-history rule, and confirm the pre-commit release-doc gate plus the current GitHub Actions PowerShell compatibility entrypoint.

### Chores
- Updated `tools/enable-git-hooks.ps1` to describe the stronger pre-commit gate accurately.
- Fixed `.github/workflows/quality-gate.yml` to use `tests/powershell-compatibility-check.ps1` instead of the removed `tests/powershell-matrix.ps1`.

## [2026.3.10.259] - 2026-03-10

### Features
- Added a new `do` operator command for `status`, `start`, `restart`, `stop`, `deallocate`, and `hibernate` actions against one managed VM.
- Made the new `do` command state-aware so it inspects Azure power/provisioning/hibernation state before mutating and exits politely with a non-zero code when the requested action is not valid for the current VM state.
- Added Windows `vm-update` install tasks `27-install-itunes-system`, `28-install-be-my-eyes`, `29-install-nvda-system`, `13-install-edge-browser`, `26-install-vlc-system`, `30-install-rclone-system`, `21-install-onedrive-system`, and `22-install-google-drive`, each following the existing repo pattern of bounded `winget` install plus explicit post-install verification.
- Added Windows `vm-update` task `19-install-codex-app` to install the Store-backed Codex desktop app through `winget install codex -s msstore`, verify it via AppX/StartApps/winget readback, and register a deferred RunOnce retry when the noninteractive Store session cannot complete immediately.
- Added Windows `vm-update` task `32-configure-apps-startup` to apply a static snapshot of the current approved auto-start application set on the guest VM by creating machine startup shortcuts for Docker Desktop, Ollama, OneDrive, Teams, one private local-only accessibility launcher, and iTunesHelper.

### Fixes
- Hardened `32-configure-apps-startup` after isolated live `exec` validation showed that existing startup shortcuts could fail approval when `HKLM\...\StartupApproved\StartupFolder` was missing: the task now creates the missing parent/leaf registry keys before marking shortcuts enabled, so reruns succeed cleanly against already-provisioned desktops.
- Replaced the Windows public-desktop Chrome shortcut profile binding so repo-managed web shortcuts now resolve `--profile-directory` from `.env` `company_name` instead of `VM_NAME`, while still falling back to `VM_NAME` if the new key is left empty.
- Switched both `move` and `set` to the `--vm-name` contract and removed the last public `--vm` usage from those commands.
- Hardened the snapshot-based region-move path so it now deallocates the source VM before snapshot creation, validates that the source resource group is safe for automatic purge, creates target-region public IPs with explicit zonal intent to avoid Azure CLI warning noise, attaches copied OS disks without invalid admin-credential flags, and preserves hibernation flags on the target disk and VM.
- Tightened the move cutover gate so the post-target `37-capture-snapshot-health` validation now runs through strict task-outcome semantics instead of allowing warning-mode continuation to delete the old source group.
- Increased the Windows `37-capture-snapshot-health` catalog timeout from `10s` to `30s` after live regional-move validation on `swedencentral` showed that the old bound could produce false timeout warnings during the target health gate.
- Restored `do --vm-action=hibernate` as the single public hibernation action while keeping the underlying Azure behavior unchanged: hibernation still runs through Azure's deallocation-based hibernate path.
- Made `ssh` and `rdp` state-aware so they now refuse politely when the target VM is not running and point operators to `clagnos do --vm-action=start`.
- Updated `resize` to use `--vm-name` instead of legacy `--vm`, added `--windows`/`--linux` support, and kept no-parameter invocation interactive.
- Split `resize` away from the generic move/resize prompt flow so interactive resize stays in the current region and direct fully specified resize runs without an extra confirmation prompt.
- Streamlined isolated `exec` task runs so they now accept `--vm-name`, resolve only the selected VM/task context, and skip the broader Step-1 managed-resource inventory path before pyssh execution.
- Refreshed `33-create-shortcuts-public-desktop` so the public desktop set now uses the new canonical `a1/i0/i1/i2/z1/z2/t*` naming, removes legacy `i7whatsapp`, adds shared Chrome-profile launchers for ChatGPT, internet, WhatsApp Web, and account setup, dynamically resolves the WhatsApp desktop executable with a fixed fallback path, and wraps command-style launchers through `cmd.exe` so `.cmd`-backed tools do not open in Notepad.
- Extended the Windows public-desktop contract again so `33-create-shortcuts-public-desktop` now adds `a3CodexApp` with the requested `OpenAI.Codex_26.306.996.0_x64__2p2nqsd0c76g0\app\Codex.exe` target fallback, while `37-capture-snapshot-health` inventories the new shortcut during late-stage validation.
- Extended the late Windows validation path so `37-capture-snapshot-health` now also inventories the static auto-start shortcut contract that `32-configure-apps-startup` writes under the machine Startup folder.
- Expanded `37-capture-snapshot-health` to inventory the refreshed public desktop shortcut set and read back the updated target-path and argument contracts during late Windows validation.
- Recalibrated all Windows `vm-update` task catalog timeouts from live transcript data and successful isolated reruns using a `max_success_seconds * 1.3` buffer rule, including new bounded values for tasks `27` and `29` after live `exec` confirmation at `7.2s` and `6.7s`.
- Expanded the late-stage public desktop contract again so the canonical set now also includes normalized social-media links, app launchers for Be My Eyes/NVDA/Edge/VLC/iTunes/OneDrive/Google Drive, one private local-only accessibility shortcut hotkey, dynamic app-path fallback resolution, and Unicode-safe `q1Eksisozluk` creation plus readback through `Shell.Application`.
- Recalibrated Windows `vm-update` catalog timeouts for the new install tasks and refreshed late-stage tasks from successful isolated live durations with a 30% buffer, including final bounded values for tasks `30` through `37`, plus rerun-confirmed `27=10s` and `29=10s`.
- Replaced the fragile reboot/autologon path for Windows `vm-update` tasks `04` and `05` with a bounded `manager` password-logon scheduled-task helper so isolated `exec` runs no longer stall in interactive-session retry loops.
- Reworked `34-configure-ux-windows` so it now enforces and readback-validates hibernate-menu visibility, Explorer details/no-group defaults, desktop name sort plus auto-arrange/grid alignment, Control Panel small icons, file-copy details, keyboard repeat delay, and Task Manager full view through `TaskManager\settings.json`.
- Repaired `34-configure-ux-windows` so it now verifies Task Manager can really launch before and after patching `TaskManager\settings.json`, restores the prior store on failure, and also hides the taskbar Search, Widgets, and Task View controls.
- Reworked `34-configure-ux-windows` again after live `exec` failures so user-hive writes now run through the bounded password-logon helper, registry writes use writable .NET registry handles instead of `New-ItemProperty`/`reg add`, Task Manager no longer synthesizes a minimal `settings.json`, and Widgets hiding now uses the supported `HKLM\SOFTWARE\Policies\Microsoft\Dsh\AllowNewsAndInterests=0` policy path instead of the failing `TaskbarDa` value.
- Simplified `35-configure-settings-advanced-system` down to deterministic machine-level advanced settings only and removed the unsupported audio/max-volume automation branch.
- Added `36-copy-settings-user` to seed the repo-owned Windows user/app settings from `manager` into `assistant`, `C:\Users\Default`, and `HKU\.DEFAULT` with explicit exclusions for volatile caches, tokens, and credential stores.
- Reworked `36-copy-settings-user` after live hang/debug cycles so `assistant` now receives repo-owned HKCU and user-class settings through its own password-logon seed step instead of conflicting offline hive mounts, while default-profile seeding keeps the offline main-hive path only and excludes non-settings-heavy branches such as `AppData\Local\Programs`, `Microsoft\WindowsApps`, and default-profile `LocalLow` to avoid long robocopy stalls on runtime binaries and alias placeholders.
- Hardened one private local-only accessibility settings task with staging extraction, `version.dll` hash verification, per-file roaming copy, and explicit missing-file detection after live validation exposed a false-success path.
- Reworked `18-install-ollama-system` to short-circuit healthy existing installs, detach `ollama serve` stdout/stderr from the SSH session, clear stale installer locks before `winget`, and bound the `winget` wait so interrupted e2e runs no longer hang indefinitely on `waiting another install to complete`.
- Hardened `16-install-docker-desktop` so it now clears stale installer processes before `winget install Docker.DockerDesktop` and terminates leftover installer locks when bounded install waits time out.
- Updated `12-install-vscode-system` so it now short-circuits when a healthy existing Code executable is already present instead of re-entering `winget` during resumed e2e runs.
- Normalized spinner-prefixed `CLAGNOS_*` protocol markers in the persistent SSH transport so long-running Windows package installs do not hide task-end or session-error markers behind progress spinners.

### Documentation
- Rebuilt `AGENTS.md` as the repository engineering contract for architecture, workflow, logging, testing, and documentation maintenance.
- Upgraded `README.md` into a fuller operator and contributor guide aligned with the current CLI, step flow, task model, and configuration contract.
- Documented the new `.env` `company_name` key in the config contract so Windows Chrome-based public desktop shortcuts can share a company-named default profile directory such as `orgprofile`.
- Added move timing/process guidance to `README.md` and `clagnos help move`, using the observed live `austriaeast -> swedencentral` `Standard_D4as_v5` / `127 GB` OS-disk move as an operator reference for expected duration and cutover phases.
- Added `CHANGELOG.md`, `release-notes.md`, `roadmap.md`, and `docs/prompt-history.md` to formalize project history, release context, future direction, and dialog traceability.
- Adopted commit-count version labels across `CHANGELOG.md` and `release-notes.md`.
- Normalized `CHANGELOG.md` and `release-notes.md` to LF line endings and pinned that expectation in `.gitattributes` so documentation-contract checks behave consistently.
- Removed the retired `docs/reconstruction/` artifact set after its remaining value had been folded into the maintained documentation set.
- Added an explicit repository-context assimilation rule to `AGENTS.md` so each prompt implementation starts with codebase/documentation/test baseline scanning and alignment.
- Relaxed the prompt-history rule so non-mutating prompts are only recorded on explicit user opt-in, while repo-changing prompts remain mandatory prompt-history entries with a commit.

### Tests
- Renamed `tests/powershell-smoke.ps1` to `tests/clagnos-smoke-tests.ps1` because it validates `clagnos` runtime contracts and smoke behavior rather than generic PowerShell behavior.
- Renamed `tests/docs-contract.ps1` to `tests/documentation-contract-check.ps1` for clearer intent and kept it as the documentation-contract gate for current command naming, prompt-history structure, and legacy-token removal.
- Split static quality responsibilities into `tests/code-quality-check.ps1`, `tests/bash-syntax-check.ps1`, and `tests/powershell-compatibility-check.ps1`.
- Renamed the `tests/` scripts to clearer dash-separated names and updated all live references across hooks, workflow, and docs.
- Moved the manual git-history regression replay tool to `tools/scripts/git-history-replay.ps1` so it lives with helper tooling instead of the primary test entrypoints.
- Fixed `tools/scripts/git-history-replay.ps1` to use the quality entrypoint that exists inside each replayed worktree instead of forcing the latest script onto historical commits.
- Added a smoke-contract case for catalog fallback behavior: missing entries default to `priority=1000` and missing timeouts default to `180`.
- Added smoke coverage for renamed Windows vm-update private local-only task metadata, zip asset layout, and runtime asset-copy resolution.
- Added smoke coverage for the new `do` command parser/help contract, lifecycle-state normalization, action eligibility checks, and interactive action selection.
- Added smoke coverage for `resize --vm-name`, direct-request detection, platform-flag validation, and same-region interactive size selection.
- Added smoke coverage for direct `exec --vm-name` task targeting, the new minimal `exec` runtime path, and the strengthened Ollama HTTP readiness check.
- Added smoke coverage for persistent SSH spinner-marker normalization plus the new stale-installer and bounded-timeout guards in Windows tasks `09` and `18`.
- Added smoke coverage for the new Windows UX helper-asset model, removal of reboot-resume task metadata, `TaskManager\settings.json` validation, and removal of legacy audio tuning from task `05`.
- Added smoke coverage for the new `36-copy-settings-user` task, taskbar-hide registry contract in task `04`, the `37-capture-snapshot-health` rename, and the public desktop banking shortcut set.
- Added smoke coverage for the new Windows app-install tasks `30` through `37`, the expanded canonical public desktop shortcut set, the shared Unicode-safe `q1Eksisozluk` variable contract, Be My Eyes helper-asset publication, and one private local-only accessibility hotkey assignment.
- Completed isolated live `exec` validation for Windows update tasks `04`, `05`, and one private local-only late-stage task against `rg-examplevm-ate1-g1/examplevm`, including an idempotent rerun of task `04` plus private local-only payload hash and roaming-manifest readback checks.
- Completed additional isolated live repair validation for Windows update tasks `04`, `28`, and `29` after the Windows UX/user-settings hardening changes, including repeated interrupted-task recovery, assistant/default-profile propagation checks, and a final successful `27 -> 28 -> 29` late-stage chain on `rg-examplevm-ate1-g1/examplevm`.
- Completed isolated live `exec` sweeps for every Windows `vm-init` and `vm-update` task against `rg-examplevm-ate1-g1/examplevm` in effective catalog priority/timeout order, then reran task `09` after the Ollama hardening change to prove `11434` API readiness.
- Completed isolated live `exec` validation for Windows update tasks `30` through `37`, then reran `33-create-shortcuts-public-desktop` and `37-capture-snapshot-health` to confirm the expanded shortcut contract, app-target resolution, one private local-only accessibility hotkey, and Unicode-safe `q1Eksisozluk` readback on `rg-examplevm-ate1-g1/examplevm`.
- Completed isolated live reruns of Windows update tasks `09` and `18`, then reran `create --auto --windows --perf --step-from=vm-update` successfully to the end on `rg-examplevm-ate1-g1/examplevm` with `WIN_VM_SIZE=Standard_D4as_v5`, confirming a running VM and reachable RDP port `3389`.

### Refactors
- Removed runtime task-catalog auto-sync/auto-write behavior; catalogs are now read-only inputs at execution time.
- Added catalog-level default consumption (`defaults.priority`, `defaults.timeout`) with fallback `priority=1000`, `timeout=180`.
- Moved private local-only Windows accessibility assets to zip-based packaging and aligned the surrounding update catalog entries with the revised late-stage task naming.
- Merged the user-adjusted Windows vm-update catalog ordering back onto the renamed task set by keeping `33-create-shortcuts-public-desktop` at priority `98`, inserting `36-copy-settings-user` at priority `99`, and moving `37-capture-snapshot-health` to priority `100`.
- Extended `33-create-shortcuts-public-desktop` and `37-capture-snapshot-health` so the late-stage Windows UX flow now creates and inventories eight bank shortcuts that launch Chrome with the requested `examplevm` profile and URLs.
- Replaced the Windows interactive reboot-resume plumbing with a repo-managed scheduled-task helper under `tools/windows/` and returned isolated `exec` task execution to the normal bounded SSH path.

### Chores
- Replaced the one-way hook installer with `tools/enable-git-hooks.ps1` and `tools/disable-git-hooks.ps1`.
- Added `.github/workflows/quality-gate.yml` for non-live static quality enforcement on GitHub Actions.

## [2026.3.7.223] - 2026-03-07

### Features
- Finalize public desktop shortcut coverage and ordering
- Support vm-name overrides and harden vm-deploy validation flow
- Add external ssh and rdp connection commands
- Enable nested virtualization during post-deploy feature setup

### Fixes
- Support deferred app shortcuts on public desktop
- Stabilize isolated vm-update task recovery flows
- Harden vm feature enablement and recover pyssh bootstrap
- Enforce repo-wide no-bytecode python execution
- Disable pyssh bytecode cache generation
- Always execute vm-init during full create and update flows
- Honor task outcome mode across init and update stages
- Add early naming guards and catalog-driven task timeouts
- Validate region and vm name before provisioning
- Rename vscode public desktop shortcut
- Resolve repo-root config loading and remove run-command legacy naming
- Enforce auto-option scope and align config command contract
- Add platform task-dir env fallbacks and reset-ready config docs

### Refactors
- Cut over config command and step contract to configure
- Defer vm-update reboot handling to end-of-stage reporting
- Rename task outcome mode config to vm-scoped key
- Activate template indexing for managed resource names
- Remove unused naming profile setting
- Make vm name the single naming seed
- Remove generic task directory config handling
- Remove legacy compatibility fallbacks across runtime and tooling
- Rename admin credential env keys to VM_ADMIN_*
- Split orchestrator into domain modules with function-level comments

### Documentation
- Clarify vm name semantics across prompts and help

### Tests
- Align env contract with current local source of truth

### Chores
- Report failed vm-update tasks in stage summary
- List reboot-requesting vm-update tasks in stage summary
- Normalize task catalog json formatting after modular refactor

## [2026.3.6.191] - 2026-03-06

### Features
- Add group command and group-aware command targeting
- Add catalog-driven task ordering, native exec shell, and expanded Windows update tasks
- Finalize new CLI surface and remove legacy wording
- Add show command for full Azure VM and resource configuration dump
- Expand perf telemetry across command, step, action, and task flows
- Add interactive config preview command and simplify help syntax
- Add global --help and detailed help topic workflow
- Add delete command and interactive change/exec flows
- Implement snapshot-based region change and regional naming templates

### Fixes
- Restore winget source reset --force in bootstrap task
- Remove winget --force usage from vm-update tasks
- Make sysinternals update task robust against checksum drift
- Refactor orchestrator to 7-step flow and restore targeted vm-init step execution
- Make step4 network checks non-erroring and ensure resource group exists
- Preserve config step1 context for step2 region precheck
- Harden interactive region selection against empty az_location
- Handle retail pricing nextPageLink top bug causing 400 responses
- Harden retail pricing API calls with cache and throttling-aware retry
- Render region picker grid in 9 columns per row

### Refactors
- Enforce region-required flow and platform vm env keys
- Switch task catalogs to priority-driven execution with on-demand reconciliation
- Rename CoVm markers to Clagnos and optimize show command performance

### Documentation
- Align create description in quick help overview

### Tests
- Expand help contracts and add quality replay audit scripts

## [2026.3.5.167] - 2026-03-05

### Features
- Add multi-action and single-action execution modes for create/update
- Add command-based CLI flow with create/update/change/exec
- Default interactive runs to the destructive rebuild mode used at that point in history
- Make pyssh venv-based and verify with isolated ssh test

### Fixes
- Harden region-change resource mover orchestration and stale cleanup
- Default exec command to auto mode
- Make pyssh installer recreate requirements as utf8 without bom
- Support lowercase ssh_port config with uppercase fallback
- Cap VM running-state retry attempts at three
- Remove step value usage heading from console logs
- Remove [new]/[updated] suffixes from console value logs
- Filter spinner transcript noise and harden pyssh reconnect flow
- Prevent Step8 task stalls by sanitizing SSH stream markers and stabilize health snapshot

### Refactors
- Rename pyssh installer and disable connection test by default
- Simplify step 8 task logs and hide protocol noise lines
- Remove legacy SSH/run-command leftovers and harden windows auto update flow

### Documentation
- Align init execution wording with run-command task-batch flow

### Tests
- Add update task 51 local-diagnostic for exec validation
- Validate NSG multi-port create on PowerShell 5.1 and 7

### Chores
- Verify env templates and prune obsolete local env keys

## [2026.3.4.147] - 2026-03-04

### Features
- Reuse single SSH session for Windows Step 8 substeps and bootstrap winget via choco
- Add SSH Step 8 executor and resilient update/reboot flow
- Allow returning from SKU picker to region selection with r
- Expand guest update tasks with tools, UX tuning, and post-reboot probe

### Fixes
- Stabilize combined init run-command and resume auto flow
- Use choco winget upgrade + PATH-based winget private local-only accessibility install
- Harden step8 guest task execution after auto-mode e2e
- Stabilize Step 8 persistent SSH protocol on PowerShell 5 and remove substep lockups
- Switch to portable pyssh client and stabilize windows substeps

### Refactors
- Split init/update tasks, remove output suppression, and optimize docker/wsl checks
- Unify linux/windows flow into clagnos.ps1 with task-file catalogs
- Adopt default/update/destructive-rebuild flow and pyssh-first step8

## [2026.3.3.135] - 2026-03-03

### Features
- Add Windows UX/performance tuning task to VM update flow
- Add contextual first-use value tracing across orchestration steps
- Print full runtime configuration snapshot in auto mode
- Add assistant power-admin account and dual-user connection output
- Align existing VM handling with interactive/auto delete confirmation flow
- Add two-stage y/n confirmation to interactive vm sku flow
- Add interactive region and sku picker with pricing and .env persistence
- Add full windows vm orchestration with ssh and rdp
- Add guest init and update powershell artifacts
- Add full linux vm orchestration script with step flow
- Add guest bootstrap artifacts for cloud-init and update

### Fixes
- Make Windows local group membership idempotent in VM update flow
- Prevent auto-mode snapshot lockups with az account timeouts
- Harden ps5.1 and pwsh json handling across region/sku and vm parsing flows
- Make interactive sku filtering consistent across Windows PowerShell and pwsh
- Show effective partial vm filter and count in interactive sku selection
- Format interactive region labels as n-region and mark default with star prefix
- Make interactive vm sku partial search robust for quotes and separator variants
- Limit interactive region picker to physical azure deployment regions
- Render interactive region list as visible 10-column grid and host-print sku table

### Refactors
- Centralize guest task catalogs and Step 5/6/8 script generation
- Centralize Step 8 run-command orchestration and token expansion
- Centralize shared orchestration steps in co-vm
- Rename step mode to substep and add tracked az command timing
- Introduce co-vm modules for core azure and run-command reuse

### Documentation
- Add end-to-end README with quick start, architecture, configuration, and usage guide
- Add codex evidence index with clagnos related jsonl references
- Add era index for faster navigation of reconstructed history
- Append final codex evidence checkpoint for reconstructed commit chain
- Register windows step8 diagnostics timeline and deadlock mitigation context
- Capture verified successful auto-run outcomes in austriaeast
- Add AGENTS.md with cross-platform vm scripting conventions

### Chores
- Deduplicate runtime value logging and print only new/changed values
- Ignore auto-generated vm init/update artifacts
- Add interactive RG delete confirmation in Step 3 workflow
- Refine SKU partial filtering with strict wildcard semantics
- Standardize UTF-8 no-BOM writes and enforce deterministic line endings
- Harden PS5/PS7 compatibility and add non-live matrix smoke tests
- Add linux and windows environment templates
- Add elevated root launchers for linux and windows flows
- Initialize clagnos repository with ignore and reconstruction scaffolding

## [2026.3.1.94] - 2026-03-01

### Features
- Capture auto-mode deletion prompt wording correction
- Track global ssh port migration from 443 to 444
- Record mandatory port 11434 addition across linux and windows
- Log request to observe auto-only performance impact after fixes
- Track optimization request for step mode run-command batching
- Capture precedence policy cli override env default
- Track windows disk size update to 128gb in env and script
- Record env-based variable management on both platforms
- Capture temporary windows disk size move to 80gb
- Log windows network parity requirement with linux port model
- Capture linux firewall expansion sync from user edits
- Track --step parameter request for granular diagnostics
- Record region move to austriaeast for both platforms
- Track linux region sync to westindia and parity push
- Capture request to avoid indefinite interactive waits during test runs
- Record two-mode runtime model interactive plus auto
- Log graceful user-friendly exception and exit behavior requirement
- Capture server-side filtered region-size lookup optimization
- Document az rest preference over slow list-skus path
- Track early region-sku availability precheck requirement
- Record west india default location investigation and assignment
- Document win11 25h2 avd m365 image selection request
- Record india-proximate region preference change
- Document unattended chocolatey bootstrap requirement
- Note vm size standard_b2as_v2 requirement for windows
- Capture storage sku and disk-size optimization request
- Record datacenter compatibility image requirement for windows
- Track rdp enablement and broad client compatibility requirement
- Record initial windows script parity request

### Fixes
- Record single-location rule for choco global confirmation
- Capture choco global confirmation setup requirement
- Log duplicate refreshenv cleanup requirement in windows flow
- Log windows tcp port exposure parity check across nsg and guest firewall
- Log combine-mode requirement to run generated clagnos-win-update.ps1 file
- Capture critical semantic correction for step vs combined behavior
- Capture system error 1378 mitigation by pre-check before add
- Track run-command success-gating before advancing tasks
- Record rg-reset-plus-step rerun requirement for root-cause analysis
- Record windows step8 console-lock investigation demand
- Log vm naming contract examplelinuxvm and examplevm confirmation
- Document linux auto mode graceful early exit in step2 conditions
- Capture duplicate-safe machine path augmentation mechanism
- Log refreshenv after each package installation and retest flow
- Track all-package installation standardization via chocolatey
- Capture refreshenv-before-path-check requirement
- Capture strict python install command requirement
- Capture filename suffix correction to lin.* convention

### Refactors
- Capture launcher relocation request to repository root
- Record shared co-vm architecture extraction for max code reuse
- Capture request to port latest windows combine-mode behavior to linux
- Track step-aware bash and powershell run-command strategy
- Capture linux task decomposition request to mirror windows structure
- Log request to carry latest windows fixes into linux script
- Capture linux-side adoption of step-task semantics
- Record step-task wording rollout across code ui and comments
- Capture auto and step parity expectation across both scripts
- Log request to port same task-array strategy to linux
- Track win step-mode and non-step-mode structural unification
- Record step-to-task terminology correction requirement
- Capture code-only sync request with deferred testing
- Capture cross-platform identical behavior requirement
- Capture sh-to-powershell guest update conversion for windows
- Track rename request from clagnos to linux-specific naming

### Documentation
- Align reconstruction notes with current co-vm lin-vm win-vm layout
- Finalize comprehensive reconstructed timeline index
- Capture requirement to mine codex jsonl for clagnos chronology
- Capture request for real .env.example templates with active variables
- Log unused-file detection and approval-gated deletion request
- Log parity-diff check request beyond os-specific behavior
- Capture completion status confirmation request
- Record fallback-presence and westindia sku inquiry
- Track inquiry for windows11 plus office365 combined image
- Record windows11 pro image availability inquiry
- Log regression check for rename and content updates
- Record non-interactive linux deployment and ssh validation request

### Tests
- Record request to run parallel auto-only tests for both platforms
- Capture windows auto-only execution request after parity updates
- Record request to run windows in auto mode only for syntax confidence
- Capture explicit verification request for windows auto-run completion
- Record windows auto-run iterative rebuild and fix loop
- Record linux auto-run iterative rebuild and fix loop
- Capture parallel full rebuild request for both platforms
- Record directive to postpone e2e until bulk fixes complete

### Chores
- Record mandatory commit-before-summary assistant workflow rule
- Log repository bootstrap and AGENTS documentation request
- Track second implement-plan handoff for full reuse architecture
- Record explicit implement-plan handoff for parity refactor
- Record instruction to defer both platform tests after refactor
- Note explicit request to skip tests for semantic correction phase
- Log anti-regression requirement for env and language refactor
- I18n(history): capture english-only ui strings comments and messages request
- Capture no-fallback directive for region and image checks
- Log repository structure regrouping under lin-vm and win-vm
- Document windows vm identity requirement as examplevm
