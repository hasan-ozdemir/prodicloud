# Clagnos TUI tests

Run the non-live TUI suite before opening `cg.cmd`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\tui\run-tui-tests.ps1
```

The same suite is included in `tests/powershell-compatibility-check.ps1` and runs under Windows PowerShell 5.1 and PowerShell 7+.

## Screen and action coverage

| TUI area | Covered behavior |
| --- | --- |
| Launcher and shared header | `cg.cmd` target and argument forwarding, tagline, selected subscription, offline header |
| Main menu | Virtual computers, inventory, cloud subscriptions, configure, help, and exit |
| Cloud subscriptions | Active/selected markers, enabled selection, disabled selection, invalid selection, inventory errors, and exit |
| Virtual computers | Empty inventory, numeric selection, create, refresh, legacy group migration flow, inventory errors, and exit |
| Selected VC | Detail refresh, initialize, update, programs, components, operations, delete confirmation/cancellation, back, and exit |
| VC details | Compute, image, disks, NIC/VNet/subnet/NSG, IP/DNS, security/features, tags, attached resources, and SSH/RDP credentials for both user roles |
| Manage programs | Builtin/custom catalog, package status and disabled markers, enable/disable/install/status/uninstall, uninstall confirmation, app-state save/restore and Windows/Linux local-target handling |
| Managed inventory | All ten numbered filters, optional resource-group filtering, unfiltered inventory, invalid input, back, and exit |
| Components | All nine component types; list/show/create/update/delete; disk/NIC attach/detach; invalid input and navigation |
| Tasks | Init/update listing and isolated runs, disabled task listing, app-state save/restore for VM and local Windows, and task availability enable/disable for both stages |
| Operations | All twelve lifecycle choices, force confirmations/cancellation, compute and disk resize, move, both feature toggles, SSH/RDP/test, remote command/shell, task/component submenus, report, invalid input, and exit |

## Azure safety boundary

The runner uses fixtures for Azure reads, a blocked `az` function, and a stubbed Clagnos command dispatcher. The VC mutations displayed in the menus are recorded as intended command/options only; they are never sent to `clagnos.ps1` or Azure. It does not read `.env`, spawn Azure CLI, or change local subscription state. Every test asserts that native Azure CLI calls and real dispatcher calls remain at zero.

This suite validates TUI rendering, navigation, selection mapping, and command construction. It does not claim that a live Azure operation will succeed against a specific subscription or VM.
