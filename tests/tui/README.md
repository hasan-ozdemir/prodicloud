# Clagnos TUI tests

Run the non-live TUI suite before opening `cg.cmd`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\tui\run-tui-tests.ps1
```

The same suite is included in `tests/powershell-compatibility-check.ps1` and runs under Windows PowerShell 5.1 and PowerShell 7+.

The suite contains 159 data-driven screen/action scenarios and one process-level launcher scenario. The latter copies the real `cg.cmd`, `scripts/clagnos-cli.ps1`, and runtime modules into an isolated temporary directory, launches that `cg.cmd` through `cmd.exe`, feeds menu choices through stdin, and asserts the actual captured console output.

## Screen and action coverage

| TUI area | Covered behavior |
| --- | --- |
| Launcher and shared header | `cg.cmd` target and argument forwarding, tagline, selected subscription, offline header |
| Main menu | Virtual computers, inventory, cloud subscriptions, configure, help, and exit |
| Cloud subscriptions | Active/selected markers, enabled selection, disabled selection, invalid selection, inventory errors, and exit |
| Virtual computers | Empty inventory, numeric selection, create, refresh, legacy group migration flow, inventory errors, and exit |
| Selected VC | Detail refresh, initialize, update, programs, components, operations, delete confirmation/cancellation, back, and exit |
| VC details | Compute, image, disks, NIC/VNet/subnet/NSG, IP/DNS, security/features, tags, attached resources, SSH/RDP credentials for both user roles, and the Windows WinRM endpoint |
| Manage programs | Builtin/custom catalog, package status and disabled markers, enable/disable/install/status/uninstall, uninstall confirmation, app-state save/restore and Windows/Linux local-target handling |
| Managed inventory | All ten numbered filters, optional resource-group filtering, unfiltered inventory, invalid input, back, and exit |
| Components | All nine component types; list/show/create/update/delete; disk/NIC attach/detach; invalid input and navigation |
| Tasks | Init/update listing and isolated runs, disabled task listing, local task-run history, app-state save/restore for VM and local Windows, and task availability enable/disable for both stages |
| Operations | All twelve lifecycle choices, force confirmations/cancellation, compute and disk resize, move, both feature toggles, SSH/RDP/PowerShell connection and tests, PowerShell command routing, SSH remote command/shell, task/component submenus, text report and JSON export, invalid input, and exit |

## Azure safety boundary

The screen/action scenarios use fixture Azure reads, a blocked `az` function, and a stubbed Clagnos command dispatcher. The process-level scenario uses a sanitized temporary `.env`, a fake `az.cmd` that returns fixture read data and rejects mutating verbs, and a fake `net.exe` for the launcher's elevation check. It captures output from the real `cg.cmd` process without reading the operator's `.env` or exposing local credentials. Every test asserts zero native Azure CLI calls and zero real dispatcher calls; the process scenario also checks its fake Azure log for mutation attempts.

This suite validates TUI rendering, navigation, selection mapping, command construction, and actual launcher output. It does not claim that a live Azure operation will succeed against a specific subscription or VM.
