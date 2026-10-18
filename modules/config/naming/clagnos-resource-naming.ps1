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
        -Hint "Set RESOURCE_GROUP_TEMPLATE in clagnos.env to the current placeholder contract, for example rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}."
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
        -Hint "Set naming templates in clagnos.env to the current placeholder contract, for example {RESOURCE_TYPE}-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}."
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

function Assert-ClagnosPublicDnsLabelAvailable {
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string]$Location,
        [Parameter(Mandatory = $true)][string]$SubscriptionId
    )

    $normalizedLabel = ConvertTo-ClagnosAzureDnsSafeLabel -Value $Label -Fallback 'vm'
    if ($normalizedLabel -notmatch '^[a-z][a-z0-9-]{1,61}[a-z0-9]$') {
        Throw-FriendlyError -Detail ("DNS label '{0}' is not a valid Azure public IP label." -f $normalizedLabel) -Code 25 -Summary 'Azure DNS label is invalid.' -Hint 'Use the VM name as the public DNS label.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Location) -or [string]::IsNullOrWhiteSpace([string]$SubscriptionId)) {
        Throw-FriendlyError -Detail 'DNS availability check requires the selected Azure region and subscription.' -Code 22 -Summary 'Azure DNS label could not be checked.' -Hint 'Select an Azure subscription and region, then retry.'
    }

    $url = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Network/locations/$Location/checkDnsNameAvailability?api-version=2025-05-01"
    Write-Host ("Doing: check whether Azure DNS label '{0}' is available in '{1}'" -f $normalizedLabel,$Location) -ForegroundColor Cyan
    $json = az rest --method get --url $url --url-parameters ("domainNameLabel={0}" -f $normalizedLabel) --subscription $SubscriptionId -o json --only-show-errors 2>$null
    Assert-LastExitCode 'Azure public DNS label availability check'
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        Throw-FriendlyError -Detail ("Azure returned no DNS availability result for label '{0}'." -f $normalizedLabel) -Code 22 -Summary 'Azure DNS label availability is unknown.' -Hint 'Retry after verifying Azure Network read access.'
    }

    try { $availability = ConvertFrom-JsonCompat -InputObject ([string]$json) }
    catch { Throw-FriendlyError -Detail ("Azure returned an unreadable DNS availability result for label '{0}'." -f $normalizedLabel) -Code 22 -Summary 'Azure DNS label availability is unknown.' -Hint 'Retry after verifying Azure Network read access.' }
    if ($null -eq $availability -or $availability.PSObject.Properties.Match('available').Count -eq 0) {
        Throw-FriendlyError -Detail ("Azure omitted the availability flag for DNS label '{0}'." -f $normalizedLabel) -Code 22 -Summary 'Azure DNS label availability is unknown.' -Hint 'Retry after verifying Azure Network read access.'
    }
    if (-not [bool]$availability.available) {
        $reason = [string]$availability.reason
        if ([string]::IsNullOrWhiteSpace([string]$reason)) { $reason = 'label already in use' }
        Throw-FriendlyError -Detail ("Azure DNS label '{0}.{1}.cloudapp.azure.com' is unavailable ({2})." -f $normalizedLabel,$Location,$reason) -Code 25 -Summary 'The VM name is unavailable as an Azure DNS label.' -Hint 'Choose a different VM name before provisioning; Clagnos will not add a numeric DNS suffix.'
    }
    return $true
}

# Handles Resolve-ClagnosPublicDnsLabel.
function Resolve-ClagnosPublicDnsLabel {
    param(
        [string]$PublicIpName,
        [string]$VmName = ''
    )

    $effectiveVmName = if ([string]::IsNullOrWhiteSpace([string]$VmName)) { [string]$PublicIpName } else { [string]$VmName }
    return [string](ConvertTo-ClagnosAzureDnsSafeLabel -Value $effectiveVmName -Fallback 'vm')
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
