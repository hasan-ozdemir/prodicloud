# Create command runtime helpers.

function Assert-ClagnosCreateAutoOptions {
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
    $platform = if ($WindowsFlag) {
        'windows'
    }
    elseif ($LinuxFlag) {
        'linux'
    }
    else {
        [string](Get-ConfigValue -Config $validationConfig -Key 'SELECTED_VM_OS' -DefaultValue '')
    }

    if ([string]::IsNullOrWhiteSpace([string]$platform)) {
        Throw-FriendlyError `
            -Detail "Create auto mode could not resolve a platform from CLI flags or .env." `
            -Code 2 `
            -Summary "Create auto mode requires platform selection." `
            -Hint "Set SELECTED_VM_OS=windows|linux in .env, or pass --windows/--linux."
    }

    $normalizedPlatform = $platform.Trim().ToLowerInvariant()
    if ($normalizedPlatform -notin @('windows','linux')) {
        Throw-FriendlyError `
            -Detail ("Unsupported platform value '{0}' was resolved for create auto mode." -f [string]$platform) `
            -Code 2 `
            -Summary "Create auto mode requires a supported platform." `
            -Hint "Set SELECTED_VM_OS=windows|linux in .env, or pass --windows/--linux."
    }

    $effectiveVmName = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    if ([string]::IsNullOrWhiteSpace([string]$effectiveVmName)) {
        $effectiveVmName = [string](Get-ConfigValue -Config $validationConfig -Key 'SELECTED_VM_NAME' -DefaultValue '')
    }

    $effectiveRegion = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-region')
    if ([string]::IsNullOrWhiteSpace([string]$effectiveRegion)) {
        $effectiveRegion = [string](Get-ConfigValue -Config $validationConfig -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
    }

    $vmSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $normalizedPlatform -BaseKey 'VM_SIZE'
    $effectiveVmSize = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-size')
    if ([string]::IsNullOrWhiteSpace([string]$effectiveVmSize)) {
        $effectiveVmSize = [string](Get-ConfigValue -Config $validationConfig -Key $vmSizeKey -DefaultValue '')
    }

    $missing = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace([string]$effectiveVmName)) { [void]$missing.Add('SELECTED_VM_NAME or --vm-name') }
    if ([string]::IsNullOrWhiteSpace([string]$effectiveRegion)) { [void]$missing.Add('SELECTED_AZURE_REGION or --vm-region') }
    if ([string]::IsNullOrWhiteSpace([string]$effectiveVmSize)) { [void]$missing.Add(("'{0}' or --vm-size" -f $vmSizeKey)) }

    if ($missing.Count -gt 0) {
        Throw-FriendlyError `
            -Detail ("Create auto mode is missing resolvable values: {0}." -f (@($missing) -join ', ')) `
            -Code 2 `
            -Summary "Create auto mode is missing required selection values." `
            -Hint "Populate the SELECTED_* values in .env together with the platform VM size defaults, or pass the missing CLI options explicitly."
    }
}

function Test-ClagnosCreateResumeExistingTargetActionPlan {
    param(
        [psobject]$ActionPlan
    )

    if ($null -eq $ActionPlan) {
        return $false
    }

    $actions = @($ActionPlan.Actions | ForEach-Object { [string]$_ })
    if (@($actions).Count -eq 0) {
        return $false
    }

    $runsExistingOnlyWindow = ($actions -notcontains 'group') -and ($actions -notcontains 'network') -and ($actions -notcontains 'vm-deploy')
    $touchesExistingGuest = (@($actions | Where-Object { $_ -in @('vm-init','vm-update','vm-summary') }).Count -gt 0)
    return ($runsExistingOnlyWindow -and $touchesExistingGuest)
}

function New-ClagnosCreateResumeTargetOverrides {
    param(
        [hashtable]$Options,
        [hashtable]$ConfigMap,
        [string]$VmName
    )

    $resolvedVmName = [string]$VmName
    if ([string]::IsNullOrWhiteSpace([string]$resolvedVmName)) {
        $resolvedVmName = [string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
    }

    if ([string]::IsNullOrWhiteSpace([string]$resolvedVmName)) {
        Throw-FriendlyError `
            -Detail "Create resume requires an existing managed VM target, but no VM name was resolved." `
            -Code 66 `
            -Summary "Create resume cannot resolve the existing VM target." `
            -Hint "Set SELECTED_VM_NAME in .env or pass --vm-name before using create --step-from vm-init/vm-update."
    }

    $defaultResourceGroup = [string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    $targetResourceGroup = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$defaultResourceGroup) -and (Test-ClagnosResourceGroupManaged -ResourceGroup $defaultResourceGroup)) {
        $activeVmNames = @(Get-ClagnosVmNamesForResourceGroup -ResourceGroup $defaultResourceGroup)
        foreach ($candidateVmName in @($activeVmNames)) {
            if ([string]::Equals([string]$candidateVmName, [string]$resolvedVmName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $targetResourceGroup = [string]$defaultResourceGroup
                break
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$targetResourceGroup)) {
        $matches = @(Get-ClagnosManagedVmMatchRows -VmName $resolvedVmName)
        if (@($matches).Count -eq 0) {
            Throw-FriendlyError `
                -Detail ("Create resume could not find an existing managed VM named '{0}'." -f [string]$resolvedVmName) `
                -Code 66 `
                -Summary "Create resume cannot continue because the partial managed target was not found." `
                -Hint "Rerun a full create first, or provide a VM name that already exists in a managed resource group."
        }
        if (@($matches).Count -gt 1) {
            $matchGroups = @($matches | ForEach-Object { [string]$_.ResourceGroup } | Sort-Object -Unique)
            Throw-FriendlyError `
                -Detail ("Create resume found VM name '{0}' in multiple managed resource groups: {1}." -f [string]$resolvedVmName, ($matchGroups -join ', ')) `
                -Code 66 `
                -Summary "Create resume needs one exact managed target." `
                -Hint "Set SELECTED_RESOURCE_GROUP in .env to the intended managed resource group before retrying create --step-from."
        }

        $targetResourceGroup = [string]$matches[0].ResourceGroup
        $resolvedVmName = [string]$matches[0].VmName
    }

    if (-not (Test-ClagnosAzResourceExists -AzArgs @('vm', 'show', '-g', $targetResourceGroup, '-n', $resolvedVmName))) {
        Throw-FriendlyError `
            -Detail ("Create resume target VM '{0}' was not found in managed resource group '{1}'." -f [string]$resolvedVmName, [string]$targetResourceGroup) `
            -Code 66 `
            -Summary "Create resume cannot continue because the partial VM target does not exist." `
            -Hint "Rerun a full create first, or choose an existing managed VM target."
    }

    $targetLocation = Get-ClagnosResourceGroupLocation -ResourceGroup $targetResourceGroup
    $targetOsType = Get-ClagnosManagedTargetOsType -ResourceGroup $targetResourceGroup -VmName $resolvedVmName
    $networkDescriptor = Get-ClagnosVmNetworkDescriptor -ResourceGroup $targetResourceGroup -VmName $resolvedVmName

    $resumeOverrides = @{
        SELECTED_AZURE_SUBSCRIPTION_ID = [string]$((Get-ClagnosResolvedSubscriptionContext).SubscriptionId)
        SELECTED_RESOURCE_GROUP = [string]$targetResourceGroup
        SELECTED_VM_NAME = [string]$resolvedVmName
        SELECTED_AZURE_REGION = [string]$targetLocation
        VNET_NAME = [string]$networkDescriptor.VnetName
        SUBNET_NAME = [string]$networkDescriptor.SubnetName
        NSG_NAME = [string]$networkDescriptor.NsgName
        PUBLIC_IP_NAME = [string]$networkDescriptor.PublicIpName
        NIC_NAME = [string]$networkDescriptor.NicName
        VM_DISK_NAME = [string]$networkDescriptor.OsDiskName
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$targetOsType)) {
        $resumeOverrides['SELECTED_VM_OS'] = [string]$targetOsType
    }

    foreach ($overrideKey in @($resumeOverrides.Keys)) {
        Set-ClagnosConfigValueSource -Key ([string]$overrideKey) -Source 'azure value'
    }

    return $resumeOverrides
}

function New-ClagnosCreateCommandRuntime {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $actionPlan = Resolve-ClagnosActionPlan -CommandName 'create' -Options $Options
    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    Assert-ClagnosCreateAutoOptions -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigMap $configMap
    $createOverrides = @{}
    $cliSubscriptionId = [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id')

    if (-not $AutoMode -and [string]::IsNullOrWhiteSpace([string]$cliSubscriptionId)) {
        $currentSubscription = Get-ClagnosResolvedSubscriptionContext
        $selectedSubscription = Select-ClagnosSubscriptionInteractive -DefaultSubscriptionId ([string]$currentSubscription.SubscriptionId)
        Set-ClagnosResolvedSubscriptionContext `
            -SubscriptionId ([string]$selectedSubscription.id) `
            -SubscriptionName ([string]$selectedSubscription.name) `
            -TenantId ([string]$selectedSubscription.tenantId) `
            -ResolutionSource 'interactive'
        $createOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = [string]$selectedSubscription.id
        Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Source 'interactive value'
    }

    $createVmName = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    if (-not [string]::IsNullOrWhiteSpace([string]$createVmName)) {
        $createOverrides['SELECTED_VM_NAME'] = $createVmName.Trim()
        Set-ClagnosConfigValueSource -Key 'SELECTED_VM_NAME' -Source 'cli value'
    }
    else {
        $configuredVmName = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace([string]$configuredVmName)) {
            $createOverrides['SELECTED_VM_NAME'] = $configuredVmName.Trim()
            Set-ClagnosConfigValueSource -Key 'SELECTED_VM_NAME' -Source '.env value'
        }
    }

    $createVmRegion = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-region')
    if (-not [string]::IsNullOrWhiteSpace([string]$createVmRegion)) {
        $createOverrides['SELECTED_AZURE_REGION'] = $createVmRegion.Trim().ToLowerInvariant()
        Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_REGION' -Source 'cli value'
    }
    else {
        $configuredVmRegion = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace([string]$configuredVmRegion)) {
            $createOverrides['SELECTED_AZURE_REGION'] = $configuredVmRegion.Trim().ToLowerInvariant()
            Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_REGION' -Source '.env value'
        }
    }

    $createVmSize = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-size')
    if (-not [string]::IsNullOrWhiteSpace([string]$createVmSize)) {
        $createOverrides['VM_SIZE'] = $createVmSize.Trim()
        Set-ClagnosConfigValueSource -Key 'VM_SIZE' -Source 'cli value'
    }

    $step1OperationName = 'create'
    if (Test-ClagnosCreateResumeExistingTargetActionPlan -ActionPlan $actionPlan) {
        $resumeOverrides = New-ClagnosCreateResumeTargetOverrides -Options $Options -ConfigMap $configMap -VmName ([string]$createOverrides['SELECTED_VM_NAME'])
        foreach ($overrideKey in @($resumeOverrides.Keys)) {
            $createOverrides[[string]$overrideKey] = [string]$resumeOverrides[[string]$overrideKey]
        }
        $step1OperationName = 'update'
    }

    return [pscustomobject]@{
        ActionPlan = $actionPlan
        InitialConfigOverrides = $createOverrides
        WindowsFlag = [bool]$WindowsFlag
        LinuxFlag = [bool]$LinuxFlag
        AutoMode = [bool]$AutoMode
        Step1OperationName = [string]$step1OperationName
    }
}
