# Resize command entry.

function Invoke-ProdicloudResizeCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    if (Test-ProdicloudCliOptionPresent -Options $Options -Name 'vm-region') {
        Throw-FriendlyError `
            -Detail "Option '--vm-region' is not supported with resize command." `
            -Code 62 `
            -Summary "Unsupported option for resize command." `
            -Hint "Use move command for region changes."
    }

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Get-ProdicloudGlobalEnvPath
    $configMap = Read-DotEnvFile -Path $envFilePath -GlobalOnly
    $operationRequest = Resolve-ProdicloudResizeOperationRequest -Options $Options
    $target = Resolve-ProdicloudManagedVmTarget -Options $Options -ConfigMap $configMap -OperationName 'resize'
    $resourceGroup = [string]$target.ResourceGroup
    $vmName = [string]$target.VmName
    $isDirectRequest = Test-ProdicloudResizeDirectRequest -Options $Options

    Write-ProdicloudActionProgress -Action ("inspect resize target '{0}' in '{1}'" -f $vmName, $resourceGroup)
    $vmJson = az vm show -g $resourceGroup -n $vmName -o json --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$vmJson)) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' was not found in resource group '{1}'." -f $vmName, $resourceGroup) `
            -Code 62 `
            -Summary "Resize command cannot continue because VM does not exist." `
            -Hint "Select an existing VM or run create first."
    }

    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    $currentRegion = [string]$vmObject.location
    $currentSize = [string]$vmObject.hardwareProfile.vmSize
    $actualPlatform = Get-ProdicloudPlatformNameFromOsType -OsType ([string]$vmObject.storageProfile.osDisk.osType)
    $vmSizeConfigKey = if ([string]::IsNullOrWhiteSpace([string]$actualPlatform)) { 'VM_SIZE' } else { Get-ProdicloudPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_SIZE' }
    $vmDiskSizeConfigKey = if ([string]::IsNullOrWhiteSpace([string]$actualPlatform)) { 'VM_DISK_SIZE_GB' } else { Get-ProdicloudPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_DISK_SIZE_GB' }

    Assert-ProdicloudResizePlatformExpectation `
        -ActualPlatform $actualPlatform `
        -WindowsFlag:$WindowsFlag `
        -LinuxFlag:$LinuxFlag `
        -VmName $vmName `
        -ResourceGroup $resourceGroup

    if ([string]::IsNullOrWhiteSpace([string]$currentRegion)) {
        Throw-FriendlyError `
            -Detail ("Resize command could not resolve the Azure region for VM '{0}'." -f $vmName) `
            -Code 62 `
            -Summary "Resize command cannot continue because VM region is unknown." `
            -Hint "Check the VM metadata in Azure, then retry."
    }
    if ([string]::IsNullOrWhiteSpace([string]$currentSize)) {
        Throw-FriendlyError `
            -Detail ("Resize command could not resolve the current VM size for '{0}'." -f $vmName) `
            -Code 62 `
            -Summary "Resize command cannot continue because current VM size is unknown." `
            -Hint "Check the VM metadata in Azure, then retry."
    }

    if ([string]::Equals([string]$operationRequest.Kind, 'disk', [System.StringComparison]::OrdinalIgnoreCase)) {
        $initialSnapshot = Get-ProdicloudVmLifecycleSnapshot -ResourceGroup $resourceGroup -VmName $vmName
        Invoke-ProdicloudResizeDiskOperation -Options $Options -VmObject $vmObject -OperationRequest $operationRequest -ResourceGroup $resourceGroup -VmName $vmName -Region $currentRegion -Platform $actualPlatform -InitialSnapshot $initialSnapshot
        return
    }

    $targetSize = Resolve-ProdicloudResizeTargetSize -Options $Options -CurrentRegion $currentRegion -CurrentSize $currentSize -ConfigMap $configMap
    Write-ProdicloudActionProgress -Action ("validate VM size '{0}' in region '{1}'" -f $targetSize, $currentRegion)
    Assert-LocationExists -Location $currentRegion
    Assert-VmSkuAvailableViaRest -Location $currentRegion -VmSize $targetSize

    if ([string]::Equals([string]$targetSize, [string]$currentSize, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("No effective resize operation is required. VM size is already '{0}'." -f $targetSize) -ForegroundColor Yellow
        return
    }

    if (-not $isDirectRequest) {
        $approveResize = Confirm-YesNo -PromptText "Continue with VM size change?" -DefaultYes $false
        if (-not $approveResize) {
            Write-Host "Resize command canceled by user." -ForegroundColor Yellow
            return
        }
    }

    $beforeSnapshot = Get-ProdicloudResizeLifecycleSnapshot -ResourceGroup $resourceGroup -VmName $vmName -Stage 'before resize'
    $allocationFailed = ($null -ne $beforeSnapshot -and [string]$beforeSnapshot.ProvisioningStateCode -match '(?i)failed')
    $initialPowerState = if ($allocationFailed) {
        Write-Warning 'Azure reports a failed provisioning/allocation state; resize recovery will deallocate, apply the requested SKU, and retry start.'
        'started'
    }
    else {
        Assert-ProdicloudResizeLifecycleStateSupported -Snapshot $beforeSnapshot -VmName $vmName
    }
    if ($null -ne $beforeSnapshot -and [bool]$beforeSnapshot.HibernationEnabled) {
        Write-ProdicloudActionProgress -Action ("verify hibernation support for target SKU '{0}'" -f $targetSize)
        $hibernationSupport = Get-ProdicloudHibernationSupportInfo -Location $currentRegion -VmSize $targetSize
        if ([bool]$hibernationSupport.Known -and -not [bool]$hibernationSupport.Supported) {
            Throw-FriendlyError `
                -Detail ("VM hibernation is enabled, but target SKU '{0}' in '{1}' does not advertise hibernation support. {2}" -f $targetSize,$currentRegion,(Resolve-ProdicloudFeatureSupportReasonText -FeatureLabel 'Hibernation' -CapabilityLabel 'HibernationSupported' -ReasonCode ([string]$hibernationSupport.Message) -Evidence @($hibernationSupport.Evidence))) `
                -Code 62 `
                -Summary 'VM resize is incompatible with its enabled hibernation feature.' `
                -Hint 'Select a regionally available SKU that supports hibernation or disable hibernation first.'
        }
    }
    Write-Host ("Applying VM size update for '{0}' in '{1}': {2} -> {3}" -f $vmName, $resourceGroup, $currentSize, $targetSize)
    Write-ProdicloudResizeStateSnapshot -Stage 'before' -VmName $vmName -ResourceGroup $resourceGroup -Region $currentRegion -VmSize $currentSize -LifecycleSnapshot $beforeSnapshot

    Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
        az vm deallocate -g $resourceGroup -n $vmName -o none --only-show-errors
        Assert-LastExitCode "az vm deallocate"
    } | Out-Null
    $deallocated = Wait-ProdicloudVmPowerState -ResourceGroup $resourceGroup -VmName $vmName -DesiredPowerState "VM deallocated" -MaxAttempts 18 -DelaySeconds 10
    if (-not $deallocated) {
        if ($allocationFailed) {
            Write-Warning 'Azure accepted deallocation for the allocation-failed VM but did not report a power state. Continuing with the repair resize after the successful deallocate command.'
        }
        else {
        Throw-FriendlyError `
            -Detail ("VM '{0}' did not reach deallocated state in expected time." -f $vmName) `
            -Code 62 `
            -Summary "Resize command stopped because VM deallocation was not confirmed." `
            -Hint "Check VM power state in Azure and retry resize."
        }
    }

    Invoke-TrackedAction -Label ("az vm resize -g {0} -n {1} --size {2}" -f $resourceGroup, $vmName, $targetSize) -Action {
        az vm resize -g $resourceGroup -n $vmName --size $targetSize -o none --only-show-errors
        Assert-LastExitCode "az vm resize"
    } | Out-Null

    Set-ProdicloudResizeVmPowerState -ResourceGroup $resourceGroup -VmName $vmName -DesiredState $initialPowerState

    $afterSnapshot = Get-ProdicloudResizeLifecycleSnapshot -ResourceGroup $resourceGroup -VmName $vmName -Stage 'after resize'
    $actualSize = Get-ProdicloudResizeVmSizeReadback -ResourceGroup $resourceGroup -VmName $vmName
    Write-ProdicloudResizeStateSnapshot -Stage 'after' -VmName $vmName -ResourceGroup $resourceGroup -Region $currentRegion -VmSize $actualSize -LifecycleSnapshot $afterSnapshot
    Assert-ProdicloudResizeReadback -Kind 'vm-size' -ExpectedValue $targetSize -ActualValue $actualSize -ResourceGroup $resourceGroup -VmName $vmName -LifecycleSnapshot $afterSnapshot

    Set-DotEnvValue -Path $envFilePath -Key $vmSizeConfigKey -Value $targetSize -VmName $vmName
    $script:ConfigOverrides[$vmSizeConfigKey] = $targetSize

    Write-Host ("Resize completed successfully. VM size is now '{0}'." -f $targetSize) -ForegroundColor Green
}
