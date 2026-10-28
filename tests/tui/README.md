# Prodicloud TUI tests

Run the non-live TUI suite before opening `pd.cmd`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\tui\run-tui-tests.ps1
```

The same suite is included in `tests/powershell-compatibility-check.ps1` and runs under Windows PowerShell 5.1 and PowerShell 7+.

The suite contains 187 fixture-backed scenarios, including a process-level launcher scenario. The latter copies the real `pd.cmd`, `scripts/prodicloud-cli.ps1`, `scripts/prodicloud-cache-worker.ps1`, and runtime modules into an isolated temporary directory, launches that `pd.cmd` through `cmd.exe`, feeds menu choices through stdin, asserts the actual captured console output, verifies the background worker publishes flat group/resource/VM rows using only fixture Azure reads, and invokes `pd.cmd help resize` to verify command arguments survive backend loading. Its compiled `az.exe` fixture preserves the read-only guest-probe arguments and rejects any Run Command that is not the expected nested-virtualization inspection.

## Screen and action coverage

| TUI area | Covered behavior |
| --- | --- |
| Launcher and shared header | `pd.cmd` target and argument forwarding, tagline, selected subscription, offline header |
| Main menu | Virtual computers, inventory, cloud subscriptions, configure, help, and exit |
| Inventory snapshot | Startup/background inventory command counts, real worker cache import, in-memory and disk reuse, unchanged-snapshot identity, ETag-based change detection, mutation invalidation, and reconciliation |
| Numbered selection and create wizard | Default markers, page navigation (`p/n/g/f/t`), rejecting numbers outside the visible page, all create steps, wizard controls, disk/port validation, and the create dispatch context |
| Cloud subscriptions | Active/selected markers, enabled selection, disabled selection, invalid selection, inventory errors, and exit |
| Virtual computers | Empty inventory, numeric selection, create, refresh, legacy group migration flow, inventory errors, and exit |
| Selected VC | Detail refresh, initialize, update, programs, components, VC Operations, delete confirmation/cancellation, back, and exit |
| VC details | Compute, image, disks, NIC/VNet/subnet/NSG, IP/DNS, security/features, tags, attached resources, SSH/RDP credentials for both user roles, and the Windows WinRM endpoint |
| Manage programs | Builtin/custom catalog, package status and disabled markers, enable/disable/install/status/uninstall, background status refresh results with Enter pause, uninstall confirmation, app-state save/restore and Windows/Linux local-target handling |
| Managed inventory | All ten numbered filters, optional resource-group filtering, unfiltered inventory, invalid input, back, and exit |
| Components | All nine component types; list/show/create/update/delete; disk/NIC attach/detach; invalid input and navigation |
| Tasks | Init/update listing and isolated runs, disabled task listing, local task-run history, app-state save/restore for VM and local Windows, and task availability enable/disable for both stages |
| VC Operations | All fourteen Windows lifecycle choices (Linux omits Windows-only guest hibernate), composed shutdown/power-off and deallocation, command-contract-valid target options, force confirmations/cancellation, Intel/AMD and RAM-filtered hardware resize wizard, OS/data disk expansion and shrink-review routing, move, both feature toggles, SSH/RDP/PowerShell connection and tests, PowerShell command routing, SSH remote command/shell, task/component submenus, text report and JSON export, invalid input, and exit |

## Azure safety boundary

The screen/action scenarios use fixture Azure reads, a blocked `az` function, and a stubbed Prodicloud command dispatcher. The process-level scenario uses a sanitized temporary `prodicloud.env` plus `tui-fixture-vc.env`, a compiled `az.exe` fixture that returns fixture read data and rejects mutating verbs, and a fake `net.exe` for the launcher's elevation check. It captures output from the real `pd.cmd` process without reading the operator's global or VC environment files or exposing local credentials. The same fixture process runs the hidden inventory worker and checks its Azure command counts and cache shape. Every test asserts zero native Azure CLI calls and zero real dispatcher calls; the process scenario also checks its fake Azure log for mutation attempts.

This suite validates TUI rendering, navigation, selection mapping, command construction, and actual launcher output. It does not claim that a live Azure operation will succeed against a specific subscription or VM.
