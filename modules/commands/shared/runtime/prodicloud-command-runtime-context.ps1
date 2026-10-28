# Shared command runtime-context builders.

# Handles Initialize-ProdicloudCommandRuntimeContext.
function Initialize-ProdicloudCommandRuntimeContext {
    param(
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [hashtable]$ConfigMapOverrides = @{},
        [string]$OperationName = 'generic',
        [switch]$UseInteractiveStep1,
        [switch]$WizardMode,
        [switch]$PersistGeneratedResourceGroup,
        [switch]$DeferDotEnvWrites
    )

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Get-ProdicloudGlobalEnvPath
    $globalConfigMap = Read-DotEnvFile -Path $envFilePath -GlobalOnly
    $profileVmName = ''
    if ($ConfigMapOverrides -and $ConfigMapOverrides.ContainsKey('SELECTED_VM_NAME')) { $profileVmName = [string]$ConfigMapOverrides['SELECTED_VM_NAME'] }
    elseif ($script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME')) { $profileVmName = [string]$script:ConfigOverrides['SELECTED_VM_NAME'] }
    elseif (-not [string]::Equals([string]$OperationName,'create',[System.StringComparison]::OrdinalIgnoreCase)) { $profileVmName = [string]$globalConfigMap['ACTIVE_VM_NAME'] }
    $requireVmProfile = -not [string]::IsNullOrWhiteSpace([string]$profileVmName) -and -not [string]::Equals([string]$OperationName,'create',[System.StringComparison]::OrdinalIgnoreCase)
    $configMap = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfigMap -VmName $profileVmName -RequireProfile:$requireVmProfile
    $platformSelectionOverrides = @{}
    foreach ($key in @($script:ConfigOverrides.Keys)) {
        $platformSelectionOverrides[[string]$key] = [string]$script:ConfigOverrides[$key]
    }
    foreach ($key in @($ConfigMapOverrides.Keys)) {
        $platformSelectionOverrides[[string]$key] = [string]$ConfigMapOverrides[$key]
    }

    $promptForPlatformSelection = (-not $AutoMode) -and [string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)
    $deferPlatformWrite = [bool]$DeferDotEnvWrites -or [string]::Equals([string]$OperationName,'create',[System.StringComparison]::OrdinalIgnoreCase)
    $platform = Resolve-ProdicloudPlatformSelection -ConfigMap $configMap -EnvFilePath $envFilePath -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigOverrides $platformSelectionOverrides -DeferEnvWrite:$deferPlatformWrite -PromptWhenFlagsMissing:$promptForPlatformSelection
    $platformDefaults = Get-ProdicloudPlatformDefaults -Platform $platform
    $effectiveConfigMap = Resolve-ProdicloudPlatformConfigMap -ConfigMap $configMap -Platform $platform
    foreach ($key in @($ConfigMapOverrides.Keys)) {
        $overrideKey = [string]$key
        if ([string]::IsNullOrWhiteSpace($overrideKey)) {
            continue
        }
        $effectiveConfigMap[$overrideKey] = [string]$ConfigMapOverrides[$key]
        $script:ConfigOverrides[$overrideKey] = [string]$ConfigMapOverrides[$key]
    }

    $step1AutoMode = $true
    if ($UseInteractiveStep1) {
        # The frontend wizard supplies the create-critical fields, but the
        # shared create workflow is still interactive (including its review
        # steps and normal persistence behavior). Do not treat it as auto mode.
        $step1AutoMode = [bool]$AutoMode
    }

    $step1Context = Invoke-ProdicloudStep1Common `
        -ConfigMap $effectiveConfigMap `
        -EnvFilePath $envFilePath `
        -Platform $platform `
        -AutoMode:$step1AutoMode `
        -PersistGeneratedResourceGroup:$PersistGeneratedResourceGroup `
        -ScriptRoot $repoRoot `
        -VmNameDefault ([string]$platformDefaults.VmNameDefault) `
        -VmImageDefault ([string]$platformDefaults.VmImageDefault) `
        -VmSizeDefault ([string]$platformDefaults.VmSizeDefault) `
        -VmDiskSizeDefault ([string]$platformDefaults.VmDiskSizeDefault) `
        -ConfigOverrides $script:ConfigOverrides `
        -OperationName $OperationName `
        -WizardInputComplete:$WizardMode `
        -SkipInteractiveConfigEditor:$WizardMode `
        -DeferEnvWrites:$DeferDotEnvWrites

    $step1Context['ConfigMap'] = $effectiveConfigMap
    $step1Context['VmOsType'] = $platform
    $subscriptionContext = Get-ProdicloudResolvedSubscriptionContext
    if ($null -ne $subscriptionContext) {
        $step1Context['AzureSubscriptionId'] = [string]$subscriptionContext.SubscriptionId
        $step1Context['AzureSubscriptionName'] = [string]$subscriptionContext.SubscriptionName
        $step1Context['AzureSubscriptionResolutionSource'] = [string]$subscriptionContext.ResolutionSource
    }

    $taskOutcomeModeRaw = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'VM_TASK_OUTCOME_MODE' -DefaultValue 'continue')
    if ([string]::IsNullOrWhiteSpace($taskOutcomeModeRaw)) { $taskOutcomeModeRaw = 'continue' }
    $taskOutcomeMode = $taskOutcomeModeRaw.Trim().ToLowerInvariant()
    if ($taskOutcomeMode -ne 'continue' -and $taskOutcomeMode -ne 'strict') {
        Throw-FriendlyError `
            -Detail ("Invalid VM_TASK_OUTCOME_MODE '{0}'." -f $taskOutcomeModeRaw) `
            -Code 14 `
            -Summary "Task outcome mode is invalid." `
            -Hint "Set VM_TASK_OUTCOME_MODE=continue or VM_TASK_OUTCOME_MODE=strict."
    }

    $configuredPySshClientPath = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'PYSSH_CLIENT_PATH' -DefaultValue (Get-ProdicloudDefaultPySshClientPathText))
    $sshTaskTimeoutText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SSH_TASK_TIMEOUT_SECONDS' -DefaultValue ([string]$script:SshTaskTimeoutSeconds))
    $sshTaskTimeoutSeconds = $script:SshTaskTimeoutSeconds
    if ($sshTaskTimeoutText -match '^\d+$') { $sshTaskTimeoutSeconds = [int]$sshTaskTimeoutText }
    if ($sshTaskTimeoutSeconds -lt 30) { $sshTaskTimeoutSeconds = 30 }
    if ($sshTaskTimeoutSeconds -gt 7200) { $sshTaskTimeoutSeconds = 7200 }

    $sshConnectTimeoutText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SSH_CONNECT_TIMEOUT_SECONDS' -DefaultValue ([string]$script:SshConnectTimeoutSeconds))
    $sshConnectTimeoutSeconds = $script:SshConnectTimeoutSeconds
    if ($sshConnectTimeoutText -match '^\d+$') { $sshConnectTimeoutSeconds = [int]$sshConnectTimeoutText }
    if ($sshConnectTimeoutSeconds -lt 5) { $sshConnectTimeoutSeconds = 5 }
    if ($sshConnectTimeoutSeconds -gt 300) { $sshConnectTimeoutSeconds = 300 }

    $azCommandTimeoutText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'AZURE_COMMAND_TIMEOUT_SECONDS' -DefaultValue ([string]$script:AzCommandTimeoutSeconds))
    $azCommandTimeoutSeconds = $script:AzCommandTimeoutSeconds
    if ($azCommandTimeoutText -match '^\d+$') { $azCommandTimeoutSeconds = [int]$azCommandTimeoutText }
    if ($azCommandTimeoutSeconds -lt 30) { $azCommandTimeoutSeconds = 30 }
    if ($azCommandTimeoutSeconds -gt 7200) { $azCommandTimeoutSeconds = 7200 }

    $script:AzCommandTimeoutSeconds = $azCommandTimeoutSeconds
    $script:SshTaskTimeoutSeconds = $sshTaskTimeoutSeconds
    $script:SshConnectTimeoutSeconds = $sshConnectTimeoutSeconds
    $step1Context['AzCommandTimeoutSeconds'] = $azCommandTimeoutSeconds
    $step1Context['SshTaskTimeoutSeconds'] = $sshTaskTimeoutSeconds
    $step1Context['SshConnectTimeoutSeconds'] = $sshConnectTimeoutSeconds
    $step1Context['TaskOutcomeMode'] = [string]$taskOutcomeMode
    $step1Context['ConfiguredPySshClientPath'] = [string]$configuredPySshClientPath

    return [pscustomobject]@{
        EnvFilePath = $envFilePath
        ConfigMap = $configMap
        EffectiveConfigMap = $effectiveConfigMap
        Platform = $platform
        PlatformDefaults = $platformDefaults
        Context = $step1Context
        TaskOutcomeMode = $taskOutcomeMode
        ConfiguredPySshClientPath = $configuredPySshClientPath
        SshTaskTimeoutSeconds = $sshTaskTimeoutSeconds
        SshConnectTimeoutSeconds = $sshConnectTimeoutSeconds
    }
}

# Handles Initialize-ProdicloudTaskExecutionRuntimeContext.
function Initialize-ProdicloudTaskExecutionRuntimeContext {
    param(
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [hashtable]$Options = @{}
    )

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Get-ProdicloudGlobalEnvPath
    $globalConfigMap = Read-DotEnvFile -Path $envFilePath -GlobalOnly
    $requestedVmName = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-name')
    if ([string]::IsNullOrWhiteSpace([string]$requestedVmName) -and $script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME')) { $requestedVmName = [string]$script:ConfigOverrides['SELECTED_VM_NAME'] }
    if ([string]::IsNullOrWhiteSpace([string]$requestedVmName)) { $requestedVmName = [string]$globalConfigMap['ACTIVE_VM_NAME'] }
    $configMap = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfigMap -VmName $requestedVmName -RequireProfile:([bool](-not [string]::IsNullOrWhiteSpace([string]$requestedVmName)))
    $platform = Resolve-ProdicloudPlatformSelection -ConfigMap $configMap -EnvFilePath $envFilePath -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigOverrides $script:ConfigOverrides
    $platformDefaults = Get-ProdicloudPlatformDefaults -Platform $platform
    $effectiveConfigMap = Resolve-ProdicloudPlatformConfigMap -ConfigMap $configMap -Platform $platform

    $vmName = [string](Get-ProdicloudRequiredResolvedConfigValue -ConfigMap $effectiveConfigMap -Key 'SELECTED_VM_NAME' -Summary 'VM name is required.' -Hint 'Set ACTIVE_VM_NAME in prodicloud.env or pass --vm-name; the selected VM settings are loaded from <vm-name>.env.')

    $azLocation = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
    $regionCode = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$azLocation)) {
        $regionCode = Get-ProdicloudRegionCode -Location ([string]$azLocation)
    }

    $nameTokens = @{
        SELECTED_VM_NAME = [string]$vmName
        REGION_CODE = [string]$regionCode
        N = '1'
    }

    $resourceGroup = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
        $resourceGroup = Resolve-ProdicloudTemplate -Template $resourceGroup -Tokens $nameTokens
    }

    $vmStorageSku = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'VM_STORAGE_SKU' -DefaultValue 'StandardSSD_LRS')) -Tokens $nameTokens
    $vmSizeConfigKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'
    $vmImageConfigKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
    $vmDiskSizeConfigKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'
    $vmSize = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key $vmSizeConfigKey -DefaultValue ([string]$platformDefaults.VmSizeDefault))) -Tokens $nameTokens
    $vmImage = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key $vmImageConfigKey -DefaultValue ([string]$platformDefaults.VmImageDefault))) -Tokens $nameTokens
    $vmDiskSize = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key $vmDiskSizeConfigKey -DefaultValue ([string]$platformDefaults.VmDiskSizeDefault))) -Tokens $nameTokens
    $vmDiskName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'VM_DISK_NAME' -DefaultValue '')) -Tokens $nameTokens
    $companyName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_COMPANY_NAME' -DefaultValue '')) -Tokens $nameTokens
    $companyWebAddress = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_COMPANY_WEB_ADDRESS' -DefaultValue '')) -Tokens $nameTokens
    $companyEmailAddress = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_COMPANY_EMAIL_ADDRESS' -DefaultValue '')) -Tokens $nameTokens
    $employeeEmailAddress = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' -DefaultValue '')) -Tokens $nameTokens
    $employeeFullName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_EMPLOYEE_FULL_NAME' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessLinkedInUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessYouTubeUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessGitHubUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessTikTokUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessInstagramUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessFacebookUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessXUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessSnapchatUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialBusinessNextSosyalUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalLinkedInUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalYouTubeUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalGitHubUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalTikTokUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalInstagramUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalFacebookUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutSocialPersonalXUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutWebBusinessHomeUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL' -DefaultValue '')) -Tokens $nameTokens
    $shortcutWebBusinessBlogUrl = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL' -DefaultValue '')) -Tokens $nameTokens
    $vmProfilePath = Get-ProdicloudVmEnvPath -VmName $vmName
    $vmUser = Get-ProdicloudRequiredResolvedConfigValue -ConfigMap $effectiveConfigMap -Key 'VM_ADMIN_USER' -Tokens $nameTokens -Summary 'VM admin user is required.' -Hint ("Set VM_ADMIN_USER in '{0}'." -f $vmProfilePath)
    $vmPass = Get-ProdicloudRequiredResolvedConfigValue -ConfigMap $effectiveConfigMap -Key 'VM_ADMIN_PASS' -Tokens $nameTokens -Summary 'VM admin password is required.' -Hint ("Set VM_ADMIN_PASS in '{0}' to a non-placeholder password." -f $vmProfilePath)
    $vmAssistantUser = Get-ProdicloudRequiredResolvedConfigValue -ConfigMap $effectiveConfigMap -Key 'VM_ASSISTANT_USER' -Tokens $nameTokens -Summary 'VM assistant user is required.' -Hint ("Set VM_ASSISTANT_USER in '{0}'." -f $vmProfilePath)
    $vmAssistantPass = Get-ProdicloudRequiredResolvedConfigValue -ConfigMap $effectiveConfigMap -Key 'VM_ASSISTANT_PASS' -Tokens $nameTokens -Summary 'VM assistant password is required.' -Hint ("Set VM_ASSISTANT_PASS in '{0}' to a non-placeholder password." -f $vmProfilePath)
    $sshPort = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'VM_SSH_PORT' -DefaultValue (Get-ProdicloudDefaultSshPortText))) -Tokens $nameTokens
    $rdpPort = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key 'VM_RDP_PORT' -DefaultValue (Get-ProdicloudDefaultRdpPortText))) -Tokens $nameTokens

    $vmInitTaskDirName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key (Get-ProdicloudPlatformTaskCatalogConfigKey -Platform $platform -Stage 'init') -DefaultValue ([string]$platformDefaults.VmInitTaskDirDefault))) -Tokens $nameTokens
    $vmUpdateTaskDirName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key (Get-ProdicloudPlatformTaskCatalogConfigKey -Platform $platform -Stage 'update') -DefaultValue ([string]$platformDefaults.VmUpdateTaskDirDefault))) -Tokens $nameTokens
    $vmInitTaskDir = Resolve-ConfigPath -PathValue $vmInitTaskDirName -RootPath $repoRoot
    $vmUpdateTaskDir = Resolve-ConfigPath -PathValue $vmUpdateTaskDirName -RootPath $repoRoot

    $defaultPortsCsv = Get-ProdicloudDefaultTcpPortsCsv
    $tcpPortsConfiguredCsv = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'TCP_PORTS' -DefaultValue $defaultPortsCsv)
    if ([string]::IsNullOrWhiteSpace([string]$tcpPortsConfiguredCsv)) { $tcpPortsConfiguredCsv = [string]$defaultPortsCsv }
    $requiredPorts = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$sshPort)) { $requiredPorts += [string]$sshPort }
    if ([bool]$platformDefaults.IncludeRdp -and -not [string]::IsNullOrWhiteSpace([string]$rdpPort)) { $requiredPorts += [string]$rdpPort }
    $tcpPortSpecification = Resolve-ProdicloudTcpPortSpecification -Text $tcpPortsConfiguredCsv -RequiredPorts $requiredPorts
    $tcpPortsConfiguredCsv = [string]$tcpPortSpecification.CanonicalText
    $tcpPorts = @($tcpPortSpecification.Ports)

    $taskOutcomeModeRaw = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'VM_TASK_OUTCOME_MODE' -DefaultValue 'continue')
    if ([string]::IsNullOrWhiteSpace($taskOutcomeModeRaw)) { $taskOutcomeModeRaw = 'continue' }
    $taskOutcomeMode = $taskOutcomeModeRaw.Trim().ToLowerInvariant()
    if ($taskOutcomeMode -ne 'continue' -and $taskOutcomeMode -ne 'strict') {
        Throw-FriendlyError `
            -Detail ("Invalid VM_TASK_OUTCOME_MODE '{0}'." -f $taskOutcomeModeRaw) `
            -Code 14 `
            -Summary "Task outcome mode is invalid." `
            -Hint "Set VM_TASK_OUTCOME_MODE=continue or VM_TASK_OUTCOME_MODE=strict."
    }

    $configuredPySshClientPath = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'PYSSH_CLIENT_PATH' -DefaultValue (Get-ProdicloudDefaultPySshClientPathText))
    $sshTaskTimeoutText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SSH_TASK_TIMEOUT_SECONDS' -DefaultValue ([string]$script:SshTaskTimeoutSeconds))
    $sshTaskTimeoutSeconds = $script:SshTaskTimeoutSeconds
    if ($sshTaskTimeoutText -match '^\d+$') { $sshTaskTimeoutSeconds = [int]$sshTaskTimeoutText }
    if ($sshTaskTimeoutSeconds -lt 30) { $sshTaskTimeoutSeconds = 30 }
    if ($sshTaskTimeoutSeconds -gt 7200) { $sshTaskTimeoutSeconds = 7200 }

    $sshConnectTimeoutText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SSH_CONNECT_TIMEOUT_SECONDS' -DefaultValue ([string]$script:SshConnectTimeoutSeconds))
    $sshConnectTimeoutSeconds = $script:SshConnectTimeoutSeconds
    if ($sshConnectTimeoutText -match '^\d+$') { $sshConnectTimeoutSeconds = [int]$sshConnectTimeoutText }
    if ($sshConnectTimeoutSeconds -lt 5) { $sshConnectTimeoutSeconds = 5 }
    if ($sshConnectTimeoutSeconds -gt 300) { $sshConnectTimeoutSeconds = 300 }

    $azCommandTimeoutText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'AZURE_COMMAND_TIMEOUT_SECONDS' -DefaultValue ([string]$script:AzCommandTimeoutSeconds))
    $azCommandTimeoutSeconds = $script:AzCommandTimeoutSeconds
    if ($azCommandTimeoutText -match '^\d+$') { $azCommandTimeoutSeconds = [int]$azCommandTimeoutText }
    if ($azCommandTimeoutSeconds -lt 30) { $azCommandTimeoutSeconds = 30 }
    if ($azCommandTimeoutSeconds -gt 7200) { $azCommandTimeoutSeconds = 7200 }

    $script:AzCommandTimeoutSeconds = $azCommandTimeoutSeconds
    $script:SshTaskTimeoutSeconds = $sshTaskTimeoutSeconds
    $script:SshConnectTimeoutSeconds = $sshConnectTimeoutSeconds

    $context = [ordered]@{
        ResourceGroup = [string]$resourceGroup
        AzLocation = [string]$azLocation
        VmName = [string]$vmName
        VmImage = [string]$vmImage
        VmStorageSku = [string]$vmStorageSku
        VmSize = [string]$vmSize
        VmDiskName = [string]$vmDiskName
        VmDiskSize = [string]$vmDiskSize
        CompanyName = [string]$companyName
        CompanyWebAddress = [string]$companyWebAddress
        CompanyEmailAddress = [string]$companyEmailAddress
        EmployeeEmailAddress = [string]$employeeEmailAddress
        EmployeeFullName = [string]$employeeFullName
        ShortcutSocialBusinessLinkedInUrl = [string]$shortcutSocialBusinessLinkedInUrl
        ShortcutSocialBusinessYouTubeUrl = [string]$shortcutSocialBusinessYouTubeUrl
        ShortcutSocialBusinessGitHubUrl = [string]$shortcutSocialBusinessGitHubUrl
        ShortcutSocialBusinessTikTokUrl = [string]$shortcutSocialBusinessTikTokUrl
        ShortcutSocialBusinessInstagramUrl = [string]$shortcutSocialBusinessInstagramUrl
        ShortcutSocialBusinessFacebookUrl = [string]$shortcutSocialBusinessFacebookUrl
        ShortcutSocialBusinessXUrl = [string]$shortcutSocialBusinessXUrl
        ShortcutSocialBusinessSnapchatUrl = [string]$shortcutSocialBusinessSnapchatUrl
        ShortcutSocialBusinessNextSosyalUrl = [string]$shortcutSocialBusinessNextSosyalUrl
        ShortcutSocialPersonalLinkedInUrl = [string]$shortcutSocialPersonalLinkedInUrl
        ShortcutSocialPersonalYouTubeUrl = [string]$shortcutSocialPersonalYouTubeUrl
        ShortcutSocialPersonalGitHubUrl = [string]$shortcutSocialPersonalGitHubUrl
        ShortcutSocialPersonalTikTokUrl = [string]$shortcutSocialPersonalTikTokUrl
        ShortcutSocialPersonalInstagramUrl = [string]$shortcutSocialPersonalInstagramUrl
        ShortcutSocialPersonalFacebookUrl = [string]$shortcutSocialPersonalFacebookUrl
        ShortcutSocialPersonalXUrl = [string]$shortcutSocialPersonalXUrl
        ShortcutWebBusinessHomeUrl = [string]$shortcutWebBusinessHomeUrl
        ShortcutWebBusinessBlogUrl = [string]$shortcutWebBusinessBlogUrl
        VmUser = [string]$vmUser
        VmPass = [string]$vmPass
        VmAssistantUser = [string]$vmAssistantUser
        VmAssistantPass = [string]$vmAssistantPass
        SshPort = [string]$sshPort
        RdpPort = [string]$rdpPort
        TcpPorts = @($tcpPorts)
        TcpPortRanges = @($tcpPortSpecification.PortRanges)
        TcpPortsConfiguredCsv = [string]$tcpPortsConfiguredCsv
        VmInitTaskDir = [string]$vmInitTaskDir
        VmUpdateTaskDir = [string]$vmUpdateTaskDir
        VmOsType = [string]$platform
        AzureSubscriptionId = [string]$((Get-ProdicloudResolvedSubscriptionContext).SubscriptionId)
        AzureSubscriptionName = [string]$((Get-ProdicloudResolvedSubscriptionContext).SubscriptionName)
        AzCommandTimeoutSeconds = [int]$azCommandTimeoutSeconds
        SshTaskTimeoutSeconds = [int]$sshTaskTimeoutSeconds
        SshConnectTimeoutSeconds = [int]$sshConnectTimeoutSeconds
    }
    $context['ConfigMap'] = $effectiveConfigMap

    return [pscustomobject]@{
        EnvFilePath = $envFilePath
        ConfigMap = $configMap
        EffectiveConfigMap = $effectiveConfigMap
        Platform = $platform
        PlatformDefaults = $platformDefaults
        Context = $context
        TaskOutcomeMode = $taskOutcomeMode
        ConfiguredPySshClientPath = $configuredPySshClientPath
        SshTaskTimeoutSeconds = $sshTaskTimeoutSeconds
        SshConnectTimeoutSeconds = $sshConnectTimeoutSeconds
    }
}

# Handles Initialize-ProdicloudTaskCommandRuntimeContext.
function Initialize-ProdicloudTaskCommandRuntimeContext {
    param(
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [hashtable]$Options = @{}
    )

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Get-ProdicloudGlobalEnvPath
    $globalConfigMap = Read-DotEnvFile -Path $envFilePath -GlobalOnly
    $requestedVmName = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-name')
    if ([string]::IsNullOrWhiteSpace([string]$requestedVmName) -and $script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME')) { $requestedVmName = [string]$script:ConfigOverrides['SELECTED_VM_NAME'] }
    if ([string]::IsNullOrWhiteSpace([string]$requestedVmName)) { $requestedVmName = [string]$globalConfigMap['ACTIVE_VM_NAME'] }
    $configMap = Merge-ProdicloudVmEnvironmentConfig -GlobalConfigMap $globalConfigMap -VmName $requestedVmName -RequireProfile:([bool](-not [string]::IsNullOrWhiteSpace([string]$requestedVmName)))
    $platform = Resolve-ProdicloudPlatformSelection -ConfigMap $configMap -EnvFilePath $envFilePath -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -ConfigOverrides $script:ConfigOverrides
    $platformDefaults = Get-ProdicloudPlatformDefaults -Platform $platform
    $effectiveConfigMap = Resolve-ProdicloudPlatformConfigMap -ConfigMap $configMap -Platform $platform

    $vmName = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $azLocation = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
    $regionCode = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$azLocation)) {
        $regionCode = Get-ProdicloudRegionCode -Location ([string]$azLocation)
    }

    $nameTokens = @{
        SELECTED_VM_NAME = [string]$vmName
        REGION_CODE = [string]$regionCode
        N = '1'
    }

    $vmInitTaskDirName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key (Get-ProdicloudPlatformTaskCatalogConfigKey -Platform $platform -Stage 'init') -DefaultValue ([string]$platformDefaults.VmInitTaskDirDefault))) -Tokens $nameTokens
    $vmUpdateTaskDirName = Resolve-ProdicloudTemplate -Template ([string](Get-ConfigValue -Config $effectiveConfigMap -Key (Get-ProdicloudPlatformTaskCatalogConfigKey -Platform $platform -Stage 'update') -DefaultValue ([string]$platformDefaults.VmUpdateTaskDirDefault))) -Tokens $nameTokens

    return [pscustomobject]@{
        RepoRoot = $repoRoot
        EnvFilePath = $envFilePath
        ConfigMap = $configMap
        EffectiveConfigMap = $effectiveConfigMap
        Platform = $platform
        PlatformDefaults = $platformDefaults
        VmInitTaskDir = Resolve-ConfigPath -PathValue $vmInitTaskDirName -RootPath $repoRoot
        VmUpdateTaskDir = Resolve-ConfigPath -PathValue $vmUpdateTaskDirName -RootPath $repoRoot
    }
}
