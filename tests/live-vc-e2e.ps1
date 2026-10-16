[CmdletBinding()]
param(
    [switch]$RunLive,
    [switch]$PreflightOnly,
    [switch]$ResumeExisting,
    [string]$ResumeFromPackage = '',
    [switch]$ResumeFromUpdate,
    [switch]$ResumeAfterUpdate,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9](?:[A-Za-z0-9-]{0,62})$')]
    [string]$VmName,
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^Standard_[A-Za-z0-9_]+$')]
    [string]$VmSize,
    [string]$Region = '',
    [string]$SubscriptionId = '',
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if ([string]::IsNullOrWhiteSpace([string]$RepoRoot)) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Read-ClagnosE2eDotEnv {
    param([string]$Path)

    $values = @{}
    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        if ([string]$line -notmatch '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') { continue }
        $key = [string]$Matches[1]
        $value = [string]$Matches[2]
        if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }
    return $values
}

function Invoke-ClagnosE2eAzJson {
    param([string[]]$Arguments, [string]$Description)

    Write-Host ("Doing: Azure JSON query - {0}" -f [string]$Description) -ForegroundColor DarkCyan
    $text = & az @Arguments -o json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw ("Azure preflight failed: {0}." -f $Description) }
    $joined = @($text | ForEach-Object { [string]$_ }) -join "`n"
    try { return (ConvertFrom-Json -InputObject $joined -ErrorAction Stop) }
    catch { throw ("Azure returned invalid JSON during {0}." -f $Description) }
}

function Invoke-ClagnosE2eAzText {
    param([string[]]$Arguments, [string]$Description)

    Write-Host ("Doing: Azure text query - {0}" -f [string]$Description) -ForegroundColor DarkCyan
    $text = & az @Arguments -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) { throw ("Azure verification failed: {0}." -f $Description) }
    return (@($text | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Get-ClagnosE2eStatusRows {
    param([object]$View)

    $statusRows = @()
    foreach ($row in @($View.statuses)) {
        if ($null -ne $row -and -not [string]::IsNullOrWhiteSpace([string]$row.code)) { $statusRows += $row }
    }
    if ($statusRows.Count -eq 0 -and $null -ne $View.instanceView) {
        foreach ($row in @($View.instanceView.statuses)) {
            if ($null -ne $row -and -not [string]::IsNullOrWhiteSpace([string]$row.code)) { $statusRows += $row }
        }
    }
    return @($statusRows)
}

function Get-ClagnosE2ePowerState {
    param([string]$ResourceGroup)

    $view = Invoke-ClagnosE2eAzJson -Arguments @('vm','get-instance-view','--subscription',$SubscriptionId,'--resource-group',$ResourceGroup,'--name',$VmName) -Description 'VM power and hibernation state'
    $statusRows = @(Get-ClagnosE2eStatusRows -View $view)
    $powerRow = @($statusRows | Where-Object { [string]$_.code -like 'PowerState/*' } | Select-Object -First 1)
    if ($powerRow.Count -ne 1) { return '' }
    return ([string]$powerRow[0].code).Substring('PowerState/'.Length).ToLowerInvariant()
}

function New-ClagnosE2eJawsPayloadVerifier {
    param([string]$ArchivePath, [string]$ScriptPath)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $expectedHashes = [ordered]@{}
    try {
        $prefix = 'payload/update-files/'
        foreach ($entry in @($archive.Entries | Where-Object { ([string]$_.FullName).StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase) -and -not ([string]$_.FullName).EndsWith('/') })) {
            $name = ([string]$entry.FullName).Substring($prefix.Length)
            $stream = $entry.Open()
            try { $digest = $sha256.ComputeHash($stream) } finally { $stream.Dispose() }
            $expectedHashes[$name] = [BitConverter]::ToString($digest).Replace('-','').ToLowerInvariant()
        }
    }
    finally {
        $sha256.Dispose()
        $archive.Dispose()
    }
    if ($expectedHashes.Count -ne 3) { throw ("Expected exactly three JAWS update-files payload entries, found {0}." -f $expectedHashes.Count) }

    $expectedJson = ConvertTo-Json -InputObject $expectedHashes -Compress
    $remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$targetRoot = 'C:\Program Files\Freedom Scientific\JAWS\2025'
`$expected = ConvertFrom-Json -InputObject '$expectedJson'
foreach (`$property in @(`$expected.PSObject.Properties)) {
    `$name = [string]`$property.Name
    `$path = Join-Path `$targetRoot `$name
    if (-not (Test-Path -LiteralPath `$path -PathType Leaf)) { throw ("JAWS update file is missing: {0}" -f `$name) }
    `$actualHash = (Get-FileHash -LiteralPath `$path -Algorithm SHA256).Hash.ToLowerInvariant()
    if (-not [string]::Equals(`$actualHash,[string]`$property.Value,[System.StringComparison]::OrdinalIgnoreCase)) { throw ("JAWS update file hash mismatch: {0}" -f `$name) }
    Write-Output ("JAWS update file verified: {0} => {1}" -f `$name,`$actualHash)
}
"@
    [IO.File]::WriteAllText($ScriptPath,[string]$remoteScript,[System.Text.UTF8Encoding]::new($false))
}

function Get-ClagnosE2eActiveTaskCount {
    param([ValidateSet('init','update')][string]$Stage, [ValidateSet('windows','linux')][string]$Platform)

    $stageName = if ($Stage -eq 'init') { 'vm-init' } else { 'vm-update' }
    $stageRoot = Join-Path $RepoRoot (Join-Path $stageName $Platform)
    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $stageRoot -Platform $Platform -Stage $Stage -SuppressSkipMessages
    return @($catalog.ActiveTasks).Count
}
function Get-ClagnosE2ePackageInventory {
    param([ValidateSet('builtin','custom')][string]$Catalog, [ValidateSet('windows','linux')][string]$Platform)

    $catalogRoot = Join-Path $RepoRoot (Join-Path 'vm-packages' (Join-Path $Catalog $Platform))
    if (-not (Test-Path -LiteralPath $catalogRoot -PathType Container)) { return @() }
    $availability = Read-ClagnosTaskCatalogState -Path (Join-Path $catalogRoot 'tasks.toml')
    $packages = @()
    foreach ($folder in @(Get-ChildItem -LiteralPath $catalogRoot -Directory -Force | Sort-Object Name)) {
        if ($folder.Name -in @('backup-app-states')) { continue }
        $manifestPath = Join-Path $folder.FullName 'package.json'
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
        $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop) -ErrorAction Stop
        if (-not $availability.Entries.ContainsKey([string]$folder.Name)) { throw ("Package folder is not listed in tasks.toml: {0}" -f [string]$folder.Name) }
        if (-not [bool]$availability.Entries[[string]$folder.Name]) { continue }
        $installerName = [string]$manifest.installScript
        if ([string]::IsNullOrWhiteSpace($installerName)) { $installerName = 'install.ps1' }
        $installerPath = Join-Path $folder.FullName $installerName
        if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) { throw ("Package installer is missing: {0}" -f $installerPath) }
        $installerText = [string](Get-Content -LiteralPath $installerPath -Raw -ErrorAction Stop)
        $dependsOn = @()
        if ($null -ne $manifest.dependsOn) {
            $dependsOn = @($manifest.dependsOn | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
        $packages += [pscustomobject]@{
            Catalog = $Catalog
            Id = [string]$manifest.id
            DisplayName = [string]$manifest.displayName
            StatusKind = [string]$manifest.statusCheck.kind
            RequiresWinget = [bool]($installerText -match '(?i)\bwinget(?:\.exe)?\b')
            RequiresChocolatey = [bool]($installerText -match '(?i)\b(?:choco(?:latey)?)(?:\.exe)?\b')
            RequiresNodeJs = [bool]($installerText -match '(?i)\bnpm(?:\.cmd)?\b')
            RequiresInteractiveDesktop = [bool]($installerText -match '(?i)Wait-ClagnosUserInteractiveDesktopReady')
            DependsOn = @($dependsOn)
            Manifest = $manifest
            ManifestPath = $manifestPath
        }
    }
    return @($packages)
}

function Resolve-ClagnosE2ePackageOrder {
    param([object[]]$Packages)

    $allPackages = @($Packages)
    $dependencies = @{}
    foreach ($package in @($allPackages)) {
        $key = ('{0}/{1}' -f [string]$package.Catalog,[string]$package.Id)
        $dependencyKeys = @()
        foreach ($dependencyId in @($package.DependsOn)) {
            $sameCatalog = @($allPackages | Where-Object { [string]::Equals([string]$_.Catalog,[string]$package.Catalog,[System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals([string]$_.Id,[string]$dependencyId,[System.StringComparison]::OrdinalIgnoreCase) })
            $dependencyMatches = if ($sameCatalog.Count -gt 0) { $sameCatalog } else { @($allPackages | Where-Object { [string]::Equals([string]$_.Id,[string]$dependencyId,[System.StringComparison]::OrdinalIgnoreCase) }) }
            if ($dependencyMatches.Count -ne 1) { throw ("Enabled package '{0}' has an unavailable or ambiguous dependency '{1}'." -f [string]$package.Id,[string]$dependencyId) }
            $dependencyKeys += ('{0}/{1}' -f [string]$dependencyMatches[0].Catalog,[string]$dependencyMatches[0].Id)
        }
        if (($package.StatusKind -eq 'choco' -or $package.RequiresChocolatey) -and [string]$package.Id -ne 'chocolatey') {
            if (@($allPackages | Where-Object { [string]$_.Catalog -eq 'builtin' -and [string]$_.Id -eq 'chocolatey' }).Count -ne 1) { throw 'The enabled Chocolatey prerequisite package is missing.' }
            $dependencyKeys += 'builtin/chocolatey'
        }
        if (($package.StatusKind -eq 'winget' -or $package.RequiresWinget) -and [string]$package.Id -ne 'windows-package-manager') {
            if (@($allPackages | Where-Object { [string]$_.Catalog -eq 'builtin' -and [string]$_.Id -eq 'windows-package-manager' }).Count -ne 1) { throw 'The enabled Windows Package Manager prerequisite is missing.' }
            $dependencyKeys += 'builtin/windows-package-manager'
        }
        if ($package.RequiresNodeJs -and [string]$package.Id -ne 'nodejs') {
            if (@($allPackages | Where-Object { [string]$_.Catalog -eq 'builtin' -and [string]$_.Id -eq 'nodejs' }).Count -ne 1) { throw 'The enabled Node.js prerequisite package is missing.' }
            $dependencyKeys += 'builtin/nodejs'
        }
        $dependencies[$key] = @($dependencyKeys | Select-Object -Unique)
    }

    $ordered = @()
    $remaining = @($allPackages)
    while ($remaining.Count -gt 0) {
        $remainingKeys = @($remaining | ForEach-Object { '{0}/{1}' -f [string]$_.Catalog,[string]$_.Id })
        $ready = @($remaining | Where-Object {
            $currentKey = '{0}/{1}' -f [string]$_.Catalog,[string]$_.Id
            @($dependencies[$currentKey] | Where-Object { $remainingKeys -contains $_ }).Count -eq 0
        } | Sort-Object Catalog,Id)
        if ($ready.Count -eq 0) { throw 'The enabled package dependency graph contains a cycle.' }
        $ordered += $ready
        $readyKeys = @($ready | ForEach-Object { '{0}/{1}' -f [string]$_.Catalog,[string]$_.Id })
        $remaining = @($remaining | Where-Object { $readyKeys -notcontains ('{0}/{1}' -f [string]$_.Catalog,[string]$_.Id) })
    }
    return @($ordered)
}

function Invoke-ClagnosE2eCommand {
    param([string]$Label, [string[]]$Arguments)

    Write-Host ("[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString('HH:mm:ssZ'),$Label) -ForegroundColor Cyan
    $lines = New-Object 'System.Collections.Generic.List[string]'
    & $script:PowerShellExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script:ClagnosEntryPoint @Arguments 2>&1 | ForEach-Object {
        $line = [string]$_
        [void]$lines.Add($line)
        Write-Host $line
    }
    $exitCode = $LASTEXITCODE
    $output = (@($lines) | ForEach-Object { [string]$_ }) -join "`n"
    if (-not [string]::IsNullOrWhiteSpace($output)) {
        Add-Content -LiteralPath $script:LogPath -Value ("`n--- {0} ---`n{1}" -f $Label,$output) -Encoding UTF8
    }
    if ($exitCode -ne 0) { throw ("'{0}' failed with exit code {1}. Review the local ignored E2E log: {2}" -f $Label,$exitCode,$script:LogPath) }
    return $output
}

function Assert-ClagnosE2eStageSummary {
    param([string]$Output, [ValidateSet('init','update')][string]$Stage, [int]$ExpectedSuccessCount)

    $pattern = if ($Stage -eq 'init') {
        'VM init stage summary:\s*success=(\d+),\s*failed=(\d+),\s*warning=(\d+),\s*error=(\d+),\s*reboot=(\d+)'
    }
    else {
        'VM update stage summary:\s*success=(\d+),\s*failed=(\d+),\s*warning=(\d+),\s*signal-warning=(\d+),\s*error=(\d+),\s*reboot=(\d+),\s*final-restart=(\d+)'
    }
    $match = [regex]::Match([string]$Output,$pattern,[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { throw ("The {0} stage did not emit its complete outcome summary." -f $Stage) }
    $success = [int]$match.Groups[1].Value
    $failed = [int]$match.Groups[2].Value
    $warning = [int]$match.Groups[3].Value
    $errorCount = [int]$(if ($Stage -eq 'init') { $match.Groups[4].Value } else { $match.Groups[5].Value })
    if ($Stage -eq 'update' -and [int]$match.Groups[4].Value -ne 0) { throw 'The vm-update stage reported a signal warning.' }
    if ($success -ne $ExpectedSuccessCount -or $failed -ne 0 -or $warning -ne 0 -or $errorCount -ne 0) {
        throw ("The {0} stage did not pass cleanly: success={1}/{2}, failed={3}, warning={4}, error={5}." -f $Stage,$success,$ExpectedSuccessCount,$failed,$warning,$errorCount)
    }
    Write-Host ("[PASS] {0} tasks: {1}/{1} succeeded with zero failures, warnings, or errors." -f $Stage,$success) -ForegroundColor Green
}

function Assert-ClagnosE2ePackageStatuses {
    param([string]$Output, [object[]]$Packages, [string]$Catalog)

    $catalogPackages = @($Packages | Where-Object { [string]$_.Catalog -eq $Catalog })
    foreach ($package in @($catalogPackages)) {
        $line = @(([string]$Output -split "`r?`n") | Where-Object { $_.StartsWith([string]$package.DisplayName,[System.StringComparison]::OrdinalIgnoreCase) -and $_ -match '\|\s*(installed|not-installed|unknown)\s*$' } | Select-Object -Last 1)
        if ($line.Count -ne 1 -or $line[0] -notmatch '\|\s*installed\s*$') {
            throw ("Package '{0}' did not verify as installed in the {1} catalog." -f [string]$package.Id,$Catalog)
        }
    }
}

if ($RunLive -and $PreflightOnly) { throw 'Choose either -RunLive or -PreflightOnly, not both.' }
if (-not $RunLive -and -not $PreflightOnly) { throw 'Choose -PreflightOnly for Azure read-only checks or -RunLive to explicitly execute the acceptance test.' }
if (-not [string]::IsNullOrWhiteSpace($ResumeFromPackage) -and -not $ResumeExisting) { throw '-ResumeFromPackage requires -ResumeExisting.' }
if ($ResumeFromUpdate -and -not $ResumeExisting) { throw '-ResumeFromUpdate requires -ResumeExisting.' }
if ($ResumeFromUpdate -and -not [string]::IsNullOrWhiteSpace($ResumeFromPackage)) { throw '-ResumeFromUpdate cannot be combined with -ResumeFromPackage.' }
if ($ResumeAfterUpdate -and -not $ResumeExisting) { throw '-ResumeAfterUpdate requires -ResumeExisting.' }
if ($ResumeAfterUpdate -and ($ResumeFromUpdate -or -not [string]::IsNullOrWhiteSpace($ResumeFromPackage))) { throw '-ResumeAfterUpdate cannot be combined with package resume options.' }
if ($RunLive -and ([string]$env:CI -eq 'true' -or [string]$env:GITHUB_ACTIONS -eq 'true')) { throw 'The live Azure E2E test is disabled in CI.' }

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
$globalEnvPath = Join-Path $resolvedRepoRoot 'clagnos.env'
$vmEnvPath = Join-Path $resolvedRepoRoot ($VmName + '.env')
if (-not (Test-Path -LiteralPath $globalEnvPath -PathType Leaf)) { throw 'The live E2E test requires a local clagnos.env file.' }
if (-not (Test-Path -LiteralPath $vmEnvPath -PathType Leaf)) { throw ("The live E2E test requires the target VC profile '{0}.env'." -f $VmName) }
$globalConfig = Read-ClagnosE2eDotEnv -Path $globalEnvPath
$vmConfig = Read-ClagnosE2eDotEnv -Path $vmEnvPath
if ([string]$vmConfig['SELECTED_VM_NAME'] -cne $VmName) { throw ("VC profile identity does not match its filename: {0}" -f $vmEnvPath) }
$config = @{}
foreach ($key in @($globalConfig.Keys)) { $config[[string]$key] = [string]$globalConfig[$key] }
$runtimeDefaults = @{
    DEFAULT_VM_OS = 'SELECTED_VM_OS'
    DEFAULT_AZURE_REGION = 'SELECTED_AZURE_REGION'
    DEFAULT_VM_ENABLE_HIBERNATION = 'VM_ENABLE_HIBERNATION'
    DEFAULT_VM_ENABLE_NESTED_VIRTUALIZATION = 'VM_ENABLE_NESTED_VIRTUALIZATION'
    DEFAULT_VM_ADMIN_USER = 'VM_ADMIN_USER'
    DEFAULT_VM_ASSISTANT_USER = 'VM_ASSISTANT_USER'
    DEFAULT_VM_SSH_PORT = 'VM_SSH_PORT'
    DEFAULT_VM_RDP_PORT = 'VM_RDP_PORT'
    DEFAULT_TCP_PORTS = 'TCP_PORTS'
    DEFAULT_PACKAGE_TRANSPORT = 'PACKAGE_TRANSPORT'
    DEFAULT_WIN_VM_IMAGE = 'WIN_VM_IMAGE'
    DEFAULT_WIN_VM_SIZE = 'WIN_VM_SIZE'
    DEFAULT_WIN_VM_DISK_SIZE_GB = 'WIN_VM_DISK_SIZE_GB'
}
foreach ($key in @($runtimeDefaults.Keys)) {
    $runtimeKey = [string]$runtimeDefaults[$key]
    if (-not [string]::IsNullOrWhiteSpace([string]$globalConfig[[string]$key])) { $config[$runtimeKey] = [string]$globalConfig[[string]$key] }
}
foreach ($key in @($vmConfig.Keys)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$vmConfig[$key])) { $config[[string]$key] = [string]$vmConfig[$key] }
}
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { $SubscriptionId = [string]$config['SELECTED_AZURE_SUBSCRIPTION_ID'] }
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { throw 'Set SELECTED_AZURE_SUBSCRIPTION_ID or pass -SubscriptionId.' }
if ([string]::IsNullOrWhiteSpace($Region)) { $Region = [string]$config['SELECTED_AZURE_REGION'] }
if ([string]::IsNullOrWhiteSpace($Region)) { throw 'Set SELECTED_AZURE_REGION or pass -Region.' }
if ([string]$config['SELECTED_VM_OS'] -notmatch '(?i)^windows$') { throw 'This end-to-end scenario requires SELECTED_VM_OS=windows.' }
if ([string]$config['VM_ENABLE_HIBERNATION'] -notmatch '(?i)^true$') { throw 'The target VC profile must set VM_ENABLE_HIBERNATION=true for this acceptance scenario.' }
foreach ($key in @('VM_ADMIN_USER','VM_ADMIN_PASS','VM_ASSISTANT_USER','VM_ASSISTANT_PASS','SELECTED_COMPANY_NAME','SELECTED_COMPANY_WEB_ADDRESS','SELECTED_EMPLOYEE_EMAIL_ADDRESS','SELECTED_EMPLOYEE_FULL_NAME')) {
    if ([string]::IsNullOrWhiteSpace([string]$config[$key])) { throw ("The global configuration or target VC profile is missing a required value for '{0}'." -f $key) }
}

$script:PowerShellExecutable = (Get-Command pwsh.exe -ErrorAction Stop).Source
$script:ClagnosEntryPoint = Join-Path $resolvedRepoRoot 'clagnos.ps1'
if (-not (Test-Path -LiteralPath $script:ClagnosEntryPoint -PathType Leaf)) { throw 'The clagnos.ps1 entrypoint is missing.' }
$script:LogDirectory = Join-Path $resolvedRepoRoot '.tmp\live-e2e'
New-Item -ItemType Directory -Path $script:LogDirectory -Force | Out-Null
$safeVmName = [regex]::Replace($VmName,'[^A-Za-z0-9-]','_')
$script:LogPath = Join-Path $script:LogDirectory ("{0}-{1}.log" -f $safeVmName,(Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))
Set-Content -LiteralPath $script:LogPath -Value ("Clagnos live acceptance started {0} UTC." -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

$packageArchives = @(Get-ChildItem -LiteralPath (Join-Path $resolvedRepoRoot 'vm-packages') -Recurse -File -Filter app-state.zip -ErrorAction SilentlyContinue)
if ($packageArchives.Count -gt 0) {
    $contractOutput = & $script:PowerShellExecutable -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $resolvedRepoRoot 'tests\package-app-state-contract-check.ps1') -RepoRoot $resolvedRepoRoot 2>&1
    if ($LASTEXITCODE -ne 0) { throw 'Package app-state snapshot validation failed before Azure mutation.' }
}

$packages = @((Get-ClagnosE2ePackageInventory -Catalog builtin -Platform windows) + (Get-ClagnosE2ePackageInventory -Catalog custom -Platform windows))
$packageOrder = @(Resolve-ClagnosE2ePackageOrder -Packages $packages)
if ($packages.Count -eq 0) { throw 'No enabled Windows package add-ons were found.' }
$initTaskCount = Get-ClagnosE2eActiveTaskCount -Stage init -Platform windows
$updateTaskCount = Get-ClagnosE2eActiveTaskCount -Stage update -Platform windows
if ($initTaskCount -eq 0 -or $updateTaskCount -eq 0) { throw 'The enabled Windows VC init or add-on task inventory is empty.' }
Write-Host ("Local preflight passed: init={0}, update={1}, enabled packages={2}, package app-state archives={3}." -f $initTaskCount,$updateTaskCount,$packageOrder.Count,$packageArchives.Count) -ForegroundColor DarkCyan

$account = Invoke-ClagnosE2eAzJson -Arguments @('account','show','--subscription',$SubscriptionId) -Description 'selected Azure subscription'
$activeAccount = Invoke-ClagnosE2eAzJson -Arguments @('account','show') -Description 'active Azure CLI subscription'
if (-not [string]::Equals([string]$account.id,[string]$activeAccount.id,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The selected clagnos.env subscription is not the active Azure CLI subscription.' }
if ([string]$account.state -ne 'Enabled') { throw 'The selected Azure subscription is not enabled.' }
$existingVm = @(Invoke-ClagnosE2eAzJson -Arguments @('vm','list','--subscription',$SubscriptionId,'--query',("[?name=='{0}'].{{name:name,resourceGroup:resourceGroup,location:location}}" -f $VmName)) -Description 'fresh or resume target-name check')
if ($ResumeExisting) {
    if ($existingVm.Count -ne 1) { throw ("Resume requires exactly one existing VM named '{0}' in the selected subscription; found {1}." -f $VmName,$existingVm.Count) }
    $resumeGroupName = [string]$existingVm[0].resourceGroup
    $resumeGroup = Invoke-ClagnosE2eAzJson -Arguments @('group','show','--name',$resumeGroupName,'--subscription',$SubscriptionId) -Description 'resume target ownership check'
    if ($null -eq $resumeGroup.tags -or -not [string]::Equals([string]$resumeGroup.tags.'managed-by','clagnos',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The existing resume target is not in a Clagnos-managed resource group.' }
    if (-not [string]::Equals([string]$existingVm[0].location,$Region,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The existing resume target is in an unexpected region.' }
    $resumeSize = Invoke-ClagnosE2eAzText -Arguments @('vm','show','--subscription',$SubscriptionId,'--resource-group',$resumeGroupName,'--name',$VmName,'--query','hardwareProfile.vmSize') -Description 'resume target VM size'
    if (-not [string]::Equals($resumeSize,$VmSize,[System.StringComparison]::OrdinalIgnoreCase)) { throw ("Resume target size '{0}' does not match requested E2E size '{1}'." -f $resumeSize,$VmSize) }
}
elseif ($existingVm.Count -gt 0) { throw ("VM '{0}' already exists in the selected subscription. This fresh-create test will not overwrite or delete it." -f $VmName) }

$skuRows = @(Invoke-ClagnosE2eAzJson -Arguments @('vm','list-skus','--location',$Region,'--size',$VmSize,'--resource-type','virtualMachines','--all','--query',("[?name=='{0}']" -f $VmSize)) -Description 'target VM size feature and regional availability')
if ($skuRows.Count -eq 0) { throw ("VM size '{0}' is not listed in Azure region '{1}'." -f $VmSize,$Region) }
$selectedSku = $skuRows[0]
$hibernationCapability = @($selectedSku.capabilities | Where-Object { [string]$_.name -eq 'HibernationSupported' } | Select-Object -First 1)
if ($hibernationCapability.Count -ne 1 -or [string]$hibernationCapability[0].value -notmatch '(?i)^true$') { throw ("VM size '{0}' does not advertise Azure hibernation support." -f $VmSize) }
$blockingRestrictions = @($selectedSku.restrictions | Where-Object { [string]$_.type -ne 'Zone' })
Write-Host 'Live Azure E2E preflight passed.' -ForegroundColor Green
Write-Host ("Subscription: {0}; region: {1}; VM name: {2}; VM size: {3}" -f [string]$account.name,$Region,$VmName,$VmSize)
Write-Host ("Enabled tasks: init={0}, add-on/update={1}; enabled packages across both catalogs={2}; app-state archives={3}." -f $initTaskCount,$updateTaskCount,$packageOrder.Count,$packageArchives.Count)
Write-Host 'The configured VM size must expose nested virtualization to the guest; the test validates that live after creation.'
Write-Host ("Local ignored test log: {0}" -f $script:LogPath)
if ($ResumeExisting) {
    $resumeStage = if ($ResumeAfterUpdate) { 'post-update verification' } elseif ($ResumeFromUpdate) { 'vm-update' } elseif (-not [string]::IsNullOrWhiteSpace($ResumeFromPackage)) { 'package ' + $ResumeFromPackage } else { 'package installation' }
    Write-Host ("Resume mode: existing managed VM {0}/{1}; starting at {2}." -f [string]$existingVm[0].resourceGroup,$VmName,$resumeStage) -ForegroundColor Yellow
}

if ($PreflightOnly) {
    Write-Host 'PRE-FLIGHT PASSED. No Azure resources were changed.' -ForegroundColor Green
    Write-Host 'Install order:' -ForegroundColor Cyan
    foreach ($package in @($packageOrder)) { Write-Host ("- [{0}] {1}" -f [string]$package.Catalog,[string]$package.Id) }
    return
}

Push-Location $resolvedRepoRoot
try {
    if ($ResumeExisting) {
        $resourceGroup = [string]$existingVm[0].resourceGroup
        Write-Host ("[PASS] Resuming the existing managed VM: {0} / {1}." -f $resourceGroup,$VmName) -ForegroundColor Green
    }
    else {
        $createOutput = Invoke-ClagnosE2eCommand -Label 'Create fresh virtual computer' -Arguments @('create','--auto','--windows','--vm-name',$VmName,'--vm-region',$Region,'--vm-size',$VmSize,'--subscription-id',$SubscriptionId)
        $createdVmRows = @(Invoke-ClagnosE2eAzJson -Arguments @('vm','list','--subscription',$SubscriptionId,'--query',("[?name=='{0}'].{{name:name,resourceGroup:resourceGroup,location:location}}" -f $VmName)) -Description 'created VM inventory')
        if ($createdVmRows.Count -ne 1) { throw ("Expected exactly one newly created VM named '{0}', found {1}." -f $VmName,$createdVmRows.Count) }
        $resourceGroup = [string]$createdVmRows[0].resourceGroup
        $vmLocation = [string]$createdVmRows[0].location
        if (-not [string]::Equals($vmLocation,$Region,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The newly created VM is in an unexpected region.' }
        $group = Invoke-ClagnosE2eAzJson -Arguments @('group','show','--name',$resourceGroup,'--subscription',$SubscriptionId) -Description 'managed resource-group ownership check'
        if ($null -eq $group.tags -or -not [string]::Equals([string]$group.tags.'managed-by','clagnos',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The newly created resource group is not tagged managed-by=clagnos.' }
        Write-Host ("[PASS] Fresh VM and managed resource group were created: {0} / {1}." -f $resourceGroup,$VmName) -ForegroundColor Green

        $initOutput = Invoke-ClagnosE2eCommand -Label 'Run all enabled VC init tasks' -Arguments @('initialize','--auto','--windows','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
        Assert-ClagnosE2eStageSummary -Output $initOutput -Stage init -ExpectedSuccessCount $initTaskCount
    }

    if (-not $ResumeAfterUpdate) {
        $setOutput = Invoke-ClagnosE2eCommand -Label 'Verify nested virtualization in the guest' -Arguments @('set','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId,'--nested-virtualization=on')
        if ($setOutput -notmatch '(?i)Guest virtualization extensions are available for nested virtualization') { throw 'Clagnos did not report available nested-virtualization guest extensions.' }
        $hibernationEnabled = Invoke-ClagnosE2eAzText -Arguments @('vm','show','--subscription',$SubscriptionId,'--resource-group',$resourceGroup,'--name',$VmName,'--query','additionalCapabilities.hibernationEnabled') -Description 'Azure hibernation feature state'
        if ($hibernationEnabled -notmatch '(?i)^true$') { throw 'Azure VM hibernation is not enabled.' }
    }
    else {
        Write-Host 'Nested virtualization and Azure hibernation were verified earlier in this E2E cycle; resuming after vm-update.' -ForegroundColor DarkCyan
    }

    $startIndex = if ($ResumeFromUpdate -or $ResumeAfterUpdate) { $packageOrder.Count + 1 } else { 1 }
    if (-not [string]::IsNullOrWhiteSpace($ResumeFromPackage)) {
        $resumeIndex = -1
        for ($candidate = 0; $candidate -lt $packageOrder.Count; $candidate++) {
            $packageKey = '{0}/{1}' -f [string]$packageOrder[$candidate].Catalog,[string]$packageOrder[$candidate].Id
            if ([string]::Equals($packageKey,$ResumeFromPackage,[System.StringComparison]::OrdinalIgnoreCase)) { $resumeIndex = $candidate; break }
        }
        if ($resumeIndex -lt 0) { throw ("Resume package '{0}' is not an enabled package in the current install plan." -f $ResumeFromPackage) }
        $startIndex = $resumeIndex + 1
    }
    $firstInteractivePackageIndex = 0
    $jawsPackageIndex = 0
    for ($candidate = 0; $candidate -lt $packageOrder.Count; $candidate++) {
        if ([bool]$packageOrder[$candidate].RequiresInteractiveDesktop) { $firstInteractivePackageIndex = $candidate + 1; break }
    }
    for ($candidate = 0; $candidate -lt $packageOrder.Count; $candidate++) {
        if ([string]$packageOrder[$candidate].Catalog -eq 'builtin' -and [string]$packageOrder[$candidate].Id -eq 'jaws') { $jawsPackageIndex = $candidate + 1; break }
    }
    $interactiveBootstrapThroughIndex = [Math]::Max($firstInteractivePackageIndex,$jawsPackageIndex)
    $needsInteractiveDesktopBootstrap = ($firstInteractivePackageIndex -gt 0) -and (-not $ResumeExisting -or $startIndex -le $interactiveBootstrapThroughIndex)
    $script:EarlyInstalledPackageKeys = @()
    if ($needsInteractiveDesktopBootstrap) {
        $jawsPrerequisite = @($packageOrder | Where-Object { [string]$_.Catalog -eq 'builtin' -and [string]$_.Id -eq 'jaws' })
        if ($jawsPrerequisite.Count -ne 1) { throw 'The enabled builtin JAWS package is required before interactive autologon setup.' }
        $null = Invoke-ClagnosE2eCommand -Label 'Install JAWS before its enabled vm-update maintenance task' -Arguments @('package','--action','install','--catalog','builtin','--package','jaws','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId,'--windows','--yes')
        $autologonCatalogPath = Join-Path $resolvedRepoRoot 'vm-update\windows\builtin\tasks.toml'
        $autologonAvailability = Read-ClagnosTaskCatalogState -Path $autologonCatalogPath
        if (-not $autologonAvailability.Entries.ContainsKey('102-configure-autologon-settings') -or -not [bool]$autologonAvailability.Entries['102-configure-autologon-settings']) { throw 'The enabled Store packages require vm-update task 102 to be enabled in tasks.toml.' }
        $autologonOutput = Invoke-ClagnosE2eCommand -Label 'Enable the manager interactive desktop for Store packages' -Arguments @('task','--run-vm-update','102','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId,'--windows')
        if ($autologonOutput -notmatch '(?i)autologon-state\s*=>\s*AutoAdminLogon=1' -or $autologonOutput -notmatch 'TASK_REBOOT_REQUIRED:configure-autologon-settings') {
            throw 'The autologon prerequisite did not verify and request the restart needed for Store package installation.'
        }
        $script:EarlyInstalledPackageKeys = @('builtin/jaws')
    }
    elseif ($ResumeExisting) {
        Write-Host 'Store desktop bootstrap was already completed in the earlier E2E pass.' -ForegroundColor DarkCyan
    }
    $index = 0
    if (-not $ResumeFromUpdate -and -not $ResumeAfterUpdate) {
        foreach ($package in @($packageOrder)) {
            $index++
            if ($index -lt $startIndex) { continue }
            $packageKey = '{0}/{1}' -f [string]$package.Catalog,[string]$package.Id
            if (@($script:EarlyInstalledPackageKeys) -contains $packageKey) {
                Write-Host ("[PASS] Package prerequisite was installed early for an enabled task: {0}." -f $packageKey) -ForegroundColor Green
                continue
            }
            $packageLabel = ('{0} {1}/{2}: {3}/{4}' -f [string]$package.Catalog,$index,$packageOrder.Count,[string]$package.Id,[string]$package.DisplayName)
            $null = Invoke-ClagnosE2eCommand -Label ("Install VC add-on package {0}" -f $packageLabel) -Arguments @('package','--action','install','--catalog',[string]$package.Catalog,'--package',[string]$package.Id,'--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId,'--windows','--yes')
        }
    }
    if (-not $ResumeFromUpdate -and -not $ResumeAfterUpdate) {
        foreach ($catalog in @('builtin','custom')) {
            $catalogPackages = @($packages | Where-Object { [string]$_.Catalog -eq $catalog })
            if ($catalogPackages.Count -eq 0) { continue }
            $statusOutput = Invoke-ClagnosE2eCommand -Label ("Verify every enabled {0} package" -f $catalog) -Arguments @('package','--action','list','--catalog',$catalog,'--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId,'--windows')
            Assert-ClagnosE2ePackageStatuses -Output $statusOutput -Packages $catalogPackages -Catalog $catalog
            Write-Host ("[PASS] {0} enabled {1} packages report installed." -f $catalogPackages.Count,$catalog) -ForegroundColor Green
        }
    }
    else {
        $packageResumeMessage = if ($ResumeAfterUpdate) { 'Package install and status steps were verified earlier; resuming after vm-update.' } else { 'Package install and status steps were already completed in the earlier E2E pass; resuming at vm-update.' }
        Write-Host $packageResumeMessage -ForegroundColor DarkCyan
    }

    if (-not $ResumeAfterUpdate) {
        $updateOutput = Invoke-ClagnosE2eCommand -Label 'Run all enabled VC add-on/update tasks' -Arguments @('update','--auto','--windows','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
        Assert-ClagnosE2eStageSummary -Output $updateOutput -Stage update -ExpectedSuccessCount $updateTaskCount
    }
    else {
        Write-Host 'All enabled vm-update tasks already passed with zero warnings; resuming at final VM verification.' -ForegroundColor DarkCyan
    }

    $jawsArchivePath = Join-Path $resolvedRepoRoot 'vm-packages\builtin\windows\jaws\app-state\app-state.zip'
    $jawsVerifierPath = Join-Path (Split-Path $script:LogPath -Parent) 'verify-jaws-update-files.ps1'
    New-ClagnosE2eJawsPayloadVerifier -ArchivePath $jawsArchivePath -ScriptPath $jawsVerifierPath
    $null = Invoke-ClagnosE2eCommand -Label 'Verify JAWS app-state update files byte-for-byte on the target VM' -Arguments @('exec','--quiet','--file',$jawsVerifierPath,'--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)

    $showOutput = Invoke-ClagnosE2eCommand -Label 'Inspect complete VM and attached-resource summary' -Arguments @('show','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
    foreach ($requiredText in @('Azure VM Show Report','Resource types:','Resources:','VM details:','Size (SKU):','OS type:','Public IPs:','Private IPs:','OS disk:','Data disks:','NIC ids:','Hibernation enabled: True','VM_ADMIN_PASS: [redacted]','VM_ASSISTANT_PASS: [redacted]','Nested virtualization available to guest: True')) {
        if ($showOutput -notmatch [regex]::Escape($requiredText)) { throw ("The complete show summary did not include required evidence: {0}" -f $requiredText) }
    }
    foreach ($secretKey in @('VM_ADMIN_PASS','VM_ASSISTANT_PASS')) {
        $secret = [string]$config[$secretKey]
        if ($secret.Length -gt 0 -and $showOutput.Contains($secret)) { throw 'The show report exposed a configured password instead of redacting it.' }
    }

    $null = Invoke-ClagnosE2eCommand -Label 'Verify VM lifecycle status' -Arguments @('do','--vm-action=status','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
    $null = Invoke-ClagnosE2eCommand -Label 'Verify SSH connectivity' -Arguments @('connect','--ssh','--test','--user','manager','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
    $null = Invoke-ClagnosE2eCommand -Label 'Verify RDP connectivity' -Arguments @('connect','--rdp','--test','--user','manager','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)

    $null = Invoke-ClagnosE2eCommand -Label 'Exercise Azure hibernation path' -Arguments @('do','--vm-action=hibernate-deallocate','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
    $hibernatedState = ''
    for ($attempt = 1; $attempt -le 18; $attempt++) {
        $view = Invoke-ClagnosE2eAzJson -Arguments @('vm','get-instance-view','--subscription',$SubscriptionId,'--resource-group',$resourceGroup,'--name',$VmName) -Description 'hibernation completion check'
        $stateRows = @(Get-ClagnosE2eStatusRows -View $view)
        $hibernationRows = @($stateRows | Where-Object { [string]$_.code -like 'HibernationState/*' })
        if ($hibernationRows.Count -gt 0) { $hibernatedState = [string]$hibernationRows[0].code }
        if ($hibernatedState -match '(?i)^HibernationState/Hibernated$') { break }
        Start-Sleep -Seconds 10
    }
    if ($hibernatedState -notmatch '(?i)^HibernationState/Hibernated$') { throw 'Azure did not report the VM in Hibernated state after the hibernation operation.' }
    Write-Host '[PASS] Azure reports HibernationState/Hibernated.' -ForegroundColor Green
    $null = Invoke-ClagnosE2eCommand -Label 'Restore VM to running state after hibernation' -Arguments @('do','--vm-action=start','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
    $null = Invoke-ClagnosE2eCommand -Label 'Confirm final VM running state' -Arguments @('do','--vm-action=status','--group',$resourceGroup,'--vm-name',$VmName,'--subscription-id',$SubscriptionId)
    $finalPowerState = ''
    for ($attempt = 1; $attempt -le 18; $attempt++) {
        $finalPowerState = Get-ClagnosE2ePowerState -ResourceGroup $resourceGroup
        if ($finalPowerState -eq 'running') { break }
        Start-Sleep -Seconds 10
    }
    if ($finalPowerState -ne 'running') { throw 'The E2E acceptance did not leave the VM running.' }
    $finalHibernation = Invoke-ClagnosE2eAzText -Arguments @('vm','show','--subscription',$SubscriptionId,'--resource-group',$resourceGroup,'--name',$VmName,'--query','additionalCapabilities.hibernationEnabled') -Description 'final hibernation feature state'
    if ($finalHibernation -notmatch '(?i)^true$') { throw 'The VM ended without hibernation enabled.' }
    Write-Host ''
    Write-Host 'LIVE VC E2E PASSED' -ForegroundColor Green
    Write-Host ("VM: {0}; resource group: {1}; region: {2}; size: {3}" -f $VmName,$resourceGroup,$Region,$VmSize)
    Write-Host ("Verified {0} init tasks, {1} add-on/update tasks, {2} enabled packages, hibernation, nested virtualization, summary redaction, SSH, RDP, and the hibernation/resume cycle." -f $initTaskCount,$updateTaskCount,$packageOrder.Count)
    Write-Host 'Final VM state: running. No cleanup or deletion was performed.' -ForegroundColor Green
    Write-Host ("Ignored local transcript: {0}" -f $script:LogPath)
}
catch {
    if (-not [string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
        try {
            $currentPowerState = Get-ClagnosE2ePowerState -ResourceGroup $resourceGroup
            if ($currentPowerState -ne 'running') {
                Write-Host 'E2E failed; attempting to restore the new VM to a running state for operator access.' -ForegroundColor Yellow
                Write-Host 'Doing: start VM for operator recovery after E2E failure.' -ForegroundColor DarkCyan
                $null = & az vm start --subscription $SubscriptionId --resource-group $resourceGroup --name $VmName --only-show-errors 2>$null
                if ($LASTEXITCODE -eq 0) { Write-Host 'Azure start request completed.' -ForegroundColor Yellow }
            }
        }
        catch { Write-Host 'Automatic recovery could not verify or start the new VM.' -ForegroundColor Yellow }
    }
    Write-Error ("Live VC E2E did not complete: {0}. Partial Azure resources are left intact for diagnosis. Local transcript: {1}" -f $_.Exception.Message,$script:LogPath)
    exit 1
}
finally {
    Pop-Location
}
