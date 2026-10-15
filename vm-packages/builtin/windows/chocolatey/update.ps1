$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action update -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__CLAGNOS_INSTALL_SCRIPT_B64__'