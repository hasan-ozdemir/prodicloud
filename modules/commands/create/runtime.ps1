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
            -Detail "Create auto mode could not resolve a platform from CLI flags or the global defaults." `
            -Code 2 `
            -Summary "Create auto mode requires platform selection." `
            -Hint "Set DEFAULT_VM_OS=windows|linux in clagnos.env, or pass --windows/--linux."
    }

    $normalizedPlatform = $platform.Trim().ToLowerInvariant()
    if ($normalizedPlatform -notin @('windows','linux')) {
        Throw-FriendlyError `
            -Detail ("Unsupported platform value '{0}' was resolved for create auto mode." -f [string]$platform) `
            -Code 2 `
            -Summary "Create auto mode requires a supported platform." `
            -Hint "Set DEFAULT_VM_OS=windows|linux in clagnos.env, or pass --windows/--linux."
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
            -Hint "Pass --vm-name, --vm-region and --vm-size or set the matching DEFAULT_* values in clagnos.env. New VC settings are persisted to <vm-name>.env."
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
            -Hint "Set ACTIVE_VM_NAME in clagnos.env or pass --vm-name before using create --step-from vm-init/vm-update."
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
                -Hint "Set SELECTED_RESOURCE_GROUP in the selected <vm-name>.env profile before retrying create --step-from."
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
        [switch]$AutoMode,
        [hashtable]$WizardValues = @{},
        [switch]$WizardMode
    )

    $actionPlan = Resolve-ClagnosActionPlan -CommandName 'create' -Options $Options
    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot 'clagnos.env'
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
            Set-ClagnosConfigValueSource -Key 'SELECTED_VM_NAME' -Source 'clagnos.env value'
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
            Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_REGION' -Source 'clagnos.env value'
        }
    }

    $createVmSize = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-size')
    if (-not [string]::IsNullOrWhiteSpace([string]$createVmSize)) {
        $createOverrides['VM_SIZE'] = $createVmSize.Trim()
        Set-ClagnosConfigValueSource -Key 'VM_SIZE' -Source 'cli value'
    }

    if ($WizardMode) {
        $platform = if ($WindowsFlag) { 'windows' } elseif ($LinuxFlag) { 'linux' } else { [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_VM_OS' -DefaultValue '') }
        if ($platform -notin @('windows','linux')) {
            Throw-FriendlyError -Detail 'The interactive create wizard did not provide a supported operating system.' -Code 2 -Summary 'Create wizard platform is missing.' -Hint 'Select Windows or Linux in the wizard and retry.'
        }
        $createOverrides['SELECTED_VM_OS'] = [string]$platform
        $wizardOverrides = @{
            'WIN_VM_IMAGE' = 'Image'
            'LIN_VM_IMAGE' = 'Image'
            'WIN_VM_DISK_SIZE_GB' = 'DiskSizeGb'
            'LIN_VM_DISK_SIZE_GB' = 'DiskSizeGb'
            'VM_STORAGE_SKU' = 'StorageSku'
            'TCP_PORTS' = 'TcpPorts'
            'VM_SECURITY_TYPE' = 'SecurityType'
            'VM_ENABLE_HIBERNATION' = 'Hibernation'
            'VM_ENABLE_NESTED_VIRTUALIZATION' = 'NestedVirtualization'
            'VM_ENABLE_SECURE_BOOT' = 'SecureBoot'
            'VM_ENABLE_VTPM' = 'Vtpm'
            'VM_SSH_PORT' = 'SshPort'
            'VM_RDP_PORT' = 'RdpPort'
        }
        foreach ($configKey in @($wizardOverrides.Keys)) {
            if ([string]$configKey -like 'WIN_*' -and $platform -ne 'windows') { continue }
            if ([string]$configKey -like 'LIN_*' -and $platform -ne 'linux') { continue }
            if ([string]::Equals([string]$configKey, 'VM_RDP_PORT', [System.StringComparison]::OrdinalIgnoreCase) -and $platform -ne 'windows') { continue }
            $answerKey = [string]$wizardOverrides[[string]$configKey]
            if ($WizardValues.ContainsKey($answerKey)) {
                $createOverrides[[string]$configKey] = [string]$WizardValues[$answerKey]
                Set-ClagnosConfigValueSource -Key ([string]$configKey) -Source 'interactive wizard value'
            }
        }
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
        WizardMode = [bool]$WizardMode
        Step1OperationName = [string]$step1OperationName
    }
}
