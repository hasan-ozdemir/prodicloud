# Package Catalogs

Clagnos keeps standard packages and operator-authored packages in separate catalogs:

- `builtin/<platform>/<package-id>/` contains the maintained standard package set.
- `custom/<platform>/<package-id>/` contains packages added for this repository.

Each package directory contains `package.json` and one installer script (`install.ps1` on Windows or `install.sh` on Linux). The folder name and manifest `id` must match. Package ids use lower-case letters, numbers, and hyphens.

Required manifest fields are `id`, `displayName`, `category`, `statusCheck`, and `uninstall`. Optional fields are `enabled` (defaults to `true`), `timeout`, `sortOrder`, `assets`, `appState`, `appStateKey`, `dependsOn`, and `postInstallTasks`. `dependsOn` lists package ids that should be installed before this package; the package command installs only the selected package. `statusCheck` and `uninstall` use the validated action kinds from the runtime package catalog. Relative asset paths resolve from the package directory.

Example:

```json
{
  "id": "my-tool",
  "displayName": "My Tool",
  "category": "tool",
  "enabled": true,
  "timeout": 180,
  "installScript": "install.ps1",
  "statusCheck": { "kind": "command", "value": "my-tool" },
  "uninstall": { "kind": "choco", "value": "my-tool" }
}
```

Custom packages are installed remotely on the selected virtual computer. Catalog origin (`[builtin]` or `[custom]`) identifies where the package definition is maintained; it does not change its execution target. Enable/disable updates the package manifest after typed confirmation and affects future operations in this repository.
