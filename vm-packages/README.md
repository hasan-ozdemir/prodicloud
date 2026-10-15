# Package Catalogs

Clagnos keeps standard packages and operator-authored packages in separate catalogs:

- `builtin/<platform>/<package-id>/` contains the maintained standard package set.
- `custom/<platform>/<package-id>/` contains packages added for this repository.

Each package directory contains `package.json` and one installer script (`install.ps1` on Windows or `install.sh` on Linux). The folder name and manifest `id` must match. Package ids use lower-case letters, numbers, and hyphens.

Each `builtin/<platform>/` and `custom/<platform>/` directory contains a `tasks.toml` catalog. It lists each package id exactly once as a boolean under `[tasks]`; this is the only source of package availability. Package manifests must not contain an `enabled` field.

Required manifest fields are `id`, `displayName`, `category`, `statusCheck`, and `uninstall`. Optional fields are `timeout`, `sortOrder`, `assets`, `appState`, `appStateKey`, `dependsOn`, and `postInstallTasks`. `dependsOn` lists package ids that should be installed before this package; the package command installs only the selected package. `statusCheck` and `uninstall` use the validated action kinds from the runtime package catalog. Relative asset paths resolve from the package directory.

## Package app-state

Package app-state is settings-first. Use `profileFiles` and tightly scoped `profileDirectories` for portable preferences. Do not package sign-in sessions, passwords, access or refresh tokens, browser profiles, cloud account state, histories, caches, workspace databases, generated models, or license/activation data. If an application stores only identity-bound or machine-bound state, omit its `appState` policy.

The owning `app-state/app-state.zip` is versioned with its package manifest when it contains reviewed portable preferences. These archives make package installs reproducible from a clean Git checkout. Before adding or changing one, run `tests/package-app-state-contract-check.ps1` and `tests/sensitive-content-check.ps1`; never commit credentials, authenticated sessions, personal identity values, or source-machine paths. Package app-state backups remain local-only and git-ignored.

Capture generalizes known source profile paths, SIDs, drive roots, host names, IP addresses, and Visual Studio instance directories. A package archive may also use these target-resolved placeholders in textual payloads and manifest destinations:

| Placeholder | Resolved on the target VM |
| --- | --- |
| `%CLAGNOS_TARGET_USER%`, `%CLAGNOS_TARGET_PROFILE_PATH%` | The profile selected by the archive entry (`manager` or `assistant`); on Windows `%CLAGNOS_TARGET_PROFILE_PATH%` is its profile directory |
| `%CLAGNOS_VM_ADMIN_USER%`, `%CLAGNOS_ASSISTANT_USER%`, `%CLAGNOS_VM_ADMIN_PROFILE_PATH%`, `%CLAGNOS_ASSISTANT_PROFILE_PATH%`, `%CLAGNOS_VM_ADMIN_USER_SID%`, `%CLAGNOS_ASSISTANT_USER_SID%` | The target VM's configured operator and assistant accounts |
| `%CLAGNOS_LOCAL_APP_DATA%`, `%CLAGNOS_ROAMING_APP_DATA%` | The selected target profile's local and roaming application-data roots |
| `%CLAGNOS_COMPUTER_NAME%`, `%CLAGNOS_PROGRAM_DATA%`, `%CLAGNOS_PROGRAM_FILES%`, `%CLAGNOS_PROGRAM_FILES_X86%`, `%CLAGNOS_PRIMARY_IPV4_ADDRESS%` | The target VM's host name, OS paths, and primary IPv4 address; path values are OS-specific |
| `%CLAGNOS_SYSTEM_DRIVE%`, `%CLAGNOS_WINDOWS_DIRECTORY%`, `%CLAGNOS_TARGET_USER_SID%`, `%CLAGNOS_VM_ADMIN_USER_SID%`, `%CLAGNOS_ASSISTANT_USER_SID%` | Windows-only drive, Windows directory, and target profile SIDs |
| `%CLAGNOS_TARGET_CPU_COUNT%`, `%CLAGNOS_TARGET_MEMORY_GB%` | The target VM's detected logical CPU count and physical memory in GiB |
| `%CLAGNOS_VS_INSTANCE_DIRECTORY%` | The installed Visual Studio 2022 instance directory for that profile |

Custom Linux package app-state also supports `%CLAGNOS_TARGET_HOME%`, `%CLAGNOS_SYSTEM_ROOT%`, `%CLAGNOS_TARGET_UID%`, `%CLAGNOS_TARGET_GID%`, `%CLAGNOS_VM_ADMIN_HOME%`, `%CLAGNOS_ASSISTANT_HOME%`, `%CLAGNOS_VM_ADMIN_UID%`, `%CLAGNOS_ASSISTANT_UID%`, `%CLAGNOS_VM_ADMIN_GID%`, and `%CLAGNOS_ASSISTANT_GID%`. On Linux, `SYSTEM_ROOT` resolves to `/`, `PROGRAM_DATA` to `/var/lib`, `PROGRAM_FILES` to `/usr/local/bin`, and `PROGRAM_FILES_X86` to `/usr/lib`; Windows drive and registry placeholders are not valid on Linux.

Missing values and unsupported `%CLAGNOS_*%` tokens fail before replay. The manager and assistant profiles remain separate during capture and restore. Validate new or changed snapshots with `tests/package-app-state-contract-check.ps1`; review builtin policy changes with `tools/maintain-package-app-state.ps1` and pass `-Apply` only when the reviewed cleanup should be written.

Example:

Availability in `tasks.toml`:

```toml
[tasks]
my-tool = true
```

```json
{
  "id": "my-tool",
  "displayName": "My Tool",
  "category": "tool",
  "timeout": 180,
  "installScript": "install.ps1",
  "statusCheck": { "kind": "command", "value": "my-tool" },
  "uninstall": { "kind": "choco", "value": "my-tool" }
}
```

Custom packages are installed remotely on the selected virtual computer. Catalog origin (`[builtin]` or `[custom]`) identifies where the package definition is maintained; it does not change its execution target. Enable/disable updates the catalog's `tasks.toml` boolean after typed confirmation and affects future operations in this repository.
