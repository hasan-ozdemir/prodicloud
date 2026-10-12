# Resize command entry.

function Invoke-ClagnosResizeCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    if (Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-region') {
        Throw-FriendlyError `
            -Detail "Option '--vm-region' is not supported with resize command." `
            -Code 62 `
            -Summary "Unsupported option for resize command." `
            -Hint "Use move command for region changes."
    }

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $operationRequest = Resolve-ClagnosResizeOperationRequest -Options $Options
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $configMap -OperationName 'resize'
    $resourceGroup = [string]$target.ResourceGroup
    $vmName = [string]$target.VmName
    $isDirectRequest = Test-ClagnosResizeDirectRequest -Options $Options

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
    $actualPlatform = Get-ClagnosPlatformNameFromOsType -OsType ([string]$vmObject.storageProfile.osDisk.osType)
    $vmSizeConfigKey = if ([string]::IsNullOrWhiteSpace([string]$actualPlatform)) { 'VM_SIZE' } else { Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_SIZE' }
    $vmDiskSizeConfigKey = if ([string]::IsNullOrWhiteSpace([string]$actualPlatform)) { 'VM_DISK_SIZE_GB' } else { Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_DISK_SIZE_GB' }

    Assert-ClagnosResizePlatformExpectation `
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
        $diskContext = Get-ClagnosResizeOsDiskContext -VmObject $vmObject -ResourceGroup $resourceGroup -VmName $vmName
        $targetDiskSizeGb = [int]$operationRequest.TargetDiskSizeGb

        if ([string]::Equals([string]$operationRequest.Intent, 'shrink', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ("Shrink request summary for VM '{0}' in '{1}': disk '{2}' current={3} GB, requested={4} ({5} => {6} GB)." -f $vmName, $resourceGroup, $diskContext.DiskName, $diskContext.DiskSizeGb, $operationRequest.RawText, $operationRequest.Unit, $targetDiskSizeGb) -ForegroundColor Yellow
            Show-ClagnosResizeShrinkAlternatives

            if ($targetDiskSizeGb -ge $diskContext.DiskSizeGb) {
                Throw-FriendlyError `
                    -Detail ("Shrink request '{0}' normalizes to {1} GB, which is not smaller than the current OS disk size {2} GB." -f $operationRequest.RawText, $targetDiskSizeGb, $diskContext.DiskSizeGb) `
                    -Code 62 `
                    -Summary "Resize shrink request is not a smaller target." `
                    -Hint "Use --expand for larger targets, or provide a smaller --disk-size value."
            }

            Throw-FriendlyError `
                -Detail ("Azure does not support shrinking the existing managed OS disk '{0}' for VM '{1}'. Current size: {2} GB. Requested size: {3} GB." -f $diskContext.DiskName, $vmName, $diskContext.DiskSizeGb, $targetDiskSizeGb) `
                -Code 62 `
                -Summary "Azure managed OS disk shrink is not supported." `
                -Hint "Use one of the supported rebuild or migration alternatives printed above."
        }

        if ($targetDiskSizeGb -lt $diskContext.DiskSizeGb) {
            Throw-FriendlyError `
                -Detail ("Expand request '{0}' normalizes to {1} GB, which is smaller than the current OS disk size {2} GB." -f $operationRequest.RawText, $targetDiskSizeGb, $diskContext.DiskSizeGb) `
                -Code 62 `
                -Summary "Resize expand request is smaller than the current OS disk size." `
                -Hint "Use --shrink for unsupported shrink guidance, or provide a larger --disk-size value."
        }

        if ($targetDiskSizeGb -eq $diskContext.DiskSizeGb) {
            Write-Host ("No effective OS disk expansion is required. Managed OS disk '{0}' is already {1} GB." -f $diskContext.DiskName, $diskContext.DiskSizeGb) -ForegroundColor Yellow
            return
        }

        if (-not $isDirectRequest) {
            $approveDiskExpand = Confirm-YesNo -PromptText "Continue with managed OS disk expansion?" -DefaultYes $false
            if (-not $approveDiskExpand) {
                Write-Host "Resize command canceled by user." -ForegroundColor Yellow
                return
            }
        }

        Write-Host ("Managed OS disk expansion plan for '{0}' in '{1}': disk '{2}' {3} GB -> {4} GB (requested '{5}')." -f $vmName, $resourceGroup, $diskContext.DiskName, $diskContext.DiskSizeGb, $targetDiskSizeGb, $operationRequest.RawText)
        Write-Host "Managed OS disk expansion requires the VM to be deallocated before Azure updates the disk size."

        Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
            az vm deallocate -g $resourceGroup -n $vmName -o none --only-show-errors
            Assert-LastExitCode "az vm deallocate"
        } | Out-Null
        $deallocated = Wait-ClagnosVmPowerState -ResourceGroup $resourceGroup -VmName $vmName -DesiredPowerState "VM deallocated" -MaxAttempts 18 -DelaySeconds 10
        if (-not $deallocated) {
            Throw-FriendlyError `
                -Detail ("VM '{0}' did not reach deallocated state in expected time." -f $vmName) `
                -Code 62 `
                -Summary "Resize command stopped because VM deallocation was not confirmed." `
                -Hint "Check VM power state in Azure and retry the disk expansion."
        }

        Write-Host ("Applying managed OS disk size update: '{0}' -> {1} GB." -f $diskContext.DiskName, $targetDiskSizeGb)
        Invoke-TrackedAction -Label ("az disk update -g {0} -n {1} --size-gb {2}" -f $resourceGroup, $diskContext.DiskName, $targetDiskSizeGb) -Action {
            az disk update -g $resourceGroup -n $diskContext.DiskName --size-gb $targetDiskSizeGb -o none --only-show-errors
            Assert-LastExitCode "az disk update"
        } | Out-Null

        Write-Host ("Managed OS disk '{0}' is now {1} GB in Azure. Starting VM '{2}'..." -f $diskContext.DiskName, $targetDiskSizeGb, $vmName)
        Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
            az vm start -g $resourceGroup -n $vmName -o none --only-show-errors
            Assert-LastExitCode "az vm start"
        } | Out-Null

        $running = Wait-ClagnosVmPowerState -ResourceGroup $resourceGroup -VmName $vmName -DesiredPowerState "VM running" -MaxAttempts 18 -DelaySeconds 10
        if (-not $running) {
            Throw-FriendlyError `
                -Detail "VM did not return to running state after the managed OS disk expansion." `
                -Code 62 `
                -Summary "Resize command completed with unhealthy VM power state." `
                -Hint "Check VM power state in Azure Portal and start VM manually if needed."
        }

        Set-DotEnvValue -Path $envFilePath -Key $vmDiskSizeConfigKey -Value ([string]$targetDiskSizeGb)
        $script:ConfigOverrides[$vmDiskSizeConfigKey] = [string]$targetDiskSizeGb

        Write-Host ("Managed OS disk expansion completed successfully. Disk '{0}' is now {1} GB." -f $diskContext.DiskName, $targetDiskSizeGb) -ForegroundColor Green
        return
    }

    $targetSize = Resolve-ClagnosResizeTargetSize -Options $Options -CurrentRegion $currentRegion -CurrentSize $currentSize -ConfigMap $configMap
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

    Write-Host ("Applying VM size update for '{0}' in '{1}': {2} -> {3}" -f $vmName, $resourceGroup, $currentSize, $targetSize)

    Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
        az vm deallocate -g $resourceGroup -n $vmName -o none --only-show-errors
        Assert-LastExitCode "az vm deallocate"
    } | Out-Null
    $deallocated = Wait-ClagnosVmPowerState -ResourceGroup $resourceGroup -VmName $vmName -DesiredPowerState "VM deallocated" -MaxAttempts 18 -DelaySeconds 10
    if (-not $deallocated) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' did not reach deallocated state in expected time." -f $vmName) `
            -Code 62 `
            -Summary "Resize command stopped because VM deallocation was not confirmed." `
            -Hint "Check VM power state in Azure and retry resize."
    }

    Invoke-TrackedAction -Label ("az vm resize -g {0} -n {1} --size {2}" -f $resourceGroup, $vmName, $targetSize) -Action {
        az vm resize -g $resourceGroup -n $vmName --size $targetSize -o none --only-show-errors
        Assert-LastExitCode "az vm resize"
    } | Out-Null

    Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
        az vm start -g $resourceGroup -n $vmName -o none --only-show-errors
        Assert-LastExitCode "az vm start"
    } | Out-Null

    $running = Wait-ClagnosVmRunningState -ResourceGroup $resourceGroup -VmName $vmName -MaxAttempts 3 -DelaySeconds 10
    if (-not $running) {
        Throw-FriendlyError `
            -Detail "VM did not return to running state after resize operation." `
            -Code 62 `
            -Summary "Resize command completed with unhealthy VM power state." `
            -Hint "Check VM power state in Azure Portal and start VM manually if needed."
    }

    Set-DotEnvValue -Path $envFilePath -Key $vmSizeConfigKey -Value $targetSize
    $script:ConfigOverrides[$vmSizeConfigKey] = $targetSize

    Write-Host ("Resize completed successfully. VM size is now '{0}'." -f $targetSize) -ForegroundColor Green
}
