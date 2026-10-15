# Interactive configure editor helpers.

function New-ClagnosConfigureFieldSpec {
    param(
        [string]$Key,
        [string]$Section,
        [string]$Label,
        [string]$EditorKind,
        [switch]$AzureBacked,
        [switch]$Secret,
        [string]$Notes = ''
    )

    return [pscustomobject]@{
        Key = [string]$Key
        Section = [string]$Section
        Label = [string]$Label
        EditorKind = [string]$EditorKind
        AzureBacked = [bool]$AzureBacked
        Secret = [bool]$Secret
        Notes = [string]$Notes
    }
}

function Get-ClagnosConfigureSectionNames {
    return @(
        'Basic',
        'Platform & Compute',
        'Identity & Secrets',
        'Advanced'
    )
}

function Get-ClagnosConfigureFieldSchema {
    param(
        [string]$SelectedPlatform = 'windows'
    )

    $platformText = [string]$SelectedPlatform
    if ([string]::IsNullOrWhiteSpace([string]$platformText)) {
        $platformText = 'windows'
    }
    $platformText = $platformText.Trim().ToLowerInvariant()
    if ($platformText -notin @('windows','linux')) {
        $platformText = 'windows'
    }

    $activePrefix = if ($platformText -eq 'windows') { 'WIN' } else { 'LIN' }
    $inactivePrefix = if ($platformText -eq 'windows') { 'LIN' } else { 'WIN' }
    $activeLabel = if ($platformText -eq 'windows') { 'Windows' } else { 'Linux' }
    $inactiveLabel = if ($platformText -eq 'windows') { 'Linux' } else { 'Windows' }

    $fields = @(
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_VM_OS' -Section 'Basic' -Label 'Selected VM OS' -EditorKind 'vm-os-picker')
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_VM_NAME' -Section 'Basic' -Label 'Selected VM name' -EditorKind 'vm-name')
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_RESOURCE_GROUP' -Section 'Basic' -Label 'Selected resource group' -EditorKind 'resource-group-picker' -AzureBacked)
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Section 'Basic' -Label 'Selected Azure subscription' -EditorKind 'subscription-picker' -AzureBacked)
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_AZURE_REGION' -Section 'Basic' -Label 'Selected Azure region' -EditorKind 'region-picker' -AzureBacked)

        (New-ClagnosConfigureFieldSpec -Key 'VM_STORAGE_SKU' -Section 'Platform & Compute' -Label 'VM storage SKU' -EditorKind 'storage-sku-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_SECURITY_TYPE' -Section 'Platform & Compute' -Label 'VM security type' -EditorKind 'security-type-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ENABLE_HIBERNATION' -Section 'Platform & Compute' -Label 'Enable hibernation' -EditorKind 'toggle-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ENABLE_NESTED_VIRTUALIZATION' -Section 'Platform & Compute' -Label 'Enable nested virtualization' -EditorKind 'toggle-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ENABLE_SECURE_BOOT' -Section 'Platform & Compute' -Label 'Enable secure boot' -EditorKind 'toggle-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ENABLE_VTPM' -Section 'Platform & Compute' -Label 'Enable vTPM' -EditorKind 'toggle-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_PRICE_COUNT_HOURS' -Section 'Platform & Compute' -Label 'Monthly price hour count' -EditorKind 'positive-int')
        (New-ClagnosConfigureFieldSpec -Key ("{0}_VM_IMAGE" -f $activePrefix) -Section 'Platform & Compute' -Label ("{0} VM image" -f $activeLabel) -EditorKind 'vm-image-picker' -AzureBacked)
        (New-ClagnosConfigureFieldSpec -Key ("{0}_VM_SIZE" -f $activePrefix) -Section 'Platform & Compute' -Label ("{0} VM size" -f $activeLabel) -EditorKind 'vm-size-picker' -AzureBacked)
        (New-ClagnosConfigureFieldSpec -Key ("{0}_VM_DISK_SIZE_GB" -f $activePrefix) -Section 'Platform & Compute' -Label ("{0} VM disk size (GB)" -f $activeLabel) -EditorKind 'positive-int')
        (New-ClagnosConfigureFieldSpec -Key ("{0}_VM_IMAGE" -f $inactivePrefix) -Section 'Platform & Compute' -Label ("{0} VM image" -f $inactiveLabel) -EditorKind 'vm-image-picker' -AzureBacked)
        (New-ClagnosConfigureFieldSpec -Key ("{0}_VM_SIZE" -f $inactivePrefix) -Section 'Platform & Compute' -Label ("{0} VM size" -f $inactiveLabel) -EditorKind 'vm-size-picker' -AzureBacked)
        (New-ClagnosConfigureFieldSpec -Key ("{0}_VM_DISK_SIZE_GB" -f $inactivePrefix) -Section 'Platform & Compute' -Label ("{0} VM disk size (GB)" -f $inactiveLabel) -EditorKind 'positive-int')

        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_COMPANY_NAME' -Section 'Identity & Secrets' -Label 'Company name' -EditorKind 'text')
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_COMPANY_WEB_ADDRESS' -Section 'Identity & Secrets' -Label 'Company web address' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_COMPANY_EMAIL_ADDRESS' -Section 'Identity & Secrets' -Label 'Company email address' -EditorKind 'email')
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' -Section 'Identity & Secrets' -Label 'Employee email address' -EditorKind 'email')
        (New-ClagnosConfigureFieldSpec -Key 'SELECTED_EMPLOYEE_FULL_NAME' -Section 'Identity & Secrets' -Label 'Employee full name' -EditorKind 'text')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL' -Section 'Identity & Secrets' -Label 'Business LinkedIn shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL' -Section 'Identity & Secrets' -Label 'Business YouTube shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL' -Section 'Identity & Secrets' -Label 'Business GitHub shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL' -Section 'Identity & Secrets' -Label 'Business TikTok shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL' -Section 'Identity & Secrets' -Label 'Business Instagram shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL' -Section 'Identity & Secrets' -Label 'Business Facebook shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL' -Section 'Identity & Secrets' -Label 'Business X shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL' -Section 'Identity & Secrets' -Label 'Business Snapchat shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL' -Section 'Identity & Secrets' -Label 'Business NextSosyal shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL' -Section 'Identity & Secrets' -Label 'Personal LinkedIn shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL' -Section 'Identity & Secrets' -Label 'Personal YouTube shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL' -Section 'Identity & Secrets' -Label 'Personal GitHub shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL' -Section 'Identity & Secrets' -Label 'Personal TikTok shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL' -Section 'Identity & Secrets' -Label 'Personal Instagram shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL' -Section 'Identity & Secrets' -Label 'Personal Facebook shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL' -Section 'Identity & Secrets' -Label 'Personal X shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL' -Section 'Identity & Secrets' -Label 'Business home shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL' -Section 'Identity & Secrets' -Label 'Business blog shortcut URL' -EditorKind 'url')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ADMIN_USER' -Section 'Identity & Secrets' -Label 'Admin user name' -EditorKind 'text')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ADMIN_PASS' -Section 'Identity & Secrets' -Label 'Admin password' -EditorKind 'secret' -Secret)
        (New-ClagnosConfigureFieldSpec -Key 'VM_ASSISTANT_USER' -Section 'Identity & Secrets' -Label 'Assistant user name' -EditorKind 'text')
        (New-ClagnosConfigureFieldSpec -Key 'VM_ASSISTANT_PASS' -Section 'Identity & Secrets' -Label 'Assistant password' -EditorKind 'secret' -Secret)

        (New-ClagnosConfigureFieldSpec -Key 'RESOURCE_GROUP_TEMPLATE' -Section 'Advanced' -Label 'Resource group template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'VNET_NAME_TEMPLATE' -Section 'Advanced' -Label 'VNet name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'SUBNET_NAME_TEMPLATE' -Section 'Advanced' -Label 'Subnet name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'NSG_NAME_TEMPLATE' -Section 'Advanced' -Label 'NSG name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'NSG_RULE_NAME_TEMPLATE' -Section 'Advanced' -Label 'NSG rule name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'PUBLIC_IP_NAME_TEMPLATE' -Section 'Advanced' -Label 'Public IP name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'NIC_NAME_TEMPLATE' -Section 'Advanced' -Label 'NIC name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'VM_DISK_NAME_TEMPLATE' -Section 'Advanced' -Label 'VM disk name template' -EditorKind 'template')
        (New-ClagnosConfigureFieldSpec -Key 'VM_SSH_PORT' -Section 'Advanced' -Label 'SSH port' -EditorKind 'port')
        (New-ClagnosConfigureFieldSpec -Key 'VM_RDP_PORT' -Section 'Advanced' -Label 'RDP port' -EditorKind 'port')
        (New-ClagnosConfigureFieldSpec -Key 'AZURE_COMMAND_TIMEOUT_SECONDS' -Section 'Advanced' -Label 'Azure command timeout (seconds)' -EditorKind 'positive-int')
        (New-ClagnosConfigureFieldSpec -Key 'SSH_CONNECT_TIMEOUT_SECONDS' -Section 'Advanced' -Label 'SSH connect timeout (seconds)' -EditorKind 'positive-int')
        (New-ClagnosConfigureFieldSpec -Key 'SSH_TASK_TIMEOUT_SECONDS' -Section 'Advanced' -Label 'SSH task timeout (seconds)' -EditorKind 'positive-int')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_VM_INIT_TASK_DIR' -Section 'Advanced' -Label 'Windows vm-init task directory' -EditorKind 'task-dir-picker')
        (New-ClagnosConfigureFieldSpec -Key 'WIN_VM_UPDATE_TASK_DIR' -Section 'Advanced' -Label 'Windows vm-update task directory' -EditorKind 'task-dir-picker')
        (New-ClagnosConfigureFieldSpec -Key 'LIN_VM_INIT_TASK_DIR' -Section 'Advanced' -Label 'Linux vm-init task directory' -EditorKind 'task-dir-picker')
        (New-ClagnosConfigureFieldSpec -Key 'LIN_VM_UPDATE_TASK_DIR' -Section 'Advanced' -Label 'Linux vm-update task directory' -EditorKind 'task-dir-picker')
        (New-ClagnosConfigureFieldSpec -Key 'VM_TASK_OUTCOME_MODE' -Section 'Advanced' -Label 'Task outcome mode' -EditorKind 'task-outcome-picker')
        (New-ClagnosConfigureFieldSpec -Key 'SSH_MAX_RETRIES' -Section 'Advanced' -Label 'SSH max retries' -EditorKind 'positive-int')
        (New-ClagnosConfigureFieldSpec -Key 'PACKAGE_TRANSPORT' -Section 'Advanced' -Label 'Windows package transport' -EditorKind 'package-transport-picker')
        (New-ClagnosConfigureFieldSpec -Key 'PYSSH_CLIENT_PATH' -Section 'Advanced' -Label 'PYSSH client path' -EditorKind 'pyssh-path-picker')
        (New-ClagnosConfigureFieldSpec -Key 'TCP_PORTS' -Section 'Advanced' -Label 'TCP ports' -EditorKind 'tcp-ports-picker')
    )

    return @($fields)
}

function Get-ClagnosConfigureMergedValues {
    param(
        [hashtable]$CurrentConfig,
        [hashtable]$DefaultConfig
    )

    $result = [ordered]@{}
    foreach ($key in @(Get-ClagnosSupportedDotEnvKeys)) {
        $valueText = ''
        if ($CurrentConfig -and $CurrentConfig.ContainsKey([string]$key)) {
            $valueText = [string]$CurrentConfig[[string]$key]
        }
        elseif ($DefaultConfig -and $DefaultConfig.ContainsKey([string]$key)) {
            $valueText = [string]$DefaultConfig[[string]$key]
        }
        $result[[string]$key] = [string]$valueText
    }

    return $result
}

function Get-ClagnosConfigureSelectedPlatform {
    param(
        [hashtable]$Values
    )

    $platformText = [string](Get-ConfigValue -Config $Values -Key 'SELECTED_VM_OS' -DefaultValue 'windows')
    if ([string]::IsNullOrWhiteSpace([string]$platformText)) {
        return 'windows'
    }

    $normalized = $platformText.Trim().ToLowerInvariant()
    if ($normalized -notin @('windows','linux')) {
        return 'windows'
    }

    return $normalized
}

function Get-ClagnosConfigureCreateCriticalKeys {
    param(
        [hashtable]$Values
    )

    $platform = Get-ClagnosConfigureSelectedPlatform -Values $Values
    $vmImageKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
    $vmSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'

    return @(
        'SELECTED_VM_OS',
        'SELECTED_VM_NAME',
        'SELECTED_AZURE_REGION',
        [string]$vmImageKey,
        [string]$vmSizeKey,
        'VM_ADMIN_USER',
        'VM_ADMIN_PASS',
        'VM_ASSISTANT_USER',
        'VM_ASSISTANT_PASS'
    )
}

function Test-ClagnosConfigureFieldIsCreateCritical {
    param(
        [string]$Key,
        [hashtable]$Values
    )

    foreach ($candidate in @(Get-ClagnosConfigureCreateCriticalKeys -Values $Values)) {
        if ([string]::Equals([string]$candidate, [string]$Key, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-ClagnosConfigureFieldAllowsBlank {
    param(
        [string]$Key,
        [hashtable]$Values
    )

    return (-not (Test-ClagnosConfigureFieldIsCreateCritical -Key $Key -Values $Values))
}

function Test-ClagnosConfigureChoiceContainsValue {
    param(
        [object[]]$Rows,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }

    foreach ($row in @(ConvertTo-ObjectArrayCompat -InputObject $Rows)) {
        if ($null -eq $row) {
            continue
        }

        if ([string]::Equals([string]$row.Value, [string]$Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-ClagnosConfigureFriendlyErrorSummary {
    param(
        [System.Exception]$Exception
    )

    if ($null -eq $Exception) {
        return 'The value is invalid.'
    }

    if ($Exception.Data -and $Exception.Data.Contains('Summary')) {
        $summary = [string]$Exception.Data['Summary']
        if (-not [string]::IsNullOrWhiteSpace([string]$summary)) {
            return $summary
        }
    }

    return [string]$Exception.Message
}

function Get-ClagnosConfigureFriendlyErrorHint {
    param(
        [System.Exception]$Exception
    )

    if ($null -eq $Exception) {
        return ''
    }

    if ($Exception.Data -and $Exception.Data.Contains('Hint')) {
        return [string]$Exception.Data['Hint']
    }

    return ''
}

function Test-ClagnosConfigureExceptionIsRecoverable {
    param(
        [System.Exception]$Exception
    )

    if ($null -eq $Exception) {
        return $false
    }

    $typeName = [string]$Exception.GetType().FullName
    if ($typeName -in @(
        'System.Management.Automation.PipelineStoppedException',
        'System.OperationCanceledException',
        'System.Management.Automation.Host.HostException'
    )) {
        return $false
    }

    if ($Exception.Data -and $Exception.Data.Contains('ExitCode')) {
        return $true
    }

    return $false
}

function Write-ClagnosConfigureValidationMessage {
    param(
        [psobject]$Field,
        [System.Exception]$Exception
    )

    $summary = Get-ClagnosConfigureFriendlyErrorSummary -Exception $Exception
    $hint = Get-ClagnosConfigureFriendlyErrorHint -Exception $Exception

    Write-Host ("{0}: {1}" -f [string]$Field.Label, [string]$summary) -ForegroundColor Yellow
    if (-not [string]::IsNullOrWhiteSpace([string]$hint)) {
        Write-Host $hint -ForegroundColor DarkGray
    }
}

function ConvertTo-ClagnosConfigureDisplayValue {
    param(
        [object]$Value,
        [switch]$Secret
    )

    if ($Secret) {
        return '[redacted]'
    }

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return '(empty)'
    }

    return $text
}

function Initialize-ClagnosConfigureAzureState {
    param(
        [hashtable]$Values
    )

    $state = @{
        Available = $false
        Hint = 'Run az login to edit or verify this field.'
        SubscriptionRows = @()
        SelectedSubscriptionRow = $null
    }

    Clear-ClagnosResolvedSubscriptionContext
    try {
        $rows = @(Get-ClagnosAccessibleSubscriptionRows)
        if (@($rows).Count -le 0) {
            return $state
        }

        $requestedSubscriptionId = [string](Get-ConfigValue -Config $Values -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -DefaultValue '')
        $selectedRow = $null
        if (-not [string]::IsNullOrWhiteSpace([string]$requestedSubscriptionId) -and (Test-ClagnosSubscriptionIdFormat -SubscriptionId $requestedSubscriptionId)) {
            $selectedRow = Find-ClagnosSubscriptionRowById -SubscriptionRows $rows -SubscriptionId $requestedSubscriptionId
        }
        if ($null -eq $selectedRow) {
            $selectedRow = Get-ClagnosDefaultSubscriptionRow -SubscriptionRows $rows
        }

        Set-ClagnosResolvedSubscriptionContext `
            -SubscriptionId ([string]$selectedRow.id) `
            -SubscriptionName ([string]$selectedRow.name) `
            -TenantId ([string]$selectedRow.tenantId) `
            -ResolutionSource 'configure'

        $state['Available'] = $true
        $state['SubscriptionRows'] = @($rows)
        $state['SelectedSubscriptionRow'] = $selectedRow
        return $state
    }
    catch {
        return $state
    }
}

function Set-ClagnosConfigureAzureSubscription {
    param(
        [hashtable]$State,
        [object]$SubscriptionRow
    )

    if ($null -eq $State -or $null -eq $SubscriptionRow) {
        return
    }

    Set-ClagnosResolvedSubscriptionContext `
        -SubscriptionId ([string]$SubscriptionRow.id) `
        -SubscriptionName ([string]$SubscriptionRow.name) `
        -TenantId ([string]$SubscriptionRow.tenantId) `
        -ResolutionSource 'configure'
    $State['Available'] = $true
    $State['SelectedSubscriptionRow'] = $SubscriptionRow
}

function Get-ClagnosConfigureBooleanRows {
    return @(
        [pscustomobject]@{ Value = 'true'; Label = 'true'; Description = 'Enabled.' }
        [pscustomobject]@{ Value = 'false'; Label = 'false'; Description = 'Disabled.' }
    )
}

function Get-ClagnosConfigureTaskDirRows {
    param(
        [string]$Key,
        [hashtable]$State
    )

    $repoRoot = [string]$State['RepoRoot']
    $candidates = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $currentValue = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key $Key -DefaultValue '')
    $defaults = @{
        'WIN_VM_INIT_TASK_DIR' = 'vm-init/windows'
        'WIN_VM_UPDATE_TASK_DIR' = 'vm-update/windows'
        'LIN_VM_INIT_TASK_DIR' = 'vm-init/linux'
        'LIN_VM_UPDATE_TASK_DIR' = 'vm-update/linux'
    }

    foreach ($candidate in @($currentValue, [string]$defaults[$Key])) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }
        $resolvedPath = Resolve-ConfigPath -PathValue ([string]$candidate) -RootPath $repoRoot
        if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
            [void]$candidates.Add(([string]$candidate).Trim())
        }
    }

    $rows = @()
    foreach ($candidate in @($candidates | Sort-Object)) {
        $rows += [pscustomobject]@{
            Value = [string]$candidate
            Label = [string]$candidate
            Description = 'Existing task catalog directory.'
        }
    }
    return @($rows)
}

function Get-ClagnosConfigurePySshPathRows {
    param(
        [hashtable]$State
    )

    $repoRoot = [string]$State['RepoRoot']
    $currentValue = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'PYSSH_CLIENT_PATH' -DefaultValue '')
    $candidates = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in @($currentValue, (Get-ClagnosDefaultPySshClientPathText))) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }
        $resolvedPath = Resolve-ConfigPath -PathValue ([string]$candidate) -RootPath $repoRoot
        if (Test-Path -LiteralPath $resolvedPath -PathType Leaf) {
            [void]$candidates.Add(([string]$candidate).Trim())
        }
    }

    $discovered = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'tools') -Recurse -Filter 'ssh_client.py' -File -ErrorAction SilentlyContinue)
    foreach ($fileInfo in @($discovered)) {
        $relativePath = $fileInfo.FullName
        if ($relativePath.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $relativePath.Substring($repoRoot.Length).TrimStart('\','/')
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$relativePath)) {
            [void]$candidates.Add($relativePath)
        }
    }

    $rows = @()
    foreach ($candidate in @($candidates | Sort-Object)) {
        $rows += [pscustomobject]@{
            Value = [string]$candidate
            Label = [string]$candidate
            Description = 'Existing PYSSH client path.'
        }
    }

    return @($rows)
}

function Get-ClagnosConfigureChoiceRows {
    param(
        [string]$Key,
        [hashtable]$State
    )

    $rows = @()
    switch ([string]$Key) {
        'SELECTED_VM_OS' {
            $rows = @(
                [pscustomobject]@{ Value = 'windows'; Label = 'windows'; Description = 'Windows platform defaults and task catalogs.' }
                [pscustomobject]@{ Value = 'linux'; Label = 'linux'; Description = 'Linux platform defaults and task catalogs.' }
            )
        }
        'VM_STORAGE_SKU' {
            $rows = @(
                [pscustomobject]@{ Value = 'StandardSSD_LRS'; Label = 'StandardSSD_LRS'; Description = 'Balanced standard SSD.' }
                [pscustomobject]@{ Value = 'StandardSSD_ZRS'; Label = 'StandardSSD_ZRS'; Description = 'Standard SSD with zone redundancy.' }
                [pscustomobject]@{ Value = 'Premium_LRS'; Label = 'Premium_LRS'; Description = 'Premium SSD locally redundant.' }
                [pscustomobject]@{ Value = 'Premium_ZRS'; Label = 'Premium_ZRS'; Description = 'Premium SSD with zone redundancy.' }
                [pscustomobject]@{ Value = 'PremiumV2_LRS'; Label = 'PremiumV2_LRS'; Description = 'Premium SSD v2.' }
                [pscustomobject]@{ Value = 'Standard_LRS'; Label = 'Standard_LRS'; Description = 'Standard HDD.' }
                [pscustomobject]@{ Value = 'Standard_ZRS'; Label = 'Standard_ZRS'; Description = 'Standard HDD with zone redundancy.' }
                [pscustomobject]@{ Value = 'UltraSSD_LRS'; Label = 'UltraSSD_LRS'; Description = 'Ultra disk.' }
            )
        }
        'VM_SECURITY_TYPE' {
            $rows = @(
                [pscustomobject]@{ Value = ''; Label = '(empty)'; Description = 'No explicit security type.' }
                [pscustomobject]@{ Value = 'Standard'; Label = 'Standard'; Description = 'Standard VM security profile.' }
                [pscustomobject]@{ Value = 'TrustedLaunch'; Label = 'TrustedLaunch'; Description = 'Trusted Launch security profile.' }
            )
        }
        'VM_ENABLE_HIBERNATION' { $rows = Get-ClagnosConfigureBooleanRows }
        'VM_ENABLE_NESTED_VIRTUALIZATION' { $rows = Get-ClagnosConfigureBooleanRows }
        'VM_ENABLE_SECURE_BOOT' { $rows = Get-ClagnosConfigureBooleanRows }
        'VM_ENABLE_VTPM' { $rows = Get-ClagnosConfigureBooleanRows }
        'VM_TASK_OUTCOME_MODE' {
            $rows = @(
                [pscustomobject]@{ Value = 'continue'; Label = 'continue'; Description = 'Log task failures and continue.' }
                [pscustomobject]@{ Value = 'strict'; Label = 'strict'; Description = 'Stop the task stage on the first failure.' }
            )
        }
        'PACKAGE_TRANSPORT' {
            $rows = @(
                [pscustomobject]@{ Value = 'ssh'; Label = 'ssh'; Description = 'Use SSH for Windows package operations.' }
                [pscustomobject]@{ Value = 'winrm'; Label = 'winrm'; Description = 'Use Windows PowerShell remoting for package operations.' }
            )
        }
        default {
            if ($Key -in @('WIN_VM_INIT_TASK_DIR','WIN_VM_UPDATE_TASK_DIR','LIN_VM_INIT_TASK_DIR','LIN_VM_UPDATE_TASK_DIR')) {
                $rows = Get-ClagnosConfigureTaskDirRows -Key $Key -State $State
            }
            elseif ($Key -eq 'PYSSH_CLIENT_PATH') {
                $rows = Get-ClagnosConfigurePySshPathRows -State $State
            }
        }
    }

    return @($rows)
}

function Get-ClagnosConfigureSubscriptionRows {
    param(
        [hashtable]$State
    )

    $azureState = [hashtable]$State['Azure']
    if ($null -eq $azureState -or -not [bool]$azureState['Available']) {
        return @()
    }

    $rows = @()
    foreach ($subscriptionRow in @(ConvertTo-ObjectArrayCompat -InputObject $azureState['SubscriptionRows'])) {
        if ($null -eq $subscriptionRow) {
            continue
        }

        $subscriptionId = [string]$subscriptionRow.id
        if ([string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
            continue
        }

        $description = $subscriptionId
        if ([bool]$subscriptionRow.isDefault) {
            $description = "{0} [active default]" -f $description
        }

        $rows += [pscustomobject]@{
            Value = $subscriptionId
            Label = [string]$subscriptionRow.name
            Description = $description
        }
    }

    return @($rows)
}

function Get-ClagnosConfigureRegionRows {
    param(
        [hashtable]$State
    )

    $azureState = [hashtable]$State['Azure']
    if ($null -eq $azureState -or -not [bool]$azureState['Available']) {
        return @()
    }

    $rows = @()
    foreach ($location in @(Get-AzLocationCatalog)) {
        if ($null -eq $location) {
            continue
        }

        $locationName = [string]$location.Name
        if ([string]::IsNullOrWhiteSpace([string]$locationName)) {
            continue
        }

        $rows += [pscustomobject]@{
            Value = $locationName.Trim().ToLowerInvariant()
            Label = [string]$location.DisplayName
            Description = $locationName.Trim().ToLowerInvariant()
        }
    }

    return @($rows)
}

function Get-ClagnosConfigureManagedResourceGroupRows {
    param(
        [hashtable]$State
    )

    $azureState = [hashtable]$State['Azure']
    if ($null -eq $azureState -or -not [bool]$azureState['Available']) {
        return @()
    }

    $rows = @()
    try {
        $groupRows = @(Get-ClagnosManagedResourceGroupRows)
    }
    catch {
        return @()
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($groupRow in @($groupRows)) {
        if ($null -eq $groupRow) {
            continue
        }

        $groupName = [string]$groupRow.name
        if ([string]::IsNullOrWhiteSpace([string]$groupName) -or -not $seen.Add($groupName)) {
            continue
        }

        $descriptionParts = New-Object 'System.Collections.Generic.List[string]'
        $location = [string]$groupRow.location
        if (-not [string]::IsNullOrWhiteSpace([string]$location)) {
            [void]$descriptionParts.Add($location.Trim().ToLowerInvariant())
        }
        $groupId = [string]$groupRow.id
        if (-not [string]::IsNullOrWhiteSpace([string]$groupId)) {
            [void]$descriptionParts.Add($groupId.Trim())
        }

        $rows += [pscustomobject]@{
            Value = $groupName.Trim()
            Label = $groupName.Trim()
            Description = (@($descriptionParts) -join ' | ')
        }
    }

    return @($rows | Sort-Object Label)
}

function Select-ClagnosConfigureChoiceInteractive {
    param(
        [string]$Title,
        [object[]]$Rows,
        [string]$CurrentValue,
        [switch]$AllowEmptySelection,
        [string]$EmptySelectionLabel = '(clear value)'
    )

    $allRows = @(
        ConvertTo-ObjectArrayCompat -InputObject $Rows |
            Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.Label) }
    )
    if (@($allRows).Count -le 0) {
        return $null
    }

    $filterText = ''
    while ($true) {
        $visibleRows = @($allRows)
        if (-not [string]::IsNullOrWhiteSpace([string]$filterText)) {
            $needle = $filterText.Trim().ToLowerInvariant()
            $visibleRows = @(
                @($allRows) | Where-Object {
                    $haystack = @(
                        [string]$_.Label,
                        [string]$_.Value,
                        [string]$_.Description
                    ) -join ' '
                    $haystack.ToLowerInvariant().Contains($needle)
                }
            )
        }

        Write-Host ''
        Write-Host $Title -ForegroundColor Cyan
        Write-Host ("Current value: {0}" -f (ConvertTo-ClagnosConfigureDisplayValue -Value $CurrentValue)) -ForegroundColor DarkGray
        if (-not [string]::IsNullOrWhiteSpace([string]$filterText)) {
            Write-Host ("Filter: {0}" -f $filterText) -ForegroundColor DarkGray
        }
        $currentValueIsSelectable = Test-ClagnosConfigureChoiceContainsValue -Rows $allRows -Value $CurrentValue
        if (-not $currentValueIsSelectable -and -not [string]::IsNullOrWhiteSpace([string]$CurrentValue)) {
            Write-Host 'The current value is no longer in the available option list. Select a new value.' -ForegroundColor Yellow
        }
        if ($AllowEmptySelection) {
            Write-Host ("Type 'c' to set this field to {0}." -f $EmptySelectionLabel) -ForegroundColor DarkGray
        }

        if (@($visibleRows).Count -le 0) {
            Write-Host 'No matching options were found.' -ForegroundColor Yellow
        }
        else {
            $maxRows = [Math]::Min(@($visibleRows).Count, 30)
            for ($i = 0; $i -lt $maxRows; $i++) {
                $row = $visibleRows[$i]
                $marker = if ([string]::Equals([string]$row.Value, [string]$CurrentValue, [System.StringComparison]::OrdinalIgnoreCase)) { '*' } else { ' ' }
                $description = [string]$row.Description
                if ([string]::IsNullOrWhiteSpace([string]$description)) {
                    Write-Host ("{0}{1}. {2}" -f $marker, ($i + 1), [string]$row.Label)
                }
                else {
                    Write-Host ("{0}{1}. {2} - {3}" -f $marker, ($i + 1), [string]$row.Label, $description)
                }
            }
            if (@($visibleRows).Count -gt $maxRows) {
                Write-Host ("Showing the first {0} matching options. Refine the filter to narrow the list." -f $maxRows) -ForegroundColor DarkGray
            }
        }

        $prompt = if ($AllowEmptySelection) {
            "Enter number, 'f' to change filter, 'c' to clear, or press Enter to keep the current value"
        }
        else {
            "Enter number, 'f' to change filter, or press Enter to keep the current value"
        }
        $raw = Read-Host $prompt
        if ([string]::IsNullOrWhiteSpace([string]$raw)) {
            if ($currentValueIsSelectable -or ($AllowEmptySelection -and [string]::IsNullOrWhiteSpace([string]$CurrentValue))) {
                return $CurrentValue
            }

            Write-Host 'The current value cannot be kept because it is no longer valid.' -ForegroundColor Yellow
            continue
        }
        if ([string]::Equals([string]$raw, 'f', [System.StringComparison]::OrdinalIgnoreCase)) {
            $filterText = Read-Host 'Enter a filter string'
            continue
        }
        if ($AllowEmptySelection -and [string]::Equals([string]$raw, 'c', [System.StringComparison]::OrdinalIgnoreCase)) {
            return ''
        }
        if ($raw -match '^\d+$') {
            $index = [int]$raw
            if ($index -ge 1 -and $index -le @($visibleRows).Count) {
                return [string]$visibleRows[$index - 1].Value
            }
        }

        Write-Host 'Invalid selection. Please enter a valid number.' -ForegroundColor Yellow
    }
}

function ConvertFrom-ClagnosSecureStringToPlainText {
    param(
        [securestring]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ([System.Net.NetworkCredential]::new('', $Value).Password)
}

function Assert-ClagnosConfigurePositiveIntegerValue {
    param([string]$Key,[string]$Value)
    if (-not ($Value -match '^\d+$') -or [int]$Value -le 0) {
        Throw-FriendlyError -Detail ("Value '{0}' is invalid for {1}." -f $Value, $Key) -Code 2 -Summary 'Numeric value is invalid.' -Hint 'Use a positive integer.'
    }
    return ([string]([int]$Value))
}

function Assert-ClagnosConfigurePortValue {
    param([string]$Key,[string]$Value)
    if (-not ($Value -match '^\d+$')) {
        Throw-FriendlyError -Detail ("Port value '{0}' is invalid for {1}." -f $Value, $Key) -Code 2 -Summary 'Port value is invalid.' -Hint 'Use a TCP port between 1 and 65535.'
    }
    $port = [int]$Value
    if ($port -lt 1 -or $port -gt 65535) {
        Throw-FriendlyError -Detail ("Port value '{0}' is out of range for {1}." -f $Value, $Key) -Code 2 -Summary 'Port value is invalid.' -Hint 'Use a TCP port between 1 and 65535.'
    }
    return ([string]$port)
}

function Assert-ClagnosConfigureEmailValue {
    param([string]$Key,[string]$Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    if (Test-ClagnosConfigPlaceholderValue -Value $Value) {
        Throw-FriendlyError -Detail ("Value '{0}' is still a placeholder for {1}." -f $Value, $Key) -Code 2 -Summary 'Email value is invalid.' -Hint 'Enter a real email address or leave the field empty.'
    }
    if (-not ($Value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$')) {
        Throw-FriendlyError -Detail ("Email address '{0}' is invalid for {1}." -f $Value, $Key) -Code 2 -Summary 'Email value is invalid.' -Hint 'Use a standard email address shape.'
    }
    return $Value.Trim()
}

function Assert-ClagnosConfigureOptionalUrlValue {
    param([string]$Key,[string]$Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    if (Test-ClagnosConfigPlaceholderValue -Value $Value) {
        Throw-FriendlyError -Detail ("Value '{0}' is still a placeholder for {1}." -f $Value, $Key) -Code 2 -Summary 'URL value is invalid.' -Hint 'Enter a real http:// or https:// address, or leave the field empty.'
    }
    if (-not ($Value -match '^https?://')) {
        Throw-FriendlyError -Detail ("URL '{0}' is invalid for {1}." -f $Value, $Key) -Code 2 -Summary 'URL value is invalid.' -Hint 'Use an http:// or https:// address.'
    }
    return $Value.Trim()
}

function Assert-ClagnosConfigureSecretValue {
    param([string]$Key,[string]$Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        Throw-FriendlyError -Detail ("Secret value for {0} is empty." -f $Key) -Code 2 -Summary 'Secret value is invalid.' -Hint 'Enter a non-empty secret value.'
    }
    if (Test-ClagnosConfigPlaceholderValue -Value $Value) {
        Throw-FriendlyError -Detail ("Secret value for {0} is still a placeholder." -f $Key) -Code 2 -Summary 'Secret value is invalid.' -Hint 'Enter a real secret value.'
    }
    return $Value
}

function Assert-ClagnosConfigureTemplateValue {
    param([string]$Key,[string]$Value)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    [void](Assert-ClagnosResolvedTemplateValue -Value $Value -ConfigKey $Key -AllowedTokens @('SELECTED_VM_NAME','REGION_CODE','N'))
    return $Value.Trim()
}

function Assert-ClagnosConfigureDirectoryValue {
    param([string]$Key,[string]$Value,[hashtable]$State)
    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        Throw-FriendlyError -Detail ("Directory value for {0} is empty." -f $Key) -Code 2 -Summary 'Directory value is invalid.' -Hint 'Choose an existing directory.'
    }
    $resolvedPath = Resolve-ConfigPath -PathValue $Value -RootPath ([string]$State['RepoRoot'])
    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
        Throw-FriendlyError -Detail ("Directory '{0}' was not found for {1}." -f $Value, $Key) -Code 2 -Summary 'Directory value is invalid.' -Hint 'Choose an existing repo-relative or absolute directory.'
    }
    return $Value.Trim()
}

function Assert-ClagnosConfigureFieldValue {
    param(
        [string]$Key,
        [string]$Value,
        [hashtable]$State
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value }

    switch ([string]$Key) {
        'SELECTED_VM_OS' {
            if ([string]::IsNullOrWhiteSpace([string]$text)) {
                Throw-FriendlyError -Detail 'SELECTED_VM_OS is empty.' -Code 2 -Summary 'Selected VM OS is required.' -Hint 'Choose either windows or linux.'
            }

            $normalizedPlatform = $text.Trim().ToLowerInvariant()
            if ($normalizedPlatform -notin @('windows','linux')) {
                Throw-FriendlyError -Detail ("VM OS value '{0}' is invalid." -f $text) -Code 2 -Summary 'Selected VM OS is invalid.' -Hint 'Choose either windows or linux.'
            }

            return $normalizedPlatform
        }
        'SELECTED_VM_NAME' {
            if ([string]::IsNullOrWhiteSpace([string]$text)) {
                Throw-FriendlyError -Detail 'SELECTED_VM_NAME is empty.' -Code 2 -Summary 'Selected VM name is required.' -Hint 'Enter a valid VM name.'
            }
            if (-not (Test-ClagnosVmNameFormat -VmName $text)) {
                Throw-FriendlyError -Detail ("VM name '{0}' is invalid." -f $text) -Code 2 -Summary 'VM name value is invalid.' -Hint 'Use 3-16 characters, start with a letter, and keep only letters, numbers, or hyphen.'
            }
            return $text.Trim().ToLowerInvariant()
        }
        'SELECTED_AZURE_SUBSCRIPTION_ID' {
            if ([string]::IsNullOrWhiteSpace([string]$text)) { return '' }
            return [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $text -OptionSource 'configure editor')
        }
        'SELECTED_COMPANY_WEB_ADDRESS' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'SELECTED_COMPANY_EMAIL_ADDRESS' { return (Assert-ClagnosConfigureEmailValue -Key $Key -Value $text) }
        'SELECTED_EMPLOYEE_EMAIL_ADDRESS' { return (Assert-ClagnosConfigureEmailValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL' { return (Assert-ClagnosConfigureOptionalUrlValue -Key $Key -Value $text) }
        'VM_ADMIN_USER' { return (Assert-ClagnosConfigureRequiredTextValue -Key $Key -Value $text -Label 'Admin user name') }
        'VM_ADMIN_PASS' { return (Assert-ClagnosConfigureSecretValue -Key $Key -Value $text) }
        'VM_ASSISTANT_USER' { return (Assert-ClagnosConfigureRequiredTextValue -Key $Key -Value $text -Label 'Assistant user name') }
        'VM_ASSISTANT_PASS' { return (Assert-ClagnosConfigureSecretValue -Key $Key -Value $text) }
        'VM_SSH_PORT' { return (Assert-ClagnosConfigurePortValue -Key $Key -Value $text) }
        'VM_RDP_PORT' { return (Assert-ClagnosConfigurePortValue -Key $Key -Value $text) }
        'VM_PRICE_COUNT_HOURS' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'AZURE_COMMAND_TIMEOUT_SECONDS' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'SSH_CONNECT_TIMEOUT_SECONDS' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'SSH_TASK_TIMEOUT_SECONDS' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'WIN_VM_DISK_SIZE_GB' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'LIN_VM_DISK_SIZE_GB' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'SSH_MAX_RETRIES' { return (Assert-ClagnosConfigurePositiveIntegerValue -Key $Key -Value $text) }
        'PACKAGE_TRANSPORT' {
            $transport = ([string]$text).Trim().ToLowerInvariant()
            if ($transport -notin @('ssh','winrm')) {
                Throw-FriendlyError -Detail ("Unsupported package transport '{0}'." -f $text) -Code 2 -Summary 'Package transport is invalid.' -Hint 'Select ssh or winrm.'
            }
            return $transport
        }
        'RESOURCE_GROUP_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'VNET_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'SUBNET_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'NSG_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'NSG_RULE_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'PUBLIC_IP_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'NIC_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'VM_DISK_NAME_TEMPLATE' { return (Assert-ClagnosConfigureTemplateValue -Key $Key -Value $text) }
        'PYSSH_CLIENT_PATH' {
            if ([string]::IsNullOrWhiteSpace([string]$text)) {
                Throw-FriendlyError -Detail 'PYSSH client path is empty.' -Code 2 -Summary 'PYSSH client path is invalid.' -Hint 'Choose an existing PYSSH client path.'
            }
            $resolvedPath = Resolve-ConfigPath -PathValue $text -RootPath ([string]$State['RepoRoot'])
            if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
                Throw-FriendlyError -Detail ("PYSSH client path '{0}' was not found." -f $text) -Code 2 -Summary 'PYSSH client path is invalid.' -Hint 'Choose an existing repo-relative or absolute file path.'
            }
            return $text.Trim()
        }
        'WIN_VM_INIT_TASK_DIR' { return (Assert-ClagnosConfigureDirectoryValue -Key $Key -Value $text -State $State) }
        'WIN_VM_UPDATE_TASK_DIR' { return (Assert-ClagnosConfigureDirectoryValue -Key $Key -Value $text -State $State) }
        'LIN_VM_INIT_TASK_DIR' { return (Assert-ClagnosConfigureDirectoryValue -Key $Key -Value $text -State $State) }
        'LIN_VM_UPDATE_TASK_DIR' { return (Assert-ClagnosConfigureDirectoryValue -Key $Key -Value $text -State $State) }
        default {
            return $text.Trim()
        }
    }
}

function Invoke-ClagnosConfigureAzureValueVerification {
    param(
        [string]$Key,
        [string]$Value,
        [hashtable]$State
    )

    $azureState = [hashtable]$State['Azure']
    if (-not [bool]$azureState['Available']) {
        return $Value
    }

    switch ([string]$Key) {
        'SELECTED_AZURE_REGION' {
            Assert-LocationExists -Location $Value
            return $Value.Trim().ToLowerInvariant()
        }
        'WIN_VM_SIZE' {
            $location = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
            Assert-VmSkuAvailableViaRest -Location $location -VmSize $Value
            return $Value.Trim()
        }
        'LIN_VM_SIZE' {
            $location = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
            Assert-VmSkuAvailableViaRest -Location $location -VmSize $Value
            return $Value.Trim()
        }
        'WIN_VM_IMAGE' {
            $location = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
            Assert-VmImageAvailable -Location $location -ImageUrn $Value
            return $Value.Trim()
        }
        'LIN_VM_IMAGE' {
            $location = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
            Assert-VmImageAvailable -Location $location -ImageUrn $Value
            return $Value.Trim()
        }
        'SELECTED_RESOURCE_GROUP' {
            if ([string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
            Assert-ClagnosManagedResourceGroup -ResourceGroup $Value -OperationName 'configure'
            return $Value.Trim()
        }
        'SELECTED_AZURE_SUBSCRIPTION_ID' {
            return [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $Value -OptionSource 'configure picker')
        }
        default {
            return $Value
        }
    }
}

function Select-ClagnosConfigureListValue {
    param(
        [string]$Title,
        [object[]]$Rows,
        [string]$CurrentValue,
        [switch]$AllowBlank,
        [string]$EmptyStateSummary = '',
        [string]$EmptyStateHint = ''
    )

    $resolvedRows = @(
        ConvertTo-ObjectArrayCompat -InputObject $Rows |
            Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.Label) }
    )

    if (@($resolvedRows).Count -le 0) {
        if ($AllowBlank) {
            if (-not [string]::IsNullOrWhiteSpace([string]$EmptyStateSummary)) {
                Write-Host $EmptyStateSummary -ForegroundColor Yellow
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$EmptyStateHint)) {
                Write-Host $EmptyStateHint -ForegroundColor DarkGray
            }
            return ''
        }

        Throw-FriendlyError `
            -Detail ("No selectable values were available for '{0}'." -f [string]$Title) `
            -Code 2 `
            -Summary ("{0} picker cannot continue." -f [string]$Title) `
            -Hint 'Retry after Azure-backed values are available again.'
    }

    return (Select-ClagnosConfigureChoiceInteractive -Title $Title -Rows $resolvedRows -CurrentValue $CurrentValue -AllowEmptySelection:$AllowBlank)
}

function Assert-ClagnosConfigureRequiredTextValue {
    param(
        [string]$Key,
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        Throw-FriendlyError -Detail ("Value for {0} is empty." -f $Key) -Code 2 -Summary ("{0} is required." -f $Label) -Hint ("Enter a non-empty value for {0}." -f $Label.ToLowerInvariant())
    }
    if (Test-ClagnosConfigPlaceholderValue -Value $Value) {
        Throw-FriendlyError -Detail ("Value '{0}' is still a placeholder for {1}." -f $Value, $Key) -Code 2 -Summary ("{0} is invalid." -f $Label) -Hint ("Enter a real value for {0}." -f $Label.ToLowerInvariant())
    }

    return $Value.Trim()
}

function Edit-ClagnosConfigureTcpPortsInteractive {
    param(
        [string]$CurrentValue
    )

    $defaultPorts = @(Convert-ClagnosCliTextToTokens -Text ((Get-ClagnosDefaultTcpPortsCsv) -replace ',', ' '))
    $currentPorts = @(Convert-ClagnosCliTextToTokens -Text (([string]$CurrentValue) -replace ',', ' '))
    $allPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($port in @($defaultPorts + $currentPorts)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$port) -and $port -match '^\d+$') {
            [void]$allPorts.Add(([string]$port).Trim())
        }
    }

    $selectedPorts = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($port in @($currentPorts)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$port) -and $port -match '^\d+$') {
            [void]$selectedPorts.Add(([string]$port).Trim())
        }
    }

    while ($true) {
        Write-Host ''
        Write-Host 'TCP port picker' -ForegroundColor Cyan
        $orderedPorts = @($allPorts | Sort-Object { [int]$_ })
        for ($i = 0; $i -lt @($orderedPorts).Count; $i++) {
            $portText = [string]$orderedPorts[$i]
            $marker = if ($selectedPorts.Contains($portText)) { '[x]' } else { '[ ]' }
            Write-Host ("{0} {1}. {2}" -f $marker, ($i + 1), $portText)
        }
        Write-Host ("Current selection: {0}" -f ((@($selectedPorts | Sort-Object { [int]$_ }) -join ','))) -ForegroundColor DarkGray
        $raw = Read-Host "Enter number to toggle, 'a' to add a custom port, 'd' to finish, or press Enter to keep the current value"
        if ([string]::IsNullOrWhiteSpace([string]$raw)) {
            return $CurrentValue
        }
        if ([string]::Equals([string]$raw, 'd', [System.StringComparison]::OrdinalIgnoreCase)) {
            return (@($selectedPorts | Sort-Object { [int]$_ }) -join ',')
        }
        if ([string]::Equals([string]$raw, 'a', [System.StringComparison]::OrdinalIgnoreCase)) {
            $customPort = Read-Host 'Enter a custom TCP port'
            $normalizedPort = Assert-ClagnosConfigurePortValue -Key 'TCP_PORTS' -Value $customPort
            [void]$allPorts.Add($normalizedPort)
            [void]$selectedPorts.Add($normalizedPort)
            continue
        }
        if ($raw -match '^\d+$') {
            $index = [int]$raw
            if ($index -ge 1 -and $index -le @($orderedPorts).Count) {
                $portText = [string]$orderedPorts[$index - 1]
                if ($selectedPorts.Contains($portText)) {
                    [void]$selectedPorts.Remove($portText)
                }
                else {
                    [void]$selectedPorts.Add($portText)
                }
                continue
            }
        }
        Write-Host 'Invalid TCP port selection.' -ForegroundColor Yellow
    }
}

function Select-ClagnosConfigureImageInteractive {
    param(
        [string]$CurrentValue,
        [hashtable]$State
    )

    $location = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace([string]$location)) {
        Throw-FriendlyError -Detail 'SELECTED_AZURE_REGION is empty.' -Code 2 -Summary 'VM image picker cannot continue.' -Hint 'Set the Azure region first.'
    }

    $currentParts = @([string]$CurrentValue -split ':')
    $defaultPublisher = if (@($currentParts).Count -ge 1) { [string]$currentParts[0] } else { '' }
    $defaultOffer = if (@($currentParts).Count -ge 2) { [string]$currentParts[1] } else { '' }
    $defaultSku = if (@($currentParts).Count -ge 3) { [string]$currentParts[2] } else { '' }
    $defaultVersion = if (@($currentParts).Count -ge 4) { [string]$currentParts[3] } else { 'latest' }

    $publishers = Invoke-ClagnosWithBypassedAzCliSubscription -Action { az vm image list-publishers -l $location -o json --only-show-errors }
    $publisherRows = @(
        ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $publishers) |
            ForEach-Object { [pscustomobject]@{ Value = [string]$_.name; Label = [string]$_.name; Description = 'Publisher' } }
    )
    $publisher = Select-ClagnosConfigureChoiceInteractive -Title 'VM image publisher' -Rows $publisherRows -CurrentValue $defaultPublisher

    $offers = Invoke-ClagnosWithBypassedAzCliSubscription -Action { az vm image list-offers -l $location -p $publisher -o json --only-show-errors }
    $offerRows = @(
        ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $offers) |
            ForEach-Object { [pscustomobject]@{ Value = [string]$_.name; Label = [string]$_.name; Description = 'Offer' } }
    )
    $offer = Select-ClagnosConfigureChoiceInteractive -Title 'VM image offer' -Rows $offerRows -CurrentValue $defaultOffer

    $skus = Invoke-ClagnosWithBypassedAzCliSubscription -Action { az vm image list-skus -l $location -p $publisher -f $offer -o json --only-show-errors }
    $skuRows = @(
        ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $skus) |
            ForEach-Object { [pscustomobject]@{ Value = [string]$_.name; Label = [string]$_.name; Description = 'SKU' } }
    )
    $sku = Select-ClagnosConfigureChoiceInteractive -Title 'VM image SKU' -Rows $skuRows -CurrentValue $defaultSku

    $versionRows = @([pscustomobject]@{ Value = 'latest'; Label = 'latest'; Description = 'Latest image version.' })
    $versions = Invoke-ClagnosWithBypassedAzCliSubscription -Action { az vm image list -l $location -p $publisher -f $offer -s $sku --all --query "[].version" -o json --only-show-errors }
    $versionRows += @(
        ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $versions) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Descending |
            Select-Object -First 20 |
            ForEach-Object { [pscustomobject]@{ Value = [string]$_; Label = [string]$_; Description = 'Version' } }
    )
    $version = Select-ClagnosConfigureChoiceInteractive -Title 'VM image version' -Rows $versionRows -CurrentValue $defaultVersion

    return ("{0}:{1}:{2}:{3}" -f $publisher, $offer, $sku, $version)
}

function Edit-ClagnosConfigureField {
    param(
        [psobject]$Field,
        [hashtable]$State
    )

    $values = [hashtable]$State['Values']
    $currentValue = [string](Get-ConfigValue -Config $values -Key ([string]$Field.Key) -DefaultValue '')
    $displayValue = ConvertTo-ClagnosConfigureDisplayValue -Value $currentValue -Secret:([bool]$Field.Secret)

    Write-Host ''
    Write-Host ("{0}" -f [string]$Field.Label) -ForegroundColor Cyan
    Write-Host ("Current value: {0}" -f $displayValue) -ForegroundColor DarkGray

    if ([bool]$Field.AzureBacked -and -not [bool]$State['Azure']['Available']) {
        Write-Host ([string]$State['Azure']['Hint']) -ForegroundColor Yellow
        if (Test-ClagnosConfigureFieldIsCreateCritical -Key ([string]$Field.Key) -Values $values) {
            Write-Host 'This value must be verified before save. Run az login and revisit this field.' -ForegroundColor DarkGray
        }
        return $currentValue
    }

    switch ([string]$Field.EditorKind) {
        'subscription-picker' {
            $selectedSubscriptionId = [string](Select-ClagnosConfigureListValue `
                    -Title ([string]$Field.Label) `
                    -Rows (Get-ClagnosConfigureSubscriptionRows -State $State) `
                    -CurrentValue $currentValue `
                    -AllowBlank)
            if (-not [string]::IsNullOrWhiteSpace([string]$selectedSubscriptionId)) {
                $selectedRow = Find-ClagnosSubscriptionRowById -SubscriptionRows @($State['Azure']['SubscriptionRows']) -SubscriptionId $selectedSubscriptionId
                if ($null -ne $selectedRow) {
                    Set-ClagnosConfigureAzureSubscription -State ([hashtable]$State['Azure']) -SubscriptionRow $selectedRow
                }
            }
            return $selectedSubscriptionId
        }
        'region-picker' {
            return [string](Select-ClagnosConfigureListValue `
                    -Title ([string]$Field.Label) `
                    -Rows (Get-ClagnosConfigureRegionRows -State $State) `
                    -CurrentValue $currentValue)
        }
        'resource-group-picker' {
            return [string](Select-ClagnosConfigureListValue `
                    -Title ([string]$Field.Label) `
                    -Rows (Get-ClagnosConfigureManagedResourceGroupRows -State $State) `
                    -CurrentValue $currentValue `
                    -AllowBlank `
                    -EmptyStateSummary 'No managed resource groups were found in the current Azure subscription.' `
                    -EmptyStateHint 'SELECTED_RESOURCE_GROUP will stay empty. Run create when you want to provision a new managed resource group.')
        }
        'vm-size-picker' {
            $raw = Read-Host "Press Enter to keep the current value, or type 'p' to choose a different value"
            if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $currentValue }
            $location = [string](Get-ConfigValue -Config $values -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
            $priceHours = [int](Get-ConfigValue -Config $values -Key 'VM_PRICE_COUNT_HOURS' -DefaultValue '730')
            $selectedSku = Select-VmSkuInteractive -Location $location -DefaultVmSize $currentValue -PriceHours $priceHours
            if ([string]::Equals([string]$selectedSku, (Get-ClagnosSkuPickerRegionBackToken), [System.StringComparison]::Ordinal)) {
                return $currentValue
            }
            return [string]$selectedSku
        }
        'vm-image-picker' {
            $raw = Read-Host "Press Enter to keep the current value, or type 'p' to choose a different value"
            if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $currentValue }
            return (Select-ClagnosConfigureImageInteractive -CurrentValue $currentValue -State $State)
        }
        'vm-os-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'storage-sku-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'security-type-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'toggle-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'task-outcome-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'package-transport-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'task-dir-picker' { return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue) }
        'pyssh-path-picker' {
            $raw = Read-Host "Press Enter to keep the current value, 'p' to choose a listed value, or 'm' to enter a path manually"
            if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $currentValue }
            if ([string]::Equals([string]$raw, 'm', [System.StringComparison]::OrdinalIgnoreCase)) {
                return [string](Read-Host 'Enter a repo-relative or absolute PYSSH client path')
            }
            return (Select-ClagnosConfigureChoiceInteractive -Title ([string]$Field.Label) -Rows (Get-ClagnosConfigureChoiceRows -Key ([string]$Field.Key) -State $State) -CurrentValue $currentValue)
        }
        'tcp-ports-picker' { return (Edit-ClagnosConfigureTcpPortsInteractive -CurrentValue $currentValue) }
        'secret' {
            $raw = Read-Host "Press Enter to keep the current value, or type 'e' to enter a new secret"
            if ([string]::IsNullOrWhiteSpace([string]$raw)) { return $currentValue }
            $secureValue = Read-Host ("Enter {0}" -f [string]$Field.Label) -AsSecureString
            return (ConvertFrom-ClagnosSecureStringToPlainText -Value $secureValue)
        }
        default {
            $enteredValue = Read-Host ("Enter {0} (press Enter to keep the current value)" -f [string]$Field.Label)
            if ([string]::IsNullOrWhiteSpace([string]$enteredValue)) {
                return $currentValue
            }
            return [string]$enteredValue
        }
    }
}

function Invoke-ClagnosConfigureSectionEditor {
    param(
        [string]$SectionName,
        [hashtable]$State
    )

    $selectedPlatform = [string](Get-ConfigValue -Config ([hashtable]$State['Values']) -Key 'SELECTED_VM_OS' -DefaultValue 'windows')
    $fields = @(Get-ClagnosConfigureFieldSchema -SelectedPlatform $selectedPlatform | Where-Object { [string]$_.Section -eq [string]$SectionName })

    Write-Host ''
    Write-Host ("=== {0} ===" -f $SectionName) -ForegroundColor Green
    foreach ($field in @($fields)) {
        while ($true) {
            try {
                $candidateValue = Edit-ClagnosConfigureField -Field $field -State $State
                $validatedValue = Assert-ClagnosConfigureFieldValue -Key ([string]$field.Key) -Value ([string]$candidateValue) -State $State
                if ([bool]$field.AzureBacked) {
                    $validatedValue = Invoke-ClagnosConfigureAzureValueVerification -Key ([string]$field.Key) -Value ([string]$validatedValue) -State $State
                }
                $State['Values'][[string]$field.Key] = [string]$validatedValue
                if ([string]::Equals([string]$field.Key, 'SELECTED_AZURE_SUBSCRIPTION_ID', [System.StringComparison]::OrdinalIgnoreCase) -and [bool]$State['Azure']['Available']) {
                    $selectedRow = Find-ClagnosSubscriptionRowById -SubscriptionRows @($State['Azure']['SubscriptionRows']) -SubscriptionId ([string]$validatedValue)
                    if ($null -ne $selectedRow) {
                        Set-ClagnosConfigureAzureSubscription -State ([hashtable]$State['Azure']) -SubscriptionRow $selectedRow
                    }
                }
                break
            }
            catch {
                if (-not (Test-ClagnosConfigureExceptionIsRecoverable -Exception $_.Exception)) {
                    throw
                }

                Write-ClagnosConfigureValidationMessage -Field $field -Exception $_.Exception
                if (Test-ClagnosConfigureFieldIsCreateCritical -Key ([string]$field.Key) -Values ([hashtable]$State['Values'])) {
                    Write-Host 'This value is required before create-ready save can succeed. Choose or enter a valid value.' -ForegroundColor DarkGray
                    continue
                }

                if (Test-ClagnosConfigureFieldAllowsBlank -Key ([string]$field.Key) -Values ([hashtable]$State['Values'])) {
                    $recoveryChoice = Read-Host "Press Enter to retry this field, or type 'c' to clear it and continue"
                    if ([string]::Equals([string]$recoveryChoice, 'c', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $State['Values'][[string]$field.Key] = ''
                        break
                    }
                    continue
                }

                continue
            }
        }
    }
}

function Assert-ClagnosConfigureSaveReady {
    param(
        [hashtable]$State
    )

    $values = [hashtable]$State['Values']
    $selectedPlatform = Get-ClagnosConfigureSelectedPlatform -Values $values
    $fieldLookup = @{}
    foreach ($field in @(Get-ClagnosConfigureFieldSchema -SelectedPlatform $selectedPlatform)) {
        $fieldLookup[[string]$field.Key] = $field
    }

    $issues = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @(Get-ClagnosConfigureCreateCriticalKeys -Values $values)) {
        $field = $fieldLookup[[string]$key]
        $fieldLabel = if ($null -ne $field) { [string]$field.Label } else { [string]$key }
        $value = [string](Get-ConfigValue -Config $values -Key ([string]$key) -DefaultValue '')

        try {
            $validatedValue = Assert-ClagnosConfigureFieldValue -Key ([string]$key) -Value $value -State $State
            if ($null -ne $field -and [bool]$field.AzureBacked) {
                if (-not [bool]$State['Azure']['Available']) {
                    [void]$issues.Add(("{0}: run az login to verify this value before saving." -f $fieldLabel))
                    continue
                }

                [void](Invoke-ClagnosConfigureAzureValueVerification -Key ([string]$key) -Value ([string]$validatedValue) -State $State)
            }
        }
        catch {
            if (-not (Test-ClagnosConfigureExceptionIsRecoverable -Exception $_.Exception)) {
                throw
            }

            $summary = Get-ClagnosConfigureFriendlyErrorSummary -Exception $_.Exception
            [void]$issues.Add(("{0}: {1}" -f $fieldLabel, $summary))
        }
    }

    if ($issues.Count -gt 0) {
        Throw-FriendlyError `
            -Detail ((@($issues) -join '; ')) `
            -Code 2 `
            -Summary 'Configure cannot save until all create-critical values are valid.' `
            -Hint 'Revisit the relevant sections, fix the required values, and then choose Save again.'
    }
}

function Get-ClagnosConfigureEffectiveTcpPorts {
    param(
        [hashtable]$Values
    )

    $platform = [string](Get-ConfigValue -Config $Values -Key 'SELECTED_VM_OS' -DefaultValue 'windows')
    $sshPort = [string](Get-ConfigValue -Config $Values -Key 'VM_SSH_PORT' -DefaultValue '')
    $rdpPort = [string](Get-ConfigValue -Config $Values -Key 'VM_RDP_PORT' -DefaultValue '')
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($port in @(Convert-ClagnosCliTextToTokens -Text (([string](Get-ConfigValue -Config $Values -Key 'TCP_PORTS' -DefaultValue '')) -replace ',', ' '))) {
        if ($port -match '^\d+$') {
            [void]$set.Add(([string]$port).Trim())
        }
    }
    if ($sshPort -match '^\d+$') {
        [void]$set.Add($sshPort)
    }
    if ([string]::Equals([string]$platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase) -and $rdpPort -match '^\d+$') {
        [void]$set.Add($rdpPort)
    }

    return @($set | Sort-Object { [int]$_ })
}

function Get-ClagnosConfigurePreviewMap {
    param(
        [hashtable]$Values,
        [hashtable]$AzureState
    )

    $platform = [string](Get-ConfigValue -Config $Values -Key 'SELECTED_VM_OS' -DefaultValue 'windows')
    $platformMap = Resolve-ClagnosPlatformConfigMap -ConfigMap $Values -Platform $platform
    $vmName = [string](Get-ConfigValue -Config $platformMap -Key 'SELECTED_VM_NAME' -DefaultValue '')
    $derivedVmName = Get-ClagnosDerivedVmNameFromEmployeeEmailAddress -EmployeeEmailAddress ([string](Get-ConfigValue -Config $platformMap -Key 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' -DefaultValue ''))
    $effectiveVmName = if ([string]::IsNullOrWhiteSpace([string]$vmName)) { [string]$derivedVmName } else { [string]$vmName }
    $location = [string](Get-ConfigValue -Config $platformMap -Key 'SELECTED_AZURE_REGION' -DefaultValue '')
    $regionCode = ''
    try {
        if (-not [string]::IsNullOrWhiteSpace([string]$location)) {
            $regionCode = Get-ClagnosRegionCode -Location $location
        }
    }
    catch {
        $regionCode = ''
    }

    $preview = [ordered]@{
        SELECTED_VM_OS = [string]$platform
        SELECTED_VM_NAME = [string]$vmName
        DerivedVmNamePreview = [string]$derivedVmName
        EffectiveVmName = [string]$effectiveVmName
        SELECTED_RESOURCE_GROUP = [string](Get-ConfigValue -Config $platformMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
        SELECTED_AZURE_REGION = [string]$location
        VM_STORAGE_SKU = [string](Get-ConfigValue -Config $platformMap -Key 'VM_STORAGE_SKU' -DefaultValue '')
        VM_SECURITY_TYPE = [string](Get-ConfigValue -Config $platformMap -Key 'VM_SECURITY_TYPE' -DefaultValue '')
        EffectiveTcpPorts = (@(Get-ClagnosConfigureEffectiveTcpPorts -Values $platformMap) -join ',')
    }

    $platformVmImageKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
    $platformVmSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'
    $platformVmDiskKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'
    $preview[$platformVmImageKey] = [string](Get-ConfigValue -Config $platformMap -Key $platformVmImageKey -DefaultValue '')
    $preview[$platformVmSizeKey] = [string](Get-ConfigValue -Config $platformMap -Key $platformVmSizeKey -DefaultValue '')
    $preview[$platformVmDiskKey] = [string](Get-ConfigValue -Config $platformMap -Key $platformVmDiskKey -DefaultValue '')

    if ([bool]$AzureState['Available'] -and -not [string]::IsNullOrWhiteSpace([string]$effectiveVmName) -and -not [string]::IsNullOrWhiteSpace([string]$regionCode)) {
        $resourceAllocator = New-ClagnosManagedResourceIndexAllocator
        $preview['NextManagedResourceGroupName'] = Resolve-ClagnosResourceGroupNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'RESOURCE_GROUP_TEMPLATE' -DefaultValue '')) -VmName $effectiveVmName -RegionCode $regionCode -UseNextIndex
        $preview['NextVnetName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'VNET_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'net' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'vnet'
        $preview['NextSubnetName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'SUBNET_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'subnet' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'subnet'
        $preview['NextNsgName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'NSG_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'nsg' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'nsg'
        $preview['NextNsgRuleName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'NSG_RULE_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'nsg-rule' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'nsg-rule'
        $preview['NextPublicIpName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'PUBLIC_IP_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'ip' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'public-ip'
        $preview['NextNicName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'NIC_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'nic' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'nic'
        $preview['NextVmDiskName'] = Resolve-ClagnosNameFromTemplate -Template ([string](Get-ConfigValue -Config $platformMap -Key 'VM_DISK_NAME_TEMPLATE' -DefaultValue '')) -ResourceType 'disk' -VmName $effectiveVmName -RegionCode $regionCode -ResourceGroup '' -UseNextIndex -IndexAllocator $resourceAllocator -LogicalName 'vm-disk'
    }
    else {
        $preview['NextManagedResourceGroupName'] = 'Run az login and set a valid VM name + region to preview the next managed resource names.'
    }

    return $preview
}

function Write-ClagnosConfigurePreview {
    param(
        [hashtable]$Values,
        [hashtable]$AzureState
    )

    $previewMap = Get-ClagnosConfigurePreviewMap -Values $Values -AzureState $AzureState
    Write-Host ''
    Show-ClagnosKeyValueList -Title 'Next Create Preview:' -Values $previewMap
}

function Select-ClagnosConfigureReviewAction {
    while ($true) {
        Write-Host ''
        Write-Host 'Review actions:' -ForegroundColor Cyan
        Write-Host '1. Save'
        Write-Host '2. Revisit Basic'
        Write-Host '3. Revisit Platform & Compute'
        Write-Host '4. Revisit Identity & Secrets'
        Write-Host '5. Revisit Advanced'
        Write-Host '6. Cancel without saving'

        $raw = Read-Host 'Select review action'
        switch ([string]$raw) {
            '1' { return 'save' }
            '2' { return 'Basic' }
            '3' { return 'Platform & Compute' }
            '4' { return 'Identity & Secrets' }
            '5' { return 'Advanced' }
            '6' { return 'cancel' }
            default { Write-Host 'Invalid review action.' -ForegroundColor Yellow }
        }
    }
}

function Invoke-ClagnosConfigureInteractiveEditor {
    param(
        [string]$RepoRoot,
        [string]$EnvFilePath,
        [switch]$Perf
    )

    $defaultConfig = Read-DotEnvFile -Path (Join-Path $RepoRoot '.env.example')
    $currentConfig = Read-DotEnvFile -Path $EnvFilePath
    $state = @{
        RepoRoot = [string]$RepoRoot
        EnvFilePath = [string]$EnvFilePath
        Values = (Get-ClagnosConfigureMergedValues -CurrentConfig $currentConfig -DefaultConfig $defaultConfig)
        Azure = $null
    }
    $state['Azure'] = Initialize-ClagnosConfigureAzureState -Values ([hashtable]$state['Values'])

    Write-Host ''
    Write-Host 'Interactive .env editor' -ForegroundColor Green
    Write-Host 'Press Enter to keep a current value. Picker-backed fields open only when you ask to change them.' -ForegroundColor DarkGray

    foreach ($sectionName in @(Get-ClagnosConfigureSectionNames)) {
        Invoke-ClagnosConfigureSectionEditor -SectionName $sectionName -State $state
    }

    while ($true) {
        Write-ClagnosConfigurePreview -Values ([hashtable]$state['Values']) -AzureState ([hashtable]$state['Azure'])
        $action = Select-ClagnosConfigureReviewAction
        if ([string]::Equals([string]$action, 'save', [System.StringComparison]::OrdinalIgnoreCase)) {
            try {
                Assert-ClagnosConfigureSaveReady -State $state
                Save-ClagnosSupportedDotEnvValues -Path $EnvFilePath -ValueMap ([hashtable]$state['Values']) -TemplatePath (Join-Path $RepoRoot '.env.example')
                Write-Host ''
                Write-Host (".env was saved successfully to '{0}'." -f $EnvFilePath) -ForegroundColor Green
                return
            }
            catch {
                if (-not (Test-ClagnosConfigureExceptionIsRecoverable -Exception $_.Exception)) {
                    throw
                }

                Write-Host ''
                Write-Host (Get-ClagnosConfigureFriendlyErrorSummary -Exception $_.Exception) -ForegroundColor Yellow
                $hint = Get-ClagnosConfigureFriendlyErrorHint -Exception $_.Exception
                if (-not [string]::IsNullOrWhiteSpace([string]$hint)) {
                    Write-Host $hint -ForegroundColor DarkGray
                }
                continue
            }
        }
        if ([string]::Equals([string]$action, 'cancel', [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host ''
            Write-Host 'Configure was canceled. No .env changes were saved.' -ForegroundColor Yellow
            return
        }

        Invoke-ClagnosConfigureSectionEditor -SectionName ([string]$action) -State $state
    }
}
