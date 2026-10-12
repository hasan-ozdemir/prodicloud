# Resource naming and path-resolution helpers.

# Handles Get-ClagnosManagedResourceNames.
function Get-ClagnosManagedResourceNames {
    $rows = @()
    try {
        $rows = @(Get-ClagnosManagedResourceGroupRows)
    }
    catch {
        Throw-FriendlyError `
            -Detail "Managed resource groups could not be listed while resolving the next resource id." `
            -Code 22 `
            -Summary "Managed resource naming could not be resolved." `
            -Hint "Run az login and verify access to list tagged resource groups."
    }

    $names = @()
    foreach ($row in @($rows)) {
        $resourceGroup = [string]$row.name
        if ([string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
            continue
        }

        $groupNamesText = az resource list -g $resourceGroup --query "[].name" -o tsv --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0) {
            continue
        }

        $names += @(Convert-ClagnosCliTextToTokens -Text $groupNamesText)
    }

    return @(
        @($names) |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
}

# Handles Get-ClagnosNextManagedResourceIndex.
function Get-ClagnosNextManagedResourceIndex {
    $pattern = '-n(\d+)$'
    $maxIndex = 0
    foreach ($name in @(Get-ClagnosManagedResourceNames)) {
        $match = [regex]::Match([string]$name, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $match.Success) {
            continue
        }

        $idxText = [string]$match.Groups[1].Value
        if (-not ($idxText -match '^\d+$')) {
            continue
        }

        $idx = [int]$idxText
        if ($idx -gt $maxIndex) {
            $maxIndex = $idx
        }
    }

    return ($maxIndex + 1)
}

# Handles New-ClagnosManagedResourceIndexAllocator.
function New-ClagnosManagedResourceIndexAllocator {
    return @{
        ExistingMaxIndex = ((Get-ClagnosNextManagedResourceIndex) - 1)
        NextIndex = (Get-ClagnosNextManagedResourceIndex)
        AllocatedIndices = @{}
    }
}

# Handles Get-ClagnosManagedResourceNameIndex.
function Get-ClagnosManagedResourceNameIndex {
    param(
        [string]$Name
    )

    $match = [regex]::Match([string]$Name, '-n(\d+)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return 0
    }

    $idxText = [string]$match.Groups[1].Value
    if (-not ($idxText -match '^\d+$')) {
        return 0
    }

    return [int]$idxText
}

# Handles Register-ClagnosManagedResourceNameIndex.
function Register-ClagnosManagedResourceNameIndex {
    param(
        [hashtable]$Allocator,
        [string]$Name,
        [string]$LogicalName = 'resource'
    )

    if ($null -eq $Allocator) {
        return 0
    }

    if (-not $Allocator.ContainsKey('AllocatedIndices') -or $null -eq $Allocator['AllocatedIndices']) {
        $Allocator['AllocatedIndices'] = @{}
    }

    $index = Get-ClagnosManagedResourceNameIndex -Name $Name
    if ($index -lt 1) {
        return 0
    }

    $allocatedIndices = $Allocator['AllocatedIndices']
    $existingMaxIndex = 0
    if ($Allocator.ContainsKey('ExistingMaxIndex')) {
        $existingMaxIndex = [int]$Allocator['ExistingMaxIndex']
    }

    if ($index -le $existingMaxIndex) {
        Throw-FriendlyError `
            -Detail ("Managed resource name '{0}' reuses existing global resource id n{1}." -f [string]$Name, $index) `
            -Code 62 `
            -Summary "Managed resource ids must be globally unique." `
            -Hint "Accept the generated resource name or choose a custom name with an unused nX suffix."
    }

    if ($allocatedIndices.ContainsKey([string]$index)) {
        $otherLogicalName = [string]$allocatedIndices[[string]$index]
        if ([string]::Equals([string]$otherLogicalName, [string]$LogicalName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $index
        }
        Throw-FriendlyError `
            -Detail ("Managed resource names '{0}' and '{1}' both use global resource id n{2}." -f [string]$LogicalName, [string]$otherLogicalName, $index) `
            -Code 62 `
            -Summary "Managed resource ids must stay unique within the provisioning plan." `
            -Hint "Use generated names or choose custom names with distinct nX suffixes."
    }

    $allocatedIndices[[string]$index] = [string]$LogicalName
    $Allocator['AllocatedIndices'] = $allocatedIndices
    $nextIndex = [int]$Allocator['NextIndex']
    if ($index -ge $nextIndex) {
        $Allocator['NextIndex'] = ($index + 1)
    }

    return $index
}

# Handles Get-ClagnosManagedResourceIndexFromAllocator.
function Get-ClagnosManagedResourceIndexFromAllocator {
    param(
        [hashtable]$Allocator,
        [string]$LogicalName = 'resource'
    )

    if ($null -eq $Allocator) {
        return (Get-ClagnosNextManagedResourceIndex)
    }

    if (-not $Allocator.ContainsKey('NextIndex')) {
        $Allocator['NextIndex'] = (Get-ClagnosNextManagedResourceIndex)
    }

    $index = [int]$Allocator['NextIndex']
    if ($index -lt 1) {
        $index = 1
    }

    $Allocator['NextIndex'] = ($index + 1)
    if (-not $Allocator.ContainsKey('AllocatedIndices') -or $null -eq $Allocator['AllocatedIndices']) {
        $Allocator['AllocatedIndices'] = @{}
    }
    $allocatedIndices = $Allocator['AllocatedIndices']
    $allocatedIndices[[string]$index] = [string]$LogicalName
    $Allocator['AllocatedIndices'] = $allocatedIndices
    return $index
}

# Handles Get-ClagnosNextManagedResourceGroupIndex.
function Get-ClagnosNextManagedResourceGroupIndex {
    param(
        [string]$NamePrefix
    )

    $rows = @()
    try {
        $rows = @(Get-ClagnosManagedResourceGroupRows)
    }
    catch {
        Throw-FriendlyError `
            -Detail "Managed resource groups could not be listed while resolving the next group id." `
            -Code 22 `
            -Summary "Resource group naming could not be resolved." `
            -Hint "Run az login and verify access to list tagged resource groups."
    }

    $pattern = '-g(\d+)$'
    $maxIndex = 0
    foreach ($row in @($rows)) {
        $name = [string]$row.name
        if ([string]::IsNullOrWhiteSpace([string]$name)) {
            continue
        }

        $m = [regex]::Match($name, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $m.Success) {
            continue
        }

        $idxText = [string]$m.Groups[1].Value
        if (-not ($idxText -match '^\d+$')) {
            continue
        }

        $idx = [int]$idxText
        if ($idx -gt $maxIndex) {
            $maxIndex = $idx
        }
    }

    return ($maxIndex + 1)
}

# Handles Resolve-ClagnosResourceGroupNameFromTemplate.
function Resolve-ClagnosResourceGroupNameFromTemplate {
    param(
        [string]$Template,
        [string]$VmName,
        [string]$RegionCode,
        [switch]$UseNextIndex
    )

    $effectiveTemplate = [string]$Template
    if ([string]::IsNullOrWhiteSpace([string]$effectiveTemplate)) {
        $effectiveTemplate = "rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}"
    }

    $baseTokens = @{
        SELECTED_VM_NAME = [string]$VmName
        REGION_CODE = [string]$RegionCode
    }

    $resolved = Resolve-ClagnosTemplate -Template $effectiveTemplate -Tokens $baseTokens
    $resolved = Assert-ClagnosResolvedTemplateValue `
        -Value $resolved `
        -ConfigKey 'RESOURCE_GROUP_TEMPLATE' `
        -AllowedTokens @('N') `
        -Hint "Set RESOURCE_GROUP_TEMPLATE in .env to the current placeholder contract, for example rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}."
    if ($resolved.IndexOf("{N}", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return $resolved
    }

    $index = 1
    if ($UseNextIndex) {
        $index = Get-ClagnosNextManagedResourceGroupIndex -NamePrefix ''
    }

    return $resolved.Replace("{N}", [string]$index)
}

# Handles Resolve-ClagnosNameFromTemplate.
function Resolve-ClagnosNameFromTemplate {
    param(
        [string]$Template,
        [string]$ResourceType,
        [string]$VmName,
        [string]$RegionCode,
        [string]$ResourceGroup,
        [switch]$UseNextIndex,
        [hashtable]$IndexAllocator,
        [string]$LogicalName = 'resource'
    )

    $effectiveTemplate = [string]$Template
    if ([string]::IsNullOrWhiteSpace($effectiveTemplate)) {
        $effectiveTemplate = "{RESOURCE_TYPE}-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}"
    }

    $baseTokens = @{
        RESOURCE_TYPE = [string]$ResourceType
        SELECTED_VM_NAME = [string]$VmName
        REGION_CODE = [string]$RegionCode
    }

    $resolved = Resolve-ClagnosTemplate -Template $effectiveTemplate -Tokens $baseTokens
    $resolved = Assert-ClagnosResolvedTemplateValue `
        -Value $resolved `
        -ConfigKey ("{0} template" -f [string]$LogicalName) `
        -AllowedTokens @('N') `
        -Hint "Set naming templates in .env to the current placeholder contract, for example {RESOURCE_TYPE}-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}."
    if ($resolved.IndexOf("{N}", [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
        return $resolved
    }

    $index = 1
    if ($UseNextIndex) {
        $index = Get-ClagnosManagedResourceIndexFromAllocator -Allocator $IndexAllocator -LogicalName $LogicalName
    }

    return $resolved.Replace("{N}", [string]$index)
}

function ConvertTo-ClagnosAzureDnsSafeLabel {
    param(
        [string]$Value,
        [string]$Fallback = 'vm0'
    )

    $label = if ([string]::IsNullOrWhiteSpace([string]$Value)) { '' } else { [string]$Value.Trim().ToLowerInvariant() }
    $label = [regex]::Replace($label, '[^a-z0-9-]', '-')
    $label = [regex]::Replace($label, '-{2,}', '-')
    $label = $label.Trim('-')

    if ([string]::IsNullOrWhiteSpace([string]$label)) {
        $label = [string]$Fallback
    }

    if ($label.Length -gt 63) {
        $label = ([string]$label.Substring(0, 63)).TrimEnd('-')
    }

    $label = $label.Trim('-')
    if ([string]::IsNullOrWhiteSpace([string]$label)) {
        $label = [string]$Fallback
    }

    if ($label.Length -lt 3) {
        $label = $label.PadRight(3, '0')
    }

    return [string]$label
}

function Get-ClagnosManagedPublicIpRows {
    $rows = New-Object 'System.Collections.Generic.List[object]'
    try {
        $resourceGroups = @(Get-ClagnosManagedResourceGroupRows)
        foreach ($groupRow in @($resourceGroups)) {
            $resourceGroup = [string]$groupRow.name
            if ([string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
                continue
            }

            $publicIpJson = az network public-ip list -g $resourceGroup -o json --only-show-errors 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$publicIpJson)) {
                continue
            }

            foreach ($publicIpRow in @(ConvertFrom-JsonArrayCompat -InputObject $publicIpJson)) {
                if ($null -eq $publicIpRow) {
                    continue
                }

                $rows.Add($publicIpRow) | Out-Null
            }
        }
    }
    catch {
        Throw-FriendlyError `
            -Detail "Managed public IP inventory could not be listed while resolving the next public DNS label." `
            -Code 22 `
            -Summary "Managed public DNS label could not be resolved." `
            -Hint "Run az login and verify access to list clagnos managed resource groups and public IPs."
    }

    return @($rows.ToArray())
}

function Test-ClagnosManagedPublicIpAttached {
    param([AllowNull()]$PublicIpRow)

    if ($null -eq $PublicIpRow) {
        return $false
    }

    $ipConfigurationId = ''
    if ($PublicIpRow.PSObject.Properties.Match('ipConfiguration').Count -gt 0 -and $null -ne $PublicIpRow.ipConfiguration) {
        if ($PublicIpRow.ipConfiguration.PSObject.Properties.Match('id').Count -gt 0) {
            $ipConfigurationId = [string]$PublicIpRow.ipConfiguration.id
        }
    }

    return (-not [string]::IsNullOrWhiteSpace([string]$ipConfigurationId))
}

function New-ClagnosManagedPublicDnsLabelCandidate {
    param(
        [string]$VmName,
        [int]$VmId
    )

    $effectiveVmId = if ($VmId -lt 1) { 1 } else { [int]$VmId }
    $safeVmName = ConvertTo-ClagnosAzureDnsSafeLabel -Value $VmName -Fallback 'vm'
    $suffix = ('-vm{0}' -f $effectiveVmId)
    $maxVmNameLength = [Math]::Max(1, 63 - $suffix.Length)
    if ($safeVmName.Length -gt $maxVmNameLength) {
        $safeVmName = ([string]$safeVmName.Substring(0, $maxVmNameLength)).TrimEnd('-')
        if ([string]::IsNullOrWhiteSpace([string]$safeVmName)) {
            $safeVmName = 'vm'
        }
    }

    return (ConvertTo-ClagnosAzureDnsSafeLabel -Value ($safeVmName + $suffix) -Fallback ('vm' + $effectiveVmId))
}

# Handles Resolve-ClagnosPublicDnsLabel.
function Resolve-ClagnosPublicDnsLabel {
    param(
        [string]$PublicIpName,
        [string]$VmName = '',
        [int]$PreferredVmId = 0,
        [object[]]$ManagedPublicIpRows = @()
    )

    $effectiveVmName = if ([string]::IsNullOrWhiteSpace([string]$VmName)) { [string]$PublicIpName } else { [string]$VmName }
    $managedRowsWereProvided = $PSBoundParameters.ContainsKey('ManagedPublicIpRows')
    $publicIpRows = if ($managedRowsWereProvided) { @($ManagedPublicIpRows) } else { @(Get-ClagnosManagedPublicIpRows) }
    $existingLabels = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $attachedCount = 0

    foreach ($publicIpRow in @($publicIpRows)) {
        $rowName = ''
        if ($publicIpRow.PSObject.Properties.Match('name').Count -gt 0) {
            $rowName = [string]$publicIpRow.name
        }

        if (Test-ClagnosManagedPublicIpAttached -PublicIpRow $publicIpRow) {
            $attachedCount++
        }

        $domainNameLabel = ''
        if ($publicIpRow.PSObject.Properties.Match('dnsSettings').Count -gt 0 -and $null -ne $publicIpRow.dnsSettings) {
            if ($publicIpRow.dnsSettings.PSObject.Properties.Match('domainNameLabel').Count -gt 0) {
                $domainNameLabel = [string]$publicIpRow.dnsSettings.domainNameLabel
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$domainNameLabel)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$PublicIpName) -and
                [string]::Equals([string]$rowName, [string]$PublicIpName, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [string]($domainNameLabel.Trim().ToLowerInvariant())
            }

            [void]$existingLabels.Add($domainNameLabel.Trim().ToLowerInvariant())
        }
    }

    $vmId = if ($PreferredVmId -gt 0) { [int]$PreferredVmId } else { ($attachedCount + 1) }
    while ($true) {
        $candidateLabel = New-ClagnosManagedPublicDnsLabelCandidate -VmName $effectiveVmName -VmId $vmId
        if (-not $existingLabels.Contains($candidateLabel)) {
            return [string]$candidateLabel
        }

        $vmId++
    }
}

# Handles Resolve-ConfigPath.
function Resolve-ConfigPath {
    param(
        [string]$PathValue,
        [string]$RootPath
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        return $PathValue
    }

    return Join-Path $RootPath $PathValue
}
