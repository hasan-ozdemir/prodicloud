$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\clagnos-package-operations.psm1' -Force -DisableNameChecking
Invoke-ClagnosPackageLifecycle -Action uninstall -PackageSpecBase64 '__CLAGNOS_PACKAGE_SPEC_B64__'