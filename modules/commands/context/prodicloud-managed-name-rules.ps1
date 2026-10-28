# Shared managed naming and override-precheck helpers.

# Handles Test-ProdicloudVmNameFormat.
function Test-ProdicloudVmNameFormat {
    param(
        [string]$VmName
    )

    if ([string]::IsNullOrWhiteSpace([string]$VmName)) {
        return $false
    }

    return ([string]$VmName -match '^[a-zA-Z][a-zA-Z0-9\-]{2,15}$')
}

# Handles Get-ProdicloudManagedNameValidationRule.
function Get-ProdicloudManagedNameValidationRule {
    param(
        [string]$ConfigKey
    )

    switch ([string]$ConfigKey) {
        'RESOURCE_GROUP' {
            return [pscustomobject]@{
                DisplayName = 'resource group'
                MaxLength = 90
                Pattern = '^[A-Za-z0-9._()\-]+$'
                TrailingDotForbidden = $true
                Hint = "Use 1-90 characters with letters, numbers, dot, underscore, hyphen, or parentheses."
            }
        }
        'VNET_NAME' {
            return [pscustomobject]@{
                DisplayName = 'virtual network'
                MaxLength = 64
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,63}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-64 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
        'SUBNET_NAME' {
            return [pscustomobject]@{
                DisplayName = 'subnet'
                MaxLength = 80
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,79}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-80 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
        'NSG_NAME' {
            return [pscustomobject]@{
                DisplayName = 'network security group'
                MaxLength = 80
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,79}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-80 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
        'NSG_RULE_NAME' {
            return [pscustomobject]@{
                DisplayName = 'network security rule'
                MaxLength = 80
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,79}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-80 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
        'PUBLIC_IP_NAME' {
            return [pscustomobject]@{
                DisplayName = 'public IP'
                MaxLength = 80
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,79}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-80 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
        'NIC_NAME' {
            return [pscustomobject]@{
                DisplayName = 'network interface'
                MaxLength = 80
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,79}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-80 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
        'VM_DISK_NAME' {
            return [pscustomobject]@{
                DisplayName = 'managed disk'
                MaxLength = 80
                Pattern = '^[A-Za-z0-9][A-Za-z0-9._\-]{0,79}$'
                TrailingDotForbidden = $false
                Hint = "Use 1-80 characters with letters, numbers, dot, underscore, or hyphen."
            }
        }
    }

    return $null
}

# Handles Assert-ProdicloudManagedNameContract.
function Assert-ProdicloudManagedNameContract {
    param(
        [string]$ConfigKey,
        [string]$NameValue
    )

    $rule = Get-ProdicloudManagedNameValidationRule -ConfigKey $ConfigKey
    if ($null -eq $rule) {
        return
    }

    $valueText = [string]$NameValue
    if ([string]::IsNullOrWhiteSpace([string]$valueText)) {
        Throw-FriendlyError `
            -Detail ("{0} resolved to an empty value." -f [string]$ConfigKey) `
            -Code 22 `
            -Summary "Managed resource naming is invalid." `
            -Hint ([string]$rule.Hint)
    }

    if ($valueText.Length -gt [int]$rule.MaxLength) {
        Throw-FriendlyError `
            -Detail ("{0} '{1}' is too long ({2} characters, max {3})." -f [string]$rule.DisplayName, $valueText, $valueText.Length, [int]$rule.MaxLength) `
            -Code 22 `
            -Summary "Managed resource naming is invalid." `
            -Hint ([string]$rule.Hint)
    }

    if (-not ($valueText -match [string]$rule.Pattern)) {
        Throw-FriendlyError `
            -Detail ("{0} '{1}' contains unsupported characters for this prodicloud naming contract." -f [string]$rule.DisplayName, $valueText) `
            -Code 22 `
            -Summary "Managed resource naming is invalid." `
            -Hint ([string]$rule.Hint)
    }

    if ([bool]$rule.TrailingDotForbidden -and $valueText.EndsWith('.', [System.StringComparison]::Ordinal)) {
        Throw-FriendlyError `
            -Detail ("{0} '{1}' must not end with a dot." -f [string]$rule.DisplayName, $valueText) `
            -Code 22 `
            -Summary "Managed resource naming is invalid." `
            -Hint ([string]$rule.Hint)
    }
}

# Handles Get-ProdicloudPublicIpZoneArgs.
function Get-ProdicloudPublicIpZoneArgs {
    param(
        [string]$Location
    )

    $locationName = [string]$Location
    if ([string]::IsNullOrWhiteSpace([string]$locationName)) {
        return @()
    }

    $zonesJson = Invoke-ProdicloudWithBypassedAzCliSubscription -Action {
        az account list-locations --query "[?name=='$locationName'] | [0].availabilityZoneMappings[].logicalZone" -o json --only-show-errors
    }
    Assert-LastExitCode "az account list-locations (public IP zones)"
    $zones = ConvertFrom-JsonCompat -InputObject $zonesJson

    $zoneList = @()
    if ($zones -is [System.Array]) {
        $zoneList = @($zones)
    }
    elseif ($null -ne $zones) {
        $zoneList = @($zones)
    }

    $normalizedZones = @(
        $zoneList |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim() } |
            Sort-Object -Unique
    )

    if ($normalizedZones.Count -lt 1) {
        return @()
    }

    return @('--zone') + $normalizedZones
}

# Handles Assert-ProdicloudManagedResourceNamesValid.
function Assert-ProdicloudManagedResourceNamesValid {
    param(
        [hashtable]$NameMap
    )

    if ($null -eq $NameMap) {
        return
    }

    foreach ($configKey in @($NameMap.Keys)) {
        Assert-ProdicloudManagedNameContract -ConfigKey ([string]$configKey) -NameValue ([string]$NameMap[[string]$configKey])
    }
}

# Handles Invoke-ProdicloudExplicitOverridePrecheck.
function Invoke-ProdicloudExplicitOverridePrecheck {
    param(
        [string]$ResourceGroup,
        [string]$VnetName,
        [string]$SubnetName,
        [string]$NsgName,
        [string]$NsgRuleName,
        [string]$PublicIpName,
        [string]$NicName,
        [string]$VmDiskName,
        [switch]$ResourceGroupExists,
        [switch]$VnetExplicit,
        [switch]$SubnetExplicit,
        [switch]$NsgExplicit,
        [switch]$NsgRuleExplicit,
        [switch]$PublicIpExplicit,
        [switch]$NicExplicit,
        [switch]$VmDiskExplicit
    )

    if (-not $ResourceGroupExists) {
        return
    }

    $resourceChecks = @(
        @{ Enabled = [bool]$VnetExplicit; Label = 'VNET_NAME'; Type = 'Microsoft.Network/virtualNetworks'; Name = [string]$VnetName },
        @{ Enabled = [bool]$NsgExplicit; Label = 'NSG_NAME'; Type = 'Microsoft.Network/networkSecurityGroups'; Name = [string]$NsgName },
        @{ Enabled = [bool]$PublicIpExplicit; Label = 'PUBLIC_IP_NAME'; Type = 'Microsoft.Network/publicIPAddresses'; Name = [string]$PublicIpName },
        @{ Enabled = [bool]$NicExplicit; Label = 'NIC_NAME'; Type = 'Microsoft.Network/networkInterfaces'; Name = [string]$NicName },
        @{ Enabled = [bool]$VmDiskExplicit; Label = 'VM_DISK_NAME'; Type = 'Microsoft.Compute/disks'; Name = [string]$VmDiskName }
    )

    foreach ($resourceCheck in @($resourceChecks)) {
        if (-not [bool]$resourceCheck.Enabled) {
            continue
        }

        $resourceExists = Test-ProdicloudAzResourceExistsByType -ResourceGroup $ResourceGroup -ResourceType ([string]$resourceCheck.Type) -ResourceName ([string]$resourceCheck.Name)
        $resourceState = if ($resourceExists) { 'existing resource will be reused' } else { 'resource will be created later' }
        Write-Host ("Explicit override validated: {0}='{1}' -> {2}." -f [string]$resourceCheck.Label, [string]$resourceCheck.Name, [string]$resourceState) -ForegroundColor DarkCyan
    }

    if ($SubnetExplicit -and -not [string]::IsNullOrWhiteSpace([string]$VnetName)) {
        $vnetExists = Test-ProdicloudAzResourceExistsByType -ResourceGroup $ResourceGroup -ResourceType 'Microsoft.Network/virtualNetworks' -ResourceName $VnetName
        if ($vnetExists) {
            $subnetExists = Test-ProdicloudAzResourceExists -AzArgs @('network', 'vnet', 'subnet', 'show', '-g', $ResourceGroup, '--vnet-name', $VnetName, '-n', $SubnetName)
            $subnetState = if ($subnetExists) { 'existing resource will be reused' } else { 'resource will be created later' }
            Write-Host ("Explicit override validated: SUBNET_NAME='{0}' under VNET_NAME='{1}' -> {2}." -f [string]$SubnetName, [string]$VnetName, [string]$subnetState) -ForegroundColor DarkCyan
        }
    }

    if ($NsgRuleExplicit -and -not [string]::IsNullOrWhiteSpace([string]$NsgName)) {
        $nsgExists = Test-ProdicloudAzResourceExistsByType -ResourceGroup $ResourceGroup -ResourceType 'Microsoft.Network/networkSecurityGroups' -ResourceName $NsgName
        if ($nsgExists) {
            $ruleExists = Test-ProdicloudNsgRuleExists -ResourceGroup $ResourceGroup -NsgName $NsgName -RuleName $NsgRuleName
            $ruleState = if ($ruleExists) { 'existing resource will be reused' } else { 'resource will be created later' }
            Write-Host ("Explicit override validated: NSG_RULE_NAME='{0}' in NSG_NAME='{1}' -> {2}." -f [string]$NsgRuleName, [string]$NsgName, [string]$ruleState) -ForegroundColor DarkCyan
        }
    }
}
