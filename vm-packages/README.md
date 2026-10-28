# Package Catalogs

Prodicloud keeps standard packages and operator-authored packages in separate catalogs:

- `builtin/<platform>/<package-id>/` contains the maintained standard package set.
- `custom/<platform>/<package-id>/` contains packages added for this repository.

Each package directory contains `package.json` and one installer script (`install.ps1` on Windows or `install.sh` on Linux). The folder name and manifest `id` must match. Package ids use lower-case letters, numbers, and hyphens.

Each `builtin/<platform>/` and `custom/<platform>/` directory contains a `tasks.toml` catalog. It lists each package id exactly once as a boolean under `[tasks]`; this is the only source of package availability. Package manifests must not contain an `enabled` field.

Required manifest fields are `id`, `displayName`, `category`, `statusCheck`, and `uninstall`. Optional fields are `timeout`, `sortOrder`, `assets`, `appState`, `appStateKey`, `dependsOn`, and `postInstallTasks`. `dependsOn` lists package ids that should be installed before this package; the package command installs only the selected package. `statusCheck` and `uninstall` use the validated action kinds from the runtime package catalog. For a Windows Chocolatey package, optional `statusCheck.executable` adds a runnable-file health check; `versionArgument` selects that executable's version flag, and `executablePaths` lists additional absolute locations rooted at `%ProgramFiles%`, `%ProgramFiles(x86)%`, or `%LOCALAPPDATA%`. Relative asset paths resolve from the package directory.

## Package app-state

Package app-state is settings-first. Use `profileFiles` and tightly scoped `profileDirectories` for portable preferences. Do not package sign-in sessions, passwords, access or refresh tokens, browser profiles, cloud account state, histories, caches, workspace databases, generated models, or license/activation data. If an application stores only identity-bound or machine-bound state, omit its `appState` policy.

The owning `app-state/app-state.zip` is versioned with its package manifest when it contains reviewed portable preferences. These archives make package installs reproducible from a clean Git checkout. Before adding or changing one, run `tests/package-app-state-contract-check.ps1` and `tests/sensitive-content-check.ps1`; never commit credentials, authenticated sessions, personal identity values, or source-machine paths. Package app-state backups remain local-only and git-ignored.

Capture generalizes known source profile paths, SIDs, drive roots, host names, IP addresses, and Visual Studio instance directories. A package archive may also use these target-resolved placeholders in textual payloads and manifest destinations:

| Placeholder | Resolved on the target VM |
| --- | --- |
| `%PRODICLOUD_TARGET_USER%`, `%PRODICLOUD_TARGET_PROFILE_PATH%` | The profile selected by the archive entry (`manager` or `assistant`); on Windows `%PRODICLOUD_TARGET_PROFILE_PATH%` is its profile directory |
| `%PRODICLOUD_VM_ADMIN_USER%`, `%PRODICLOUD_ASSISTANT_USER%`, `%PRODICLOUD_VM_ADMIN_PROFILE_PATH%`, `%PRODICLOUD_ASSISTANT_PROFILE_PATH%`, `%PRODICLOUD_VM_ADMIN_USER_SID%`, `%PRODICLOUD_ASSISTANT_USER_SID%` | The target VM's configured operator and assistant accounts |
| `%PRODICLOUD_LOCAL_APP_DATA%`, `%PRODICLOUD_ROAMING_APP_DATA%` | The selected target profile's local and roaming application-data roots |
| `%PRODICLOUD_COMPUTER_NAME%`, `%PRODICLOUD_PROGRAM_DATA%`, `%PRODICLOUD_PROGRAM_FILES%`, `%PRODICLOUD_PROGRAM_FILES_X86%`, `%PRODICLOUD_PRIMARY_IPV4_ADDRESS%` | The target VM's host name, OS paths, and primary IPv4 address; path values are OS-specific |
| `%PRODICLOUD_SYSTEM_DRIVE%`, `%PRODICLOUD_WINDOWS_DIRECTORY%`, `%PRODICLOUD_TARGET_USER_SID%`, `%PRODICLOUD_VM_ADMIN_USER_SID%`, `%PRODICLOUD_ASSISTANT_USER_SID%` | Windows-only drive, Windows directory, and target profile SIDs |
| `%PRODICLOUD_TARGET_CPU_COUNT%`, `%PRODICLOUD_TARGET_MEMORY_GB%` | The target VM's detected logical CPU count and physical memory in GiB |
| `%PRODICLOUD_VS_INSTANCE_DIRECTORY%` | The installed Visual Studio 2022 instance directory for that profile |

Custom Linux package app-state also supports `%PRODICLOUD_TARGET_HOME%`, `%PRODICLOUD_SYSTEM_ROOT%`, `%PRODICLOUD_TARGET_UID%`, `%PRODICLOUD_TARGET_GID%`, `%PRODICLOUD_VM_ADMIN_HOME%`, `%PRODICLOUD_ASSISTANT_HOME%`, `%PRODICLOUD_VM_ADMIN_UID%`, `%PRODICLOUD_ASSISTANT_UID%`, `%PRODICLOUD_VM_ADMIN_GID%`, and `%PRODICLOUD_ASSISTANT_GID%`. On Linux, `SYSTEM_ROOT` resolves to `/`, `PROGRAM_DATA` to `/var/lib`, `PROGRAM_FILES` to `/usr/local/bin`, and `PROGRAM_FILES_X86` to `/usr/lib`; Windows drive and registry placeholders are not valid on Linux.

Missing values and unsupported `%PRODICLOUD_*%` tokens fail before replay. The manager and assistant profiles remain separate during capture and restore. Validate new or changed snapshots with `tests/package-app-state-contract-check.ps1`; review builtin policy changes with `tools/maintain-package-app-state.ps1` and pass `-Apply` only when the reviewed cleanup should be written.

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
