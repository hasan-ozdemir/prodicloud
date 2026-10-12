# Update command runtime helpers.

function Assert-ClagnosUpdateAutoOptions {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [hashtable]$ConfigMap
    )

    if (-not (Get-ClagnosCliOptionBool -Options $Options -Name 'auto' -DefaultValue $false)) {
        return
    }

    $validationConfig = if ($ConfigMap) { Resolve-ClagnosSupportedDotEnvConfig -ConfigMap $ConfigMap } else { @{} }
    $effectiveGroup = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    if ([string]::IsNullOrWhiteSpace([string]$effectiveGroup)) {
        $effectiveGroup = [string](Get-ConfigValue -Config $validationConfig -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    }

    if ([string]::IsNullOrWhiteSpace([string]$effectiveGroup)) {
        Throw-FriendlyError `
            -Detail "Update auto mode could not resolve a managed resource group from CLI or .env SELECTED_RESOURCE_GROUP." `
            -Code 2 `
            -Summary "Update auto mode cannot resolve target resource group." `
            -Hint "Set SELECTED_RESOURCE_GROUP in .env, or pass --group."
    }
}

function Get-ClagnosManagedTargetOsType {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $osType = az vm show -g $ResourceGroup -n $VmName --query "storageProfile.osDisk.osType" -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ''
    }

    $normalized = ([string]$osType).Trim().ToLowerInvariant()
    if ($normalized -eq 'windows' -or $normalized -eq 'linux') {
        return $normalized
    }

    return ''
}

function New-ClagnosUpdateCommandRuntime {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $actionPlan = Resolve-ClagnosActionPlan -CommandName 'update' -Options $Options
    $envFilePath = Join-Path (Get-ClagnosRepoRoot) '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    Assert-ClagnosUpdateAutoOptions -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigMap $configMap
    $cliSubscriptionId = [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id')

    if (-not $AutoMode -and [string]::IsNullOrWhiteSpace([string]$cliSubscriptionId)) {
        $currentSubscription = Get-ClagnosResolvedSubscriptionContext
        $selectedSubscription = Select-ClagnosSubscriptionInteractive -DefaultSubscriptionId ([string]$currentSubscription.SubscriptionId)
        Set-ClagnosResolvedSubscriptionContext `
            -SubscriptionId ([string]$selectedSubscription.id) `
            -SubscriptionName ([string]$selectedSubscription.name) `
            -TenantId ([string]$selectedSubscription.tenantId) `
            -ResolutionSource 'interactive'
        Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Source 'interactive value'
    }

    $defaultResourceGroup = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    $vmNameOverride = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    $vmName = if (-not [string]::IsNullOrWhiteSpace([string]$vmNameOverride)) { $vmNameOverride.Trim() } else { [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_VM_NAME' -DefaultValue '') }
    $targetResourceGroup = Resolve-ClagnosTargetResourceGroup -Options $Options -AutoMode:$AutoMode -DefaultResourceGroup $defaultResourceGroup -VmName $vmName -OperationName 'update'
    $resolvedVmName = [string](Resolve-ClagnosTargetVmName -ResourceGroup $targetResourceGroup -DefaultVmName $vmName -AutoMode:$AutoMode -OperationName 'update')
    if (-not (Test-ClagnosAzResourceExists -AzArgs @('vm', 'show', '-g', $targetResourceGroup, '-n', $resolvedVmName))) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' was not found in managed resource group '{1}'." -f $resolvedVmName, $targetResourceGroup) `
            -Code 66 `
            -Summary "Update command cannot continue because the target VM does not exist." `
            -Hint "Run create to provision a fresh managed VM, or choose an existing managed VM target."
    }

    $targetLocation = Get-ClagnosResourceGroupLocation -ResourceGroup $targetResourceGroup
    $targetOsType = Get-ClagnosManagedTargetOsType -ResourceGroup $targetResourceGroup -VmName $resolvedVmName
    $networkDescriptor = Get-ClagnosVmNetworkDescriptor -ResourceGroup $targetResourceGroup -VmName $resolvedVmName

    $updateOverrides = @{
        SELECTED_AZURE_SUBSCRIPTION_ID = [string]$((Get-ClagnosResolvedSubscriptionContext).SubscriptionId)
        SELECTED_RESOURCE_GROUP = $targetResourceGroup
        SELECTED_VM_NAME = $resolvedVmName
        SELECTED_AZURE_REGION = $targetLocation
        VNET_NAME = [string]$networkDescriptor.VnetName
        SUBNET_NAME = [string]$networkDescriptor.SubnetName
        NSG_NAME = [string]$networkDescriptor.NsgName
        PUBLIC_IP_NAME = [string]$networkDescriptor.PublicIpName
        NIC_NAME = [string]$networkDescriptor.NicName
        VM_DISK_NAME = [string]$networkDescriptor.OsDiskName
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$targetOsType)) {
        $updateOverrides['SELECTED_VM_OS'] = $targetOsType
    }

    foreach ($overrideKey in @($updateOverrides.Keys)) {
        Set-ClagnosConfigValueSource -Key ([string]$overrideKey) -Source 'azure value'
    }

    return [pscustomobject]@{
        ActionPlan = $actionPlan
        InitialConfigOverrides = $updateOverrides
        WindowsFlag = [bool]$WindowsFlag
        LinuxFlag = [bool]$LinuxFlag
    }
}
