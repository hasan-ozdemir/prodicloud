$ErrorActionPreference = 'Stop'
Import-Module 'C:\Windows\Temp\prodicloud-package-operations.psm1' -Force -DisableNameChecking
Invoke-ProdicloudPackageLifecycle -Action update -PackageSpecBase64 '__PRODICLOUD_PACKAGE_SPEC_B64__' -InstallScriptBase64 '__PRODICLOUD_INSTALL_SCRIPT_B64__'