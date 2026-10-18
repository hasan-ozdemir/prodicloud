# clagnos

`clagnos` is an interactive Azure virtual-computer operations toolkit for Windows and Linux. It exposes a numbered, lettered menu over the same validated PowerShell orchestration used by direct commands. A virtual computer combines its VM, managed disks, network interfaces, virtual network, subnets, public IP, NSG, and related rules. `cg.cmd` opens the menu; passing a command to `cg.cmd` forwards it to the same command engine.

At a glance:
- Customer teams get a repeatable Azure VM outcome that can feel closer to an all-in-one prepared remote computer than a portal-built raw VM.
- Executive teams get lower drift, faster support handoff, and one repo that captures runtime behavior, guest-configuration intent, release notes, and operating guidance together.
- Developers and DevOps maintainers get one command surface plus portable task folders that can preload apps, services, settings, desktop behavior, and UX details on both Windows and Linux.
- Employees, administrative teams, workers, and regular operators get a near-zero-touch first session: connect remotely and find the machine already prepared for common daily work.
- Visitors and sponsors can evaluate a mature operational toolkit with visible docs, quality gates, release discipline, and proof-of-outcome scenarios instead of vague promises.

## Table Of Contents
- [Quick Start Guide](#quick-start-guide)
  - [Why Start Here](#why-start-here)
  - [Interactive CLI](#interactive-cli)
  - [Prerequisites](#prerequisites)
  - [Repository Layout](#repository-layout)
  - [First Configuration Pass](#first-configuration-pass)
  - [Fastest Safe Path To Value](#fastest-safe-path-to-value)
  - [First End-To-End Run](#first-end-to-end-run)
  - [Daily Operator Shortcuts](#daily-operator-shortcuts)
- [Customer Business Value](#customer-business-value)
- [Executive Summary](#executive-summary)
- [Value By Audience](#value-by-audience)
- [Delivered VM Outcome Matrix](#delivered-vm-outcome-matrix)
- [Who clagnos Is For](#who-clagnos-is-for)
- [Why clagnos Exists](#why-clagnos-exists)
  - [What It Does](#what-it-does)
  - [Problems It Solves](#problems-it-solves)
  - [When To Use It](#when-to-use-it)
  - [When Not To Use It](#when-not-to-use-it)
- [Operational Command Matrix](#operational-command-matrix)
  - [Global Options Matrix](#global-options-matrix)
  - [Command Matrix](#command-matrix)
  - [Command Variations By Command](#command-variations-by-command)
- [Practical And Extensive Usage Scenarios](#practical-and-extensive-usage-scenarios)
  - [Create A Fresh Managed VM](#create-a-fresh-managed-vm)
  - [Update An Existing Managed VM](#update-an-existing-managed-vm)
  - [Inspect Managed Resource Groups And VM State](#inspect-managed-resource-groups-and-vm-state)
  - [Run One Task Or Open A Remote Shell](#run-one-task-or-open-a-remote-shell)
  - [Resize Compute Or OS Disk In Place](#resize-compute-or-os-disk-in-place)
  - [Move Regions And Clean Up Safely](#move-regions-and-clean-up-safely)
  - [Delete Only The Scope You Intend](#delete-only-the-scope-you-intend)
  - [Inspect And Control Power State](#inspect-and-control-power-state)
  - [Connect To The VM](#connect-to-the-vm)
- [Command Guide](#command-guide)
  - [Global Options](#global-options)
  - [`configure`](#configure)
  - [`create`](#create)
  - [`initialize`](#initialize)
  - [`update`](#update)
  - [`list`](#list)
  - [`show`](#show)
  - [`do`](#do)
  - [`task`](#task)
  - [`package`](#package)
  - [`component`](#component)
  - [`exec`](#exec)
  - [`connect`](#connect)
  - [`move`](#move)
  - [`resize`](#resize)
  - [`set`](#set)
  - [`delete`](#delete)
  - [`help`](#help)
- [Task Authoring And Execution](#task-authoring-and-execution)
  - [Task Folder Ownership](#task-folder-ownership)
  - [Task Naming Rules](#task-naming-rules)
  - [Timeouts, Priority, And Enable Flags](#timeouts-priority-and-enable-flags)
  - [Direct Task Execution With `task`](#direct-task-execution-with-task)
- [Configuration Guide](#configuration-guide)
  - [Runtime Precedence](#runtime-precedence)
  - [Global And VC Environment Files](#global-and-vc-environment-files)
  - [Shared VM Feature Toggles](#shared-vm-feature-toggles)
  - [Platform-Specific Settings](#platform-specific-settings)
  - [Connection And Task Settings](#connection-and-task-settings)
  - [Global Versus Task-Local Configuration](#global-versus-task-local-configuration)
- [Developer Benefits](#developer-benefits)
  - [Why Developers Move Faster](#why-developers-move-faster)
  - [Daily Maintainer Flow](#daily-maintainer-flow)
  - [Versioned Release Source Package](#versioned-release-source-package)
- [Core Mental Model](#core-mental-model)
  - [One Entrypoint, Two Platforms](#one-entrypoint-two-platforms)
  - [Top-Level Orchestration Steps](#top-level-orchestration-steps)
  - [Init Tasks Versus Update Tasks](#init-tasks-versus-update-tasks)
  - [Interactive Versus Auto Mode](#interactive-versus-auto-mode)
  - [Naming And Managed Resource Rules](#naming-and-managed-resource-rules)
- [Architecture From Zero To Hero](#architecture-from-zero-to-hero)
  - [Entrypoints And Runtime Modules](#entrypoints-and-runtime-modules)
  - [Configuration Resolution](#configuration-resolution)
  - [Task Folder Model](#task-folder-model)
  - [Windows And Linux Execution Model](#windows-and-linux-execution-model)
  - [End-To-End Create And Update Flow](#end-to-end-create-and-update-flow)
  - [Safety Model And Failure Handling](#safety-model-and-failure-handling)
  - [Documentation, History, And Release Discipline](#documentation-history-and-release-discipline)
- [Troubleshooting Guide](#troubleshooting-guide)
  - [Validation Failures](#validation-failures)
  - [Task Failures](#task-failures)
  - [Connection Failures](#connection-failures)
  - [Move And Resize Expectations](#move-and-resize-expectations)
- [Developer Workflow](#developer-workflow)
  - [Branching And Local Hooks](#branching-and-local-hooks)
  - [Quality Gates](#quality-gates)
  - [Live Release Acceptance](#live-release-acceptance)
  - [Support And Contribution Paths](#support-and-contribution-paths)
  - [Documentation Contract](#documentation-contract)
  - [Prompt History Rule](#prompt-history-rule)
- [Documentation Set](#documentation-set)
- [License And Sponsorship](#license-and-sponsorship)

## Quick Start Guide

### Why Start Here
This section is optimized for the reader who wants usable value quickly without skipping the repo's safety model. The goal is simple: get from clone to one visible Azure VM outcome fast, while still understanding what the command surface is doing, which config matters first, and how to verify that the result is healthy.

The workflow separates infrastructure creation, initial guest setup, maintenance, and package management. Create the virtual computer first, initialize its `vm-init` tasks, then use `p: setup all program packages` for a reviewed, dependency-ordered setup pass or `m: manage program packages` to choose the isolated builtin or custom package catalog. Both catalogs support Windows and Linux installer scripts.

### Interactive CLI
The optional first two console rows are controlled by `TOP_STATUS_LINES` in `clagnos.env` (default `false`). When `true`, they show the current screen, selected VC, subscription, active `Doing:` action, and inventory cache state; identical rows are not rewritten, and `Ready` has no advancing age counter. When `false`, Clagnos uses the compact header. Change the setting directly or through Configure > Advanced. TUI startup reads the saved subscription and active VC profile locally; inventory warmup continues in the background while the menu is usable.
If only a saved subscription ID is available, it is shown immediately; its display name is filled in when the Cloud subscriptions screen loads the Azure subscription list.
Run `.\cg.cmd` to open the menu. The welcome screen shows the `one tool for all common cloud operations` line, the selected Azure subscription name/id. The main menu offers `1. Virtual computers`, `2. Managed resource inventory`, and `3. Cloud subscriptions`; choose a subscription by number to update both the Azure CLI default and Clagnos's saved subscription. Use numbers or the shown letter shortcuts and press Enter. Press Escape or enter `b` to return one level, `c` to close a submenu flow, or `q` to exit. `.\cg.cmd <command> ...` forwards a direct command to the same `clagnos.ps1` runtime.

The selected virtual computer opens with compute, CPU/RAM, OS image, disks, security/feature settings, NIC/VNet/subnet/NSG, private/public IP, public DNS, tags, and attached-resource details. It also shows SSH/RDP endpoints, the Windows PowerShell remoting endpoint, and the configured manager and assistant usernames/passwords read from that VC's local `<vm-name>.env` profile; passwords are not included in progress or operation log messages. Its menus expose initialization, explicit managed-user password reset, maintenance, reviewed package setup-all, builtin/custom package status/install/repair/update/uninstall/reinstall and enable/disable, component list/show/CRUD and disk/NIC attachment, lifecycle/repair, resize/move, VM features, SSH/RDP/PowerShell remoting, remote commands, active and disabled tasks, package app-state, reports, and deletion. Select `o: operations` for numbered power actions (including graceful shutdown, hibernate/resume, immediate power-off, and force reset), feature toggles, resizing, and the other advanced operations.

On the first signed-in launch, a hidden background worker reads managed resource groups, their resources, and detailed VM state into a subscription-scoped local snapshot without blocking the welcome screen. An exclusive per-subscription worker lock prevents concurrent TUI instances from duplicating inventory calls. Later launches can reuse the snapshot immediately. The worker revalidates it every 60 seconds; `r: check or refresh managed resource cache`, a subscription change, or a command that may mutate Azure state requests an earlier refresh. A persisted refresh request survives closing the TUI, and snapshots older than five minutes are not used. Azure ETags detect changes, with resource-content signatures as a fallback when ETags are absent; unchanged validation preserves the current snapshot. Inventory and component list/show screens read this cache instead of repeating Azure list calls. If Azure CLI reads fail, the worker reports the error and retries with a bounded backoff.

Repeated inventory refresh requests are coalesced while a scan is pending; a new resource mutation can still supersede an in-progress scan so its result is checked again against Azure. When `TOP_STATUS_LINES=true`, the status strip polls worker state while waiting for menu input and receives each runtime `Doing:` update during a foreground operation.

Manage Programs prewarms installed-package status for the builtin and custom catalogs in the background. Complete package-status snapshots are cached per subscription, VC, platform, catalog, and status-check definition for 45 seconds, with the newest snapshot persisted locally between TUI runs. Catalog screens show the cached status immediately while a stale or missing result refreshes; `r` requests a refresh and `s` queues a status check. Install and uninstall still execute on the selected VC, while target resolution and VM endpoint lookup reuse a recent validated inventory snapshot where available. A successful SSH bootstrap can be reused for 20 seconds so closely spaced task/package operations avoid an extra probe connection.

Creating a virtual computer opens a numbered wizard. The configured/default OS, name, region, VM size, image, storage tier, security options, feature toggles, ports, and disk size are marked with `>`. Long lists use `p`/`n` for previous/next, `g` for a page number, and `f`/`t` for first/last page; select only a number visible on the current page. Wizard controls are `s` to keep the configured default for this step, `k` to keep defaults for all remaining steps, `a` to accept the current default, `l` to accept remaining defaults, and `c` to close without creating. Menus use numbered or lettered choices and do not require arrow-key navigation.

The wizard accepts inbound TCP ports as comma-separated numbers and ascending ranges such as `22,80,443,3000-3300`; it validates ports from 1 through 65535, merges overlapping ranges, and adds the required SSH/RDP ports. OS disk-size text accepts `MB`, `GB`, or `TB` (for example `1MB`, `128GB`, or `1TB`) and normalizes to whole GiB within the Azure OS disk limit of 1–4095 GiB. Invalid entries are explained and requested again before the create command is dispatched.

### Prerequisites
- Windows host with PowerShell and the Azure CLI available.
- Azure subscription access with permission to create, update, and delete compute and networking resources.
- Azure CLI sign-in is strictly required for Azure-touching commands. Run `az login` before using `create`, `initialize`, `update`, `list`, `show`, `do`, remote `task` or `package` operations, `component`, `connect`, `move`, `resize`, `set`, `exec`, or `delete`. Local task/package availability changes do not require Azure sign-in. The TUI welcome screen can open without Azure sign-in; Azure inventory remains unavailable until `az login`. `configure` can open without Azure sign-in, but its Azure-backed pickers stay read-only until `az login` is available.
- Local Git for the repo workflow and hook support.
- Python available when the repo-managed pyssh helper is needed.

### Repository Layout
- `cg.cmd`: elevated interactive launcher; command arguments are forwarded to the same runtime.
- `scripts/clagnos-cli.ps1`: interactive menu frontend.
- `clagnos.ps1`: unified command/orchestration entrypoint.
- `modules/clagnos-runtime-manifest.ps1`: deterministic ordered manifest of the runtime leaf files loaded by `clagnos.ps1`.
- `modules/core/`: shared runtime foundations, CLI/system helpers, task discovery, and host/runtime utilities.
- `modules/config/`: dotenv parsing, naming templates, region-code helpers, and config-resolution primitives.
- `modules/commands/`: command-owned implementations split by command, plus shared pipeline/context/step/feature helpers.
- `modules/ui/`: prompts, interactive selection, show/report rendering, and connection presentation helpers.
- `modules/tasks/`: Azure Run Command and persistent SSH transport/runtime helpers.
- `vm-packages/{builtin,custom}/<platform>/`: physically isolated package catalogs; each catalog has a `tasks.toml` availability list and package folders; see [`vm-packages/README.md`](vm-packages/README.md).
- `vm-init/<platform>/{builtin,custom}/` and `vm-update/<platform>/{builtin,custom}/`: task catalogs with a `tasks.toml` availability list and portable task folders.
- `tools/`: pyssh helper, scripts, Windows helper assets, and git-hook toggles.
- `tests/`: local quality and contract checks.
- `docs/prompt-history.md`: English-normalized historical ledger of completed prompt/summary pairs.

### First Configuration Pass
1. Copy `clagnos.env.example` to `clagnos.env`.
2. Use `clagnos.env` for `SELECTED_AZURE_SUBSCRIPTION_ID`, operator identity, naming templates, Azure/SSH timeouts, task paths, and `DEFAULT_*` values used only when creating a VC.
3. Copy `vc.env.example` to `<vm-name>.env` only when preparing a profile manually. It contains that VC's resource group, OS, region, compute/image/disk, feature flags, connection ports, package transport, usernames, and passwords. The create wizard creates and saves this file for new VCs; existing VCs load their own profile by name.
4. Set `SELECTED_COMPANY_NAME`, `SELECTED_COMPANY_WEB_ADDRESS`, `SELECTED_COMPANY_EMAIL_ADDRESS`, `SELECTED_EMPLOYEE_EMAIL_ADDRESS`, and `SELECTED_EMPLOYEE_FULL_NAME` in `clagnos.env` for Windows flows. Repo-managed public desktop web shortcuts require the company and employee identity inputs; business shortcuts use `SELECTED_COMPANY_NAME` plus `SELECTED_COMPANY_WEB_ADDRESS`, personal shortcuts use the email local-part from `SELECTED_EMPLOYEE_EMAIL_ADDRESS` as the Chrome `--profile-directory`, and future mail-facing shortcuts can reuse `SELECTED_COMPANY_EMAIL_ADDRESS`. The task normalizes profile-directory sources to lowercase before writing the Chrome profile name.
5. Keep task-only constants in the owning task script's top config block. Runtime `*.env` files are local and git-ignored.

### Fastest Safe Path To Value
If you want the fastest safe path to value, use this order. The target outcome is not only "the VM exists"; it is "someone can connect and start real work quickly" with a machine that already looks curated. On the current Windows path that includes Store-aware public desktop shortcuts, managed short-launcher wrapping for overlong Chrome/Edge-style shortcut invocations, git-ignored task app-state plugins, sanitized package app-state archives versioned beside their package manifests, and WSL2 plus Docker Desktop prerequisite hardening before developer-runtime health is considered ready:
1. Open `.\cg.cmd`, choose `c: configure settings`, and review global `clagnos.env` values and the next-create preview.
2. Choose Virtual computers, then `c: create virtual computer`. This creates the managed group, network, and VM only.
3. Select the new VM and use `i: initialize VC` to run its enabled `vm-init` tasks. Existing manager/assistant passwords are preserved on later init runs; use `k: reset managed-user passwords from <vm-name>.env` for the separate, typed-confirmation reset operation.
4. Use `p: setup all program packages` to review enabled packages from both catalogs, install missing packages, and repair detected Clagnos-managed startup drift, or use `m: manage program packages` to inspect a catalog and run individual package actions. `install` is a no-op when already installed; use `repair` to repair the same version, `update` to move to a newer vendor version, and `reinstall` to force uninstall followed by a clean install.
5. Use `u: update VC` for vm-update maintenance, then verify the VM with its report and connection tests.

Representative PoC / PoE outcomes from the current repo shape:
- Employee or knowledge-worker desktop: connect over RDP and land on a machine with browser, collaboration, storage, media, support, and accessibility tooling already staged, with desktop shortcuts and startup behavior already prepared.
- Developer or DevOps workstation: connect and find PowerShell, Git, Python, Node.js, Azure CLI, GitHub CLI, azd, VS Code, WSL2, Docker Desktop, Ollama, Codex app, and other repo-managed tooling prepared by the current portable task inventory.
- Administrative or support machine: connect and find remote-support, startup, health-capture, user-copy, and advanced settings tasks already applied so day-two assistance is easier.
- Linux proof path: use the same orchestrator, connection flow, and portable task-folder model today, then extend the lighter default guest with your own task-authored apps, services, and settings as needed.

### First End-To-End Run
```powershell
az login
.\cg.cmd
```
In the menu, choose `c` to configure settings if needed, then choose `1` for Virtual computers. Use `c` to create a virtual computer, select it by number, run `i` to initialize it, and use `p` to review and apply setup for all packages.

For a live acceptance run that creates a fresh Windows VC, installs every enabled package in both catalogs, runs every enabled init and update task, validates the full report, nested virtualization, hibernation/resume, and SSH/RDP connectivity, use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\live-vc-e2e.ps1 -RunLive -VmName <unused-vm-name> -VmSize <compatible-azure-vm-size>
```

The test requires an unused VM name, a compatible VM size and image, an authenticated active Azure subscription selected in `clagnos.env`, a Windows operator identity, and passwords in the target `<vm-name>.env` profile. Store-backed packages install through bounded password-logon tasks without requiring an RDP or interactive desktop session; new Teams uses Microsoft's signed headless Teams bootstrapper to provision the current client for all users. It then installs every enabled Windows package and leaves the VM running after a successful hibernation/resume check. It is opt-in and never runs in CI. The committed B-series default does not support nested virtualization. When the Compute SKU response omits that capability, Clagnos checks the documented VM family; a B-series selection with nested virtualization enabled now fails during configuration review, before creating a resource group, network, or VM. See Microsoft's [Bsv2 feature support table](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/bsv2-series). Choose a size whose documented and subscription-reported features satisfy the requested toggles, or set `VM_ENABLE_NESTED_VIRTUALIZATION=false` in that VC profile for a B-series VM. To continue a partially completed run without recreating the managed VM or rerunning init tasks, pass `-ResumeExisting -ResumeFromPackage <catalog>/<package-id>` after fixing the reported cause.

For a live lifecycle matrix against an existing Windows VC, use the opt-in WinRM test:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\live-package-lifecycle-e2e.ps1 -RunLive -VmName <vm-name> -ResourceGroup <resource-group> -SubscriptionId <subscription-id> -RestartAfterPass
```

It runs install, same-version repair, update, uninstall, reinstall, and status verification for all 36 enabled Windows builtin packages in dependency order over WinRM, without requiring an RDP or logged-on desktop session. Windows Package Manager and Microsoft Edge are protected by this Windows image; Clagnos blocks their uninstall and reinstall before guest mutation and records those actions as unsupported. Windscribe uninstall/reinstall reads the active service identity's persistent firewall state and runs its signed two-phase uninstaller through a bounded password-logon scheduled task. It does not require a manager desktop session; if the firewall state is indeterminate or Always On, Clagnos refuses removal and records those actions as unsupported. Other package actions remain testable. Per-operation deadlines are capped at 360 seconds by default and 480 seconds only when the report contains measured evidence; the VM activity watcher reports CPU, RAM, network, and disk changes, retries once after a sustained idle period, and fails with the observed lifecycle phase if progress does not return. Concurrent E2E runs against the same VM are rejected. The test does not create infrastructure or resize, detach, or replace disks or networking; it compares the Azure VM, disk, NIC, and endpoint snapshot before and after the package cycle. `-RestartAfterPass` performs one controlled restart and verifies JAWS logon-screen startup, both managed post-logon profiles, and the JAWS preference files. A JSON result report is written under the local temp directory. This test is gated by `-RunLive` and is never run in CI.

The builtin JAWS package installs only the ENU product language and uses the vendor-supported `/InstallerUILanguage enu` and `/DisableExternalServices` arguments through WinGet `--custom`; its [status check](https://www.freedomscientific.com/training/enterprise/installation/) verifies the ENU-only and offline-feature policy. The versioned JAWS app-state archive includes the local `Settings\enu\*.j*` files and voice profiles, sanitized for reuse by both managed users. JAWS uninstall uses the signed Freedom Scientific silent shared-uninstall mode only when no other main Freedom Scientific product is installed; its cleanup is bounded and limited to JAWS-owned paths. If Windows has a JAWS `version.dll` loaded in other processes, Clagnos preserves that one locked file for the package's hash-verified replacement path and requests a restart only when Windows must apply the replacement.

### Repeatable VC Setup And Purge

The profile-driven launchers use the current repository checkout and the selected subscription id in `clagnos.env`:

```powershell
.\setup-vc1.cmd -PreflightOnly
.\remove-vc1.cmd -PreflightOnly
.\remove-vc1.cmd
.\remove-vc1.cmd       # verifies absence and returns successfully
.\setup-vc1.cmd
.\setup-vc1.cmd        # reconciles the same live VC without rebuilding a healthy target

.\setup-vc2.cmd -PreflightOnly
.\setup-vc2.cmd
.\setup-vc2.cmd -ResumeAtPackageStage
.\remove-vc2.cmd
```

Both setup launchers call the shared `setup-vc.ps1` engine and read `{vm-name}.env`. WinGet-dependent packages declare the builtin Windows Package Manager as a setup dependency, and its status check requires a usable WinGet executable. The engine validates the saved OS, region, image, VM SKU, disk size/storage SKU, security and feature settings, managed NIC/VNet/subnet/NSG/public IP attachments, inbound TCP ports, and credentials before Azure changes. It persists normalized profile values before provisioning; Clagnos persists generated group/resource names before creating them. Existing VCs record Azure-verified network resource names in their VC profile, and setup verifies profile port ranges against the attached NSG rule. Each Azure command is pinned to the selected subscription id, regardless of the Azure CLI default subscription. Setup creates a missing VC, purges and recreates an interrupted managed partial create, safely resizes the VM or expands its OS disk when needed, re-runs idempotent vm-init/vm-update and package setup, and verifies the final Azure state plus RDP/SSH/WinRM. Package failures are reported after independent package work and final health checks. Transcripts are written under `%TEMP%\clagnos-setup-{vm-name}-*.log`; AnyDesk’s signed installer is verified locally and on the VM before installation.

Setup automatically removes and recreates the selected managed resource group when the VM’s region, OS image/type, security settings, disk storage SKU/size, or required resource inventory cannot be reconciled safely in place. Recreate deletes guest data on that VM. Unmanaged targets and ambiguous ownership stop before deletion. `-PreflightOnly` is read-only. `-ResumeAtPackageStage` requires an existing compatible managed VM and resumes at package prerequisites.

The shared `remove-vc.ps1` engine backs `remove-vc1.cmd` and `remove-vc2.cmd`. It inventories every resource in the profile’s Clagnos-managed resource group, writes a git-ignored purge journal before deletion, deletes the whole group through `cg.cmd`, waits with a bounded timeout, and rechecks the group and captured resource IDs. If a run is interrupted, the next invocation resumes from that journal. Repeated removal completes any remaining cleanup or returns a verified no-op when the VC and its resources are already absent. The local VC profile remains available for the next setup run. Provider-level retention that prevents immediate purge is reported as a failure instead of a successful hard purge.

### Daily Operator Shortcuts
```powershell
.\cg.cmd --version
.\cg.cmd -h
.\cg.cmd show --group=<resource-group>
.\cg.cmd do --vm-action=start --group=<resource-group> --vm-name=<vm-name> -s <subscription-guid>
.\cg.cmd task --list --vm-update --windows
.\cg.cmd task --save-app-state --vm-update-task=115 --group=<resource-group> --vm-name=<vm-name> -s <subscription-guid>
.\cg.cmd task --restore-app-state --vm-update-task=115 --group=<resource-group> --vm-name=<vm-name> -s <subscription-guid>
.\cg.cmd task --save-app-state --source=lm --user=.current. --vm-update-task=115 --windows
.\cg.cmd task --restore-app-state --target=lm --user=.current. --vm-update-task=115 --windows
.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --vm-size=Standard_D4as_v5 --windows
```

## Customer Business Value

`clagnos` compresses the time between "we need a working Azure VM" and "someone can remotely connect and start real work" into one operator workflow. The practical benefit is not just faster provisioning; it is lower variance after provisioning. The repo keeps infrastructure intent, guest configuration, direct task reruns, diagnostics, release notes, and support-facing guidance together, so a team does not have to rediscover the same setup logic every time a VM must be rebuilt, updated, resized, repaired, or handed to another person.

The strongest current story is the Windows workstation path. The menu separates infrastructure creation, guest initialization, individual package changes, and vm-update maintenance, so operators can see and control each stage. The task catalog still configures startup behavior, public desktop shortcuts, Store-backed desktop launches, advanced Windows settings, app-state replay, and safe user preferences. Operators choose which catalogued applications and tools to install, update, or remove before connecting.

From a customer-facing perspective, the value proposition is concrete:
- guided path to a prepared remote Windows workstation in Azure, backed by the current portable task inventory
- faster time to a usable VM with known software, known guest-side configuration, and a prepared desktop experience
- safer day-two operations because the same toolkit handles update, inspect, resize, move, repair, and delete flows
- more predictable support handoff because runtime behavior, docs, release notes, and prompt history live in the same repository

Representative PoC / PoE stories the current repo can already support:
- A customer demo or pilot machine that already contains the common tooling, shortcuts, and tuned settings needed to make the environment feel complete on first login.
- A cloud-hosted employee workstation where the user connects remotely and finds mainstream daily apps, developer tools, service tooling, startup entries, and desktop organization already staged.
- A support or accessibility-focused machine where remote-support tools, accessibility apps, and curated desktop/startup behavior reduce the amount of manual aftercare needed after provisioning.

## Executive Summary

For decision-makers, `clagnos` is an operational standardization asset. It turns a previously manual, portal-heavy, and person-dependent VM build into a repo-governed process with validation before mutation, visible orchestration steps, repeatable guest task folders, and non-live quality gates. That matters because environment drift, undocumented post-install tweaks, and ad hoc support work are expensive even when the VM count is small.

Viewed as a service outcome rather than a scripting repo, `clagnos` helps teams deliver an Azure-hosted computer experience, not just an Azure-hosted VM. The Windows path combines managed infrastructure with explicit guest initialization, selectable package actions, desktop configuration, startup behavior, advanced settings, and supportability. That shortens the path from "budget approved" to "someone is productively connected and working."

The executive-level outcomes are straightforward:
- lower operational variance across fresh builds and maintenance windows
- faster onboarding for internal operators, downstream support teams, and end users who simply need a prepared machine
- clearer release readiness because the repo already enforces docs, quality, and live acceptance discipline
- stronger sponsor and stakeholder confidence because the value is visible in the repo structure, not only in verbal explanation

Windows is the richest end-user path today. Linux is already reliable, intentionally lighter by default, and fully extensible through the same task model, so the platform story can keep expanding without replacing the operator contract.

## Value By Audience

| Audience | What they care about | What `clagnos` delivers | Why it matters |
| --- | --- | --- | --- |
| Customer | A usable VM quickly, with fewer surprises | One command surface for create, update, inspect, connect, resize, move, and delete flows, plus a prepared guest experience on the Windows hero path | The delivered environment is easier to understand, verify, and support. |
| Executive / decision maker | Risk reduction, repeatability, supportability | Validation before mutation, explicit orchestration, repo-owned release and docs discipline, and a service-like remote workstation outcome | Operational work becomes more predictable and less person-dependent. |
| Employee / knowledge worker | A machine that feels ready on first login | Browsers, collaboration apps, storage tools, desktop shortcuts, startup entries, and tuned settings from current Windows task coverage | The first remote session can feel closer to "sit down and work" than "finish setting up the machine." |
| Administrative / support team | Easier handoff, assistance, and guided maintenance | Remote-support tooling, health capture, curated desktop/startup behavior, and readable lifecycle commands | Supporting the machine takes less rediscovery and less ad hoc recovery work. |
| Developer / DevOps / maintainer | Faster iteration, fewer hidden scripts, isolated reruns | Catalog-driven init/update tasks, direct `task` and `exec` paths, one Windows/Linux mental model, and easy task-based extensibility | Maintenance and debugging become narrower, faster, and more deterministic. |
| Worker / field operator | Reliable access to the same prepared toolset from anywhere | Remote connection flow, curated shortcuts, common apps, and a repeatable rebuild/update path | The cloud machine behaves more like a stable working environment than a one-off build. |
| Operator / regular user | Practical daily commands that do what they say | Clear lifecycle, connection, inventory, and repair commands with readable output | Day-to-day work is easier without learning a sprawling platform surface first. |
| Visitor / evaluator | Evidence that the repo is real and usable | Readable README, release notes, prompt history, tests, workflow gates, and proof-of-outcome scenarios | Evaluation is based on visible substance rather than vague promises. |
| Sponsor / backer | A credible project with continuing value | Strong operator documentation, explicit contracts, repeatable acceptance, and clear business framing | Sponsorship has a concrete quality and maintainability story behind it. |

## Delivered VM Outcome Matrix

| Outcome area | Windows managed VM outcome | Linux managed VM outcome | Operator impact | Business value |
| --- | --- | --- | --- | --- |
| Base access | Local users, OpenSSH, RDP, WinRM PowerShell remoting, firewall ports, repo-managed connection flow | Local users, SSHD port config, firewall ports, repo-managed connection flow | Teams can connect immediately with less setup drift. | Handoffs happen faster and with less rediscovery. |
| Core tooling | PowerShell 7, Git, Python, Node.js, Azure CLI, GitHub CLI, azd, VS Code, 7-Zip, Sysinternals, FFmpeg | System package upgrade, Node capability tuning, SSHD tuning | A new VM becomes useful for cloud, scripting, and diagnostics fast. | Less first-day setup work and less tool inconsistency. |
| Developer runtime | Docker Desktop, WSL2, npm global package set, Ollama, Codex app, VS 2022 Community, WSL prerequisite hardening, Docker health probes, and docker-desktop-focused WSL state replay | Node-ready SSH environment and updated base packages | Engineering workflows can start earlier and recover with fewer hidden prerequisites. | Faster onboarding and less rebuild waste. |
| Collaboration and daily apps | Edge, Chrome validation, Teams, WhatsApp, OneDrive, Google Drive, VLC, iTunes, iCloud | Minimal by design | The machine feels operational, not half-finished. | Customer-facing and operator-facing use is easier to stage. |
| Accessibility and remote support | AnyDesk, Windscribe, NVDA, JAWS, Be My Eyes, startup flows, autologon manager, advanced Windows settings, public desktop shortcuts | Minimal by design | Assisted-operation scenarios are easier to reproduce and support. | Broader usability and faster support response. |
| Desktop and personalization | Startup configuration, grouped public desktop shortcuts, Store-backed `AppsFolder` launches where supported, Windows UX tuning, advanced settings, git-ignored task app-state replay, versioned sanitized package preferences, and safe user preference copy | Extensible through the same task model rather than a rich built-in desktop catalog | People connect to a machine that already feels curated and less drift-prone. | Less post-build manual cleanup and faster user adoption. |
| Health and observability | Snapshot-health capture, show/report output, direct task reruns, explicit redeploy repair | Snapshot-health capture, show/report output, direct task reruns | Troubleshooting narrows quickly to the failing area. | Less wasted time during support and maintenance. |
| Lifecycle changes | Create fresh, explicit rebuild by `delete` plus `create`, update, reapply, redeploy, hibernation, move, VM-size resize, managed OS disk expand, explicit shrink guidance | Create fresh, explicit rebuild by `delete` plus `create`, update, move, VM-size resize, managed OS disk expand, explicit shrink guidance | The same toolkit still works after day one. | Operations do not regress to ad hoc portal work. |

## Who clagnos Is For

- Operators who want reproducible Azure VM environments without rebuilding the full stack by hand every time.
- Maintainers who need Windows and Linux parity under one command surface.
- Developers who want infrastructure, guest tasks, and operator workflows documented together.
- Small teams that value pragmatic automation, explicit state, and readable PowerShell over opaque orchestration layers.
- Stakeholders and sponsors who want visible evidence of operational maturity, not just a thin wrapper around Azure CLI calls.

## Why clagnos Exists

### What It Does
- Provisions Azure infrastructure for one managed Windows or Linux VM from one orchestrator.
- Applies deterministic guest initialization and guest update task inventories.
- Gives operators lifecycle commands for status, start/resume, restart/reset, shutdown, immediate power-off, reapply, redeploy, stop, deallocate, hibernate-stop, hibernate-deallocate, move, resize, connect, inspect, and delete flows.
- Keeps command wording, configuration behavior, and execution semantics as parallel as possible across Windows and Linux.

### Problems It Solves
- Eliminates ad hoc VM setup drift caused by one-off portal changes and manual guest tweaking.
- Replaces hidden or implicit guest scripts with explicit, portable task-folder ordering and timeouts.
- Reduces unsafe Azure mutations by validating names, regions, SKUs, image values, and state before mutating resources.
- Gives one repeatable operator workflow for create, update, repair, inspect, connect, and cutover work.
- Captures repo behavior, release notes, and development decisions in the same repository instead of splitting them across chat history and tribal knowledge.

### When To Use It
- When one managed VM per flow is the main unit of operation.
- When you need repeatable Windows or Linux workstation/server-like environments in Azure.
- When you need deterministic reruns of guest-side tasks after provisioning.
- When move, resize, hibernation, and isolated task reruns need to stay operator-friendly.

### When Not To Use It
- When you need large-scale fleet orchestration across many VMs at once.
- When you want a generic IaC module library rather than one opinionated operator toolkit.
- When you want a broad public open-source license with unrestricted commercial use.

## Operational Command Matrix

### Global Options Matrix

| Option | Applies to | Operational effect | Common usage note |
| --- | --- | --- | --- |
| `--auto` | `create`, `initialize`, `update`, `delete` | Runs the command without waiting for interactive confirmation | Use it only when the target and intent are already explicit. |
| `--perf` | Most public commands | Prints timing metrics for the current command | Useful during profiling, acceptance, and long-running change windows. |
| `--windows` | `create`, `initialize`, `update`, `exec`, `resize`, `package` | Forces the Windows platform path or validates Windows expectation | Use this when the target platform must be explicit. |
| `--linux` | `create`, `initialize`, `update`, `exec`, `resize`, `package` | Forces the Linux platform path or validates Linux expectation | Use this when the target platform must be explicit. |
| `-s`, `--subscription-id=<subscription-guid>` | All Azure-touching commands plus `task --run-*` and `task --save/restore-app-state` | Targets Azure operations to one subscription and persists CLI-provided subscription intent locally | `-s`, `--subscription-id=<subscription-guid>`: target Azure subscription for every Azure-touching command; successful CLI usage also writes `SELECTED_AZURE_SUBSCRIPTION_ID` into `clagnos.env`. |
| `-h`, `--help` | All public commands | Prints quick help or command-specific help | `-h`, `--help` are equivalent operator aliases. |

### Command Matrix

| Command | Purpose | Mutation level | When to use it | Primary outcome |
| --- | --- | --- | --- | --- |
| `configure` | Review, edit, validate, preview, and save global `clagnos.env` settings and create defaults | Local global config only | Before create/update work, or when app-wide settings need editing | Validated global values with a next-create preview |
| `create` | Create a fresh managed group, initial network, and VM | Azure-mutating | First deployment or explicit rebuild flow | New virtual computer infrastructure; guest stages remain separate. |
| `initialize` | Run enabled `vm-init` tasks on an existing managed VM | Guest-mutating | Initial guest bootstrap | Initialized guest access and base configuration. |
| `update` | Run enabled `vm-update` maintenance tasks | Guest-mutating | Ongoing maintenance | Package installers live in their isolated package catalogs. |
| `list` | Print managed inventory by type | Azure-read-only | Inventory, targeting, quick visibility | Managed group/resource listings |
| `show` | Print a full managed report and optionally export redacted JSON | Azure-read-only | Health review, support handoff, release verification, diagnostic export | Screen report or redacted JSON file |
| `do` | Apply lifecycle or repair actions | Azure-mutating or read-only for `status` | Power-state control, reapply, redeploy, hibernation flow | Target VM lifecycle action |
| `task` | List tasks, view local run history, explicitly enable/disable a task, run one task, or save/restore task or package app-state | Local for inventory/history and confirmed availability changes; Azure-touching for remote task/app-state actions; local-machine for `--source=lm` / `--target=lm` | Review task state and outcomes, change future task availability, rerun one task, or refresh one payload | Verified catalog change, history view, or isolated task/app-state action |
| `package` | Check status, install, update, uninstall, enable, or disable one builtin/custom package | Guest-mutating except status and catalog availability | Manage packages on one VC | Verified catalog or package action result |
| `component` | List/read/create/update/delete a Clagnos-managed Azure component | Azure-read-only for list/show; Azure-mutating for create/update/delete | Inspect or change one VC component | Component state or dependency-reviewed mutation |
| `connect` | Launch or test SSH/RDP/Windows PowerShell remoting | Azure-touching, local-client action | SSH access, Windows desktop access, or Windows remote PowerShell commands | Direct client launch, PSSession, or connection test |
| `exec` | Open direct remote shell path or run one remote command | Azure-touching and guest-touching | Interactive shell work or one-shot remote command execution | One direct shell or command result |
| `move` | Move a managed VM to another region | Azure-mutating | Planned cutover or regional relocation | Health-gated regional move |
| `resize` | Change VM SKU or expand OS disk | Azure-mutating | Compute sizing change or safe disk growth | Resized VM or grown OS disk |
| `set` | Apply hibernation and validate or store nested virtualization requests | Azure-mutating plus guest validation | Feature-state management | Updated hibernation state and validated guest capability |
| `delete` | Delete a selected managed scope after showing its resource chain | Azure-mutating | Controlled cleanup | Deleted selected target scope, verified absent in Azure. |
| `help` | Print the command catalog or one command's details | Local/read-only | Operator discovery and reference | Command documentation |

Windows package actions use `PACKAGE_TRANSPORT=ssh|winrm` from the target VC profile, with `DEFAULT_PACKAGE_TRANSPORT` in `clagnos.env` as the create default. The selected transport is strict: authentication or transfer failures stop the action and do not silently retry through the other transport. WinRM uses the manager credentials and adds only the exact target endpoint to the local TrustedHosts list when it is not already present.

To compare the read-only package status path over both transports, run `tools/benchmark-package-transports.ps1` with one existing target and package. It takes five samples per transport by default, prints medians and ranges, and restores the original target profile's `PACKAGE_TRANSPORT` setting afterward.

### Command Variations By Command

#### `configure`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd configure` | none | Opens the interactive global `clagnos.env` editor | First configuration pass or safe local config maintenance | Edits global identity, Azure selection, naming templates, runtime settings, and create defaults. VC-specific values stay in each `<vm-name>.env`. |
| `.\cg.cmd configure --help` | `--help` | Prints the configure editor contract | Operator discovery | `configure` is interactive-only and rejects target-selection flags such as `--group`, `--vm-name`, and `--subscription-id`. |

#### `create`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd create` | interactive | Creates a new managed group, initial network, and VM | First deployment | It stops after VM deployment; use initialize for vm-init and package for software. |
| `.\cg.cmd create --auto` | `--auto` | Unattended fresh infrastructure/VM deployment | Controlled deployment | CLI overrides win over global `DEFAULT_*` create values; platform, name, region, size, and credentials must resolve. |
| `.\cg.cmd create --step-from=group --step-to=vm-deploy` | step window | Runs a validated infrastructure window | Recovery or diagnosis | Guest task stages are not part of create. |

#### `initialize`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd initialize --group=<resource-group> --vm-name=<vm-name>` | target selectors | Runs enabled vm-init tasks | Guest bootstrap | Requires an existing managed VM. |
| `.\cg.cmd initialize --auto --group=<resource-group> --vm-name=<vm-name>` | `--auto`, target selectors | Runs init tasks without review prompts | Automated bootstrap | Does not create Azure resources. |
| `.\cg.cmd initialize --group=<resource-group> --vm-name=<vm-name> --reset-managed-user-passwords` | target selectors, explicit reset flag | Resets manager and assistant passwords to that VC's `<vm-name>.env` values after typed confirmation | Credential rotation | Interactive-only; ordinary init preserves existing passwords. |

#### `update`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd update` | interactive | Runs vm-update maintenance tasks on an existing VM | Manual upkeep | Prompts for a subscription if needed. |
| `.\cg.cmd update --auto --group=<resource-group> --vm-name=<vm-name>` | `--auto`, target selectors | Runs vm-update tasks | Controlled maintenance | Package operations are outside task-stage catalogs. |
| `.\cg.cmd update --step=vm-update --auto --group=<resource-group> --vm-name=<vm-name>` | `--step` | Runs the maintenance task stage | Isolated maintenance | Use package for software tasks. |

#### `package`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd package --action=list --catalog=builtin --group=<resource-group> --vm-name=<vm-name> --windows` | catalog, target, platform | Lists builtin packages and their status | Standard software inventory | Availability comes from the catalog tasks.toml; installed status comes from validated package metadata. |
| `.\cg.cmd package --action=list --catalog=custom --group=<resource-group> --vm-name=<vm-name> --windows` | catalog, target, platform | Lists custom packages and their status | Operator-added software inventory | The custom and builtin catalogs remain isolated. |
| `.\cg.cmd package --action=install --catalog=builtin --package=visual-studio-code --group=<resource-group> --vm-name=<vm-name> --windows` | catalog, package id, target | Installs an absent package; returns no-op when already installed | Install one package | Install does not repair or upgrade. Disabled packages must be enabled first. |
| `.\cg.cmd package --action=repair --catalog=builtin --package=visual-studio-code --group=<resource-group> --vm-name=<vm-name> --windows` | catalog, package id, target | Repairs the detected installed version and verifies it remains installed | Repair one installed package | It does not run a vendor upgrade and fails before mutation if safe same-version repair is unavailable. Disabled packages must be enabled first. |
| `.\cg.cmd package --action=update --catalog=builtin --package=visual-studio-code --group=<resource-group> --vm-name=<vm-name> --windows` | catalog, package id, target | Runs the package's distinct update script and verifies status | Update one installed package | Packages that are absent are not implicitly installed. Disabled packages must be enabled first. |
| `.\cg.cmd package --action=setup-all --catalog=all --group=<resource-group> --vm-name=<vm-name> --windows --yes` | both catalogs, target | Reviews enabled packages in both catalogs, installs absent packages, and repairs managed startup drift | Prepare enabled packages on one VC | Omitting `--yes` requests a typed `SETUP ALL` confirmation. Disabled packages are skipped; unknown status and operation failures return a nonzero result after independent work completes. |
| `.\cg.cmd package --action=uninstall --catalog=builtin --package=visual-studio-code --group=<resource-group> --vm-name=<vm-name> --windows` | catalog, package id, target | Runs the allow-listed package remover | Remove one package | Requires exact `UNINSTALL` confirmation unless `--yes` is passed. |
| `.\cg.cmd package --action=reinstall --catalog=builtin --package=visual-studio-code --group=<resource-group> --vm-name=<vm-name> --windows --yes` | catalog, package id, target | Verifies removal, then installs the package again | Force a clean package install | Interactive mode requires exact `REINSTALL` confirmation. |
| `.\cg.cmd package --action=disable --catalog=custom --package=my-tool --windows` | catalog, package id | Disables future operations for one custom package | Block an operator package | Typed confirmation updates only its catalog `tasks.toml`. |
#### `component`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd component --action=list --type=disk --group=<resource-group>` | component type, group | Lists managed disk components | Inventory | Supported types are group, vm, disk, vnet, subnet, nic, ip, nsg, and nsg-rule. |
| `.\cg.cmd component --action=show --type=nic --group=<resource-group>` | component type, group | Shows one component and current properties | Inspect before editing | A number prompt appears when several matches exist. |
| `.\cg.cmd component --action=create|update|delete --type=<type> --group=<resource-group>` | action, type, group | Opens a validated type-specific CRUD flow | Change one VC component | Deletion displays linked resources and verifies Azure removal. |

#### `list`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd list` | none | Prints all managed inventory sections | Quick managed visibility | Purpose: print read-only managed inventory sections for clagnos-tagged resource groups and resources. |
| `.\cg.cmd list --type=group,vm` | `--type` | Narrows output to selected inventory types | Daily operator targeting | `list` gives a read-only managed inventory view across groups and resource types |
| `.\cg.cmd list --type=nsg,nsg-rule --group=<resource-group>` | `--type`, `--group` | Group-filtered managed inventory | Resource-specific inspection | Azure-read-only output; `--subscription-id` / `-s` only changes the subscription context and persists `SELECTED_AZURE_SUBSCRIPTION_ID` when it comes from the CLI |

#### `show`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd show` | none | Prints the broader managed report | Environment audit | Good for multi-group review. |
| `.\cg.cmd show --group=<resource-group>` | `--group` | Prints one managed group report | Support handoff and verification | `show` prints the expected inventory while password-bearing VC profile values are redacted. |
| `.\cg.cmd show --group=<resource-group> --vm-name=<vm-name>` | `--group`, `--vm-name` | Prints the managed report and one VM's target-derived configuration | Focused inspection of a single managed target | `show` stays read-only and uses actual Azure state without writing `clagnos.env`. |
| `.\cg.cmd show --export-json=<path>` | `--export-json`, optional `--overwrite` | Writes a machine-readable report with sensitive configuration redacted | Support handoff or downstream reporting | Existing files are preserved unless `--overwrite` is explicit. |

#### `do`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd do --vm-action=status --vm-name=<vm-name>` | `--vm-action=status` | Reads lifecycle state | Preflight and release checks | Fastest safety check before mutation. |
| `.\cg.cmd do --vm-action=start --group=<resource-group> --vm-name=<vm-name>` | lifecycle action | Starts the VM | Connection prep | Use before `connect --ssh` or `connect --rdp`. |
| `.\cg.cmd do --vm-action=resume --group=<resource-group> --vm-name=<vm-name>` | `resume` | Starts a hibernated VM | Resume a saved hibernation state | Allowed only while Azure reports the VM hibernated. |
| `.\cg.cmd do --vm-action=shutdown --group=<resource-group> --vm-name=<vm-name>` | `shutdown` | Requests guest shutdown; VM stays allocated | Graceful power-off | Compute billing continues until deallocation. |
| `.\cg.cmd do --vm-action=power-off --group=<resource-group> --vm-name=<vm-name>` | `power-off` | Stops immediately without guest shutdown | Forceful power-off | Uses `az vm stop --skip-shutdown`; may lose unsaved guest work and remains allocated. |
| `.\cg.cmd do --vm-action=reset --group=<resource-group> --vm-name=<vm-name>` | `reset` | Force-restarts an unresponsive VM through Azure redeploy | Recovery operation | Azure `--force` redeploys the VM; it is more disruptive than a normal restart. |
| `.\cg.cmd do --vm-action=reapply --group=<resource-group> --vm-name=<vm-name>` | `reapply` | Calls Azure reapply | Repair path | Good when provisioning succeeded but the instance needs Azure-side repair. |
| `.\cg.cmd do --vm-action=redeploy --group=<resource-group> --vm-name=<vm-name>` | `redeploy` | Calls Azure redeploy and waits for recovery | Host-level repair path | Good when the VM needs Azure-side host repair or provisioning recovery. |
| `.\cg.cmd do --vm-action=hibernate-stop --group=<resource-group> --vm-name=<vm-name>` | `hibernate-stop` | Guest-triggered hibernation through SSH | Preserve guest state without Azure deallocation path | Requires the VM to be running first. |
| `.\cg.cmd do --vm-action=hibernate-deallocate --group=<resource-group> --vm-name=<vm-name>` | `hibernate-deallocate` | Azure hibernation-through-deallocation path | Platform-backed hibernation path | Use when the VM is configured for hibernation. |

#### `task`

`cg.cmd task --history` prints the latest local task and package execution outcomes without connecting to Azure.

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd task --list --vm-init` | `--list`, `--vm-init` | Lists init tasks | Init audit | Shows real execution order. |
| `.\cg.cmd task --list --vm-update --windows` | `--list`, `--vm-update`, `--windows` | Lists Windows update tasks | Update inspection | Good before isolated reruns. |
| `.\cg.cmd task --list --disabled --vm-update --windows` | `--disabled` | Lists disabled tasks | Cleanup or contract review | Surfaces disabled reason and source. |
| `.\cg.cmd task --disable --vm-update-task=136 --windows` | `--disable`, task selector, platform | Disables one maintenance task in its catalog tasks.toml after typed confirmation; the task folder stays in place | Stop future task runs | Package availability is managed by the package command. |
| `.\cg.cmd task --enable --vm-update-task=136 --windows` | `--enable`, task selector, platform | Enables one maintenance task in its catalog tasks.toml after typed confirmation | Allow future task runs | Leaves `task.json` unchanged and verifies the `tasks.toml` state. |
| `.\cg.cmd task --run-vm-init 01 --group <resource-group> --vm-name <vm-name>` | `--run-vm-init`, target selectors | Runs one init task directly | Isolated bootstrap rerun | Uses Azure run-command against one managed VM. |
| `.\cg.cmd task --run-vm-update 10002 --group <resource-group> --vm-name <vm-name> --windows` | `--run-vm-update`, platform | Runs one update task directly | Isolated guest fix | Uses the SSH task runner against one managed VM; task-signaled immediate restarts still run, Isolated task reruns do not run package installers or their declared post-install tasks. |
| `.\cg.cmd task --save-app-state --vm-update-task=115 --group=<resource-group> --vm-name=<vm-name> -s <subscription-guid>` | `--save-app-state`, `--vm-update-task`, target selectors | Captures one live task-owned app-state payload into the task-local `<task-folder>/app-state/app-state.zip` | Refreshing an operator-owned payload from the active VM | Cleanly skips when no capture coverage exists. |
| `.\cg.cmd task --restore-app-state --vm-update-task=115 --group=<resource-group> --vm-name=<vm-name> -s <subscription-guid>` | `--restore-app-state`, `--vm-update-task`, target selectors | Replays one saved task-owned app-state payload to the active VM | Targeted state restore after reinstall or cleanup | Fails cleanly when the requested zip is missing or invalid, and otherwise verifies the guest replayed content and rolls back from guest-side backup staging on mismatch. |
| `.\cg.cmd task --save-app-state --source=lm --user=.current. --vm-update-task=115 --windows` | `--save-app-state`, `--source=lm`, `--user=.current.` | Captures one local-machine task payload into the same task-local zip path | Refreshing a portable app-state payload from the operator machine | Windows-host-only. |
| `.\cg.cmd task --save-app-state --package=visual-studio-code --package-catalog=builtin --group=<resource-group> --vm-name=<vm-name> --windows` | package id, catalog, target | Captures package app-state from the active VC into that package folder | Refreshing a package app-state payload | Uses `appStateKey` so existing archives remain valid. |
| `.\cg.cmd task --restore-app-state --package=visual-studio-code --package-catalog=builtin --group=<resource-group> --vm-name=<vm-name> --windows` | package id, catalog, target | Replays package app-state to the active VC | Restoring package settings after reinstall | Uses the package folder's app-state zip with shared verification and rollback. |
| `.\cg.cmd task --restore-app-state --target=lm --user=.current. --vm-update-task=115 --windows` | `--restore-app-state`, `--target=lm`, `--user=.current.` | Restores one task-local payload back onto the operator machine | Safe local replay and troubleshooting | Validates `task.json`, writes task-adjacent `backup-app-states/<task-name>/` snapshots plus `restore-journal.json` and `verify-report.json`, and rolls back on verification failure. |

#### `exec`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd exec --group <resource-group> --vm-name <vm-name>` | target selectors | Opens the interactive remote-shell path | Manual guest work | Interactive shell mode is used when no `--command` is provided. |
| `.\cg.cmd exec --command "Get-Date" --group <resource-group> --vm-name <vm-name>` | `--command`, target selectors | Runs one remote command over SSH | One-shot diagnosis or manual admin action | Uses PowerShell on Windows and bash on Linux. |
| `.\cg.cmd exec --file .\tools\scripts\sample-remote.ps1 --group <resource-group> --vm-name <vm-name>` | `--file`, target selectors | Runs one local script file remotely over SSH | Safer multi-line remote diagnosis or admin action | Reads the local file content and sends it through the same one-shot exec path. |
| `.\cg.cmd exec --quiet --command "Get-Date" --group <resource-group> --vm-name <vm-name>` | `--quiet`, `--command`, target selectors | Runs one remote command and prints its result with local action progress | Script-friendly automation | Suppresses remote output chatter while retaining local `Doing:` progress and wait heartbeats. |
| `.\cg.cmd exec -c "uname -a" --group <resource-group> --vm-name <vm-name>` | `-c`, target selectors | Same one-shot remote command path with short syntax | Operator convenience | `-c` and `--command` are equivalent. |

#### `connect`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd connect --ssh --vm-name <vm-name>` | `--ssh`, `--vm-name` | Opens SSH with default targeting | Direct shell access | Only works when the VM is already running. |
| `.\cg.cmd connect --ssh --group <resource-group> --vm-name <vm-name> --user assistant` | `--ssh`, `--group`, `--vm-name`, `--user` | Opens SSH as a selected user | Role-specific shell access | Password entry remains local. |
| `.\cg.cmd connect --ssh --group <resource-group> --vm-name <vm-name> --user manager --test` | `--ssh`, `--test` | Runs a non-interactive SSH handshake check | Release and connection verification | Helpful before opening a real session. |
| `.\cg.cmd connect --rdp --vm-name <vm-name>` | `--rdp`, `--vm-name` | Opens RDP with default targeting | Windows desktop access | Only works when the VM is already running. |
| `.\cg.cmd connect --rdp --group <resource-group> --vm-name <vm-name> --user assistant` | `--rdp`, `--group`, `--vm-name`, `--user` | Opens RDP as a selected user | Assistant desktop access | Uses `cmdkey` before `mstsc.exe`. |
| `.\cg.cmd connect --rdp --group <resource-group> --vm-name <vm-name> --user manager --test` | `--rdp`, `--test` | Runs a non-interactive TCP reachability check | Release and connection verification | Useful before a full interactive desktop session. |

| `cg.cmd connect --powershell --group <resource-group> --vm-name <vm-name> --user manager` | `--powershell`, target selectors, `--user` | Opens a remote PowerShell command prompt over WinRM | Windows guest administration | Type one command per line; enter `exit` to close. Windows init task 06 enables WinRM on TCP 5985. |
| `cg.cmd connect --powershell --command "Get-Service WinRM" --group <resource-group> --vm-name <vm-name>` | `--powershell`, `--command`, target selectors | Runs one PowerShell command through a remote PSSession | One-shot Windows diagnosis or administration | Uses Negotiate authentication and the selected VM user credentials. |
| `cg.cmd connect --powershell --test --group <resource-group> --vm-name <vm-name> --user manager` | `--powershell`, `--test`, target selectors | Checks TCP reachability, opens a WinRM session, and verifies the remote account | Connection verification | Does not mutate Azure resources. |

#### `move`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd move --group=<resource-group> --vm-name=<vm-name> --vm-region=swedencentral -s <subscription-guid>` | `--group`, `--vm-name`, `--vm-region`, `-s` | Performs a health-gated regional move | Planned cutover | Expect a longer-running operation with snapshot copy time. |

#### `resize`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --vm-size=Standard_D4as_v5 --windows` | `--vm-size` | Changes the VM SKU in the same region | Compute sizing changes | Same-region only. |
| `.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=196gb --expand --windows` | `--disk-size`, `--expand` | Performs supported managed OS disk growth | Safe in-place disk growth | Deallocates the VM, updates disk size, and starts it again. |
| `.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=98304mb --expand` | `mb` units | Performs the same expand path with MB input | Operator convenience | The runtime normalizes to Azure-safe GB values. |
| `.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=1tb --expand` | `mb`, `gb`, or `tb` units | Normalizes the OS disk target to 1024 GiB | Operator convenience | OS disk text sizes must resolve to 1–4095 GiB. |
| `.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=64gb --shrink` | `--shrink` | Stops before mutation and explains supported alternatives | Operator guidance only | `--disk-size=... --shrink` is a non-mutating guidance path because Azure does not support shrinking an existing managed OS disk in place; the command prints supported rebuild and migration alternatives instead of risking disk integrity |

#### `set`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd set --group=<resource-group> --vm-name=<vm-name> --hibernation=off -s <subscription-guid>` | `--hibernation` | Changes hibernation state | Feature-state management | Syncs the successful change into the selected VC profile. |
| `.\cg.cmd set --group=<resource-group> --vm-name=<vm-name> --nested-virtualization=off` | `--nested-virtualization` | Saves the Clagnos nested-virtualization request | Repo setting sync | Does not change Azure hardware exposure; `on` requires a running VM and validates guest CPU virtualization extensions |
| `.\cg.cmd set --group=<resource-group> --vm-name=<vm-name> --hibernation=on --nested-virtualization=off` | both flags | Applies both feature controls | Coordinated feature changes | Partial success still updates local state for the successful part. |

#### `delete`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd delete --target=vm --group=<resource-group> --yes` | `--target=vm`, `--yes` | Deletes only the VM scope | Controlled cleanup | Destructive by design. |
| `.\cg.cmd delete --target=group --group=<resource-group> --yes -s <subscription-guid>` | `--target=group`, `--yes`, `-s` | Deletes the full managed group | Full teardown | Best used when the target is explicitly safe to purge. |

#### `help`

| Usage pattern | Key parameters | What it does | When to use it | Important notes |
| --- | --- | --- | --- | --- |
| `.\cg.cmd -h` | `-h` | Prints the quick overview | Fast discovery | Same as `--help`. |
| `.\cg.cmd help` | `help` | Prints the detailed command catalog | Full command reference | Good onboarding path for new operators. |
| `.\cg.cmd help move` | one command topic | Prints one command's details | Deep dive into one operation | Best companion to the command matrix. |

## Practical And Extensive Usage Scenarios

### Create A Fresh Managed VM
```powershell
.\cg.cmd create --auto
.\cg.cmd create --step=network --linux
.\cg.cmd create --step-from=vm-deploy --step-to=vm-summary --perf
.\cg.cmd delete --target=group --group=<resource-group> --yes
.\cg.cmd create --auto
```

Practical outcomes:
- the default path creates one fresh managed resource group and one fresh VM target
- interactive mode proposes the next globally unique managed `gX` group id and globally unique managed `nX` resource ids
- auto mode succeeds when CLI overrides plus `DEFAULT_*` values in `clagnos.env` resolve platform, VM name, Azure region, and VM size
- when a destructive rebuild is intentional, run `delete` first and then run `create`
- the same step model works in interactive and auto mode

### Update An Existing Managed VM
```powershell
.\cg.cmd update --auto
.\cg.cmd update --step=vm-update --auto --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd initialize --auto --group=<resource-group> --vm-name=<vm-name>
```

Practical outcomes:
- the command fails fast if the managed resource group or VM does not exist, and it points the operator to `create`
- auto mode requires an explicit platform plus `--group` and `--vm-name`
- `update` runs enabled vm-update `vm-update` maintenance tasks against the existing VM
- use `initialize` for `vm-init`; use `do --vm-action=reapply|redeploy` for explicit Azure-side repair

### Inspect Managed Resource Groups And VM State
```powershell
.\cg.cmd list --type=group,vm
.\cg.cmd configure
.\cg.cmd show --group=<resource-group>
.\cg.cmd do --vm-action=status --vm-name=<vm-name>
```

Practical outcomes:
- `list` gives a read-only managed inventory view across groups and resource types
- `configure` gives a safe interactive frontend for every supported global `clagnos.env` key, with picker-backed multi-option fields and a next-create preview before save
- `show` gives an inventory snapshot while password-bearing VC profile values are redacted, and adds target-derived configuration when one managed VM is in scope
- `do --vm-action=status` is the quickest preflight check before a mutating change

### Run One Task Or Open A Remote Shell
```powershell
.\cg.cmd task --list --vm-update --windows
.\cg.cmd task --run-vm-update 10099 --group <resource-group> --vm-name <vm-name> --windows
.\cg.cmd task --run-vm-init 01 --group <resource-group> --vm-name <vm-name>
.\cg.cmd exec --group <resource-group> --vm-name <vm-name>
.\cg.cmd connect --ssh --group <resource-group> --vm-name <vm-name> --user manager
.\cg.cmd connect --rdp --group <resource-group> --vm-name <vm-name> --user assistant
.\cg.cmd connect --powershell --group <resource-group> --vm-name <vm-name> --user manager
.\cg.cmd connect --powershell --command "Get-Service WinRM" --group <resource-group> --vm-name <vm-name>
```

Practical outcomes:
- support and development teams can rerun only the failing task instead of replaying the whole deployment
- `task` exposes the real discovered inventory, including builtin and custom tasks
- `connect --ssh`, `connect --rdp`, and Windows-only `connect --powershell` remain direct operator commands; `connect --powershell --command <text>` runs one remote command, and `--test` verifies WinRM authentication/readiness

### Resize Compute Or OS Disk In Place
```powershell
.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --vm-size=Standard_D4as_v5 --windows
.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=196gb --expand --windows
.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=98304mb --expand
.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=1tb --expand
.\cg.cmd resize --group=<resource-group> --vm-name=<vm-name> --disk-size=64gb --shrink
```

Practical outcomes:
- `--vm-size` changes compute SKU in the same region
- `--expand` performs the supported managed OS disk growth path with explicit before/after logging
- `--shrink` explains why Azure OS disk shrink is unsupported and lists safer rebuild alternatives

### Move Regions And Clean Up Safely
```powershell
.\cg.cmd move --group=<resource-group> --vm-name=<vm-name> --vm-region=swedencentral
```

### Delete Only The Scope You Intend
```powershell
.\cg.cmd delete --target=vm --group=<resource-group> --yes
.\cg.cmd delete --target=group --group=<resource-group> --yes
```

### Inspect And Control Power State
```powershell
.\cg.cmd do --vm-action=status --vm-name=<vm-name>
.\cg.cmd do --vm-action=start --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd do --vm-action=reapply --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd do --vm-action=redeploy --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd do --vm-action=stop --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd do --vm-action=hibernate-stop --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd do --vm-action=hibernate-deallocate --group=<resource-group> --vm-name=<vm-name>
```

### Connect To The VM
```powershell
.\cg.cmd do --vm-action=start --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd connect --ssh --group=<resource-group> --vm-name=<vm-name>
.\cg.cmd connect --rdp --group=<resource-group> --vm-name=<vm-name> --user=assistant
```

## Command Guide

### Global Options
- `--version`: print the current documented clagnos release and exit without loading the normal command workflow
- `--auto`: unattended mode for `create`, `initialize`, `update`, and `delete`
- `--perf`: print timing metrics
- `--windows`, `--linux`: explicit platform selection or platform expectation
- `-s`, `--subscription-id=<subscription-guid>`: target Azure subscription for every Azure-touching command; successful CLI usage also writes `SELECTED_AZURE_SUBSCRIPTION_ID` into `clagnos.env`.
- `-h`, `--help`: print quick or command-specific help
- Canonical target selectors are `--group` / `-g`, `--vm-name` / `-v`, and `--subscription-id` / `-s`; value-taking options accept both `--option=value` and `--option value`, plus short-form `-x=value` and `-x value` when a short alias exists.

Azure subscription selection precedence is: CLI `--subscription-id` / `-s` -> `clagnos.env` `SELECTED_AZURE_SUBSCRIPTION_ID` -> active Azure CLI subscription.

### `configure`
Purpose: review, edit, validate, preview, and save the global `clagnos.env` contract through one interactive frontend.

Behavior notes:
- interactive-only global `clagnos.env` editor
- shows every supported global key in section order derived from `clagnos.env.example`
- uses a picker for every finite or discoverable multi-option field
- stages edits in memory until final confirmation, then writes only supported global keys once
- renders a next-create preview with effective platform inputs plus next managed resource names when Azure validation is available
- can open without `az login`, but Azure-backed fields stay read-only until Azure validation is available
- never edits or syncs an individual VM profile; VM lifecycle commands read and persist those values in `<vm-name>.env`
- accepts blank create defaults; the wizard collects missing target-specific values and credentials when a VC is created

### `create`
Purpose: build one fresh managed resource group, its initial network, and one VM.

Behavior notes:
- `create` stops after VM deployment and the read-only summary. Run `initialize` for vm-init tasks and use `package` for catalogued software.
- `create` never reuses an existing managed resource group or existing managed resource names, and `update` never falls through to an implicit fresh-create path.
- Auto `create` succeeds when CLI overrides plus `DEFAULT_*` global values resolve platform, VM name, Azure region, and VM size. The per-VC profile then stores the resolved values and credentials.
- The infra flow keeps deterministic resource naming, validation, and review checkpoints before group and VM deployment.
- if `--windows` or `--linux` is omitted, interactive mode asks for the VM OS type first and then scopes size, disk, and image defaults to that selection
- Interactive `create` reviews only the resource group and VM deployment steps.
- `configure` and `vm-summary` stay visible in `create` and `update` flows, even when partial step selection skips interior stages.
- Use `initialize` and `update` for guest stages instead of passing guest stages to create.

### `initialize`
Purpose: run enabled vm-init tasks on one existing managed VM.

Behavior notes:
- This command never creates or updates Azure resources.
- It uses the shared platform task catalog, dependency ordering, timeout, reboot, and post-task app-state behavior.
- It requires a managed resource group and VM, supplied directly or resolved from `ACTIVE_VM_NAME` and that VC's required profile.

### `update`
Purpose: run enabled vm-update maintenance tasks on one existing managed VM.

Behavior notes:
- `update` requires an existing managed resource group and VM. It does not create or redeploy the VM.
- Auto `update` resolves its target from CLI overrides first, then `ACTIVE_VM_NAME` and that VM's `SELECTED_RESOURCE_GROUP` in `<vm-name>.env`; single-VM auto-resolution remains available for an explicitly selected group.
- Packages are managed separately from task stages through their package catalogs.
- Use `do` for explicit redeploy/repair and lifecycle actions.
- Best fit for day-two guest setting and service maintenance.

### `package`
Purpose: manage the separate builtin and custom package catalogs, and install or remove packages on one managed VC.

Behavior notes:
- `vm-packages/builtin/<platform>/<package-id>/` and `vm-packages/custom/<platform>/<package-id>/` are physically separate catalogs. Each package folder contains `package.json` and its platform installer script.
- Manage Programs first offers `Builtin package catalog` and `Custom package catalog`. Rows are labeled `[builtin]` or `[custom]`; disabled packages display `(disabled)`.
- The selected VC menu offers `p: setup all program packages` and `m: manage program packages`. Setup-all shows a review plan, installs enabled absent packages and repairs detected Clagnos-managed startup drift in dependency order, then reports independent failures. Docker Desktop startup verification accepts the manager/assistant Run entry or the user's verified StartupFolder shortcut produced by the update startup profile, avoiding an unnecessary vendor reinstall.
- Select a package by number, then choose `e: enable`, `d: disable`, `u: uninstall`, `i: install`, `r: repair`, `v: update`, `x: reinstall`, or `s: status`. Packages with app-state policies also offer `a: manage package app-state`.
- `e` and `d` update only that catalog's `tasks.toml` boolean after typed confirmation. `package.json` remains package metadata. The change affects future operations for VCs using this repository; it does not change software already installed on a VC.
- Status and uninstall remain available while disabled. Install/repair/update/reinstall is blocked until the package is enabled. `install` installs an absent package and is a no-op when present; `repair` pins that version and refuses unsafe strategies; `update` remains the vendor-version upgrade path; `reinstall` performs a confirmed uninstall followed by install. `operationTimeoutSeconds` provides finite per-action budgets. WinRM package runs stream guest output and sample CPU, memory, network, disk I/O, and free space while enforcing bounded deadlines.
- Package manifests supply a display name, category, installed-state detector, explicit uninstall action, and optional installer assets, per-operation timeout budgets, app-state policy, dependencies, and post-install tasks. Windows builtin manifests declare separate `status.ps1`, `update.ps1`, `uninstall.ps1`, and `repair.ps1` scripts with validated strategies; custom catalogs can use the shared lifecycle fallback.
- Installers run synchronously on the selected VC; uninstalls require confirmation and are verified against the status detector. Setup-all mutates only after `a: apply`; `c: close` leaves the VM unchanged.

### `component`
Purpose: manage the Azure resources that make up a Clagnos virtual computer.

Behavior notes:
- CRUD menus cover resource groups, VMs, managed disks, VNets, subnets, NICs, public IPs, NSGs, and NSG rules.
- Property forms use per-type validation for compute size/features, disk size/tier, network addresses, IP configuration, rules, associations, and tags.
- Deletion prints the linked-resource plan, removes dependents before dependencies, and verifies deletion. Azure service-specific purge or name retention can still constrain immediate reuse.

### `list`
Purpose: print read-only managed inventory sections for clagnos-tagged resource groups and resources.

Behavior notes:
- supports `--type` and `--group` for managed inventory output
- `list` gives a read-only managed inventory view across groups and resource types
- `list --type group` includes the active marker, Azure location, and provisioning state for each managed resource group
- Azure-read-only output; `--subscription-id` / `-s` only changes the subscription context and persists `SELECTED_AZURE_SUBSCRIPTION_ID` when it comes from the CLI

### `show`
Purpose: print a full system and configuration dump for app resource groups and VMs.

Behavior notes:
- good for support handoff, release verification, and environment auditing
- password-bearing VC profile values are redacted
- `--export-json <path>` writes a machine-readable report with sensitive config values redacted; existing files require `--overwrite`
- nested virtualization request (`VM_ENABLE_NESTED_VIRTUALIZATION`), any Azure-reported nested virtualization setting, and guest CPU-extension availability are shown separately; a request is not proof that Azure exposed virtualization extensions or that Hyper-V is installed inside the guest
- when the VM is running, guest availability is determined by guest validation evidence. Windows validation requires VMX, firmware virtualization, and SLAT extensions to be exposed to the guest. `HyperVisorPresent` or an enabled `VirtualMachinePlatform` feature alone does not prove nested virtualization; missing probe fields remain unknown instead of being reported as disabled

### `do`
Purpose: apply one VM lifecycle action or print the current VM lifecycle state.

Behavior notes:
- use `status` before mutating changes
- `reapply` and `redeploy` are available for Azure-side repair on an existing VM
- `hibernate-stop` and `hibernate-deallocate` remain explicit, separate operator paths

### `task`
Purpose: list discovered init/update tasks in runtime order, run one task in isolation, or save/restore one task-owned app-state payload.

Behavior notes:
- shows builtin and custom task folders together
- `--run-vm-init` routes one init task through Azure run-command and relays the full guest transcript immediately after that task finishes
- `--run-vm-update` routes one update task through the SSH task runner and streams guest stdout/stderr live over SSH
- `--history` shows recent isolated/package outcomes and vm-init/vm-update stage summaries recorded on the operator machine without Azure access
- history stores task names, target, outcome counts, duration, and deferred app-state task names; it does not save guest output or credentials
- history is stored under the operator's local application state directory in `clagnos/task-runs.jsonl` and is trimmed to roughly 2,000 rows after the file grows beyond 5 MiB
- `--save-app-state` defaults to `--source=vm`; `--restore-app-state` defaults to `--target=vm`; both default to `--user=.all.`
- `--user` accepts `.all.`, `.current.`, one explicit user, or a comma-separated user list such as `--user=operator,assistant`
- managed VM app-state reads or writes the task-local payload at `<task-folder>/app-state/app-state.zip`
- VM restore uses guest-side temporary backup staging, verifies restored files and registry after replay, and rolls back automatically if verification fails
- local-machine save/restore is Windows-host-only and reuses the same task-local payload path
- init and update restore flows both reuse the same shared per-task app-state post-process over SSH; init defers replay until SSH is reachable and update replays immediately over SSH
- task-owned app-state payloads target only the managed `manager` and `assistant` OS profiles on VM paths; missing zips skip cleanly, and broad generated caches, installers, models, and telemetry payloads are pruned from the managed capture contract
- local restore validates the current `task.json` allow-list, writes task-adjacent `backup-app-states/<task-name>/` snapshots plus `restore-journal.json` and `verify-report.json` first, verifies the replayed content, and rolls back the current target user if replay or verification fails
- useful before isolated reruns or when checking timeout and enable-state behavior

### `exec`
Purpose: open the direct remote shell path or run one one-shot remote command.

Behavior notes:
- ideal for isolated diagnosis or manual guest work
- resolves only the selected VM plus SSH context
- `--command` / `-c` runs one remote PowerShell or bash snippet without opening the interactive shell
- `--file` / `-f` reads one local script file and runs that content through the same remote exec path
- `--quiet` / `-q` is valid only with `--command` / `-c` / `--file`; it suppresses remote output chatter but keeps local `Doing:` progress and wait heartbeats visible
- Azure CLI, VM lifecycle, guest task, package, and connection steps print a safe `Doing: <action>` message before work starts. Blocking Azure CLI and HTTP requests emit elapsed-time heartbeats every 30 seconds; progress labels omit secrets.

### `connect`
Purpose: launch the local Windows OpenSSH client or Remote Desktop client, open a Windows PowerShell remoting session, or run connection tests for a managed VM.

Behavior notes:
- only works when the VM is already running
- requires exactly one transport flag: `--ssh`, `--rdp`, or `--powershell`
- `--test` performs a non-interactive handshake or reachability check instead of opening an external client/session
- `connect --rdp` is only valid for Windows VMs
- `connect --powershell` is Windows-only, uses WinRM Negotiate over TCP 5985, and opens a remote command prompt backed by one persistent PSSession; type `exit` to close it
- `connect --powershell --command <text>` runs one remote command, while `connect --powershell --test` checks TCP reachability, authentication, and the selected account
- Windows init task `06-configure-powershell-remoting` enables WinRM, keeps Basic authentication and unencrypted traffic disabled, and grants the manager and assistant accounts remote-management access; the default `TCP_PORTS` includes 5985, which must stay listed for WinRM access when customizing that setting

### `move`
Purpose: move a managed VM to another Azure region with a health-gated cutover.

Observed reference timing:
- live reference for `austriaeast -> swedencentral`, `Standard_D4as_v5`, `127 GB` OS disk: about `25-30 minutes`
- the longest phase was cross-region snapshot copy at about `17-19 minutes`

### `resize`
Purpose: change the VM size or expand the managed OS disk in-place within the current region.

Behavior notes:
- same-region only
- `--vm-size` changes compute SKU
- `--disk-size` accepts positive `MB`, `GB`, or `TB` text values that normalize to an OS disk size from 1 through 4095 GiB
- `--disk-size=... --expand` performs the supported managed OS disk growth path
- `--disk-size=... --shrink` is a non-mutating guidance path because Azure does not support shrinking an existing managed OS disk in place; the command prints supported rebuild and migration alternatives instead of risking disk integrity
- both mutating resize paths print before/after lifecycle snapshots and verify the resulting VM SKU or OS disk size with Azure readbacks before saving the requested value into the selected VC profile
- if Azure's readback differs from the requested target, the command reports the actual state, does not save the target config value, and does not claim an automatic rollback; it starts the VM before performing the final readback

### `set`
Purpose: apply hibernation and validate or store nested-virtualization settings.

Behavior notes:
- Hibernation is changed through Azure.
- The nested-virtualization option stores Clagnos intent in the selected VC profile; Azure single-VM APIs do not expose a separate nested-virtualization toggle in this workflow.
- Turning nested virtualization on requires a running VM and checks whether all required CPU virtualization extensions are visible to the guest. This check does not install or configure Hyper-V inside the guest.
- Successful hibernation changes and validated nested-virtualization requests are synchronized back into the selected VC profile.

### `delete`
Purpose: delete a selected scope from a managed resource group.

Behavior notes:
- destructive by design
- requires explicit target selection
- `--yes` is the non-interactive confirmation bypass

### `help`
Purpose: print the quick overview or one-command help.

Behavior notes:
- use `.\cg.cmd -h` or `.\cg.cmd --help` for the overview
- use `.\cg.cmd help <command>` for one command topic

## Task Authoring And Execution

### Task Folder Ownership
Every task is a portable folder under `vm-init/<platform>/{builtin,custom}/` or `vm-update/<platform>/{builtin,custom}/`. The folder name defines the task identity, the same-named script defines the executable body, `tasks.toml` defines whether the task is enabled, and `task.json` defines ordering, timeout, assets, dependencies, and app-state capture coverage. Runtime code must not rewrite either catalog implicitly.

### Task Naming Rules
- `<task-number>-verb-noun-target/`
- task-number bands:
  - `01-99` = `initial`
  - `101-999` = `normal`
  - `10001-10099` = `final`
- 2-5 English words in kebab-case
- each task folder contains one same-named `.ps1` or `.sh` script plus `task.json`

### Timeouts, Priority, And Availability
- each `builtin` and `custom` task catalog has a `tasks.toml` file with one `[tasks]` table; every task folder id appears exactly once with a boolean availability value
- each task folder uses `task.json` for `priority`, `timeout`, optional `assets`, optional `appState`, and optional dependencies; it must not define `enabled`
- The selected VC menu offers `p: setup all program packages` and `m: manage program packages`. The package screen supports `e: enable`, `d: disable`, `u: uninstall`, `i: install`, `r: repair`, `v: update`, `x: reinstall`, and `s: status`. Status and uninstall remain available while disabled; install/repair/update/reinstall is blocked until enabled.
- Task and package enable/disable changes only the matching boolean in that catalog's `tasks.toml`, after typing `ENABLE` or `DISABLE`. Folders stay in their `builtin` or `custom` catalog. Availability changes apply to future runs and do not uninstall a package already installed on a VC.
- task asset paths are resolved relative to the owning task folder
- missing task folders are treated as absent, unlisted task folders warn and skip, and package catalogs require their `tasks.toml` ids to match package folders
- missing task folders behave as if the task never existed; malformed task folders warn and skip; duplicate task names or duplicate effective priorities still fail fast
- missing `priority`: default to the filename task number when available, otherwise `1000`
- missing `timeout`: default to `180`
- `initial`, `normal`, and `final` task folders from both `builtin` and `custom` catalogs are ordered by their effective priority and dependencies

### Direct Task Execution With `task`
Direct `task --run-vm-init` and `task --run-vm-update` are the main diagnosis path when one task needs to be rerun without replaying the entire orchestration chain.

Current task template replacement uses the public selected-value placeholders: `__SELECTED_VM_NAME__`, `__SELECTED_AZURE_REGION__`, `__SELECTED_RESOURCE_GROUP__`, `__SELECTED_COMPANY_NAME__`, `__SELECTED_COMPANY_WEB_ADDRESS__`, `__SELECTED_COMPANY_EMAIL_ADDRESS__`, `__SELECTED_EMPLOYEE_EMAIL_ADDRESS__`, and `__SELECTED_EMPLOYEE_FULL_NAME__`.

Task-scoped app-state capture and replay use the portable task folder contract. Package app-state uses the owning `<package-folder>/app-state/app-state.zip` and policy in `package.json`; `appStateKey` preserves the identity of previously captured archives. Package snapshots are settings-first, exclude sign-in and machine state, and resolve supported `%CLAGNOS_*%` placeholders against the target profile and VM immediately before replay. Sanitized package archives are versioned in Git with their package definitions; validate every archive with `tests/package-app-state-contract-check.ps1` before committing it. Task app-state plugins remain git-ignored. Local-machine restore snapshots are written under the owning task or package catalog's `backup-app-states/` root and include both `restore-journal.json` and `verify-report.json`.

## Configuration Guide

### Runtime Precedence
Runtime precedence is:
1. CLI override
2. selected VC's `<vm-name>.env` value
3. global `clagnos.env` default
4. hard-coded default

This matters because:
- command-line overrides are the safest way to test one change without rewriting local defaults
- `clagnos.env.example` and `vc.env.example` are the committed global and per-VC contracts
- `clagnos.env` and every `<vm-name>.env` remain local and untracked

### Global And VC Environment Files
`clagnos.env` contains app-wide values: `ACTIVE_VM_NAME`, the Azure subscription selector, operator identity and shortcut overrides, naming templates, timeouts, task paths, and non-secret `DEFAULT_*` values used to seed newly created VCs. `configure` edits this global file only.

Each VC has a `<vm-name>.env` file containing its `SELECTED_VM_NAME`, `SELECTED_RESOURCE_GROUP`, generated VNet/subnet/NSG/rule/public-IP/NIC/disk names, operating system, Azure region, VM image/size/disk, storage and security settings, hibernation/nested-virtualization intent, login users/passwords, connection ports, allowed ports, and package transport. The create wizard creates that file; target commands verify its name matches the profile identity. Passwords never go into `clagnos.env`.

`SELECTED_AZURE_SUBSCRIPTION_ID`, company/employee identity keys, `VM_PRICE_COUNT_HOURS`, `AZURE_COMMAND_TIMEOUT_SECONDS`, and `PYSSH_CLIENT_PATH` are global. `PYSSH_CLIENT_PATH` defaults to `tools/pyssh/ssh_client.py`. `DEFAULT_*` keys seed create only; once a VC exists, its profile wins over global defaults.

### Naming And Platform Defaults
- `DEFAULT_WIN_*` and `DEFAULT_LIN_*` keys in `clagnos.env` seed image, size, and disk settings for a new Windows or Linux VC.
- Existing target values use `WIN_*` or `LIN_*` keys in that VC's profile.
- The committed managed-resource templates in `clagnos.env.example` use `{SELECTED_VM_NAME}` as the naming placeholder, for example `rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}`.
- Managed resource group ids use a global `gX` suffix that increments across all managed groups, regardless of region.
- Managed resource ids use a global `nX` suffix that increments across all generated managed resources and is never reused by another managed resource of any type.

### Connection And Task Settings
- Configure SSH and RDP ports through the committed runtime contract instead of editing tasks blindly; Windows PowerShell remoting uses TCP 5985.
- Keep long-running task timeouts in `task.json`, not hidden in repo-wide runtime logic.
- Use `--perf` when you want timing evidence for long-running flows.

### Global Versus Task-Local Configuration
- Keep global app customization, Azure subscription selection, operator identity, and non-secret create defaults in `clagnos.env`.
- Keep VM credentials and every target-specific setting in that VC's `<vm-name>.env` profile.
- Task-only constants should stay in the owning task script, in a clearly labeled config block at the top of the owning `vm-init` or `vm-update` script.

## Developer Benefits

### Why Developers Move Faster
- One orchestrator means less context switching between separate scripts for provisioning, update, connection, and repair.
- The same command surface covers Windows and Linux, so platform differences stay narrow and explicit.
- `create` now stays dedicated to one fresh managed resource group plus one fresh managed VM; use `delete` and then `create` when a destructive rebuild is intentional.
- `initialize` runs initial guest bootstrap on an existing managed VM; `update` runs vm-update maintenance tasks without recreating or redeploying Azure resources.
- `resize --disk-size=... --expand` gives a safe in-place managed OS disk growth path, while `resize --disk-size=... --shrink` stops early and explains the supported alternatives instead of risking data loss.
- Direct `task` and `exec` flows let maintainers inspect and rerun exactly the step or task that matters.

### Daily Maintainer Flow
1. Confirm the target with `list`, `show`, `configure`, and `do --vm-action=status`.
2. Use `create` for first deploys and fresh environments; when a full destructive rebuild is intentional, run `delete` first and then run `create`.
3. Use `initialize` for initial guest setup, `update` for ongoing vm-update maintenance, and `do` for explicit Azure lifecycle or repair actions.
4. Use `task` and `exec` to isolate one failing init or update task instead of replaying the whole chain.
5. Use `move`, `resize`, `set`, and `delete` only after the inventory and current state are explicit.

### Versioned Release Source Package
After committing the release docs with the version's cumulative commit count, create a versioned source archive and SHA256 sidecar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1
```

The packager requires aligned `CHANGELOG.md` and `release-notes.md` versions, a clean git worktree, and no tracked runtime `*.env` files. It archives the committed tree under `dist/clagnos-<version>/`, adds `BUILD-MANIFEST.json`, and writes `dist/clagnos-<version>.zip.sha256`. The default output directory is git-ignored. Use `-OutputDirectory <path>` to choose another destination or `-Overwrite` to replace an existing artifact deliberately.

## Core Mental Model

### One Runtime, Two Platforms
`clagnos.ps1` is the shared orchestration runtime. `cg.cmd` opens `scripts/clagnos-cli.ps1` without arguments and forwards direct command arguments through the same frontend. Windows and Linux share one operator model; guest differences stay in platform task folders.

### Top-Level Orchestration Steps
`clagnos` uses these top-level steps:
1. `configure`
2. `group`
3. `network`
4. `vm-deploy`
5. `vm-init`
6. `vm-update`
7. `vm-summary`

`create` runs the infrastructure steps through `vm-deploy`; `initialize` runs `vm-init`; `update` runs vm-update `vm-update` tasks. Package operations are invoked through `package`.

### Init Tasks Versus Update Tasks
- `vm-init` is Azure Run Command driven and is used for early guest bootstrap, one task at a time.
- `vm-update` is pyssh driven and is used for richer task-by-task update flows after the VM is reachable.
- `vm-init` relays the full guest transcript back to the local clagnos console as soon as each task completes, while `vm-update` streams guest stdout/stderr live over SSH while the task is still running.
- Both stages use portable task folders, `tasks.toml` for availability, and `task.json` for ordering, timeout, and execution metadata. Both invoke the same per-task app-state restore helper when a matching task-local plugin zip exists.
- `builtin` and `custom` tasks share the `initial`, `normal`, and `final` priority bands and are ordered by effective priority and dependencies.
- Every task timeout is normalized to a minimum of `30` seconds and then rounded up in `15`-second slots.
- Reboot-signaling tasks restart the VM immediately, wait for the required transport recovery, and then resume from the next task. The `update` stage retains its Windows final restart after the vm-update maintenance stage; isolated `task --run-vm-update` reruns skip that workflow-only final restart.
- Windows Store package manifests declare the public desktop shortcut refresh as a post-install task.
- `vm-summary` begins with a read-only guest readback block and then continues with the normal summary and connection details.

### Interactive Versus Auto Mode
- Interactive mode is the default and prompts when required values are missing.
- Interactive mode prompts for Azure subscription first when `--subscription-id` is omitted for `create`, `initialize`, and `update`.
- Interactive `create` reviews the resource group and VM deployment steps; `initialize` and `update` have their own task-stage reviews.
- `--auto` supports unattended `create`, `initialize`, `update`, and `delete` operations.
- Auto `create` provisions infrastructure only and resolves platform, VM name, region, and size from CLI or global `DEFAULT_*` values; target-specific values are saved in the VC profile.
- Auto `update` resolves its managed target from CLI overrides first, then `ACTIVE_VM_NAME` and the selected VC profile.
- Auto mode prints the same review context, but it continues without waiting for checkpoint confirmation.
- The TUI keeps every public command and registered component/package action reachable from a numbered or lettered submenu.
- Legacy `managed-by=az-vm` groups remain readable and migrate to `managed-by=clagnos` after confirmation on the first inventory.
- Operator commands such as `show`, `do`, `connect`, and `exec` stay direct and do not require `--auto`.

### Naming And Managed Resource Rules
- `SELECTED_VM_NAME` is the persisted naming seed.
- Managed names are template-driven and deterministic.
- Managed resource group ids use a global `gX` suffix that increments across all managed groups, regardless of region.
- Managed resource ids use a global `nX` suffix that increments across all generated managed resources and is never reused by another managed resource of any type.
- Runtime code validates names before Azure mutation.

## Architecture From Zero To Hero

### Entrypoints And Runtime Modules
- `cg.cmd` launches the interactive frontend; with command arguments it dispatches through the same PowerShell menu/runtime script.
- `scripts/clagnos-cli.ps1` owns the menu hierarchy and delegates operations to the shared command handlers.
- `clagnos.ps1` loads `modules/clagnos-runtime-manifest.ps1`, then dot-sources the ordered runtime leaf files before dispatching the direct command surface.
- There is no transitional root-loader layer for `core`, `config`, `commands`, `ui`, or `tasks`; the launcher resolves the refactored module tree directly.
- `modules/core/` holds shared contracts, CLI helpers, system/runtime utilities, task discovery, and host mirroring logic.
- `modules/config/` isolates dotenv, naming-template, region-code, and related config helpers from command and UI code.
- `modules/commands/` owns the public command surface plus shared create/update pipeline helpers.
- `modules/ui/` is restricted to operator interaction concerns such as prompts, selection flows, report rendering, and connection-facing helpers.
- `modules/tasks/` is split into Azure Run Command and persistent SSH internals so guest transport logic stays reusable and explicit.

### Configuration Resolution
Runtime precedence is:
1. CLI override
2. selected VC's `<vm-name>.env` value
3. global `clagnos.env` default
4. hard-coded default

This matters because:
- command-line overrides are the safest way to test one change without rewriting local defaults
- `clagnos.env.example` and `vc.env.example` are the committed global and per-VC contracts
- `clagnos.env` and every `<vm-name>.env` remain local and untracked

### Task Folder Model
Each task directory is self-contained. The folder holds one same-named script, one `task.json`, optional helper assets, and an optional git-ignored `app-state/` directory. `tasks.toml` owns catalog membership and availability; discovery does not rewrite it or `task.json`. A missing portable task folder is treated as absent rather than as a failure. Package installer folders are separate from task stages and use `package.json` plus `install.ps1` or `install.sh`.

### Windows And Linux Execution Model
- Windows and Linux share the same top-level orchestration model.
- Guest task language, package model, access model, and platform-specific tooling differ only where they must.
- Help output, docs, and runtime wording try to stay parallel across both platforms.

### End-To-End Create And Update Flow
- `create` creates one fresh managed group, network, and VM; `initialize` runs vm-init; `update` runs vm-update maintenance tasks on an existing managed VM.
- `package` manages catalogued package status/install/update/uninstall. `component` provides CRUD for the Azure resources Clagnos owns.
- `update` requires one existing managed group and VM and never falls through to implicit fresh-create behavior.
- `configure` edits only supported global `clagnos.env` values; VC-specific settings remain in their `<vm-name>.env` profile, and neither path syncs from live Azure state.
- `list` is the managed inventory command: it must stay Azure-read-only, must not mutate Azure resources, and must expose managed resource listings through `--type` plus optional exact `--group` filtering.
- Azure component deletion displays dependent resources, removes them in dependency order, verifies absence, and uses provider purge only when supported; immediate name reuse remains subject to Azure service rules.

### Safety Model And Failure Handling
- Validate before mutating Azure resources.
- Prefer fast, filtered Azure checks over broad slow listings.
- If Azure does not support a requested operation safely, fail before mutation with the explicit platform reason and list the supported alternatives.
- Avoid retry storms; retry behavior should stay explicit and intentionally bounded.

### Documentation, History, And Release Discipline
- `README.md` is the operator and contributor guide.
- `CHANGELOG.md` and `release-notes.md` are updated in the same final change set as shipped behavior or contract changes.
- `docs/prompt-history.md` keeps the English-normalized prompt ledger.
- `.github/workflows/quality-gate.yml` is the non-live GitHub Actions quality gate workflow.

## Troubleshooting Guide

### Validation Failures
- Check region, image, and SKU first.
- Confirm the naming seed and resource templates.
- Prefer fixing config and rerunning the isolated failing command instead of restarting from zero immediately.

### Task Failures
- Rerun the failing task with `task --run-vm-init` or `task --run-vm-update`.
- Check task timeouts in `task.json` and task/package availability in the corresponding `tasks.toml`.
- Vm-init and vm-update app-state replay are post-task and plug-in based. If `<task-folder>/app-state/app-state.zip` is absent, the task logs a skip and continues; if it exists, the shared SSH post-process deploys it without requiring a dedicated restore task, and vm-init defers replay until SSH is ready.
- Managed app-state save and restore target only the `manager` and `assistant` OS profiles. Large generated payloads such as installers, models, telemetry trees, and low-value caches are intentionally pruned so the zips stay operator-owned and reusable instead of drifting into machine-image snapshots.
- Local-machine app-state restore validates the current `task.json` allow-list and writes task-adjacent `backup-app-states/<task-name>/` snapshots plus `restore-journal.json` and `verify-report.json` before replaying onto the operator machine.
- Windows public desktop shortcut validation names the exact missing `clagnos.env` keys, for example `SELECTED_COMPANY_NAME is required for the Windows business public desktop shortcut flow.` and `SELECTED_EMPLOYEE_EMAIL_ADDRESS is required for the Windows public desktop shortcut flow.`
- Use `VM_TASK_OUTCOME_MODE=strict` when you want the stage to stop at the first failure.

### Connection Failures
- Check `do --vm-action=status`.
- Confirm the VM is running before `connect --ssh`, `connect --rdp`, or `connect --powershell`.
- Verify guest firewall, NSG exposure, and configured ports together.
- For Windows PowerShell remoting, run init task 06, verify TCP 5985, and add the exact host to local WSMan TrustedHosts only when the endpoint is an IP or non-domain host.
- If Azure keeps the VM in provisioning state `Updating`, the connection and direct-task runtime now performs one bounded `az vm redeploy` repair attempt before it gives up.

### Move And Resize Expectations
- `move` is a deliberate cutover operation with downtime and cross-region copy time.
- `resize` is same-region only and is much smaller in scope than `move`.
- managed OS disk shrink is intentionally blocked as an unsupported Azure scenario; use the printed rebuild or migration alternatives instead.
- both commands validate before mutation and return friendly hints on invalid state or configuration.

## Developer Workflow

### Branching And Local Hooks
- Use a working branch for changes.
- Enable local hooks with:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\enable-git-hooks.ps1
```
- Disable them with:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\disable-git-hooks.ps1
```
- The local hook path blocks obvious contact-style values, concrete identity leaks, and non-placeholder sensitive config drift before commits and pushes are shared.

### Quality Gates
Run these locally:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\code-quality-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\sensitive-content-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\documentation-contract-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\powershell-compatibility-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\clagnos-smoke-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\tui\run-tui-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\package-app-state-contract-check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\bash-syntax-check.ps1
```

`code-quality-check.ps1` and the local commit hook keep the current tree and the current commit message clean. Run `.\tests\sensitive-content-check.ps1` directly when you also want the full reachable-history commit-message audit.

The TUI suite has 153 detailed menu/action scenarios plus a process-level test that launches the real `cg.cmd` from an isolated fixture copy and checks captured console output. It uses a fake Azure CLI that rejects mutations and a stubbed command dispatcher; the PowerShell compatibility matrix runs it under Windows PowerShell 5.1 and PowerShell 7+.

GitHub Actions runs the non-destructive `.github/workflows/quality-gate.yml` workflow on pull requests, pushes to `main`, and manual dispatch. It covers static audit, an explicit documentation-contract check, PowerShell and TUI compatibility, Linux shell syntax, package app-state archive contracts, workflow linting, and the non-live smoke-contract suite. The live Azure E2E script is never run in CI.
For a release push, the job is not finished until the pushed `main` SHA completes this workflow green.

### Live Release Acceptance
Before calling the repo or the active profile release-ready for a live publish, run one end-to-end live acceptance cycle against the current active VC profile and global subscription:
- if the target group is safe to purge, prefer a full recreate by running `clagnos delete --target=group --group=<resource-group> --yes` before the live create
- run a clean `clagnos create --auto --perf` once the active VC profile and global create defaults are complete
- rerun `clagnos update --auto --perf` without changing the natural task order
- confirm `clagnos show` prints the expected inventory while password-bearing VC profile values stay redacted
- confirm `clagnos do --vm-action=status --vm-name=<vm-name>` reports the VM as started
- confirm `clagnos connect --ssh --vm-name=<vm-name> --user=manager --test`; for Windows also confirm `clagnos connect --rdp --vm-name=<vm-name> --user=manager --test`
- when `VM_ENABLE_HIBERNATION=true`, validate the intended hibernation path explicitly and restore the VM to `started` before finishing the release gate
- when `VM_ENABLE_NESTED_VIRTUALIZATION=true`, verify that outcome after the live run before declaring release readiness

### Support And Contribution Paths
- Read [SUPPORT.md](SUPPORT.md) before opening a public issue.
- Read [SECURITY.md](SECURITY.md) for vulnerability reporting; do not post sensitive reports publicly.
- Read [CONTRIBUTING.md](CONTRIBUTING.md) before sending a pull request, especially for command-surface or workflow changes.
- Read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before participating in repo discussions or reviews.
- This repo uses a contact-first contribution model for large changes and a maintainer-curated review path.

### Documentation Contract
When a prompt changes repo files:
- update `README.md`, `AGENTS.md`, `clagnos.env.example`, tests, or help text when the contract changes
- update `CHANGELOG.md` and `release-notes.md` in the same final change set before commit
- update `docs/prompt-history.md` with the English-normalized prompt and final summary
- when a maintained document records a time-of-day, record it in UTC

### Prompt History Rule
- Very short approval/confirmation/follow-up prompts are not auto-recorded.
- Non-mutating questions, analysis requests, and investigation-only prompts are not auto-recorded.
- All other substantive prompts are recorded.
- Excluded prompt types are recorded only after explicit user confirmation.
- Recorded entries are stored in English. If the original dialog was not English, it is translated before recording.
- Prompt-history headings use `### YYYY-MM-DD HH:MM UTC`.

## Documentation Set
- `AGENTS.md`: engineering contract and collaboration rules.
- `README.md`: operator and contributor manual.
- `LICENSE`: custom non-commercial repository license.
- `CONTRIBUTING.md`: contributor workflow and review expectations.
- `SUPPORT.md`: support and escalation guidance.
- `SECURITY.md`: private vulnerability-reporting path.
- `CODE_OF_CONDUCT.md`: participation expectations for repo spaces.
- `CHANGELOG.md`: complete project history.
- `release-notes.md`: current documented release summary.
- `roadmap.md`: forward plan organized by business value.
- `docs/prompt-history.md`: English-normalized prompt ledger.
- `docs/windows-store-migration-audit.md`: current Windows installer-source audit, including which Store migrations are already active and which candidates still wait for explicit approval.

## License And Sponsorship
This repository is distributed under the custom non-commercial license in [LICENSE](LICENSE).

High-level intent:
- learning, teaching, evaluation, and private non-commercial modification are allowed
- public redistribution and commercial use require developer permission
- commercial licensing and sponsorship discussions should be directed to the developer

If this project saves time, reduces operational risk, or is useful in your environment, sponsorship helps keep the documentation, testing, and VM automation work moving forward.
