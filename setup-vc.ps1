[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,62}$')]
    [string]$VmName,
    [switch]$PreflightOnly,
    [switch]$ResumeAtPackageStage,
    [string]$SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:SetupRepoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$script:SetupGlobalEnvPath = Join-Path $script:SetupRepoRoot 'clagnos.env'
$script:SetupVmName = $VmName.Trim().ToLowerInvariant()
$script:SetupVmEnvPath = Join-Path $script:SetupRepoRoot ($script:SetupVmName + '.env')
$script:SetupLauncherPath = Join-Path $script:SetupRepoRoot 'cg.cmd'
$script:SetupVmRegion = ''
$script:SetupVmSize = ''
$script:SetupVmDiskSizeGb = 0
$script:SetupVmImage = ''
$script:SetupVmAdminUser = ''
$script:SetupVmAssistantUser = ''
$script:SetupVmOs = ''
$script:SetupVmHibernation = $false
$script:SetupVmNestedVirtualization = $false
$script:SetupVmSecurityType = ''
$script:SetupVmSecureBoot = $false
$script:SetupVmVtpm = $false
$script:SetupTemporaryEnvValues = @{}
$script:SetupSubscriptionId = ''
$script:SetupResourceGroup = ''
$script:SetupDidPushLocation = $false
$script:SetupFailed = $false
$script:SetupPackageWarnings = @()
$script:SetupTranscriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-setup-' + $script:SetupVmName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$script:SetupTranscriptStarted = $false

function Write-SetupDoing {
    param([Parameter(Mandatory = $true)][string]$Action)
    Write-Host ("Doing: {0}" -f $Action) -ForegroundColor Cyan
}

function Assert-SetupElevatedSession {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run setup-vc*.cmd from an elevated PowerShell or Command Prompt. The unattended runner will not open an interactive UAC prompt.'
    }
}

function Get-SetupEnvPathForKey {
    param([Parameter(Mandatory = $true)][string]$Key)
    if ($Key -eq 'SELECTED_AZURE_SUBSCRIPTION_ID' -or $Key -like 'DEFAULT_*' -or $Key -in @('RESOURCE_GROUP_TEMPLATE','VNET_NAME_TEMPLATE','SUBNET_NAME_TEMPLATE','NSG_NAME_TEMPLATE','NSG_RULE_NAME_TEMPLATE','PUBLIC_IP_NAME_TEMPLATE','NIC_NAME_TEMPLATE','VM_DISK_NAME_TEMPLATE','AZURE_COMMAND_TIMEOUT_SECONDS','SSH_CONNECT_TIMEOUT_SECONDS','SSH_TASK_TIMEOUT_SECONDS','VM_TASK_OUTCOME_MODE','SSH_MAX_RETRIES','PYSSH_CLIENT_PATH','VM_PRICE_COUNT_HOURS') -or $Key -like 'SELECTED_COMPANY_*' -or $Key -like 'SELECTED_EMPLOYEE_*' -or $Key -like 'WIN_PUBLIC_SHORTCUT_*') {
        return $script:SetupGlobalEnvPath
    }
    return $script:SetupVmEnvPath
}

function Get-SetupEnvValue {
    param([Parameter(Mandatory = $true)][string]$Key)
    $path = Get-SetupEnvPathForKey -Key $Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    $text = [System.IO.File]::ReadAllText($path)
    $match = [regex]::Match($text, '(?m)^\s*' + [regex]::Escape($Key) + '\s*=(.*)$')
    if (-not $match.Success) {
        $defaultKey = switch -Exact ($Key) {
            'SELECTED_VM_OS' { 'DEFAULT_VM_OS' }
            'SELECTED_AZURE_REGION' { 'DEFAULT_AZURE_REGION' }
            'VM_STORAGE_SKU' { 'DEFAULT_VM_STORAGE_SKU' }
            'VM_SECURITY_TYPE' { 'DEFAULT_VM_SECURITY_TYPE' }
            'VM_ENABLE_HIBERNATION' { 'DEFAULT_VM_ENABLE_HIBERNATION' }
            'VM_ENABLE_NESTED_VIRTUALIZATION' { 'DEFAULT_VM_ENABLE_NESTED_VIRTUALIZATION' }
            'VM_ENABLE_SECURE_BOOT' { 'DEFAULT_VM_ENABLE_SECURE_BOOT' }
            'VM_ENABLE_VTPM' { 'DEFAULT_VM_ENABLE_VTPM' }
            'VM_ADMIN_USER' { 'DEFAULT_VM_ADMIN_USER' }
            'VM_ASSISTANT_USER' { 'DEFAULT_VM_ASSISTANT_USER' }
            'VM_SSH_PORT' { 'DEFAULT_VM_SSH_PORT' }
            'VM_RDP_PORT' { 'DEFAULT_VM_RDP_PORT' }
            'TCP_PORTS' { 'DEFAULT_TCP_PORTS' }
            'PACKAGE_TRANSPORT' { 'DEFAULT_PACKAGE_TRANSPORT' }
            'WIN_VM_IMAGE' { 'DEFAULT_WIN_VM_IMAGE' }
            'WIN_VM_SIZE' { 'DEFAULT_WIN_VM_SIZE' }
            'WIN_VM_DISK_SIZE_GB' { 'DEFAULT_WIN_VM_DISK_SIZE_GB' }
            'LIN_VM_IMAGE' { 'DEFAULT_LIN_VM_IMAGE' }
            'LIN_VM_SIZE' { 'DEFAULT_LIN_VM_SIZE' }
            'LIN_VM_DISK_SIZE_GB' { 'DEFAULT_LIN_VM_DISK_SIZE_GB' }
            default { '' }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$defaultKey)) { return (Get-SetupEnvValue -Key $defaultKey) }
        return ''
    }
    $value = [string]$match.Groups[1].Value.Trim()
    if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value
}

function Get-SetupBooleanValue {
    param([Parameter(Mandatory = $true)][string]$Key)
    $raw = (Get-SetupEnvValue -Key $Key).Trim()
    $value = $false
    if (-not [bool]::TryParse($raw,[ref]$value)) {
        throw ("VC setting '{0}' must be true or false in '{1}'." -f $Key,[System.IO.Path]::GetFileName($script:SetupVmEnvPath))
    }
    return $value
}

function Initialize-SetupDesiredConfiguration {
    $profileVmName = (Get-SetupEnvValue -Key 'SELECTED_VM_NAME').Trim()
    if (-not [string]::IsNullOrWhiteSpace($profileVmName) -and -not [string]::Equals($profileVmName,$script:SetupVmName,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Profile '{0}' identifies VM '{1}', not requested VM '{2}'." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath),$profileVmName,$script:SetupVmName)
    }
    if ([string]::IsNullOrWhiteSpace($profileVmName)) { Set-SetupEnvValue -Key 'SELECTED_VM_NAME' -Value $script:SetupVmName }

    $script:SetupVmOs = (Get-SetupEnvValue -Key 'SELECTED_VM_OS').Trim().ToLowerInvariant()
    if ($script:SetupVmOs -ne 'windows') { throw ("The unattended setup runner currently requires SELECTED_VM_OS=windows in '{0}'." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath)) }
    $script:SetupVmRegion = (Get-SetupEnvValue -Key 'SELECTED_AZURE_REGION').Trim().ToLowerInvariant()
    $script:SetupVmSize = (Get-SetupEnvValue -Key 'WIN_VM_SIZE').Trim()
    $script:SetupVmImage = (Get-SetupEnvValue -Key 'WIN_VM_IMAGE').Trim()
    $script:SetupVmAdminUser = (Get-SetupEnvValue -Key 'VM_ADMIN_USER').Trim()
    $script:SetupVmAssistantUser = (Get-SetupEnvValue -Key 'VM_ASSISTANT_USER').Trim()
    $diskSizeText = (Get-SetupEnvValue -Key 'WIN_VM_DISK_SIZE_GB').Trim()
    if ([string]::IsNullOrWhiteSpace($script:SetupVmRegion) -or [string]::IsNullOrWhiteSpace($script:SetupVmSize) -or [string]::IsNullOrWhiteSpace($script:SetupVmImage)) {
        throw ("Profile '{0}' must define SELECTED_AZURE_REGION, WIN_VM_SIZE, and WIN_VM_IMAGE before setup." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath))
    }
    if (-not [int]::TryParse($diskSizeText,[ref]$script:SetupVmDiskSizeGb) -or $script:SetupVmDiskSizeGb -lt 1) {
        throw ("Profile '{0}' must define a positive integer WIN_VM_DISK_SIZE_GB." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath))
    }
    if ([string]::IsNullOrWhiteSpace($script:SetupVmAdminUser) -or [string]::IsNullOrWhiteSpace($script:SetupVmAssistantUser)) {
        throw ("Profile '{0}' must define VM_ADMIN_USER and VM_ASSISTANT_USER." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath))
    }
    if ([string]::IsNullOrWhiteSpace((Get-SetupEnvValue -Key 'VM_ADMIN_PASS')) -or [string]::IsNullOrWhiteSpace((Get-SetupEnvValue -Key 'VM_ASSISTANT_PASS'))) {
        throw ("Profile '{0}' must contain both managed-user passwords for unattended setup. Values are never printed." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath))
    }
    $script:SetupVmHibernation = Get-SetupBooleanValue -Key 'VM_ENABLE_HIBERNATION'
    $script:SetupVmNestedVirtualization = Get-SetupBooleanValue -Key 'VM_ENABLE_NESTED_VIRTUALIZATION'
    $script:SetupVmSecurityType = (Get-SetupEnvValue -Key 'VM_SECURITY_TYPE').Trim()
    if ([string]::IsNullOrWhiteSpace($script:SetupVmSecurityType)) { $script:SetupVmSecurityType = 'Standard' }
    $script:SetupVmSecureBoot = Get-SetupBooleanValue -Key 'VM_ENABLE_SECURE_BOOT'
    $script:SetupVmVtpm = Get-SetupBooleanValue -Key 'VM_ENABLE_VTPM'
}

function Set-SetupEnvValue {
    param([Parameter(Mandatory = $true)][string]$Key,[AllowEmptyString()][string]$Value)
    $path = Get-SetupEnvPathForKey -Key $Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        if ($path -eq $script:SetupVmEnvPath) {
            $template = Join-Path $script:SetupRepoRoot 'vc.env.example'
            if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw 'vc.env.example was not found.' }
            Copy-Item -LiteralPath $template -Destination $path -ErrorAction Stop
        }
        else { throw ("Required local configuration file was not found: {0}" -f $path) }
    }
    $text = [System.IO.File]::ReadAllText($path)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @([regex]::Split($text, "\r\n|\n|\r"))) { $lines.Add([string]$line) }
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=.*$'
    $found = $false
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match $pattern) {
            $lines[$index] = ('{0}={1}' -f $Key,$Value)
            $found = $true
        }
    }
    if (-not $found) { $lines.Add(('{0}={1}' -f $Key,$Value)) }
    [System.IO.File]::WriteAllText($path,($lines -join $newline),[System.Text.UTF8Encoding]::new($false))
}

function Set-SetupTemporaryEnvValues {
    param([Parameter(Mandatory = $true)][hashtable]$Values)
    foreach ($key in @($Values.Keys)) {
        $name = [string]$key
        if (-not $script:SetupTemporaryEnvValues.ContainsKey($name)) { $script:SetupTemporaryEnvValues[$name] = [string](Get-SetupEnvValue -Key $name) }
        Set-SetupEnvValue -Key $name -Value ([string]$Values[$key])
    }
}

function Restore-SetupOriginalEnv {
    if (@($script:SetupTemporaryEnvValues.Keys).Count -gt 0) {
        Write-SetupDoing 'restore temporary VC setting overrides'
        foreach ($key in @($script:SetupTemporaryEnvValues.Keys)) { Set-SetupEnvValue -Key ([string]$key) -Value ([string]$script:SetupTemporaryEnvValues[$key]) }
        $script:SetupTemporaryEnvValues = @{}
    }
}

function Invoke-SetupAzJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-SetupDoing $Action
    $output = & az @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("Azure CLI failed while attempting to {0} (exit {1})." -f $Action,$exitCode) }
    if ([string]::IsNullOrWhiteSpace([string]$output)) { return $null }
    try { return (ConvertFrom-Json -InputObject ([string]($output -join [Environment]::NewLine)) -ErrorAction Stop) }
    catch { throw ("Azure CLI returned unreadable data while attempting to {0}." -f $Action) }
}

function Invoke-SetupAzText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-SetupDoing $Action
    $output = & az @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("Azure CLI failed while attempting to {0} (exit {1})." -f $Action,$exitCode) }
    return [string]($output -join [Environment]::NewLine).Trim()
}

function Invoke-SetupCg {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-SetupDoing $Action
    & $script:SetupLauncherPath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("cg.cmd failed while attempting to {0} (exit {1})." -f $Action,$exitCode) }
}

function Invoke-SetupCgRedacted {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-SetupDoing $Action
    & $script:SetupLauncherPath @Arguments 2>&1 | ForEach-Object {
        $safeLine = [regex]::Replace([string]$_,'(?i)(password|credential|secret|token|pass)(\s*[:=]\s*)\S+','$1$2[redacted]')
        Write-Host $safeLine
    }
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("cg.cmd failed while attempting to {0} (exit {1})." -f $Action,$exitCode) }
}

function Invoke-SetupCgCaptured {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-SetupDoing $Action
    $output = New-Object 'System.Collections.Generic.List[string]'
    & $script:SetupLauncherPath @Arguments 2>&1 | ForEach-Object {
        $line = [string]$_
        $safeLine = [regex]::Replace($line,'(?i)(password|credential|secret|token|pass)(\s*[:=]\s*)\S+','$1$2[redacted]')
        Write-Host $safeLine
        $output.Add($safeLine)
    }
    $exitCode = $LASTEXITCODE
    return [pscustomobject]@{ ExitCode = [int]$exitCode; Output = @($output.ToArray()) }
}

function Get-SetupPackageStatus {
    param([Parameter(Mandatory = $true)][string]$PackageId,[Parameter(Mandatory = $true)][string]$DisplayName)
    $arguments = @('package','--action','status','--catalog','builtin','--package',$PackageId,'--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId)
    Write-SetupDoing ("check {0} package status over WinRM" -f $DisplayName)
    $output = @(& $script:SetupLauncherPath @arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) {
        $safeLine = [regex]::Replace([string]$line,'(?i)(password|credential|secret|token|pass)(\s*[:=]\s*)\S+','$1$2[redacted]')
        Write-Host $safeLine
    }
    if ($exitCode -ne 0) { throw ("cg.cmd failed while checking {0} status (exit {1})." -f $DisplayName,$exitCode) }
    $statusLine = @($output | Where-Object { [string]$_ -match ('(?i)^\s*' + [regex]::Escape($DisplayName) + ':') } | Select-Object -Last 1)
    if ($statusLine.Count -ne 1) { throw ("Package status output did not include '{0}'." -f $DisplayName) }
    if ([string]$statusLine[0] -match '(?i)\bnot[- ]installed\b') { return 'not-installed' }
    if ([string]$statusLine[0] -match '(?i)\binstalled and detectable\b') { return 'installed' }
    throw ("Package '{0}' status is not safe to interpret: {1}" -f $DisplayName,[string]$statusLine[0])
}

function Get-SetupAuthenticodeInfo {
    param([Parameter(Mandatory = $true)][string]$Path)
    $pwshCandidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    $childPowerShell = if (Test-Path -LiteralPath $pwshCandidate -PathType Leaf) { $pwshCandidate } else { Join-Path $PSHOME 'powershell.exe' }
    if (-not (Test-Path -LiteralPath $childPowerShell -PathType Leaf)) { throw 'Windows PowerShell was not found for isolated Authenticode verification.' }
    $escapedPath = $Path.Replace("'", "''")
    $childScript = @"
`$ErrorActionPreference = 'Stop'
`$signature = Get-AuthenticodeSignature -LiteralPath '$escapedPath' -ErrorAction Stop
`$version = (Get-Item -LiteralPath '$escapedPath' -ErrorAction Stop).VersionInfo
`$signer = if (`$null -ne `$signature.SignerCertificate) { [string]`$signature.SignerCertificate.Subject } else { '' }
[pscustomobject]@{ Status = [string]`$signature.Status; Signer = `$signer; Company = [string]`$version.CompanyName; Product = [string]`$version.ProductName; ProductVersion = [string]`$version.ProductVersion } | ConvertTo-Json -Compress
"@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    $output = @(& $childPowerShell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("Isolated Authenticode verification failed (exit {0}): {1}" -f $exitCode,($output -join ' ').Trim()) }
    $jsonLine = @($output | Where-Object { [string]$_ -match '^\s*\{' } | Select-Object -Last 1)
    if ($jsonLine.Count -ne 1) { throw 'Isolated Authenticode verification returned no JSON result.' }
    try { return (ConvertFrom-Json -InputObject ([string]$jsonLine[0]) -ErrorAction Stop) }
    catch { throw 'Isolated Authenticode verification returned invalid JSON.' }
}

function Get-SetupSha256Hash {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [System.IO.File]::OpenRead($Path)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Stage-SetupAnyDeskInstaller {
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-' + $script:SetupVmName + '-anydesk')
    if (-not (Test-Path -LiteralPath $stagingRoot -PathType Container)) { New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null }
    $localInstaller = Join-Path $stagingRoot 'AnyDesk.exe'
    if (-not (Test-Path -LiteralPath $localInstaller -PathType Leaf)) {
        Write-SetupDoing 'download the official AnyDesk installer to a temporary local staging path'
        Invoke-WebRequest -Uri 'https://download.anydesk.com/AnyDesk.exe' -OutFile $localInstaller -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop
    }
    else { Write-SetupDoing 'reuse the existing temporary AnyDesk installer and verify its publisher before transfer' }
    $localSignature = Get-SetupAuthenticodeInfo -Path $localInstaller
    $localSigner = [string]$localSignature.Signer
    if ([string]$localSignature.Status -ne 'Valid' -or $localSigner -notmatch '(?i)O=AnyDesk Software GmbH' -or [string]$localSignature.Company -ne 'AnyDesk Software GmbH' -or [string]$localSignature.Product -notmatch '(?i)^AnyDesk$') {
        throw 'The downloaded AnyDesk installer did not pass the expected valid Authenticode publisher and product checks.'
    }

    if (-not (Get-Command New-ClagnosPowerShellRemotingSession -ErrorAction SilentlyContinue)) {
        $backendPath = Join-Path $script:SetupRepoRoot 'clagnos.ps1'
        $null = . $backendPath
    }
    $vmEndpoint = Invoke-SetupAzJson -Arguments @('vm','show','--resource-group',$script:SetupResourceGroup,'--name',$script:SetupVmName,'--subscription',$script:SetupSubscriptionId,'-d','--output','json','--only-show-errors') -Action ("resolve FQDN for WinRM staging to VM '{0}'" -f $script:SetupVmName)
    $connectionHost = [string]$vmEndpoint.fqdns
    if ([string]::IsNullOrWhiteSpace($connectionHost)) { $connectionHost = [string]$vmEndpoint.publicIps }
    if ([string]::IsNullOrWhiteSpace($connectionHost)) { throw ("Azure did not return an FQDN or public IP for VM '{0}' WinRM staging." -f $script:SetupVmName) }
    $managerUser = (Get-SetupEnvValue -Key 'VM_ADMIN_USER').Trim()
    $managerPassword = Get-SetupEnvValue -Key 'VM_ADMIN_PASS'
    if ([string]::IsNullOrWhiteSpace($managerUser) -or [string]::IsNullOrWhiteSpace($managerPassword)) { throw ("WinRM staging requires the manager credential in local '{0}'." -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath)) }
    if (Get-Command Add-ClagnosPackageTrustedHost -ErrorAction SilentlyContinue) { Add-ClagnosPackageTrustedHost -HostName $connectionHost }
    $connectionRuntime = [pscustomobject]@{
        ConnectionHost = $connectionHost
        VmPowerShellPort = [string](Get-ClagnosDefaultPowerShellPortText)
        SelectedUserName = $managerUser
        SelectedPassword = $managerPassword
    }
    $session = $null
    $remoteInstaller = 'C:/Windows/Temp/clagnos-anydesk-verified.exe'
    try {
        $session = New-ClagnosPowerShellRemotingSession -Runtime $connectionRuntime
        Write-SetupDoing ("copy the signature-verified AnyDesk installer to VM '{0}' through the authenticated WinRM session" -f $script:SetupVmName)
        Copy-Item -LiteralPath $localInstaller -Destination $remoteInstaller -ToSession $session -Force -ErrorAction Stop
        Write-SetupDoing ("verify the staged AnyDesk file SHA256 and publisher metadata on VM '{0}'" -f $script:SetupVmName)
        $remoteVerification = Invoke-Command -Session $session -ScriptBlock {
            param([string]$Path)
            $file = Get-Item -LiteralPath $Path -ErrorAction Stop
            $version = $file.VersionInfo
            $stream = [System.IO.File]::OpenRead($Path)
            $sha = [System.Security.Cryptography.SHA256]::Create()
            try { $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
            finally { $stream.Dispose(); $sha.Dispose() }
            [pscustomobject]@{
                Hash = [string]$hash
                Company = [string]$version.CompanyName
                Product = [string]$version.ProductName
            }
        } -ArgumentList $remoteInstaller -ErrorAction Stop
        $localHash = Get-SetupSha256Hash -Path $localInstaller
        if (-not [string]::Equals([string]$remoteVerification.Hash,$localHash,[System.StringComparison]::OrdinalIgnoreCase) -or [string]$remoteVerification.Company -ne 'AnyDesk Software GmbH' -or [string]$remoteVerification.Product -notmatch '(?i)^AnyDesk$') {
            throw 'Staged AnyDesk installer did not match the locally signature-verified source SHA256 and publisher metadata.'
        }
        Write-Host ("Staged AnyDesk installer matches the locally Authenticode-verified source on VM '{0}' (SHA256={1})." -f $script:SetupVmName,$localHash) -ForegroundColor Green
    }
    finally {
        if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    }
}

function Get-SetupManagedVm {
    $vms = Invoke-SetupAzJson -Arguments @('vm','list','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("find VM '{0}' in the selected subscription" -f $script:SetupVmName)
    $matches = @($vms | Where-Object { [string]::Equals([string]$_.name,$script:SetupVmName,[System.StringComparison]::OrdinalIgnoreCase) })
    if ($matches.Count -gt 1) { throw ("More than one VM named '{0}' exists in the selected subscription; refusing an ambiguous target." -f $script:SetupVmName) }
    if ($matches.Count -eq 1) {
        $vm = $matches[0]
        $groupName = [string]$vm.resourceGroup
        if ([string]::IsNullOrWhiteSpace($groupName)) { throw ("Azure did not report a resource group for VM '{0}'." -f $script:SetupVmName) }
        $group = Invoke-SetupAzJson -Arguments @('group','show','--name',$groupName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("verify resource group '{0}' is Clagnos-managed" -f $groupName)
        if ([string]$group.tags.'managed-by' -notin @('clagnos','az-vm')) { throw ("VM '{0}' is in resource group '{1}', which is not marked as Clagnos-managed; refusing to operate on it." -f $script:SetupVmName,$groupName) }
        $script:SetupResourceGroup = $groupName
        if (-not [string]::Equals((Get-SetupEnvValue -Key 'SELECTED_RESOURCE_GROUP'),$groupName,[System.StringComparison]::OrdinalIgnoreCase)) { Set-SetupEnvValue -Key 'SELECTED_RESOURCE_GROUP' -Value $groupName }
        return [pscustomobject]@{ Vm = $vm; Group = $group; IsPartial = $false }
    }

    $configuredGroup = (Get-SetupEnvValue -Key 'SELECTED_RESOURCE_GROUP').Trim()
    if ([string]::IsNullOrWhiteSpace($configuredGroup)) { return $null }
    $exists = Invoke-SetupAzText -Arguments @('group','exists','--name',$configuredGroup,'--subscription',$script:SetupSubscriptionId,'--output','tsv','--only-show-errors') -Action ("check configured group '{0}' for an interrupted setup" -f $configuredGroup)
    if (-not [string]::Equals($exists,'true',[System.StringComparison]::OrdinalIgnoreCase)) { return $null }
    $group = Invoke-SetupAzJson -Arguments @('group','show','--name',$configuredGroup,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("verify partial resource group '{0}' is Clagnos-managed" -f $configuredGroup)
    if ([string]$group.tags.'managed-by' -notin @('clagnos','az-vm')) { throw ("Configured group '{0}' is not marked as Clagnos-managed; refusing to reuse or remove it." -f $configuredGroup) }
    $resources = Invoke-SetupAzJson -Arguments @('resource','list','--resource-group',$configuredGroup,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("inspect partial resources in '{0}'" -f $configuredGroup)
    $script:SetupResourceGroup = $configuredGroup
    return [pscustomobject]@{ Vm = $null; Group = $group; Resources = @($resources); IsPartial = $true }
}

function Test-SetupImageMatches {
    param([psobject]$Vm)
    $actual = $Vm.storageProfile.imageReference
    if ($null -eq $actual) { return $false }
    $desiredParts = @($script:SetupVmImage.Split(':'))
    if ($desiredParts.Count -lt 4) { throw "WIN_VM_IMAGE must use publisher:offer:sku:version format." }
    foreach ($pair in @(@('publisher',$desiredParts[0]),@('offer',$desiredParts[1]),@('sku',$desiredParts[2]),@('version',$desiredParts[3]))) {
        if (-not [string]::Equals([string]$actual.($pair[0]),[string]$pair[1],[System.StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    return $true
}

function Get-SetupInfrastructureDrift {
    $resources = Invoke-SetupAzJson -Arguments @('resource','list','--resource-group',$script:SetupResourceGroup,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("audit managed resource inventory for VM '{0}'" -f $script:SetupVmName)
    $types = @($resources | ForEach-Object { [string]$_.type })
    $requiredTypes = @(
        'Microsoft.Compute/virtualMachines',
        'Microsoft.Compute/disks',
        'Microsoft.Network/networkInterfaces',
        'Microsoft.Network/publicIPAddresses',
        'Microsoft.Network/networkSecurityGroups',
        'Microsoft.Network/virtualNetworks'
    )
    $missing = @($requiredTypes | Where-Object { $types -notcontains $_ })
    return $missing
}

function Get-SetupAzureIdSegment {
    param([string]$ResourceId,[string]$Segment)
    $parts = @(([string]$ResourceId).Trim('/').Split('/'))
    for ($index = 0; $index -lt ($parts.Count - 1); $index++) {
        if ([string]::Equals([string]$parts[$index],[string]$Segment,[System.StringComparison]::OrdinalIgnoreCase)) { return [string]$parts[$index + 1] }
    }
    return ''
}

function ConvertTo-SetupPortSet {
    param([string[]]$PortValues)
    $portMap = @{}
    foreach ($value in @($PortValues)) {
        foreach ($tokenRaw in @(([string]$value).Split(','))) {
            $token = ([string]$tokenRaw).Trim()
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            if ($token -match '^(?<first>\d+)-(?<last>\d+)$') {
                $first = 0
                $last = 0
                if (-not [int]::TryParse([string]$Matches.first,[ref]$first) -or -not [int]::TryParse([string]$Matches.last,[ref]$last) -or $first -lt 1 -or $last -gt 65535 -or $first -gt $last -or ($last - $first) -gt 20000) {
                    throw ("TCP port range '{0}' is invalid or exceeds the safe comparison bound." -f $token)
                }
                for ($port = $first; $port -le $last; $port++) { $portMap[[string]$port] = $true }
                continue
            }
            $number = 0
            if (-not [int]::TryParse($token,[ref]$number) -or $number -lt 1 -or $number -gt 65535) { throw ("TCP port '{0}' is invalid in the VC profile." -f $token) }
            $portMap[[string]$number] = $true
        }
    }
    return @($portMap.Keys | Sort-Object { [int]$_ })
}

function Get-SetupNetworkState {
    param([Parameter(Mandatory = $true)][psobject]$Vm)
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $profileUpdates = [ordered]@{}
    $nicReferences = @($Vm.networkProfile.networkInterfaces)
    if ($nicReferences.Count -ne 1) {
        [void]$reasons.Add(("VM network interface count is {0}; exactly one Clagnos-managed NIC is expected" -f $nicReferences.Count))
        return [pscustomobject]@{ DriftReasons = @($reasons.ToArray()); ProfileUpdates = $profileUpdates }
    }

    $nicId = [string]$nicReferences[0].id
    $nicName = Get-SetupAzureIdSegment -ResourceId $nicId -Segment 'networkInterfaces'
    $nicGroup = Get-SetupAzureIdSegment -ResourceId $nicId -Segment 'resourceGroups'
    if ([string]::IsNullOrWhiteSpace($nicName) -or -not [string]::Equals($nicGroup,$script:SetupResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) {
        [void]$reasons.Add('VM NIC reference is missing or is outside the selected managed resource group')
        return [pscustomobject]@{ DriftReasons = @($reasons.ToArray()); ProfileUpdates = $profileUpdates }
    }

    $nic = Invoke-SetupAzJson -Arguments @('network','nic','show','--resource-group',$nicGroup,'--name',$nicName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("inspect NIC '{0}' subnet, NSG, and public IP attachments" -f $nicName)
    $ipConfigurations = @($nic.ipConfigurations)
    if ($ipConfigurations.Count -ne 1) {
        [void]$reasons.Add(("NIC '{0}' has {1} IP configurations; one is expected by the VC profile" -f $nicName,$ipConfigurations.Count))
        return [pscustomobject]@{ DriftReasons = @($reasons.ToArray()); ProfileUpdates = $profileUpdates }
    }
    $ipConfiguration = $ipConfigurations[0]
    $subnetId = [string]$ipConfiguration.subnet.id
    $vnetName = Get-SetupAzureIdSegment -ResourceId $subnetId -Segment 'virtualNetworks'
    $subnetName = Get-SetupAzureIdSegment -ResourceId $subnetId -Segment 'subnets'
    $subnetGroup = Get-SetupAzureIdSegment -ResourceId $subnetId -Segment 'resourceGroups'
    $nsgId = [string]$nic.networkSecurityGroup.id
    $nsgName = Get-SetupAzureIdSegment -ResourceId $nsgId -Segment 'networkSecurityGroups'
    $nsgGroup = Get-SetupAzureIdSegment -ResourceId $nsgId -Segment 'resourceGroups'
    $publicIpId = [string]$ipConfiguration.publicIPAddress.id
    $publicIpName = Get-SetupAzureIdSegment -ResourceId $publicIpId -Segment 'publicIPAddresses'
    $publicIpGroup = Get-SetupAzureIdSegment -ResourceId $publicIpId -Segment 'resourceGroups'
    $diskName = [string]$Vm.storageProfile.osDisk.name
    foreach ($item in @(
        @{ Key = 'NIC_NAME'; Value = $nicName; Group = $nicGroup },
        @{ Key = 'VNET_NAME'; Value = $vnetName; Group = $subnetGroup },
        @{ Key = 'SUBNET_NAME'; Value = $subnetName; Group = $subnetGroup },
        @{ Key = 'NSG_NAME'; Value = $nsgName; Group = $nsgGroup },
        @{ Key = 'PUBLIC_IP_NAME'; Value = $publicIpName; Group = $publicIpGroup },
        @{ Key = 'VM_DISK_NAME'; Value = $diskName; Group = $script:SetupResourceGroup }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$item.Value) -or -not [string]::Equals([string]$item.Group,$script:SetupResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$reasons.Add(("{0} attachment is missing or outside the managed resource group" -f [string]$item.Key))
            continue
        }
        $configured = (Get-SetupEnvValue -Key ([string]$item.Key)).Trim()
        if ([string]::IsNullOrWhiteSpace($configured)) { $profileUpdates[[string]$item.Key] = [string]$item.Value }
        elseif (-not [string]::Equals($configured,[string]$item.Value,[System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$reasons.Add(("{0} '{1}' does not match attached Azure resource '{2}'" -f [string]$item.Key,$configured,[string]$item.Value))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($nsgName)) {
        if ([string]::IsNullOrWhiteSpace((Get-SetupEnvValue -Key 'NSG_RULE_NAME'))) {
            $script:SetupObservedNsgRuleName = ''
        }
        $rules = Invoke-SetupAzJson -Arguments @('network','nsg','rule','list','--resource-group',$script:SetupResourceGroup,'--nsg-name',$nsgName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("read inbound TCP rules for NSG '{0}'" -f $nsgName)
        $configuredRuleName = (Get-SetupEnvValue -Key 'NSG_RULE_NAME').Trim()
        $matchingRules = @($rules | Where-Object {
            [string]::Equals([string]$_.direction,'Inbound',[System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([string]$_.access,'Allow',[System.StringComparison]::OrdinalIgnoreCase) -and
            ([string]$_.protocol -in @('Tcp','*')) -and
            ($(if ([string]::IsNullOrWhiteSpace($configuredRuleName)) { [int]$_.priority -eq 101 } else { [string]::Equals([string]$_.name,$configuredRuleName,[System.StringComparison]::OrdinalIgnoreCase) }) )
        })
        if ($matchingRules.Count -ne 1) { [void]$reasons.Add('the managed inbound TCP NSG rule is missing or ambiguous') }
        else {
            $script:SetupObservedNsgRuleName = [string]$matchingRules[0].name
            if ([string]::IsNullOrWhiteSpace($configuredRuleName)) { $profileUpdates['NSG_RULE_NAME'] = [string]$matchingRules[0].name }
            $expectedPortInputs = @((Get-SetupEnvValue -Key 'TCP_PORTS'),(Get-SetupEnvValue -Key 'VM_SSH_PORT'),(Get-SetupEnvValue -Key 'VM_RDP_PORT'))
            $actualPortInputs = @()
            if ($null -ne $matchingRules[0].destinationPortRanges) { $actualPortInputs += @($matchingRules[0].destinationPortRanges) }
            if ($null -ne $matchingRules[0].destinationPortRange) { $actualPortInputs += [string]$matchingRules[0].destinationPortRange }
            $expectedPortSet = @(ConvertTo-SetupPortSet -PortValues $expectedPortInputs)
            $actualPortSet = @(ConvertTo-SetupPortSet -PortValues $actualPortInputs)
            if (($expectedPortSet -join ',') -ne ($actualPortSet -join ',')) { [void]$reasons.Add('inbound TCP ports do not match TCP_PORTS, VM_SSH_PORT, and VM_RDP_PORT') }
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($publicIpName)) {
        $publicIp = Invoke-SetupAzJson -Arguments @('network','public-ip','show','--resource-group',$script:SetupResourceGroup,'--name',$publicIpName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("verify public IP '{0}' SKU, allocation, and DNS" -f $publicIpName)
        if (-not [string]::Equals([string]$publicIp.sku.name,'Standard',[System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$publicIp.publicIPAllocationMethod,'Static',[System.StringComparison]::OrdinalIgnoreCase) -or [string]::IsNullOrWhiteSpace([string]$publicIp.dnsSettings.domainNameLabel)) {
            [void]$reasons.Add('public IP must remain Standard, static, and have its Clagnos DNS label')
        }
    }
    return [pscustomobject]@{ DriftReasons = @($reasons.ToArray()); ProfileUpdates = $profileUpdates }
}

function Assert-SetupTargetContract {
    param([Parameter(Mandatory = $true)][psobject]$Target,[switch]$ApplyFixes)
    $vm = Invoke-SetupAzJson -Arguments @('vm','show','--resource-group',$script:SetupResourceGroup,'--name',$script:SetupVmName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("inspect VM '{0}' settings" -f $script:SetupVmName)
    $incompatibleReasons = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::Equals([string]$vm.location,$script:SetupVmRegion,[System.StringComparison]::OrdinalIgnoreCase)) { [void]$incompatibleReasons.Add(("region {0} does not match {1}" -f [string]$vm.location,$script:SetupVmRegion)) }
    if (-not [string]::Equals([string]$vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { [void]$incompatibleReasons.Add(("OS {0} is not Windows" -f [string]$vm.storageProfile.osDisk.osType)) }
    if (-not (Test-SetupImageMatches -Vm $vm)) { [void]$incompatibleReasons.Add('OS image does not match WIN_VM_IMAGE') }
    $missingResourceTypes = @(Get-SetupInfrastructureDrift)
    foreach ($missingType in @($missingResourceTypes)) { [void]$incompatibleReasons.Add(("managed resource inventory is missing {0}" -f $missingType)) }
    $networkState = [pscustomobject]@{ DriftReasons = @(); ProfileUpdates = [ordered]@{} }
    if ($missingResourceTypes.Count -eq 0) {
        $networkState = Get-SetupNetworkState -Vm $vm
        foreach ($networkReason in @($networkState.DriftReasons)) { [void]$incompatibleReasons.Add([string]$networkReason) }
    }

    $diskName = [string]$vm.storageProfile.osDisk.name
    if ([string]::IsNullOrWhiteSpace($diskName)) { throw ("Azure did not report the OS disk name for VM '{0}'." -f $script:SetupVmName) }
    $disk = Invoke-SetupAzJson -Arguments @('disk','show','--resource-group',$script:SetupResourceGroup,'--name',$diskName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("verify OS disk '{0}' size" -f $diskName)
    $diskSize = 0
    if (-not [int]::TryParse([string]$disk.diskSizeGb,[ref]$diskSize)) { throw ("Azure did not report a numeric OS disk size for VM '{0}'." -f $script:SetupVmName) }
    if ($diskSize -gt $script:SetupVmDiskSizeGb) {
        [void]$incompatibleReasons.Add(("OS disk is {0} GB; profile requires {1} GB and Azure cannot shrink it" -f $diskSize,$script:SetupVmDiskSizeGb))
    }
    if (-not [string]::Equals([string]$disk.sku.name,(Get-SetupEnvValue -Key 'VM_STORAGE_SKU'),[System.StringComparison]::OrdinalIgnoreCase)) { [void]$incompatibleReasons.Add('OS disk storage SKU does not match VM_STORAGE_SKU') }

    $actualSecurityType = [string]$vm.securityProfile.securityType
    if ([string]::IsNullOrWhiteSpace($actualSecurityType) -and $script:SetupVmSecurityType -eq 'Standard') { $actualSecurityType = 'Standard' }
    $actualSecureBoot = $false
    $actualVtpm = $false
    if ($null -ne $vm.securityProfile -and $null -ne $vm.securityProfile.uefiSettings) {
        $actualSecureBoot = [bool]$vm.securityProfile.uefiSettings.secureBootEnabled
        $actualVtpm = [bool]$vm.securityProfile.uefiSettings.vTpmEnabled
    }
    if (-not [string]::Equals($actualSecurityType,$script:SetupVmSecurityType,[System.StringComparison]::OrdinalIgnoreCase) -or $actualSecureBoot -ne $script:SetupVmSecureBoot -or $actualVtpm -ne $script:SetupVmVtpm) {
        [void]$incompatibleReasons.Add('security type, secure boot, or vTPM does not match the VC profile')
    }
    if ($incompatibleReasons.Count -gt 0) {
        $reason = $incompatibleReasons -join '; '
        if ($ApplyFixes) { return [pscustomobject]@{ RequiresRebuild = $true; Reason = $reason } }
        throw ("VM '{0}' requires a clean recreate to match its profile: {1}." -f $script:SetupVmName,$reason)
    }

    $currentSize = [string]$vm.hardwareProfile.vmSize
    if (-not [string]::Equals($currentSize,$script:SetupVmSize,[System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $ApplyFixes) { throw ("VM '{0}' uses '{1}'; setup will resize it to '{2}'." -f $script:SetupVmName,$currentSize,$script:SetupVmSize) }
        Invoke-SetupCg -Arguments @('resize','--auto','--windows','--vm-size',$script:SetupVmSize,'--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("resize VM '{0}' to {1}" -f $script:SetupVmName,$script:SetupVmSize)
    }
    if ($diskSize -lt $script:SetupVmDiskSizeGb) {
        if (-not $ApplyFixes) { throw ("VM '{0}' disk is {1} GB; setup will expand it to {2} GB." -f $script:SetupVmName,$diskSize,$script:SetupVmDiskSizeGb) }
        Invoke-SetupCg -Arguments @('resize','--auto','--windows','--disk-size',('{0}gb' -f $script:SetupVmDiskSizeGb),'--expand','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("expand VM '{0}' OS disk to {1} GB" -f $script:SetupVmName,$script:SetupVmDiskSizeGb)
    }

    $hibernationEnabled = $false
    if ($null -ne $vm.additionalCapabilities -and $null -ne $vm.additionalCapabilities.hibernationEnabled) { $hibernationEnabled = [bool]$vm.additionalCapabilities.hibernationEnabled }
    if ($hibernationEnabled -ne $script:SetupVmHibernation) {
        if (-not $ApplyFixes) { throw ("VM '{0}' hibernation state differs from its profile; setup will reconcile it." -f $script:SetupVmName) }
        $hibernationValue = if ($script:SetupVmHibernation) { 'on' } else { 'off' }
        Invoke-SetupCg -Arguments @('set','--auto','--windows','--hibernation',$hibernationValue,'--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("set VM '{0}' hibernation to {1}" -f $script:SetupVmName,$hibernationValue)
    }

    $nestedEnabled = $false
    if ($null -ne $vm.additionalCapabilities -and $null -ne $vm.additionalCapabilities.nestedVirtualizationEnabled) { $nestedEnabled = [bool]$vm.additionalCapabilities.nestedVirtualizationEnabled }
    if ($nestedEnabled -ne $script:SetupVmNestedVirtualization) {
        if (-not $ApplyFixes) { throw ("VM '{0}' nested-virtualization state differs from its profile; setup will reconcile it." -f $script:SetupVmName) }
        $nestedValue = if ($script:SetupVmNestedVirtualization) { 'on' } else { 'off' }
        Invoke-SetupCg -Arguments @('set','--auto','--windows','--nested-virtualization',$nestedValue,'--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("set VM '{0}' nested virtualization to {1}" -f $script:SetupVmName,$nestedValue)
    }
    return [pscustomobject]@{ RequiresRebuild = $false; Reason = ''; ProfileUpdates = $networkState.ProfileUpdates }
}

function Get-SetupVmPowerState {
    $instance = Invoke-SetupAzJson -Arguments @('vm','get-instance-view','--resource-group',$script:SetupResourceGroup,'--name',$script:SetupVmName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("read power state for VM '{0}'" -f $script:SetupVmName)
    $statuses = @()
    if ($null -ne $instance.instanceView -and $null -ne $instance.instanceView.statuses) { $statuses = @($instance.instanceView.statuses) }
    elseif ($null -ne $instance.statuses) { $statuses = @($instance.statuses) }
    $status = @($statuses | Where-Object { [string]$_.code -like 'PowerState/*' } | Select-Object -First 1)
    if ($status.Count -eq 0) { return 'unknown' }
    return [string]$status[0].displayStatus
}

function Invoke-SetupConnectionChecks {
    $common = @('--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId,'--user',$script:SetupVmAdminUser,'--test')
    Invoke-SetupCg -Arguments (@('connect','--rdp') + $common) -Action ("test RDP connectivity to VM '{0}'" -f $script:SetupVmName)
    Invoke-SetupCg -Arguments (@('connect','--ssh') + $common) -Action ("test SSH connectivity to VM '{0}'" -f $script:SetupVmName)
    Invoke-SetupCg -Arguments (@('connect','--powershell') + $common) -Action ("test WinRM PowerShell remoting to VM '{0}'" -f $script:SetupVmName)
}

function Invoke-SetupCreate {
    param([switch]$ConfigureOnly)
    $config = @{
        SELECTED_VM_OS = $script:SetupVmOs
        SELECTED_VM_NAME = $script:SetupVmName
        SELECTED_RESOURCE_GROUP = ''
        SELECTED_AZURE_REGION = $script:SetupVmRegion
        WIN_VM_IMAGE = $script:SetupVmImage
        WIN_VM_SIZE = $script:SetupVmSize
        WIN_VM_DISK_SIZE_GB = [string]$script:SetupVmDiskSizeGb
        VM_ENABLE_HIBERNATION = ([string]$script:SetupVmHibernation).ToLowerInvariant()
        VM_ENABLE_NESTED_VIRTUALIZATION = ([string]$script:SetupVmNestedVirtualization).ToLowerInvariant()
        VM_SECURITY_TYPE = $script:SetupVmSecurityType
        VM_ENABLE_SECURE_BOOT = ([string]$script:SetupVmSecureBoot).ToLowerInvariant()
        VM_ENABLE_VTPM = ([string]$script:SetupVmVtpm).ToLowerInvariant()
    }
    if (-not $ConfigureOnly) {
        foreach ($key in @($config.Keys)) { Set-SetupEnvValue -Key ([string]$key) -Value ([string]$config[$key]) }
    }
    $createArgs = @('create','--auto','--windows','--vm-name',$script:SetupVmName,'--vm-region',$script:SetupVmRegion,'--vm-size',$script:SetupVmSize,'--subscription-id',$script:SetupSubscriptionId)
    if ($ConfigureOnly) { $createArgs += @('--step','configure') }
    $action = if ($ConfigureOnly) { "run read-only create configuration preflight for VM '$($script:SetupVmName)'" } else { "create fresh managed VM '$($script:SetupVmName)' from its saved VC profile" }
    Invoke-SetupCg -Arguments $createArgs -Action $action
}

function Invoke-SetupRemoveTarget {
    param([string]$Reason)
    $removeScript = Join-Path $script:SetupRepoRoot 'remove-vc.ps1'
    if (-not (Test-Path -LiteralPath $removeScript -PathType Leaf)) { throw "The shared remove-vc.ps1 runner was not found; cannot safely recreate this target." }
    $hostCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $hostCommand) { $hostCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue }
    if (-not $hostCommand) { throw 'PowerShell was not found for the bounded remove/recreate workflow.' }
    Write-SetupDoing ("purge managed VM '{0}' before profile-driven recreate: {1}" -f $script:SetupVmName,$Reason)
    & $hostCommand.Source -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $removeScript -VmName $script:SetupVmName -SubscriptionId $script:SetupSubscriptionId
    if ($LASTEXITCODE -ne 0) { throw ("remove-vc.ps1 failed while preparing a clean target for VM '{0}' (exit {1})." -f $script:SetupVmName,$LASTEXITCODE) }
    $script:SetupResourceGroup = ''
    Set-SetupEnvValue -Key 'SELECTED_RESOURCE_GROUP' -Value ''
}

try {
    Assert-SetupElevatedSession
    if (-not (Test-Path -LiteralPath $script:SetupGlobalEnvPath -PathType Leaf)) { throw "Local clagnos.env was not found. Run cg.cmd configure and select an Azure subscription before setup." }
    if (-not (Test-Path -LiteralPath $script:SetupVmEnvPath -PathType Leaf)) {
        $vmTemplate = Join-Path $script:SetupRepoRoot 'vc.env.example'
        if (-not (Test-Path -LiteralPath $vmTemplate -PathType Leaf)) { throw 'vc.env.example was not found.' }
        Copy-Item -LiteralPath $vmTemplate -Destination $script:SetupVmEnvPath -ErrorAction Stop
        Set-SetupEnvValue -Key 'SELECTED_VM_NAME' -Value $script:SetupVmName
    }
    if (-not (Test-Path -LiteralPath $script:SetupLauncherPath -PathType Leaf)) { throw "cg.cmd was not found at the repository root." }
    Initialize-SetupDesiredConfiguration
    Push-Location $script:SetupRepoRoot
    $script:SetupDidPushLocation = $true
    Start-Transcript -LiteralPath $script:SetupTranscriptPath -Force | Out-Null
    $script:SetupTranscriptStarted = $true
    Write-Host ("Setup transcript: {0}" -f $script:SetupTranscriptPath) -ForegroundColor DarkGray

    $script:SetupSubscriptionId = if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId.Trim() } else { (Get-SetupEnvValue -Key 'SELECTED_AZURE_SUBSCRIPTION_ID').Trim() }
    if ([string]::IsNullOrWhiteSpace($script:SetupSubscriptionId)) { throw 'Set SELECTED_AZURE_SUBSCRIPTION_ID in clagnos.env or pass -SubscriptionId.' }
    $account = Invoke-SetupAzJson -Arguments @('account','show','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action 'verify Azure CLI authentication and selected subscription'
    if (-not [string]::Equals([string]$account.id,$script:SetupSubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Azure CLI returned a subscription id that does not match the requested setup subscription.'
    }
    Write-Host ("Target: subscription {0}; VM {1}; {2}; {3}; {4}; {5} GB OS disk." -f [string]$account.name,$script:SetupVmName,$script:SetupVmOs,$script:SetupVmRegion,$script:SetupVmSize,$script:SetupVmDiskSizeGb) -ForegroundColor Cyan

    $target = Get-SetupManagedVm
    if ($PreflightOnly) {
        if ($null -eq $target) {
            $configuredGroup = (Get-SetupEnvValue -Key 'SELECTED_RESOURCE_GROUP').Trim()
            if (-not [string]::IsNullOrWhiteSpace($configuredGroup)) {
                $groupExists = Invoke-SetupAzText -Arguments @('group','exists','--name',$configuredGroup,'--subscription',$script:SetupSubscriptionId,'--output','tsv','--only-show-errors') -Action ("check stale configured group '{0}' during preflight" -f $configuredGroup)
                if ([string]::Equals($groupExists,'true',[System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ("Preflight found an interrupted managed resource group '{0}' with no VM. A normal setup run will purge the partial group and recreate the target." -f $configuredGroup)
                }
            }
            Invoke-SetupCreate -ConfigureOnly
        }
        elseif ([bool]$target.IsPartial) {
            throw ("Preflight found an interrupted managed resource group '{0}' with no VM. A normal setup run will purge the partial group and recreate the target." -f $script:SetupResourceGroup)
        }
        else {
            Assert-SetupTargetContract -Target $target
            Write-Host ("Preflight passed for existing managed VM '{0}' in '{1}'." -f $script:SetupVmName,$script:SetupResourceGroup) -ForegroundColor Green
        }
        return
    }

    if (($null -eq $target -or [bool]$target.IsPartial) -and $ResumeAtPackageStage) {
        throw ("-ResumeAtPackageStage requires an existing managed VM named '{0}'; no resources were changed." -f $script:SetupVmName)
    }
    if ($null -ne $target -and [bool]$target.IsPartial) {
        Invoke-SetupRemoveTarget -Reason 'finish cleanup of an interrupted create before provisioning the complete target'
        $target = $null
    }
    if ($null -eq $target) {
        Invoke-SetupRemoveTarget -Reason 'verify and clean any prior partial resources before fresh provisioning'
        Invoke-SetupCreate
        $target = Get-SetupManagedVm
        if ($null -eq $target -or [bool]$target.IsPartial) { throw ("The create command completed but Azure inventory did not find managed VM '{0}'." -f $script:SetupVmName) }
    }
    if ($ResumeAtPackageStage) {
        $contractResult = Assert-SetupTargetContract -Target $target
    }
    else {
        $contractResult = Assert-SetupTargetContract -Target $target -ApplyFixes
        if ([bool]$contractResult.RequiresRebuild) {
            Invoke-SetupRemoveTarget -Reason ([string]$contractResult.Reason)
            Invoke-SetupCreate
            $target = Get-SetupManagedVm
            if ($null -eq $target -or [bool]$target.IsPartial) { throw ("Profile-driven recreate did not produce managed VM '{0}'." -f $script:SetupVmName) }
            $postCreateContract = Assert-SetupTargetContract -Target $target
            if ([bool]$postCreateContract.RequiresRebuild) { throw ("VM '{0}' still differs from its profile after a fresh create: {1}." -f $script:SetupVmName,[string]$postCreateContract.Reason) }
            $contractResult = $postCreateContract
        }
    }
    if ($null -ne $contractResult.ProfileUpdates -and @($contractResult.ProfileUpdates.Keys).Count -gt 0) {
        Write-SetupDoing ("persist Azure-verified network resource names into '{0}'" -f [System.IO.Path]::GetFileName($script:SetupVmEnvPath))
        foreach ($key in @($contractResult.ProfileUpdates.Keys)) { Set-SetupEnvValue -Key ([string]$key) -Value ([string]$contractResult.ProfileUpdates[$key]) }
    }

    if ($ResumeAtPackageStage) {
        Write-Host 'Resume mode: reusing the existing managed VM and continuing at package prerequisites; create, initialize, and the first vm-update pass are skipped.' -ForegroundColor Yellow
    }
    else {
        Invoke-SetupCg -Arguments @('initialize','--auto','--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("run all enabled vm-init tasks on VM '{0}'" -f $script:SetupVmName)
    }

    Set-SetupTemporaryEnvValues -Values @{ PACKAGE_TRANSPORT = 'winrm' }
    try {
        $chocolateyStatus = Get-SetupPackageStatus -PackageId 'chocolatey' -DisplayName 'Chocolatey'
        if ($chocolateyStatus -eq 'not-installed') {
            Invoke-SetupCg -Arguments @('package','--action','install','--catalog','builtin','--package','chocolatey','--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action "bootstrap Chocolatey over WinRM before installing Chocolatey-managed packages"
        }
        else { Write-Host 'Chocolatey is already installed; keeping the current CLI version.' -ForegroundColor Green }

        $sysinternalsStatus = Get-SetupPackageStatus -PackageId 'sysinternals' -DisplayName 'Sysinternals'
        if ($sysinternalsStatus -eq 'not-installed') {
            Invoke-SetupCg -Arguments @('package','--action','install','--catalog','builtin','--package','sysinternals','--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action "ensure the Sysinternals prerequisite is installed over WinRM for vm-update tasks"
        }
        else { Write-Host 'Sysinternals is already installed; keeping the current package version.' -ForegroundColor Green }
    }
    finally { Restore-SetupOriginalEnv }

    if (-not $ResumeAtPackageStage) {
        Invoke-SetupCg -Arguments @('update','--step','vm-update','--auto','--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("run all enabled vm-update tasks on VM '{0}'" -f $script:SetupVmName)
    }
    else { Write-Host 'Resume mode: vm-init and the first vm-update pass are already complete; continuing to package setup.' -ForegroundColor Yellow }

    Set-SetupTemporaryEnvValues -Values @{ PACKAGE_TRANSPORT = 'winrm' }
    try {
        $anyDeskStatus = Get-SetupPackageStatus -PackageId 'anydesk' -DisplayName 'AnyDesk'
        if ($anyDeskStatus -eq 'not-installed') {
            try { Stage-SetupAnyDeskInstaller }
            catch {
                $warning = "AnyDesk installer staging failed: $([string]$_.Exception.Message)"
                $script:SetupPackageWarnings += $warning
                Write-Warning 'AnyDesk installer staging failed; continuing setup-all so independent packages can still be prepared.'
                Write-Warning $warning
            }
        }
        else { Write-Host 'AnyDesk is already installed; no installer file needs staging.' -ForegroundColor Green }
        $packageSetupResult = Invoke-SetupCgCaptured -Arguments @('package','--action','setup-all','--catalog','all','--yes','--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("run reviewed setup-all for enabled builtin and custom packages over WinRM on VM '{0}'" -f $script:SetupVmName)
        if ([int]$packageSetupResult.ExitCode -ne 0) {
            $script:SetupPackageWarnings = @($packageSetupResult.Output | Where-Object { [string]$_ -match '(?i)Package setup (?:failed|skipped) for|Package setup-all left one or more enabled packages unverified' } | Select-Object -Unique)
            if ($script:SetupPackageWarnings.Count -eq 0) { $script:SetupPackageWarnings = @("Package setup-all returned exit code $([int]$packageSetupResult.ExitCode).") }
            Write-Warning 'Package setup-all reported unverified packages; continuing with final update, connection, and Azure health checks.'
        }
    }
    finally { Restore-SetupOriginalEnv }

    Invoke-SetupCg -Arguments @('update','--step','vm-update','--auto','--windows','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("rerun vm-update tasks after packages are installed and verify the final idempotent state for '{0}'" -f $script:SetupVmName)

    $powerState = Get-SetupVmPowerState
    if ($powerState -eq 'unknown') { throw ("Azure did not report a power state for VM '{0}'; refusing to issue a lifecycle action without a verified current state." -f $script:SetupVmName) }
    if ($powerState -notmatch '(?i)^VM running$') {
        Invoke-SetupCg -Arguments @('do','--vm-action=start','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("start VM '{0}' after guest setup" -f $script:SetupVmName)
    }
    $powerState = Get-SetupVmPowerState
    if ($powerState -notmatch '(?i)^VM running$') { throw ("VM '{0}' is not running after setup (Azure reports '{1}')." -f $script:SetupVmName,$powerState) }

    Invoke-SetupConnectionChecks
    Invoke-SetupCg -Arguments @('do','--vm-action=status','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("verify final Azure status for VM '{0}'" -f $script:SetupVmName)
    Invoke-SetupCgRedacted -Arguments @('show','--group',$script:SetupResourceGroup,'--vm-name',$script:SetupVmName,'--subscription-id',$script:SetupSubscriptionId) -Action ("review final Clagnos summary for VM '{0}'" -f $script:SetupVmName)

    $finalVm = Invoke-SetupAzJson -Arguments @('vm','show','--resource-group',$script:SetupResourceGroup,'--name',$script:SetupVmName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("read final VM properties for '{0}'" -f $script:SetupVmName)
    $finalDisk = Invoke-SetupAzJson -Arguments @('disk','show','--resource-group',$script:SetupResourceGroup,'--name',[string]$finalVm.storageProfile.osDisk.name,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("read final OS disk properties for '{0}'" -f $script:SetupVmName)
    $finalHibernation = $false
    if ($null -ne $finalVm.additionalCapabilities -and $null -ne $finalVm.additionalCapabilities.hibernationEnabled) { $finalHibernation = [bool]$finalVm.additionalCapabilities.hibernationEnabled }
    $finalNested = $false
    if ($null -ne $finalVm.additionalCapabilities -and $null -ne $finalVm.additionalCapabilities.nestedVirtualizationEnabled) { $finalNested = [bool]$finalVm.additionalCapabilities.nestedVirtualizationEnabled }
    $finalSecureBoot = $false
    $finalVtpm = $false
    if ($null -ne $finalVm.securityProfile -and $null -ne $finalVm.securityProfile.uefiSettings) {
        $finalSecureBoot = [bool]$finalVm.securityProfile.uefiSettings.secureBootEnabled
        $finalVtpm = [bool]$finalVm.securityProfile.uefiSettings.vTpmEnabled
    }
    $actualSecurityType = [string]$finalVm.securityProfile.securityType
    if ([string]::IsNullOrWhiteSpace($actualSecurityType) -and $script:SetupVmSecurityType -eq 'Standard') { $actualSecurityType = 'Standard' }
    if (-not [string]::Equals([string]$finalVm.hardwareProfile.vmSize,$script:SetupVmSize,[System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$finalVm.location,$script:SetupVmRegion,[System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$finalVm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase) -or [int]$finalDisk.diskSizeGb -ne $script:SetupVmDiskSizeGb -or -not [string]::Equals([string]$finalDisk.sku.name,(Get-SetupEnvValue -Key 'VM_STORAGE_SKU'),[System.StringComparison]::OrdinalIgnoreCase) -or $finalHibernation -ne $script:SetupVmHibernation -or $finalNested -ne $script:SetupVmNestedVirtualization -or $finalSecureBoot -ne $script:SetupVmSecureBoot -or $finalVtpm -ne $script:SetupVmVtpm -or -not [string]::Equals($actualSecurityType,$script:SetupVmSecurityType,[System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-SetupImageMatches -Vm $finalVm)) {
        throw 'Final Azure configuration verification failed for image, VM SKU, location, OS, disk, security, hibernation, or nested virtualization.'
    }
    if (@(Get-SetupInfrastructureDrift).Count -gt 0) { throw 'Final Azure configuration is missing one or more managed network or compute resources.' }
    $finalNetworkState = Get-SetupNetworkState -Vm $finalVm
    if (@($finalNetworkState.DriftReasons).Count -gt 0) { throw ("Final Azure network configuration failed verification: {0}." -f (@($finalNetworkState.DriftReasons) -join '; ')) }
    if ((Get-SetupVmPowerState) -notmatch '(?i)^VM running$') { throw ("VM '{0}' stopped during final verification." -f $script:SetupVmName) }
    Write-Host ''
    if ($script:SetupPackageWarnings.Count -gt 0) {
        Write-Host ("VM '{0}' is running in '{1}'; Azure properties, vm-init, vm-update, RDP, SSH, and WinRM checks completed, with package setup warnings." -f $script:SetupVmName,$script:SetupResourceGroup) -ForegroundColor Yellow
        foreach ($warning in @($script:SetupPackageWarnings)) { Write-Host ('- {0}' -f [string]$warning) -ForegroundColor Yellow }
        if (-not $script:SetupVmNestedVirtualization) { Write-Host 'Nested virtualization is disabled in this VC profile.' -ForegroundColor Yellow }
    }
    else {
        Write-Host ("VM '{0}' is ready and running in '{1}'. Azure properties, vm-init, vm-update, package setup, RDP, SSH, and WinRM checks completed." -f $script:SetupVmName,$script:SetupResourceGroup) -ForegroundColor Green
        if (-not $script:SetupVmNestedVirtualization) { Write-Host 'Nested virtualization is disabled in this VC profile.' -ForegroundColor Yellow }
    }
}
catch {
    $script:SetupFailed = $true
    Write-Host ''
    Write-Host ("Setup for VM '{0}' did not complete." -f $script:SetupVmName) -ForegroundColor Red
    Write-Host ([string]$_.Exception.Message) -ForegroundColor Red
}
finally {
    Restore-SetupOriginalEnv
    if ($script:SetupTranscriptStarted) { Stop-Transcript | Out-Null }
    if ($script:SetupDidPushLocation) { Pop-Location }
}
if ($script:SetupFailed -or $script:SetupPackageWarnings.Count -gt 0) { exit 1 }
