[CmdletBinding()]
param(
    [switch]$PreflightOnly,
    [switch]$ResumeAtPackageStage,
    [string]$SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:SetupRepoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$script:SetupGlobalEnvPath = Join-Path $script:SetupRepoRoot 'clagnos.env'
$script:SetupVmEnvPath = Join-Path $script:SetupRepoRoot 'vc2.env'
$script:SetupLauncherPath = Join-Path $script:SetupRepoRoot 'cg.cmd'
$script:SetupTemporaryEnvValues = @{}
$script:SetupSubscriptionId = ''
$script:SetupResourceGroup = ''
$script:SetupDidPushLocation = $false
$script:SetupFailed = $false
$script:SetupPackageWarnings = @()
$script:SetupTranscriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-setup-vc2-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$script:SetupTranscriptStarted = $false

function Write-SetupDoing {
    param([Parameter(Mandatory = $true)][string]$Action)
    Write-Host ("Doing: {0}" -f $Action) -ForegroundColor Cyan
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
    $output = @(& $script:SetupLauncherPath @Arguments 2>&1 | ForEach-Object { [string]$_ })
    $exitCode = $LASTEXITCODE
    foreach ($line in @($output)) {
        $safeLine = [regex]::Replace([string]$line,'(?i)(password|credential|secret|token)(\s*[:=]\s*)\S+','$1$2[redacted]')
        Write-Host $safeLine
    }
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
    $arguments = @('package','--action','status','--catalog','builtin','--package',$PackageId,'--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId)
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
    $stagingRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'clagnos-vc2-anydesk'
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
    $vmEndpoint = Invoke-SetupAzJson -Arguments @('vm','show','--resource-group',$script:SetupResourceGroup,'--name','vc2','--subscription',$script:SetupSubscriptionId,'-d','--output','json','--only-show-errors') -Action "resolve FQDN for WinRM staging to VM 'vc2'"
    $connectionHost = [string]$vmEndpoint.fqdns
    if ([string]::IsNullOrWhiteSpace($connectionHost)) { $connectionHost = [string]$vmEndpoint.publicIps }
    if ([string]::IsNullOrWhiteSpace($connectionHost)) { throw "Azure did not return an FQDN or public IP for VM 'vc2' WinRM staging." }
    $managerUser = (Get-SetupEnvValue -Key 'VM_ADMIN_USER').Trim()
    $managerPassword = Get-SetupEnvValue -Key 'VM_ADMIN_PASS'
    if ([string]::IsNullOrWhiteSpace($managerUser) -or [string]::IsNullOrWhiteSpace($managerPassword)) { throw "WinRM staging requires the manager credential in local 'vc2.env'." }
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
        Write-SetupDoing "copy the signature-verified AnyDesk installer to VM 'vc2' through the authenticated WinRM session"
        Copy-Item -LiteralPath $localInstaller -Destination $remoteInstaller -ToSession $session -Force -ErrorAction Stop
        Write-SetupDoing "verify the staged AnyDesk file SHA256 and publisher metadata on VM 'vc2'"
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
        Write-Host ("Staged AnyDesk installer matches the locally Authenticode-verified source on VM 'vc2' (SHA256={0})." -f $localHash) -ForegroundColor Green
    }
    finally {
        if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    }
}

function Get-SetupManagedVc2 {
    $vms = Invoke-SetupAzJson -Arguments @('vm','list','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action "find VM 'vc2' in the selected subscription"
    $matches = @($vms | Where-Object { [string]::Equals([string]$_.name,'vc2',[System.StringComparison]::OrdinalIgnoreCase) })
    if ($matches.Count -gt 1) { throw "More than one VM named 'vc2' exists in the selected subscription; refusing an ambiguous target." }
    if ($matches.Count -eq 0) { return $null }
    $vm = $matches[0]
    $groupName = [string]$vm.resourceGroup
    if ([string]::IsNullOrWhiteSpace($groupName)) { throw "Azure did not report a resource group for VM 'vc2'." }
    $group = Invoke-SetupAzJson -Arguments @('group','show','--name',$groupName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("verify resource group '{0}' is Clagnos-managed" -f $groupName)
    $managedBy = [string]$group.tags.'managed-by'
    if ($managedBy -notin @('clagnos','az-vm')) { throw ("VM 'vc2' is in resource group '{0}', which is not marked as Clagnos-managed; refusing to operate on it." -f $groupName) }
    $script:SetupResourceGroup = $groupName
    return [pscustomobject]@{ Vm = $vm; Group = $group }
}

function Assert-SetupTargetContract {
    param([Parameter(Mandatory = $true)][psobject]$Target,[switch]$ApplyFixes)
    $vm = Invoke-SetupAzJson -Arguments @('vm','show','--resource-group',$script:SetupResourceGroup,'--name','vc2','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action "inspect VM 'vc2' settings"
    if (-not [string]::Equals([string]$vm.location,'germanywestcentral',[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("VM 'vc2' is in '{0}'; this setup requires germanywestcentral and cannot move an existing VM between regions." -f [string]$vm.location)
    }
    if (-not [string]::Equals([string]$vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("VM 'vc2' has OS type '{0}'; this setup is Windows-only." -f [string]$vm.storageProfile.osDisk.osType)
    }
    $currentSize = [string]$vm.hardwareProfile.vmSize
    if (-not [string]::Equals($currentSize,'Standard_B2s_v2',[System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not $ApplyFixes) { throw ("VM 'vc2' uses '{0}'; rerun without -PreflightOnly to resize it to Standard_B2s_v2." -f $currentSize) }
        Invoke-SetupCg -Arguments @('resize','--auto','--windows','--vm-size','Standard_B2s_v2','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "resize VM 'vc2' to Standard_B2s_v2"
    }
    $diskName = [string]$vm.storageProfile.osDisk.name
    if ([string]::IsNullOrWhiteSpace($diskName)) { throw "Azure did not report the OS disk name for VM 'vc2'." }
    $disk = Invoke-SetupAzJson -Arguments @('disk','show','--resource-group',$script:SetupResourceGroup,'--name',$diskName,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action ("verify OS disk '{0}' size" -f $diskName)
    $diskSize = 0
    if (-not [int]::TryParse([string]$disk.diskSizeGb,[ref]$diskSize)) { throw "Azure did not report a numeric OS disk size for VM 'vc2'." }
    if ($diskSize -gt 160) { throw ("VM 'vc2' already has a {0} GB OS disk; this setup cannot shrink it to 160 GB." -f $diskSize) }
    if ($diskSize -lt 160) {
        if (-not $ApplyFixes) { throw ("VM 'vc2' has a {0} GB OS disk; rerun without -PreflightOnly to expand it to 160 GB." -f $diskSize) }
        Invoke-SetupCg -Arguments @('resize','--auto','--windows','--disk-size','160gb','--expand','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "expand VM 'vc2' OS disk to 160 GB"
    }
    $hibernationEnabled = $false
    if ($null -ne $vm.additionalCapabilities -and $null -ne $vm.additionalCapabilities.hibernationEnabled) { $hibernationEnabled = [bool]$vm.additionalCapabilities.hibernationEnabled }
    if (-not $hibernationEnabled) {
        if (-not $ApplyFixes) { throw "VM 'vc2' does not currently have hibernation enabled; rerun without -PreflightOnly to enable it." }
        Invoke-SetupCg -Arguments @('set','--auto','--windows','--hibernation','on','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "enable hibernation for VM 'vc2'"
    }
}

function Get-SetupVmPowerState {
    $instance = Invoke-SetupAzJson -Arguments @('vm','get-instance-view','--resource-group',$script:SetupResourceGroup,'--name','vc2','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action "read power state for VM 'vc2'"
    $statuses = @()
    if ($null -ne $instance.instanceView -and $null -ne $instance.instanceView.statuses) { $statuses = @($instance.instanceView.statuses) }
    elseif ($null -ne $instance.statuses) { $statuses = @($instance.statuses) }
    $status = @($statuses | Where-Object { [string]$_.code -like 'PowerState/*' } | Select-Object -First 1)
    if ($status.Count -eq 0) { return 'unknown' }
    return [string]$status[0].displayStatus
}

function Invoke-SetupConnectionChecks {
    $common = @('--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId,'--user','manager','--test')
    Invoke-SetupCg -Arguments (@('connect','--rdp') + $common) -Action "test RDP connectivity to VM 'vc2'"
    Invoke-SetupCg -Arguments (@('connect','--ssh') + $common) -Action "test SSH connectivity to VM 'vc2'"
    Invoke-SetupCg -Arguments (@('connect','--powershell') + $common) -Action "test WinRM PowerShell remoting to VM 'vc2'"
}

function Invoke-SetupCreate {
    param([switch]$ConfigureOnly)
    $config = @{
        SELECTED_VM_OS = 'windows'
        SELECTED_VM_NAME = 'vc2'
        SELECTED_RESOURCE_GROUP = ''
        SELECTED_AZURE_REGION = 'germanywestcentral'
        WIN_VM_SIZE = 'Standard_B2s_v2'
        WIN_VM_DISK_SIZE_GB = '160'
        VM_ENABLE_HIBERNATION = 'true'
        VM_ENABLE_NESTED_VIRTUALIZATION = 'false'
    }
    foreach ($key in @($config.Keys)) { Set-SetupEnvValue -Key ([string]$key) -Value ([string]$config[$key]) }
    Set-SetupEnvValue -Key 'SELECTED_VM_NAME' -Value 'vc2'
    $createArgs = @('create','--auto','--windows','--vm-name','vc2','--vm-region','germanywestcentral','--vm-size','Standard_B2s_v2','--subscription-id',$script:SetupSubscriptionId)
    if ($ConfigureOnly) { $createArgs += @('--step','configure') }
    $action = if ($ConfigureOnly) { "run read-only create configuration preflight for VM 'vc2'" } else { "create fresh managed VM 'vc2' with its default Windows image, 160 GB disk, and hibernation enabled" }
    if (-not $ConfigureOnly) {
        Write-Host 'Nested virtualization is disabled for this VM because Standard_B2s_v2 does not expose the required guest CPU virtualization extensions.' -ForegroundColor Yellow
    }
    Invoke-SetupCg -Arguments $createArgs -Action $action
}

try {
    if (-not (Test-Path -LiteralPath $script:SetupGlobalEnvPath -PathType Leaf)) { throw "Local clagnos.env was not found. Run cg.cmd configure and select an Azure subscription before setup." }
    if (-not (Test-Path -LiteralPath $script:SetupVmEnvPath -PathType Leaf)) {
        $vmTemplate = Join-Path $script:SetupRepoRoot 'vc.env.example'
        if (-not (Test-Path -LiteralPath $vmTemplate -PathType Leaf)) { throw 'vc.env.example was not found.' }
        Copy-Item -LiteralPath $vmTemplate -Destination $script:SetupVmEnvPath -ErrorAction Stop
        Set-SetupEnvValue -Key 'SELECTED_VM_NAME' -Value 'vc2'
    }
    if (-not (Test-Path -LiteralPath $script:SetupLauncherPath -PathType Leaf)) { throw "cg.cmd was not found at the repository root." }
    Push-Location $script:SetupRepoRoot
    $script:SetupDidPushLocation = $true
    Start-Transcript -LiteralPath $script:SetupTranscriptPath -Force | Out-Null
    $script:SetupTranscriptStarted = $true
    Write-Host ("Setup transcript: {0}" -f $script:SetupTranscriptPath) -ForegroundColor DarkGray

    $script:SetupSubscriptionId = if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId.Trim() } else { (Get-SetupEnvValue -Key 'SELECTED_AZURE_SUBSCRIPTION_ID').Trim() }
    if ([string]::IsNullOrWhiteSpace($script:SetupSubscriptionId)) { throw 'Set SELECTED_AZURE_SUBSCRIPTION_ID in clagnos.env or pass -SubscriptionId.' }
    $account = Invoke-SetupAzJson -Arguments @('account','show','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action 'verify Azure CLI authentication and selected subscription'
    if (-not [string]::Equals([string]$account.name,'az2vs',[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("The selected subscription is '{0}'; this setup requires the 'az2vs' subscription." -f [string]$account.name)
    }
    if (-not [string]::Equals([string]$account.id,$script:SetupSubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Azure CLI returned a subscription id that does not match the requested setup subscription.'
    }
    Write-Host ("Target: subscription {0}; VM vc2; Windows; germanywestcentral; Standard_B2s_v2; 160 GB OS disk." -f [string]$account.name) -ForegroundColor Cyan

    $target = Get-SetupManagedVc2
    if ($PreflightOnly) {
        if ($null -eq $target) {
            if ([string]::IsNullOrWhiteSpace((Get-SetupEnvValue -Key 'WIN_VM_IMAGE'))) { throw 'WIN_VM_IMAGE is empty; select a Windows image in clagnos.env before running the preflight.' }
            Invoke-SetupCreate -ConfigureOnly
        }
        else {
            Assert-SetupTargetContract -Target $target
            Write-Host ("Preflight passed for existing managed VM 'vc2' in '{0}'." -f $script:SetupResourceGroup) -ForegroundColor Green
        }
        return
    }

    if ($null -eq $target -and $ResumeAtPackageStage) { throw '-ResumeAtPackageStage requires an existing Clagnos-managed VM named vc2; no resources were created.' }
    if ($null -eq $target) {
        if ([string]::IsNullOrWhiteSpace((Get-SetupEnvValue -Key 'WIN_VM_IMAGE'))) { throw 'WIN_VM_IMAGE is empty; select a Windows image in clagnos.env before creating vc2.' }
        Invoke-SetupCreate
        $target = Get-SetupManagedVc2
        if ($null -eq $target) { throw "The create command completed but Azure inventory did not find managed VM 'vc2'." }
    }
    if ($ResumeAtPackageStage) { Assert-SetupTargetContract -Target $target }
    else { Assert-SetupTargetContract -Target $target -ApplyFixes }

    if ($ResumeAtPackageStage) {
        Write-Host 'Resume mode: reusing the existing managed VM and continuing at package prerequisites; create, initialize, and the first vm-update pass are skipped.' -ForegroundColor Yellow
    }
    else {
        Invoke-SetupCg -Arguments @('initialize','--auto','--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "run all enabled vm-init tasks on VM 'vc2'"
    }

    Set-SetupTemporaryEnvValues -Values @{ PACKAGE_TRANSPORT = 'winrm' }
    try {
        $chocolateyStatus = Get-SetupPackageStatus -PackageId 'chocolatey' -DisplayName 'Chocolatey'
        if ($chocolateyStatus -eq 'not-installed') {
            Invoke-SetupCg -Arguments @('package','--action','install','--catalog','builtin','--package','chocolatey','--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "bootstrap Chocolatey over WinRM before installing Chocolatey-managed packages"
        }
        else { Write-Host 'Chocolatey is already installed; keeping the current CLI version.' -ForegroundColor Green }

        $sysinternalsStatus = Get-SetupPackageStatus -PackageId 'sysinternals' -DisplayName 'Sysinternals'
        if ($sysinternalsStatus -eq 'not-installed') {
            Invoke-SetupCg -Arguments @('package','--action','install','--catalog','builtin','--package','sysinternals','--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "ensure the Sysinternals prerequisite is installed over WinRM for vm-update tasks"
        }
        else { Write-Host 'Sysinternals is already installed; keeping the current package version.' -ForegroundColor Green }
    }
    finally { Restore-SetupOriginalEnv }

    if (-not $ResumeAtPackageStage) {
        Invoke-SetupCg -Arguments @('update','--step','vm-update','--auto','--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "run all enabled vm-update tasks on VM 'vc2'"
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
        $packageSetupResult = Invoke-SetupCgCaptured -Arguments @('package','--action','setup-all','--catalog','all','--yes','--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "run reviewed setup-all for enabled builtin and custom packages over WinRM on VM 'vc2'"
        if ([int]$packageSetupResult.ExitCode -ne 0) {
            $script:SetupPackageWarnings = @($packageSetupResult.Output | Where-Object { [string]$_ -match '(?i)Package setup (?:failed|skipped) for|Package setup-all left one or more enabled packages unverified' } | Select-Object -Unique)
            if ($script:SetupPackageWarnings.Count -eq 0) { $script:SetupPackageWarnings = @("Package setup-all returned exit code $([int]$packageSetupResult.ExitCode).") }
            Write-Warning 'Package setup-all reported unverified packages; continuing with final update, connection, and Azure health checks.'
        }
    }
    finally { Restore-SetupOriginalEnv }

    Invoke-SetupCg -Arguments @('update','--step','vm-update','--auto','--windows','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "rerun vm-update tasks after packages are installed and verify their final idempotent state"

    $powerState = Get-SetupVmPowerState
    if ($powerState -eq 'unknown') { throw "Azure did not report a power state for VM 'vc2'; refusing to issue a lifecycle action without a verified current state." }
    if ($powerState -notmatch '(?i)^VM running$') {
        Invoke-SetupCg -Arguments @('do','--vm-action=start','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "start VM 'vc2' after guest setup"
    }
    $powerState = Get-SetupVmPowerState
    if ($powerState -notmatch '(?i)^VM running$') { throw ("VM 'vc2' is not running after setup (Azure reports '{0}')." -f $powerState) }

    Invoke-SetupConnectionChecks
    Invoke-SetupCg -Arguments @('do','--vm-action=status','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "verify final Azure status for VM 'vc2'"
    Invoke-SetupCgRedacted -Arguments @('show','--group',$script:SetupResourceGroup,'--vm-name','vc2','--subscription-id',$script:SetupSubscriptionId) -Action "review final Clagnos summary for VM 'vc2'"

    $finalVm = Invoke-SetupAzJson -Arguments @('vm','show','--resource-group',$script:SetupResourceGroup,'--name','vc2','--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action "read final VM properties for 'vc2'"
    $finalDisk = Invoke-SetupAzJson -Arguments @('disk','show','--resource-group',$script:SetupResourceGroup,'--name',[string]$finalVm.storageProfile.osDisk.name,'--subscription',$script:SetupSubscriptionId,'--output','json','--only-show-errors') -Action "read final OS disk properties for 'vc2'"
    if ([string]$finalVm.hardwareProfile.vmSize -ne 'Standard_B2s_v2' -or [string]$finalVm.location -ne 'germanywestcentral' -or [string]$finalVm.storageProfile.osDisk.osType -ne 'Windows' -or [int]$finalDisk.diskSizeGb -ne 160 -or -not [bool]$finalVm.additionalCapabilities.hibernationEnabled) {
        throw 'Final Azure configuration verification failed for VM SKU, location, OS, disk size, or hibernation.'
    }
    if ((Get-SetupVmPowerState) -notmatch '(?i)^VM running$') { throw "VM 'vc2' stopped during final verification." }
    Write-Host ''
    if ($script:SetupPackageWarnings.Count -gt 0) {
        Write-Host ("VC2 is running in '{0}'; Azure properties, vm-init, vm-update, RDP, SSH, and WinRM checks completed, with package setup warnings." -f $script:SetupResourceGroup) -ForegroundColor Yellow
        foreach ($warning in @($script:SetupPackageWarnings)) { Write-Host ('- {0}' -f [string]$warning) -ForegroundColor Yellow }
        Write-Host 'Nested virtualization is unavailable to guest applications on Standard_B2s_v2; WSL2/Docker engine use requires a SKU that exposes nested virtualization.' -ForegroundColor Yellow
    }
    else {
        Write-Host ("VC2 is ready and running in '{0}'. Azure properties, vm-init, vm-update, package setup, RDP, SSH, and WinRM checks completed." -f $script:SetupResourceGroup) -ForegroundColor Green
        Write-Host 'Nested virtualization is unavailable to guest applications on Standard_B2s_v2; WSL2/Docker engine use requires a SKU that exposes nested virtualization.' -ForegroundColor Yellow
    }
}
catch {
    $script:SetupFailed = $true
    Write-Host ''
    Write-Host 'VC2 setup did not complete.' -ForegroundColor Red
    Write-Host ([string]$_.Exception.Message) -ForegroundColor Red
}
finally {
    Restore-SetupOriginalEnv
    if ($script:SetupTranscriptStarted) { Stop-Transcript | Out-Null }
    if ($script:SetupDidPushLocation) { Pop-Location }
}
if ($script:SetupFailed -or $script:SetupPackageWarnings.Count -gt 0) { exit 1 }
