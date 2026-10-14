# UI resource-group and VM target selection helpers.

# Handles Get-ClagnosResourceGroupsForSelection.
function Get-ClagnosResourceGroupsForSelection {
    param(
        [string]$VmName
    )

    $rows = @()
    try {
        $rows = @(Get-ClagnosManagedResourceGroupRows)
    }
    catch {
        Throw-FriendlyError `
            -Detail "az group list failed while loading managed resource groups." `
            -Code 64 `
            -Summary "Resource group list could not be loaded." `
            -Hint "Run az login and verify subscription access."
    }

    $names = @(
        ConvertTo-ObjectArrayCompat -InputObject $rows |
            ForEach-Object { [string]$_.name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
    if ($names.Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("No managed resource groups were found with tag {0}={1}." -f [string]$script:ManagedByTagKey, [string]$script:ManagedByTagValue) `
            -Code 64 `
            -Summary "Resource group list is empty." `
            -Hint "Run create to provision a managed resource group, then retry."
    }

    $filtered = @($names)

    if (-not [string]::IsNullOrWhiteSpace([string]$VmName)) {
        $needle = [string]$VmName.Trim().ToLowerInvariant()
        $vmMatches = @(
            $filtered | Where-Object {
                $candidate = ([string]$_).ToLowerInvariant()
                $candidate.Contains($needle)
            }
        )
        if ($vmMatches.Count -gt 0) {
            $filtered = @($vmMatches)
        }
    }

    return @($filtered | Sort-Object -Unique)
}

# Handles Select-ClagnosResourceGroupInteractive.
function Select-ClagnosResourceGroupInteractive {
    param(
        [string]$DefaultResourceGroup,
        [string]$VmName
    )

    $groups = @(Get-ClagnosResourceGroupsForSelection -VmName $VmName)
    if ($groups.Count -eq 0) {
        Throw-FriendlyError `
            -Detail "No selectable resource group was found." `
            -Code 64 `
            -Summary "Resource group selection cannot continue." `
            -Hint "Create a resource group first, then retry."
    }

    $options = @($groups | ForEach-Object { [pscustomobject]@{ Value = [string]$_; Label = [string]$_; Detail = '' } })
    $selection = Select-ClagnosNumberedOptionPage -Options $options -Prompt 'Available resource groups' -DefaultValue $DefaultResourceGroup -PageSize 12
    if ([string]$selection.Action -eq 'selected') { return [string]$selection.Value }
    Throw-FriendlyError -Detail 'Resource group selection was closed before a resource group was selected.' -Code 64 -Summary 'Resource group selection was canceled.' -Hint 'Select a managed resource group by number and retry.'
}

# Handles Resolve-ClagnosTargetResourceGroup.
function Resolve-ClagnosTargetResourceGroup {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [string]$DefaultResourceGroup,
        [string]$VmName,
        [string]$OperationName = 'operation'
    )

    $groupOption = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    $resourceGroup = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$groupOption)) {
        $resourceGroup = $groupOption.Trim()
    }
    elseif ($AutoMode) {
        $resourceGroup = [string]$DefaultResourceGroup
        if ([string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
            Throw-FriendlyError `
                -Detail ("No active resource group is configured for auto mode in {0} command." -f $OperationName) `
                -Code 66 `
                -Summary ("{0} command cannot resolve target resource group." -f $OperationName) `
                -Hint "Set SELECTED_RESOURCE_GROUP in .env or provide --group=<name>."
        }
    }
    else {
        $resourceGroup = Select-ClagnosResourceGroupInteractive -DefaultResourceGroup $DefaultResourceGroup -VmName $VmName
    }

    $groupExists = az group exists -n $resourceGroup --only-show-errors
    Assert-LastExitCode ("az group exists ({0})" -f $OperationName)
    if (-not [string]::Equals([string]$groupExists, "true", [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' was not found." -f $resourceGroup) `
            -Code 66 `
            -Summary ("{0} command cannot continue because resource group was not found." -f $OperationName) `
            -Hint "Provide a valid --group value or select an existing managed resource group."
    }

    Assert-ClagnosManagedResourceGroup -ResourceGroup $resourceGroup -OperationName $OperationName
    return $resourceGroup
}

# Handles Get-ClagnosResourceGroupLocation.
function Get-ClagnosResourceGroupLocation {
    param(
        [string]$ResourceGroup
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        Throw-FriendlyError `
            -Detail "Resource group name is empty while resolving Azure location." `
            -Code 66 `
            -Summary "Resource group location could not be resolved." `
            -Hint "Provide an existing managed resource group."
    }

    $location = az group show -n ([string]$ResourceGroup) --query "location" -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$location)) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' location could not be read from Azure." -f [string]$ResourceGroup) `
            -Code 66 `
            -Summary "Resource group location could not be resolved." `
            -Hint "Verify Azure access and the selected managed resource group."
    }

    return ([string]$location).Trim().ToLowerInvariant()
}

# Handles Get-ClagnosVmNamesForResourceGroup.
function Get-ClagnosVmNamesForResourceGroup {
    param(
        [string]$ResourceGroup
    )

    $raw = az vm list -g $ResourceGroup --query "[].name" -o json --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        Throw-FriendlyError `
            -Detail ("az vm list failed for resource group '{0}'." -f $ResourceGroup) `
            -Code 65 `
            -Summary "VM list could not be loaded." `
            -Hint "Verify the resource group name and Azure access."
    }

    $vmNames = @(
        ConvertFrom-JsonArrayCompat -InputObject $raw |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
    return @($vmNames)
}

# Handles Select-ClagnosVmInteractive.
function Select-ClagnosVmInteractive {
    param(
        [string]$ResourceGroup,
        [string]$DefaultVmName
    )

    $vmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $ResourceGroup)
    if ($vmNames.Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' does not contain any VM." -f $ResourceGroup) `
            -Code 65 `
            -Summary "VM selection cannot continue because the VM list is empty." `
            -Hint "Create a VM first or choose another resource group."
    }

    $options = @($vmNames | ForEach-Object { [pscustomobject]@{ Value = [string]$_; Label = [string]$_; Detail = '' } })
    $selection = Select-ClagnosNumberedOptionPage -Options $options -Prompt ("Virtual machines in '{0}'" -f $ResourceGroup) -DefaultValue $DefaultVmName -PageSize 12
    if ([string]$selection.Action -eq 'selected') { return [string]$selection.Value }
    Throw-FriendlyError -Detail ("VM selection was closed before a VM was selected in resource group '{0}'." -f $ResourceGroup) -Code 65 -Summary 'VM selection was canceled.' -Hint 'Select a VM by number and retry.'
}

# Handles Resolve-ClagnosVmSelectionForResourceGroup.
function Resolve-ClagnosVmSelectionForResourceGroup {
    param(
        [string]$ResourceGroup,
        [string]$RequestedVmName,
        [string]$DefaultVmName,
        [switch]$AutoSelectSingleVm,
        [switch]$FailIfMultipleWithoutExplicitVm,
        [string]$OperationName = 'operation'
    )

    $vmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $ResourceGroup)
    if ($vmNames.Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' does not contain any VM." -f $ResourceGroup) `
            -Code 65 `
            -Summary ("{0} command cannot continue because the VM list is empty." -f $OperationName) `
            -Hint "Create a VM first or choose another managed resource group."
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$RequestedVmName)) {
        $resolvedVmName = @(
            $vmNames |
                Where-Object {
                    [string]::Equals([string]$_, [string]$RequestedVmName, [System.StringComparison]::OrdinalIgnoreCase)
                } |
                Select-Object -First 1
        )
        if (@($resolvedVmName).Count -eq 0) {
            Throw-FriendlyError `
                -Detail ("VM '{0}' was not found in resource group '{1}'." -f $RequestedVmName, $ResourceGroup) `
                -Code 66 `
                -Summary ("{0} command could not resolve the target VM." -f $OperationName) `
                -Hint "Provide an exact VM name in the selected managed resource group, or omit --vm-name to select interactively."
        }

        return [string]$resolvedVmName[0]
    }

    if ($AutoSelectSingleVm -and $vmNames.Count -eq 1) {
        $resolvedSingleVm = [string]$vmNames[0]
        Write-Host ("Resolved target VM '{0}' automatically because resource group '{1}' contains exactly one VM." -f $resolvedSingleVm, $ResourceGroup) -ForegroundColor Cyan
        return $resolvedSingleVm
    }

    if ($FailIfMultipleWithoutExplicitVm -and $vmNames.Count -gt 1) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' contains multiple VMs: {1}." -f $ResourceGroup, (@($vmNames) -join ', ')) `
            -Code 66 `
            -Summary ("{0} command needs an explicit VM for the selected resource group." -f $OperationName) `
            -Hint "Provide --vm-name=<name>, or rerun configure without --group to select both target values interactively."
    }

    return (Select-ClagnosVmInteractive -ResourceGroup $ResourceGroup -DefaultVmName $DefaultVmName)
}

# Handles Resolve-ClagnosTargetVmName.
function Resolve-ClagnosTargetVmName {
    param(
        [string]$ResourceGroup,
        [string]$DefaultVmName,
        [switch]$AutoMode,
        [string]$OperationName = 'operation'
    )

    $vmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $ResourceGroup)
    if ($vmNames.Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("No VM found in resource group '{0}'." -f $ResourceGroup) `
            -Code 65 `
            -Summary ("{0} command cannot continue because VM list is empty." -f $OperationName) `
            -Hint "Create a VM first or choose another resource group."
    }

    if ($AutoMode) {
        if (-not [string]::IsNullOrWhiteSpace([string]$DefaultVmName)) {
            foreach ($candidate in @($vmNames)) {
                if ([string]::Equals([string]$candidate, [string]$DefaultVmName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [string]$candidate
                }
            }
        }

        if ($vmNames.Count -eq 1) {
            return [string]$vmNames[0]
        }

        Throw-FriendlyError `
            -Detail ("Auto mode could not resolve one VM in resource group '{0}'." -f $ResourceGroup) `
            -Code 65 `
            -Summary ("{0} command cannot resolve target VM in auto mode." -f $OperationName) `
            -Hint "Set SELECTED_VM_NAME in .env to the exact Azure VM name, provide a command-specific VM parameter, or use interactive mode."
    }

    return (Select-ClagnosVmInteractive -ResourceGroup $ResourceGroup -DefaultVmName $DefaultVmName)
}

# Handles Get-ClagnosVmNetworkDescriptor.
function Get-ClagnosVmNetworkDescriptor {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $vmJson = az vm show -g $ResourceGroup -n $VmName -o json --only-show-errors
    Assert-LastExitCode "az vm show (network descriptor)"
    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    if (-not $vmObject) {
        throw "VM metadata could not be parsed while collecting network resources."
    }

    $osDiskName = [string]$vmObject.storageProfile.osDisk.name
    $nicName = ""
    $nicEntries = @($vmObject.networkProfile.networkInterfaces)
    if ($nicEntries.Count -gt 0) {
        $primaryNic = @($nicEntries | Where-Object { $_.primary -eq $true } | Select-Object -First 1)
        if ($null -eq $primaryNic -or @($primaryNic).Count -eq 0) {
            $primaryNic = @($nicEntries | Select-Object -First 1)
        }
        if ($primaryNic -is [System.Array]) { $primaryNic = [object]$primaryNic[0] }
        $nicId = [string]$primaryNic.id
        if (-not [string]::IsNullOrWhiteSpace([string]$nicId)) {
            $nicParts = @($nicId -split '/')
            $nicName = [string]$nicParts[$nicParts.Count - 1]
        }
    }

    $publicIpName = ""
    $nsgName = ""
    $vnetName = ""
    $subnetName = ""
    $subnetName = ""
    if (-not [string]::IsNullOrWhiteSpace($nicName)) {
        $nicJson = az network nic show -g $ResourceGroup -n $nicName -o json --only-show-errors
        Assert-LastExitCode "az network nic show (network descriptor)"
        $nicObject = ConvertFrom-JsonCompat -InputObject $nicJson
        if ($nicObject) {
            $publicIpId = [string]$nicObject.ipConfigurations[0].publicIPAddress.id
            if (-not [string]::IsNullOrWhiteSpace([string]$publicIpId)) {
                $publicIpParts = @($publicIpId -split '/')
                $publicIpName = [string]$publicIpParts[$publicIpParts.Count - 1]
            }

            $nsgId = [string]$nicObject.networkSecurityGroup.id
            if (-not [string]::IsNullOrWhiteSpace([string]$nsgId)) {
                $nsgParts = @($nsgId -split '/')
                $nsgName = [string]$nsgParts[$nsgParts.Count - 1]
            }

            $subnetId = [string]$nicObject.ipConfigurations[0].subnet.id
            if (-not [string]::IsNullOrWhiteSpace([string]$subnetId)) {
                $subnetParts = @($subnetId -split '/')
                $subnetName = [string]$subnetParts[$subnetParts.Count - 1]
                for ($i = 0; $i -lt $subnetParts.Count - 1; $i++) {
                    if ([string]::Equals([string]$subnetParts[$i], 'virtualNetworks', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $vnetName = [string]$subnetParts[$i + 1]
                        break
                    }
                }
            }
        }
    }

    return [pscustomobject]@{
        OsDiskName = $osDiskName
        NicName = $nicName
        PublicIpName = $publicIpName
        NsgName = $nsgName
        VnetName = $vnetName
        SubnetName = $subnetName
    }
}

# Handles Get-ClagnosManagedVmMatchRows.
function Get-ClagnosManagedVmMatchRows {
    param(
        [string]$VmName
    )

    $needle = [string]$VmName
    if ([string]::IsNullOrWhiteSpace([string]$needle)) {
        return @()
    }

    $matches = @()
    $groups = @(Get-ClagnosManagedResourceGroupRows)
    foreach ($groupRow in @($groups)) {
        $resourceGroup = [string]$groupRow.name
        if ([string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
            continue
        }

        $vmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $resourceGroup)
        foreach ($candidateVmName in @($vmNames)) {
            if ([string]::Equals([string]$candidateVmName, $needle, [System.StringComparison]::OrdinalIgnoreCase)) {
                $matches += [pscustomobject]@{
                    ResourceGroup = $resourceGroup
                    VmName = [string]$candidateVmName
                }
            }
        }
    }

    return @($matches)
}

# Handles Resolve-ClagnosManagedVmTarget.
function Resolve-ClagnosManagedVmTarget {
    param(
        [hashtable]$Options,
        [hashtable]$ConfigMap,
        [string]$OperationName,
        [switch]$AutoSelectSingleVm,
        [switch]$FailIfMultipleWithoutExplicitVmForExplicitGroup
    )

    $defaultResourceGroup = [string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    $defaultVmName = [string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $groupOption = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    $vmNameOption = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    $requestedResourceGroup = $groupOption.Trim()
    $requestedVmName = $vmNameOption.Trim()

    if (-not [string]::IsNullOrWhiteSpace([string]$requestedResourceGroup)) {
        $resourceGroup = Resolve-ClagnosTargetResourceGroup `
            -Options $Options `
            -AutoMode:$false `
            -DefaultResourceGroup $defaultResourceGroup `
            -VmName $requestedVmName `
            -OperationName $OperationName

        $vmName = Resolve-ClagnosVmSelectionForResourceGroup `
            -ResourceGroup $resourceGroup `
            -RequestedVmName $requestedVmName `
            -DefaultVmName $defaultVmName `
            -AutoSelectSingleVm:$AutoSelectSingleVm `
            -FailIfMultipleWithoutExplicitVm:$FailIfMultipleWithoutExplicitVmForExplicitGroup `
            -OperationName $OperationName

        return [pscustomobject]@{
            ResourceGroup = $resourceGroup
            VmName = $vmName
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$requestedVmName)) {
        $activeGroupMatches = $false
        if (-not [string]::IsNullOrWhiteSpace([string]$defaultResourceGroup) -and (Test-ClagnosResourceGroupManaged -ResourceGroup $defaultResourceGroup)) {
            $activeVmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $defaultResourceGroup)
            foreach ($candidateVmName in @($activeVmNames)) {
                if ([string]::Equals([string]$candidateVmName, $requestedVmName, [System.StringComparison]::OrdinalIgnoreCase)) {
                    return [pscustomobject]@{
                        ResourceGroup = $defaultResourceGroup
                        VmName = [string]$candidateVmName
                    }
                }
            }
            $activeGroupMatches = $true
        }

        $matches = @(Get-ClagnosManagedVmMatchRows -VmName $requestedVmName)
        if (@($matches).Count -eq 1) {
            return [pscustomobject]@{
                ResourceGroup = [string]$matches[0].ResourceGroup
                VmName = [string]$matches[0].VmName
            }
        }

        if (@($matches).Count -gt 1) {
            $matchGroups = @($matches | ForEach-Object { [string]$_.ResourceGroup } | Sort-Object -Unique)
            Throw-FriendlyError `
                -Detail ("VM name '{0}' was found in multiple managed resource groups: {1}." -f $requestedVmName, ($matchGroups -join ', ')) `
                -Code 66 `
                -Summary ("{0} command needs an explicit resource group." -f $OperationName) `
                -Hint "Provide --group=<resource-group> together with --vm-name=<name>."
        }

        $notFoundHint = if ($activeGroupMatches) {
            "Provide --group=<resource-group> or select another exact VM name."
        }
        else {
            "Select a managed resource group interactively or provide both --group and --vm-name."
        }

        Throw-FriendlyError `
            -Detail ("VM '{0}' was not found in clagnos managed resource groups." -f $requestedVmName) `
            -Code 66 `
            -Summary ("{0} command could not find the target VM." -f $OperationName) `
            -Hint $notFoundHint
    }

    $resourceGroup = Select-ClagnosResourceGroupInteractive -DefaultResourceGroup $defaultResourceGroup -VmName $defaultVmName
    $vmName = Resolve-ClagnosVmSelectionForResourceGroup `
        -ResourceGroup $resourceGroup `
        -RequestedVmName '' `
        -DefaultVmName $defaultVmName `
        -AutoSelectSingleVm:$AutoSelectSingleVm `
        -OperationName $OperationName
    return [pscustomobject]@{
        ResourceGroup = $resourceGroup
        VmName = $vmName
    }
}

# Handles Resolve-ClagnosConnectionTarget.
function Resolve-ClagnosConnectionTarget {
    param(
        [hashtable]$Options,
        [hashtable]$ConfigMap,
        [string]$OperationName
    )

    return (Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $ConfigMap -OperationName $OperationName)
}
