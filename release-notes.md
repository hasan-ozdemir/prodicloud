# Release Notes

This document uses `YYYY.M.D.N`, where `N` is the cumulative repository commit count at the documented release point.

## Release 2026.10.15.418 - 2026-10-15

### Summary
Windows builtin packages now have separate, verified status, install, update, and uninstall flows that can run over SSH or WinRM. Manage Programs remains responsive through batched package inventory and cached status, and JAWS app-state replay now works over the selected WinRM session.

### Highlights
- Added lifecycle dispatch scripts and update strategies for all 36 Windows builtin packages. Install leaves an installed package alone; update runs only for installed packages; status and uninstall remain available for disabled packages.
- Added strict WinRM package transport, exact-host TrustedHosts management, shared session asset transfer, and WinRM app-state replay. Added a read-only repeated-status benchmark for comparing SSH and WinRM.
- Chocolatey uninstall preserves other package files and its bootstrap reinstalls the CLI without discarding them.
- JAWS update checks for a real winget upgrade before invoking its installer, verifies app-state update-files before copying, applies post-logon startup, and reports logon-screen launch as installer-managed.

### Validation
- Repository quality checks passed, including package app-state and lifecycle contracts, sensitive-content audit, release packaging, and CLI help. Compatibility smoke checks passed 192/192 and fixture-backed TUI checks passed 174/174; the real `cg.cmd` test made zero native Azure CLI calls.
- Live package checks covered a full Chocolatey uninstall/install/update/status cycle, GitHub Copilot CLI uninstall/install, and JAWS status/install-no-op/update/app-state replay. The 36-package status inventory returned installed; JAWS app-state replay verified 4/4 settings with zero mismatches. During early JAWS update attempts, two guest restarts interrupted WinRM shells; the final update detected there was no vendor upgrade and the packaged files already matched, then completed without another restart.
- Five read-only status samples per transport measured SSH median 39,310 ms and WinRM median 18,151 ms. The target VM remained running, with no disk, network, or other Azure resource changes.

## Release 2026.10.14.417 - 2026-10-14

### Summary
Nested-virtualization intent and actual guest capability are now reported as separate facts across creation, feature updates, VC details, and full reports.

### Highlights
- Create review labels the `.env` value as a request. Feature validation reports whether guest CPU virtualization extensions are available without claiming it installed Hyper-V or toggled Azure hardware exposure.
- The selected-VC screen and `show` use the same guest validation result. `show` keeps an Azure-reported setting separate from `NestedVirtualizationAvailableToGuest` and includes probe evidence and errors.
- Missing or malformed CPU-extension fields report unknown. Windows requires VMX, firmware virtualization, and SLAT to be present; outer-hypervisor presence and an enabled Windows optional feature do not override missing extensions.
- The process-level `cg.cmd` fixture now safely transports and validates its read-only guest probe without permitting other Azure Run Command calls.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ each passed 191 smoke checks and 173 fixture-backed TUI checks, including real `cg.cmd` console output. Repository quality checks passed. No live Azure resources or settings were changed.

## Release 2026.10.14.416 - 2026-10-14

### Summary
Clagnos now rejects unsupported B-series nested-virtualization settings before deployment and no longer mistakes Azure's outer hypervisor plus an enabled Windows feature for nested CPU extensions exposed to the VM.

### Highlights
- Create/update prechecks use family metadata to reject documented unsupported Bv1, Bsv2, Basv2, and Bpsv2 families when the Azure SKU API omits nested capability rows.
- `VMMonitorModeExtensions`, `VirtualizationFirmwareEnabled`, and `SecondLevelAddressTranslationExtensions` are authoritative for Windows nested-virtualization availability. `HyperVisorPresent` and Windows optional-feature state remain in evidence only.
- A read-only Bsv2 guest check found all CPU extension flags false while the outer hypervisor was present and `VirtualMachinePlatform` was enabled. Clagnos now correctly reports nested virtualization unavailable.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ each passed 191 smoke checks and 173 fixture-backed TUI scenarios. Repository quality checks passed. Regression coverage includes supported and unsupported guest CPU evidence. The live Azure queries were read-only and changed no resources or settings.

## Release 2026.10.14.415 - 2026-10-14

### Summary
Clagnos now rejects documented B-series nested-virtualization incompatibilities before creating Azure resources, even when Azure omits the relevant SKU capability row.

### Highlights
- The precheck reads the SKU family metadata as a fallback to the Compute capability list. Bv1, Bsv2, Basv2, and Bpsv2 are treated as known unsupported families, with SKU/family evidence and a corrective hint shown during configuration review. Unknown families remain inconclusive and are not falsely rejected.
- Added a regression test for `Standard_B2s_v2` with no nested-virtualization capability row in the fixture. Unsupported settings stop before resource-group, network, or VM deployment.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ each passed 191 smoke checks and 173 fixture-backed TUI scenarios. Repository quality checks passed. Tests used fixture data only; no live Azure operations were performed.

## Release 2026.10.14.414 - 2026-10-14

### Summary
The interactive CLI now keeps Azure inventory and package status snapshots warm in the background, reducing repeated Azure list calls and remote status probes.

### Highlights
- A hidden worker atomically refreshes subscription-scoped groups, resources, and detailed VM rows without blocking TUI startup. An exclusive per-subscription lock avoids duplicate scans across concurrent TUI instances. It revalidates every 60 seconds, carries pending refreshes across CLI restarts, rejects snapshots older than five minutes, and uses bounded backoff after Azure failures.
- Manage Programs shows the latest package status from a per-VC local cache while builtin/custom catalog checks run asynchronously. Complete status snapshots are reused for 45 seconds; explicit `r`/`s` actions request refreshes.
- Package operations reuse an already resolved runtime/target and fresh VM endpoint data. A successful SSH bootstrap is reused for 20 seconds. The worker explicitly flattens JSON root arrays for Windows PowerShell 5.1 compatibility.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ each passed 190 smoke checks and 173 fixture-backed TUI scenarios, including real `cg.cmd` process output, background-worker inventory publication, and persisted-refresh recovery.
- Repository quality checks passed for parsing, docs, sensitive content, package app-state, release packaging, Python hygiene, and CLI help. Tests used fixture Azure reads only; no live Azure operations were performed.

## Release 2026.10.14.413 - 2026-10-14

### Summary
The interactive CLI now reuses a validated Azure resource snapshot and creates virtual computers through a numbered, paged, input-validated wizard.

### Highlights
- The first signed-in TUI screen caches managed resource groups, their resources, and VM details for the selected subscription. Screens reuse that snapshot; it is revalidated every 60 seconds and invalidated by explicit refresh, subscription changes, and operations that may mutate Azure state.
- Resource changes are detected by Azure ETags, with content signatures as a fallback when a resource does not expose an ETag. An unchanged validation preserves the existing snapshot.
- The create wizard pages region, SKU, and other option lists; marks defaults with `>`; supports `p/n/g/f/t` page navigation and `s/k/a/l/c` step controls; and reviews validated values before calling the shared create workflow.
- OS disk sizes accept `MB`, `GB`, or `TB` text up to the 4095 GiB Azure OS disk limit. Inbound TCP ports accept comma-separated values and ranges such as `3000-3300`; invalid values are rejected before command dispatch.
- Task selection, inventory group filters, app-state user selectors, and report paths now use accessible numeric or validated input paths.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ each passed 189 smoke checks and 172 fixture-backed TUI scenarios, including the real `cg.cmd` process output, snapshot reuse/change checks, create wizard controls, invalid defaults, text-validation retry paths, and canceled report-path input.
- Fixture tests made no native Azure calls and dispatched no real Clagnos commands; no Azure resources were changed.
- Repository quality checks passed for PowerShell parsing, documentation, sensitive content, package app-state, release packaging, and Python artifact hygiene.

## Release 2026.10.13.412 - 2026-10-13

### Summary
The virtual computer inventory and detail screens now read Azure VM power state from the correct Azure CLI response field.

### Highlights
- Supports Azure CLI's `instanceView.statuses` response and the Compute REST instance-view response's root `statuses` array.
- Uses Azure's `displayStatus` when present and derives a readable label from a `PowerState/*` code when it is absent.

### Validation
- The real parameterless `cg.cmd` showed `vc1` as `VM running` in its virtual computer list after the fix.
- The status lookup is read-only; no VM or disk/network resources were changed.

## Release 2026.10.13.411 - 2026-10-13

### Summary
The interactive VM power and status menu now passes only options supported by the shared `do` command.

### Highlights
- Removed OS platform flags from `do` dispatches; the TUI status action now works for a selected virtual computer.
- Added TUI coverage that checks all lifecycle actions use command-contract-valid options.

### Validation
- TUI suite passed 160/160 under Windows PowerShell 5.1 and PowerShell 7+.
- The argless `cg.cmd` workflow selected `vc1`, changed its size to `Standard_B2s_v2`, verified the resulting size, and confirmed `VM running` through the interactive status menu. No disk or network resource was changed.
- Full quality audit passed.

## Release 2026.10.13.410 - 2026-10-13

### Summary
The `cg.cmd` launcher preserves command-line arguments, and VM size validation honors active-subscription SKU restrictions before lifecycle changes.

### Highlights
- Fixed command mode falling through into the interactive menu after the runtime's `CliTokens` parameter shadowed the launcher arguments.
- Added a process-level regression check that runs `cg.cmd help resize` through the real batch launcher in a temporary fixture workspace.
- Added an active-subscription `az vm list-skus` precheck after regional validation; unavailable VM sizes now fail before deallocation.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ compatibility checks passed: 188 smoke checks and 160 TUI scenarios per runtime.
- Launcher and restricted-SKU regression checks used fixtures and attempted no resource mutations.

## Release 2026.10.13.409 - 2026-10-13

### Summary
Clagnos adds practical reporting, task-history, resize-verification, and source-package workflows while keeping validation fixture-backed and non-mutating.

### Highlights
- `resize` prints before/after lifecycle snapshots and verifies Azure's actual VM SKU or OS disk size before saving the requested value to `.env`.
- `list --type=group` shows the active group, Azure location, and provisioning state.
- `show --export-json=<path>` writes a machine-readable report with sensitive configuration values redacted; replacing a file requires `--overwrite`.
- `task --history` shows local isolated task/package outcomes and init/update stage summaries, including deferred app-state tasks, without guest output or credentials.
- `tools/package-release.ps1` creates a versioned source ZIP with `BUILD-MANIFEST.json` and a SHA256 sidecar after checking version alignment, worktree cleanliness, and tracked `.env` exclusion.

### Validation
- Windows PowerShell 5.1 and PowerShell 7+ compatibility checks passed: 187 smoke checks and 160 TUI scenarios per runtime.
- The real `cg.cmd` process test used fixture Azure reads only. No native Azure CLI calls, real dispatcher calls, Azure mutations, or VC provisioning occurred.
- Full quality audit passed.

## Release 2026.10.13.408 - 2026-10-13

### Summary
Windows virtual computers can now be opened through Clagnos PowerShell remoting for an interactive remote command prompt, one-shot commands, and an authenticated connectivity check.

### Highlights
- Added `cg.cmd connect --powershell` over WinRM Negotiate on TCP 5985. The interactive mode keeps one PSSession open and accepts one PowerShell command per line; `exit` closes it.
- Added `--command` and `--test` modes, surfaced the connection and test commands in the workflow summary, and added PowerShell options to the selected VC operations menu.
- Extended the existing enabled Windows init task 06 to grant both manager and assistant accounts Remote Management Users access. Basic authentication and unencrypted WinRM remain disabled.
- The default TCP port list already includes 5985. Keep that port in a customized `TCP_PORTS` value when WinRM connectivity is wanted.

### Validation
- Compatibility checks passed under Windows PowerShell 5.1 and PowerShell 7+: 179 smoke checks and 158 TUI scenarios per runtime.
- The real `cg.cmd` process scenario captured the VC endpoint and PowerShell submenu; all tests reported zero native Azure CLI calls, zero real dispatcher calls, and no Azure mutations.

## Release 2026.10.13.407 - 2026-10-13

### Summary
TUI verification now launches the actual `cg.cmd` in an isolated fixture environment and checks its real console output.

### Highlights
- Added a process-level screen journey through the home menu, VC list/details, package catalog, component menu, operations menu, managed inventory, and cloud subscriptions.
- The test copies the real launcher, UI, and runtime modules into a temporary sandbox and feeds scripted input to the launched process.
- The sandbox uses fake Azure read responses and a fake launcher elevation check. Mutating Azure verbs are rejected; the operator `.env` and real Azure CLI are not used.

### Validation
- All 154 TUI scenarios passed under Windows PowerShell 5.1 and PowerShell 7+.
- The actual `cg.cmd` process output was captured and checked; no native Azure CLI call or Azure resource mutation occurred.

## Release 2026.10.12.406 - 2026-10-12

### Summary
Added a non-live TUI acceptance suite covering the Clagnos menu hierarchy and all visible actions before an operator launches `cg.cmd`.

### Highlights
- Added 153 fixture-driven scenarios for the home menu, subscriptions, VC list/details, package catalogs, resource inventory, component CRUD, task/app-state menus, and VC operations.
- Asserted rendered VC details, credential source presentation, endpoint fields, confirmation prompts, navigation, and command-option mapping.
- The test harness blocks Azure CLI and the real command dispatcher. It verifies zero cloud calls and zero backend dispatches.
- Added the suite to the PowerShell 5.1/7+ compatibility matrix used by CI.

### Validation
- TUI suite passed 153/153 scenarios under Windows PowerShell 5.1 and PowerShell 7+.
- Both runs ended with zero native Azure CLI calls and zero real dispatcher calls. No Azure resources were changed.

## Release 2026.10.12.405 - 2026-10-12

### Summary
Selecting a VC now opens a more complete detail screen with its connection endpoints, configured login credentials, network addresses, storage, security settings, and attached Azure resources.

### Highlights
- Shows the VC's SSH and RDP host/port, plus manager and assistant usernames and passwords read from local `.env`.
- Adds public IP and public DNS/FQDN, private addresses, NIC and IP configuration, VNet/subnet/NSG, image, OS and data disk settings, security, hibernation, tags, identity, and attached-resource details.
- Keeps credentials in the interactive screen output and excludes them from progress and operation log messages.

## Release 2026.10.12.404 - 2026-10-12

### Summary
Clagnos now reports long-running work as it happens, exposes its complete VC operations set from a dedicated interactive menu, and has a successful live acceptance cycle for `vc1`.

### Highlights
- Added `Doing: <action>` progress before cloud and guest operations, plus 30-second heartbeats during long waits. Quiet remote execution retains local progress messages.
- Added the selected VC's numbered `o: operations` menu for VM lifecycle actions, hibernation/resume, force power-off/reset, resize, feature toggles, move, connections, tasks, components, and reports.
- Added state-checked `resume`, `shutdown`, `power-off`, and `reset` actions. Azure force reset uses `az vm restart --force`, which redeploys the VM; immediate power-off skips guest shutdown but keeps the VM allocated.
- Added a resumable live E2E test, committed eight sanitized builtin app-state archives, and copied/verified the JAWS `update-files` payload during package install.

### Validation
- The live `vc1` acceptance test passed after confirming 8 init tasks, 10 update tasks, 36 packages, nested virtualization, hibernation/resume, VM summary redaction, SSH, and RDP. It left the VM running.
- Windows PowerShell 5.1 and PowerShell 7+ compatibility passed at 174/174 checks. Code quality, documentation, sensitive-content, package app-state, and Bash syntax checks passed.

## Release 2026.10.12.403 - 2026-10-12

### Summary
Package app-state is now stored as portable preference data and adapted to the target VM just before replay. Sign-in sessions and other machine-bound state are no longer copied between computers.

### Highlights
- Audited all builtin app-state policies and snapshots. Narrowed retained snapshots to Azure CLI/AZD configuration, GitHub CLI preferences, JAWS/NVDA settings, Visual Studio user settings, and VLC preferences; removed browser, cloud-account, messaging, remote-access, activation, history, and cache state.
- Added target placeholders for user profiles, SIDs or UIDs/GIDs, OS paths, host name, primary IP, CPU/memory, and Visual Studio instance paths. Windows and Linux capture generalize these values; replay resolves them against the selected target profile and host.
- Added fail-closed handling for missing or unsupported placeholders and secret-key filtering during capture.
- Added repeatable builtin app-state maintenance tooling and automated checks that also cover the custom package catalog contract.

### Validation
- Package app-state contract checks passed for all builtin and custom manifests and retained archives.
- Windows placeholder materialization and Linux capture/replay round trips passed. PowerShell compatibility, documentation, code quality, Bash syntax, and sensitive-content checks were rerun. No Azure resources were changed.

## Release 2026.10.12.402 - 2026-10-12

### Summary
Manage Programs now uses two isolated package catalogs: builtin packages maintained by Clagnos and custom packages maintained in this repository.

### Highlights
- Moved all 36 existing standard Windows installers into `packages/builtin/windows/` with `package.json` manifests and `install.ps1` scripts.
- Added custom catalog roots for Windows and Linux packages, with the package manifest contract documented in `packages/README.md`.
- Manage Programs offers separate builtin/custom catalog paths and labels packages `[builtin]` or `[custom]`.
- Package availability, status, install/update, uninstall, and package app-state operate through the selected catalog. Disabled packages remain visible; install/update requires an enabled package.
- Existing app-state archives were moved with their package folders and retained their legacy identity through `appStateKey`.

### Validation
- Catalog isolation, manifest updates, package install planning, status paths, and app-state selection passed the non-live smoke suite.
- PowerShell compatibility, documentation, code quality, Bash syntax, sensitive-content, and release-document checks passed. No Azure resources were changed.

## Release 2026.10.12.401 - 2026-10-12

### Summary
Tasks can now be enabled or disabled deliberately from the Clagnos task and program menus. The operation updates the shared task catalog for future runs and reports the resulting availability state.

### Highlights
- The Manage programs list marks disabled entries and offers `e` enable, `d` disable, `u` uninstall, `i` install/update, and `s` status actions.
- Program rows identify `initial` versus `add-on` tasks and `local` versus `remote` execution; local-only task catalogs have a separate marker.
- Status and uninstall remain available for disabled programs; install/update is blocked until the program task is enabled.
- Added task-wide availability management for init and update tasks, including local-only task folders.
- Enable/disable requires a typed confirmation, preserves task manifest metadata, verifies the resulting catalog, and never changes an already-running VM.

### Validation
- All 168 smoke checks passed under Windows PowerShell 5.1 and PowerShell 7+.
- Code quality, documentation, Bash syntax, and sensitive-content checks passed. No Azure resource changes were made.

## Release 2026.10.12.400 - 2026-10-12

### Summary
The Clagnos TUI now provides a refreshed cloud-subscription selector and complete menu access to managed resource inventory, component inspection, disabled task inventory, and the existing lifecycle operations. Subscription selection synchronizes the Azure CLI active default with the subscription persisted for Clagnos commands.

### Highlights
- Added `3. Cloud subscriptions`, listing current Azure CLI subscriptions and marking both the app selection and CLI active default.
- Added numbered component-detail and disabled-task views, plus numbered lifecycle, resize, and feature choices.
- Updated help text to match the separate `create`, `initialize`, and `update` contracts.
- Scanned accessible subscriptions for legacy managed resource groups; none were present, so no resource-group tags were changed.

### Validation
- All 167 smoke checks passed under Windows PowerShell 5.1 and PowerShell 7+.
- Code quality, documentation, Bash syntax, and sensitive-content checks passed. No Azure resource mutation was run.

## Release 2026.10.12.399 - 2026-10-12

### Summary
Clagnos now opens through `cg.cmd` into an interactive, nested operator menu while keeping the direct PowerShell command surface available. The repo-wide rebrand updates application paths and public wording, and the menu exposes the managed virtual-computer lifecycle and its Azure and guest operations.

### Highlights
- Separated fresh infrastructure creation (`create`), existing VM bootstrap (`initialize`), and ongoing non-program maintenance (`update`).
- Added task-catalog-backed program inventory, status, install/update, and uninstall flows.
- Added component inventory and CRUD for managed groups, VMs, disks, networks, interfaces, IPs, security groups, and rules, with dependency-aware deletion plans.
- Kept old managed resource groups visible until an operator accepts the management-tag migration.
- Added smoke coverage for the command/menu surface and clarified lifecycle contracts throughout operator documentation.

### Validation
- The Clagnos smoke suite passed all 167 checks under Windows PowerShell 5.1 and PowerShell 7+.
- Documentation, code quality, Bash syntax, and sensitive-content checks passed. No live Azure operations were run.

## Release 2026.3.23.397 - 2026-03-23

### Summary
This documentation update closes the production publish loop by recording the final zero-warning live acceptance result for the managed Windows VM. After the last runtime fixes landed, the final fresh `create`, isolated `10005-copy-user-settings` rerun, natural-order `update`, redacted `show`, `do --vm-action=status`, `connect --ssh --test`, and `connect --rdp --test` all completed successfully with no remaining live warning or error.

### Highlights
- Recorded the completed zero-warning publish cycle in the maintained release notes and prompt history.
- Confirmed the final live `show` output still redacts `VM_ADMIN_PASS` and `VM_ASSISTANT_PASS` while reporting `Hibernation enabled: True` and `Nested virtualization enabled: True`.
- Confirmed the final published VM remained healthy and reachable at the end of the loop: `VM running`, `Provisioning succeeded`, SSH test passed for `manager`, and RDP test passed for `assistant`.

## Release 2026.3.22.395 - 2026-03-22

### Summary
This release fixes the next blocker found during the restarted live `update` acceptance run after the Public Desktop cleanup fix. The rerun progressed through `136-configure-language-settings`, requested a reboot as expected, and then failed because the shared `az vm restart` wrapper still used the default 300-second Azure CLI timeout. Task-triggered restarts now run under an explicit longer Azure CLI timeout, while the existing running-state, provisioning, and SSH recovery checks stay intact.

### Highlights
- Wrapped the shared task restart helper in `Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds 900` so slower Azure restart operations triggered by heavyweight Windows tasks no longer fail at the default 300-second CLI boundary.
- Kept the downstream restart recovery contract unchanged: the helper still waits for `VM running`, repairs provisioning state when needed, and verifies SSH reachability when the caller requires SSH before continuing.
- Revalidated the change locally in `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed after the restart-timeout hardening.

## Release 2026.3.22.394 - 2026-03-22

### Summary
This release fixes the next zero-warning blocker found during the live acceptance `update` rerun after the fresh Windows create completed cleanly. The update reached `10003-create-public-desktop-shortcuts`, where removing `C:\Users\Public\Desktop\s7TikTok Business.lnk` failed because the shortcut was temporarily in use by another process. Public Desktop cleanup now retries short-lived lock collisions and keeps an existing shortcut in place when it is already semantically normalized to the current managed spec.

### Highlights
- Added a bounded retry path for locked Public Desktop `.lnk` files inside `10003-create-public-desktop-shortcuts` instead of failing on the first transient “used by another process” collision.
- Added a semantic retain path that keeps an already-correct managed shortcut in place when it remains locked, avoiding redundant replacement work and warning-only transcript noise during steady-state updates.
- Revalidated the change locally in `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed after the Public Desktop cleanup hardening.

## Release 2026.3.22.393 - 2026-03-22

### Summary
This release fixes the next zero-warning blocker found in the restarted live Windows create loop after the WSL cleanup. A fresh `create --auto --windows --perf` rerun progressed past `121-install-wsl-feature`, but `124-install-openai-codex-tool` still surfaced raw `npm notice` version-banner lines as `WARNING:` records even though the command already used `--loglevel error`. The npm-backed CLI tasks now capture merged native output locally, discard only the known benign notice/deprecation chatter, and continue to treat the real npm exit code as authoritative.

### Highlights
- Changed `124-install-openai-codex-tool`, `125-install-github-copilot-tool`, and `126-install-google-gemini-tool` so each task runs `npm install -g` through a local merged-output capture guarded by `ErrorActionPreference='Continue'`.
- Filtered only the known benign `npm notice` and `npm warn deprecated` lines before replaying task output, preventing one-shot SSH task execution from inflating the live transcript with warning-only npm chatter.
- Revalidated the change locally in `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\bash-syntax-check.ps1`; all passed after the npm-task hardening.

## Release 2026.3.22.392 - 2026-03-22

### Summary
This release fixes the remaining full-create WSL warning that was still stopping the zero-warning Windows publish loop after the previous `NativeCommandError` cleanup. The latest fresh recreate reached `121-install-wsl-feature`, but its internal readiness probe still called `wsl.exe --version` raw and surfaced the plain bootstrap guidance as `WARNING:` lines before the winget bootstrap completed. The readiness probe now captures and filters that benign first-run output locally, so the task stays warning-clean in both isolated reruns and the next full recreate attempt.

### Highlights
- Changed `121-install-wsl-feature` so `Test-WslReady` now runs `wsl.exe --version` through a local merged-output capture with `ErrorActionPreference='Continue'`, keeping the benign first-run bootstrap guidance out of the task transcript while still returning readiness from the real exit code.
- Preserved visibility for unexpected probe output by replaying only non-benign captured lines, instead of letting the known bootstrap guidance surface as transcript warnings.
- Revalidated the change locally across smoke, static audit, PowerShell compatibility, and shell syntax gates, then reran isolated live task `121-install-wsl-feature` on the active managed Windows VM and confirmed `warning=0`, `signal-warning=0`, and `error=0`.

## Release 2026.3.22.391 - 2026-03-22

### Summary
This release fixes the next zero-warning blocker found during the restarted Windows create loop after the SSH asset-copy recovery patch. The fresh run successfully passed the earlier `114-install-teams-application` failure point, but `121-install-wsl-feature` still surfaced split `NativeCommandError` transcript lines while `wsl.exe --install --no-distribution` was bootstrapping WSL for the first time. The task now treats that stderr as expected bootstrap noise, the shared SSH protocol filter suppresses the split warning shape, and isolated live reruns of `121` finish cleanly with zero warnings.

### Highlights
- Changed `121-install-wsl-feature` so its native WSL bootstrap command runs with a temporary local `ErrorActionPreference='Continue'` guard, preventing benign first-run stderr from aborting the task before its exit code and output filters are evaluated.
- Extended the shared SSH task-output warning filter to discard the exact split WSL bootstrap lines seen in the live transcript, including the relayed `wsl.exe : ...`, call-site, and `NativeCommandError` metadata fragments.
- Revalidated the fix locally in `tests\clagnos-smoke-tests.ps1` and live in isolation on the active managed Windows VM, where `task --run-vm-update 121 --windows --perf` completed with `warning=0`, `signal-warning=0`, and `error=0`.

## Release 2026.3.22.390 - 2026-03-22

### Summary
This release fixes the next live blocker discovered after the zero-warning cleanup work. During a fresh Windows create run, `vm-update` reached `114-install-teams-application` and then died while copying `clagnos-store-install-state.psm1` over pyssh because Paramiko could not read the SSH protocol banner. The VM was still healthy, but the asset-copy path lived outside the task retry loop, so one transient SSH drop aborted the whole publish flow. The SSH runner now retries task asset preparation through the same bounded task recovery path used for transport failures.

### Highlights
- Moved Windows and Linux task asset uploads inside the bounded task retry loop so transient pre-task copy failures no longer bypass task retry policy.
- Added one-shot SSH retry recovery that rechecks provisioning health, waits for SSH port reachability, and re-runs the pyssh connection bootstrap before retrying.
- Added smoke coverage that simulates a first-attempt `Error reading SSH protocol banner` during Windows task asset copy and verifies the runner recovers without inflating warning counts.

## Release 2026.3.22.389 - 2026-03-22

### Summary
This release hardens the zero-warning live publish path after the `10005-copy-user-settings` fix. The remote task protocol now suppresses stderr-prefixed benign WSL and npm chatter, the WSL feature task filters its own first-run bootstrap notices at source, and the npm-based CLI install tasks emit errors only. Together these changes remove the remaining warning-only noise that caused an otherwise healthy live `create --auto --windows --perf` run to be stopped and restarted.

### Highlights
- Filtered known benign WSL bootstrap lines directly inside `121-install-wsl-feature` after merging native stdout/stderr so the task no longer replays the `wsl.exe --install` guidance as transcript warnings.
- Added stderr-prefix normalization plus benign WSL/npm warning patterns to the SSH task-output protocol filter so remote task relays stay warning-clean.
- Changed the npm global install commands in `124`, `125`, and `126` to use `--loglevel error`, removing `npm notice` and `npm warn deprecated` chatter from live `vm-update` runs.
- Revalidated the changed paths locally in `tests\clagnos-smoke-tests.ps1` and by isolated live reruns of `121`, `124`, `125`, `126`, and `10005` on the active managed VM; each isolated rerun finished with zero warnings and zero errors.

## Release 2026.3.22.388 - 2026-03-22

### Summary
This release removes the last live `vm-update` warning still blocking the zero-warning Windows publish loop. `10005-copy-user-settings` now treats the `UsrClass` AppModel repository branch as non-portable and skips it during assistant/default classes-hive mirroring, preventing the access-denied `New-Item` failure that previously downgraded the task to a warning even though the assistant hive later existed.

### Highlights
- Added a dedicated classes-hive registry exclusion set for `10005-copy-user-settings`.
- Excluded `Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository` from `UsrClass.dat` mirroring so mounted assistant/default target hives are no longer asked to recreate protected packaged-app repository keys.

## Release 2026.3.22.387 - 2026-03-22

### Summary
This release closes the last live blocker from the assistant-profile mirror path. The dedicated target-prune exclusion set already existed, but one post-copy cleanup call still used the broader source exclusion list; that stale call is now aligned so target-owned profile hives survive the full `10005-copy-user-settings` workflow.

### Highlights
- Changed the post-copy `Remove-StaleExcludedTargetPaths` call inside `Invoke-RobocopyBranch` to use `TargetPruneExcludedDirectories` and `TargetPruneExcludedFiles`, not the broader source exclusion lists.
- This specifically preserves `C:\Users\assistant\NTUSER.DAT*` and `UsrClass.dat*` during the assistant mirror pass while still excluding those files from the copied manager source profile.

## Release 2026.3.22.386 - 2026-03-22

### Summary
This release closes the two issues that still blocked the second live Windows recreate loop: transcript noise from the Windows SCP host-key fallback path and accidental removal of the assistant profile hive during `10005-copy-user-settings`. It also finishes the Chocolatey noise filter so first-run bootstrap chatter no longer surfaces as a task warning signal.

### Highlights
- Changed the Windows SCP host-key resolver to use a non-throwing probe path before falling back to `pyssh`, eliminating repeated `PS>TerminatingError()` host-key noise from otherwise successful task asset copies.
- Changed the SSH task-output noise matcher so Chocolatey bootstrap warnings about reopening the shell and missing tab-completion profile files are filtered in the same split-line form seen during live `01-install-choco-tool` runs.
- Changed `10005-copy-user-settings` so source exclusions and target pruning are separated: `NTUSER.DAT*` and `UsrClass.dat*` remain excluded from profile mirroring, but they are no longer deleted from the assistant or default target profiles before registry replay.

## Release 2026.3.22.385 - 2026-03-22

### Summary
This release addresses the live `create --auto --windows --perf` warning set that blocked the zero-warning production target. The Windows task pipeline now filters known benign SSH/package-manager noise before it reaches warning summaries, requires a real assistant user hive before profile-copy completion, accepts deferred language-capability completion across restart boundaries, and treats Ollama process/API readiness as authoritative during cold starts while improving vm-summary readback timing.

### Highlights
- Changed the SSH task relay, warning-signal counter, and Windows SCP fallback path so known Chocolatey, WSL, Docker, and host-key fallback noise is normalized or suppressed before it can inflate `vm-update` warnings.
- Changed `10005-copy-user-settings` to require `Test-PortableProfileHiveReady` and fail explicitly when `C:\Users\assistant\NTUSER.DAT` never materializes, preventing partial-profile false success.
- Changed `135-install-ollama-tool` to prioritize process, port, and API readiness, log deferred `ollama ls` detail without surfacing a warning on cold starts, and publish `listReady` in the completion summary.
- Changed `136-configure-language-settings` to carry component-level install results into restart verification and accept deferred capability states such as `InstallPending` when Windows still needs a restart or sign-in to finish language package application.
- Changed the Windows vm-summary readback to extend Ollama API wait time when the managed startup shortcut is already healthy and to rerun `ollama ls` after the API becomes reachable.

## Release 2026.3.22.384 - 2026-03-22

### Summary
This release hardens the second Windows run-command follow-up before the live production rerun. Instead of embedding the decoded guest task through a quote-sensitive inline Base64 assignment inside the generated wrapper, Azure Run Command now writes the decoded task body to a temporary payload script, passes that payload path into the nested hidden `powershell.exe`, and relays merged task output deterministically before the explicit nested result marker is classified.

### Highlights
- Changed the Windows Azure Run Command wrapper to write the decoded guest task body to a temporary `.payload.ps1` file and invoke the nested worker with `-TaskScriptPath`, eliminating the earlier quote-fragile inline Base64 assignment path.
- Changed the nested Windows guest worker to execute the payload file content directly and relay merged `*>&1` task output back into the Azure Run Command transcript before `CLAGNOS_NESTED_RESULT:success|error` is emitted.
- Extended the smoke contract to generate the wrapper script at test time and assert the new payload handoff fragments while explicitly proving the old uninterpolated Base64 assignment fragment is gone.

## Release 2026.3.22.383 - 2026-03-22

### Summary
This release closes the follow-up false negative that still remained after the first Windows run-command timeout hardening. Successful Windows guest tasks no longer fall through as `task-result` warnings just because the nested hidden `powershell.exe` returned an ambiguous exit code; the nested worker now emits an explicit success/error marker and the outer Azure Run Command wrapper classifies task outcome from that structured marker.

### Highlights
- Added explicit `CLAGNOS_NESTED_RESULT:success|error` markers to the nested Windows guest task worker used by Azure Run Command.
- Changed the outer Windows run-command wrapper to trust the nested result marker first, keep the task timeout enforcement, and only treat missing markers as a failure condition.
- Extended smoke coverage for the new nested result markers and the missing-marker failure path.

## Release 2026.3.22.382 - 2026-03-22

### Summary
This release hardens the Windows live publish path after the March 22 fresh-create run exposed a real guest-task timeout gap. The Windows Azure Run Command wrapper now enforces the task manifest timeout against the actual nested PowerShell task process, and the new `07-configure-all-users` init task now keeps its interactive profile-materialization wait bounded so it fits within its declared timeout budget instead of blocking the whole init stage behind Azure's one-at-a-time Run Command lock.

### Highlights
- Changed the Windows run-command wrapper to execute guest task bodies through a temporary nested `powershell.exe -File <temp-script>` process, capture stdout/stderr explicitly, force-stop that child process when it exceeds the task timeout, and surface the guest failure text back into the stage transcript.
- Reduced the `07-configure-all-users` interactive materialization wait to a task-configured 20 seconds so the task can still create the durable user profile when needed without overrunning its 120-second manifest timeout during fresh create or partial init reruns.
- Extended the maintained smoke suite to cover the new nested-process timeout fragments and the shorter `configure-all-users` wait-budget contract.

## Release 2026.3.22.381 - 2026-03-22

### Summary
This release closes the create-path regression that the March 22 live publish exposed: when `VM_ENABLE_HIBERNATION=true` targeted a VM size that Azure already reported as unsupported, the old flow still created the VM and only failed afterwards during post-deploy feature enablement. The Step 1 precheck now validates known hibernation and nested-virtualization compatibility before Azure mutation, so create/update stops cleanly with a config error instead of leaving behind a partially published managed VM.

### Highlights
- Added `Assert-ClagnosFeaturePreconditions` to the shared feature-support runtime and wired it into `Invoke-ClagnosPrecheckStep`, so Step 1 now validates `VM_ENABLE_HIBERNATION` and `VM_ENABLE_NESTED_VIRTUALIZATION` against the selected region, VM size, and security type before resource-group, network, or VM deployment work begins.
- Hardened the failure mode for known unsupported feature combinations: hibernation now fails fast when Azure does not advertise `HibernationSupported=true`, and nested virtualization now fails fast when the requested VM size is known unsupported or when the VM is configured with `VM_SECURITY_TYPE=TrustedLaunch`.
- Extended the maintained smoke suite with direct fail-fast coverage for unsupported hibernation, Trusted Launch plus nested virtualization, and the new precheck call order.

## Release 2026.3.22.378 - 2026-03-22

### Summary
This release closes the remaining live Windows Ollama follow-up that was still visible in the March 20 production logs. The managed Windows Ollama install task now performs a clean Chocolatey reinstall path, verifies the client, process, TCP listener, and API explicitly, and keeps a bounded `serve` fallback for the headless Windows case where `cmd.exe /c start ... ollama ls` alone does not leave a durable runtime. The Ollama task-local app-state contract is now settings-first and limited to config files, and the Windows vm-summary readback now uses a quiet `ollama ls` health probe plus a short API wait so cold-start timing no longer produces a false unhealthy readback immediately after reboot.

### Highlights
- Switched `135-install-ollama-tool` to a clean `choco install ollama -y --no-progress --ignore-detected-reboot` flow with explicit pre-reinstall cleanup of stale Ollama footprints.
- Added bounded post-install runtime validation in `135`: detached `cmd.exe /c start ... ollama.exe ls` bootstrap, verified `ollama ls`, confirmed a running `ollama.exe` process, and validated `127.0.0.1:11434` plus `/api/version`; when the detached `ls` bootstrap is not durable on Windows, the task now falls back to hidden `Start-Process "<ollama.exe>" serve`.
- Reduced the maintained Ollama app-state contract to the three small managed config files instead of replaying the broader `AppData\Local\Ollama`, `.ollama`, and `ollama app.exe` runtime trees.
- Hardened the Windows vm-summary readback so the Ollama health section now reports the real post-bootstrap state: the latest live `vm-summary` transcript records `ollama-ls-probe => success=True`, `ollama-process-count => 2`, `ollama-port-11434-open => True`, and `ollama-api-probe => success=True; timed-out=False`.
- Revalidated the full live closure path on the active managed Windows target with a clean remote uninstall, isolated reruns of `task --run-vm-update 135` and `task --run-vm-update 10002`, explicit restarts, and a final `update --step vm-summary --windows --perf` run against the latest live VM.

## Release 2026.3.22.377 - 2026-03-22

### Summary
This release adds an explicit Windows user-profile materialization step ahead of the rest of `vm-init`, which closes the remaining assistant-profile drift that was still surfacing in live accessibility flows. The new `07-configure-all-users` task now materializes the managed local users before later tasks or app-state replay touch their profile files and hives, repairs temporary-profile registrations back to the intended profile path when needed, and removes the JAWS replay warning that the latest March 20 production logs still showed for the `assistant` user.

### Highlights
- Added `07-configure-all-users` to the tracked Windows init catalog and positioned it directly after `01-ensure-local-user-accounts`.
- Hardened the Windows profile-repair path so loaded user hives are exported into the durable profile root, the live SID registration is repaired back to the intended profile path, and locked hive transaction logs are treated as best-effort informational skips instead of task failures.
- Cleared the assistant-side JAWS replay prerequisite: after the new init task runs, the live assistant profile resolves to `C:\Users\assistant` with a real `NTUSER.DAT` hive instead of a temporary-profile mapping.
- Revalidated the change live in isolation on the active managed Windows target: `task --run-vm-init 07 --windows --perf` completed successfully, direct profile readback confirmed the repaired assistant mapping, and a follow-up isolated rerun of `task --run-vm-update 133 --windows --perf` finished with `profiles=2`, `user-registry=2`, `skipped=0`, and no `assistant => no-hive-file` warning during the JAWS app-state replay.

## Release 2026.3.20.376 - 2026-03-20

### Summary
This release closes the final regressions found during the live Windows production publish cycle. Full managed `update` runs now keep the existing public FQDN stable, the WinRM init task is cleanly idempotent during repeated maintenance passes, the language task no longer flags already-installed languages because of optional image-managed capability lag, and the Unicode Public Desktop shortcut verification path now accepts reconciled written filenames instead of raising a false warning.

### Highlights
- Fixed `06-configure-powershell-remoting` so repeated `vm-init` runs keep `Remote Management Users` membership quiet and deterministic instead of surfacing a false task-result warning.
- Fixed managed public DNS label resolution for existing public IPs so maintenance updates preserve the current `vm_name-vm{id}` label instead of drifting to the next suffix.
- Fixed `136-configure-language-settings` so installed-language state is accepted when optional language capability packages remain image-managed in the Windows image.
- Fixed `10003-create-public-desktop-shortcuts` so Unicode shortcut names such as the Turkish public-web labels are verified through normalized reconciliation instead of exact-path-only checking.
- Revalidated the full live acceptance path after the fixes: clean managed create already succeeded earlier in the same publish cycle, the final full natural-order `update --auto --windows --perf` run reached zero warnings and zero signal warnings, `show` and lifecycle status were healthy, SSH and RDP tests passed, and a real WinRM `Invoke-Command` succeeded with the managed `manager` account.

## Release 2026.3.19.375 - 2026-03-19

### Summary
This release closes the Windows app-state replay warning cleanup and adds operator-visible WinRM support to the managed Windows contract. The replay engine now treats optional locked and unavailable state as info-only skips, the warning-producing Windows task-local plugins were refreshed to the current portable model, the Windows init catalog now includes `06-configure-powershell-remoting`, `vm-summary` now prints PowerShell remoting commands beside SSH and RDP, and the latest full live `vm-update -> vm-summary` run completed with zero warnings and zero signal warnings.

### Highlights
- Hardened Windows app-state replay, verification, and rollback so in-use files, unavailable user hives, and optional access-denied targets no longer degrade the maintained update stage into false warnings.
- Refreshed the maintained task-local app-state payload handling for OneDrive, AnyDesk, Teams, WhatsApp, Google Drive, and JAWS, and fixed stale zip replacement during live `task --save-app-state` refreshes.
- Added `06-configure-powershell-remoting` to Windows `vm-init`, enabled WinRM on TCP `5985`, and rendered ready-to-run `Enter-PSSession` and `Invoke-Command` examples in the Windows summary output.
- Switched the Windows advanced-settings task to a Store-safe silent UAC model that keeps `EnableLUA=1` while suppressing admin prompts.
- Tuned the current Docker Desktop, Ollama, and language follow-up paths so Docker keeps checking daemon readiness when the interactive process is still materializing, Ollama probes read the API more reliably, and language servicing accepts queued success sooner instead of waiting at the old upper bound.
- Revalidated the full live closure path: the final `update --auto --windows --perf --step-from=vm-update --step-to=vm-summary` run reached `warning=0`, `signal-warning=0`, and `error=0`, and WinRM remoting succeeded immediately afterward with a real `Invoke-Command`.

## Release 2026.3.19.374 - 2026-03-19

### Summary
This release repairs the fresh Windows live path that had just started failing at the first SSH asset copy during `vm-update`. The root cause was local host-key fingerprint discovery, not guest SSH reachability: the local `ssh-keyscan.exe` build could not negotiate the newer KEX set offered by the fresh Windows OpenSSH server, so the Windows SCP transport now falls back cleanly to the existing pyssh copy/fetch path when trusted fingerprint discovery cannot be resolved locally.

### Highlights
- Kept `pscp.exe` with trusted host-key discovery as the primary Windows asset-copy transport.
- Added a bounded fallback from Windows SCP to pyssh copy/fetch when local host-key fingerprint discovery cannot be resolved for a Windows path.
- Fixed the fallback cleanup path so pyssh-only transfers no longer try to remove an empty SCP password-file path.
- Revalidated `tests\clagnos-smoke-tests.ps1`, `tests\code-quality-check.ps1`, and a live isolated `task --run-vm-update 01` run; all passed, and the live task completed successfully through the new fallback path.

## Release 2026.3.19.373 - 2026-03-19

### Summary
This release repairs the failing `quality-gate` run on `main` without changing the public command surface. The Windows startup-profile JSON path now behaves consistently in Windows PowerShell 5.1 and PowerShell 7+, the maintained smoke suite no longer depends on version-specific JSON-array behavior, and the tracked release docs no longer trip the sensitive-content audit with concrete managed-target identifiers.

### Highlights
- Fixed the startup-profile decode path used by `10002-configure-startup-settings` and the Windows summary readback so approved startup-profile arrays enumerate correctly in Windows PowerShell 5.1.
- Fixed the startup-profile smoke assertions so the maintained non-live contract now matches the shared PowerShell 5.1-safe JSON-array handling.
- Sanitized the tracked release/changelog/history wording so the sensitive-content audit passes again while preserving the operator-visible validation record.
- Revalidated `tests\sensitive-content-check.ps1`, `tests\clagnos-smoke-tests.ps1`, `tests\powershell-compatibility-check.ps1`, and `tests\code-quality-check.ps1` locally; all now pass cleanly.

## Release 2026.3.19.372 - 2026-03-19

### Summary
This release turns Windows `10002-configure-startup-settings` into an app-state-driven startup-profile task and validates the new behavior live on the managed Windows VM. The approved startup set now applies additively to both `manager` and `assistant`, task-local startup intent lives in `app-state/app-state.zip`, and the final isolated rerun completed warning-free before and after an explicit VM restart.

### Highlights
- Added a task-local startup-profile contract for `10002-configure-startup-settings`, carried through task discovery, runtime materialization, and local `task --save-app-state --source=lm` generation.
- Refactored `10002` so it no longer hardcodes the approved app list in the script body and instead applies the managed startup set from `extensions/startup-profile.json` inside the task-local plugin zip.
- Hardened the assistant-profile path by seeding/materializing the profile hive when necessary and by preferring a portable current-user Startup folder surface for assistant-side managed current-user apps.
- Revalidated the change live in isolation on the active managed Windows target: the final `10002` rerun completed with `warning=0`, `signal-warning=0`, and `error=0`.
- Rebooted the managed Windows VM after the isolated task run and confirmed that the machine entries, the `manager` startup artifacts, and the `assistant` startup artifacts all persisted across reboot. Post-reboot process evidence remained partial for some apps, and those residual gaps are reported as informational follow-up only.

## Release 2026.3.19.371 - 2026-03-19

### Summary
This release captures the latest selective Windows maintenance commits that were already validated as safe: updated task timeout budgets, `exec --file` one-shot SSH support, a more resilient Docker Desktop recovery path, and faster Windows language/user-settings completion behavior. The tracked smoke contract is now aligned with those approved changes and passes cleanly again.

### Highlights
- Raised the approved Windows init and update task timeout budgets and kept the tracked manifest contract in sync with the live-tuned values.
- Added `clagnos exec --file <script-file>` so operators can run one local script remotely through the same SSH one-shot path without quoting multi-line command text manually.
- Hardened the Docker Desktop task to clear stale uninstall registration and to tolerate guest images where native `Start-Service` succeeds but `net start` is not the right follow-up signal for every prerequisite service.
- Refined `136-configure-language-settings` and `10005-copy-user-settings` so already-satisfied queued language installs recover faster and non-portable profile artifacts are skipped explicitly during user-settings copy.
- Revalidated the maintained non-live gate with `tests\clagnos-smoke-tests.ps1`; the suite passed with `Passed: 156, Failed: 0`.

## Release 2026.3.19.364 - 2026-03-19

### Summary
This release makes the Windows Public Desktop social and business-web shortcuts configurable through local `.env` values without breaking the tracked generic shortcut contract. The `10003` task now reads optional override URLs for the managed `s1-s18` shortcut set, falls back cleanly when those values are blank, and the interactive `configure` editor exposes the same URL fields so local operators can manage them without editing task code.

### Highlights
- Added optional local `.env` override keys for the managed Windows social and business-web shortcut URLs used by `10003-create-public-desktop-shortcuts`.
- Carried those URL overrides through the runtime context and task materialization pipeline so they work in normal runs and isolated `task --run-vm-update 10003` executions.
- Updated the interactive `configure` schema and validation surface so every new shortcut URL key is visible and verified as an optional HTTP/HTTPS value.
- Revalidated the behavior live in isolation on the active managed Windows VM: `10003-create-public-desktop-shortcuts` completed with `warning=0`, `signal-warning=0`, and `error=0`, and direct shortcut readback confirmed the business and personal social/web URLs now resolve from local `.env` overrides.

## Release 2026.3.19.363 - 2026-03-19

### Summary
This release fixes the remaining Turkish naming drift in the Windows Public Desktop shortcut flow. The visible managed shortcut labels now stay correctly Turkish on Windows PowerShell 5.1 as well as PowerShell 7+, the old `q1SourTimes` shortcut is replaced by `q1EkşiSözlük`, and stale mojibake desktop entries such as `r13Ã‡iÃ§ekSepeti Business` are normalized back to their intended `ÇiçekSepeti` names during the managed cleanup pass.

### Highlights
- Reworked the shared shortcut launcher helper so Turkish shortcut names are normalized and transliterated from PowerShell-safe Unicode code points instead of fragile raw source literals.
- Renamed the managed quick-access shortcut from `q1SourTimes` to `q1EkşiSözlük` while keeping cleanup aliases for the previous English and ASCII spellings.
- Updated the Windows summary readback contract so the live shortcut inventory now validates `q1EkşiSözlük`, `r13ÇiçekSepeti Business`, and `r14ÇiçekSepeti Personal` consistently.
- Revalidated the change live in isolation on the active managed Windows VM: `10003-create-public-desktop-shortcuts` completed with `warning=0`, `signal-warning=0`, and `error=0`, and direct `exec` readback confirmed the corrected Turkish shortcut names and targets on `C:\Users\Public\Desktop`.

## Release 2026.3.18.362 - 2026-03-18

### Summary
This release closes the last CI-only drift that was still blocking the remote quality gate. The managed public DNS label helper now honors an explicitly provided empty managed public IP list, which keeps the smoke and compatibility tests fully local in GitHub Actions instead of attempting live Azure inventory reads.

### Highlights
- Updated `Resolve-ClagnosPublicDnsLabel` so explicit empty managed public IP overrides stay local and deterministic.
- Removed the concrete managed VM name from the latest changelog note so the sensitive-content audit stays green.
- Revalidated the affected non-live gates locally before re-publishing `main`.

## Release 2026.3.18.361 - 2026-03-18

### Summary
This release restores the tracked Windows `vm-update` timeout contracts that the remote quality gate expects. Local validation had already been running against the longer live task budgets, but `main` still carried shorter timeout manifests for several maintained Windows tasks, which kept the smoke and compatibility jobs red on GitHub Actions.

### Highlights
- Updated the tracked timeout budgets for Windows tasks `110`, `111`, `113`, `115`, `119`, `122`, `123`, `126`, `127`, `128`, `129`, `130`, `132`, and `133`.
- Realigned the remote smoke and compatibility expectations with the live task budgets that were already being validated locally.
- Revalidated the affected non-live gates locally before re-publishing the branch heads.

## Release 2026.3.18.360 - 2026-03-18

### Summary
This release replaces the slow Windows 11 OpenSSH capability bootstrap in `vm-init` with an official Win32-OpenSSH MSI bootstrap. Fresh Windows builds were spending minutes inside Azure Run Command while the capability path waited on servicing; the new path installs the official server package directly, recovers the `sshd` service deterministically, and reaches a working SSH listener fast enough for the rest of the init flow.

### Highlights
- Updated `03-install-openssh-service` to download and install the official Win32-OpenSSH MSI, then recover or register `sshd` only when needed.
- Updated the install task so it refreshes and logs the real running `sshd` state after startup instead of reporting a stale stopped state.
- Updated the OpenSSH smoke contract to assert the MSI bootstrap fragments alongside the existing service-recovery paths.
- Revalidated the non-live gates plus the live Windows bootstrap path with isolated `03`, isolated `04`, and `connect --ssh --test` on the current managed VM.

## Release 2026.3.18.359 - 2026-03-18

### Summary
This release restores the main GitHub Actions quality gate. Two stale committed surfaces were causing the run to fail: the tracked Windows GitHub CLI task in `HEAD` still used a 30-second timeout even though the live contract expects 180 seconds, and `docs/prompt-history.md` still carried a banned personal token that the sensitive-content audit rejects.

### Highlights
- Updated the maintained Windows `107-install-gh-tool` timeout contract back to 180 seconds.
- Redacted the banned personal token from the prompt-history workflow-fix entry.
- Revalidated the affected non-live gates locally so the quality gate now matches the intended committed state again.

## Release 2026.3.18.358 - 2026-03-18

### Summary
This release fixes the live create-resume path for interrupted fresh Windows builds. A partial `create` window that started at `vm-init` or later was still entering the fresh create naming path and generating a new managed resource group name, which made the resume command fail immediately with `ResourceGroupNotFound` even though the original create had already provisioned the real managed target successfully.

### Highlights
- Updated the create runtime so partial `create` windows that begin at `vm-init`, `vm-update`, or `vm-summary` now resolve and lock the existing managed VM target instead of generating a fresh `gX` resource group.
- Updated the main pipeline so `create` can keep its create-mode workflow and banner while using existing-target step-1 semantics for those resume-only step windows.
- Added a smoke regression that proves `create --step-from vm-init` reuses the actual managed resource group, location, and network/disk names from Azure.
- Revalidated `tests\clagnos-smoke-tests.ps1`; the maintained smoke suite passes fully with the new resume contract.

## Release 2026.3.18.357 - 2026-03-18

### Summary
This release fixes the latest failing `quality-gate` workflow on `main`. The run was failing in the non-live smoke and compatibility jobs because the committed task contracts were still behind the intended Windows `106`, `121`, and `135` behavior. The updated contracts restore the tracked `106` timeout, make WSL bootstrap accept the feature-enabled ready state after `wsl --install --no-distribution`, and narrow the Ollama installer process filter so the version/readiness checks work cleanly in both Windows PowerShell 5.1 and PowerShell 7+.

### Highlights
- Updated `106-install-7zip-tool` back to the tracked 90-second timeout expected by the compatibility matrix.
- Updated `121-install-wsl-feature` to add `Test-WslBootstrapSatisfied`, which treats the WSL and VirtualMachinePlatform feature-enabled state as a valid bootstrap completion condition when the live `wsl` runtime is still settling after install.
- Updated `135-install-ollama-tool` so its installer process filter no longer matches unrelated app names and its `ollama --version` output is normalized through a warning-filtered helper.
- Revalidated `tests\clagnos-smoke-tests.ps1` and `tests\powershell-compatibility-check.ps1` locally; both now pass, including the Windows PowerShell 5.1 compatibility target that had been failing in CI.

## Release 2026.3.18.356 - 2026-03-18

### Summary
This release closes the last tracked Windows `vm-update` `--force` gap and finishes the Azure CLI validation path. The maintained smoke suite had still been failing because `130-install-azure-cli-tool` kept one forceful Chocolatey uninstall path and `134-install-docker-desktop-application` still used `winget source reset --force`. The Azure CLI task also had one live drift left: it could prove `az` healthy through a direct executable path while fresh later `cmd` shells still could not resolve `az`.

### Highlights
- Updated `130-install-azure-cli-tool` so an unhealthy existing Azure CLI is removed without `--force`, uninstall success is confirmed from Chocolatey package state, and the resolved Azure CLI command directory is added back into machine PATH before the task exits.
- Added a bounded `winget install Microsoft.AzureCLI` fallback in `130-install-azure-cli-tool` for the observed live case where the Chocolatey path does not materialize a resolvable `az` command cleanly enough.
- Updated `134-install-docker-desktop-application` so its bounded winget source repair uses `winget source reset` without `--force`.
- Revalidated `130-install-azure-cli-tool` live in isolation on the active managed Windows VM by uninstalling Azure CLI to clean state, rerunning the task, and confirming a fresh `cmd /c az version` succeeds with the final task summary at `warning=0`, `signal-warning=0`, and `error=0`.
- Revalidated `tests\clagnos-smoke-tests.ps1` and `tests\code-quality-check.ps1`; both now pass for this no-force contract update.

## Release 2026.3.18.355 - 2026-03-18

### Summary
This release is a focused Windows shortcut-contract hardening pass. The Public Desktop shortcut task already covered the intended Store apps, classic apps, and Chrome/Edge browser shortcut surface, but its `VS2022` and `JAWS` target resolution was still weaker than the installer tasks that own those applications. The shortcut task now uses the same richer discovery paths, so it does not miss a valid target that the installer has already proven healthy.

### Highlights
- Updated `10003-create-public-desktop-shortcuts` so it now resolves `devenv.exe` through `vswhere.exe` and the canonical Community install paths instead of trusting one hard-coded path only.
- Updated the same task so it now resolves `jfw.exe` through the Freedom Scientific registry roots before falling back to canonical JAWS install paths.
- Revalidated the non-live shortcut contract in `tests\clagnos-smoke-tests.ps1`; the `10003` coverage assertions passed with the new resolvers, while the suite still reports one unrelated pre-existing failure in `130-install-azure-cli-tool.ps1` about `--force`.

## Release 2026.3.18.354 - 2026-03-18

### Summary
This release closes the remaining isolated warning paths that were still open after the Docker fix. Visual Studio 2022 Community and JAWS both needed more realistic post-install readback on the active managed Windows VM, and the JAWS task-local app-state flow still needed to capture the real local HKCU/settings payload while skipping impossible guest replay work for a managed user profile that had no hive file.

### Highlights
- Updated `132-install-vs2022community-application` so it now resolves `devenv.exe` through both canonical install paths and `vswhere.exe`, then tolerates transient non-standard Chocolatey exits if Visual Studio 2022 Community has already landed cleanly.
- Updated `133-install-jaws-application` so it now repairs noisy winget source state, tolerates the observed noisy install exit when package registration and install evidence exist, and resolves `jfw.exe` recursively under the registered installation root instead of assuming one fixed path.
- Updated the task-local JAWS state flow end to end: local portable app-state capture now includes the current-user Freedom Scientific HKCU payload and `AppData\Roaming\Freedom Scientific\JAWS\2025\Settings`, and guest replay now skips managed-user registry import when there is no real hive surface to target.
- Revalidated live in isolation on the active managed Windows VM by uninstalling Visual Studio 2022 Community and JAWS, rerunning `132` and `133` from clean state, then rerunning the JAWS follow-up tasks `1001` and `10002` until every stage summary reached `warning=0`, `signal-warning=0`, and `error=0`.

## Release 2026.3.18.353 - 2026-03-18

### Summary
This release closes the remaining Windows Docker Desktop gap that was still leaving `docker info` unhealthy on the active managed VM even after the Desktop frontend and WSL features appeared to be present. The working local machine pattern showed one more required step: after the interactive Desktop launch, the task still needed to request `docker desktop start` explicitly so the backend would materialize the Linux engine and the `docker-desktop` WSL distro.

### Highlights
- Updated `134-install-docker-desktop-application` so it now treats `vmcompute`, `hns`, and `wslservice` as first-class prerequisites when present, seeds the managed Docker Desktop profile with the accepted license/settings state, keeps `com.docker.service` in the manual/stopped WSL2-aligned mode, and explicitly runs `docker desktop start` before the bounded `docker desktop status` and `docker info` probes.
- Removed the stale tracked Docker Desktop task-local app-state plugin zip because it was replaying transient Desktop lockfiles into healthy reruns and producing a non-actionable app-state signal warning even when the Docker engine itself was ready. The task now relies on its managed in-script profile seeding for the required Desktop state.
- Revalidated the exact live path on the active managed Windows VM: `docker desktop status`, `docker info`, and `wsl -l -v` all showed the expected running Docker Desktop engine state, and isolated `task --run-vm-update 134 --perf` against that target finished with `warning=0`, `signal-warning=0`, and `error=0`.

## Release 2026.3.18.352 - 2026-03-18

### Summary
This release closes a workflow-level race in the Windows publish path. The earlier OpenSSH fixes made `03-install-openssh-service` reliable on a stabilized disposable VM, but the full `create` workflow was still entering `vm-init` while Azure sometimes kept the brand-new VM in provisioning state `Updating`. The pipeline now waits for provisioning recovery before `vm-init`, and the redeploy repair used during that wait can run longer than the generic Azure CLI timeout.

### Highlights
- Added a provisioning-ready gate before `vm-init` so create/update do not start init tasks while Azure still reports the target VM as `Updating`.
- Extended the Azure CLI timeout budget for the built-in provisioning-repair redeploy path, preventing the repo-wide `AZURE_COMMAND_TIMEOUT_SECONDS=300` value from cutting off that recovery action too early.
- Added non-live regression coverage for both the new `vm-init` provisioning gate and the extended redeploy timeout contract.

## Release 2026.3.18.351 - 2026-03-18

### Summary
This release removes one more hidden blocker from the Windows publish path. The previous fix kept Azure CLI alive long enough for long `vm-init` Run Command tasks, but the Windows PowerShell wrapper was still launching guest scripts inside a nested background job. On the active image, that nested job path interfered with `Add-WindowsCapability` and kept OpenSSH Server from landing cleanly. The wrapper now runs PowerShell init tasks directly inside the Run Command session, and the OpenSSH task budget was lifted to match the measured first-install duration under that simpler path.

### Highlights
- Simplified the Windows PowerShell Run Command wrapper so it now executes tracked init scripts directly instead of through `Start-Job` plus a second nested `powershell.exe` timeout layer.
- Raised the tracked timeout budget for `03-install-openssh-service` to cover the measured first-install path on the active Windows image when OpenSSH Server is genuinely absent.
- Revalidated the exact first-install scenario live by removing the OpenSSH Server capability from the disposable managed VM, rerunning `03`, rerunning `04`, and then passing `connect --ssh --test`.

## Release 2026.3.18.350 - 2026-03-18

### Summary
This release hardens the transport layer around long Windows `vm-init` Run Command tasks. The OpenSSH guest bootstrap had already been fixed, but the second clean publish retry still failed because Azure CLI itself stopped waiting after the repo-wide `AZURE_COMMAND_TIMEOUT_SECONDS=300` limit even though `03-install-openssh-service` had a legitimate `360` second task budget. The Run Command runner now temporarily lifts the Azure CLI timeout to match the task budget plus buffer.

### Highlights
- Added a temporary Azure CLI timeout override helper so long Run Command tasks can exceed the generic repo-wide Azure CLI timeout without weakening the default timeout for unrelated Azure operations.
- Updated the Windows Run Command task runner to request at least `task-timeout + 120s` for each `az vm run-command invoke` call, then restore the previous CLI timeout after the invocation finishes.
- Added smoke and compatibility coverage to keep the timeout-override contract pinned in the maintained test suite.

## Release 2026.3.18.349 - 2026-03-18

### Summary
This release is a targeted Windows OpenSSH hotfix for the live publish path. The first-run OpenSSH capability install on the active Windows image needed more than the old `180` second init budget, and the inbox image exposed `sshd.exe` plus `ssh-keygen.exe` without exposing `install-sshd.ps1`. The OpenSSH init chain now tolerates that reality and keeps the first live `create` path from stalling before SSH comes up.

### Highlights
- Raised the tracked timeout budget for `03-install-openssh-service` so a first-run Windows capability install can complete inside Azure Run Command instead of being cut off before `sshd` registration settles.
- Fixed `03-install-openssh-service` so it now recovers missing `sshd` registration directly from the OpenSSH executable and can emit a reboot-required marker when the capability is still pending.
- Fixed `04-configure-sshd-service` so it now shares the same direct `sshd.exe` recovery path and regenerates host keys through `ssh-keygen.exe` before the repo-managed `444` listener is started.
- Revalidated the fix non-live and then live in isolation on the fresh managed Windows target with successful reruns of `03`, `04`, and `connect --ssh --test`.

## Release 2026.3.18.348 - 2026-03-18

### Summary
This release refactors the active Windows task catalog around two themes: a consistent `[verb]-[entity]-[target-type]` naming contract and a cleaner Windows guest bootstrap/runtime surface. Chocolatey now starts in the Windows `vm-update` initial band, OpenSSH no longer depends on Chocolatey during `vm-init`, the old combined npm bootstrap task is split into three standalone CLI tasks, and Windows PATH refresh no longer depends on `refreshenv.cmd`.

### Highlights
- Renamed the active Windows `vm-init` and `vm-update` catalog to a consistent target-type-oriented scheme, including `01-install-choco-tool`, `02-install-winget-tool`, `114-install-teams-application`, `124-install-openai-codex-tool`, `125-install-github-copilot-tool`, `126-install-google-gemini-tool`, `134-install-docker-desktop-application`, and `10003-create-public-desktop-shortcuts`.
- Moved Chocolatey bootstrap from `vm-init` to the Windows `vm-update` initial band and rewrote the Windows OpenSSH init path so `03-install-openssh-service` now installs the Windows capability with an inbox recovery path instead of requiring Chocolatey first.
- Split the old combined Windows npm task into three standalone tracked tasks with separate task-local app-state plugin zips and separate manifest task names for Codex CLI, GitHub Copilot CLI, and Gemini CLI.
- Replaced the Windows `refreshenv.cmd` path refresh pattern with a shared registry-backed helper module and propagated that helper through the touched Windows task surface, the Store install-state helper, and the Windows summary readback path.
- Hardened `121-install-wsl-feature`, `134-install-docker-desktop-application`, and `136-configure-language-settings`: WSL now begins with `wsl --install --no-distribution`, Docker now waits for both `docker desktop status` and `docker info` readiness before success, and the language task now exits cleanly when the Turkish capability state is already satisfied even if the lingering scheduled worker never writes a result file.
- Revalidated the release non-live and live in isolation on the active managed Windows VM, including successful isolated reruns of `03`, `04`, `01`, `121`, `124`, `125`, `126`, `134`, and the fixed `136` language task with its reboot and SSH recovery.

## Release 2026.3.18.347 - 2026-03-18

### Summary
This release makes the managed Windows Public Desktop shortcut surface truly dual-user. `10003-create-shortcuts-public-desktop` now repairs Microsoft Store AppsFolder registrations for both `manager` and `assistant` before it normalizes shortcuts, and the same task now preserves user-relative shortcut commands instead of freezing user-scoped CLI or app paths to whichever profile generated the shortcut set.

### Highlights
- Added a reusable AppX registration repair helper to `tools/scripts/clagnos-interactive-session-helper.ps1`, so the repo can validate or repair `shell:AppsFolder` visibility for a selected managed user through the existing scheduled-task automation path instead of trusting only the current SSH session inventory.
- Changed `10003-create-shortcuts-public-desktop` so it now copies that helper as a tracked task asset, runs manager-and-assistant AppsFolder repair for Teams, Be My Eyes, Codex App, WhatsApp Business, and iCloud, and uses a `120` second task timeout to cover that extra dual-user validation work.
- Fixed the Public Desktop shortcut generation path so user-scoped shortcuts such as `k1Codex CLI`, `k2Gemini CLI`, `k3Github Copilot CLI`, `t4Ollama App`, and `v5VS Code` now keep `%UserProfile%` or `%LocalAppData%` in their managed contract instead of persisting one concrete `C:\Users\<name>\...` path into a shared desktop shortcut.
- Revalidated live on the active managed Windows VM through isolated reruns of `10003`, then confirmed from the repaired VM state that the dual-user Store AppID repairs complete successfully for both managed users and that the critical user-scoped Public Desktop shortcuts now keep the intended user-relative launch contract.

## Release 2026.3.18.346 - 2026-03-18

### Summary
This release finishes the shared Microsoft Store repair path for all repo-managed Windows `winget -s msstore` apps. Microsoft Teams now uses the same interactive-desktop and persisted Store-state contract as the other Store-backed tasks, and isolated reruns of those Store tasks now refresh Public Desktop shortcuts automatically by appending `10003-create-shortcuts-public-desktop` in the same task execution.

### Highlights
- Changed `105-install-teams-system` so Teams now uses the shared interactive Store install flow, persisted Store-state records, launch-target validation, and legacy pre-renumber state-file fallback already used by the other Store-backed Windows update tasks.
- Changed isolated Windows `task --run-vm-update` behavior so reruns of `105`, `115`, `116`, `117`, and `122` automatically append `10003-create-shortcuts-public-desktop`, which keeps Public Desktop shortcut refresh inside the same diagnostic or repair run without re-enabling the workflow-only final restart.
- Fixed `10003-create-shortcuts-public-desktop` so Teams now follows the same Store-managed shortcut contract as Codex, Be My Eyes, WhatsApp Business, and iCloud, preferring `C:\Windows\explorer.exe` plus `shell:AppsFolder\<AUMID>` when the live VM resolves a valid AppsFolder AppID.
- Revalidated live on the active managed Windows VM with isolated reruns of `105`, `115`, `116`, `117`, and `122`, then confirmed through `exec` that `o2Teams`, `a2CodexApp`, `a3Be My Eyes`, `a4WhatsApp Business`, and `d4ICloud` all exist on the Public Desktop and point to `explorer.exe` with `shell:AppsFolder\...` launch arguments.

## Release 2026.3.18.345 - 2026-03-18

### Summary
This release hardens the Windows Microsoft Store task flow around autologon state. The touched Store-backed tasks now explain exactly why the manager desktop is unavailable when autologon has been disabled, wait briefly when autologon is already configured but the post-boot desktop is still initializing, and then continue to the real Store install only when the interactive desktop is actually ready.

### Highlights
- Changed the shared interactive-session helper so Store tasks now emit an explicit `interactive-desktop-state` line and classify `autologon-disabled`, wrong-user autologon, pending desktop, and `explorer.exe`-not-ready cases separately.
- Fixed the no-autologon path for `115-install-be-my-eyes`, `116-install-whatsapp-system`, `117-install-codex-app`, and `122-install-icloud-system` so they now produce clear warning guidance to run `102-autologon-manager-user` and restart the VM, instead of crashing on missing Winlogon values or emitting a generic desktop-missing message.
- Changed the same four tasks so they perform one bounded desktop-readiness wait only when autologon is already configured for the manager user, which keeps the post-autologon boot path deterministic without hiding true no-autologon warnings.
- Increased the tracked timeouts for `115-install-be-my-eyes`, `116-install-whatsapp-system`, and `117-install-codex-app` to `90` seconds so the bounded readiness wait still fits inside isolated task runs.
- Revalidated live through a full two-phase isolated-task scenario on the active managed Windows VM: autologon disabled plus all four Store apps removed, reboot into a no-desktop state, isolated reruns of `115`, `116`, `117`, and `122` confirming the new warning path, an isolated rerun of `102-autologon-manager-user` with its reboot, and post-reboot reruns of `115`, `116`, `117`, and `122` confirming successful reinstall and final AppID readback for Be My Eyes, WhatsApp, Codex, and iCloud.

## Release 2026.3.18.344 - 2026-03-18

### Summary
This release finishes the current Windows Microsoft Store repair path. The touched Store-backed tasks now install Be My Eyes, WhatsApp, Codex App, and iCloud through the manager interactive desktop token when that desktop is available, keep warning-producing degraded outcomes when that desktop is missing, and let `10003-create-shortcuts-public-desktop` recover from stale Store state by trusting live AppsFolder launch targets when the VM already has the app installed.

### Highlights
- Changed `115-install-be-my-eyes`, `116-install-whatsapp-system`, `117-install-codex-app`, and `122-install-icloud-system` so the Microsoft Store install step now runs under the manager interactive desktop token instead of the SSH/service session whenever the manager desktop is available.
- Changed the same tasks so a missing interactive manager desktop is no longer treated as a quiet informational skip; they now persist degraded Store state and remain warning-producing until an interactive desktop is ready.
- Upgraded WhatsApp and Codex to the same interactive-desktop automation pattern already used by the other Store-backed tasks, while preserving explicit Store state persistence and no-deferred-boot failure semantics.
- Changed Store detection to prefer AppsFolder AppIDs where available, which aligns the launch-ready state with the desired `explorer.exe shell:AppsFolder\<AUMID>` shortcut contract.
- Fixed `10003-create-shortcuts-public-desktop` so stale `skipped` or `degraded` Store state no longer prevents shortcut recovery when the live VM can already resolve the real AppsFolder target or launch-ready executable.
- Revalidated live with `exec` on the active managed Windows VM and confirmed launch-ready AppIDs for Be My Eyes, WhatsApp, Codex, and iCloud. After isolated reruns of tasks `115`, `116`, `117`, `122`, and `10003`, the Public Desktop shortcuts `a2CodexApp`, `a3Be My Eyes`, `a4WhatsApp Business`, and `d4ICloud` all resolved through `C:\Windows\explorer.exe` with `shell:AppsFolder\...`, and `10003` finished with `warning=0`, `signal-warning=0`, and `final-restart=0`.

## Release 2026.3.17.343 - 2026-03-17

### Summary
This release cleans up the remaining warning noise around `10003-create-shortcuts-public-desktop` and narrows the final Windows `vm-update` restart to end-to-end workflow runs only. Public Desktop shortcut generation now treats optional missing app/console targets and already-degraded Store installs as informational skips, while isolated `task --run-vm-update` reruns keep task-signaled immediate restarts but no longer perform the workflow-only final restart before `vm-summary`.

### Highlights
- Changed `10003-create-shortcuts-public-desktop` so optional unresolved app and console targets log informational `public-shortcut-skip` lines instead of warnings, which removes false-positive shortcut warnings from partial or isolated Windows task reruns.
- Fixed the same shortcut task so Store-backed shortcuts whose install state is already `skipped` or `degraded` no longer duplicate that condition as a second warning during Public Desktop shortcut creation.
- Added legacy Store-state alias fallback for Be My Eyes, WhatsApp, Codex App, and iCloud so existing VMs with pre-renumber JSON state files still feed the current shortcut/runtime helpers correctly.
- Scoped the final Windows `vm-update` restart behind an explicit workflow switch in the shared SSH task runner, so only end-to-end `create` and `update` request that extra restart; isolated `task --run-vm-update` reruns now finish without the workflow-only restart unless the task itself requested a reboot.
- Updated README, CLI help, smoke coverage, and documentation-contract checks to describe the new isolated-task restart contract explicitly.
- Revalidated the release non-live with the smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates, then reran isolated live task `10003` on the active managed Windows VM and confirmed `warning=0`, `signal-warning=0`, and `final-restart=0`.

## Release 2026.3.17.342 - 2026-03-17

### Summary
This release fixes the Windows update-ordering and renumber drift that showed up in the latest create logs, restores autologon to the start of the normal update band, and switches managed public FQDN allocation to the requested `vm_name-vm{id}` format. The same pass also raises the Teams Store-install timeout to `75` seconds, makes Store-backed tasks skip cleanly when no interactive manager desktop is available, and hardens the successful isolated-task cleanup path so Google Drive no longer drops the session into PowerShell debug mode after a successful run.

### Highlights
- Reordered the Windows normal `vm-update` band so `101-install-sysinternals-suite` runs first, `102-autologon-manager-user` runs second, and the remaining normal tasks keep their relative order under the new numbering.
- Fixed runtime task discovery so dependency-safe ready-task selection now sorts by `priority` first instead of letting timeout-first ordering run tasks such as `#106` ahead of lower-priority ready tasks.
- Repaired renumber drift across shipped `app-state.zip` manifests, live app-state/export maps, summary readback, task-specific helper constants, and public-shortcut task references so canonical task names are used consistently again.
- Changed `102-autologon-manager-user` to log interactive-session readiness and emit the reboot-required marker, which lets isolated task runs and the shared task runner restart immediately before later Store tasks continue.
- Changed `105-install-teams-system` to keep the unattended Microsoft Store `winget` install path but use a `75s` timeout, and changed the other Store-backed tasks so a missing interactive session becomes a clean informational skip with persisted `skipped` state instead of a warning-style degradation.
- Replaced the old public-IP-name-based DNS label logic with managed attached-public-IP counting, so newly created managed VMs now get labels such as `test-vm1.austriaeast.cloudapp.azure.com`, with collision fallback to the next free id and live DNS-settings fallback when `az vm show -d` omits `fqdns`.
- Hardened transcript shutdown so successful isolated tasks such as `126-install-google-drive` now return normally instead of dropping the main PowerShell process into debug mode.
- Revalidated the change non-live with the full local quality gates and live only through isolated Windows task reruns for `101`, `102`, `105`, `115`, `116`, `117`, `122`, `126`, and `10003`; this release does not claim a fresh end-to-end live `create` acceptance run.

## Release 2026.3.17.341 - 2026-03-17

### Summary
This release completes the VM task-catalog refactor. `vm-init` and `vm-update` now share the normalized timeout contract, reboot-signaling tasks restart the VM immediately instead of deferring restart ownership to the stage wrapper, Windows `vm-update` ends with one unconditional final restart, and the old task-based health snapshot has been removed in favor of a read-only `vm-summary` readback block. The same pass also reorders and renumbers the task catalogs, moves Windows autologon into the final update band, and narrows `10005-copy-settings-user` to a portable manager-state mirror only.

### Highlights
- Normalized all tracked and local VM task timeouts to the shared `30s` minimum plus `15s` upward-rounding contract, and taught runtime task discovery to enforce the same rule centrally.
- Reordered and renumbered the Windows task catalogs, keeping dependency-safe ordering inside the existing `initial` / `normal` / `local` / `final` bands, moving `autologon-manager-user` into the final Windows update band, and removing the old `capture-snapshot-health` task from both Windows and Linux update inventories.
- Added dependency-aware task discovery that sorts by dependency safety first, then normalized timeout, then observed duration, then alphabetical name.
- Changed both task runners so reboot-signaling `vm-init` and `vm-update` tasks restart the VM immediately, wait for recovery, and then resume from the next task, while Windows `vm-update` still performs one additional final restart before `vm-summary`.
- Moved the old late health/reporting logic into `vm-summary`, which now starts with a read-only guest readback block before showing the normal connection details.
- Reworked `10005-copy-settings-user` into a pure portable mirror: it now mirrors portable `manager` profile and registry state into `assistant`, `C:\Users\Default`, and `HKEY_USERS\.DEFAULT`, while excluding caches, temp data, DPAPI-bound secret stores, vault/credential stores, and other non-portable artifacts.
- Removed the remaining dead curated-copy helpers from `10005-copy-settings-user`, aligned smoke coverage with the new mirror contract, and revalidated the full change non-live across the smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates.

## Release 2026.3.17.340 - 2026-03-17

### Summary
This release hardens the Windows create/update publish path before the next full retry. The workflow now preserves the real `vm-update` stage result so post-update restart requests are applied reliably, warning-only task issues stay classified as warnings instead of failed-task noise, `123-install-vlc-system` no longer trips over its `winget` verification call, and `10003-configure-ux-windows` no longer raises a false culture warning while the persisted regional state is already correct.

### Highlights
- Fixed the Step 6 wrapper contract so the conditional restart after `vm-update` can actually see the returned `RebootRequired` state and run before `vm-summary`.
- Reclassified continue-mode SSH task issues as warnings in the shared task-stage result, keeping warning-only update runs out of the failed-task bucket.
- Fixed `123-install-vlc-system` so bounded VLC verification now calls the resolved `winget.exe` path correctly instead of producing the invalid call-operator warning seen in the last full create transcript.
- Tightened `10003-configure-ux-windows` verification so it reports the current-session culture for evidence but no longer treats that transient view as a hard mismatch when the persisted Turkish regional state is already applied.
- Revalidated the repair set non-live with the full local quality gates and live in isolation on the active managed Windows VM through `123`, `10003`, and `10006`.

## Release 2026.3.17.339 - 2026-03-17

### Summary
This release hardens the new interactive `configure` editor so stale Azure-backed selections no longer kick the operator out of the session. Managed resource-group selection now stays picker-driven and filterable, missing managed-resource-group inventory now clears `SELECTED_RESOURCE_GROUP` politely instead of throwing, and final save is blocked only by unresolved create-critical values rather than by blank-permitted defaults.

### Highlights
- Replaced the old hard-stop managed resource-group validation path in `configure` with a filterable numbered picker that refuses stale current values and guides the operator toward a real managed group when one exists.
- Added the no-managed-resource-group recovery path: `SELECTED_RESOURCE_GROUP` now stays empty, the operator is told that no managed groups were found, and the editor points to `create` without terminating the session.
- Added create-critical save gating so required values such as VM OS, VM name, region, active image, active size, and VM credentials are rechecked before `.env` is written, while blank-permitted fields can be retried or cleared without blocking the rest of the editor.
- Revalidated the update non-live with the smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates.

## Release 2026.3.17.338 - 2026-03-17

### Summary
This release turns `clagnos configure` into the interactive `.env` frontend you requested. The command now walks the full supported dotenv contract in sections, uses pickers for every finite or discoverable multi-option setting, validates edits before they can be saved, and shows a next-create preview before writing `.env`. The old live-target sync behavior has been moved out of `configure` and into `show`, which can now focus one VM with `--vm-name` and print a read-only target-derived configuration section.

### Highlights
- Replaced the old Azure target-sync behavior of `configure` with an interactive-only `.env` editor that stages all edits in memory until final confirmation.
- Added picker-backed flows for VM OS, Azure subscription, region, resource group, VM size, VM image, disk SKU, security type, toggles, task directories, PYSSH path, and TCP port selection.
- Kept `configure` usable without Azure sign-in while forcing Azure-backed fields to stay read-only until `az login` makes verification available.
- Added `show --vm-name` so one managed VM can be inspected with a read-only target-derived configuration view, keeping live Azure inspection and local `.env` editing cleanly separated.
- Revalidated the full contract non-live with the smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates.

## Release 2026.3.17.337 - 2026-03-17

### Summary
This release cleans up the remaining operator-facing metadata wording that was still leaking into Windows create/update logs and hardens the PowerShell Core install task that interrupted the latest live `clagnos create` attempt. Feature validation and language readback lines now use plainer, more direct wording, while `101-install-powershell-core` now gets enough time to finish on a fresh VM and can short-circuit a healthy existing install by checking the real `pwsh.exe` path directly.

### Highlights
- Replaced the old `metadata-unavailable` language readback text in `132-configure-language-settings` and `10006-capture-snapshot-health` with clearer operator-facing wording.
- Refined nested-virtualization feature fallback messaging so create/update logs now say Azure did not report the capability clearly and that guest validation will be used, instead of using the older metadata-centric phrasing.
- Hardened `101-install-powershell-core` by raising its tracked timeout to `120` seconds, accepting reboot-style Chocolatey completion, and treating a directly discovered healthy `pwsh.exe` install as success even when `Get-Command pwsh` is not yet refreshed.
- Revalidated the cleanup non-live with the smoke, documentation-contract, code-quality, and PowerShell compatibility gates, and revalidated `101-install-powershell-core` live in isolation on the partially created Windows VM before returning the managed Azure inventory to a clean empty state.

## Release 2026.3.17.336 - 2026-03-17

### Summary
This release tightens the final Windows mixed language-and-region contract so applications now see `en-US` as the machine system locale again, while the managed VM still keeps English UI, Turkish regional formats, Turkish Q input, Istanbul time zone, and UTF-8 enabled by default. The same pass hardens the regional propagation flow so welcome-screen and new-user copy steps no longer risk drifting the intended system-locale target.

### Highlights
- Changed `10003-configure-ux-windows` so the system locale target is now `en-US` instead of `tr-TR`, matching the desired application-facing default locale for apps such as VLC and Chrome.
- Kept the rest of the mixed regional state intact: English primary language, Turkish secondary language, Turkish Q-only input, Turkish 24-hour formats, Turkey home location, Istanbul time zone, and UTF-8 ANSI/OEM code pages.
- Reasserted the `en-US` system locale after the welcome-screen and new-user propagation step so the final state remains stable even when broader international settings are copied system-wide.
- Revalidated the change non-live plus live in isolation on the active managed Windows VM through `10003`, `10006`, and direct locale/timezone/input/codepage readbacks.

## Release 2026.3.17.335 - 2026-03-17

### Summary
This release finishes the current Windows task-repair pass driven by the last two create logs. The repo now keeps the language-package work and the regional/input work in separate update tasks, carries Sysinternals plus manager autologon in the Windows update stage instead of Windows init, removes the planned restart at the start of `vm-update`, and tightens timeout plus progress behavior around the affected Windows tasks. The same pass also removes the lingering VLC and default-profile hive warning noise that was still appearing in isolated update reruns.

### Highlights
- Split Windows language configuration cleanly: `132-configure-language-settings` now owns language packages and UI language behavior, while `10003-configure-ux-windows` now owns Turkish Q input, Turkish regional formats, Istanbul time zone, UTF-8 code page intent, and welcome-screen/new-user propagation.
- Moved the tracked Windows Sysinternals and manager autologon tasks into `vm-update` as `133-install-sysinternals-suite` and `134-autologon-manager-user`, and recalibrated the current Windows init/update timeout contract from recent live create evidence.
- Removed the old planned restart at the start of `vm-update`; create and update now keep only the conditional workflow-owned restart after `vm-update` when a task explicitly requests reboot.
- Fixed `123-install-vlc-system`, `10003-configure-ux-windows`, and `10006-capture-snapshot-health` so their isolated reruns now finish cleanly without the earlier timeout, `wmic`, or registry-hive warning noise.
- Revalidated the full repair set non-live plus live in isolation on the active managed Windows VM through `132`, `10003`, `123`, `133`, `134`, and `10006`, together with direct locale/timezone/VLC/autologon readbacks.

## Release 2026.3.16.333 - 2026-03-16

### Summary
This release finishes the current operator-surface and workflow-wrap pass. `clagnos` now exposes a commandless `--version` fast path, treats the Windows `vm-update` step as a fully wrapped restart-aware stage, relays guest task output back into the local console and transcript, and presents clearer top-level step and feature-enablement messaging during create and update runs. The same release also documents the post-push GitHub Actions quality gate as part of release completion.

### Highlights
- Added `clagnos --version`, which prints exactly `clagnos version <current-release>` without the normal banner or command workflow.
- Wrapped Windows `vm-update` with one planned restart at the start of Step 6 plus one automatic restart before `vm-summary` when any update task requests reboot.
- Streamed guest task output back to the operator: `vm-update` now relays stdout/stderr live over SSH, and `vm-init` now replays the full guest transcript immediately after each task completes.
- Refined create/update and feature-enablement messaging so step start/end lines and nested-virtualization validation messages read as clear current operations instead of future-tense or ambiguous status prose.
- Revalidated the shipped behavior non-live with the smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates.

## Release 2026.3.16.332 - 2026-03-16

### Summary
This release hardens the new Windows language-settings task so reboot-pending language servicing no longer produces a false task failure. When Windows queues the requested Turkish language capabilities as `InstallPending` behind an earlier restart requirement, `132-configure-language-settings` now treats that as a valid success path, records the restart requirement explicitly, and continues with capability-aware verification instead of failing on an empty pre-reboot `Get-InstalledLanguage` result.

### Highlights
- Added capability-aware verification to `132-configure-language-settings`, covering `Language.Basic`, `Language.Handwriting`, `Language.OCR`, `Language.Speech`, and `Language.TextToSpeech` for the requested language tags.
- Accepted `InstallPending` as a valid queued completion state for the requested language surface when Windows servicing has already staged the requested capabilities behind a reboot.
- Revalidated the updated task contract non-live with the smoke, PowerShell compatibility, code-quality, documentation-contract, and release-doc gates so the repo is ready for the next live publish cycle.

## Release 2026.3.16.331 - 2026-03-16

### Summary
This release finishes the current Windows language-settings and operator-surface cleanup pass. The repo now ships a dedicated `132-configure-language-settings` update task for English UI plus Turkish locale/region/time formatting and Turkish Q keyboard policy, keeps `10005` and `10006` out of task-local app-state replay, and hardens `exec --quiet` so one-shot remote commands print only the command result without banner or `Write-Host` noise. The release was validated both non-live and live, including step-by-step readback of the language settings on the active managed Windows VM before the final isolated task reruns.

### Highlights
- Added tracked Windows `vm-update` task `132-configure-language-settings` to install `en-US` and `tr-TR`, enforce English UI with Turkish system locale, Turkish regional formats, Istanbul time zone, UTF-8 code page intent, Turkish Q keyboard, and welcome-screen/new-user propagation.
- Removed task-local app-state ownership from `10005-copy-settings-user` and `10006-capture-snapshot-health`, keeping both tasks on-the-fly and preventing any language-state replay overlap with the new `132` task.
- Added `exec --quiet` / `exec -q` so one-shot SSH commands can return only the remote result stream; the Windows wrapper now suppresses information-stream chatter and uses the task timeout budget instead of the short connect timeout.
- Revalidated the change live on the active managed Windows VM with direct `exec -q` readbacks plus isolated reruns of `132`, `10005`, and `10006`, confirming English UI, `tr-TR` locale and time formats, Turkish Q preload `0000041f`, default input `041F:0000041F`, and matching welcome-screen/new-user defaults.

## Release 2026.3.16.330 - 2026-03-16

### Summary
This release tightens the managed shortcut-launcher invocation shape for over-limit Windows Public Desktop shortcuts. Launcher-backed entries still appear only above the combined `TargetPath + Arguments` boundary, but they now invoke their generated `.cmd` launchers through the explicit `cmd.exe /c call "<launcher-path>"` form you requested.

### Highlights
- Updated the shared launcher helper so every managed launcher-backed Public Desktop shortcut now uses `cmd.exe /c call "<launcher-path>"`.
- Kept the direct path untouched for shorter entries, so direct-safe shortcuts still point straight to `chrome.exe` or `msedge.exe` without any launcher indirection.
- Revalidated the change live on the active managed Windows VM: `q2Spotify` now reads back as `cmd.exe /c call "C:\ProgramData\clagnos\shortcut-launchers\public-desktop\q2spotify.cmd"`, while `z1Google Account Setup` still reads back as a direct `chrome.exe` shortcut.

## Release 2026.3.16.329 - 2026-03-16

### Summary
This release removes task-local app-state replay from `10002-create-shortcuts-public-desktop` so the Windows Public Desktop task stays purely on-the-fly. Fresh shortcut generation now wins end to end: direct-safe browser shortcuts stay bound directly to `chrome.exe` or `msedge.exe`, while only genuinely over-limit invocations continue to use managed launcher `.cmd` files.

### Highlights
- Removed the task-local `app-state.zip` ownership from `10002-create-shortcuts-public-desktop`, so rerunning the Public Desktop task no longer restores stale shortcut or launcher artifacts after it regenerates the managed shortcut set.
- Kept the direct-vs-launcher boundary exactly at the shipped combined `TargetPath + Arguments` threshold of `259`, with direct `.lnk` targets for shorter browser entries and managed launcher `.cmd` files only for longer entries.
- Revalidated the task live in isolation on the active managed Windows VM, confirming that `z1Google Account Setup`, `i1Internet Business`, and `a11MS Edge` now resolve directly to their browser executables while `q2Spotify` still routes through a managed launcher because its effective invocation length is `265`.

## Release 2026.3.16.328 - 2026-03-16

### Summary
This release hardens the task-local app-state payload contract and clarifies the Windows Public Desktop shortcut launcher boundary. The repo now ships a dedicated normalization helper that rewrites foreign local-source user tokens in task-local `app-state.zip` payloads to the canonical managed token `manager`, merges duplicate foreign profile trees deterministically, and rewrites embedded user-profile registry paths to `manager`. The manual app-state audit now reports foreign source-profile and embedded registry-user drift directly, and the Public Desktop shortcut contract now makes the direct-vs-launcher threshold explicit: keep the direct `.lnk` invocation up to combined `TargetPath + Arguments` length `259`, and only fall back to a managed launcher above that.

### Highlights
- Added `tools/scripts/normalize-app-state-zips.ps1` so foreign local-source profile markers are normalized to `manager` across task-local payload folders, manifest source paths, and embedded registry path literals.
- Fixed the remaining shipped task-local payloads that still carried foreign user residue, including `10005-copy-settings-user`, `116-install-codex-app`, `117-install-teams-system`, `120-install-whatsapp-system`, and `125-install-be-my-eyes`, then re-audited the payload set to confirm the repo no longer reports foreign user tokens.
- Extended `tools/scripts/app-state-audit.ps1` to report foreign source users and embedded registry-user literals in addition to foreign manifest targets.
- Made the Public Desktop shortcut launcher rule explicit and testable: use the direct `.lnk` target plus arguments until the combined invocation exceeds `259`, then generate the managed launcher `.cmd` instead.

## Release 2026.3.16.327 - 2026-03-16

### Summary
This release finishes the JAWS task-state handoff by making `131-install-jaws-screen-reader` the sole builtin owner of JAWS settings replay. The task-local payload now captures the full JAWS 2025 settings tree plus the full `Freedom Scientific` HKLM/HKCU surface, local-machine saves normalize the portable payload to the canonical managed profile token `manager` instead of preserving the operator's local profile name, and the Windows health snapshot now reports JAWS settings and registry presence for both managed profiles. The release was validated non-live and again live with isolated JAWS task reruns on the active managed VM.

### Highlights
- Kept JAWS auto-start isolated in `10001-configure-apps-startup` but moved all other builtin JAWS settings replay responsibility onto `131-install-jaws-screen-reader`, which now owns the full task-local settings and registry payload.
- Normalized portable local JAWS app-state saves so the task-local zip rewrites profile payload folders, manifest source paths, and HKCU registry path markers to `manager`, eliminating source-machine user tokens from the reusable payload.
- Extended `10006-capture-snapshot-health` with JAWS settings and registry readback for `manager`, `assistant`, `HKLM\Software\Freedom Scientific`, and `HKLM\Software\WOW6432Node\Freedom Scientific`.
- Revalidated the change non-live with the smoke and PowerShell compatibility gates, regenerated the live task-local JAWS payload from the local machine, reran `task --run-vm-update 131` in isolation on the active managed VM, and confirmed the expected settings and registry surface on the target VM with isolated readback commands.

## Release 2026.3.16.326 - 2026-03-16

### Summary
This release hardens the live Windows create path around the exact `create --auto --windows --perf` publish flow. Windows task asset delivery now uses a verified SCP path instead of the slower base64 chunk transport, step review redacts password- and token-shaped values reliably, task-scoped app-state capture/replay preserves exact file destinations for overlays like JAWS `version.dll`, and several narrow task timeouts were widened so healthy installs do not degrade into warning-only runs. The release was validated by completing a full live Windows publish cycle and the normal post-create acceptance checks.

### Highlights
- Replaced the Windows task asset upload path with host-key-validated `pscp.exe` SCP plus remote size and SHA-256 verification, removing the chunk-heavy transfer mode that had been inflating live create time.
- Added generic sensitive-key redaction in the effective configuration review so passwords, secrets, and tokens render as `[redacted]` instead of appearing in plaintext during operator review output.
- Fixed app-state file capture/replay and wildcard destination expansion on both local-machine and guest paths, and trimmed the WhatsApp payload contract so large transfer/AppCenter residue no longer bloats uploads.
- Raised the timeout ceilings for Python, GitHub CLI, 7-Zip, and rclone install tasks, then verified the Python task in isolation before rerunning the exact Windows create and confirming the resulting VM with `show`, status, SSH, and RDP checks.

## Release 2026.3.16.325 - 2026-03-16

### Summary
This release removes all remaining on-disk disabled `vm-init` and `vm-update` task folders while preserving the empty `disabled/` directory contract. The stage trees now keep only placeholder `.gitkeep` files where the disabled roots must remain visible, and the stale Windows local disabled task folders no longer show up as leftover cleanup residue.

### Highlights
- Removed the remaining disabled task folders from the repository disk layout so disabled task cleanup now means an actually empty disabled tree, not a tree that still carries stale task folders.
- Standardized empty `disabled/` roots for both Linux and Windows stage trees by keeping only `.gitkeep` placeholders where the directory contract should remain explicit.
- Revalidated the result non-live with direct disabled-inventory checks plus the smoke, documentation-contract, and release-doc gates.

## Release 2026.3.16.324 - 2026-03-16

### Summary
This release hardens `task --restore-app-state` around real backup, verification, and rollback behavior. Local-machine restore now writes task-adjacent `backup-app-states/<task-name>/` snapshots plus `restore-journal.json` and `verify-report.json`, verifies the replayed files and registry before declaring success, and rolls back automatically if replay or verification fails. The Windows VM restore path now follows the same safety model on the guest side with temporary backup staging and post-restore verification.

### Highlights
- Moved local-machine restore backups from temp-only roots to task-adjacent `backup-app-states/<task-name>/` and `local/backup-app-states/<task-name>/`, keeping the restore journal and verify report beside the active snapshot.
- Added post-restore verification for local-machine replay so declared files, directories, and registry payloads are checked after restore and automatically rolled back when drift remains.
- Added Windows guest-side backup, verification, and rollback to the shared VM restore helper so direct VM app-state replay no longer assumes restore success after import/copy alone.
- Revalidated the backup/verify/rollback contract non-live with the smoke, documentation-contract, and PowerShell compatibility gates.

## Release 2026.3.16.323 - 2026-03-16

### Summary
This release adds first-class JAWS support to the tracked Windows update flow. The repo now has a builtin `131-install-jaws-screen-reader` task for JAWS 2025, task-local JAWS app-state capture for the full `Freedom Scientific` registry surface plus the JAWS 2025 settings directory, one managed `j0Jaws` Public Desktop shortcut, and a managed startup exception that writes the same machine `Run` entry shape observed on the local reference machine.

### Highlights
- Added tracked Windows update task `131-install-jaws-screen-reader` with bounded `winget` install-and-verify behavior for `FreedomScientific.JAWS.2025`.
- Added JAWS task-local app-state coverage for `AppData\Roaming\Freedom Scientific\JAWS\2025\Settings`, `HKCU\Software\Freedom Scientific`, `HKLM\Software\Freedom Scientific`, and `HKLM\Software\WOW6432Node\Freedom Scientific`, and extended the local app-state export helper with the same JAWS contract.
- Added the managed `j0Jaws` Public Desktop shortcut with `Ctrl+Shift+J`, normalized stale `JAWS` aliases during shortcut cleanup, extended the health snapshot with JAWS install/startup readback, and added one explicit managed auto-start exception so JAWS is always written as `HKLM\Software\Microsoft\Windows\CurrentVersion\Run\JAWS="C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe" /run`.
- Revalidated the shipped contract non-live through the smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates.

## Release 2026.3.16.322 - 2026-03-16

### Summary
This release completes a three-part portability and maintenance pass. Vm-init and vm-update now use portable task folders instead of flat stage-root task files and stage-root catalog JSON files, task-scoped app-state save/restore now supports both the managed VM default surface and a new Windows local-machine surface, and maintained documentation timestamps now standardize on UTC. The runtime, help, docs, and tests now describe one task-owned contract consistently: the folder names the task, `task.json` owns its runtime metadata, and `<task-folder>/app-state/app-state.zip` owns its reusable settings payload.

### Highlights
- Replaced tracked stage-root task scripts with portable task folders across Windows and Linux init/update stages, renumbered the stage inventories without band gaps, and kept missing portable task folders hot-swap-safe so absent tasks are skipped cleanly instead of breaking the workflow.
- Added `task --save-app-state --source=lm|vm` and `task --restore-app-state --target=lm|vm`, kept `vm` as the default behavior, added `.all.`, `.current.`, and comma-separated multi-user support, and hardened local restore with allow-list validation, backups, per-user journals, and rollback.
- Converted the maintained UTC policy from a forward-only rule into a current-tree standard by updating AGENTS, README, prompt-history formatting rules, and the existing `docs/prompt-history.md` headings to UTC.
- Revalidated the feature set with the non-live smoke, documentation-contract, code-quality, PowerShell compatibility, and release-doc gates only; live isolated reruns were intentionally deferred because the active managed VM had already been deleted.

## Release 2026.3.16.321 - 2026-03-16

### Summary
This release finishes the runtime cutover to the selected-only configuration contract and cleans up the Windows SSH transport path that was inflating live `create` and isolated `task` runs. The runtime now resolves and logs one effective configuration snapshot with explicit value sources, Windows asset delivery now uses one direct base64 chunk transport instead of falling through layered fallback paths, and Windows app-state replay now stages unique zip paths, waits for the zip to become readable, and exposes replay phases and remote errors clearly. The same pass trims the managed browser app-state contract down to lightweight settings payloads and raises the Sysinternals init timeout so isolated reruns behave deterministically.

### Highlights
- Removed the old `.env` compatibility surface from the live runtime so only current `SELECTED_*` names, current naming placeholders, and `AZURE_COMMAND_TIMEOUT_SECONDS` remain in the active configuration contract.
- Replaced repeated config review dumps with one canonical `KEY=value (source)` snapshot so operators see every effective setting once without losing visibility into where the value came from.
- Reworked Windows SSH execution and asset staging so the repo now uses a single bounded base64 upload path with grouped progress logs, direct stdout and stderr capture, remote hash reuse, and no per-chunk pyssh noise.
- Tightened Windows app-state replay by using unique remote zip names, zip-readiness waits, clearer replay-phase logging, and lighter Chrome and Edge settings payloads, then verified the new path live with isolated `vm-init` and `vm-update` task reruns on the active managed Windows VM.

## Release 2026.3.16.320 - 2026-03-16

### Summary
This release is a documentation-and-tests alignment pass for the current selected-only configuration surface. The maintained docs and contract checks now describe the public runtime with `SELECTED_*` config names, `{SELECTED_VM_NAME}` managed-resource templates, `__SELECTED_*__` task placeholders, `AZURE_COMMAND_TIMEOUT_SECONDS`, the `180` second Sysinternals init timeout, and the current Windows public-desktop shortcut validation wording.

### Highlights
- Updated `README.md` to describe the current template and task-placeholder contract, including `{SELECTED_VM_NAME}` and `__SELECTED_*__`.
- Updated the smoke suite so create override assertions, `.env.example` template checks, task token replacement checks, and the Sysinternals init timeout all match the selected-only contract.
- Updated the documentation-contract gate to keep the README wording aligned with the current Windows shortcut validation messages and selected-name placeholder model.

## Release 2026.3.15.319 - 2026-03-15

### Summary
This release hardens the Windows SSH task transport for environments where the OpenSSH command channel is healthy but the SFTP subsystem refuses negotiation. Windows SSH asset uploads now retry SFTP briefly and then fall back to a chunked PowerShell `exec` transfer that can stage helper modules and larger task scripts without tripping the remote Windows command-line limit, keeping `vm-update` moving instead of aborting at the first `pyssh copy asset` failure.

### Highlights
- Added a Windows-specific no-SFTP asset-transfer fallback in the shared SSH asset helper so `vm-update` can keep using one-shot SSH execution even when Paramiko cannot open an SFTP channel.
- Reduced the inline chunk size used by the fallback transport so larger staged task scripts and helper modules avoid the remote `The command line is too long.` failure while still reconstructing the remote file deterministically.
- Revalidated the behavior live by rebuilding the managed Windows target, then confirming the resulting VM is in `Provisioning succeeded` / `VM running` state and that both `connect --ssh --test` and `connect --rdp --test` pass against the new managed VM.

## Release 2026.3.15.318 - 2026-03-15

### Summary
This release unifies task-scoped app-state restore behavior across vm-init, vm-update, and the direct `task --restore-app-state` surface. Vm-init now runs one task at a time over Azure Run Command so it can invoke the same shared post-task app-state restore helper after each init task when a matching plugin zip exists, while direct vm-init restore uses that same shared helper through a run-command transport instead of depending on SSH readiness. The same pass also adds a small unconditional banner to the CLI entrypoint so every `clagnos` invocation starts with version and feature context before command parsing begins.

### Highlights
- Reworked the vm-init runner from one combined Run Command batch into one-task-at-a-time execution so init-stage post-task app-state replay can use the same shared helper contract as vm-update.
- Expanded the shared app-state restore helper with a run-command transport and routed `task --restore-app-state --vm-init-task ...` through it, giving init restore and init post-task replay the same plugin resolver and replay core that update restore already uses over SSH.
- Added an unconditional `CLAGNOS CLI V<version>` welcome banner with a two-line feature summary that prints before valid, invalid, parameterized, and parameterless invocations alike.

## Release 2026.3.15.317 - 2026-03-15

### Summary
This release adds one more explicit lifecycle repair path to `clagnos do`: `--vm-action=redeploy`. Operators can now request a direct Azure host redeploy from the same lifecycle command that already handles status, power-state changes, reapply, and hibernation flows, while the runtime waits for provisioning recovery and then restores the original started/stopped lifecycle state when Azure reports it deterministically.

### Highlights
- Added `do --vm-action=redeploy` to the public lifecycle contract, help surface, README command matrix, and smoke validation.
- Reused the same tracked Azure-action wrapper as the rest of the `do` command so manual redeploy stays visible, audited, and consistent with the existing lifecycle UX.
- Added isolated smoke coverage that verifies the redeploy action calls `az vm redeploy`, waits for provisioning recovery, restores the original lifecycle state, and prints the refreshed VM status.

## Release 2026.3.15.316 - 2026-03-15

### Summary
This release cuts the persisted configuration contract over to a selected-only model. `.env` now stores active targeting, operator identity, company metadata, subscription choice, and region choice exclusively through `SELECTED_*` keys, while the shared runtime still materializes the same internal canonical fields for orchestration. The same pass makes unattended `clagnos create --auto` runnable from `.env` alone when the selected values and platform defaults are complete, and it removes the older persisted output-key contract from configure/create/update/move/set writeback.

### Highlights
- Added `SELECTED_RESOURCE_GROUP` as the persisted existing-target selector so unattended update, configure, delete, set, move, task, exec, and connection flows can resolve the active managed VM target from `.env` without reviving the old output-key contract.
- Reworked `.env.example`, README, AGENTS, help output, smoke coverage, and documentation contracts so the committed configuration model is now `SELECTED_*` plus the shared and platform-specific VM defaults.
- Updated the create runtime so `clagnos create --auto` can resolve platform, VM name, Azure region, and VM size from `.env` `SELECTED_VM_OS`, `SELECTED_VM_NAME`, `SELECTED_AZURE_REGION`, and the matching `WIN_*` or `LIN_*` defaults without requiring explicit CLI `--vm-name`, `--vm-region`, `--vm-size`, or platform flags.
- Updated the runtime persistence path so configure/create/update/move/set flows now remove the retired persisted keys after writing the selected contract, keeping `.env` aligned with the current committed model instead of accumulating both generations side by side.

## Release 2026.3.15.315 - 2026-03-15

### Summary
This release narrows the managed app-state system from a broad machine snapshot into a stricter settings-first contract. Managed save and restore now target only the `manager` and `assistant` OS profiles, the shared capture/replay runtime no longer enumerates `default` or arbitrary local users, and the tracked Windows capture specs now prune generated browser caches, installer/update payloads, telemetry trees, embedded WebView runtime content, and other low-value artifacts before they can bloat new payloads. The same pass also sanitizes the current ignored `windows/update/app-states/*/app-state.zip` payload set so the existing operator-owned zips match the new contract instead of carrying older foreign-profile drift forward.

### Highlights
- Added `tools\\scripts\\app-state-audit.ps1` as a manual payload-inspection helper that reports zip sizes, foreign profile targets, and the heaviest entries inside each stage-local app-state payload.
- Locked the shared app-state runtime to the managed `manager` and `assistant` OS-user targets across Windows and Linux, removing the old `default` and arbitrary-local-profile replay/capture behavior.
- Tightened the tracked Windows app-state capture specs so Chrome, Edge, Azure CLI, azd, Docker Desktop, GitHub CLI, Ollama, Office settings, npm-managed CLI state, and Visual Studio now exclude the biggest generated caches, model stores, telemetry folders, installer binaries, and other low-value artifacts.
- Rewrote the current ignored app-state payloads in place so the managed zip set no longer carries foreign profile targets and so the heaviest payloads are cut down to a reusable settings baseline.

## Release 2026.3.15.314 - 2026-03-15

### Summary
This release completes the CLI surface cutover that separates task execution, direct shell execution, and user-facing connection flows cleanly. `clagnos task` now owns isolated `vm-init` and `vm-update` task runs, `clagnos exec` is now only the SSH shell/remote-command surface, and the old standalone `ssh` and `rdp` commands are replaced by one explicit `clagnos connect --ssh|--rdp` contract. The same pass also standardizes target selectors on `--group` / `-g`, `--vm-name` / `-v`, and `--subscription-id` / `-s`, and tightens parser/help/docs alignment so value-taking options consistently accept both `--option=value` and `--option value`.

### Highlights
- Added `task --run-vm-init` and `task --run-vm-update`, moving isolated task execution out of `exec` and into the command that already owns task inventory and task app-state maintenance.
- Added the new `connect` command so SSH and RDP launch/test behavior now lives under one explicit transport-selected surface: `connect --ssh` or `connect --rdp`.
- Reduced `exec` to two deliberate modes only: bare `exec` for the interactive SSH shell and `exec --command` / `-c` for one-shot remote commands.
- Standardized the canonical selector names and option-shape handling across the app, then updated help, README, AGENTS, and smoke/docs contract coverage to remove the retired public forms in the same cutover.
- Kept the full reachable-history sensitive-content audit available through `tests\sensitive-content-check.ps1`, while focusing automated local gate and commit-message checks on the current tree and the current commit message.

## Release 2026.3.15.313 - 2026-03-15

### Summary
This release opens a new live-maintenance surface for task-owned app-state payloads and aligns the surrounding Windows operator contract with it. `clagnos task` can now save and restore per-task app-state zips over SSH, task `115-install-npm-packages-global` now captures richer per-user CLI state including full `.codex` trees, the default VM name can now derive from the local-part of `employee_email_address`, and the Windows public desktop surface now takes its business web root from `company_web_address` while using refreshed iCloud and Codex CLI shortcut contracts. The same pass also hardens Windows app-state capture internals and adds a Chrome-specific pre-restore close hook so app-state replay can reduce file-in-use conflicts instead of trying to restore over running Chrome windows.

### Highlights
- Added live `task --save-app-state` and `task --restore-app-state` flows that target one init or update task at a time and read or write the existing per-task `app-state.zip` payload under the stage-local `app-states/` tree.
- Added one shared capture-spec registry plus one shared capture engine, backed by new `fetch` support in the repo-owned pyssh client, so app-state payloads can now be refreshed directly from the live VM instead of being authored only by hand.
- Updated the Windows shortcut surface so `i1Internet Business` comes from `company_web_address`, `k1Codex CLI` uses the richer Codex CLI invocation, and `d4ICloud` resolves through the real iCloud launch contract instead of the File Picker fallback.
- Hardened task app-state capture and restore with fixed plan merging, shorter Windows scratch paths for deep `.codex` trees, safer legacy-registry deduplication, and a Chrome pre-restore process-close step that runs before task `02-check-install-chrome` replay.

## Release 2026.3.14.312 - 2026-03-14

### Summary
This release tightens the Windows desktop-finish path around three operational edges: overlong Public Desktop shortcut invocations, fragmented local screen-reader execution, and transcript housekeeping. Overlong Chrome and Edge shortcut commands now collapse into managed short launchers without changing the effective browser/profile/URL behavior, the local screen-reader workflow now runs as one self-contained local vm-update task instead of several loosely chained tasks, and the retro log audit helper moves into `tools/scripts/` as a manual maintenance tool while the current local transcript files are cleaned from the repo working tree.

### Highlights
- Added a shared managed shortcut launcher helper so Public Desktop shortcut creation and late health validation now use the same short-launcher contract.
- Merged the local screen-reader install, settings, shortcut, autostart, and verify-repair flow into one local task, with one matching app-state plugin name.
- Moved `retro-log-audit.ps1` to `tools/scripts/` and removed it from the default non-live gate so it stays available for targeted maintenance runs without being auto-triggered.
- Cleaned the current untracked `clagnos-log-*.txt` files from the repo root while keeping `.gitignore` coverage in place.

## Release 2026.3.14.311 - 2026-03-14

### Summary
This release closes the retro-log hardening pass without reintroducing any next-boot follow-up behavior. The affected Windows vm-update tasks now stay strictly one-shot, Store-backed installs write an explicit launch-ready or degraded state instead of leaving RunOnce-style continuation work behind, the SSH stage summary reports warning signals more honestly, Linux app-state replay now covers the supported file-copy contract, and the late Windows health snapshot reads back the same Store-install state ledger that the install and shortcut tasks now use.

### Highlights
- Added a shared Store install-state helper module so the touched Windows Store-backed tasks now share one centralized contract for PATH refresh, `winget` discovery, stale RunOnce cleanup, and launch-ready state persistence.
- Added a deterministic retro-log audit helper so the historical `clagnos-log-*.txt` corpus can be rescanned for the noisy or degraded patterns that drove this hardening pass.
- Updated the touched Store-backed install tasks so they now fail or degrade explicitly when an interactive Store-capable session is missing, instead of scheduling any next-boot or next-sign-in continuation work.
- Updated Teams startup so the managed startup surface now prefers the packaged `AppsFolder` launch contract, matching the healthy Store shortcut model.
- Fixed Python verification, copy-settings skip accounting, local screen-reader autostart self-heal, and benign transcript noise filtering in the SSH task pipeline.
- Revalidated the changes with isolated live task runs on the active managed Windows VM, including the touched builtin tasks plus the local-only screen-reader autostart tasks, ending with healthy Docker, Ollama, Teams startup, refreshed public shortcuts, and zero managed shortcut or stage-summary failures.

## Release 2026.3.14.310 - 2026-03-14

### Summary
This release replaces the old Windows app-state replay surface with a more extensible plugin model. Vm-update tasks now look only for `.../update/app-states/<task-name>/app-state.zip`, replay that payload when it exists, and continue cleanly when it does not. The shared post-process now serves builtin and local-only tasks alike, connection and direct-task flows can repair a VM that remains stuck in provisioning state `Updating` through one bounded `az vm redeploy`, Store-backed public desktop shortcuts still normalize through `AppsFolder` launches, and the local WSL payload still keeps only the `docker-desktop` distro state.

### Highlights
- Added a shared vm-update app-state plugin manager and guest replay helper so builtin and local-only update tasks can both consume one exact per-task app-state zip contract without a dedicated restore task.
- Standardized the only valid app-state source path to `.../update/app-states/<task-name>/app-state.zip` and removed the old tracked restore task plus the old local overlay replay path.
- Moved the local app-state export helper into `modules/core/tasks/` so builtin and local-only update tasks now share one orchestration layer for save/restore helpers and post-task replay.
- Added `docs/windows-store-migration-audit.md` so the repo now documents which Windows apps are already Store-backed, which Store migrations are credible but still approval-gated, and which installers should stay on their current source.
- Updated the Windows public desktop shortcut contract so Store-backed apps such as Codex, Teams, WhatsApp, and Be My Eyes prefer `explorer.exe` with `shell:AppsFolder\<AUMID>`, while `a11MS Edge` stays on the requested direct `msedge.exe` launch contract and Google Drive now refreshes to the newest versioned executable path.
- Hardened the WSL/Docker path with explicit feature-state health evidence and narrowed the local-only WSL overlay replay so only `docker-desktop` remains in the exported and replayed distro state.
- Added one bounded redeploy repair path when Azure leaves the VM stuck in provisioning state `Updating`, and hardened task execution so persistent SSH session drops can fall back to one-shot execution without skipping per-task app-state replay.
- Revalidated the change set with isolated live task runs on the active Windows VM across the full builtin and local-only vm-update task set, including the refreshed shortcut normalization, the per-task app-state post-process hook, the SSH transport fallback path, and the filtered WSL payload behavior.

## Release 2026.3.13.308 - 2026-03-13

### Summary
This release turns the top of the README into a much stronger public value story. The repo now presents `clagnos` more clearly as a Windows-first, near-zero-touch remote workstation delivery path while still describing Linux accurately as a lighter but fully extensible platform under the same operator model.

### Highlights
- Rewrote the opening README funnel so the first sections emphasize the prepared remote-computer outcome: installed applications, curated startup behavior, desktop shortcuts, UX tuning, advanced settings, and task-driven customization.
- Added concrete PoC / PoE-style stories for customer demos, employee workstations, developer workstations, and support-oriented machines.
- Expanded the audience framing so customers, executives, employees, administrative teams, workers, developers, operators, visitors, and sponsors can all see a credible value proposition quickly.

## Release 2026.3.13.307 - 2026-03-13

### Summary
This release narrows prompt-history auto-recording to the turns that matter most. Very short approval/follow-up nudges and non-mutating question or analysis turns are now excluded from automatic ledger recording, while substantive prompts still remain mandatory English-normalized history entries.

### Highlights
- Updated `AGENTS.md` so excluded prompt types are explicit and the assistant must end those turns with a short opt-in recording hint.
- Updated `README.md` and the documentation contract so the refined prompt-history policy stays visible and test-enforced.
- Kept the standing sensitive-content guardrail in place while making prompt-history output more signal-dense and easier to maintain.

## Release 2026.3.13.306 - 2026-03-13

### Summary
This release turns the recent cleanup discipline into a standing engineering control. The repo now has an always-on sensitive-content audit in local hooks and in the non-live quality gate, so obvious contact-style values, concrete identity leaks, and non-placeholder sensitive config drift are blocked before they become shared history.

### Highlights
- Added `tests\sensitive-content-check.ps1` as a dedicated repo-authored hygiene audit for tracked files, committed configuration placeholders, and reachable commit messages.
- Added a native `commit-msg` hook so commit messages are checked before the commit is accepted, not only after the content reaches CI.
- Updated `AGENTS.md`, `README.md`, and the documentation contract so contributors see the rule clearly and the repo keeps enforcing it automatically.

## Release 2026.3.13.305 - 2026-03-13

### Summary
This release is a final documentation polish pass on top of the repository-wide cleanup work. The maintained repo surface now avoids restating retired tokens, removed sample values, and replacement metadata explicitly in the release-facing docs, so the current public tree stays aligned with the sanitized content policy end to end.

### Highlights
- Reworded the maintained release documents so they describe the cleanup outcome without reintroducing any retired surface tokens or removed sample terms in current tracked text.
- Rewrote the matching prompt-history entry in neutral language so the human-readable ledger stays consistent with the cleaned repository surface.
- Revalidated the maintained tip with the full non-live gate: smoke, documentation contract, PowerShell compatibility, code quality, and bash syntax.

## Release 2026.3.13.304 - 2026-03-13

### Summary
This release finalizes the repository cleanup pass for public history and current content. The obsolete destructive-rebuild shortcut is gone, rebuild guidance now uses explicit `delete` plus `create`, and the tracked repo plus reachable git history were redacted so concrete contact-style values, secret samples, organization-style example names, and real live-target identifiers no longer remain in the public history that the repo exposes.

### Highlights
- Removed the retired destructive-rebuild shortcut from runtime code, help, README, smoke coverage, and release docs, and aligned the operator contract around an explicit `delete` then `create` rebuild flow.
- Replaced concrete-looking contact values, secret samples, live target names, and subscription identifiers in the current tracked repo with generic placeholders or neutral examples so the maintained surface is safer to publish and easier to reuse.
- Rewrote reachable history in a controlled offline clone with the same replacement map applied to blobs and commit messages, then standardized rewritten author and committer metadata to the configured maintainer identity while preserving timestamps.
- Revalidated the rewritten current tip with the full local non-live gate: smoke, documentation contract, PowerShell compatibility, code quality, and bash syntax.

## Release 2026.3.13.302 - 2026-03-13

### Summary
This release is a documentation presentation refresh focused on readability, audience fit, and public-facing clarity. `README.md` now opens with a faster value story for customers and executives, keeps the technical depth for operators and maintainers, and adds a table-driven operational command reference so the full command surface is easier to scan and adopt.

### Highlights
- Merged the old quick-start and quick-accelerator material into one stronger `Quick Start Guide` and moved business impact to the top of the document through `Customer Business Value`, a standalone `Executive Summary`, and the new `Value By Audience` section.
- Added the new `Operational Command Matrix` so every public command, important parameter group, and practical usage variation is visible in one pragmatic table-driven section before the deeper narrative command guide.
- Updated the README information architecture to work better for customers, executives, developers, operators, visitors, and potential sponsors while preserving the repo's exact contract-heavy command and workflow wording.
- Extended the documentation contract checks so the new heading order, the merged quick-start structure, and the new command-matrix sections remain enforced.

## Release 2026.3.13.301 - 2026-03-13

### Summary
This release closes the fresh Windows release-bar loop on the current Azure subscription and stabilizes the remaining first-run guest tasks that blocked a clean `create -> update` cycle. The Windows user-settings copy task now mirrors only the known user folders and explicit app settings that matter, the long-running Ollama and VLC installers now follow bounded verification paths that survive clean-build cold starts, and the live create/update path now recovers more cleanly from OpenSSH bootstrap and transient SSH-session loss on a brand-new VM.

### Highlights
- `10005-copy-settings-user.ps1` now copies only explicit profile roots plus selected Task Manager, VS Code, Chrome, and repo-managed CLI-wrapper state, removing the old shallow broad-AppData mirroring that was slow, fragile, and noisy around ACLs, locked files, and reparse points.
- Fresh Windows `create` now survives the previously observed first-run failures because `03-install-openssh-service.ps1`, `04-configure-sshd-port.ps1`, and the shared persistent SSH task runner now recover missing `sshd` service registration and restore the transport session after transient installer drops.
- `116-install-ollama-system.ps1` now uses a stronger bounded cold-start API readiness contract for `/api/version`, including both `127.0.0.1` and `localhost` probes plus longer bounded grace windows, and `124-install-vlc-system.ps1` now uses a bounded winget-install plus executable verification model instead of failing on a short runner timeout.
- `10099-capture-snapshot-health.ps1` now refreshes PATH and resolves `az`, `docker`, and `ollama` through explicit fallback paths, which removes the earlier false `not-found` signals from late-stage health capture on fresh VMs.
- Live acceptance completed successfully against subscription `<subscription-guid>`: a fresh `create --auto --windows --vm-name=examplevm --vm-region=austriaeast --vm-size=Standard_D4as_v5` rebuilt `rg-examplevm-ate1-g2`, a controlled reboot satisfied the post-create WSL restart requirement, and the follow-up `update --auto --windows --group=rg-examplevm-ate1-g2 --vm-name=examplevm` finished with `failed=0` and `warning=0`.

## Release 2026.3.13.300 - 2026-03-13

### Summary
This release closes the Azure subscription-selection gap across the command surface. Every Azure-touching command now accepts `--subscription-id` / `-s`, the runtime resolves subscriptions with the committed `CLI -> .env -> active Azure CLI` precedence, interactive `create` and `update` now ask for the subscription before Azure-backed discovery when no CLI override is present, and the docs/help/tests now treat `az login` as a strict prerequisite for Azure operations.

### Highlights
- Added shared subscription targeting for `create`, `update`, `configure`, `list`, `show`, `do`, `move`, `resize`, `set`, `exec`, `ssh`, `rdp`, and `delete`, while keeping `task` and `help` local-only and intentionally outside the subscription-aware contract.
- Added the repo-local `azure_subscription_id` configuration key to `.env.example` and documented the exact precedence rule everywhere the operator contract lives: CLI `--subscription-id` / `-s` wins first, `.env azure_subscription_id` wins next, and the active Azure CLI subscription is the final fallback.
- Updated the shared Azure CLI wrapper so normal `az` calls inherit the resolved subscription automatically through Azure CLI's global `--subscription` argument, while account-discovery helpers can still bypass forced subscription injection when they need to inspect the full accessible subscription set.
- Interactive `create` and `update` now show a numbered Azure subscription picker before region, SKU, managed resource-group, or VM discovery when `--subscription-id` is omitted, and successful CLI `-s` usage persists `azure_subscription_id` back into `.env`.
- Revalidated the entire non-live gate after the contract landed: smoke, documentation contract, PowerShell compatibility, code quality, and bash syntax all pass against the subscription-aware surface.

## Release 2026.3.13.299 - 2026-03-13

### Summary
This release finishes the `configure` and public inventory command-surface refresh. `configure` now acts as the managed target selector and `.env` synchronization command for existing clagnos-managed VMs, interactive `create` now asks for the VM OS first when no platform flag is supplied, and the old `group` command has been replaced by the new read-only `list` command.

### Highlights
- `clagnos configure` now accepts `--group` and `--vm-name`, selects only clagnos-managed targets, reads actual Azure VM, disk, and network state, validates optional platform flags against the real VM OS type, and writes only target-derived `.env` values.
- `clagnos list` now exposes managed inventory sections through `--type=group,vm,disk,vnet,subnet,nic,ip,nsg,nsg-rule` with optional exact `--group` filtering, replacing the removed public `group` command.
- Interactive `create` no longer silently inherits `.env VM_OS_TYPE` when platform flags are missing; it now prompts for the VM OS first and scopes image, size, and disk defaults from that explicit choice.
- Help, README, AGENTS, and smoke/documentation/code-quality checks were all updated together so the repo no longer documents or tests the removed `group` command surface.

## Release 2026.3.13.298 - 2026-03-13

### Summary
This release finishes the runtime side of the fresh-create, existing-update, and live-grounded Windows hardening work. The create/update workflow now stays aligned with the review-first UX contract, managed naming keeps globally unique `gX` and `nX` ids, and the Windows init/update tasks were tightened using read-only findings from the current live VM so new VMs come up with fewer shortcut, startup, autologon, Docker, Ollama, and profile-copy regressions.

### Highlights
- Fresh `create` planning now always proposes a new managed resource group with the next global `gX` suffix, and every generated managed resource now consumes a globally unique `nX` suffix across all managed resource types instead of reusing per-type counters.
- `create` no longer reuses persisted managed resource names from `.env` during fresh planning unless the current invocation explicitly overrides them, while `update` continues to target the existing managed RG and VM path.
- Windows tracked task catalogs now place `108-install-sysinternals-suite` and `130-autologon-manager-user` in `vm-init`, with the Windows workflow keeping a restart barrier before `vm-update` when init ran.
- `10001-configure-apps-startup.ps1`, `10002-create-shortcuts-public-desktop.ps1`, `114-install-docker-desktop.ps1`, `116-install-ollama-system.ps1`, `10005-copy-settings-user.ps1`, and `10099-capture-snapshot-health.ps1` now follow the live VM findings more closely: startup artifacts are written-and-verified, orphan managed shortcuts are skipped, packaged apps resolve through real executables or `shell:AppsFolder`, excluded profile-cache targets are pruned on reruns, and the health snapshot reports richer Docker/Ollama/WSL/autologon state.
- The isolated live validation set completed successfully on `rg-examplevm-sec1-g1/examplevm`, including targeted init/update task reruns plus non-mutating `create --step=configure` and `update --step=configure` probes that confirmed the fresh naming and existing-target contracts.

## Release 2026.3.13.297 - 2026-03-13

### Summary
This release finishes the help/docs/tests side of the in-progress command-surface refresh. The maintained documentation now describes `create` as a fresh-only flow, `update` as an existing-managed-target flow, the review-first interactive UX, globally unique managed `gX`/`nX` naming, and the strict auto-mode requirements without carrying the earlier reuse-oriented wording.

### Highlights
- Updated `modules/core/cli/clagnos-help.ps1` and `README.md` so `create --auto` now documents the required explicit platform plus `--vm-name`, `--vm-region`, and `--vm-size`, while `update --auto` documents the required explicit platform plus `--group` and `--vm-name`.
- Documented the review-first UX more precisely: only `group`, `vm-deploy`, `vm-init`, and `vm-update` use `yes/no/cancel`, while `configure` and `vm-summary` always render even when a partial step window skips interior stages.
- Updated the naming guidance so managed resource groups use globally increasing `gX` ids and managed resources use globally increasing `nX` ids that are never reused across resource types.
- Refreshed the smoke/documentation contracts to match the current in-progress implementation, including the current autologon health snapshot output rather than a future `DefaultPasswordPresent` health-field expectation.

## Release 2026.3.12.296 - 2026-03-12

### Summary
This release fixes the remaining GitHub Actions quality-gate blocker after publication by making the smoke suite fully non-live again. The slow `smoke-contracts` job was not a runner deadlock; it was accidentally executing real Azure-dependent code paths because several test doubles were declared in the wrong scope.

### Highlights
- Updated `tests/clagnos-smoke-tests.ps1` so the create, update, resize, reapply, and hibernate-stop smoke doubles now override the runtime functions in the active test scope instead of falling through to `.env` and Azure CLI backed implementations on GitHub-hosted runners.
- Restored the smoke suite to the expected short non-live execution profile, eliminating CI waits caused by unintended `az login` prompts and unexpected Azure calls inside the smoke contract job.
- Revalidated the full local non-live gate before the follow-up push: smoke, documentation contract, PowerShell compatibility, code quality, bash syntax, and pre-commit release-doc checks all pass.

## Release 2026.3.12.295 - 2026-03-12

### Summary
This release fixes the GitHub Actions publish gate for the new public repository by switching every workflow checkout to full-history mode, which restores the commit-count-based release-document validation on CI after the initial public push.

### Highlights
- Updated `.github/workflows/quality-gate.yml` so every `actions/checkout@v6` step uses `fetch-depth: 0`, preventing the release-document checks from seeing a shallow clone count of `1` on GitHub-hosted runners.
- Published the repo to the public GitHub remote, pushed aligned `main` and `dev`, and removed all remaining non-canonical local branches so the repo now keeps only the two intended long-lived branches.
- The previous failing `main` workflow run was traced to shallow checkout depth rather than the actual code or docs contract; the follow-up push from this release is intended to produce the clean authoritative `main` Actions result.

## Release 2026.3.12.294 - 2026-03-12

### Summary
This release closes the last live Windows publish blockers from the recreate-and-update acceptance cycle by fixing the remaining Node, Edge, and profile-copy task failures, then rerunning the full live update validation to a clean finish.

### Highlights
- Raised the tracked timeout budgets for `104-install-node-system` and `111-install-edge-browser`, and added short bounded post-install verification so the tasks still require a real healthy install but no longer time out during first-run package setup.
- Hardened `10005-copy-settings-user.ps1` so `AppData\Local\Microsoft\Windows\WebCacheLock.dat` is excluded from the local profile copy path and the robocopy fallback now tolerates the same live lock signature across the observed return codes.
- Revalidated the live Windows path on `rg-examplevm-sec1-g1/examplevm` with isolated reruns of tasks `104`, `111`, and `10005`, then a full `clagnos update --auto --windows --perf` pass that finished `success=45, failed=0, warning=0, error=0, reboot=0`.
- Completed the release-closeout checks with `clagnos show --group=rg-examplevm-sec1-g1`, `clagnos do --vm-action=status`, `clagnos ssh --test`, and `clagnos rdp --test`, all passing against the live VM after the clean full update.

## Release 2026.3.12.293 - 2026-03-12

### Summary
This release finishes the command-surface refresh for publish-readiness: step selectors are renamed to the new `--step` family, destructive rebuild guidance is made explicit through a `delete` then `create` flow while the broader create/update contract continues toward the current fresh-only create model, `update` now requires an existing managed VM and redeploys it during the VM deploy stage, and `resize` gains a safe managed OS disk expand path plus an explicit non-mutating shrink guidance path.

### Highlights
- Renamed the create/update step selectors from `--single-step`, `--from-step`, and `--to-step` to `--step`, `--step-from`, and `--step-to`, then removed the retired option forms throughout the parser, manifest, parameter modules, help output, README, and smoke contract.
- Standardized destructive rebuild guidance around an explicit `delete` followed by `create`, keeping destructive rebuild intent separate from the evolving default create/update contract.
- Changed `update` so it fails early when the managed resource group or VM is missing, then uses Azure create-or-update plus `az vm redeploy` once an existing VM is confirmed.
- Added `resize --disk-size=<number>gb|mb --expand` for the supported managed OS disk growth path, and `resize --disk-size=<number>gb|mb --shrink` as a fail-fast guidance path that explains Azure's OS disk shrink limit and lists supported rebuild alternatives.
- Refreshed README and AGENTS with a stronger quick-start, business-value, developer-benefit, and practical-usage narrative while keeping the documentation contract aligned with the runtime surface.

## Release 2026.3.12.291 - 2026-03-12

### Summary
This release synchronizes the publish-facing repository contract with the current live-acceptance workflow and hardens Windows VM creation against transient Azure CLI create failures that can still result in a successfully deployed VM.

### Highlights
- Updated the GitHub issue templates, pull-request template, README, contributing guide, and support guide so live Azure acceptance and release-readiness claims now follow the same documented reporting contract everywhere.
- Added an explicit `documentation-contract` job to `.github/workflows/quality-gate.yml`, bringing the existing documentation contract check into the GitHub Actions gate alongside the rest of the non-live validation suite.
- Hardened `Invoke-ClagnosVmCreateStep` so transient non-zero `az vm create` results now trigger a short bounded VM-presence probe instead of immediately failing when Azure may still complete the deployment moments later.
- Revalidated the non-live publish gate with code-quality, documentation-contract, PowerShell compatibility, smoke, and bash-syntax checks before recording this release point.

## Release 2026.3.12.290 - 2026-03-12

### Summary
This release completes a second Windows `vm-update` performance-tuning pass against live perf logs by removing the remaining retry-heavy noninteractive waits, shortening bounded settle windows, and making repeated deferred Store installs short-circuit instead of trying the same failing path again.

### Highlights
- Reworked `114-install-docker-desktop.ps1` so the task no longer waits on repeated Docker daemon probes in SSH sessions; it now verifies the Docker client, starts Docker Desktop once, and immediately registers an interactive `RunOnce` start for the next sign-in.
- Reworked `121-install-whatsapp-system.ps1` so it prefers fast local registration checks over `winget list`, and skips the whole install attempt when a deferred `RunOnce` Store install is already registered.
- Shortened registry-hive unload waits in `10001-configure-apps-startup.ps1` and `10099-capture-snapshot-health.ps1`, and reduced Task Manager / Explorer settle waits in `10003-configure-ux-windows.ps1`.
- Updated smoke coverage so the Docker Desktop task is enforced against the new bounded deferred-start model rather than the old daemon-probe loop.
- Revalidated the live Windows path on `rg-examplevm-sec1-g1/examplevm`: `114-install-docker-desktop` fell from about `16.2s` to about `3.2s`, `121-install-whatsapp-system` now short-circuits deferred reruns at about `3.5s`, `10099-capture-snapshot-health` fell to about `6.1s`, and the full `vm-update` step fell from about `234.7s` to about `198.0s`.

## Release 2026.3.12.288 - 2026-03-12

### Summary
This release splits the old `do --vm-action=hibernate` contract into two explicit operator choices: `hibernate-stop` for guest-triggered SSH hibernation without Azure deallocation, and `hibernate-deallocate` for Azure's existing deallocation-based hibernation path.

### Highlights
- Added `do --vm-action=hibernate-stop`, which connects through the repo-managed pyssh path, runs `shutdown /h /f` inside the running guest, and waits until the VM is no longer accepting SSH without treating Azure deallocation as success.
- Renamed the Azure-backed hibernation action from `hibernate` to `hibernate-deallocate`, making the deallocation behavior explicit instead of hiding it behind the old shorter action name.
- Updated the `do` action parser, interactive picker, help output, README examples, and smoke suite so the retired `hibernate` action now fails with a precise migration hint to `hibernate-stop` or `hibernate-deallocate`.

## Release 2026.3.12.287 - 2026-03-12

### Summary
This release fine-tunes the slowest Windows `vm-update` paths by making Docker Desktop readiness checks non-blocking in SSH sessions, shortening user-settings copy waits, removing retry-heavy shortcut normalization behavior, and enforcing a repo-wide no-`--force` install contract for tracked Windows update tasks.

### Highlights
- Reworked `114-install-docker-desktop.ps1` so it uses only two short `docker version` probes, skips the old blocking `docker info` gate, and registers a deferred interactive `RunOnce` start instead of waiting for the daemon indefinitely inside a noninteractive guest session.
- Reworked `10005-copy-settings-user.ps1` so assistant logoff/process cleanup settles through a short bounded session/process watcher rather than a fixed five-second sleep, and registry-hive unload retries now use fewer attempts with much shorter waits.
- Fixed and accelerated `10002-create-shortcuts-public-desktop.ps1` by adding an already-normalized fast path, removing the accidental early-return behavior during Public Desktop inspection, and broadening duplicate cleanup coverage to installer-created `AnyDesk`, `Windscribe`, `VLC media player`, `iTunes`, `IObit Unlocker`, and `NVDA` shortcuts.
- Removed every tracked Windows `vm-update` `--force` flag and aligned the install tasks with an install-if-missing, skip-if-healthy model; the winget bootstrap task now avoids forceful source resets and uses only one bounded `source update` recovery attempt.
- Completed a live Windows validation cycle on `rg-examplevm-sec1-g1/examplevm`, including isolated reruns of the tuned tasks plus a full `update --step=vm-update --auto --windows` pass; the latest Public Desktop readback leaves only the intentionally unmanaged local-only accessibility shortcuts outside the tracked managed set.

## Release 2026.3.12.286 - 2026-03-12

### Summary
This release renames the tracked Windows Public Desktop shortcut set into the approved English `Business`/`Personal` vocabulary, restores the managed `SourTimes` and company-branded Web/Blog shortcuts, lowercases every repo-managed Chrome profile-directory value, and upgrades Public Desktop cleanup from exact-name replacement to semantic duplicate normalization.

### Highlights
- Renamed the tracked Public Desktop labels to the approved English contract, including the explicit overrides `s18NextSosyal Business`, `r13CicekSepeti Business`, `r14CicekSepeti Personal`, `r17PTTAVM Business`, and `r18PTTAVM Personal`.
- Restored `q1SourTimes`, `s15{TitleCase(company_name)} Web`, and `s16{TitleCase(company_name)} Blog` as tracked managed shortcuts while keeping `q2Spotify` and `q3Netflix` intact.
- Refactored Chrome shortcut profile routing so business/personal intent is carried by shortcut metadata instead of old label text, and both `company_name` and the email local-part are normalized to lowercase before being emitted into `--profile-directory`.
- Hardened `10002-create-shortcuts-public-desktop` so installer-created overlaps such as Google Chrome, Microsoft Edge, AnyDesk, and Visual Studio 2022 are removed by semantic duplicate matching, while unrelated unmanaged Public Desktop shortcuts remain untouched.
- Moved `clagnos-interactive-session-helper.ps1` into `tools/scripts/` and updated runtime helper-asset resolution to load it from the new repo path while keeping the guest-side helper copy target unchanged.
- Updated the tracked health snapshot, `.env.example`, README, AGENTS contract, and smoke assertions so the new label set, lowercase Chrome profile rule, restored shortcuts, and duplicate-normalization behavior are enforced together.

## Release 2026.3.12.284 - 2026-03-12

### Summary
This release adds `clagnos do --vm-action=reapply` as a repo-managed VM repair action, keeps it available when Azure provisioning is not currently succeeded, and aligns the interactive selector, help output, README examples, and smoke coverage with the new lifecycle-action contract.

### Highlights
- Added `do --vm-action=reapply`, which resolves the managed VM target, runs `az vm reapply`, and then prints a refreshed lifecycle status report.
- Expanded the `do` parser hints, interactive action picker, CLI help pages, and README examples so `reapply` is documented alongside the existing lifecycle actions.
- Added smoke coverage for the new action, including parser acceptance, provisioning-guard bypass behavior, interactive selection, help/docs visibility, and the concrete `az vm reapply` invocation path.

## Release 2026.3.12.283 - 2026-03-12

### Summary
This release expands the tracked Windows shortcut/update contract with employee-aware Chrome profile routing, new marketplace and tooling shortcuts, new prerequisite install tasks, and a generic local-accessibility boundary that removes vendor-specific ownership from the tracked repo surface while preserving local-only flexibility.

### Highlights
- Added committed `employee_email_address` and `employee_full_name` placeholders and wired employee-aware token replacement through the command runtime and task materialization layer.
- Expanded the tracked Public Desktop shortcut task with `i1Internet Kurumsal`, `i2Internet Bireysel`, `r11-r22`, `k3Github Copilot CLI`, `v1VS2022Com`, and the renamed `t10Azd CLI`; `e1Mail` and every `Bireysel` Chrome shortcut now use the employee email local-part for `--profile-directory`, while `Kurumsal` shortcuts continue using `company_name`.
- Added tracked Windows task `132-install-vs2022community.ps1`, raised tracked task `115-install-npm-packages-global` to the new timeout contract, and extended it to install the GitHub Copilot CLI prerequisite.
- Reworked the tracked startup/profile-copy surface so one private local-only accessibility flow is handled generically: tracked code now provides neutral host autostart discovery, keeps unmanaged public shortcuts intact, and no longer contains vendor-specific startup or profile-copy ownership.
- Revalidated the whole non-live gate and completed a live Windows acceptance cycle on `rg-examplevm-sec1-g1/examplevm`, including isolated local-only accessibility reruns, a full `update --step=vm-update --auto --windows` pass with `success=45`, repo-managed restart validation, and post-reboot SSH/process readback confirming the active manager session, startup shortcut, automatic utility service, and running local accessibility processes.

## Release 2026.3.11.282 - 2026-03-11

### Summary
This release closes the live Windows publish-gate blockers uncovered during end-to-end acceptance, tightens the `copy-settings-user` profile-sync rules around deterministic skip paths, fixes the provisioning-ready poll used by post-deploy feature verification, documents the required live release bar, and compresses the startup `script description:` banner into a single line.

### Highlights
- Fixed the provisioning-ready wait so post-deploy feature verification now reads `az vm get-instance-view` from `instanceView.statuses` and the top-level `provisioningState`, eliminating the false empty-state retry loop observed on real existing VMs.
- Hardened Windows task `10005-copy-settings-user` so required profile roots are copied explicitly, compatibility-alias/reparse-point paths are skipped deterministically, missing HKCU source branches no longer abort assistant hive seeding, and best-effort profile artifacts can be skipped safely on ACL or in-use failures.
- Added a written live release-acceptance gate to `README.md`, `AGENTS.md`, and the documentation contract checks, requiring a real create/update/status/show/connection verification cycle whenever live release-readiness is claimed.
- Changed the startup banner in `Invoke-ClagnosMain` so `script description:` now stays on one line with the rest of its explanatory text.
- Revalidated the change set with `tests/clagnos-smoke-tests.ps1`, `tests/powershell-compatibility-check.ps1`, and `tests/documentation-contract-check.ps1`, then completed a live `clagnos update --auto --windows` acceptance run with `vm-update` finishing `success=41, failed=0, warning=0, error=0, reboot=0`.

## Release 2026.3.11.281 - 2026-03-11

### Summary
This release finishes the modular-runtime cutover by removing the transitional root loaders entirely. `clagnos.ps1` now loads one ordered manifest and then dot-sources the refactored leaf files directly, so the active runtime path is fully modernized with no legacy root-wrapper layer left in `modules/`.

### Highlights
- Added `modules/clagnos-runtime-manifest.ps1` as the single ordered source of truth for runtime leaf-file loading.
- Removed the old root wrapper files from `modules/core/`, `modules/config/`, `modules/tasks/`, `modules/ui/`, and `modules/commands/`, so current execution no longer flows through compatibility-loader scripts.
- Updated the smoke suite to assert that the deleted root loader paths do not exist and that `clagnos.ps1` and the manifest do not reference them.
- Revalidated the cutover with `tests/code-quality-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/powershell-compatibility-check.ps1`.

## Release 2026.3.11.280 - 2026-03-11

### Summary
This release is a behavior-preserving modularization of the `modules/` runtime: the historical root module paths stay loadable as compatibility shims, but the implementation now lives in smaller domain files with command-level and parameter-level ownership, so the repo is easier to extend without reintroducing large monolithic PowerShell files.

### Highlights
- Kept the existing entrypoint and root runtime file paths, then turned those roots into deterministic compatibility loaders that dot-source the new leaf files in a fixed order.
- Split `modules/commands/` by public command so each supported command now has its own `entry.ps1`, `contract.ps1`, `runtime.ps1`, and `parameters/` directory, with reusable shared parameter logic staying under `modules/commands/shared/parameters/`.
- Moved create/update orchestration internals into dedicated `context`, `steps`, `features`, `pipeline`, and shared-runtime helpers, and limited `modules/ui/` to prompts, selection flows, show rendering, and connection-facing helpers.
- Split task transport internals into `modules/tasks/run-command/` and `modules/tasks/ssh/`, while isolating shared system, config, naming, runtime, and task-discovery helpers under `modules/core/` and `modules/config/`.
- Revalidated the refactor with the full non-live gate: `tests/code-quality-check.ps1`, `tests/clagnos-smoke-tests.ps1`, and `tests/powershell-compatibility-check.ps1`.

## Release 2026.3.11.279 - 2026-03-11

### Summary
This release hardens the live publish-gate surface by adding non-interactive SSH/RDP validation, turning hibernation and nested virtualization into verified post-deploy outcomes, redacting password-bearing values from `clagnos show`, and making the Windows interactive/update tasks more resilient under real guest conditions.

### Highlights
- Added `clagnos ssh --test` and `clagnos rdp --test` so the repo can prove connection readiness without launching `ssh.exe` or `mstsc.exe`.
- Changed post-deploy feature reconciliation so `VM_ENABLE_HIBERNATION=true` and `VM_ENABLE_NESTED_VIRTUALIZATION=true` now require successful verification instead of best-effort warnings; nested virtualization is validated from inside the running guest.
- Updated `clagnos show` to redact password-bearing config values and to print nested-virtualization state, validation source, and evidence when available.
- Improved the Windows interactive desktop helper plus the Be My Eyes and iCloud tasks so they can use an existing interactive desktop when present and register deferred `RunOnce` installs when Store-backed flows cannot complete headlessly.
- Hardened Windows UX/profile-copy, Ollama, Docker Desktop, and AnyDesk tasks to reduce avoidable noise, stale-installer waits, and non-fatal native exit-code regressions during real update runs.

## Release 2026.3.11.278 - 2026-03-11

### Summary
This release removes an artificial compatibility-test bottleneck by fixing the smoke-test stubs behind the new provisioning-ready gate, so the PowerShell compatibility matrix no longer spends minutes waiting on fake Azure provisioning and now finishes in normal time again.

### Highlights
- Fixed the two post-deploy feature-enable smoke tests so their local `az` stubs now answer `az vm get-instance-view` with an immediate `Provisioning succeeded` snapshot.
- Eliminated the repeated synthetic provisioning wait loop that had stretched `tests/powershell-compatibility-check.ps1` into multi-minute runs and timeout-prone output floods.
- Revalidated the fix with a direct smoke rerun and a full compatibility-matrix rerun after the stub update.

## Release 2026.3.11.277 - 2026-03-11

### Summary
This release makes the repo publish-ready for GitHub by adding `-h` as a first-class help alias, expanding the public community/support files, extending the non-live CI smoke gate, and redacting publish-inappropriate literals from maintained history docs without changing the product's current runtime contract.

### Highlights
- Added `-h` support next to `--help` for the global CLI surface and command-specific help pages, then refreshed the README and help examples so operators can rely on either form consistently.
- Added `CONTRIBUTING.md`, `SUPPORT.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates, and a pull-request template shaped around the current custom non-commercial license, maintainer-curated contact-first workflow, and sponsorship/commercial-contact path.
- Extended `.github/workflows/quality-gate.yml` so GitHub now runs the non-live smoke-contract suite alongside the existing static audit, PowerShell compatibility, Linux shell syntax, and workflow lint checks.
- Redacted environment-specific VM names, profile examples, local filesystem paths, and other publish-unnecessary literals from `CHANGELOG.md`, `release-notes.md`, and `docs/prompt-history.md` while preserving the repo's technical history.
- Normalized tracked Linux shell scripts to LF and added `*.sh text eol=lf` to `.gitattributes`, removing the CRLF-induced `bash -n` failures from the publish gate.

## Release 2026.3.11.276 - 2026-03-11

### Summary
This release changes the Windows Public Desktop shortcut task from a destructive full mirror into a managed-only reconcile pass, restores host-driven startup mirroring for installed guest apps, and expands the late health snapshot so preserved unmanaged shortcuts and host-observed startup surfaces are both inventoried explicitly.

### Highlights
- Updated `10002-create-shortcuts-public-desktop` so it now preserves unmanaged Public Desktop shortcuts such as local-only accessibility shortcuts while still rebuilding the tracked managed shortcut set and clearing the manager, assistant, and default desktop roots.
- Restored dynamic host startup-profile discovery and moved `10001-configure-apps-startup` to method-based host parity, including guest compatibility scaffolding for host apps that start from LocalMachine surfaces.
- Expanded `10099-capture-snapshot-health` and the smoke contract so unmanaged Public Desktop shortcuts are inventoried instead of flagged as unexpected, and startup verification now reads back the decoded host startup profile instead of a static guest snapshot.

## Release 2026.3.11.275 - 2026-03-11

### Summary
This release expands the managed Public Desktop contract again by adding the requested `g1-g4` developer shortcuts and `q2-q8` quick-access web shortcuts, all reusing the same Chrome launcher shape as `i1Internet`.

### Highlights
- Extended `10002-create-shortcuts-public-desktop` with `g1Apple Developer`, `g2Google Developer`, `g3Microsoft Developer`, `g4Azure Portal`, `q2Spotify`, `q3Netflix`, `q4EDevlet`, `q5Apple Account`, `q6AJet Flights`, `q7TCDD Train`, and `q8OBilet Bus`, each using the existing Public Desktop Chrome target and argument contract.
- Expanded `10099-capture-snapshot-health` and the smoke contract so the new shortcut names and URLs are now read back and enforced together with the rest of the managed Public Desktop set.

## Release 2026.3.11.274 - 2026-03-11

### Summary
This release adds a tracked Windows autologon task right after the IO Unlocker step, validates the configured `manager` credentials before applying Sysinternals Autologon, renumbers the tracked iCloud task to keep the catalog order contiguous, and extends the Windows late health snapshot with explicit autologon readback.

### Highlights
- Added `130-autologon-manager-user` so the Windows update flow now resolves `autologon.exe`, validates `VM_ADMIN_USER` and `VM_ADMIN_PASS` locally, runs `autologon /accepteula <user> . <password>`, and then verifies the resulting Winlogon state.
- Renamed the tracked iCloud task from `130-install-icloud-system` to `131-install-icloud-system` so the new autologon task can run immediately after `129-configure-unlocker-io`.
- Expanded `10099-capture-snapshot-health` and the smoke contract so autologon status is now inventoried together with the rest of the Windows late-stage machine state.

## Release 2026.3.11.273 - 2026-03-11

### Summary
This release expands the managed Public Desktop contract again by restoring the requested `e1`, `m1`, `n1`, `r1-r10`, and `u7Network and Sharing` shortcuts while keeping the existing Chrome-profile, mirroring, admin-flag, and per-user desktop cleanup behavior unchanged.

### Highlights
- Extended `10002-create-shortcuts-public-desktop` with the new Outlook inbox launcher, Notepad shortcut, marketplace and tax-portal Chrome shortcuts, and a direct `control.exe /name Microsoft.NetworkAndSharingCenter` shortcut for `u7Network and Sharing`.
- Expanded `10099-capture-snapshot-health` and the smoke contract so the new shortcut names, URLs, and launcher fragments are now read back and enforced together with the existing Public Desktop set.

## Release 2026.3.11.272 - 2026-03-11

### Summary
This release closes the remaining `public-desktop-icons` gap by making `10002-create-shortcuts-public-desktop` clear the manager, assistant, and default desktop roots itself, so the Public Desktop mirror task now enforces the shared-desktop contract end to end on its own.

### Highlights
- Extended `10002-create-shortcuts-public-desktop` so it now deletes lingering entries from `C:\Users\<manager>\Desktop`, `C:\Users\<assistant>\Desktop`, and `C:\Users\Default\Desktop` as part of the same mirror pass that rebuilds the managed Public Desktop shortcut set.
- Updated smoke coverage so the shortcut task must continue to own both the Public Desktop mirror and the per-user desktop cleanup contract.

## Release 2026.3.11.271 - 2026-03-11

### Summary
This release adjusts the `z1Google Account Setup` public desktop shortcut so it now opens Chrome through the exact requested `cmd.exe /c start "" "chrome.exe" ... chrome://settings/syncSetup` launcher shape while keeping the shared Public Desktop Chrome profile contract intact.

### Highlights
- Changed `10002-create-shortcuts-public-desktop` so `z1Google Account Setup` now targets `C:\Windows\System32\cmd.exe` and uses a `start "" "C:\Program Files\Google\Chrome\Application\chrome.exe"` wrapper with `--new-window`, `--start-maximized`, the shared Public Desktop `--user-data-dir`, and the direct `chrome://settings/syncSetup` URL.
- Updated smoke coverage so the Windows shortcut contract now explicitly checks the new `z1` target/argument layout.

## Release 2026.3.11.270 - 2026-03-11

### Summary
This release hardens the Windows late-stage update flow around the requested public desktop, iCloud, and UX contract: `company_name` is now mandatory for repo-managed Windows web shortcuts, the public desktop is rebuilt as a fully mirrored managed set, iCloud is installed through a tracked Store task, user desktops are emptied in favor of Public Desktop, and the UX/readback tasks now cover System Restore shutdown, RDP compatibility, Explorer no-group defaults, and best-effort desktop artifact suppression.

### Highlights
- Added `130-install-icloud-system` and wired it into the tracked Windows update catalog so iCloud for Windows is installed unattended from the Microsoft Store path and exposed to the new `d4ICloud` desktop shortcut.
- Rebuilt `10002-create-shortcuts-public-desktop` around one manifest-driven shortcut contract with the requested 1-based naming, full Public Desktop mirroring, required `company_name`, dynamic `s15/s16`, new `s17/s18`, updated CLI targets, `Ctrl+Alt+N` for NVDA, run-maximized defaults, run-as-admin link flags, and `%UserProfile%` start-in handling for console entries.
- Extended `10003-configure-ux-windows` to disable System Restore and shadow copies, keep RDP NLA off, suppress thumbnail artifacts on known desktop roots, hide shell desktop icons, and reinforce Explorer details/no-group defaults for `This PC` and seeded user settings.
- Reworked `10005-copy-settings-user` so assistant/default settings propagation is now deterministic and fast enough for isolated exec loops, while keeping manager, assistant, and default desktops empty and preserving the helper-asset contract.
- Expanded `10099-capture-snapshot-health` so it now inventories the final shortcut set, target/args/hotkey/start-in/show/admin state, unexpected Public Desktop entries, per-user desktop emptiness, artifact scans, RDP/System Restore state, and Explorer bag values.
- Verified the release live on the Windows VM with isolated `exec` runs of `130`, `10003`, `10002`, `10005`, and `10099`, then repeated `10002` and `10003` for idempotency before the final health pass.

## Release 2026.3.11.269 - 2026-03-11

### Summary
This release introduces the new shared task-band model across Windows and Linux, adds the read-only `task --list` inventory command, renames the tracked task files/catalogs to the new numbering scheme, moves the Windows health snapshot task to `10099`, and standardizes fallback task defaults across tracked and local discovery.

### Highlights
- Added `clagnos task --list` with `--vm-init`, `--vm-update`, and `--disabled`, using the same tracked/local discovery pipeline as real orchestration.
- Renamed tracked Windows and Linux task files so the repo now uses the shared task-number bands `01-99`, `101-999`, `1001-9999`, and `10001-10099`.
- Updated tracked catalogs with explicit `taskType` metadata and band-aligned priorities while keeping the existing timeout values unchanged.
- Updated local-task ordering so runtime now resolves priority from script metadata first, then filename number, then deterministic `1001+` auto-detection.
- Standardized tracked fallback defaults to `priority=1000` and `timeout=180`, while local tasks continue to default missing timeout values to `180` and keep metadata-first priority resolution.
- Moved the Windows late health check to `10099-capture-snapshot-health` and updated move-cutover and `exec` selectors to target the new number.

## Release 2026.3.10.267 - 2026-03-10

### Summary
This release moves intentionally local-only stage tasks under explicit `local/` directories, keeps them metadata-driven and disk-discovered, restores the local accessibility asset layout, and simplifies stage-related `.gitignore` rules around that model.

### Highlights
- Added `local/` and `local/disabled/` task locations to the stage loader while keeping tracked root tasks catalog-driven and duplicate tracked/local task names invalid.
- Restored the Windows local accessibility asset layout under `local/` and kept asset resolution relative to the local task file directory.
- Updated `AGENTS.md`, `README.md`, and smoke/documentation checks so the repo now documents and enforces the new local-only task contract.

## Release 2026.3.10.266 - 2026-03-10

### Summary
This release completes the Windows update `31/32` correction by renaming the tracked task files and catalog entries, not just their priorities: `31` is now the Unlocker task and `32` is now the app-startup task.

### Highlights
- Renamed the tracked Windows files so `31-configure-unlocker-io.ps1` now contains the IObit Unlocker task and `32-configure-apps-startup.ps1` now contains the startup-configuration task.
- Updated the Windows update catalog to match the new file names while keeping the existing timeout values.
- Refreshed smoke coverage and release history so the tracked repo now consistently documents `31=unlocker`, `32=app-startup`.

## Release 2026.3.10.265 - 2026-03-10

### Summary
This release makes one catalog-order correction on the Windows update flow: `32-configure-unlocker-io` now runs before `31-configure-apps-startup`, while both tasks keep their previous timeout values.

### Highlights
- Swapped only the catalog priority values of `31-configure-apps-startup` and `32-configure-unlocker-io`.
- Kept both task names, scripts, and timeout values unchanged.
- Updated smoke coverage so the tracked Windows update order assertion matches the corrected priority order.

## Release 2026.3.10.264 - 2026-03-10

### Summary
This release removes selected private local-only Windows tasks and payloads from tracked history, normalizes the tracked Windows task naming/order, and moves the remaining local-only behavior behind script-level metadata instead of hardcoded runtime special cases.

### Highlights
- Renamed tracked Windows `vm-init` and `vm-update` scripts to the shared `NN-verb-noun-target` convention and reordered the tracked Windows update flow so bootstrap/package tasks start first while late-stage UX, user-settings, and health tasks run last.
- Moved selected private local-only Windows tasks and payloads out of source control while keeping them runnable from disk through ignored local-only files.
- Added generic script-local metadata support for local-only Windows tasks so they can declare `priority`, `enabled`, `timeout`, and asset copy requirements without re-entering tracked catalogs.
- Replaced the runtime's old task-specific Windows asset-copy branch with generic metadata-driven asset resolution.
- Rewrote the active `main` and `dev` histories to remove the selected private local-only tracked paths and their tracked textual references, while preserving `backup-main` and `backup-dev` as untouched backups.
- Expanded smoke and documentation checks to cover the normalized naming/order model, local-only metadata discovery, and the cleaned tracked surface.

## Release 2026.3.10.263 - 2026-03-10

### Summary
This release hardens the `set` command so its public parameters now map cleanly to real behavior and every successful feature-toggle change is reflected back into the local `.env` contract.

### Highlights
- Removed the `set` command's dependency on the heavier Step-1 runtime initialization path and switched it to direct managed-VM target resolution.
- `set` now writes the resolved `RESOURCE_GROUP`, `VM_NAME`, and any successfully applied `VM_ENABLE_HIBERNATION` / `VM_ENABLE_NESTED_VIRTUALIZATION` values back to `.env`.
- Added smoke coverage for both the full-success and partial-success-then-failure cases so `.env` stays aligned with the actual Azure-side result.

## Release 2026.3.10.262 - 2026-03-10

### Summary
This release tightens three shared configuration contracts at once: the repo-managed pyssh client path now has a non-empty default, NSG rule naming now consistently uses the `nsg-rule-` prefix, and create/update flows now honor shared `.env` booleans for hibernation and nested-virtualization intent.

### Highlights
- Set the committed `PYSSH_CLIENT_PATH` default to `tools/pyssh/ssh_client.py` and updated runtime call sites to use that shared default consistently.
- Standardized `NSG_RULE_NAME_TEMPLATE` and related defaults/tests on the `nsg-rule-` prefix.
- Added shared `VM_ENABLE_HIBERNATION=true|false` and `VM_ENABLE_NESTED_VIRTUALIZATION=true|false` keys to the `.env` contract and wired them into create/update post-deploy feature handling.
- Updated `README.md`, `AGENTS.md`, `.env.example`, and validation coverage so the new config contract is documented and enforced together.

### Reliability And Process Notes
- Setting `VM_ENABLE_HIBERNATION=false` now skips create/update hibernation enablement cleanly, even when the chosen SKU supports it.
- Setting `VM_ENABLE_NESTED_VIRTUALIZATION=false` now suppresses the create/update nested-virtualization enablement/validation path without changing the separate `set` command surface.

## Release 2026.3.10.261 - 2026-03-10

### Summary
This release hardens the repository's configuration contract by removing committed runtime identity and password defaults, making required VM identity and credential inputs fail fast when they are missing or left on placeholders, and drawing a sharper line between app-wide `.env` configuration and task-local config blocks inside guest-task scripts.

### Highlights
- Removed shared runtime fallback defaults for legacy sample VM names and demo passwords from the orchestration/UI paths; non-interactive flows now require real `VM_NAME`, `VM_ADMIN_USER`, `VM_ADMIN_PASS`, `VM_ASSISTANT_USER`, and `VM_ASSISTANT_PASS` values.
- Added shared config-resolution helpers so placeholder-sensitive values are rejected consistently with precise remediation hints.
- Updated `.env.example` to use neutral placeholders only, document the new config split, and keep `company_name` as the app-wide brand/profile override for repo-managed Chrome web shortcuts.
- Refactored key Windows update tasks so mutable task-only constants live in explicit top-of-file config blocks instead of being embedded through the task body.
- Kept user-specific shortcut bundles and similar task-only values local to their owning task instead of widening the global `.env` surface unnecessarily.
- Expanded smoke coverage to verify the new required-config behavior and to confirm that shared runtime modules no longer carry the old personal/demo defaults.

### Reliability And Process Notes
- This change intentionally surfaces missing `.env` values earlier: auto/non-interactive orchestration no longer invents VM identity or secret defaults on the operator's behalf.
- The repository now documents a stricter config split: use `.env` for app-wide customization and secrets, and use task-local config blocks for values that matter only to a single init/update task.

## Release 2026.3.10.260 - 2026-03-10

### Summary
This release focuses on the developer-facing contract and documentation set. It adds a custom non-commercial `LICENSE`, rewrites the README into a much broader operator/developer manual, rewrites the roadmap around business value and a more sustainable delivery rhythm, converts prompt-history recording to an English-normalized model, tightens the engineering contract in `AGENTS.md`, and adds a pre-commit release-document gate so repo-changing prompts cannot be committed without aligned changelog and release-notes updates.

### Highlights
- Added a root `LICENSE` file with the repository's custom non-commercial terms, including learning/teaching/evaluation allowances, private non-commercial modification allowance, and a clear commercial licensing and sponsorship contact path.
- Expanded `README.md` into a much more detailed guide covering purpose, target audience, quick start, architecture, configuration, full command guide, task model, troubleshooting, developer workflow, and licensing.
- Reworked `roadmap.md` around business value, relaxed planning horizons, promotion rules, and concrete done criteria.
- Updated `AGENTS.md` so maintained docs, help text, comments, and operator-facing runtime wording must stay in English.
- Changed `docs/prompt-history.md` to an English-normalized contract and translated the existing historical entries into English while preserving structure and chronology.
- Added `tests/pre-commit-release-doc-check.ps1` and wired it into `.githooks/pre-commit`, so repo-changing staged work must include `CHANGELOG.md` and `release-notes.md` in the same final change set.
- Fixed `.github/workflows/quality-gate.yml` so the PowerShell compatibility job now calls the current `tests/powershell-compatibility-check.ps1` entrypoint.

### Reliability And Process Notes
- The stronger release-doc gate is intentionally non-recursive: release-history-only staged changes are exempt, but any other staged repo change must include both `CHANGELOG.md` and `release-notes.md`.
- The English-only documentation rule still allows explicit literal display-label exceptions where the repository intentionally preserves a user-defined non-English shortcut or product/site name.
- No Azure runtime behavior changed in this release; the work is contract, documentation, and developer-workflow hardening.

## Release 2026.3.10.259 - 2026-03-10

### Summary
This release turns `clagnos` into a documented, process-hardened, operator-facing Azure VM toolkit with one orchestrator, explicit task catalogs, stronger documentation boundaries, formal local/CI quality gates, explicit hook enable/disable controls, a new state-aware VM power-action command, a corrected direct resize contract, a fully `--vm-name`-based move/set surface, faster isolated `exec` task runs, connection commands that now require a running VM, hardened Ollama and Docker Desktop installer recovery, a far more reliable Windows interactive UX and user-settings propagation path, an expanded public desktop/app-install contract that now includes the Store-backed Codex desktop app plus a statically curated and live-validated guest auto-start set, and a hardened snapshot-based regional move path validated live from `austriaeast` to `swedencentral`.

### Highlights
- Unified command surface for configure, create, update, inspect, connect, power-action, move, resize, set, and delete workflows.
- `move` and `set` now consistently use `--vm-name`; the legacy `--vm` form is no longer part of their public contract.
- One orchestrator for Windows and Linux with parity-first step semantics.
- Catalog-driven guest task execution with explicit priority and timeout metadata.
- New `do` command for `status`, `start`, `restart`, `stop`, `deallocate`, and `hibernate` actions against managed VMs.
- `do --vm-action=hibernate` remains the public hibernation action; Azure still executes it through the deallocation-based hibernate path, so `stop` remains the non-deallocated power-off path.
- Corrected `resize` command syntax to use `--vm-name`, added `--windows`/`--linux` support, and kept resize interactive when parameters are omitted.
- Direct `exec` task runs now accept `--vm-name` and skip the broader Step-1 resource inventory path so isolated task execution reaches pyssh more quickly.
- Windows Chrome-based public desktop shortcuts now take their default `--profile-directory` from `.env` `company_name`, so shared web shortcuts can target a stable company profile such as `orgprofile` instead of deriving the profile name from `VM_NAME`.
- Snapshot-based regional move now deallocates the source VM before snapshotting, validates that the source group is safe for automatic purge, creates target public IPs with explicit zonal intent to avoid Azure CLI warning noise, attaches copied OS disks without invalid admin-credential flags, and keeps post-cutover task validation strict before old-source cleanup.
- `README.md` and `clagnos help move` now document the move cutover sequence and include an observed live timing reference: the `austriaeast -> swedencentral` move of a `Standard_D4as_v5` VM with a `127 GB` OS disk took about `25-30 minutes`, with cross-region snapshot copy as the dominant phase.
- `ssh` and `rdp` now refuse politely unless the target VM is already running, with a direct hint to start it through `do`.
- External `ssh` and `rdp` connection commands for managed VMs.
- Windows update task `18-install-ollama-system` now short-circuits healthy existing installs, detaches `ollama serve` from the SSH transcript, clears stale installer locks before `winget`, and bounds installer wait time with explicit timeout diagnostics.
- Windows update task `16-install-docker-desktop` now clears stale installer locks before `winget install Docker.DockerDesktop` and reports timed-out installer waits without hanging indefinitely.
- Windows update task `12-install-vscode-system` now short-circuits healthy existing installs instead of re-entering `winget` during resumed e2e runs.
- Windows update task `04` now applies and validates `manager` UX settings through a bounded password-logon scheduled task instead of a reboot/autologon loop.
- Windows update task `04` now enforces hibernate-menu visibility, Explorer details/no-group defaults, desktop name-sort plus auto-arrange/grid alignment, Control Panel small icons, file-copy details, keyboard repeat delay, Task Manager full view via `TaskManager\settings.json`, and hidden Search/Widgets/Task View taskbar controls.
- Windows update task `04` now also uses writable .NET registry handles for user-hive writes, avoids generating a synthetic minimal Task Manager store, and hides Widgets through the supported `AllowNewsAndInterests` machine policy after live `TaskbarDa` failures showed that the prior path was not reliable.
- Windows update task `05` now keeps only deterministic machine-level advanced settings and no longer carries unsupported audio/max-volume automation.
- Windows update task `36-copy-settings-user` now propagates the repo-owned manager user settings into `assistant`, the default profile, and the logon-screen hive with explicit exclusions for volatile and identity-bound stores.
- Windows update task `36-copy-settings-user` was further hardened so `assistant` receives its HKCU/user-class seed through a dedicated password-logon worker while default-profile seeding skips heavyweight non-settings branches such as `AppData\\Local\\Programs`, `Microsoft\\WindowsApps`, and default-profile `LocalLow`, removing the live robocopy stalls seen during repeated isolated `exec` validation.
- Windows update task `33-create-shortcuts-public-desktop` now creates the refreshed public shortcut set for ChatGPT, internet, WhatsApp desktop/web, Google and Office account setup, banking links, and command-style tool launchers with canonical `a1/i0/i1/i2/z1/z2/t*` names, dynamic WhatsApp desktop resolution, and `cmd.exe` wrappers for `.cmd` launchers.
- Windows update tasks `30` through `37` now install and verify iTunes, Be My Eyes, NVDA, Microsoft Edge, VLC, rclone, OneDrive, and Google Drive through the same bounded install-and-readback pattern used elsewhere in the repo.
- Windows update task `19-install-codex-app` now installs the Store-backed Codex desktop app through `winget install codex -s msstore`, verifies it through AppX/StartApps/winget readback, and registers a deferred RunOnce retry when a noninteractive Store session cannot finish immediately.
- Windows update task `32-configure-apps-startup` now applies a static startup snapshot for Docker Desktop, Ollama, OneDrive, Teams, one private local-only accessibility launcher, and iTunesHelper onto the guest VM and writes the resulting launchers into the machine Startup folder.
- Windows update task `32-configure-apps-startup` now also creates missing `StartupApproved` registry keys before it marks existing startup shortcuts enabled, after isolated live `exec` validation exposed that reruns on an already-provisioned VM could otherwise fail on Docker Desktop approval.
- Windows update task `33-create-shortcuts-public-desktop` now also normalizes the broader Public Desktop set with social-media links, app launchers, dynamic app-path fallbacks, one private local-only accessibility hotkey, and Unicode-safe `q1Eksisozluk` handling.
- Windows update task `33-create-shortcuts-public-desktop` now also adds `a3CodexApp` and keeps the requested `OpenAI.Codex_26.306.996.0_x64__2p2nqsd0c76g0\app\Codex.exe` fallback target in the public shortcut contract, while `37-capture-snapshot-health` inventories that shortcut during late-stage validation.
- Windows update task `37-capture-snapshot-health` now also reads back the static machine-startup shortcut set so late-stage validation can show exactly which auto-start launchers were expected and present.
- Windows update task `37-capture-snapshot-health` now inventories the expanded public desktop shortcut set and reads back the exact target-path, argument, hotkey, and Unicode shortcut contracts during late-stage validation.
- Windows update task `37-capture-snapshot-health` now uses a `30s` catalog timeout so live move cutover validation does not produce false timeout warnings on a healthy target VM.
- Windows `vm-update` task catalog timeouts are now derived from observed successful live durations with a 30% buffer, including isolated rerun calibration for tasks `27` and `29`.
- Windows `vm-update` task catalog timeouts are now also calibrated for tasks `30` through `37` from successful isolated live durations, with rerun-confirmed bounded values applied back into the catalog.
- Hardened naming, env-key, and validation contracts across provisioning flows.
- Post-deploy feature enablement for hibernation and nested-virtualization support checks.
- Broader Windows guest update coverage, including UX tuning and public desktop shortcut generation.
- One private local-only Windows accessibility payload now deploys from local zip packages, including staged version replacement, roaming settings restore, and stricter post-copy verification.

### Breaking and Contract-Significant Changes
- Legacy command names and aliases have been removed rather than preserved.
- `configure` is the current configuration-preview command; `config` is no longer part of the public surface.
- `do` is the current VM power-action command; `release` is no longer a valid VM action token.
- `resize` now uses `--vm-name`; the legacy `--vm` form is no longer part of the public resize contract.
- `VM_NAME` is the single naming seed for managed resources.
- `VM_SSH_PORT` and `VM_RDP_PORT` are the canonical connection-port keys.
- `VM_TASK_OUTCOME_MODE` is the canonical task outcome policy key.
- Generic task-directory config keys and other historical fallbacks are no longer part of the runtime contract.

### Reliability and UX Improvements
- Earlier validation for region, VM name, naming templates, and mutation-critical config.
- Cleaner operator logging with explicit stage summaries and failure/reboot reporting.
- Catalog-driven timeout handling for guest tasks.
- Repo-managed Python tooling configured to avoid bytecode cache artifacts.
- More consistent Linux/Windows terminology and step/task wording.
- Renamed Windows vm-update task entries are now aligned with the task catalog so the intended `19/20/28` ordering and timeout policy apply again.
- The merged Windows update catalog now preserves the late-stage ordering intent by keeping public desktop shortcuts at priority `98`, running `copy-settings-user` at priority `99`, and moving health snapshot to priority `100`.
- Windows interactive UX tasks no longer depend on reboot-resume metadata or autologon cleanup; isolated `exec` runs stay on the normal bounded SSH flow.
- Isolated live validation now covers tasks `04`, `05`, and one private local-only late-stage task on `rg-examplevm-ate1-g1/examplevm`, including idempotent rerun of `04` and private local-only hash/manifest readbacks.
- Isolated live validation now also covers the repaired Windows UX/user-settings late-stage chain: task `04` succeeds after the registry-write fix, task `28` completes without hive-unload or default-profile copy hangs, and task `29` confirms the post-copy machine state on `rg-examplevm-ate1-g1/examplevm`.
- Isolated live validation now also covers full Windows `vm-init` and `vm-update` sweeps plus a focused Ollama rerun that confirms HTTP readiness on port `11434`.
- Isolated live validation now also covers tasks `30` through `37` plus rerun-confirmed `27` and `29`, proving the new package installs, app-backed Public Desktop shortcuts, one private local-only accessibility hotkey assignment, and Unicode-safe `q1Eksisozluk` readback on `rg-examplevm-ate1-g1/examplevm`.
- Persistent SSH task parsing now strips spinner prefixes from `CLAGNOS_*` protocol markers so long-running Windows installers cannot hide task-completion signals.
- A fresh `create --auto --windows --perf --step-from=vm-update` rerun now completes successfully on `rg-examplevm-ate1-g1/examplevm` with `Standard_D4as_v5`, and the rebuilt VM answers on RDP port `3389`.

### Documentation and Process Improvements
- Expanded `AGENTS.md` into a repository engineering contract.
- Upgraded `README.md` into a fuller operator and contributor guide.
- Added full-project `CHANGELOG.md`.
- Added `docs/prompt-history.md` as a human-readable dialog ledger.
- Added `roadmap.md` to track future work.
- Added a GitHub Actions `quality-gate.yml` workflow and native local git hooks.
- Replaced the one-way hook installer with explicit enable/disable scripts for local git-hook control.
- Adopted commit-count version labels for `CHANGELOG.md` and `release-notes.md`.
- Normalized `CHANGELOG.md` and `release-notes.md` to LF line endings and pinned that expectation in `.gitattributes` so documentation-contract checks behave consistently.
- Removed the retired `docs/reconstruction/` folder after folding its remaining value into the maintained documentation set.
- Renamed the `tests/` scripts to clearer, self-explanatory dash-separated file names.
- Renamed the documentation contract gate to `documentation-contract-check` for clearer test intent.
- Renamed the `clagnos` smoke suite to `clagnos-smoke-tests` so the file name reflects its actual repo-specific purpose.
- Split code-quality, bash-syntax, and PowerShell-compatibility checks into separate scripts instead of using skip-style audit switches.
- Moved the manual history replay utility to `tools/scripts/git-history-replay.ps1` and corrected it so it resolves the quality script that actually exists in each historical worktree.
- Removed runtime auto-sync writes for task catalogs and moved catalog handling to manual-only editing.
- Standardized catalog fallback defaults to `priority=1000` and `timeout=180` when entries or timeout values are missing.
- Added a strict `AGENTS.md` rule requiring repository-wide context assimilation before implementing each prompt.
- Relaxed the prompt-history policy so non-mutating prompts are only recorded on explicit user confirmation, while repo-changing prompts still require prompt-history capture plus a commit.

### Operator Notes
- CI remains static and non-live. Azure provisioning is intentionally excluded from automated workflows.
- Some Windows application installs may still require first interactive sign-in for full activation even after unattended installation succeeds.
- `docs/prompt-history.md` is append-only for recorded turns; repo-changing prompts are mandatory entries, while non-mutating prompts are recorded only after explicit user confirmation.

### Known Limitations
- No live Azure end-to-end validation runs in CI.
- Some Store-backed Windows applications may need deferred first-sign-in finalization.
- Release notes are commit-count-versioned; the repo still does not use a tag-driven release workflow.
