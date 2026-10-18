$ErrorActionPreference = 'Stop'
Write-Host 'Doing: install or verify Microsoft Teams using the signed headless Teams bootstrapper'

$existingPackages = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction Stop)
if ($existingPackages.Count -gt 0) {
    Write-Host ("Existing Microsoft Teams package is present for {0} user registration(s); install script will not upgrade during install or repair." -f $existingPackages.Count)
}
else {
    Invoke-ClagnosTeamsBootstrapper -Action install -TimeoutSeconds 240
}

$verifiedPackages = @(Get-AppxPackage -AllUsers -Name 'MSTeams' -ErrorAction Stop)
if ($verifiedPackages.Count -eq 0) {
    throw 'Microsoft Teams was not registered for any user after the bootstrapper operation.'
}

$verifiedVersion = [string](@($verifiedPackages | Sort-Object Version -Descending | Select-Object -First 1)[0].Version)
Set-ClagnosTeamsStoreInstallState -State installed -Summary ("Microsoft Teams is provisioned for users at version {0}." -f $verifiedVersion)
Write-Host ("Microsoft Teams package detected for {0} user registration(s), version {1}." -f $verifiedPackages.Count,$verifiedVersion)
Write-Host 'install-teams-application-completed'
