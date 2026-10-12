# Shared config resolution helpers.

# Handles Test-ClagnosConfigPlaceholderValue.
function Test-ClagnosConfigPlaceholderValue {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $false
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    return (
        $normalized.Contains('change_me') -or
        $normalized.Contains('changeme') -or
        $normalized.Contains('replace_me') -or
        $normalized.Contains('set_me') -or
        $normalized.Contains('todo') -or
        $normalized.StartsWith('<') -or
        $normalized.EndsWith('>')
    )
}

# Handles Get-ClagnosUnresolvedTemplateTokens.
function Get-ClagnosUnresolvedTemplateTokens {
    param(
        [string]$Value,
        [string[]]$AllowedTokens = @()
    )

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return @()
    }

    $allowedLookup = @{}
    foreach ($token in @($AllowedTokens)) {
        if ([string]::IsNullOrWhiteSpace([string]$token)) {
            continue
        }

        $allowedLookup[[string]$token] = $true
    }

    $tokens = New-Object 'System.Collections.Generic.List[string]'
    foreach ($match in [regex]::Matches([string]$Value, '\{([A-Z][A-Z0-9_]*)\}')) {
        $tokenName = [string]$match.Groups[1].Value
        if ($allowedLookup.ContainsKey($tokenName)) {
            continue
        }

        if (-not $tokens.Contains($tokenName)) {
            [void]$tokens.Add($tokenName)
        }
    }

    return @($tokens.ToArray())
}

# Handles Assert-ClagnosResolvedTemplateValue.
function Assert-ClagnosResolvedTemplateValue {
    param(
        [string]$Value,
        [string]$ConfigKey,
        [string[]]$AllowedTokens = @(),
        [string]$Hint = 'Update the configured template so it uses only the current placeholder contract.'
    )

    $unresolvedTokens = @(Get-ClagnosUnresolvedTemplateTokens -Value $Value -AllowedTokens $AllowedTokens)
    if ($unresolvedTokens.Count -le 0) {
        return [string]$Value
    }

    $tokenList = ($unresolvedTokens | ForEach-Object { '{' + [string]$_ + '}' }) -join ', '
    Throw-FriendlyError `
        -Detail ("Config template '{0}' resolved to '{1}', but unresolved placeholder token(s) remain: {2}." -f [string]$ConfigKey, [string]$Value, $tokenList) `
        -Code 22 `
        -Summary "Config template contains unresolved placeholder tokens." `
        -Hint $Hint
}

# Handles Get-ClagnosResolvedConfigValue.
function Get-ClagnosResolvedConfigValue {
    param(
        [hashtable]$ConfigMap,
        [string]$Key,
        [hashtable]$Tokens = @{},
        [string]$DefaultValue = ''
    )

    $rawValue = [string](Get-ConfigValue -Config $ConfigMap -Key $Key -DefaultValue $DefaultValue)
    return [string](Resolve-ClagnosTemplate -Template $rawValue -Tokens $Tokens)
}

# Handles Get-ClagnosRequiredResolvedConfigValue.
function Get-ClagnosRequiredResolvedConfigValue {
    param(
        [hashtable]$ConfigMap,
        [string]$Key,
        [hashtable]$Tokens = @{},
        [string]$Summary,
        [string]$Hint,
        [int]$Code = 14,
        [string]$DefaultValue = ''
    )

    $resolvedValue = [string](Get-ClagnosResolvedConfigValue -ConfigMap $ConfigMap -Key $Key -Tokens $Tokens -DefaultValue $DefaultValue)
    if ([string]::IsNullOrWhiteSpace([string]$resolvedValue)) {
        Throw-FriendlyError `
            -Detail ("Required config value '{0}' is not set." -f $Key) `
            -Code $Code `
            -Summary $Summary `
            -Hint $Hint
    }

    if (Test-ClagnosConfigPlaceholderValue -Value $resolvedValue) {
        Throw-FriendlyError `
            -Detail ("Config value '{0}' still uses a placeholder value: '{1}'." -f $Key, $resolvedValue) `
            -Code $Code `
            -Summary $Summary `
            -Hint $Hint
    }

    return $resolvedValue
}
