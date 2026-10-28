$ErrorActionPreference = 'Stop'
Write-Output 'Doing: install the official Microsoft Sysinternals suite after validating its signed binaries.'
Install-ProdicloudSysinternalsPackage -Spec $spec
