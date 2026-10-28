[CmdletBinding()]
param(
    [switch]$RunLive,
    [Parameter(Mandatory = $true)][string]$VmName,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [string]$PackageId = '',
    [switch]$RestartAfterPass,
    [string]$ReportPath = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
if (-not $RunLive) { throw 'This package lifecycle test changes software on a live VM. Pass -RunLive to execute it.' }

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'prodicloud.ps1')

$mutexToken = [regex]::Replace([string]$VmName,'[^A-Za-z0-9_.-]','_')
$mutexName = 'Local\ProdicloudPackageLifecycleE2E_' + $mutexToken
$livePackageE2eMutex = New-Object System.Threading.Mutex($false,$mutexName)
$livePackageE2eLockAcquired = $false
try { $livePackageE2eLockAcquired = [bool]$livePackageE2eMutex.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $livePackageE2eLockAcquired = $true }
if (-not $livePackageE2eLockAcquired) {
    $livePackageE2eMutex.Dispose()
    throw ("A live package lifecycle E2E run is already active for VM '{0}'. Wait for its report before starting another run." -f $VmName)
}

try {

function Get-LivePackageAzureSnapshot {
    param([string]$Name,[string]$Group,[string]$Subscription)

    $query = '{name:name,location:location,size:hardwareProfile.vmSize,powerState:powerState,osDiskId:storageProfile.osDisk.managedDisk.id,osDiskSize:storageProfile.osDisk.diskSizeGb,dataDisks:storageProfile.dataDisks[].{name:name,id:managedDisk.id,size:diskSizeGb},nics:networkProfile.networkInterfaces[].id}'
    $raw = Invoke-ProdicloudAzCliCommand -Arguments @('vm','show','--resource-group',$Group,'--name',$Name,'--subscription',$Subscription,'--show-details','--query',$query,'--output','json','--only-show-errors')
    if ($global:LASTEXITCODE -ne 0) { throw 'Read-only Azure VM infrastructure snapshot failed.' }
    $vm = ConvertFrom-JsonCompat -InputObject ([string]$raw)
    $ipRaw = Invoke-ProdicloudAzCliCommand -Arguments @('vm','list-ip-addresses','--resource-group',$Group,'--name',$Name,'--subscription',$Subscription,'--query','[0].virtualMachine.network.publicIpAddresses[].{ip:ipAddress,dns:dnsSettings.fqdn}','--output','json','--only-show-errors')
    if ($global:LASTEXITCODE -ne 0) { throw 'Read-only Azure network endpoint snapshot failed.' }
    $ips = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject ([string]$ipRaw)))
    $dataDisks = @($vm.dataDisks | ForEach-Object { '{0}|{1}|{2}' -f [string]$_.name,[string]$_.id,[string]$_.size } | Sort-Object)
    $nics = @($vm.nics | ForEach-Object { [string]$_ } | Sort-Object)
    $endpoints = @($ips | ForEach-Object { '{0}|{1}' -f [string]$_.ip,[string]$_.dns } | Sort-Object)
    return [pscustomobject]@{
        Name = [string]$vm.name
        Location = [string]$vm.location
        Size = [string]$vm.size
        PowerState = [string]$vm.powerState
        OsDiskId = [string]$vm.osDiskId
        OsDiskSize = [int]$vm.osDiskSize
        DataDisks = @($dataDisks)
        NicIds = @($nics)
        PublicEndpoints = @($endpoints)
    }
}

function Get-LivePackageResultRecord {
    param([AllowNull()][object]$OperationResult)

    if ($null -eq $OperationResult) { return $null }
    if ($OperationResult.PSObject.Properties.Match('Status').Count -gt 0 -and $OperationResult.PSObject.Properties.Match('TaskOutputs').Count -eq 0) {
        return [pscustomobject]@{ status = [string]$OperationResult.Status; message = [string]$OperationResult.Message; phase = [string]$OperationResult.Phase; durationSeconds = 0 }
    }
    $taskResult = if ($OperationResult.PSObject.Properties.Match('Result').Count -gt 0) { $OperationResult } else { [pscustomobject]@{ Result = $OperationResult } }
    return (Get-ProdicloudPackageStructuredResult -TaskResult $taskResult)
}

function Invoke-LivePackageAction {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][object]$Package,
        [hashtable]$BaseOptions
    )

    if ($Action -in @('uninstall','reinstall') -and $null -ne $Package.UninstallPolicy -and $null -ne $Package.UninstallPolicy.PSObject.Properties['supported'] -and -not [bool]$Package.UninstallPolicy.supported) {
        return [pscustomobject]@{ status = 'unsupported'; message = [string]$Package.UninstallPolicy.reason; phase = 'preflight'; durationSeconds = 0 }
    }

    $rawArgs = @(
        ('--action={0}' -f $Action),
        '--catalog=builtin',
        ('--package={0}' -f [string]$Package.Id),
        ('--group={0}' -f [string]$BaseOptions['group']),
        ('--vm-name={0}' -f [string]$BaseOptions['vm-name']),
        ('--subscription-id={0}' -f [string]$BaseOptions['subscription-id']),
        '--windows'
    )
    if ($Action -in @('uninstall','reinstall')) { $rawArgs += '--yes' }
    $parsed = Parse-ProdicloudCliArguments -CommandToken 'package' -RawArgs $rawArgs
    Assert-ProdicloudCommandOptions -CommandName ([string]$parsed.Command) -Options ([hashtable]$parsed.Options)
    $script:ActiveCommand = 'package'
    $script:AutoMode = $false
    $script:PerfMode = $false
    $script:ConfigOverrides['SELECTED_VM_NAME'] = [string]$BaseOptions['vm-name']
    Invoke-ProdicloudPackageCommand -Options ([hashtable]$parsed.Options) -AutoMode:$false -WindowsFlag
}

function Set-LivePackageTimeoutMeasurements {
    param([object[]]$Packages,[hashtable]$SuccessfulSeconds,[double]$BatchStatusDurationSeconds,[DateTime]$MeasuredAtUtc)

    foreach ($package in @($Packages)) {
        $manifestPath = [string]$package.ManifestPath
        $manifest = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop))
        $timeouts = $manifest.operationTimeoutSeconds
        if ($null -eq $timeouts) { $timeouts = [pscustomobject]@{} }
        $evidence = [ordered]@{}
        if ($null -ne $manifest.operationTimeoutEvidence) {
            foreach ($evidenceProperty in @($manifest.operationTimeoutEvidence.PSObject.Properties)) {
                $evidence[[string]$evidenceProperty.Name] = $evidenceProperty.Value
            }
        }
        foreach ($action in @('status','install','repair','update','uninstall','reinstall')) {
            $key = '{0}|{1}' -f [string]$package.Id,$action
            if ($action -eq 'status') {
                $measured = [double]$BatchStatusDurationSeconds
            }
            elseif ($SuccessfulSeconds.ContainsKey($key)) {
                $measured = [double]$SuccessfulSeconds[$key]
            }
            else { continue }
            $measuredBudget = [Math]::Max(30,([int][Math]::Ceiling($measured) + 10))
            $existingBudget = 0
            if ($null -ne $timeouts.PSObject.Properties[$action]) { $existingBudget = [int]$timeouts.$action }
            $budget = [Math]::Max($measuredBudget,$existingBudget)
            if ($budget -gt 480) { throw ("Measured {0} timeout for '{1}' exceeds the 480-second operational maximum." -f $action,[string]$package.Id) }
            if ($budget -gt 360 -and -not $evidence.Contains($action) -and $measured -le 350) {
                throw ("The {0} timeout for '{1}' exceeds 360 seconds without live evidence of a genuinely longer operation." -f $action,[string]$package.Id)
            }
            $timeouts | Add-Member -NotePropertyName $action -NotePropertyValue $budget -Force
            if ($measured -gt 350) {
                $previousMeasured = if ($evidence.Contains($action)) { [double]$evidence[$action].measuredSeconds } else { 0.0 }
                if ($measured -gt $previousMeasured) {
                    $evidence[$action] = [ordered]@{
                        measuredSeconds = [Math]::Round($measured,1)
                        timeoutSeconds = [int]$budget
                        measuredAtUtc = $MeasuredAtUtc.ToString('o')
                        verification = 'Live WinRM lifecycle result and target package state were verified; provider version evidence is recorded when available.'
                    }
                }
            }
        }
        $manifest | Add-Member -NotePropertyName operationTimeoutSeconds -NotePropertyValue $timeouts -Force
        if ($evidence.Count -gt 0) { $manifest | Add-Member -NotePropertyName operationTimeoutEvidence -NotePropertyValue $evidence -Force }
        elseif ($null -ne $manifest.PSObject.Properties['operationTimeoutEvidence']) { $manifest.PSObject.Properties.Remove('operationTimeoutEvidence') }
        if ($null -ne $manifest.PSObject.Properties['timeout']) { $manifest.PSObject.Properties.Remove('timeout') }
        $json = ConvertTo-Json -InputObject $manifest -Depth 100
        [IO.File]::WriteAllText($manifestPath,($json + "`n"),(New-Object System.Text.UTF8Encoding($false)))
    }
}

function Get-LivePackageStatusSnapshot {
    param([object[]]$Packages,[hashtable]$Options,[psobject]$Runtime,[psobject]$Target)
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $snapshot = Get-ProdicloudPackageStatusSnapshot -Packages $Packages -Options $Options -Platform 'windows' -Force -Runtime $Runtime -Target $Target
    $watch.Stop()
    Write-Host ("Doing: all {0} package status checks completed in {1:N1}s" -f @($Packages).Count,$watch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    return [pscustomobject]@{ StatusByPackage = $snapshot; DurationSeconds = [double]$watch.Elapsed.TotalSeconds }
}

if ([string]::IsNullOrWhiteSpace($VmName) -or [string]::IsNullOrWhiteSpace($ResourceGroup) -or [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    throw 'VmName, ResourceGroup, and SubscriptionId must be supplied explicitly for a live package test.'
}
if ($RestartAfterPass -and -not [string]::IsNullOrWhiteSpace($PackageId)) {
    throw 'The controlled restart is available only after the unfiltered all-package lifecycle matrix passes.'
}

$options = @{
    'group' = [string]$ResourceGroup
    'vm-name' = [string]$VmName
    'subscription-id' = [string]$SubscriptionId
    'windows' = $true
}
$subscriptionRaw = Invoke-ProdicloudAzCliCommand -Arguments @('account','show','--subscription',$SubscriptionId,'--query','{id:id,name:name,tenantId:tenantId}','--output','json','--only-show-errors')
if ($global:LASTEXITCODE -ne 0) { throw 'The requested subscription is not accessible to the authenticated Azure CLI session.' }
$subscriptionInfo = ConvertFrom-JsonCompat -InputObject ([string]$subscriptionRaw)
Set-ProdicloudResolvedSubscriptionContext -SubscriptionId ([string]$subscriptionInfo.id) -SubscriptionName ([string]$subscriptionInfo.name) -TenantId ([string]$subscriptionInfo.tenantId) -ResolutionSource 'live-package-test-explicit-override'
$script:ConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = [string]$SubscriptionId
$globalConfigPath = Get-ProdicloudGlobalEnvPath
$globalConfig = Read-DotEnvFile -Path $globalConfigPath -GlobalOnly
$targetConfig = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfig -VmName $VmName
$transport = Get-ProdicloudPackageTransport -ConfigMap $targetConfig
if ($transport -ne 'winrm') { throw ("The live package test requires VC profile PACKAGE_TRANSPORT=winrm; observed '{0}'." -f $transport) }

$runtime = Initialize-ProdicloudTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag -Options $options
$target = Resolve-ProdicloudManagedVmTarget -Options $options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'package'
$runtime.Context.ResourceGroup = [string]$target.ResourceGroup
$runtime.Context.VmName = [string]$target.VmName
$resolvedSubscription = Get-ProdicloudResolvedSubscriptionContext
if ($null -eq $resolvedSubscription -or -not [string]::Equals([string]$resolvedSubscription.SubscriptionId,$SubscriptionId,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'The live package test did not resolve the explicitly requested Azure subscription.'
}

$allPackages = @(Get-ProdicloudPackageCatalog -Platform 'windows' -Catalog 'builtin')
if ($allPackages.Count -ne 36) { throw ("Expected all 36 Windows builtin packages; found {0}." -f $allPackages.Count) }
$disabledPackages = @($allPackages | Where-Object { -not [bool]$_.Enabled })
if ($disabledPackages.Count -gt 0) { throw ("This test covers enabled packages only; enable these first: {0}" -f (@($disabledPackages | ForEach-Object { [string]$_.Id }) -join ', ')) }
$matrixPackages = if ([string]::IsNullOrWhiteSpace($PackageId)) { @($allPackages) } else { @($allPackages | Where-Object { [string]::Equals([string]$_.Id,[string]$PackageId,[StringComparison]::OrdinalIgnoreCase) }) }
if ($matrixPackages.Count -eq 0) { throw ("Package '{0}' was not found in the enabled builtin Windows catalog." -f $PackageId) }
$orderedPackages = @(Get-ProdicloudPackageDependencyOrder -Packages $matrixPackages)
$beforeInfrastructure = Get-LivePackageAzureSnapshot -Name $VmName -Group $ResourceGroup -Subscription $SubscriptionId
if (-not [string]::Equals([string]$beforeInfrastructure.Name,[string]$VmName,[StringComparison]::OrdinalIgnoreCase)) { throw 'Azure returned a different VM than requested.' }
if ($beforeInfrastructure.PowerState -notmatch '(?i)running') { throw 'The live package test requires VC2 to be running before package operations.' }

$startedAtUtc = [DateTime]::UtcNow
$statusBaseline = Get-LivePackageStatusSnapshot -Packages $allPackages -Options $options -Runtime $runtime -Target $target
$failedOperations = New-Object 'System.Collections.Generic.List[object]'
$operationRows = New-Object 'System.Collections.Generic.List[object]'
$successfulSeconds = @{}
$packageRequestedRebootCount = 0
$lastPackageStatusSnapshot = $null
$cycle = @('install','repair','update','uninstall','install','reinstall')

for ($packageIndex = 0; $packageIndex -lt $orderedPackages.Count; $packageIndex++) {
    $package = $orderedPackages[$packageIndex]
    Write-Host ("Doing: lifecycle matrix package {0}/{1}: {2}" -f ($packageIndex + 1),$orderedPackages.Count,[string]$package.Id) -ForegroundColor Cyan
    foreach ($action in @($cycle)) {
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $outcome = 'succeeded'
        $message = ''
        $phase = ''
        $record = $null
        Write-ProdicloudActionProgress -Action ("live package matrix {0} '{1}' on {2}" -f $action,[string]$package.Id,[string]$VmName)
        try {
            $result = Invoke-LivePackageAction -Action $action -Package $package -BaseOptions $options
            $record = Get-LivePackageResultRecord -OperationResult $result
            if ($null -ne $record) {
                $message = [string]$record.message
                $phase = [string]$record.phase
                if ([string]$record.status -eq 'unsupported' -and $action -in @('uninstall','reinstall')) {
                    $outcome = 'unsupported'
                }
                else {
                    $expectedStatus = if ($action -eq 'uninstall') { 'not-installed' } elseif ($action -eq 'install' -and [string]$record.status -eq 'installed-drifted') { 'installed-drifted' } else { 'installed' }
                    if ($null -ne $record.PSObject.Properties['Status'] -and $null -eq $record.PSObject.Properties['status']) { $record.status = [string]$record.Status }
                    if (-not [string]::IsNullOrWhiteSpace([string]$record.status) -and [string]$record.status -ne $expectedStatus) {
                        throw ("Lifecycle action returned status '{0}' rather than expected '{1}'." -f [string]$record.status,$expectedStatus)
                    }
                }
                if ($outcome -eq 'succeeded' -and [bool]$record.rebootRequired) {
                    $restarted = Restart-ProdicloudPackageVmForPendingReboot -Runtime $runtime -Target $target -Options $options -WindowsFlag
                    $runtime = $restarted.Runtime
                    $target = $restarted.Target
                    $packageRequestedRebootCount++
                    Write-Host ("Doing: completed package-requested restart; VM '{0}' is reachable again." -f $VmName) -ForegroundColor Green
                }
            }
            else {
                $message = if ($action -eq 'install') { 'Install was a verified no-op or no structured guest record was needed.' } else { 'The command returned without a structured package result.' }
                if ($action -notin @('install','update')) { throw 'No structured package lifecycle result was returned.' }
            }
        }
        catch {
            $outcome = 'failed'
            $message = [string]$_.Exception.Message
            $phase = if ($message -match "(?i)phase '([^']+)'") { [string]$Matches[1] } else { $action }
            foreach ($secret in @([string]$runtime.Context.VmPass,[string]$runtime.Context.VmAssistantPass)) {
                if (-not [string]::IsNullOrWhiteSpace($secret)) { $message = $message.Replace($secret,'[redacted]') }
            }
            $failedOperations.Add([pscustomobject]@{ Package = [string]$package.Id; Action = [string]$action; Phase = $phase; Message = $message }) | Out-Null
        }
        finally { $watch.Stop() }

        $elapsedSeconds = [Math]::Round([double]$watch.Elapsed.TotalSeconds,1)
        if ($outcome -eq 'succeeded') {
            $measureKey = '{0}|{1}' -f [string]$package.Id,$action
            if (-not $successfulSeconds.ContainsKey($measureKey) -or $elapsedSeconds -gt [double]$successfulSeconds[$measureKey]) { $successfulSeconds[$measureKey] = $elapsedSeconds }
        }
        $operationRows.Add([pscustomobject]@{
            Package = [string]$package.Id
            Action = [string]$action
            Outcome = $outcome
            Phase = $phase
            DurationSeconds = $elapsedSeconds
            ResultStatus = if ($null -ne $record) { [string]$record.status } else { '' }
            RebootRequired = if ($null -ne $record) { [bool]$record.rebootRequired } else { $false }
            Message = $message
        }) | Out-Null
        Write-Host ("Doing: completed live package matrix {0} '{1}' => {2} ({3:N1}s)" -f $action,[string]$package.Id,$outcome,$elapsedSeconds) -ForegroundColor $(if ($outcome -eq 'succeeded') { 'Green' } else { 'Red' })
        if ($outcome -eq 'failed') {
            $failureStatus = 'unknown'
            try {
                $failureStatusSnapshot = Get-LivePackageStatusSnapshot -Packages @($package) -Options $options -Runtime $runtime -Target $target
                $failureStatus = [string]$failureStatusSnapshot.StatusByPackage[[string]$package.Id]
            }
            catch { $failureStatus = 'status-check-failed' }
            $failureInfrastructure = $null
            try { $failureInfrastructure = Get-LivePackageAzureSnapshot -Name $VmName -Group $ResourceGroup -Subscription $SubscriptionId } catch { }
            if ([string]::IsNullOrWhiteSpace($ReportPath)) {
                $ReportPath = Join-Path ([IO.Path]::GetTempPath()) ('prodicloud-package-lifecycle-{0}-{1}-stopped.json' -f $VmName,[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
            }
            $partialReport = [ordered]@{
                StartedAtUtc = $startedAtUtc.ToString('o')
                StoppedAtUtc = [DateTime]::UtcNow.ToString('o')
                VmName = [string]$VmName
                ResourceGroup = [string]$ResourceGroup
                SubscriptionId = [string]$SubscriptionId
                Transport = [string]$transport
                PackageCount = [int]$allPackages.Count
                MatrixPackageCount = [int]$matrixPackages.Count
                PackageFilter = [string]$PackageId
                StoppedAfterPackage = [string]$package.Id
                StoppedAfterAction = [string]$action
                PackageStatusAtStop = [string]$failureStatus
                InfrastructureBefore = $beforeInfrastructure
                InfrastructureAtStop = $failureInfrastructure
                Results = @($operationRows.ToArray())
                Failures = @($failedOperations.ToArray())
            }
            [IO.File]::WriteAllText($ReportPath,(ConvertTo-Json -InputObject $partialReport -Depth 40),(New-Object System.Text.UTF8Encoding($false)))
            throw ("Stopped at the first failed action '{0}' for package '{1}'. Fix this package, then rerun only that package before continuing the catalog. Report: {2}" -f $action,[string]$package.Id,$ReportPath)
        }
    }

    $packageStatus = Get-LivePackageStatusSnapshot -Packages @($package) -Options $options -Runtime $runtime -Target $target
    $lastPackageStatusSnapshot = $packageStatus
    if ([string]$packageStatus.StatusByPackage[[string]$package.Id] -notin @('installed','installed-drifted')) {
        Write-ProdicloudActionProgress -Action ("recovery install for '{0}' after lifecycle matrix" -f [string]$package.Id)
        try { $null = Invoke-LivePackageAction -Action 'install' -Package $package -BaseOptions $options }
        catch {
            $message = [string]$_.Exception.Message
            foreach ($secret in @([string]$runtime.Context.VmPass,[string]$runtime.Context.VmAssistantPass)) { if (-not [string]::IsNullOrWhiteSpace($secret)) { $message = $message.Replace($secret,'[redacted]') } }
            $failedOperations.Add([pscustomobject]@{ Package = [string]$package.Id; Action = 'recovery-install'; Phase = 'recovery'; Message = $message }) | Out-Null
        }
    }
}

$finalVerificationPackages = if ([string]::IsNullOrWhiteSpace($PackageId)) { @($allPackages) } else { @($matrixPackages) }
$finalStatusResult = if ([string]::IsNullOrWhiteSpace($PackageId)) {
    Get-LivePackageStatusSnapshot -Packages $finalVerificationPackages -Options $options -Runtime $runtime -Target $target
}
else {
    $lastPackageStatusSnapshot
}
if ($null -eq $finalStatusResult) { throw 'Final package status was not captured during the package lifecycle pass.' }
$finalStatus = $finalStatusResult.StatusByPackage
$notInstalled = @($finalVerificationPackages | Where-Object { [string]$finalStatus[[string]$_.Id] -ne 'installed' })
if ($notInstalled.Count -gt 0) {
    foreach ($package in @($notInstalled)) {
        $failedOperations.Add([pscustomobject]@{ Package = [string]$package.Id; Action = 'final-status'; Phase = 'final-verification'; Message = ('Final package state is ' + [string]$finalStatus[[string]$package.Id]) }) | Out-Null
    }
}

$measuredAtUtc = [DateTime]::UtcNow

$rebootResult = if ($packageRequestedRebootCount -gt 0) { 'completed after package vendor request' } else { 'not-requested' }
if ($RestartAfterPass -and $failedOperations.Count -eq 0) {
    try {
    Write-ProdicloudActionProgress -Action ("perform the single authorized VC restart on '{0}'" -f $VmName)
    $restartArgs = @('--vm-action=restart',('--group={0}' -f $ResourceGroup),('--vm-name={0}' -f $VmName),('--subscription-id={0}' -f $SubscriptionId),'--windows')
    $parsedRestart = Parse-ProdicloudCliArguments -CommandToken 'do' -RawArgs $restartArgs
    Invoke-ProdicloudCommandDispatcher -CommandName ([string]$parsedRestart.Command) -Options ([hashtable]$parsedRestart.Options) -HelpTopic ([string]$parsedRestart.HelpTopic)
    $restartDeadline = [DateTime]::UtcNow.AddMinutes(20)
    do {
        $powerState = [string](Invoke-ProdicloudAzCliCommand -Arguments @('vm','show','--resource-group',$ResourceGroup,'--name',$VmName,'--subscription',$SubscriptionId,'--show-details','--query','powerState','--output','tsv','--only-show-errors'))
        if ($powerState -match '(?i)running') { break }
        if ([DateTime]::UtcNow -ge $restartDeadline) { throw 'The authorized post-package restart did not return VC2 to running before the 20-minute deadline.' }
        Write-Host ("Doing: waiting for post-package VM restart; state={0}" -f $powerState) -ForegroundColor DarkCyan
        Start-Sleep -Seconds 15
    } while ($true)

    $runtime = Initialize-ProdicloudTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag -Options $options
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $vmDetails = Get-ProdicloudVmDetails -Context $runtime.Context -AllowCachedInventory
    $hostName = [string]$vmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($hostName)) { $hostName = [string]$vmDetails.PublicIP }
    if (-not (Wait-ProdicloudTcpPortReachable -HostName $hostName -Port 5985 -MaxAttempts 40 -DelaySeconds 15 -TimeoutSeconds 5 -Label 'WinRM after package restart')) {
        throw 'WinRM did not become reachable within 10 minutes after the controlled package restart.'
    }
    $session = New-ProdicloudPackagePowerShellSession -Runtime $runtime -HostName $hostName -OpenTimeoutSeconds 30 -OperationTimeoutSeconds 60
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $jawsZipPath = Join-Path $repoRoot 'vm-packages/builtin/windows/jaws/app-state/app-state.zip'
        $jawsArchive = [IO.Compression.ZipFile]::OpenRead($jawsZipPath)
        try {
            $jawsManifestEntry = $jawsArchive.GetEntry('app-state.manifest.json')
            $jawsReader = New-Object IO.StreamReader($jawsManifestEntry.Open())
            try { $jawsSnapshotManifest = ConvertFrom-Json -InputObject $jawsReader.ReadToEnd() -ErrorAction Stop }
            finally { $jawsReader.Dispose() }
            $jawsRelativePaths = @($jawsSnapshotManifest.profileFiles | ForEach-Object { [string]$_.relativeDestinationPath })
        }
        finally { $jawsArchive.Dispose() }
        $jawsStartup = Invoke-Command -Session $session -ArgumentList ([string]$runtime.Context.VmUser,[string]$runtime.Context.VmAssistantUser,[string[]]$jawsRelativePaths) -ErrorAction Stop -ScriptBlock {
            param([string]$ManagerUser,[string]$AssistantUser,[string[]]$PreferencePaths)
            Import-Module 'C:\Windows\Temp\prodicloud-package-operations.psm1' -Force -DisableNameChecking
            $profilePaths = @{}
            $profiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.LocalPath) })
            foreach ($role in @(@{ Name = 'manager'; User = $ManagerUser },@{ Name = 'assistant'; User = $AssistantUser })) {
                $profile = @($profiles | Where-Object { [string]::Equals((Split-Path -Leaf ([string]$_.LocalPath)),[string]$role.User,[StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                $profilePaths[[string]$role.Name] = if ($profile.Count -gt 0) { [string]$profile[0].LocalPath } else { Join-Path $env:SystemDrive (Join-Path 'Users' ([string]$role.User)) }
            }
            $missingPreferenceFiles = @()
            foreach ($roleName in @('manager','assistant')) {
                foreach ($relative in @($PreferencePaths)) {
                    $profileRelative = [string]$relative -replace '(?i)^AppData\\Roaming\\',''
                    $fullPath = Join-Path (Join-Path ([string]$profilePaths[$roleName]) 'AppData\Roaming') $profileRelative
                    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { $missingPreferenceFiles += ('{0}:{1}' -f $roleName,[IO.Path]::GetFileName($fullPath)) }
                }
            }
            [pscustomobject]@{
                LogonScreenRunEnabled = Test-ProdicloudJawsLogonScreenStartup
                MachinePostLogonEntry = [string](Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'JAWS' -ErrorAction SilentlyContinue).JAWS
                ManagerPostLogonReady = Test-ProdicloudJawsPostLogonStartup -UserName $ManagerUser -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe'
                AssistantPostLogonReady = Test-ProdicloudJawsPostLogonStartup -UserName $AssistantUser -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe'
                JawsExecutablePresent = Test-Path -LiteralPath 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe' -PathType Leaf
                MissingPreferenceFiles = @($missingPreferenceFiles)
            }
        }
    }
    finally { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
    if (-not [bool]$jawsStartup.LogonScreenRunEnabled -or -not [bool]$jawsStartup.ManagerPostLogonReady -or -not [bool]$jawsStartup.AssistantPostLogonReady -or -not [bool]$jawsStartup.JawsExecutablePresent -or @($jawsStartup.MissingPreferenceFiles).Count -gt 0) {
        throw 'JAWS startup verification after the controlled restart did not pass for the logon screen and both managed users.'
    }
    if ([string](Invoke-ProdicloudAzCliCommand -Arguments @('vm','show','--resource-group',$ResourceGroup,'--name',$VmName,'--subscription',$SubscriptionId,'--show-details','--query','powerState','--output','tsv','--only-show-errors')) -notmatch '(?i)running') {
        throw 'VC2 must remain running after the package lifecycle test.'
    }
    $postRestartStatus = Get-LivePackageStatusSnapshot -Packages $allPackages -Options $options -Runtime $runtime -Target $target
    $finalStatus = $postRestartStatus.StatusByPackage
    $postRestartFailures = @($allPackages | Where-Object { [string]$finalStatus[[string]$_.Id] -ne 'installed' })
    foreach ($package in @($postRestartFailures)) {
        $failedOperations.Add([pscustomobject]@{ Package = [string]$package.Id; Action = 'post-restart-status'; Phase = 'final-verification'; Message = ('Post-restart package state is ' + [string]$finalStatus[[string]$package.Id]) }) | Out-Null
    }
    $finalStatusResult = $postRestartStatus
    $rebootResult = 'completed; VM running; JAWS logon and both post-logon startup entries verified'
    }
    catch {
        $rebootResult = 'failed during post-package restart or startup verification'
        $message = [string]$_.Exception.Message
        foreach ($secret in @([string]$runtime.Context.VmPass,[string]$runtime.Context.VmAssistantPass)) { if (-not [string]::IsNullOrWhiteSpace($secret)) { $message = $message.Replace($secret,'[redacted]') } }
        $failedOperations.Add([pscustomobject]@{ Package = 'jaws'; Action = 'post-restart-startup-verification'; Phase = 'post-restart'; Message = $message }) | Out-Null
    }
}
elseif ($RestartAfterPass) { $rebootResult = 'skipped because package lifecycle or final-state checks failed' }

$afterInfrastructure = Get-LivePackageAzureSnapshot -Name $VmName -Group $ResourceGroup -Subscription $SubscriptionId
$beforeSignature = ConvertTo-Json -InputObject $beforeInfrastructure -Depth 12 -Compress
$afterSignature = ConvertTo-Json -InputObject $afterInfrastructure -Depth 12 -Compress
if (-not [string]::Equals($beforeSignature,$afterSignature,[StringComparison]::Ordinal)) {
    $failedOperations.Add([pscustomobject]@{ Package = ''; Action = 'infrastructure-invariant'; Phase = 'final-verification'; Message = 'VM size, disk ids/sizes, NIC ids, power state, or public endpoints changed during package operations.' }) | Out-Null
}

if ($failedOperations.Count -eq 0 -and @($notInstalled).Count -eq 0) {
foreach ($package in @($matrixPackages)) {
        $packageMeasurements = @{}
        foreach ($action in @('install','repair','update','uninstall','reinstall')) {
            $key = '{0}|{1}' -f [string]$package.Id,$action
            if ($successfulSeconds.ContainsKey($key)) { $packageMeasurements[$key] = [double]$successfulSeconds[$key] }
        }
        Set-LivePackageTimeoutMeasurements -Packages @($package) -SuccessfulSeconds $packageMeasurements -BatchStatusDurationSeconds ([double]$statusBaseline.DurationSeconds) -MeasuredAtUtc $measuredAtUtc
    }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path ([IO.Path]::GetTempPath()) ('prodicloud-package-lifecycle-{0}-{1}.json' -f $VmName,$measuredAtUtc.ToString('yyyyMMddTHHmmssZ'))
}
$report = [ordered]@{
    StartedAtUtc = $startedAtUtc.ToString('o')
    CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
    VmName = [string]$VmName
    ResourceGroup = [string]$ResourceGroup
    SubscriptionId = [string]$SubscriptionId
    Transport = [string]$transport
    PackageCount = [int]$allPackages.Count
    MatrixPackageCount = [int]$matrixPackages.Count
    PackageFilter = [string]$PackageId
    BaselineStatusSeconds = [Math]::Round([double]$statusBaseline.DurationSeconds,1)
    FinalStatusSeconds = [Math]::Round([double]$finalStatusResult.DurationSeconds,1)
    InfrastructureBefore = $beforeInfrastructure
    InfrastructureAfter = $afterInfrastructure
    RestartResult = [string]$rebootResult
    Results = @($operationRows.ToArray())
    Failures = @($failedOperations.ToArray())
    FinalStatus = $finalStatus
}
[IO.File]::WriteAllText($ReportPath,(ConvertTo-Json -InputObject $report -Depth 40),(New-Object System.Text.UTF8Encoding($false)))
Write-Host ("Package lifecycle E2E report: {0}" -f $ReportPath) -ForegroundColor Cyan
Write-Host ("Package actions: {0}; unsupported by Windows: {1}; failures: {2}; VM: {3}; size: {4}; state: {5}" -f $operationRows.Count,@($operationRows | Where-Object { [string]$_.Outcome -eq 'unsupported' }).Count,$failedOperations.Count,$VmName,$afterInfrastructure.Size,$rebootResult) -ForegroundColor $(if ($failedOperations.Count -eq 0) { 'Green' } else { 'Red' })
if ($failedOperations.Count -gt 0) { throw ("Package lifecycle E2E completed with {0} failed check(s). Review {1}." -f $failedOperations.Count,$ReportPath) }
}
finally {
    if ($livePackageE2eLockAcquired) {
        try { $livePackageE2eMutex.ReleaseMutex() } catch { }
        $livePackageE2eMutex.Dispose()
    }
}
