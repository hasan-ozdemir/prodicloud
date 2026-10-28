# Show command runtime helpers.

function Get-ProdicloudShowCommandRuntime {
    param(
        [hashtable]$Options
    )

    return [pscustomobject]@{
        Options = $Options
    }
}

function Resolve-ProdicloudShowFocusedTarget {
    param(
        [hashtable]$Options,
        [hashtable]$ConfigMap,
        [object[]]$SelectedGroupDumps
    )

    $groupOption = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'group')
    $vmNameOption = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-name')
    $requestedGroup = if ([string]::IsNullOrWhiteSpace([string]$groupOption)) { '' } else { $groupOption.Trim() }
    $requestedVmName = if ([string]::IsNullOrWhiteSpace([string]$vmNameOption)) { '' } else { $vmNameOption.Trim() }

    if (-not [string]::IsNullOrWhiteSpace([string]$requestedGroup) -or -not [string]::IsNullOrWhiteSpace([string]$requestedVmName)) {
        return (Resolve-ProdicloudManagedVmTarget -Options $Options -ConfigMap $ConfigMap -OperationName 'show' -AutoSelectSingleVm)
    }

    $vmRows = @()
    foreach ($groupDump in @(ConvertTo-ObjectArrayCompat -InputObject $SelectedGroupDumps)) {
        foreach ($vmDump in @(ConvertTo-ObjectArrayCompat -InputObject $groupDump.Vms)) {
            $vmRows += [pscustomobject]@{
                ResourceGroup = [string]$groupDump.Name
                VmName = [string]$vmDump.Name
            }
        }
    }

    if (@($vmRows).Count -eq 1) {
        return [pscustomobject]@{
            ResourceGroup = [string]$vmRows[0].ResourceGroup
            VmName = [string]$vmRows[0].VmName
        }
    }

    return $null
}

function Get-ProdicloudShowTargetDerivedConfiguration {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [hashtable]$ConfigMap
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::IsNullOrWhiteSpace([string]$VmName)) {
        return $null
    }

    $targetState = Get-ProdicloudConfigureTargetState -ResourceGroup $ResourceGroup -VmName $VmName -ConfigBefore $ConfigMap
    return [ordered]@{
        ResourceGroup = [string]$ResourceGroup
        VmName = [string]$VmName
        Summary = $targetState.SummaryMap
        SkippedFeatureKeys = @($targetState.SkippedFeatureKeys)
    }
}
