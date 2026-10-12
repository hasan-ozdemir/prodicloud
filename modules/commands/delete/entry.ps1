# Delete command entry.

# Handles Invoke-ClagnosDeleteCommand.
function Invoke-ClagnosDeleteCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $vmName = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $defaultResourceGroup = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    $defaultVmName = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $defaultVmDiskName = [string](Get-ConfigValue -Config $configMap -Key 'VM_DISK_NAME' -DefaultValue '')

    $targetRaw = [string](Get-ClagnosCliOptionText -Options $Options -Name 'target')
    $target = $targetRaw.Trim().ToLowerInvariant()
    if ($target -notin @('group','network','vm','disk')) {
        Throw-FriendlyError `
            -Detail ("Invalid delete target '{0}'." -f $targetRaw) `
            -Code 66 `
            -Summary "Delete target is invalid." `
            -Hint "Use --target=group|network|vm|disk."
    }

    $groupOption = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    $resourceGroup = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$groupOption)) {
        $resourceGroup = $groupOption.Trim()
    }
    elseif ($AutoMode) {
        if ([string]::IsNullOrWhiteSpace([string]$defaultResourceGroup)) {
            Throw-FriendlyError `
                -Detail "Resource group is required in auto mode when --group is not provided." `
                -Code 66 `
                -Summary "Delete command cannot resolve target resource group." `
                -Hint "Provide --group=<name> or set SELECTED_RESOURCE_GROUP in .env."
        }
        $resourceGroup = $defaultResourceGroup.Trim()
    }
    else {
        $resourceGroup = Select-ClagnosResourceGroupInteractive -DefaultResourceGroup $defaultResourceGroup -VmName $vmName
    }

    $groupExists = az group exists -n $resourceGroup --only-show-errors
    Assert-LastExitCode "az group exists (delete)"
    if (-not [string]::Equals([string]$groupExists, "true", [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' was not found." -f $resourceGroup) `
            -Code 66 `
            -Summary "Delete command cannot continue because resource group was not found." `
            -Hint "Select an existing resource group."
    }
    Assert-ClagnosManagedResourceGroup -ResourceGroup $resourceGroup -OperationName 'delete'

    $forceYes = Get-ClagnosCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
    $componentDeleteOptions = @{} + $Options
    if ($AutoMode -or $forceYes) { $componentDeleteOptions['yes'] = $true }

    if ($target -eq 'group') {
        $groupRow = Select-ClagnosComponentRow -Rows @(Get-ClagnosComponentRowsForGroup -Type 'group' -ResourceGroup $resourceGroup) -Name $resourceGroup -Type 'resource group'
        Invoke-ClagnosComponentDelete -Type 'group' -SelectedRow $groupRow -ResourceGroup $resourceGroup -Options $componentDeleteOptions
        return
    }

    $vmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $resourceGroup)
    if ($vmNames.Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("No VM found in resource group '{0}' for target '{1}'." -f $resourceGroup, $target) `
            -Code 66 `
            -Summary "Delete target requires a VM context but none was found." `
            -Hint "Create a VM first or choose another resource group."
    }

    $selectedVmName = ''
    if ($AutoMode) {
        if (-not [string]::IsNullOrWhiteSpace([string]$defaultVmName)) {
            $candidate = $defaultVmName.Trim()
            if (@($vmNames | Where-Object { [string]::Equals([string]$_, $candidate, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                $selectedVmName = $candidate
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$selectedVmName)) {
            if ($vmNames.Count -eq 1) {
                $selectedVmName = [string]$vmNames[0]
            }
            else {
                Throw-FriendlyError `
                    -Detail ("Auto mode could not resolve a unique VM in resource group '{0}'." -f $resourceGroup) `
                    -Code 66 `
                    -Summary "Delete command needs an explicit VM in auto mode." `
                    -Hint "Set SELECTED_VM_NAME in .env to the exact Azure VM name in the selected group."
            }
        }
    }
    else {
        $selectedVmName = Select-ClagnosVmInteractive -ResourceGroup $resourceGroup -DefaultVmName $defaultVmName
    }

    $descriptor = Get-ClagnosVmNetworkDescriptor -ResourceGroup $resourceGroup -VmName $selectedVmName
    $vmExists = Test-ClagnosAzResourceExists -AzArgs @("vm", "show", "-g", $resourceGroup, "-n", $selectedVmName)

    $componentType = switch ($target) {
        'vm' { 'vm' }
        'disk' { 'disk' }
        default { 'vnet' }
    }
    $componentRows = @(Get-ClagnosComponentRowsForGroup -Type $componentType -ResourceGroup $resourceGroup)
    $componentName = switch ($target) {
        'vm' { $selectedVmName }
        'disk' { [string]$descriptor.OsDiskName }
        default { [string]$descriptor.VnetName }
    }
    $componentRow = Select-ClagnosComponentRow -Rows $componentRows -Name $componentName -Type $componentType
    Invoke-ClagnosComponentDelete -Type $componentType -SelectedRow $componentRow -ResourceGroup $resourceGroup -Options $componentDeleteOptions
    return

    $confirmPrompt = switch ($target) {
        'vm' { "Delete VM '$selectedVmName' from resource group '$resourceGroup'?" }
        'disk' { "Delete OS disk for VM '$selectedVmName' in resource group '$resourceGroup'?" }
        default { "Delete VM-bound network resources for '$selectedVmName' in resource group '$resourceGroup'?" }
    }
    $approved = ($forceYes -or $AutoMode)
    if (-not $approved) {
        $approved = Confirm-YesNo -PromptText $confirmPrompt -DefaultYes $false
    }
    if (-not $approved) {
        Write-Host "Delete command canceled by user." -ForegroundColor Yellow
        return
    }

    if ($target -eq 'vm') {
        if (-not $vmExists) {
            Write-Host ("VM '{0}' is already absent in resource group '{1}'." -f $selectedVmName, $resourceGroup) -ForegroundColor Yellow
            return
        }
        Invoke-TrackedAction -Label ("az vm delete -g {0} -n {1} --yes" -f $resourceGroup, $selectedVmName) -Action {
            az vm delete -g $resourceGroup -n $selectedVmName --yes -o none --only-show-errors
            Assert-LastExitCode "az vm delete"
        } | Out-Null
        Write-Host ("Delete completed: VM '{0}' was purged." -f $selectedVmName) -ForegroundColor Green
        return
    }

    if ($vmExists) {
        Invoke-TrackedAction -Label ("az vm delete -g {0} -n {1} --yes" -f $resourceGroup, $selectedVmName) -Action {
            az vm delete -g $resourceGroup -n $selectedVmName --yes -o none --only-show-errors
            Assert-LastExitCode "az vm delete"
        } | Out-Null
    }

    if ($target -eq 'disk') {
        $diskName = [string]$descriptor.OsDiskName
        if ([string]::IsNullOrWhiteSpace([string]$diskName)) {
            $diskName = $defaultVmDiskName
        }
        if ([string]::IsNullOrWhiteSpace([string]$diskName)) {
            Throw-FriendlyError `
                -Detail "OS disk name could not be resolved." `
                -Code 66 `
                -Summary "Delete disk target failed before execution." `
                -Hint "Set VM_DISK_NAME in .env or ensure VM metadata is available."
        }

        $diskExists = Test-ClagnosAzResourceExists -AzArgs @("disk", "show", "-g", $resourceGroup, "-n", $diskName)
        if ($diskExists) {
            Invoke-TrackedAction -Label ("az disk delete -g {0} -n {1} --yes" -f $resourceGroup, $diskName) -Action {
                az disk delete -g $resourceGroup -n $diskName --yes -o none --only-show-errors
                Assert-LastExitCode "az disk delete"
            } | Out-Null
            Write-Host ("Delete completed: disk '{0}' was purged." -f $diskName) -ForegroundColor Green
        }
        else {
            Write-Host ("Disk '{0}' is already absent in resource group '{1}'." -f $diskName, $resourceGroup) -ForegroundColor Yellow
        }
        return
    }

    $nicName = [string]$descriptor.NicName
    if (-not [string]::IsNullOrWhiteSpace([string]$nicName)) {
        $nicExists = Test-ClagnosAzResourceExists -AzArgs @("network", "nic", "show", "-g", $resourceGroup, "-n", $nicName)
        if ($nicExists) {
            Invoke-TrackedAction -Label ("az network nic delete -g {0} -n {1}" -f $resourceGroup, $nicName) -Action {
                az network nic delete -g $resourceGroup -n $nicName --only-show-errors
                Assert-LastExitCode "az network nic delete"
            } | Out-Null
        }
    }

    $publicIpName = [string]$descriptor.PublicIpName
    if (-not [string]::IsNullOrWhiteSpace([string]$publicIpName)) {
        $ipExists = Test-ClagnosAzResourceExists -AzArgs @("network", "public-ip", "show", "-g", $resourceGroup, "-n", $publicIpName)
        if ($ipExists) {
            Invoke-TrackedAction -Label ("az network public-ip delete -g {0} -n {1}" -f $resourceGroup, $publicIpName) -Action {
                az network public-ip delete -g $resourceGroup -n $publicIpName --only-show-errors
                Assert-LastExitCode "az network public-ip delete"
            } | Out-Null
        }
    }

    $nsgName = [string]$descriptor.NsgName
    if (-not [string]::IsNullOrWhiteSpace([string]$nsgName)) {
        $nsgExists = Test-ClagnosAzResourceExists -AzArgs @("network", "nsg", "show", "-g", $resourceGroup, "-n", $nsgName)
        if ($nsgExists) {
            Invoke-TrackedAction -Label ("az network nsg delete -g {0} -n {1}" -f $resourceGroup, $nsgName) -Action {
                az network nsg delete -g $resourceGroup -n $nsgName --only-show-errors
                Assert-LastExitCode "az network nsg delete"
            } | Out-Null
        }
    }

    $vnetName = [string]$descriptor.VnetName
    if (-not [string]::IsNullOrWhiteSpace([string]$vnetName)) {
        $vnetExists = Test-ClagnosAzResourceExists -AzArgs @("network", "vnet", "show", "-g", $resourceGroup, "-n", $vnetName)
        if ($vnetExists) {
            Invoke-TrackedAction -Label ("az network vnet delete -g {0} -n {1}" -f $resourceGroup, $vnetName) -Action {
                az network vnet delete -g $resourceGroup -n $vnetName --only-show-errors
                Assert-LastExitCode "az network vnet delete"
            } | Out-Null
        }
    }

    Write-Host ("Delete completed: VM-bound network resources for '{0}' were purged." -f $selectedVmName) -ForegroundColor Green
}
