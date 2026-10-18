# Dotenv read/write helpers.

function Get-ClagnosGlobalEnvKeys {
    return @(
        'ACTIVE_VM_NAME',
        'SELECTED_AZURE_SUBSCRIPTION_ID',
        'TOP_STATUS_LINES',
        'DEFAULT_VM_OS',
        'DEFAULT_AZURE_REGION',
        'SELECTED_COMPANY_NAME',
        'SELECTED_COMPANY_WEB_ADDRESS',
        'SELECTED_COMPANY_EMAIL_ADDRESS',
        'SELECTED_EMPLOYEE_EMAIL_ADDRESS',
        'SELECTED_EMPLOYEE_FULL_NAME',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL',
        'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL',
        'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL',
        'RESOURCE_GROUP_TEMPLATE',
        'VNET_NAME_TEMPLATE',
        'SUBNET_NAME_TEMPLATE',
        'NSG_NAME_TEMPLATE',
        'NSG_RULE_NAME_TEMPLATE',
        'PUBLIC_IP_NAME_TEMPLATE',
        'NIC_NAME_TEMPLATE',
        'VM_DISK_NAME_TEMPLATE',
        'DEFAULT_VM_STORAGE_SKU',
        'DEFAULT_VM_SECURITY_TYPE',
        'DEFAULT_VM_ENABLE_HIBERNATION',
        'DEFAULT_VM_ENABLE_NESTED_VIRTUALIZATION',
        'DEFAULT_VM_ENABLE_SECURE_BOOT',
        'DEFAULT_VM_ENABLE_VTPM',
        'DEFAULT_VM_ADMIN_USER',
        'DEFAULT_VM_ASSISTANT_USER',
        'DEFAULT_VM_SSH_PORT',
        'DEFAULT_VM_RDP_PORT',
        'DEFAULT_TCP_PORTS',
        'DEFAULT_PACKAGE_TRANSPORT',
        'DEFAULT_WIN_VM_IMAGE',
        'DEFAULT_WIN_VM_SIZE',
        'DEFAULT_WIN_VM_DISK_SIZE_GB',
        'DEFAULT_LIN_VM_IMAGE',
        'DEFAULT_LIN_VM_SIZE',
        'DEFAULT_LIN_VM_DISK_SIZE_GB',
        'VM_PRICE_COUNT_HOURS',
        'AZURE_COMMAND_TIMEOUT_SECONDS',
        'SSH_CONNECT_TIMEOUT_SECONDS',
        'SSH_TASK_TIMEOUT_SECONDS',
        'WIN_VM_INIT_TASK_DIR',
        'WIN_VM_UPDATE_TASK_DIR',
        'LIN_VM_INIT_TASK_DIR',
        'LIN_VM_UPDATE_TASK_DIR',
        'VM_TASK_OUTCOME_MODE',
        'SSH_MAX_RETRIES',
        'PYSSH_CLIENT_PATH'
    )
}

function Get-ClagnosVmScopedEnvKeys {
    return @(
        'SELECTED_VM_NAME',
        'SELECTED_RESOURCE_GROUP',
        'SELECTED_VM_OS',
        'SELECTED_AZURE_REGION',
        'VNET_NAME',
        'SUBNET_NAME',
        'NSG_NAME',
        'NSG_RULE_NAME',
        'PUBLIC_IP_NAME',
        'NIC_NAME',
        'VM_DISK_NAME',
        'VM_STORAGE_SKU',
        'VM_SECURITY_TYPE',
        'VM_ENABLE_HIBERNATION',
        'VM_ENABLE_NESTED_VIRTUALIZATION',
        'VM_ENABLE_SECURE_BOOT',
        'VM_ENABLE_VTPM',
        'VM_ADMIN_USER',
        'VM_ADMIN_PASS',
        'VM_ASSISTANT_USER',
        'VM_ASSISTANT_PASS',
        'VM_SSH_PORT',
        'VM_RDP_PORT',
        'TCP_PORTS',
        'PACKAGE_TRANSPORT',
        'WIN_VM_IMAGE',
        'WIN_VM_SIZE',
        'WIN_VM_DISK_SIZE_GB',
        'LIN_VM_IMAGE',
        'LIN_VM_SIZE',
        'LIN_VM_DISK_SIZE_GB'
    )
}

function Get-ClagnosSupportedDotEnvKeys {
    return @(Get-ClagnosGlobalEnvKeys)
}

function Get-ClagnosSupportedVmEnvKeys {
    return @(Get-ClagnosVmScopedEnvKeys)
}

function Get-ClagnosAllSupportedEnvKeys {
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($key in @(Get-ClagnosGlobalEnvKeys) + @(Get-ClagnosVmScopedEnvKeys)) {
        if (-not $keys.Contains([string]$key)) { $keys.Add([string]$key) | Out-Null }
    }
    return @($keys.ToArray())
}

function Get-ClagnosGlobalEnvPath {
    return (Join-Path (Get-ClagnosRepoRoot) 'clagnos.env')
}

function Get-ClagnosVmEnvPath {
    param([string]$VmName,[string]$RepoRoot = '')

    $name = if ($null -eq $VmName) { '' } else { [string]$VmName.Trim() }
    if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,63}$') {
        throw 'A safe Azure VM name is required to resolve its environment file.'
    }
    $root = if ([string]::IsNullOrWhiteSpace([string]$RepoRoot)) { Get-ClagnosRepoRoot } else { [string]$RepoRoot }
    return (Join-Path $root ($name + '.env'))
}

function Get-ClagnosVmNameForEnvironment {
    param([hashtable]$GlobalConfigMap)

    if ($script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME') -and
        -not [string]::IsNullOrWhiteSpace([string]$script:ConfigOverrides['SELECTED_VM_NAME'])) {
        return [string]$script:ConfigOverrides['SELECTED_VM_NAME']
    }
    if ([string]::Equals([string]$script:ActiveCommand,'create',[System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }
    if ($null -ne $GlobalConfigMap -and -not [string]::IsNullOrWhiteSpace([string]$GlobalConfigMap['ACTIVE_VM_NAME'])) {
        return [string]$GlobalConfigMap['ACTIVE_VM_NAME']
    }
    return ''
}

function Merge-ClagnosVmEnvironmentConfig {
    param(
        [hashtable]$GlobalConfigMap,
        [string]$VmName,
        [string]$VmEnvRoot = '',
        [switch]$RequireProfile,
        [switch]$IgnoreActiveSelection
    )

    $effective = @{}
    foreach ($key in @($GlobalConfigMap.Keys)) { $effective[[string]$key] = [string]$GlobalConfigMap[$key] }
    $defaults = @{
        'DEFAULT_VM_OS' = 'SELECTED_VM_OS'
        'DEFAULT_AZURE_REGION' = 'SELECTED_AZURE_REGION'
        'DEFAULT_VM_STORAGE_SKU' = 'VM_STORAGE_SKU'
        'DEFAULT_VM_SECURITY_TYPE' = 'VM_SECURITY_TYPE'
        'DEFAULT_VM_ENABLE_HIBERNATION' = 'VM_ENABLE_HIBERNATION'
        'DEFAULT_VM_ENABLE_NESTED_VIRTUALIZATION' = 'VM_ENABLE_NESTED_VIRTUALIZATION'
        'DEFAULT_VM_ENABLE_SECURE_BOOT' = 'VM_ENABLE_SECURE_BOOT'
        'DEFAULT_VM_ENABLE_VTPM' = 'VM_ENABLE_VTPM'
        'DEFAULT_VM_ADMIN_USER' = 'VM_ADMIN_USER'
        'DEFAULT_VM_ASSISTANT_USER' = 'VM_ASSISTANT_USER'
        'DEFAULT_VM_SSH_PORT' = 'VM_SSH_PORT'
        'DEFAULT_VM_RDP_PORT' = 'VM_RDP_PORT'
        'DEFAULT_TCP_PORTS' = 'TCP_PORTS'
        'DEFAULT_PACKAGE_TRANSPORT' = 'PACKAGE_TRANSPORT'
        'DEFAULT_WIN_VM_IMAGE' = 'WIN_VM_IMAGE'
        'DEFAULT_WIN_VM_SIZE' = 'WIN_VM_SIZE'
        'DEFAULT_WIN_VM_DISK_SIZE_GB' = 'WIN_VM_DISK_SIZE_GB'
        'DEFAULT_LIN_VM_IMAGE' = 'LIN_VM_IMAGE'
        'DEFAULT_LIN_VM_SIZE' = 'LIN_VM_SIZE'
        'DEFAULT_LIN_VM_DISK_SIZE_GB' = 'LIN_VM_DISK_SIZE_GB'
    }
    foreach ($defaultKey in @($defaults.Keys)) {
        $runtimeKey = [string]$defaults[$defaultKey]
        if (-not $effective.ContainsKey($runtimeKey) -or [string]::IsNullOrWhiteSpace([string]$effective[$runtimeKey])) {
            if ($GlobalConfigMap.ContainsKey($defaultKey)) { $effective[$runtimeKey] = [string]$GlobalConfigMap[$defaultKey] }
        }
    }

    $resolvedVmName = if (-not [string]::IsNullOrWhiteSpace([string]$VmName)) { [string]$VmName } elseif ($IgnoreActiveSelection) { '' } else { Get-ClagnosVmNameForEnvironment -GlobalConfigMap $GlobalConfigMap }
    if ([string]::IsNullOrWhiteSpace([string]$resolvedVmName)) { return $effective }
    $profilePath = Get-ClagnosVmEnvPath -VmName $resolvedVmName -RepoRoot $VmEnvRoot
    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        if ($RequireProfile) { throw ("VC environment file is required for '{0}': {1}" -f $resolvedVmName,$profilePath) }
        $effective['SELECTED_VM_NAME'] = [string]$resolvedVmName
        return $effective
    }

    $profile = Read-DotEnvFile -Path $profilePath -GlobalOnly
    if (-not $profile.ContainsKey('SELECTED_VM_NAME') -or
        -not [string]::Equals([string]$profile['SELECTED_VM_NAME'],[string]$resolvedVmName,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("VC environment identity does not match its file name: {0}" -f $profilePath)
    }
    foreach ($key in @(Get-ClagnosVmScopedEnvKeys)) {
        if ($profile.ContainsKey([string]$key) -and -not [string]::IsNullOrWhiteSpace([string]$profile[[string]$key])) {
            $effective[[string]$key] = [string]$profile[[string]$key]
        }
    }
    $effective['SELECTED_VM_NAME'] = [string]$resolvedVmName
    return $effective
}

function Get-ClagnosEnvironmentFileScope {
    param([string]$Path)

    $leaf = [System.IO.Path]::GetFileName([string]$Path)
    if ([string]::Equals($leaf,'clagnos.env',[System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($leaf,'clagnos.env.example',[System.StringComparison]::OrdinalIgnoreCase)) { return 'global' }
    if ([string]::Equals($leaf,'vc.env.example',[System.StringComparison]::OrdinalIgnoreCase) -or
        $leaf -match '^[A-Za-z0-9][A-Za-z0-9-]{0,63}\.env$') { return 'vm' }
    return 'unsupported'
}

function Resolve-ClagnosSupportedDotEnvConfig {
    param(
        [hashtable]$ConfigMap
    )

    $resolved = @{}
    $supportedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @(Get-ClagnosAllSupportedEnvKeys)) {
        [void]$supportedKeys.Add([string]$key)
    }

    if ($ConfigMap) {
        foreach ($key in @($ConfigMap.Keys)) {
            $normalizedKey = [string]$key
            if ($supportedKeys.Contains($normalizedKey)) {
                $resolved[$normalizedKey] = [string]$ConfigMap[$key]
            }
        }
    }

    return $resolved
}

# Handles Read-DotEnvFile.
function Read-DotEnvFile {
    param(
        [string]$Path,
        [switch]$GlobalOnly
    )

    $config = @{}
    if (-not (Test-Path $Path)) {
        Write-Warning "Environment file was not found at '$Path'. Built-in defaults will be used."
        return $config
    }

    $scope = Get-ClagnosEnvironmentFileScope -Path $Path
    if ($scope -eq 'unsupported') { throw "Unsupported environment file path. Use clagnos.env or a <vm-name>.env profile." }
    $allowedKeys = if ($scope -eq 'global') { @(Get-ClagnosGlobalEnvKeys) } else { @(Get-ClagnosVmScopedEnvKeys) }
    $allowedLookup = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($allowedKeys)) { [void]$allowedLookup.Add([string]$key) }

    foreach ($rawLine in Get-Content -Path $Path) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        $match = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$')
        if (-not $match.Success) {
            Write-Warning "Skipping invalid environment line: $rawLine"
            continue
        }

        $key = $match.Groups[1].Value
        $value = $match.Groups[2].Value.Trim()
        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        if ($allowedLookup.Contains([string]$key)) { $config[$key] = $value }
    }

    $config = Resolve-ClagnosSupportedDotEnvConfig -ConfigMap $config
    if ($scope -eq 'global' -and -not $GlobalOnly -and [string]::Equals([System.IO.Path]::GetFileName([string]$Path),'clagnos.env',[System.StringComparison]::OrdinalIgnoreCase)) {
        return (Merge-ClagnosVmEnvironmentConfig -GlobalConfigMap $config -VmEnvRoot (Split-Path -Path $Path -Parent))
    }
    return $config
}

# Handles Get-ConfigValue.
function Get-ConfigValue {
    param(
        [hashtable]$Config,
        [string]$Key,
        [string]$DefaultValue
    )

    if ($script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey($Key)) {
        $overrideValue = [string]$script:ConfigOverrides[$Key]
        if (-not [string]::IsNullOrWhiteSpace($overrideValue)) {
            return $overrideValue
        }
    }
    elseif ($script:ConfigOverrides) {
        foreach ($overrideKey in @($script:ConfigOverrides.Keys)) {
            if (-not [string]::Equals([string]$overrideKey, [string]$Key, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $overrideValue = [string]$script:ConfigOverrides[$overrideKey]
            if (-not [string]::IsNullOrWhiteSpace($overrideValue)) {
                return $overrideValue
            }
        }
    }

    if ($Config -and $Config.ContainsKey($Key)) {
        $configValue = [string]$Config[$Key]
        if (-not [string]::IsNullOrWhiteSpace($configValue)) {
            return $configValue
        }
    }
    elseif ($Config) {
        foreach ($configKey in @($Config.Keys)) {
            if (-not [string]::Equals([string]$configKey, [string]$Key, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $configValue = [string]$Config[$configKey]
            if (-not [string]::IsNullOrWhiteSpace($configValue)) {
                return $configValue
            }
        }
    }

    return $DefaultValue
}

# Writes one key directly to the named environment file.
function Set-ClagnosEnvFileValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Set-ClagnosEnvFileValue requires a valid file path."
    }
    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw "Set-ClagnosEnvFileValue requires a non-empty key."
    }
    if ($null -eq $Value) {
        $Value = ""
    }

    $lines = @()
    if (Test-Path -LiteralPath $Path) {
        $lines = @((Get-Content -Path $Path -ErrorAction Stop))
    }

    $pattern = "^\s*" + [regex]::Escape($Key) + "\s*="
    $updated = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Key=$Value"
            $updated = $true
            break
        }
    }

    if (-not $updated) {
        if ($lines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($lines[$lines.Count - 1])) {
            $lines += ""
        }
        $lines += "$Key=$Value"
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-TextFileNormalized `
        -Path $Path `
        -Content ($lines -join "`n") `
        -Encoding "utf8NoBom" `
        -LineEnding "crlf" `
        -EnsureTrailingNewline
}

function Set-DotEnvValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value,
        [string]$VmName = ''
    )

    $scope = Get-ClagnosEnvironmentFileScope -Path $Path
    if ($scope -eq 'unsupported') { throw "Unsupported environment file path. Use clagnos.env or a <vm-name>.env profile." }
    $normalizedKey = [string]$Key
    if ($scope -eq 'global') {
        if ([string]::Equals($normalizedKey,'SELECTED_VM_NAME',[System.StringComparison]::OrdinalIgnoreCase)) {
            $targetVm = if (-not [string]::IsNullOrWhiteSpace([string]$Value)) { [string]$Value } else { [string]$VmName }
            if ([string]::IsNullOrWhiteSpace([string]$targetVm)) { throw 'ACTIVE_VM_NAME requires a VC name.' }
            $targetProfilePath = Get-ClagnosVmEnvPath -VmName $targetVm -RepoRoot (Split-Path -Path $Path -Parent)
            if (Test-Path -LiteralPath $targetProfilePath -PathType Leaf) {
                $targetProfile = Read-DotEnvFile -Path $targetProfilePath -GlobalOnly
                if ($targetProfile.ContainsKey('SELECTED_VM_NAME') -and -not [string]::Equals([string]$targetProfile['SELECTED_VM_NAME'],$targetVm,[System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ("VC environment identity does not match its file name: {0}" -f $targetProfilePath)
                }
            }
            Set-ClagnosEnvFileValue -Path $targetProfilePath -Key 'SELECTED_VM_NAME' -Value $targetVm
            Set-ClagnosEnvFileValue -Path $Path -Key 'ACTIVE_VM_NAME' -Value $targetVm
            return
        }
        if ([string]::Equals($normalizedKey,'ACTIVE_VM_NAME',[System.StringComparison]::OrdinalIgnoreCase)) {
            Set-ClagnosEnvFileValue -Path $Path -Key $normalizedKey -Value $Value
            return
        }
        if (@(Get-ClagnosVmScopedEnvKeys) -contains $normalizedKey) {
            $targetVm = [string]$VmName
            if ([string]::IsNullOrWhiteSpace([string]$targetVm) -and $script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME')) {
                $targetVm = [string]$script:ConfigOverrides['SELECTED_VM_NAME']
            }
            if ([string]::IsNullOrWhiteSpace([string]$targetVm)) {
                $globalMap = Read-DotEnvFile -Path $Path -GlobalOnly
                $targetVm = [string]$globalMap['ACTIVE_VM_NAME']
            }
            if ([string]::IsNullOrWhiteSpace([string]$targetVm)) { throw ("VM-scoped environment value '{0}' requires a selected VC." -f $normalizedKey) }
            $targetProfilePath = Get-ClagnosVmEnvPath -VmName $targetVm -RepoRoot (Split-Path -Path $Path -Parent)
            if (Test-Path -LiteralPath $targetProfilePath -PathType Leaf) {
                $targetProfile = Read-DotEnvFile -Path $targetProfilePath -GlobalOnly
                if ($targetProfile.ContainsKey('SELECTED_VM_NAME') -and -not [string]::Equals([string]$targetProfile['SELECTED_VM_NAME'],$targetVm,[System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ("VC environment identity does not match its file name: {0}" -f $targetProfilePath)
                }
            }
            Set-ClagnosEnvFileValue -Path $targetProfilePath -Key 'SELECTED_VM_NAME' -Value $targetVm
            Set-ClagnosEnvFileValue -Path $targetProfilePath -Key $normalizedKey -Value $Value
            return
        }
        if (-not (@(Get-ClagnosGlobalEnvKeys) -contains $normalizedKey)) { throw ("Environment key '{0}' is not valid in clagnos.env." -f $normalizedKey) }
        Set-ClagnosEnvFileValue -Path $Path -Key $normalizedKey -Value $Value
        return
    }

    if ($scope -eq 'vm' -and -not (@(Get-ClagnosVmScopedEnvKeys) -contains $normalizedKey)) {
        throw ("Environment key '{0}' is not VC-scoped and cannot be written to '{1}'." -f $normalizedKey,$Path)
    }
    Set-ClagnosEnvFileValue -Path $Path -Key $normalizedKey -Value $Value
}

function Remove-DotEnvKeys {
    param(
        [string]$Path,
        [string[]]$Keys
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $keysToRemove = @(
        @($Keys) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
    if (@($keysToRemove).Count -eq 0) {
        return
    }

    $lines = @((Get-Content -Path $Path -ErrorAction Stop))
    $filtered = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($lines)) {
        $removeLine = $false
        foreach ($key in @($keysToRemove)) {
            $pattern = "^\s*" + [regex]::Escape($key) + "\s*="
            if ([string]$line -match $pattern) {
                $removeLine = $true
                break
            }
        }

        if (-not $removeLine) {
            [void]$filtered.Add([string]$line)
        }
    }

    Write-TextFileNormalized `
        -Path $Path `
        -Content (@($filtered) -join "`n") `
        -Encoding "utf8NoBom" `
        -LineEnding "crlf" `
        -EnsureTrailingNewline
}

function Remove-ClagnosUnsupportedDotEnvKeys {
    param(
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $scope = Get-ClagnosEnvironmentFileScope -Path $Path
    if ($scope -eq 'unsupported') { throw "Unsupported environment file path. Use clagnos.env or a <vm-name>.env profile." }
    $allowedKeys = if ($scope -eq 'vm') { @(Get-ClagnosVmScopedEnvKeys) } else { @(Get-ClagnosGlobalEnvKeys) }
    $supportedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($allowedKeys)) {
        [void]$supportedKeys.Add([string]$key)
    }

    $lines = @((Get-Content -Path $Path -ErrorAction Stop))
    $filtered = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($lines)) {
        $rawLine = [string]$line
        $trimmedLine = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace([string]$trimmedLine) -or $trimmedLine.StartsWith('#')) {
            [void]$filtered.Add($rawLine)
            continue
        }

        $match = [regex]::Match($rawLine, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=')
        if (-not $match.Success) {
            [void]$filtered.Add($rawLine)
            continue
        }

        $key = [string]$match.Groups[1].Value
        if ($supportedKeys.Contains($key)) {
            [void]$filtered.Add($rawLine)
        }
    }

    Write-TextFileNormalized `
        -Path $Path `
        -Content (@($filtered) -join "`n") `
        -Encoding "utf8NoBom" `
        -LineEnding "crlf" `
        -EnsureTrailingNewline
}

function Save-ClagnosSupportedDotEnvValues {
    param(
        [string]$Path,
        [hashtable]$ValueMap,
        [string]$TemplatePath = ''
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path)) {
        throw 'Save-ClagnosSupportedDotEnvValues requires a destination path.'
    }

    $scope = Get-ClagnosEnvironmentFileScope -Path $Path
    if ($scope -eq 'unsupported') { throw "Unsupported environment file path. Use clagnos.env or a <vm-name>.env profile." }
    $supportedKeys = if ($scope -eq 'vm') { @(Get-ClagnosVmScopedEnvKeys) } else { @(Get-ClagnosGlobalEnvKeys) }
    $supportedLookup = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @($supportedKeys)) {
        [void]$supportedLookup.Add([string]$key)
    }

    $normalizedValues = @{}
    foreach ($key in @($supportedKeys)) {
        $normalizedValues[[string]$key] = ''
        if ($ValueMap -and $ValueMap.ContainsKey([string]$key)) {
            $valueText = [string]$ValueMap[[string]$key]
            if ($null -ne $valueText) {
                $normalizedValues[[string]$key] = $valueText
            }
        }
    }

    $sourceLines = @()
    if (Test-Path -LiteralPath $Path) {
        $sourceLines = @((Get-Content -LiteralPath $Path -ErrorAction Stop))
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$TemplatePath) -and (Test-Path -LiteralPath $TemplatePath)) {
        $sourceLines = @((Get-Content -LiteralPath $TemplatePath -ErrorAction Stop))
    }

    $writtenKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $outputLines = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($sourceLines)) {
        $rawLine = [string]$line
        $trimmedLine = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace([string]$trimmedLine) -or $trimmedLine.StartsWith('#')) {
            [void]$outputLines.Add($rawLine)
            continue
        }

        $match = [regex]::Match($rawLine, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=')
        if (-not $match.Success) {
            [void]$outputLines.Add($rawLine)
            continue
        }

        $key = [string]$match.Groups[1].Value
        if (-not $supportedLookup.Contains($key)) {
            continue
        }
        if ($writtenKeys.Contains($key)) {
            continue
        }

        $valueText = [string]$normalizedValues[$key]
        [void]$outputLines.Add(("{0}={1}" -f $key, $valueText))
        [void]$writtenKeys.Add($key)
    }

    foreach ($key in @($supportedKeys)) {
        if ($writtenKeys.Contains([string]$key)) {
            continue
        }

        if ($outputLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$outputLines[$outputLines.Count - 1])) {
            [void]$outputLines.Add('')
        }

        $valueText = [string]$normalizedValues[[string]$key]
        [void]$outputLines.Add(("{0}={1}" -f [string]$key, $valueText))
        [void]$writtenKeys.Add([string]$key)
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace([string]$parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-TextFileNormalized `
        -Path $Path `
        -Content (@($outputLines) -join "`n") `
        -Encoding "utf8NoBom" `
        -LineEnding "crlf" `
        -EnsureTrailingNewline
}
