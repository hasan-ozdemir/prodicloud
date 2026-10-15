# Dotenv read/write helpers.

function Get-ClagnosSupportedDotEnvKeys {
    return @(
        'SELECTED_VM_OS',
        'SELECTED_VM_NAME',
        'SELECTED_RESOURCE_GROUP',
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
        'SELECTED_AZURE_SUBSCRIPTION_ID',
        'SELECTED_AZURE_REGION',
        'RESOURCE_GROUP_TEMPLATE',
        'VNET_NAME_TEMPLATE',
        'SUBNET_NAME_TEMPLATE',
        'NSG_NAME_TEMPLATE',
        'NSG_RULE_NAME_TEMPLATE',
        'PUBLIC_IP_NAME_TEMPLATE',
        'NIC_NAME_TEMPLATE',
        'VM_DISK_NAME_TEMPLATE',
        'VM_STORAGE_SKU',
        'VM_SECURITY_TYPE',
        'VM_ENABLE_HIBERNATION',
        'VM_ENABLE_NESTED_VIRTUALIZATION',
        'VM_ENABLE_SECURE_BOOT',
        'VM_ENABLE_VTPM',
        'VM_PRICE_COUNT_HOURS',
        'VM_ADMIN_USER',
        'VM_ADMIN_PASS',
        'VM_ASSISTANT_USER',
        'VM_ASSISTANT_PASS',
        'VM_SSH_PORT',
        'VM_RDP_PORT',
        'AZURE_COMMAND_TIMEOUT_SECONDS',
        'SSH_CONNECT_TIMEOUT_SECONDS',
        'SSH_TASK_TIMEOUT_SECONDS',
        'WIN_VM_IMAGE',
        'WIN_VM_SIZE',
        'WIN_VM_DISK_SIZE_GB',
        'LIN_VM_IMAGE',
        'LIN_VM_SIZE',
        'LIN_VM_DISK_SIZE_GB',
        'WIN_VM_INIT_TASK_DIR',
        'WIN_VM_UPDATE_TASK_DIR',
        'LIN_VM_INIT_TASK_DIR',
        'LIN_VM_UPDATE_TASK_DIR',
        'VM_TASK_OUTCOME_MODE',
        'SSH_MAX_RETRIES',
        'PACKAGE_TRANSPORT',
        'PYSSH_CLIENT_PATH',
        'TCP_PORTS'
    )
}

function Resolve-ClagnosSupportedDotEnvConfig {
    param(
        [hashtable]$ConfigMap
    )

    $resolved = @{}
    $supportedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @(Get-ClagnosSupportedDotEnvKeys)) {
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
        [string]$Path
    )

    $config = @{}
    if (-not (Test-Path $Path)) {
        Write-Warning ".env file was not found at '$Path'. Built-in defaults will be used."
        return $config
    }

    foreach ($rawLine in Get-Content -Path $Path) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
            continue
        }

        $match = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$')
        if (-not $match.Success) {
            Write-Warning "Skipping invalid .env line: $rawLine"
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

        $config[$key] = $value
    }

    return (Resolve-ClagnosSupportedDotEnvConfig -ConfigMap $config)
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

# Handles Set-DotEnvValue.
function Set-DotEnvValue {
    param(
        [string]$Path,
        [string]$Key,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Set-DotEnvValue requires a valid file path."
    }
    if ([string]::IsNullOrWhiteSpace($Key)) {
        throw "Set-DotEnvValue requires a non-empty key."
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

    $supportedKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($key in @(Get-ClagnosSupportedDotEnvKeys)) {
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

    $supportedKeys = @(Get-ClagnosSupportedDotEnvKeys)
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
