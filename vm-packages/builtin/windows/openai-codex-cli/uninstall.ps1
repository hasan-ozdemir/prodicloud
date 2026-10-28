$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\prodicloud-package-operations.psm1' -Force -DisableNameChecking
Invoke-ProdicloudPackageLifecycle -Action uninstall -PackageSpecBase64 '__PRODICLOUD_PACKAGE_SPEC_B64__'