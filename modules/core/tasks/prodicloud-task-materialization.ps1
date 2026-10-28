# Shared runtime task materialization helpers.

# Handles Get-ProdicloudTaskTokenReplacements.
function Get-ProdicloudTaskTokenReplacements {
    param(
        [hashtable]$Context
    )

    $tcpPorts = @(@($Context.TcpPorts) | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^\d+$' })
    $tcpPortsBash = $tcpPorts -join ' '
    $tcpRegex = (($tcpPorts | ForEach-Object { [regex]::Escape([string]$_) }) -join '|')
    $tcpPortsPsArray = $tcpPorts -join ','
    $hostStartupProfileJsonBase64 = ''
    if ($Context -and $Context.ContainsKey('HostStartupProfileJsonBase64')) {
        $hostStartupProfileJsonBase64 = [string]$Context.HostStartupProfileJsonBase64
    }
    if ([string]::IsNullOrWhiteSpace([string]$hostStartupProfileJsonBase64)) {
        $hostStartupProfileJsonBase64 = Get-ProdicloudHostStartupMirrorProfileJsonBase64
    }
    $hostAutostartDiscoveryJsonBase64 = ''
    if ($Context -and $Context.ContainsKey('HostAutostartDiscoveryJsonBase64')) {
        $hostAutostartDiscoveryJsonBase64 = [string]$Context.HostAutostartDiscoveryJsonBase64
    }
    if ([string]::IsNullOrWhiteSpace([string]$hostAutostartDiscoveryJsonBase64)) {
        $hostAutostartDiscoveryJsonBase64 = Get-ProdicloudHostAutostartDiscoveryJsonBase64
    }

    return @{
        VM_ADMIN_USER = [string]$Context.VmUser
        VM_ADMIN_PASS = [string]$Context.VmPass
        ASSISTANT_USER = [string]$Context.VmAssistantUser
        ASSISTANT_PASS = [string]$Context.VmAssistantPass
        RESET_MANAGED_USER_PASSWORDS = [string]([bool]$script:ProdicloudResetManagedUserPasswords)
        SSH_PORT = [string]$Context.SshPort
        RDP_PORT = [string]$Context.RdpPort
        TCP_PORTS_BASH = [string]$tcpPortsBash
        TCP_PORTS_REGEX = [string]$tcpRegex
        TCP_PORTS_PS_ARRAY = [string]$tcpPortsPsArray
        SELECTED_RESOURCE_GROUP = [string]$Context.ResourceGroup
        SELECTED_VM_NAME = [string]$Context.VmName
        SELECTED_COMPANY_NAME = [string]$Context.CompanyName
        SELECTED_COMPANY_WEB_ADDRESS = [string]$Context.CompanyWebAddress
        SELECTED_COMPANY_EMAIL_ADDRESS = [string]$Context.CompanyEmailAddress
        SELECTED_EMPLOYEE_EMAIL_ADDRESS = [string]$Context.EmployeeEmailAddress
        SELECTED_EMPLOYEE_FULL_NAME = [string]$Context.EmployeeFullName
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL = [string]$Context.ShortcutSocialBusinessLinkedInUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL = [string]$Context.ShortcutSocialBusinessYouTubeUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL = [string]$Context.ShortcutSocialBusinessGitHubUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL = [string]$Context.ShortcutSocialBusinessTikTokUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL = [string]$Context.ShortcutSocialBusinessInstagramUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL = [string]$Context.ShortcutSocialBusinessFacebookUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL = [string]$Context.ShortcutSocialBusinessXUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL = [string]$Context.ShortcutSocialBusinessSnapchatUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL = [string]$Context.ShortcutSocialBusinessNextSosyalUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL = [string]$Context.ShortcutSocialPersonalLinkedInUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL = [string]$Context.ShortcutSocialPersonalYouTubeUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL = [string]$Context.ShortcutSocialPersonalGitHubUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL = [string]$Context.ShortcutSocialPersonalTikTokUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL = [string]$Context.ShortcutSocialPersonalInstagramUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL = [string]$Context.ShortcutSocialPersonalFacebookUrl
        WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL = [string]$Context.ShortcutSocialPersonalXUrl
        WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL = [string]$Context.ShortcutWebBusinessHomeUrl
        WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL = [string]$Context.ShortcutWebBusinessBlogUrl
        SELECTED_AZURE_REGION = [string]$Context.AzLocation
        VM_SIZE = [string]$Context.VmSize
        VM_IMAGE = [string]$Context.VmImage
        VM_DISK_NAME = [string]$Context.VmDiskName
        VM_DISK_SIZE = [string]$Context.VmDiskSize
        VM_STORAGE_SKU = [string]$Context.VmStorageSku
        HOST_STARTUP_PROFILE_JSON_B64 = [string]$hostStartupProfileJsonBase64
        HOST_AUTOSTART_DISCOVERY_JSON_B64 = [string]$hostAutostartDiscoveryJsonBase64
    }
}

function Get-ProdicloudTaskBlockTokenOverrides {
    param(
        [psobject]$TaskBlock,
        [hashtable]$Context
    )

    $overrides = @{}
    if ($null -eq $TaskBlock) {
        return $overrides
    }

    if (Test-ProdicloudTaskStartupProfileEnabled -TaskBlock $TaskBlock) {
        $startupProfileJsonBase64 = Get-ProdicloudTaskStartupProfileJsonBase64 -TaskBlock $TaskBlock
        if (-not [string]::IsNullOrWhiteSpace([string]$startupProfileJsonBase64)) {
            $overrides['HOST_STARTUP_PROFILE_JSON_B64'] = [string]$startupProfileJsonBase64
        }
    }

    return $overrides
}

# Handles Resolve-ProdicloudRuntimeTaskBlocks.
function Resolve-ProdicloudRuntimeTaskBlocks {
    param(
        [object[]]$TemplateTaskBlocks,
        [hashtable]$Context
    )

    if (-not $TemplateTaskBlocks -or @($TemplateTaskBlocks).Count -eq 0) {
        throw 'Task template block list is empty.'
    }

    $replacements = Get-ProdicloudTaskTokenReplacements -Context $Context
    return @(Apply-ProdicloudTaskBlockReplacements -TaskBlocks $TemplateTaskBlocks -Replacements $replacements -Context $Context)
}



# Handles Get-ProdicloudTaskTimeoutSeconds.
function Get-ProdicloudTaskTimeoutSeconds {
    param(
        [psobject]$TaskBlock,
        [int]$DefaultTimeoutSeconds = 180
    )

    $taskTimeout = $DefaultTimeoutSeconds
    if ($null -ne $TaskBlock -and $TaskBlock.PSObject.Properties.Match('TimeoutSeconds').Count -gt 0) {
        $taskTimeout = [int](Convert-ProdicloudTaskCatalogTimeout -Value $TaskBlock.TimeoutSeconds -DefaultValue $DefaultTimeoutSeconds)
    }
    else {
        $taskTimeout = [int](Convert-ProdicloudTaskCatalogTimeout -Value $DefaultTimeoutSeconds -DefaultValue 180)
    }

    return [int]$taskTimeout
}
