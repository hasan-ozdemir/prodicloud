# UI show-report rendering helpers.

# Handles Invoke-ProdicloudAzJsonOrNull.
function Invoke-ProdicloudAzJsonOrNull {
    param(
        [string[]]$AzArgs,
        [string]$Context,
        [switch]$SuppressError
    )

    $output = az @AzArgs
    if ($LASTEXITCODE -ne 0) {
        if ($SuppressError) {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace([string]$Context)) {
            throw ("Azure command failed with exit code {0}." -f $LASTEXITCODE)
        }
        throw ("{0} failed with exit code {1}." -f $Context, $LASTEXITCODE)
    }

    if ($null -eq $output -or [string]::IsNullOrWhiteSpace([string]$output)) {
        return $null
    }

    try {
        return ConvertFrom-JsonCompat -InputObject $output
    }
    catch {
        if ($SuppressError) {
            return $null
        }

        if ([string]::IsNullOrWhiteSpace([string]$Context)) {
            throw "Azure command returned an unparseable JSON payload."
        }
        throw ("{0} returned an unparseable JSON payload." -f $Context)
    }
}

# Handles Get-ProdicloudResourceTypeCountMap.
function Get-ProdicloudResourceTypeCountMap {
    param(
        [object[]]$Resources
    )

    $counter = @{}
    foreach ($resource in @($Resources)) {
        if ($null -eq $resource) {
            continue
        }

        $typeName = [string]$resource.type
        if ([string]::IsNullOrWhiteSpace([string]$typeName)) {
            $typeName = "(unknown)"
        }

        if (-not $counter.ContainsKey($typeName)) {
            $counter[$typeName] = 0
        }
        $counter[$typeName] = [int]$counter[$typeName] + 1
    }

    $ordered = [ordered]@{}
    foreach ($key in @($counter.Keys | Sort-Object)) {
        $ordered[[string]$key] = [int]$counter[$key]
    }

    return $ordered
}

# Handles Get-ProdicloudVmInventoryDump.
function Get-ProdicloudVmInventoryDump {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $vmFull = Invoke-ProdicloudAzJsonOrNull -AzArgs @("vm", "show", "-g", $ResourceGroup, "-n", $VmName, "-o", "json", "--only-show-errors") -Context "az vm show" -SuppressError
    if ($null -eq $vmFull) {
        return [ordered]@{
            Name = [string]$VmName
            ResourceGroup = [string]$ResourceGroup
            Error = "VM metadata could not be loaded."
        }
    }

    $vmDetailed = Invoke-ProdicloudAzJsonOrNull -AzArgs @("vm", "show", "-d", "-g", $ResourceGroup, "-n", $VmName, "-o", "json", "--only-show-errors") -Context "az vm show -d" -SuppressError
    $vmInstanceView = Invoke-ProdicloudAzJsonOrNull -AzArgs @("vm", "get-instance-view", "-g", $ResourceGroup, "-n", $VmName, "-o", "json", "--only-show-errors") -Context "az vm get-instance-view" -SuppressError

    $location = [string]$vmFull.location
    $vmSize = [string]$vmFull.hardwareProfile.vmSize
    $osType = [string]$vmFull.storageProfile.osDisk.osType
    $powerState = [string]$vmDetailed.powerState
    if ([string]::IsNullOrWhiteSpace([string]$powerState) -and $vmInstanceView) {
        foreach ($status in @(ConvertTo-ObjectArrayCompat -InputObject $vmInstanceView.statuses)) {
            $statusCode = [string]$status.code
            if ($statusCode.StartsWith("PowerState/", [System.StringComparison]::OrdinalIgnoreCase)) {
                $powerState = [string]$status.displayStatus
                if ([string]::IsNullOrWhiteSpace([string]$powerState)) {
                    $powerState = $statusCode
                }
                break
            }
        }
    }

    $osDiskName = [string]$vmFull.storageProfile.osDisk.name
    $dataDiskNames = @(
        ConvertTo-ObjectArrayCompat -InputObject $vmFull.storageProfile.dataDisks |
            ForEach-Object { [string]$_.name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )

    $diskDetails = @()
    foreach ($diskName in @(@($osDiskName) + @($dataDiskNames) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $diskObj = Invoke-ProdicloudAzJsonOrNull -AzArgs @("disk", "show", "-g", $ResourceGroup, "-n", [string]$diskName, "-o", "json", "--only-show-errors") -Context "az disk show" -SuppressError
        if ($null -ne $diskObj) {
            $diskDetails += $diskObj
        }
    }

    $nicIds = @(
        ConvertTo-ObjectArrayCompat -InputObject $vmFull.networkProfile.networkInterfaces |
            ForEach-Object { [string]$_.id } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )

    $nicDetails = @()
    $publicIpIdSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($nicId in @($nicIds)) {
        $nicObj = Invoke-ProdicloudAzJsonOrNull -AzArgs @("network", "nic", "show", "--ids", [string]$nicId, "-o", "json", "--only-show-errors") -Context "az network nic show" -SuppressError
        if ($null -eq $nicObj) {
            continue
        }

        $nicDetails += $nicObj
        foreach ($ipCfg in @(ConvertTo-ObjectArrayCompat -InputObject $nicObj.ipConfigurations)) {
            $publicIpId = [string]$ipCfg.publicIpAddress.id
            if (-not [string]::IsNullOrWhiteSpace([string]$publicIpId)) {
                [void]$publicIpIdSet.Add($publicIpId)
            }
        }
    }

    $publicIpDetails = @()
    foreach ($publicIpId in @($publicIpIdSet | Sort-Object)) {
        $publicIpObj = Invoke-ProdicloudAzJsonOrNull -AzArgs @("network", "public-ip", "show", "--ids", [string]$publicIpId, "-o", "json", "--only-show-errors") -Context "az network public-ip show" -SuppressError
        if ($null -ne $publicIpObj) {
            $publicIpDetails += $publicIpObj
        }
    }

    $nestedAzureSetting = $null
    if ($vmFull.additionalCapabilities -and $vmFull.additionalCapabilities.PSObject.Properties.Match('nestedVirtualization').Count -gt 0) {
        $nestedAzureSetting = $vmFull.additionalCapabilities.nestedVirtualization
    }
    $featureFlags = [ordered]@{
        HibernationEnabled = $vmFull.additionalCapabilities.hibernationEnabled
        NestedVirtualizationAvailableToGuest = $null
        NestedVirtualizationAzureSetting = $nestedAzureSetting
        NestedVirtualizationValidationSource = ''
        NestedVirtualizationEvidence = @()
        NestedVirtualizationValidationError = ''
        NestedVirtualizationCapabilities = @()
    }

    $normalizedOsType = if ([string]$osType -match '(?i)linux') { 'linux' } else { 'windows' }
    if (-not [string]::IsNullOrWhiteSpace([string]$powerState) -and ([string]$powerState).ToLowerInvariant().Contains('running')) {
        $nestedValidation = Get-ProdicloudNestedVirtualizationGuestValidation -ResourceGroup $ResourceGroup -VmName $VmName -OsType $normalizedOsType -SuppressError
        $featureFlags.NestedVirtualizationValidationSource = 'guest'
        if ([bool]$nestedValidation.Known) {
            $featureFlags.NestedVirtualizationAvailableToGuest = [bool]$nestedValidation.AvailableToGuest
            $featureFlags.NestedVirtualizationEvidence = @($nestedValidation.Evidence)
        }
        else {
            $featureFlags.NestedVirtualizationValidationError = [string]$nestedValidation.ErrorMessage
            $featureFlags.NestedVirtualizationEvidence = @($nestedValidation.Evidence)
        }
    }

    return [ordered]@{
        Name = [string]$VmName
        ResourceGroup = [string]$ResourceGroup
        Location = [string]$location
        VmSize = [string]$vmSize
        OsType = [string]$osType
        PowerState = [string]$powerState
        ProvisioningState = [string]$vmDetailed.provisioningState
        PublicIps = [string]$vmDetailed.publicIps
        PrivateIps = [string]$vmDetailed.privateIps
        Fqdns = [string]$vmDetailed.fqdns
        Identity = $vmFull.identity
        AdditionalCapabilities = $vmFull.additionalCapabilities
        FeatureFlags = $featureFlags
        SkuName = [string]$vmSize
        SkuTier = ""
        SkuFamily = ""
        SkuAvailability = "unknown"
        SkuCapabilities = @()
        FocusedCapabilities = @()
        OsDiskName = [string]$osDiskName
        DataDiskNames = @($dataDiskNames)
        Disks = @($diskDetails)
        NicIds = @($nicIds)
        Nics = @($nicDetails)
        PublicIpResources = @($publicIpDetails)
        VmShowDetails = $vmDetailed
        InstanceView = $vmInstanceView
        VmProperties = $vmFull
    }
}

# Handles Get-ProdicloudSkuMetadataMap.
function Get-ProdicloudSkuMetadataMap {
    param(
        [string]$Location,
        [string[]]$SkuNames
    )

    $result = @{}
    if ([string]::IsNullOrWhiteSpace([string]$Location) -or -not $SkuNames -or $SkuNames.Count -eq 0) {
        return $result
    }

    $targetSkuSet = @{}
    foreach ($skuName in @($SkuNames)) {
        $nameText = [string]$skuName
        if ([string]::IsNullOrWhiteSpace([string]$nameText)) {
            continue
        }
        $targetSkuSet[$nameText.ToLowerInvariant()] = $true
    }
    if ($targetSkuSet.Count -eq 0) {
        return $result
    }

    $subscriptionId = az account show --only-show-errors --query id -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        return $result
    }

    $tokenJson = az account get-access-token --only-show-errors --resource https://management.azure.com/ -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$tokenJson)) {
        return $result
    }

    $accessToken = (ConvertFrom-JsonCompat -InputObject $tokenJson).accessToken
    if ([string]::IsNullOrWhiteSpace([string]$accessToken)) {
        return $result
    }

    $filter = [uri]::EscapeDataString("location eq '$Location'")
    $url = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/skus?api-version=2023-07-01&`$filter=$filter"
    try {
        $response = Invoke-ProdicloudHttpRestMethod `
            -Method Get `
            -Uri $url `
            -Headers @{ Authorization = "Bearer $accessToken" } `
            -PerfLabel ("http compute skus metadata (location={0})" -f [string]$Location)
    }
    catch {
        return $result
    }

    foreach ($item in @((ConvertTo-ObjectArrayCompat -InputObject $response.value) | Where-Object { $_.resourceType -eq "virtualMachines" })) {
        if (-not $item.name) {
            continue
        }

        $itemName = [string]$item.name
        $itemKey = $itemName.ToLowerInvariant()
        if (-not $targetSkuSet.ContainsKey($itemKey)) {
            continue
        }

        $isUnavailable = $false
        foreach ($restriction in (ConvertTo-ObjectArrayCompat -InputObject $item.restrictions)) {
            if ($restriction.reasonCode -eq "NotAvailableForSubscription") {
                $isUnavailable = $true
                break
            }
            if ($restriction.type -eq "Location" -and (($restriction.values -and ($restriction.values -contains $Location)) -or -not $restriction.values)) {
                $isUnavailable = $true
                break
            }
        }

        $locationInfo = @(
            (ConvertTo-ObjectArrayCompat -InputObject $item.locationInfo) |
                Where-Object { $_.location -ieq $Location }
        )
        $availability = if ($isUnavailable -or -not $locationInfo) { "no" } else { "yes" }

        $skuCapabilities = @(ConvertTo-ObjectArrayCompat -InputObject $item.capabilities)
        $focusedCapabilities = @(
            $skuCapabilities | Where-Object {
                $capName = [string]$_.name
                if ([string]::IsNullOrWhiteSpace([string]$capName)) {
                    return $false
                }

                $capLower = $capName.ToLowerInvariant()
                return (
                    $capLower.Contains("nested") -or
                    $capLower.Contains("hibern") -or
                    $capLower.Contains("hyperv") -or
                    $capLower.Contains("trusted") -or
                    $capLower.Contains("encryption")
                )
            }
        )

        $nestedCapabilities = @(
            $focusedCapabilities |
                Where-Object {
                    $capName = [string]$_.name
                    -not [string]::IsNullOrWhiteSpace([string]$capName) -and $capName.ToLowerInvariant().Contains("nested")
                }
        )

        $result[$itemName] = [ordered]@{
            Name = $itemName
            Tier = [string]$item.tier
            Family = [string]$item.family
            Availability = [string]$availability
            SkuCapabilities = @($skuCapabilities)
            FocusedCapabilities = @($focusedCapabilities)
            NestedCapabilities = @($nestedCapabilities)
        }
    }

    return $result
}

# Handles Get-ProdicloudResourceGroupInventoryDump.
function Get-ProdicloudResourceGroupInventoryDump {
    param(
        [string]$ResourceGroup
    )

    Write-Host ("show: scanning resource group '{0}'..." -f [string]$ResourceGroup) -ForegroundColor DarkGray
    $groupObj = Invoke-ProdicloudAzJsonOrNull -AzArgs @("group", "show", "-n", $ResourceGroup, "-o", "json", "--only-show-errors") -Context "az group show" -SuppressError
    if ($null -eq $groupObj) {
        return [ordered]@{
            Name = [string]$ResourceGroup
            Exists = $false
            ResourceCount = 0
            ResourceTypeCounts = [ordered]@{}
            VmCount = 0
            Vms = @()
            Resources = @()
        }
    }

    $resourcesRaw = Invoke-ProdicloudAzJsonOrNull -AzArgs @("resource", "list", "-g", $ResourceGroup, "-o", "json", "--only-show-errors") -Context "az resource list" -SuppressError
    $resources = @(ConvertTo-ObjectArrayCompat -InputObject $resourcesRaw)
    $resourceTypeCounts = Get-ProdicloudResourceTypeCountMap -Resources $resources

    $vmNameRows = Invoke-ProdicloudAzJsonOrNull -AzArgs @("vm", "list", "-g", $ResourceGroup, "--query", "[].name", "-o", "json", "--only-show-errors") -Context "az vm list" -SuppressError
    $vmNames = @(
        ConvertTo-ObjectArrayCompat -InputObject $vmNameRows |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )

    $vmDumps = @()
    foreach ($vmName in @($vmNames)) {
        Write-Host ("show: collecting VM '{0}' in group '{1}'..." -f [string]$vmName, [string]$ResourceGroup) -ForegroundColor DarkGray
        $vmDumps += (Get-ProdicloudVmInventoryDump -ResourceGroup $ResourceGroup -VmName ([string]$vmName))
    }

    $skuNamesByLocation = @{}
    foreach ($vmDump in @($vmDumps)) {
        $vmLocation = [string]$vmDump.Location
        $vmSkuName = [string]$vmDump.VmSize
        if ([string]::IsNullOrWhiteSpace([string]$vmLocation) -or [string]::IsNullOrWhiteSpace([string]$vmSkuName)) {
            continue
        }

        if (-not $skuNamesByLocation.ContainsKey($vmLocation)) {
            $skuNamesByLocation[$vmLocation] = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
        }
        [void]$skuNamesByLocation[$vmLocation].Add($vmSkuName)
    }

    $skuMetadataByLocation = @{}
    foreach ($locationKey in @($skuNamesByLocation.Keys)) {
        $skuNameList = @($skuNamesByLocation[$locationKey] | Sort-Object)
        if ($skuNameList.Count -eq 0) {
            continue
        }
        Write-Host ("show: loading optimized SKU metadata for location '{0}'..." -f [string]$locationKey) -ForegroundColor DarkGray
        $skuMetadataByLocation[$locationKey] = Get-ProdicloudSkuMetadataMap -Location ([string]$locationKey) -SkuNames $skuNameList
    }

    foreach ($vmDump in @($vmDumps)) {
        $vmLocation = [string]$vmDump.Location
        $vmSkuName = [string]$vmDump.VmSize
        if ([string]::IsNullOrWhiteSpace([string]$vmLocation) -or [string]::IsNullOrWhiteSpace([string]$vmSkuName)) {
            continue
        }
        if (-not $skuMetadataByLocation.ContainsKey($vmLocation)) {
            continue
        }

        $locationMeta = $skuMetadataByLocation[$vmLocation]
        if (-not $locationMeta.ContainsKey($vmSkuName)) {
            continue
        }

        $meta = $locationMeta[$vmSkuName]
        $vmDump['SkuName'] = [string]$meta.Name
        $vmDump['SkuTier'] = [string]$meta.Tier
        $vmDump['SkuFamily'] = [string]$meta.Family
        $vmDump['SkuAvailability'] = [string]$meta.Availability
        $vmDump['SkuCapabilities'] = @($meta.SkuCapabilities)
        $vmDump['FocusedCapabilities'] = @($meta.FocusedCapabilities)

        if ($vmDump.Contains('FeatureFlags') -and $vmDump.FeatureFlags) {
            $vmDump.FeatureFlags['NestedVirtualizationCapabilities'] = @($meta.NestedCapabilities)
        }
    }

    return [ordered]@{
        Name = [string]$groupObj.name
        Exists = $true
        Id = [string]$groupObj.id
        Location = [string]$groupObj.location
        ManagedBy = [string]$groupObj.managedBy
        ProvisioningState = [string]$groupObj.properties.provisioningState
        Tags = $groupObj.tags
        ResourceCount = @($resources).Count
        ResourceTypeCounts = $resourceTypeCounts
        VmCount = @($vmDumps).Count
        Vms = @($vmDumps)
        Resources = @($resources)
    }
}

# Handles Write-ProdicloudShowSectionHeader.
function Write-ProdicloudShowSectionHeader {
    param(
        [string]$Text
    )

    Write-Host ""
    Write-Host $Text -ForegroundColor Cyan
}

# Handles Write-ProdicloudShowKeyValueRow.
function Write-ProdicloudShowKeyValueRow {
    param(
        [string]$Label,
        [object]$Value,
        [int]$Indent = 0
    )

    $indentSize = [Math]::Max(0, [int]$Indent)
    $indentText = (' ' * $indentSize)
    $valueText = ConvertTo-ProdicloudDisplayValue -Value $Value
    if ([string]::IsNullOrWhiteSpace([string]$valueText)) {
        $valueText = "(empty)"
    }

    Write-Host ("{0}{1}: {2}" -f $indentText, $Label, $valueText)
}

# Handles Test-ProdicloudShowSensitiveConfigKey.
function Test-ProdicloudShowSensitiveConfigKey {
    param(
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace([string]$Key)) {
        return $false
    }

    $normalizedKey = [string]$Key
    $normalizedKey = $normalizedKey.Trim().ToUpperInvariant()
    if ($normalizedKey -in @('VM_ADMIN_PASS', 'VM_ASSISTANT_PASS')) {
        return $true
    }

    return (
        $normalizedKey.Contains('PASSWORD') -or
        $normalizedKey.Contains('_PASS') -or
        $normalizedKey.EndsWith('PASS') -or
        $normalizedKey.Contains('SECRET') -or
        $normalizedKey.Contains('TOKEN')
    )
}

# Handles ConvertTo-ProdicloudShowConfigDisplayValue.
function ConvertTo-ProdicloudShowConfigDisplayValue {
    param(
        [string]$Key,
        [object]$Value
    )

    if (Test-ProdicloudShowSensitiveConfigKey -Key $Key) {
        return '[redacted]'
    }

    return $Value
}

# Handles ConvertTo-ProdicloudShowExportDump.
function ConvertTo-ProdicloudShowExportDump {
    param([hashtable]$Dump)

    $json = ConvertTo-Json -InputObject $Dump -Depth 100 -Compress
    $safeDump = ConvertFrom-JsonCompat -InputObject $json
    $configMaps = @(
        $safeDump.Config.DotEnvValues,
        $safeDump.Config.RuntimeOverrides,
        $safeDump.TargetDerivedConfiguration.Summary
    )
    foreach ($configMap in @($configMaps)) {
        if ($null -eq $configMap) { continue }
        foreach ($property in @($configMap.PSObject.Properties)) {
            if (Test-ProdicloudShowSensitiveConfigKey -Key ([string]$property.Name)) {
                $property.Value = '[redacted]'
            }
        }
    }
    return $safeDump
}

# Handles Export-ProdicloudShowReportJson.
function Export-ProdicloudShowReportJson {
    param(
        [hashtable]$Dump,
        [string]$OutputPath,
        [switch]$Overwrite
    )

    if ([string]::IsNullOrWhiteSpace([string]$OutputPath)) {
        Throw-FriendlyError `
            -Detail "Option '--export-json' requires an output file path." `
            -Code 64 `
            -Summary "Show JSON export path is missing." `
            -Hint "Use --export-json <path> to select a report file."
    }

    $resolvedOutputPath = [System.IO.Path]::GetFullPath([string]$OutputPath)
    $parentPath = [System.IO.Path]::GetDirectoryName($resolvedOutputPath)
    if (-not (Test-Path -LiteralPath $parentPath -PathType Container)) {
        Throw-FriendlyError `
            -Detail ("JSON export directory does not exist: {0}" -f $parentPath) `
            -Code 64 `
            -Summary "Show JSON export directory was not found." `
            -Hint "Create the directory first or select an existing output directory."
    }
    if ((Test-Path -LiteralPath $resolvedOutputPath) -and -not $Overwrite) {
        Throw-FriendlyError `
            -Detail ("JSON export file already exists: {0}" -f $resolvedOutputPath) `
            -Code 64 `
            -Summary "Show JSON export would overwrite an existing file." `
            -Hint "Choose another filename or add --overwrite after reviewing the target path."
    }

    $tempPath = Join-Path $parentPath ('.prodicloud-show-{0}.tmp' -f ([guid]::NewGuid().ToString('N')))
    try {
        $safeDump = ConvertTo-ProdicloudShowExportDump -Dump $Dump
        $json = ConvertTo-Json -InputObject $safeDump -Depth 100
        [System.IO.File]::WriteAllText($tempPath, ([string]$json + [Environment]::NewLine), ([System.Text.UTF8Encoding]::new($false)))
        if ((Test-Path -LiteralPath $resolvedOutputPath) -and $Overwrite) {
            Remove-Item -LiteralPath $resolvedOutputPath -Force
        }
        Move-Item -LiteralPath $tempPath -Destination $resolvedOutputPath -ErrorAction Stop
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host ("Redacted JSON report exported: {0}" -f $resolvedOutputPath) -ForegroundColor Green
    return $resolvedOutputPath
}

# Handles Write-ProdicloudShowReport.
function Write-ProdicloudShowReport {
    param(
        [hashtable]$Dump
    )

    Write-ProdicloudShowSectionHeader -Text "Azure VM Show Report"
    Write-ProdicloudShowKeyValueRow -Label "Generated at (UTC)" -Value ([string]$Dump.GeneratedAtUtc) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Command" -Value ([string]$Dump.Command) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Mode" -Value ([string]$Dump.Mode) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Requested platform" -Value ([string]$Dump.RequestedPlatform) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Env file path" -Value ([string]$Dump.EnvFilePath) -Indent 2

    Write-ProdicloudShowSectionHeader -Text "Azure Account"
    Write-ProdicloudShowKeyValueRow -Label "Subscription name" -Value ([string]$Dump.AzureAccount.SubscriptionName) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Subscription id" -Value ([string]$Dump.AzureAccount.SubscriptionId) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Tenant name" -Value ([string]$Dump.AzureAccount.TenantName) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Tenant id" -Value ([string]$Dump.AzureAccount.TenantId) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Account user" -Value ([string]$Dump.AzureAccount.UserName) -Indent 2

    Write-ProdicloudShowSectionHeader -Text "Selection And Summary"
    Write-ProdicloudShowKeyValueRow -Label "Target group filter" -Value ([string]$Dump.Selection.TargetGroup) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Target VM filter" -Value ([string]$Dump.Selection.TargetVmName) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Included resource groups" -Value (@($Dump.Selection.IncludedResourceGroups)) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Resource group count" -Value ([int]$Dump.Summary.ResourceGroupCount) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Total VM count" -Value ([int]$Dump.Summary.TotalVmCount) -Indent 2
    Write-ProdicloudShowKeyValueRow -Label "Running VM count" -Value ([int]$Dump.Summary.RunningVmCount) -Indent 2

    if ($Dump.TargetDerivedConfiguration) {
        Write-ProdicloudShowSectionHeader -Text "Target-Derived Configuration"
        Write-ProdicloudShowKeyValueRow -Label "Resource group" -Value ([string]$Dump.TargetDerivedConfiguration.ResourceGroup) -Indent 2
        Write-ProdicloudShowKeyValueRow -Label "VM name" -Value ([string]$Dump.TargetDerivedConfiguration.VmName) -Indent 2
        foreach ($key in @($Dump.TargetDerivedConfiguration.Summary.Keys)) {
            Write-ProdicloudShowKeyValueRow -Label ([string]$key) -Value ($Dump.TargetDerivedConfiguration.Summary[[string]$key]) -Indent 2
        }
        if (@($Dump.TargetDerivedConfiguration.SkippedFeatureKeys).Count -gt 0) {
            Write-ProdicloudShowKeyValueRow -Label "Skipped feature keys" -Value (@($Dump.TargetDerivedConfiguration.SkippedFeatureKeys)) -Indent 2
        }
    }

    Write-ProdicloudShowSectionHeader -Text "Global And Active VC Configuration Values"
    $envValues = $Dump.Config.DotEnvValues
    if ($envValues -and $envValues.Count -gt 0) {
        foreach ($key in @($envValues.Keys | Sort-Object)) {
            Write-ProdicloudShowKeyValueRow -Label ([string]$key) -Value (ConvertTo-ProdicloudShowConfigDisplayValue -Key ([string]$key) -Value ($envValues[$key])) -Indent 2
        }
    }
    else {
        Write-ProdicloudShowKeyValueRow -Label "values" -Value "(empty)" -Indent 2
    }

    Write-ProdicloudShowSectionHeader -Text "Runtime Overrides"
    $overrideValues = $Dump.Config.RuntimeOverrides
    if ($overrideValues -and $overrideValues.Count -gt 0) {
        foreach ($key in @($overrideValues.Keys | Sort-Object)) {
            Write-ProdicloudShowKeyValueRow -Label ([string]$key) -Value (ConvertTo-ProdicloudShowConfigDisplayValue -Key ([string]$key) -Value ($overrideValues[$key])) -Indent 2
        }
    }
    else {
        Write-ProdicloudShowKeyValueRow -Label "values" -Value "(empty)" -Indent 2
    }

    Write-ProdicloudShowSectionHeader -Text "Resource Groups"
    $groupIndex = 0
    foreach ($group in @(ConvertTo-ObjectArrayCompat -InputObject $Dump.ResourceGroups)) {
        $groupIndex++
        Write-Host ""
        Write-Host ("[{0}] Resource Group: {1}" -f $groupIndex, [string]$group.Name) -ForegroundColor Yellow
        Write-ProdicloudShowKeyValueRow -Label "Exists" -Value ([bool]$group.Exists) -Indent 2
        Write-ProdicloudShowKeyValueRow -Label "Location" -Value ([string]$group.Location) -Indent 2
        Write-ProdicloudShowKeyValueRow -Label "Provisioning state" -Value ([string]$group.ProvisioningState) -Indent 2
        Write-ProdicloudShowKeyValueRow -Label "Resource count" -Value ([int]$group.ResourceCount) -Indent 2
        Write-ProdicloudShowKeyValueRow -Label "VM count" -Value ([int]$group.VmCount) -Indent 2

        $typeCountMap = $group.ResourceTypeCounts
        if ($typeCountMap -and $typeCountMap.Count -gt 0) {
            Write-Host "  Resource types:"
            foreach ($typeKey in @($typeCountMap.Keys | Sort-Object)) {
                Write-ProdicloudShowKeyValueRow -Label ([string]$typeKey) -Value ([int]$typeCountMap[$typeKey]) -Indent 4
            }
        }
        else {
            Write-ProdicloudShowKeyValueRow -Label "Resource types" -Value "(none)" -Indent 2
        }

        $resourceRows = @(
            ConvertTo-ObjectArrayCompat -InputObject $group.Resources |
                ForEach-Object {
                    $resourceName = [string]$_.name
                    $resourceType = [string]$_.type
                    $resourceLocation = [string]$_.location
                    if ([string]::IsNullOrWhiteSpace([string]$resourceLocation)) {
                        return ("{0} ({1})" -f $resourceName, $resourceType)
                    }
                    return ("{0} ({1}, {2})" -f $resourceName, $resourceType, $resourceLocation)
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        if ($resourceRows.Count -gt 0) {
            Write-Host "  Resources:"
            foreach ($resourceRow in @($resourceRows)) {
                Write-Host ("    - {0}" -f [string]$resourceRow)
            }
        }
        else {
            Write-ProdicloudShowKeyValueRow -Label "Resources" -Value "(none)" -Indent 2
        }

        $vmRows = @(ConvertTo-ObjectArrayCompat -InputObject $group.Vms)
        if ($vmRows.Count -eq 0) {
            Write-ProdicloudShowKeyValueRow -Label "VM details" -Value "(none)" -Indent 2
            continue
        }

        Write-Host "  VM details:"
        $vmIndex = 0
        foreach ($vm in @($vmRows)) {
            $vmIndex++
            Write-Host ("    [{0}] VM: {1}" -f $vmIndex, [string]$vm.Name) -ForegroundColor Green
            Write-ProdicloudShowKeyValueRow -Label "Power state" -Value ([string]$vm.PowerState) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "Provisioning state" -Value ([string]$vm.ProvisioningState) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "Location" -Value ([string]$vm.Location) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "Size (SKU)" -Value ([string]$vm.VmSize) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "SKU availability (subscription)" -Value ([string]$vm.SkuAvailability) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "OS type" -Value ([string]$vm.OsType) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "Public IPs" -Value ([string]$vm.PublicIps) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "Private IPs" -Value ([string]$vm.PrivateIps) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "FQDNs" -Value ([string]$vm.Fqdns) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "OS disk" -Value ([string]$vm.OsDiskName) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "Data disks" -Value (@($vm.DataDiskNames)) -Indent 6
            Write-ProdicloudShowKeyValueRow -Label "NIC ids" -Value (@($vm.NicIds)) -Indent 6

            $hibernationEnabled = $null
            if ($vm.FeatureFlags -and $vm.FeatureFlags.Contains('HibernationEnabled')) {
                $hibernationEnabled = $vm.FeatureFlags.HibernationEnabled
            }
            Write-ProdicloudShowKeyValueRow -Label "Hibernation enabled" -Value $hibernationEnabled -Indent 6

            $nestedAvailableToGuest = $null
            if ($vm.FeatureFlags -and $vm.FeatureFlags.Contains('NestedVirtualizationAvailableToGuest')) {
                $nestedAvailableToGuest = $vm.FeatureFlags.NestedVirtualizationAvailableToGuest
            }
            Write-ProdicloudShowKeyValueRow -Label "Nested virtualization available to guest" -Value $nestedAvailableToGuest -Indent 6

            $nestedAzureSetting = $null
            if ($vm.FeatureFlags -and $vm.FeatureFlags.Contains('NestedVirtualizationAzureSetting')) {
                $nestedAzureSetting = $vm.FeatureFlags.NestedVirtualizationAzureSetting
            }
            Write-ProdicloudShowKeyValueRow -Label "Nested virtualization Azure setting" -Value $nestedAzureSetting -Indent 6

            $nestedValidationSource = ''
            if ($vm.FeatureFlags -and $vm.FeatureFlags.Contains('NestedVirtualizationValidationSource')) {
                $nestedValidationSource = [string]$vm.FeatureFlags.NestedVirtualizationValidationSource
            }
            Write-ProdicloudShowKeyValueRow -Label "Nested virtualization validation source" -Value $nestedValidationSource -Indent 6

            $nestedValidationEvidence = @()
            if ($vm.FeatureFlags -and $vm.FeatureFlags.Contains('NestedVirtualizationEvidence')) {
                $nestedValidationEvidence = @($vm.FeatureFlags.NestedVirtualizationEvidence)
            }
            Write-ProdicloudShowKeyValueRow -Label "Nested virtualization guest evidence" -Value $nestedValidationEvidence -Indent 6

            $nestedValidationError = ''
            if ($vm.FeatureFlags -and $vm.FeatureFlags.Contains('NestedVirtualizationValidationError')) {
                $nestedValidationError = [string]$vm.FeatureFlags.NestedVirtualizationValidationError
            }
            Write-ProdicloudShowKeyValueRow -Label "Nested virtualization validation error" -Value $nestedValidationError -Indent 6

            $nestedCapabilityRows = @(
                ConvertTo-ObjectArrayCompat -InputObject $vm.FocusedCapabilities |
                    Where-Object {
                        $capName = [string]$_.name
                        -not [string]::IsNullOrWhiteSpace([string]$capName) -and $capName.ToLowerInvariant().Contains("nested")
                    } |
                    ForEach-Object { "{0}={1}" -f ([string]$_.name), ([string]$_.value) }
            )
            Write-ProdicloudShowKeyValueRow -Label "Nested virtualization capabilities" -Value $nestedCapabilityRows -Indent 6

            $focusedCaps = @(
                ConvertTo-ObjectArrayCompat -InputObject $vm.FocusedCapabilities |
                    ForEach-Object { "{0}={1}" -f ([string]$_.name), ([string]$_.value) }
            )
            Write-ProdicloudShowKeyValueRow -Label "Focused capabilities" -Value $focusedCaps -Indent 6
        }
    }
}
