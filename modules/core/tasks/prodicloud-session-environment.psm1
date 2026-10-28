$ErrorActionPreference = 'Stop'

function Get-ProdicloudRegistryEnvironmentValue {
    param(
        [ValidateSet('Machine', 'User')]
        [string]$Scope,
        [string]$Name
    )

    $registryPath = if ([string]::Equals([string]$Scope, 'Machine', [System.StringComparison]::OrdinalIgnoreCase)) {
        'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    }
    else {
        'HKCU:\Environment'
    }

    if (-not (Test-Path -LiteralPath $registryPath)) {
        return ''
    }

    $propertyValue = (Get-ItemProperty -LiteralPath $registryPath -Name $Name -ErrorAction SilentlyContinue).$Name
    if ($null -eq $propertyValue) {
        return ''
    }

    return [string]$propertyValue
}

function Get-ProdicloudRegistryPathEntries {
    param([ValidateSet('Machine', 'User')][string]$Scope)

    $pathValue = Get-ProdicloudRegistryEnvironmentValue -Scope $Scope -Name 'Path'
    if ([string]::IsNullOrWhiteSpace([string]$pathValue)) {
        return @()
    }

    $entries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rawEntry in @([string]$pathValue -split ';')) {
        $expandedEntry = [Environment]::ExpandEnvironmentVariables([string]$rawEntry).Trim()
        if ([string]::IsNullOrWhiteSpace([string]$expandedEntry)) {
            continue
        }

        $entries.Add([string]$expandedEntry) | Out-Null
    }

    return @($entries.ToArray())
}

function Get-ProdicloudSessionPathValue {
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $orderedEntries = New-Object 'System.Collections.Generic.List[string]'

    foreach ($scope in @('Machine', 'User')) {
        foreach ($entry in @(Get-ProdicloudRegistryPathEntries -Scope $scope)) {
            if ($seen.Add([string]$entry)) {
                $orderedEntries.Add([string]$entry) | Out-Null
            }
        }
    }

    return (@($orderedEntries.ToArray()) -join ';')
}

function Refresh-ProdicloudSessionPath {
    $resolvedPath = Get-ProdicloudSessionPathValue
    if ([string]::IsNullOrWhiteSpace([string]$resolvedPath)) {
        $resolvedPath = [string][Environment]::GetEnvironmentVariable('Path', 'Process')
    }

    $env:Path = [string]$resolvedPath
    return [string]$env:Path
}

Export-ModuleMember -Function Refresh-ProdicloudSessionPath, Get-ProdicloudSessionPathValue
