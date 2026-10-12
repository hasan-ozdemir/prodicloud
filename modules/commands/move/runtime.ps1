# Move command shared runtime helpers.

# Handles Get-ClagnosMoveExpectedSourceResourceTypeCounts.
function Get-ClagnosMoveExpectedSourceResourceTypeCounts {
    return [ordered]@{
        'Microsoft.Compute/disks' = 1
        'Microsoft.Compute/virtualMachines' = 1
        'Microsoft.Network/networkInterfaces' = 1
        'Microsoft.Network/networkSecurityGroups' = 1
        'Microsoft.Network/publicIPAddresses' = 1
        'Microsoft.Network/virtualNetworks' = 1
    }
}

# Handles Test-ClagnosMoveResourceSetIsPurgeSafe.
function Test-ClagnosMoveResourceSetIsPurgeSafe {
    param(
        [object[]]$Resources,
        [string]$VmName,
        [string]$OsDiskName
    )

    $expectedCounts = Get-ClagnosMoveExpectedSourceResourceTypeCounts
    $resourceRows = @($Resources | Where-Object { $null -ne $_ })
    $actualCounts = Get-ClagnosResourceTypeCountMap -Resources $resourceRows
    $unexpectedTypes = @($actualCounts.Keys | Where-Object { $expectedCounts.Keys -notcontains [string]$_ } | Sort-Object)
    $countMismatches = @()

    foreach ($typeName in @($expectedCounts.Keys)) {
        $expectedCount = [int]$expectedCounts[$typeName]
        $actualCount = 0
        if ($actualCounts.Contains([string]$typeName)) {
            $actualCount = [int]$actualCounts[[string]$typeName]
        }

        if ($actualCount -ne $expectedCount) {
            $countMismatches += ("{0} expected={1} actual={2}" -f [string]$typeName, $expectedCount, $actualCount)
        }
    }

    $vmMatch = @($resourceRows | Where-Object {
        [string]::Equals([string]$_.type, 'Microsoft.Compute/virtualMachines', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$_.name, [string]$VmName, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1)

    $diskMatch = @($resourceRows | Where-Object {
        [string]::Equals([string]$_.type, 'Microsoft.Compute/disks', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$_.name, [string]$OsDiskName, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1)

    return [pscustomobject]@{
        IsSafe = ($unexpectedTypes.Count -eq 0 -and $countMismatches.Count -eq 0 -and @($vmMatch).Count -gt 0 -and @($diskMatch).Count -gt 0)
        ResourceCount = [int]$resourceRows.Count
        CountMap = $actualCounts
        UnexpectedTypes = @($unexpectedTypes)
        CountMismatches = @($countMismatches)
        VmMatched = (@($vmMatch).Count -gt 0)
        DiskMatched = (@($diskMatch).Count -gt 0)
    }
}

# Handles Get-ClagnosMoveSourceGroupResources.
function Get-ClagnosMoveSourceGroupResources {
    param(
        [string]$ResourceGroup
    )

    $resourcesJson = az resource list -g $ResourceGroup -o json --only-show-errors
    Assert-LastExitCode "az resource list (move source group)"
    return @(ConvertFrom-JsonArrayCompat -InputObject $resourcesJson)
}

# Handles Assert-ClagnosMoveSourceGroupPurgeSafe.
function Assert-ClagnosMoveSourceGroupPurgeSafe {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$OsDiskName
    )

    Assert-ClagnosManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName 'move'
    $resources = @(Get-ClagnosMoveSourceGroupResources -ResourceGroup $ResourceGroup)
    $result = Test-ClagnosMoveResourceSetIsPurgeSafe -Resources $resources -VmName $VmName -OsDiskName $OsDiskName
    if ([bool]$result.IsSafe) {
        return $result
    }

    $details = @()
    if (@($result.UnexpectedTypes).Count -gt 0) {
        $details += ("unexpected resource types: {0}" -f (@($result.UnexpectedTypes) -join ', '))
    }
    if (@($result.CountMismatches).Count -gt 0) {
        $details += ("count mismatches: {0}" -f (@($result.CountMismatches) -join '; '))
    }
    if (-not [bool]$result.VmMatched) {
        $details += ("vm '{0}' was not found in the source group inventory" -f $VmName)
    }
    if (-not [bool]$result.DiskMatched) {
        $details += ("os disk '{0}' was not found in the source group inventory" -f $OsDiskName)
    }

    Throw-FriendlyError `
        -Detail ("Source resource group '{0}' is not safe for automatic purge after move: {1}." -f $ResourceGroup, ($details -join '; ')) `
        -Code 62 `
        -Summary "Move command stopped before source-group deletion safety check." `
        -Hint "Inspect the extra resources in the source group and clean them up manually, or remove only the old group yourself after the move."
}

# Handles Wait-ClagnosSnapshotCopyReady.
function Wait-ClagnosSnapshotCopyReady {
    param(
        [string]$ResourceGroup,
        [string]$SnapshotName,
        [int]$MaxAttempts = 540,
        [int]$DelaySeconds = 20,
        [int]$NoProgressAttemptLimit = 45
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }
    if ($NoProgressAttemptLimit -lt 1) { $NoProgressAttemptLimit = 1 }

    $previousProgressKey = ''
    $stagnantAttempts = 0

    for ($copyAttempt = 1; $copyAttempt -le $MaxAttempts; $copyAttempt++) {
        $copyStateJson = az snapshot show -g $ResourceGroup -n $SnapshotName --query "{provisioningState:provisioningState,snapshotAccessState:snapshotAccessState,completionPercent:completionPercent}" -o json --only-show-errors
        Assert-LastExitCode "az snapshot show (target copy state)"
        $copyState = ConvertFrom-JsonCompat -InputObject $copyStateJson
        $prov = [string]$copyState.provisioningState
        $acc = [string]$copyState.snapshotAccessState
        $pct = 0.0
        if ($null -ne $copyState.completionPercent) {
            $pct = [double]$copyState.completionPercent
        }

        $progressKey = ("{0}|{1}|{2:N1}" -f $prov, $acc, $pct)
        if ([string]::Equals([string]$progressKey, [string]$previousProgressKey, [System.StringComparison]::OrdinalIgnoreCase)) {
            $stagnantAttempts++
        }
        else {
            $stagnantAttempts = 0
            $previousProgressKey = $progressKey
        }

        Write-ClagnosActionProgress -Action ("check target snapshot copy {0}/{1}: provisioningState={2}, accessState={3}, completionPercent={4:N1}" -f $copyAttempt, $MaxAttempts, $prov, $acc, $pct)

        if ([string]::Equals($prov, "Succeeded", [System.StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($acc, "Available", [System.StringComparison]::OrdinalIgnoreCase) -and $pct -ge 100.0) {
            return $copyState
        }

        if ($stagnantAttempts -ge $NoProgressAttemptLimit) {
            throw ("Target snapshot copy made no observable progress for {0} attempt(s)." -f $NoProgressAttemptLimit)
        }

        if ($copyAttempt -ge $MaxAttempts) {
            throw "Target snapshot copy did not complete in expected time."
        }

        Write-ClagnosActionProgress -Action ("wait {0}s for target snapshot copy completion" -f $DelaySeconds)
        Start-Sleep -Seconds $DelaySeconds
    }

    throw "Target snapshot copy did not complete in expected time."
}

# Handles Test-ClagnosTcpPortReachable.
function Test-ClagnosTcpPortReachable {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$TimeoutSeconds = 5
    )

    if ([string]::IsNullOrWhiteSpace([string]$HostName) -or $Port -lt 1 -or $Port -gt 65535) {
        return $false
    }

    if ($TimeoutSeconds -lt 1) { $TimeoutSeconds = 1 }

    $client = New-Object System.Net.Sockets.TcpClient
    $waitHandle = $null
    try {
        $async = $client.BeginConnect([string]$HostName, [int]$Port, $null, $null)
        $waitHandle = $async.AsyncWaitHandle
        if (-not $waitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds), $false)) {
            return $false
        }

        $client.EndConnect($async)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $waitHandle) {
            try { $waitHandle.Close() } catch { }
        }
        try { $client.Dispose() } catch { }
    }
}

# Handles Wait-ClagnosTcpPortReachable.
function Wait-ClagnosTcpPortReachable {
    param(
        [string]$HostName,
        [int]$Port,
        [int]$MaxAttempts = 18,
        [int]$DelaySeconds = 10,
        [int]$TimeoutSeconds = 5,
        [string]$Label = 'tcp port'
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-ClagnosActionProgress -Action ("probe {0} connectivity at {1}:{2} (attempt {3}/{4})" -f $Label,$HostName,$Port,$attempt,$MaxAttempts)
        if (Test-ClagnosTcpPortReachable -HostName $HostName -Port $Port -TimeoutSeconds $TimeoutSeconds) {
            return $true
        }
        Write-ClagnosActionProgress -Action ("wait {0}s before retrying {1} connectivity" -f $DelaySeconds,$Label)
        Start-Sleep -Seconds $DelaySeconds
    }

    return $false
}

# Handles Assert-ClagnosMoveTargetParity.
function Assert-ClagnosMoveTargetParity {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$ExpectedRegion,
        [string]$ExpectedVmSize,
        [string]$ExpectedDiskSku,
        [int]$ExpectedDiskSizeGb,
        [bool]$ExpectedDiskSupportsHibernation,
        [bool]$ExpectedVmHibernationEnabled
    )

    $vmJson = az vm show -g $ResourceGroup -n $VmName -o json --only-show-errors
    Assert-LastExitCode "az vm show (move target parity)"
    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    if ($null -eq $vmObject) {
        throw "Target VM metadata could not be parsed."
    }

    $actualRegion = [string]$vmObject.location
    $actualVmSize = [string]$vmObject.hardwareProfile.vmSize
    $actualVmHibernation = $false
    if ($vmObject.PSObject.Properties.Match('additionalCapabilities').Count -gt 0 -and $null -ne $vmObject.additionalCapabilities) {
        if ($vmObject.additionalCapabilities.PSObject.Properties.Match('hibernationEnabled').Count -gt 0 -and $null -ne $vmObject.additionalCapabilities.hibernationEnabled) {
            $actualVmHibernation = [bool]$vmObject.additionalCapabilities.hibernationEnabled
        }
    }

    $diskId = [string]$vmObject.storageProfile.osDisk.managedDisk.id
    if ([string]::IsNullOrWhiteSpace([string]$diskId)) {
        throw "Target VM OS disk id could not be resolved."
    }

    $diskJson = az disk show --ids $diskId -o json --only-show-errors
    Assert-LastExitCode "az disk show (move target parity)"
    $diskObject = ConvertFrom-JsonCompat -InputObject $diskJson
    if ($null -eq $diskObject) {
        throw "Target disk metadata could not be parsed."
    }

    $actualDiskSku = [string]$diskObject.sku.name
    $actualDiskSizeGb = [int]$diskObject.diskSizeGb
    $actualDiskSupportsHibernation = $false
    if ($diskObject.PSObject.Properties.Match('supportsHibernation').Count -gt 0 -and $null -ne $diskObject.supportsHibernation) {
        $actualDiskSupportsHibernation = [bool]$diskObject.supportsHibernation
    }

    if (-not [string]::Equals([string]$actualRegion, [string]$ExpectedRegion, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Target VM region mismatch. Expected '{0}', actual '{1}'." -f $ExpectedRegion, $actualRegion)
    }
    if (-not [string]::Equals([string]$actualVmSize, [string]$ExpectedVmSize, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Target VM size mismatch. Expected '{0}', actual '{1}'." -f $ExpectedVmSize, $actualVmSize)
    }
    if (-not [string]::Equals([string]$actualDiskSku, [string]$ExpectedDiskSku, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Target disk sku mismatch. Expected '{0}', actual '{1}'." -f $ExpectedDiskSku, $actualDiskSku)
    }
    if ($actualDiskSizeGb -ne $ExpectedDiskSizeGb) {
        throw ("Target disk size mismatch. Expected '{0}', actual '{1}'." -f $ExpectedDiskSizeGb, $actualDiskSizeGb)
    }
    if ([bool]$ExpectedDiskSupportsHibernation -ne [bool]$actualDiskSupportsHibernation) {
        throw ("Target disk hibernation-support mismatch. Expected '{0}', actual '{1}'." -f $ExpectedDiskSupportsHibernation, $actualDiskSupportsHibernation)
    }
    if ([bool]$ExpectedVmHibernationEnabled -ne [bool]$actualVmHibernation) {
        throw ("Target VM hibernation setting mismatch. Expected '{0}', actual '{1}'." -f $ExpectedVmHibernationEnabled, $actualVmHibernation)
    }

    return [pscustomobject]@{
        Vm = $vmObject
        Disk = $diskObject
    }
}

# Handles Invoke-ClagnosMoveTargetHealthCheck.
function Invoke-ClagnosMoveTargetHealthCheck {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$Platform,
        [string]$ExpectedRegion,
        [string]$ExpectedVmSize,
        [string]$ExpectedDiskSku,
        [int]$ExpectedDiskSizeGb,
        [bool]$ExpectedDiskSupportsHibernation,
        [bool]$ExpectedVmHibernationEnabled,
        [string]$SshPort,
        [string]$RdpPort
    )

    $parity = Assert-ClagnosMoveTargetParity `
        -ResourceGroup $ResourceGroup `
        -VmName $VmName `
        -ExpectedRegion $ExpectedRegion `
        -ExpectedVmSize $ExpectedVmSize `
        -ExpectedDiskSku $ExpectedDiskSku `
        -ExpectedDiskSizeGb $ExpectedDiskSizeGb `
        -ExpectedDiskSupportsHibernation:$ExpectedDiskSupportsHibernation `
        -ExpectedVmHibernationEnabled:$ExpectedVmHibernationEnabled

    $taskRuntime = Initialize-ClagnosTaskExecutionRuntimeContext `
        -AutoMode:$true `
        -WindowsFlag:([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) `
        -LinuxFlag:([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase))
    $execResult = Invoke-ClagnosTaskExecutionWithTarget `
        -Runtime $taskRuntime `
        -Options @{ group = $ResourceGroup; 'vm-name' = $VmName } `
        -OperationName 'move' `
        -Stage 'update' `
        -Requested '10099' `
        -AutoMode:$true `
        -TaskOutcomeModeOverride 'strict'

    $vmDetailContext = [ordered]@{
        ResourceGroup = $ResourceGroup
        VmName = $VmName
        AzLocation = $ExpectedRegion
        SshPort = $SshPort
    }
    $targetVmDetails = Get-ClagnosVmDetails -Context $vmDetailContext
    $hostName = [string]$targetVmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace([string]$hostName)) {
        $hostName = [string]$targetVmDetails.PublicIP
    }
    if ([string]::IsNullOrWhiteSpace([string]$hostName)) {
        throw "Target VM connection host could not be resolved."
    }

    $probePortText = if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) { [string]$RdpPort } else { [string]$SshPort }
    $probeLabel = if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'rdp' } else { 'ssh' }
    $probePort = 0
    if (-not [int]::TryParse($probePortText, [ref]$probePort) -or $probePort -lt 1 -or $probePort -gt 65535) {
        throw ("Target VM {0} port could not be resolved from configuration." -f $probeLabel)
    }

    $reachable = Wait-ClagnosTcpPortReachable -HostName $hostName -Port $probePort -MaxAttempts 18 -DelaySeconds 10 -TimeoutSeconds 5 -Label $probeLabel
    if (-not $reachable) {
        throw ("Target VM {0} port {1} did not become reachable on host '{2}'." -f $probeLabel, $probePort, $hostName)
    }

    return [pscustomobject]@{
        HostName = $hostName
        ProbePort = $probePort
        ProbeLabel = $probeLabel
        Vm = $parity.Vm
        Disk = $parity.Disk
    }
}

# Handles Invoke-ClagnosChangeCommand.
function Invoke-ClagnosChangeCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [string]$OperationLabel = 'move/resize'
    )

    $runtimeConfigOverrides = @{}
    $groupOptionValue = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    if (-not [string]::IsNullOrWhiteSpace([string]$groupOptionValue)) {
        $runtimeConfigOverrides['SELECTED_RESOURCE_GROUP'] = $groupOptionValue.Trim()
        Set-ClagnosConfigValueSource -Key 'SELECTED_RESOURCE_GROUP' -Source 'cli value'
    }
    $vmOptionValue = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    if (-not [string]::IsNullOrWhiteSpace([string]$vmOptionValue)) {
        $runtimeConfigOverrides['SELECTED_VM_NAME'] = $vmOptionValue.Trim()
        Set-ClagnosConfigValueSource -Key 'SELECTED_VM_NAME' -Source 'cli value'
    }

    $runtime = Initialize-ClagnosCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigMapOverrides $runtimeConfigOverrides
    $context = $runtime.Context
    $platform = [string]$runtime.Platform
    $envFilePath = [string]$runtime.EnvFilePath
    $effectiveConfigMap = $runtime.EffectiveConfigMap
    $vmSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey "VM_SIZE"
    $resourceGroup = [string]$context.ResourceGroup
    $vmName = [string]$context.VmName
    $groupWasProvided = -not [string]::IsNullOrWhiteSpace([string]$groupOptionValue)
    $vmWasProvided = -not [string]::IsNullOrWhiteSpace([string]$vmOptionValue)

    $resourceGroup = Resolve-ClagnosTargetResourceGroup `
        -Options $Options `
        -AutoMode:$AutoMode `
        -DefaultResourceGroup $resourceGroup `
        -VmName ([string]$context.VmName) `
        -OperationName $OperationLabel
    $context.ResourceGroup = $resourceGroup

    if ($vmWasProvided) {
        $vmName = [string]$vmOptionValue
    }
    else {
        $vmName = Resolve-ClagnosTargetVmName -ResourceGroup $resourceGroup -DefaultVmName $vmName -AutoMode:$AutoMode -OperationName $OperationLabel
    }
    $context.VmName = $vmName

    $hasRegionOption = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-region'
    $hasSizeOption = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-size'
    $targetRegion = ''
    $targetSize = ''

    if (-not $hasRegionOption -and -not $hasSizeOption) {
        if ($AutoMode) {
            Throw-FriendlyError `
                -Detail ("{0} command requires at least one target value in non-interactive mode." -f $OperationLabel) `
                -Code 62 `
                -Summary "No target value was provided." `
                -Hint "Use --vm-region=<region> and/or --vm-size=<sku>."
        }

        $selectedResourceGroup = Select-ClagnosResourceGroupInteractive -DefaultResourceGroup $resourceGroup -VmName ([string]$context.VmName)
        $selectedVmName = Select-ClagnosVmInteractive -ResourceGroup $selectedResourceGroup -DefaultVmName $vmName

        if (-not [string]::Equals($selectedResourceGroup, $resourceGroup, [System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals($selectedVmName, $vmName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $runtime = Initialize-ClagnosCommandRuntimeContext `
                -AutoMode:$AutoMode `
                -WindowsFlag:$WindowsFlag `
                -LinuxFlag:$LinuxFlag `
                -ConfigMapOverrides @{
                    SELECTED_RESOURCE_GROUP = $selectedResourceGroup
                    SELECTED_VM_NAME = $selectedVmName
                }
            $context = $runtime.Context
            $envFilePath = [string]$runtime.EnvFilePath
            $effectiveConfigMap = $runtime.EffectiveConfigMap
            $resourceGroup = [string]$context.ResourceGroup
            $vmName = [string]$context.VmName
        }
    }

    $vmJson = az vm show -g $resourceGroup -n $vmName -o json --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$vmJson)) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' was not found in resource group '{1}'." -f $vmName, $resourceGroup) `
            -Code 62 `
            -Summary ("{0} command cannot continue because VM does not exist." -f $OperationLabel) `
            -Hint "Run 'clagnos create' first, or check active naming values in .env."
    }

    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    $currentRegion = [string]$vmObject.location
    $currentSize = [string]$vmObject.hardwareProfile.vmSize
    $sourceResourceGroup = [string]$resourceGroup
    $sourceVmName = [string]$vmName
    $sourceLifecycleSnapshot = $null
    if ([string]::Equals([string]$OperationLabel, 'move', [System.StringComparison]::OrdinalIgnoreCase)) {
        $sourceLifecycleSnapshot = Get-ClagnosVmLifecycleSnapshot -ResourceGroup $resourceGroup -VmName $vmName
    }
    if ([string]::IsNullOrWhiteSpace($currentRegion)) { $currentRegion = [string]$context.AzLocation }
    if ([string]::IsNullOrWhiteSpace($currentSize)) { $currentSize = [string]$context.VmSize }

    if ($hasRegionOption) {
        $targetRegion = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-region')
        if ([string]::IsNullOrWhiteSpace($targetRegion)) {
            if ($AutoMode) {
                Throw-FriendlyError `
                    -Detail "Option '--vm-region' was provided without a value in auto mode." `
                    -Code 62 `
                    -Summary "Region value is required in auto mode." `
                    -Hint "Provide --vm-region=<azure-region>."
            }
            $targetRegion = Select-AzLocationInteractive -DefaultLocation $currentRegion
        }
    }

    if ($hasSizeOption) {
        $targetSize = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-size')
        if ([string]::IsNullOrWhiteSpace($targetSize)) {
            if ($AutoMode) {
                Throw-FriendlyError `
                    -Detail "Option '--vm-size' was provided without a value in auto mode." `
                    -Code 62 `
                    -Summary "VM size value is required in auto mode." `
                    -Hint "Provide --vm-size=<vm-sku>."
            }

            $pickerLocation = $currentRegion
            if (-not [string]::IsNullOrWhiteSpace($targetRegion)) {
                $pickerLocation = $targetRegion
            }
            $priceHours = Get-PriceHoursFromConfig -Config $effectiveConfigMap -DefaultHours 730
            while ($true) {
                $sizePick = Select-VmSkuInteractive -Location $pickerLocation -DefaultVmSize $currentSize -PriceHours $priceHours
                if ([string]::Equals([string]$sizePick, (Get-ClagnosSkuPickerRegionBackToken), [System.StringComparison]::Ordinal)) {
                    $pickerLocation = Select-AzLocationInteractive -DefaultLocation $pickerLocation
                    if (-not $hasRegionOption) {
                        $targetRegion = $pickerLocation
                    }
                    continue
                }
                $targetSize = [string]$sizePick
                break
            }
        }
    }

    if (-not $hasRegionOption -and -not $hasSizeOption) {
        $targetRegion = Select-AzLocationInteractive -DefaultLocation $currentRegion
        $hasRegionOption = $true
        $priceHours = Get-PriceHoursFromConfig -Config $effectiveConfigMap -DefaultHours 730
        while ($true) {
            $sizePick = Select-VmSkuInteractive -Location $targetRegion -DefaultVmSize $currentSize -PriceHours $priceHours
            if ([string]::Equals([string]$sizePick, (Get-ClagnosSkuPickerRegionBackToken), [System.StringComparison]::Ordinal)) {
                $targetRegion = Select-AzLocationInteractive -DefaultLocation $targetRegion
                continue
            }
            $targetSize = [string]$sizePick
            $hasSizeOption = $true
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($targetRegion)) { $targetRegion = $currentRegion }
    if ([string]::IsNullOrWhiteSpace($targetSize)) { $targetSize = $currentSize }
    $targetRegion = $targetRegion.Trim().ToLowerInvariant()
    $targetSize = $targetSize.Trim()

    Assert-LocationExists -Location $targetRegion
    Assert-VmSkuAvailableViaRest -Location $targetRegion -VmSize $targetSize

    $regionChanged = -not [string]::Equals($targetRegion, $currentRegion, [System.StringComparison]::OrdinalIgnoreCase)
    $sizeChanged = -not [string]::Equals($targetSize, $currentSize, [System.StringComparison]::OrdinalIgnoreCase)
    if (-not $regionChanged -and -not $sizeChanged) {
        Write-Host ("No effective {0} operation is required. Region and VM size are already at target values." -f $OperationLabel) -ForegroundColor Yellow
        return
    }

    $regionMoveApplied = $false
    $activeResourceGroup = $resourceGroup
    $activeVmName = $vmName

    if ($regionChanged) {
        Write-Host "Applying snapshot-based region migration."
        Write-Host ("Current: region={0}, size={1}, rg={2}" -f $currentRegion, $currentSize, $resourceGroup)
        Write-Host ("Target : region={0}, size={1}" -f $targetRegion, $targetSize)

        if (-not $AutoMode) {
            $approveRegionMove = Confirm-YesNo -PromptText "Continue with snapshot-based region migration?" -DefaultYes $false
            if (-not $approveRegionMove) {
                Write-Host ("{0} command canceled by user." -f $OperationLabel) -ForegroundColor Yellow
                return
            }
        }

        $sourceOsDiskId = [string]$vmObject.storageProfile.osDisk.managedDisk.id
        if ([string]::IsNullOrWhiteSpace([string]$sourceOsDiskId)) {
            Throw-FriendlyError `
                -Detail "Source VM OS disk id could not be resolved." `
                -Code 62 `
                -Summary "Region move cannot continue." `
                -Hint "Check VM storage profile and retry."
        }

        $dataDisks = @($vmObject.storageProfile.dataDisks)
        if ($dataDisks.Count -gt 0) {
            Throw-FriendlyError `
                -Detail ("Attached data disk count: {0}." -f $dataDisks.Count) `
                -Code 62 `
                -Summary "Snapshot region move currently supports OS disk only." `
                -Hint "Detach/migrate data disks separately, then retry."
        }

        $sourceOsDiskName = [string]$vmObject.storageProfile.osDisk.name
        if ([string]::IsNullOrWhiteSpace([string]$sourceOsDiskName)) {
            $sourceOsDiskName = [string]($sourceOsDiskId -split '/')[-1]
        }
        Assert-ClagnosMoveSourceGroupPurgeSafe -ResourceGroup $resourceGroup -VmName $vmName -OsDiskName $sourceOsDiskName | Out-Null

        $sourceDiskJson = az disk show --ids $sourceOsDiskId -o json --only-show-errors
        Assert-LastExitCode "az disk show (source os disk)"
        $sourceDisk = ConvertFrom-JsonCompat -InputObject $sourceDiskJson
        $sourceDiskSku = [string]$sourceDisk.sku.name
        $sourceOsType = [string]$sourceDisk.osType
        $sourceDiskSizeGb = 0
        if ($null -ne $sourceDisk.diskSizeGb) {
            $sourceDiskSizeGb = [int]$sourceDisk.diskSizeGb
        }
        $sourceDiskSupportsHibernation = $false
        if ($sourceDisk.PSObject.Properties.Match('supportsHibernation').Count -gt 0 -and $null -ne $sourceDisk.supportsHibernation) {
            $sourceDiskSupportsHibernation = [bool]$sourceDisk.supportsHibernation
        }
        $sourceVmHibernationEnabled = $false
        if ($null -ne $sourceLifecycleSnapshot) {
            $sourceVmHibernationEnabled = [bool]$sourceLifecycleSnapshot.HibernationEnabled
        }
        if ([string]::IsNullOrWhiteSpace([string]$sourceDiskSku)) { $sourceDiskSku = "StandardSSD_LRS" }
        if ([string]::IsNullOrWhiteSpace([string]$sourceOsType)) { $sourceOsType = "Windows" }

        $targetRegionCode = Get-ClagnosRegionCode -Location $targetRegion
        $nameTokens = @{
            SELECTED_VM_NAME = [string]$context.VmName
            REGION_CODE = [string]$targetRegionCode
        }

        $targetResourceGroupTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "RESOURCE_GROUP_TEMPLATE" -DefaultValue "rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}")
        $targetResourceGroup = Resolve-ClagnosResourceGroupNameFromTemplate `
            -Template $targetResourceGroupTemplate `
            -VmName ([string]$context.VmName) `
            -RegionCode $targetRegionCode `
            -UseNextIndex

        $targetDiskTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "VM_DISK_NAME_TEMPLATE" -DefaultValue "disk-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetVnetTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "VNET_NAME_TEMPLATE" -DefaultValue "net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetSubnetTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "SUBNET_NAME_TEMPLATE" -DefaultValue "subnet-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetNsgTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "NSG_NAME_TEMPLATE" -DefaultValue "nsg-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetNsgRuleTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "NSG_RULE_NAME_TEMPLATE" -DefaultValue "nsg-rule-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetIpTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "PUBLIC_IP_NAME_TEMPLATE" -DefaultValue "ip-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetNicTemplate = [string](Get-ConfigValue -Config $effectiveConfigMap -Key "NIC_NAME_TEMPLATE" -DefaultValue "nic-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}")
        $targetResourceIndexAllocator = New-ClagnosManagedResourceIndexAllocator

        $targetVmName = [string]$context.VmName
        $targetDiskName = Resolve-ClagnosNameFromTemplate -Template $targetDiskTemplate -ResourceType 'disk' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-disk'
        $targetVnetName = Resolve-ClagnosNameFromTemplate -Template $targetVnetTemplate -ResourceType 'net' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-vnet'
        $targetSubnetName = Resolve-ClagnosNameFromTemplate -Template $targetSubnetTemplate -ResourceType 'subnet' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-subnet'
        $targetNsgName = Resolve-ClagnosNameFromTemplate -Template $targetNsgTemplate -ResourceType 'nsg' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-nsg'
        $targetNsgRuleName = Resolve-ClagnosNameFromTemplate -Template $targetNsgRuleTemplate -ResourceType 'nsgrule' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-nsg-rule'
        $targetIpName = Resolve-ClagnosNameFromTemplate -Template $targetIpTemplate -ResourceType 'ip' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-ip'
        $targetNicName = Resolve-ClagnosNameFromTemplate -Template $targetNicTemplate -ResourceType 'nic' -VmName ([string]$context.VmName) -RegionCode $targetRegionCode -ResourceGroup $targetResourceGroup -UseNextIndex -IndexAllocator $targetResourceIndexAllocator -LogicalName 'move-target-nic'

        Write-Host ("Target naming resolved: rg={0}, vm={1}, disk={2}" -f $targetResourceGroup, $targetVmName, $targetDiskName)

        $targetGroupCreatedInRun = $false
        $sourceSnapshotName = ''
        $targetSnapshotName = ''
        $sourceSnapshotCreated = $false
        $targetSnapshotCreated = $false
        $targetVmCreated = $false
        $targetDiskCreated = $false
        $targetNetworkAttempted = $false
        $sourceNeedsStartRecovery = ($null -ne $sourceLifecycleSnapshot -and [string]::Equals([string]$sourceLifecycleSnapshot.NormalizedState, 'started', [System.StringComparison]::OrdinalIgnoreCase))
        $sourceWasDeallocatedInMove = $false

        $cleanupTarget = {
            param([string]$Reason)
            Write-Host ("Region move cleanup started. Reason: {0}" -f $Reason) -ForegroundColor Yellow

            if ($targetVmCreated) {
                az vm delete -g $targetResourceGroup -n $targetVmName --yes -o none --only-show-errors 2>$null
            }
            if ($targetDiskCreated) {
                az disk delete -g $targetResourceGroup -n $targetDiskName --yes -o none --only-show-errors 2>$null
            }

            if ($targetNetworkAttempted) {
                az network nic delete -g $targetResourceGroup -n $targetNicName --only-show-errors 2>$null
                az network public-ip delete -g $targetResourceGroup -n $targetIpName --only-show-errors 2>$null
                az network nsg delete -g $targetResourceGroup -n $targetNsgName --only-show-errors 2>$null
                az network vnet delete -g $targetResourceGroup -n $targetVnetName --only-show-errors 2>$null
            }

            if ($targetSnapshotCreated -and -not [string]::IsNullOrWhiteSpace([string]$targetSnapshotName)) {
                az snapshot delete -g $targetResourceGroup -n $targetSnapshotName --only-show-errors 2>$null
            }
            if ($sourceSnapshotCreated -and -not [string]::IsNullOrWhiteSpace([string]$sourceSnapshotName)) {
                az snapshot delete -g $resourceGroup -n $sourceSnapshotName --only-show-errors 2>$null
            }
        }

        try {
            $sourceAlreadyDeallocated = ($null -ne $sourceLifecycleSnapshot -and [string]$sourceLifecycleSnapshot.NormalizedState -in @('deallocated','hibernated'))
            if (-not $sourceAlreadyDeallocated) {
                Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
                    az vm deallocate -g $resourceGroup -n $vmName -o none --only-show-errors
                    Assert-LastExitCode "az vm deallocate (source)"
                } | Out-Null
                $sourceDeallocated = Wait-ClagnosVmPowerState -ResourceGroup $resourceGroup -VmName $vmName -DesiredPowerState "VM deallocated" -MaxAttempts 24 -DelaySeconds 10
                if (-not $sourceDeallocated) {
                    throw "Source VM did not reach deallocated state before snapshot creation."
                }
                $sourceWasDeallocatedInMove = $true
            }

            $targetGroupExists = az group exists -n $targetResourceGroup --only-show-errors
            Assert-LastExitCode "az group exists (target)"
            if (-not [string]::Equals([string]$targetGroupExists, "true", [System.StringComparison]::OrdinalIgnoreCase)) {
                Invoke-TrackedAction -Label ("az group create -n {0} -l {1}" -f $targetResourceGroup, $targetRegion) -Action {
                    az group create -n $targetResourceGroup -l $targetRegion --tags ("{0}={1}" -f [string]$script:ManagedByTagKey, [string]$script:ManagedByTagValue) -o none --only-show-errors
                    Assert-LastExitCode "az group create (target)"
                } | Out-Null
                $targetGroupCreatedInRun = $true
            }
            Set-ClagnosManagedTagOnResourceGroup -ResourceGroup $targetResourceGroup

            $stamp = Get-Date -Format "yyMMddHHmmss"
            $sourceSnapshotName = ("snap-src-{0}-{1}" -f [string]$context.VmName, $stamp)
            $targetSnapshotName = ("snap-dst-{0}-{1}" -f [string]$context.VmName, $stamp)

            Invoke-TrackedAction -Label ("az snapshot create source incremental {0}" -f $sourceSnapshotName) -Action {
                az snapshot create -g $resourceGroup -n $sourceSnapshotName --source $sourceOsDiskId --location $currentRegion --incremental true --sku Standard_LRS -o none --only-show-errors
                Assert-LastExitCode "az snapshot create (source)"
            } | Out-Null
            $sourceSnapshotCreated = $true

            $sourceSnapshotId = az snapshot show -g $resourceGroup -n $sourceSnapshotName --query "id" -o tsv --only-show-errors
            Assert-LastExitCode "az snapshot show (source id)"
            if ([string]::IsNullOrWhiteSpace([string]$sourceSnapshotId)) { throw "Source snapshot id could not be resolved." }

            Invoke-TrackedAction -Label ("az snapshot create target copy-start {0}" -f $targetSnapshotName) -Action {
                az snapshot create -g $targetResourceGroup -n $targetSnapshotName --source $sourceSnapshotId --location $targetRegion --incremental true --sku Standard_LRS --copy-start true -o none --only-show-errors
                Assert-LastExitCode "az snapshot create (target)"
            } | Out-Null
            $targetSnapshotCreated = $true

            Wait-ClagnosSnapshotCopyReady -ResourceGroup $targetResourceGroup -SnapshotName $targetSnapshotName -MaxAttempts 540 -DelaySeconds 20 -NoProgressAttemptLimit 45 | Out-Null

            $targetSnapshotId = az snapshot show -g $targetResourceGroup -n $targetSnapshotName --query "id" -o tsv --only-show-errors
            Assert-LastExitCode "az snapshot show (target id)"
            if ([string]::IsNullOrWhiteSpace([string]$targetSnapshotId)) { throw "Target snapshot id could not be resolved." }

            $targetContext = [ordered]@{
                ResourceGroup = $targetResourceGroup
                AzLocation = $targetRegion
                VNET = $targetVnetName
                SUBNET = $targetSubnetName
                NSG = $targetNsgName
                NsgRule = $targetNsgRuleName
                IP = $targetIpName
                PublicDnsLabel = (Resolve-ClagnosPublicDnsLabel -PublicIpName ([string]$targetIpName) -VmName ([string]$targetVmName))
                NIC = $targetNicName
                TcpPorts = @($context.TcpPorts)
                VmName = $targetVmName
            }
            Invoke-ClagnosNetworkStep -Context $targetContext -ExecutionMode "update"
            $targetNetworkAttempted = $true

            Invoke-TrackedAction -Label ("az disk create -g {0} -n {1}" -f $targetResourceGroup, $targetDiskName) -Action {
                $diskArgs = @("disk", "create", "-g", $targetResourceGroup, "-n", $targetDiskName, "--source", $targetSnapshotId, "--location", $targetRegion, "--sku", $sourceDiskSku, "--os-type", $sourceOsType, "-o", "none", "--only-show-errors")
                az @diskArgs
                Assert-LastExitCode "az disk create (target)"
            } | Out-Null
            $targetDiskCreated = $true

            if ($sourceDiskSupportsHibernation) {
                Invoke-TrackedAction -Label ("az disk update -g {0} -n {1} --set supportsHibernation=true" -f $targetResourceGroup, $targetDiskName) -Action {
                    az disk update -g $targetResourceGroup -n $targetDiskName --set supportsHibernation=true -o none --only-show-errors
                    Assert-LastExitCode "az disk update (target supportsHibernation)"
                } | Out-Null
            }

            $targetCreateJson = Invoke-TrackedAction -Label ("az vm create -g {0} -n {1} --attach-os-disk" -f $targetResourceGroup, $targetVmName) -Action {
                $vmCreateArgs = @("vm", "create", "--resource-group", $targetResourceGroup, "--name", $targetVmName, "--attach-os-disk", $targetDiskName, "--os-type", $sourceOsType, "--size", $currentSize, "--nics", $targetNicName, "-o", "json", "--only-show-errors")
                az @vmCreateArgs
            }
            Assert-LastExitCode "az vm create (target attach-os-disk)"
            $targetCreateObj = ConvertFrom-JsonCompat -InputObject $targetCreateJson
            if (-not $targetCreateObj.id) { throw "Target VM creation returned no VM id." }
            $targetVmCreated = $true

            $targetNeedsDeallocate = $sourceVmHibernationEnabled -or (-not [string]::Equals([string]$targetSize, [string]$currentSize, [System.StringComparison]::OrdinalIgnoreCase))
            if ($targetNeedsDeallocate) {
                Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $targetResourceGroup, $targetVmName) -Action {
                    az vm deallocate -g $targetResourceGroup -n $targetVmName -o none --only-show-errors
                    Assert-LastExitCode "az vm deallocate (target)"
                } | Out-Null
                $targetDeallocated = Wait-ClagnosVmPowerState -ResourceGroup $targetResourceGroup -VmName $targetVmName -DesiredPowerState "VM deallocated" -MaxAttempts 18 -DelaySeconds 10
                if (-not $targetDeallocated) { throw "Target VM did not reach deallocated state before resize." }
            }

            if ($sourceVmHibernationEnabled) {
                Invoke-TrackedAction -Label ("az vm update -g {0} -n {1} --enable-hibernation true" -f $targetResourceGroup, $targetVmName) -Action {
                    az vm update -g $targetResourceGroup -n $targetVmName --enable-hibernation true -o none --only-show-errors
                    Assert-LastExitCode "az vm update (target enable hibernation)"
                } | Out-Null
            }

            if (-not [string]::Equals([string]$targetSize, [string]$currentSize, [System.StringComparison]::OrdinalIgnoreCase)) {
                Invoke-TrackedAction -Label ("az vm resize -g {0} -n {1} --size {2}" -f $targetResourceGroup, $targetVmName, $targetSize) -Action {
                    az vm resize -g $targetResourceGroup -n $targetVmName --size $targetSize -o none --only-show-errors
                    Assert-LastExitCode "az vm resize (target)"
                } | Out-Null
                $currentSize = $targetSize
            }

            Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $targetResourceGroup, $targetVmName) -Action {
                az vm start -g $targetResourceGroup -n $targetVmName -o none --only-show-errors
                Assert-LastExitCode "az vm start (target)"
            } | Out-Null
            $targetRunning = Wait-ClagnosVmRunningState -ResourceGroup $targetResourceGroup -VmName $targetVmName -MaxAttempts 6 -DelaySeconds 10
            if (-not $targetRunning) { throw "Target VM did not reach running state after migration." }

            if ($targetSnapshotCreated -and -not [string]::IsNullOrWhiteSpace([string]$targetSnapshotName)) { az snapshot delete -g $targetResourceGroup -n $targetSnapshotName --only-show-errors 2>$null }
            if ($sourceSnapshotCreated -and -not [string]::IsNullOrWhiteSpace([string]$sourceSnapshotName)) { az snapshot delete -g $resourceGroup -n $sourceSnapshotName --only-show-errors 2>$null }

            $activeResourceGroup = $targetResourceGroup
            $activeVmName = $targetVmName
            $resourceGroup = $targetResourceGroup
            $vmName = $targetVmName
            $currentRegion = $targetRegion
            $regionMoveApplied = $true

            $context.ResourceGroup = $targetResourceGroup
            $context.AzLocation = $targetRegion
            $context.RegionCode = $targetRegionCode
            $context.VmName = $targetVmName
            $context.VmDiskName = $targetDiskName
            $context.VNET = $targetVnetName
            $context.SUBNET = $targetSubnetName
            $context.NSG = $targetNsgName
            $context.NsgRule = $targetNsgRuleName
            $context.IP = $targetIpName
            $context.NIC = $targetNicName

            Write-Host ("Region migration completed. Active target -> rg={0}, vm={1}" -f $activeResourceGroup, $activeVmName) -ForegroundColor Green
        }
        catch {
            $innerError = $_
            & $cleanupTarget -Reason ([string]$innerError.Exception.Message)
            $sourceRecoveryNote = ''
            if ($sourceNeedsStartRecovery -and $sourceWasDeallocatedInMove) {
                try {
                    Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $sourceResourceGroup, $sourceVmName) -Action {
                        az vm start -g $sourceResourceGroup -n $sourceVmName -o none --only-show-errors
                        Assert-LastExitCode "az vm start (source recovery)"
                    } | Out-Null
                    $sourceRecovered = Wait-ClagnosVmRunningState -ResourceGroup $sourceResourceGroup -VmName $sourceVmName -MaxAttempts 6 -DelaySeconds 10
                    if ($sourceRecovered) {
                        $sourceRecoveryNote = " Source VM was restarted after rollback."
                    }
                    else {
                        $sourceRecoveryNote = " Source VM restart was attempted after rollback but running state was not confirmed."
                    }
                }
                catch {
                    $sourceRecoveryNote = (" Source VM restart failed after rollback: {0}" -f $_.Exception.Message)
                }
            }
            Throw-FriendlyError `
                -Detail ("Snapshot-based region migration failed. Cleanup completed. Error: {0}.{1}" -f $innerError.Exception.Message, $sourceRecoveryNote) `
                -Code 62 `
                -Summary "Region move failed and target-side artifacts were rolled back." `
                -Hint ("Review failure detail, then retry {0} command." -f $OperationLabel)
        }
    }

    $sizeChangedAfterRegion = -not [string]::Equals([string]$currentSize, [string]$targetSize, [System.StringComparison]::OrdinalIgnoreCase)
    if ($sizeChangedAfterRegion) {
        Write-Host ("Applying VM size update: {0} -> {1}" -f $currentSize, $targetSize)
        if (-not $AutoMode -and -not $regionMoveApplied) {
            $approveResize = Confirm-YesNo -PromptText "Continue with VM size change?" -DefaultYes $false
            if (-not $approveResize) {
                Write-Host ("{0} command canceled by user." -f $OperationLabel) -ForegroundColor Yellow
                return
            }
        }

        Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $activeResourceGroup, $activeVmName) -Action {
            az vm deallocate -g $activeResourceGroup -n $activeVmName -o none --only-show-errors
            Assert-LastExitCode "az vm deallocate"
        } | Out-Null
        $deallocated = Wait-ClagnosVmPowerState -ResourceGroup $activeResourceGroup -VmName $activeVmName -DesiredPowerState "VM deallocated" -MaxAttempts 18 -DelaySeconds 10
        if (-not $deallocated) {
            Throw-FriendlyError `
                -Detail ("VM '{0}' did not reach deallocated state in expected time." -f $activeVmName) `
                -Code 62 `
                -Summary "VM size change stopped because VM deallocation was not confirmed." `
                -Hint ("Check VM power state in Azure and retry {0} command." -f $OperationLabel)
        }

        Invoke-TrackedAction -Label ("az vm resize -g {0} -n {1} --size {2}" -f $activeResourceGroup, $activeVmName, $targetSize) -Action {
            az vm resize -g $activeResourceGroup -n $activeVmName --size $targetSize -o none --only-show-errors
            Assert-LastExitCode "az vm resize"
        } | Out-Null
        $currentSize = $targetSize
    }
    else {
        Write-Host ("VM size is already '{0}'; resize step is skipped." -f $targetSize) -ForegroundColor Yellow
    }

    Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $activeResourceGroup, $activeVmName) -Action {
        az vm start -g $activeResourceGroup -n $activeVmName -o none --only-show-errors
        Assert-LastExitCode "az vm start"
    } | Out-Null

    $running = Wait-ClagnosVmRunningState -ResourceGroup $activeResourceGroup -VmName $activeVmName -MaxAttempts 3 -DelaySeconds 10
    if (-not $running) {
        Throw-FriendlyError `
            -Detail ("VM did not return to running state after {0} operation." -f $OperationLabel) `
            -Code 62 `
            -Summary ("{0} command completed with unhealthy VM power state." -f $OperationLabel) `
            -Hint "Check VM power state in Azure Portal and start VM manually if needed."
    }

    if ($regionMoveApplied) {
        try {
            $healthCheck = Invoke-ClagnosMoveTargetHealthCheck `
                -ResourceGroup $activeResourceGroup `
                -VmName $activeVmName `
                -Platform $platform `
                -ExpectedRegion $targetRegion `
                -ExpectedVmSize $currentSize `
                -ExpectedDiskSku $sourceDiskSku `
                -ExpectedDiskSizeGb $sourceDiskSizeGb `
                -ExpectedDiskSupportsHibernation:$sourceDiskSupportsHibernation `
                -ExpectedVmHibernationEnabled:$sourceVmHibernationEnabled `
                -SshPort ([string]$context.SshPort) `
                -RdpPort ([string]$context.RdpPort)

            Write-Host ("Target move health gate passed: {0} {1}:{2}" -f [string]$healthCheck.ProbeLabel, [string]$healthCheck.HostName, [int]$healthCheck.ProbePort) -ForegroundColor Green
        }
        catch {
            Throw-FriendlyError `
                -Detail ("Target region cutover validation failed for VM '{0}' in resource group '{1}': {2}" -f $activeVmName, $activeResourceGroup, $_.Exception.Message) `
                -Code 62 `
                -Summary "Move command stopped before source cleanup because target validation did not pass." `
                -Hint "Review the target VM state, rerun the health check, and only delete the old source group after the target is confirmed healthy."
        }
    }

    if ($regionMoveApplied) {
        Set-DotEnvValue -Path $envFilePath -Key 'SELECTED_AZURE_REGION' -Value $targetRegion
        Set-DotEnvValue -Path $envFilePath -Key 'SELECTED_RESOURCE_GROUP' -Value $activeResourceGroup
        Set-DotEnvValue -Path $envFilePath -Key 'SELECTED_VM_NAME' -Value ([string]$context.VmName)
        Remove-ClagnosUnsupportedDotEnvKeys -Path $envFilePath

        $script:ConfigOverrides['SELECTED_AZURE_REGION'] = $targetRegion
        $script:ConfigOverrides['SELECTED_RESOURCE_GROUP'] = $activeResourceGroup
        $script:ConfigOverrides['SELECTED_VM_NAME'] = [string]$context.VmName
        Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_REGION' -Source 'azure value'
        Set-ClagnosConfigValueSource -Key 'SELECTED_RESOURCE_GROUP' -Source 'azure value'
        Set-ClagnosConfigValueSource -Key 'SELECTED_VM_NAME' -Source 'azure value'
    }

    if ($sizeChangedAfterRegion) {
        Set-DotEnvValue -Path $envFilePath -Key $vmSizeConfigKey -Value $targetSize
        $script:ConfigOverrides[$vmSizeConfigKey] = $targetSize
        Set-ClagnosConfigValueSource -Key $vmSizeConfigKey -Source 'cli value'
    }

    if ($regionMoveApplied) {
        try {
            Invoke-TrackedAction -Label ("az group delete -n {0} --yes --no-wait" -f $sourceResourceGroup) -Action {
                az group delete -n $sourceResourceGroup --yes --no-wait --only-show-errors
                Assert-LastExitCode "az group delete (source cleanup)"
            } | Out-Null
            Invoke-TrackedAction -Label ("az group wait -n {0} --deleted" -f $sourceResourceGroup) -Action {
                az group wait -n $sourceResourceGroup --deleted --only-show-errors
                Assert-LastExitCode "az group wait --deleted (source cleanup)"
            } | Out-Null
        }
        catch {
            Throw-FriendlyError `
                -Detail ("Target cutover to resource group '{0}' succeeded, but old source resource group '{1}' could not be deleted: {2}" -f $activeResourceGroup, $sourceResourceGroup, $_.Exception.Message) `
                -Code 62 `
                -Summary "Move command completed target cutover but old-source cleanup failed." `
                -Hint ("Delete the old source group '{0}' manually after confirming the new target is healthy." -f $sourceResourceGroup)
        }

        Write-Host ("Change completed successfully. Region='{0}', VM size='{1}', active resource group='{2}'." -f $targetRegion, $currentSize, $activeResourceGroup) -ForegroundColor Green
    }
    else {
        Write-Host ("Change completed successfully. VM size is now '{0}'." -f $targetSize) -ForegroundColor Green
    }
}
