# UI VM lifecycle display helpers.

# Handles Resolve-ClagnosVmLifecycleFieldText.
function Resolve-ClagnosVmLifecycleFieldText {
    param(
        [string]$DisplayText,
        [string]$CodeText,
        [string]$DefaultText = '(none)'
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$DisplayText)) {
        return [string]$DisplayText
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$CodeText)) {
        return [string]$CodeText
    }

    return [string]$DefaultText
}

# Handles Resolve-ClagnosVmLifecycleStateLabel.
function Resolve-ClagnosVmLifecycleStateLabel {
    param(
        [string]$PowerStateDisplay,
        [string]$PowerStateCode,
        [string]$HibernationStateDisplay,
        [string]$HibernationStateCode
    )

    $powerText = ((@([string]$PowerStateDisplay, [string]$PowerStateCode) -join ' ').Trim()).ToLowerInvariant()
    $hibernationText = ((@([string]$HibernationStateDisplay, [string]$HibernationStateCode) -join ' ').Trim()).ToLowerInvariant()

    if ($hibernationText -match 'hibernat') {
        return 'hibernated'
    }
    if ($powerText -match 'running') {
        return 'started'
    }
    if (($powerText -match 'stopped') -and -not ($powerText -match 'deallocated')) {
        return 'stopped'
    }
    if ($powerText -match 'deallocated') {
        return 'deallocated'
    }

    return 'other'
}

# Handles ConvertTo-ClagnosVmLifecycleSnapshot.
function ConvertTo-ClagnosVmLifecycleSnapshot {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [object]$VmObject,
        [object]$InstanceViewObject
    )

    $powerStateCode = ''
    $powerStateDisplay = ''
    $provisioningStateCode = ''
    $provisioningStateDisplay = ''
    $hibernationStateCode = ''
    $hibernationStateDisplay = ''

    $statusEntries = @()
    if ($null -ne $InstanceViewObject -and $InstanceViewObject.PSObject.Properties.Match('instanceView').Count -gt 0 -and $null -ne $InstanceViewObject.instanceView) {
        $statusEntries = @(ConvertTo-ObjectArrayCompat -InputObject $InstanceViewObject.instanceView.statuses)
    }
    if ($statusEntries.Count -eq 0) {
        $statusEntries = @(ConvertTo-ObjectArrayCompat -InputObject $InstanceViewObject.statuses)
    }

    foreach ($status in @($statusEntries)) {
        $statusCode = [string]$status.code
        $statusDisplay = [string]$status.displayStatus
        if ([string]::IsNullOrWhiteSpace([string]$statusCode)) {
            continue
        }

        if ($statusCode.StartsWith('PowerState/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $powerStateCode = $statusCode
            $powerStateDisplay = $statusDisplay
            continue
        }
        if ($statusCode.StartsWith('ProvisioningState/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $provisioningStateCode = $statusCode
            $provisioningStateDisplay = $statusDisplay
            continue
        }
        if ($statusCode.StartsWith('HibernationState/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $hibernationStateCode = $statusCode
            $hibernationStateDisplay = $statusDisplay
            continue
        }
    }

    $hibernationEnabled = $false
    if ($null -ne $VmObject -and $VmObject.PSObject.Properties.Match('hibernationEnabled').Count -gt 0 -and $null -ne $VmObject.hibernationEnabled) {
        $hibernationEnabled = [bool]$VmObject.hibernationEnabled
    }
    elseif ($null -ne $VmObject -and $VmObject.PSObject.Properties.Match('additionalCapabilities').Count -gt 0 -and $null -ne $VmObject.additionalCapabilities) {
        if ($VmObject.additionalCapabilities.PSObject.Properties.Match('hibernationEnabled').Count -gt 0 -and $null -ne $VmObject.additionalCapabilities.hibernationEnabled) {
            $hibernationEnabled = [bool]$VmObject.additionalCapabilities.hibernationEnabled
        }
    }

    $normalizedState = Resolve-ClagnosVmLifecycleStateLabel `
        -PowerStateDisplay $powerStateDisplay `
        -PowerStateCode $powerStateCode `
        -HibernationStateDisplay $hibernationStateDisplay `
        -HibernationStateCode $hibernationStateCode

    return [pscustomobject]@{
        ResourceGroup = [string]$ResourceGroup
        VmName = [string]$VmName
        OsType = [string]$VmObject.osType
        Location = [string]$VmObject.location
        HibernationEnabled = [bool]$hibernationEnabled
        ProvisioningStateCode = [string]$provisioningStateCode
        ProvisioningStateDisplay = [string]$provisioningStateDisplay
        PowerStateCode = [string]$powerStateCode
        PowerStateDisplay = [string]$powerStateDisplay
        HibernationStateCode = [string]$hibernationStateCode
        HibernationStateDisplay = [string]$hibernationStateDisplay
        NormalizedState = [string]$normalizedState
    }
}

# Handles Get-ClagnosVmLifecycleSnapshot.
function Get-ClagnosVmLifecycleSnapshot {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $vmJson = az vm show `
        -g $ResourceGroup `
        -n $VmName `
        --query "{location:location,osType:storageProfile.osDisk.osType,hibernationEnabled:additionalCapabilities.hibernationEnabled}" `
        -o json `
        --only-show-errors
    Assert-LastExitCode "az vm show (do lifecycle)"
    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    if ($null -eq $vmObject) {
        throw "VM lifecycle metadata could not be parsed."
    }

    $instanceViewJson = az vm get-instance-view -g $ResourceGroup -n $VmName -o json --only-show-errors
    Assert-LastExitCode "az vm get-instance-view (do lifecycle)"
    $instanceViewObject = ConvertFrom-JsonCompat -InputObject $instanceViewJson
    if ($null -eq $instanceViewObject) {
        throw "VM instance view could not be parsed."
    }

    return (ConvertTo-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName -VmObject $vmObject -InstanceViewObject $instanceViewObject)
}

# Handles Format-ClagnosVmLifecycleSummaryText.
function Format-ClagnosVmLifecycleSummaryText {
    param(
        [psobject]$Snapshot
    )

    $powerStateText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.PowerStateDisplay) -CodeText ([string]$Snapshot.PowerStateCode)
    $hibernationStateText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.HibernationStateDisplay) -CodeText ([string]$Snapshot.HibernationStateCode)
    $provisioningStateText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.ProvisioningStateDisplay) -CodeText ([string]$Snapshot.ProvisioningStateCode) -DefaultText '(unknown)'
    $hibernationEnabledText = if ([bool]$Snapshot.HibernationEnabled) { 'true' } else { 'false' }

    return ("lifecycle={0}; power={1}; hibernation={2}; provisioning={3}; hibernationEnabled={4}" -f [string]$Snapshot.NormalizedState, $powerStateText, $hibernationStateText, $provisioningStateText, $hibernationEnabledText)
}

# Handles Test-ClagnosVmProvisioningSucceeded.
function Test-ClagnosVmProvisioningSucceeded {
    param(
        [psobject]$Snapshot
    )

    if ($null -eq $Snapshot) {
        return $false
    }

    if ([string]::Equals([string]$Snapshot.ProvisioningStateCode, 'ProvisioningState/succeeded', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return [string]::Equals([string]$Snapshot.ProvisioningStateDisplay, 'Provisioning succeeded', [System.StringComparison]::OrdinalIgnoreCase)
}

# Handles Test-ClagnosVmProvisioningUpdating.
function Test-ClagnosVmProvisioningUpdating {
    param(
        [psobject]$Snapshot
    )

    if ($null -eq $Snapshot) {
        return $false
    }

    if ([string]::Equals([string]$Snapshot.ProvisioningStateCode, 'ProvisioningState/updating', [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return [string]::Equals([string]$Snapshot.ProvisioningStateDisplay, 'Updating', [System.StringComparison]::OrdinalIgnoreCase)
}

# Handles Wait-ClagnosProvisioningReadyOrRepair.
function Wait-ClagnosProvisioningReadyOrRepair {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [int]$MaxAttempts = 18,
        [int]$DelaySeconds = 10,
        [int]$UpdatingAttemptsBeforeRedeploy = 6,
        [int]$MaxRedeployCount = 1
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($MaxAttempts -gt 120) { $MaxAttempts = 120 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }
    if ($UpdatingAttemptsBeforeRedeploy -lt 1) { $UpdatingAttemptsBeforeRedeploy = 1 }
    if ($UpdatingAttemptsBeforeRedeploy -gt $MaxAttempts) { $UpdatingAttemptsBeforeRedeploy = $MaxAttempts }
    if ($MaxRedeployCount -lt 0) { $MaxRedeployCount = 0 }
    if ($MaxRedeployCount -gt 3) { $MaxRedeployCount = 3 }

    $lastSnapshot = $null
    $updatingAttemptCount = 0
    $redeployCount = 0

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $lastSnapshot = Get-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName
        if (Test-ClagnosVmProvisioningSucceeded -Snapshot $lastSnapshot) {
            return [pscustomobject]@{
                Ready = $true
                Snapshot = $lastSnapshot
                RedeployCount = $redeployCount
            }
        }

        if (Test-ClagnosVmProvisioningUpdating -Snapshot $lastSnapshot) {
            $updatingAttemptCount++
        }
        else {
            $updatingAttemptCount = 0
        }

        if (($updatingAttemptCount -ge $UpdatingAttemptsBeforeRedeploy) -and ($redeployCount -lt $MaxRedeployCount)) {
            Write-Host ("VM provisioning is still 'Updating' for '{0}' in group '{1}'. Triggering Azure redeploy repair..." -f $VmName, $ResourceGroup) -ForegroundColor Yellow
            Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds 900 -Action {
                Invoke-TrackedAction -Label ("az vm redeploy -g {0} -n {1}" -f $ResourceGroup, $VmName) -Action {
                    az vm redeploy -g $ResourceGroup -n $VmName -o none --only-show-errors
                    Assert-LastExitCode "az vm redeploy"
                } | Out-Null
            }
            $redeployCount++
            $updatingAttemptCount = 0

            if ($attempt -lt $MaxAttempts) {
                Write-ClagnosActionProgress -Action ("wait {0}s before repairing VM provisioning state" -f $DelaySeconds)
                Start-Sleep -Seconds $DelaySeconds
            }

            continue
        }

        if ($attempt -lt $MaxAttempts) {
            Write-ClagnosActionProgress -Action ("VM provisioning is not ready for '{0}' in group '{1}'. {2}. Wait {3}s; retry {4}/{5}." -f $VmName, $ResourceGroup, (Format-ClagnosVmLifecycleSummaryText -Snapshot $lastSnapshot), $DelaySeconds, $attempt, $MaxAttempts)
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    return [pscustomobject]@{
        Ready = $false
        Snapshot = $lastSnapshot
        RedeployCount = $redeployCount
    }
}
