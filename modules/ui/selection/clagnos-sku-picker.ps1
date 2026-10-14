# UI SKU picker helpers.

# Handles Convert-ToSkuSearchPattern.
function Convert-ToSkuSearchPattern {
    param(
        [string]$FilterText
    )

    if ([string]::IsNullOrWhiteSpace($FilterText)) {
        return ""
    }

    $trimmed = $FilterText.Trim()
    return "*" + $trimmed + "*"
}

# Handles Test-SkuWildcardMatchOrdinalIgnoreCase.
function Test-SkuWildcardMatchOrdinalIgnoreCase {
    param(
        [string]$Text,
        [string]$Pattern
    )

    if ($null -eq $Text) {
        $Text = ""
    }
    if ($null -eq $Pattern) {
        $Pattern = ""
    }

    $textIndex = 0
    $patternIndex = 0
    $lastStarIndex = -1
    $starMatchTextIndex = 0

    while ($textIndex -lt $Text.Length) {
        if ($patternIndex -lt $Pattern.Length) {
            $patternChar = $Pattern[$patternIndex]
            $textChar = $Text[$textIndex]

            if ($patternChar -eq '?') {
                $textIndex++
                $patternIndex++
                continue
            }

            if ([string]::Equals([string]$textChar, [string]$patternChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                $textIndex++
                $patternIndex++
                continue
            }

            if ($patternChar -eq '*') {
                $lastStarIndex = $patternIndex
                $starMatchTextIndex = $textIndex
                $patternIndex++
                continue
            }
        }

        if ($lastStarIndex -ne -1) {
            $patternIndex = $lastStarIndex + 1
            $starMatchTextIndex++
            $textIndex = $starMatchTextIndex
            continue
        }

        return $false
    }

    while ($patternIndex -lt $Pattern.Length -and $Pattern[$patternIndex] -eq '*') {
        $patternIndex++
    }

    return ($patternIndex -eq $Pattern.Length)
}

# Handles Get-LocationSkusForSelection.
function Get-LocationSkusForSelection {
    param(
        [string]$Location,
        [string]$SkuLike
    )

    $filterText = ""
    if (-not [string]::IsNullOrWhiteSpace($SkuLike)) {
        $filterText = $SkuLike.Trim()
    }

    $raw = az vm list-sizes -l $Location --only-show-errors -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        Throw-FriendlyError `
            -Detail "az vm list-sizes failed for location '$Location' with exit code $LASTEXITCODE." `
            -Code 27 `
            -Summary "VM size list could not be loaded for the selected region." `
            -Hint "Verify the selected region and Azure subscription permissions."
    }

    $allSkus = ConvertFrom-JsonArrayCompat -InputObject $raw
    $namedSkus = @(
        $allSkus | Where-Object {
            $_.name
        }
    )

    if ($filterText -eq "") {
        return (ConvertTo-ObjectArrayCompat -InputObject @($namedSkus | Sort-Object name -Unique))
        return
    }

    $effectivePattern = Convert-ToSkuSearchPattern -FilterText $filterText
    $filtered = foreach ($sku in $namedSkus) {
        $name = [string]$sku.name
        if (Test-SkuWildcardMatchOrdinalIgnoreCase -Text $name -Pattern $effectivePattern) {
            $sku
        }
    }

    return (ConvertTo-ObjectArrayCompat -InputObject @($filtered | Sort-Object name -Unique))
    return
}

# Handles Get-SkuAvailabilityMap.
function Get-SkuAvailabilityMap {
    param(
        [string]$Location,
        [string[]]$SkuNames
    )

    $result = @{}
    if (-not $SkuNames -or $SkuNames.Count -eq 0) {
        return $result
    }

    $targetSkuSet = @{}
    foreach ($skuName in $SkuNames) {
        if (-not [string]::IsNullOrWhiteSpace($skuName)) {
            $targetSkuSet[$skuName.ToLowerInvariant()] = $true
        }
    }

    $subscriptionId = az account show --only-show-errors --query id -o tsv
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($subscriptionId)) {
        Throw-FriendlyError `
            -Detail "az account show failed while resolving subscription for SKU availability." `
            -Code 24 `
            -Summary "SKU availability pre-check could not be completed." `
            -Hint "Run az login and verify active subscription."
    }

    $tokenJson = az account get-access-token --only-show-errors --resource https://management.azure.com/ -o json
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tokenJson)) {
        Throw-FriendlyError `
            -Detail "az account get-access-token failed while resolving SKU availability." `
            -Code 24 `
            -Summary "SKU availability pre-check could not be completed." `
            -Hint "Verify Azure CLI authentication and token permissions."
    }

    $accessToken = (ConvertFrom-JsonCompat -InputObject $tokenJson).accessToken
    if ([string]::IsNullOrWhiteSpace($accessToken)) {
        Throw-FriendlyError `
            -Detail "Azure access token is empty for SKU availability request." `
            -Code 24 `
            -Summary "SKU availability pre-check could not be completed." `
            -Hint "Refresh Azure login session and retry."
    }

    $filter = [uri]::EscapeDataString("location eq '$Location'")
    $url = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/skus?api-version=2023-07-01&`$filter=$filter"

    try {
        $response = Invoke-ClagnosHttpRestMethod `
            -Method Get `
            -Uri $url `
            -Headers @{ Authorization = "Bearer $accessToken" } `
            -PerfLabel ("http compute skus list (location={0})" -f [string]$Location)
    }
    catch {
        Throw-FriendlyError `
            -Detail "Resource SKU API call failed for availability check in '$Location'." `
            -Code 24 `
            -Summary "SKU availability pre-check could not be completed." `
            -Hint "Check Azure REST access and subscription permissions."
    }

    $items = @(
        (ConvertTo-ObjectArrayCompat -InputObject $response.value) |
            Where-Object { $_.resourceType -eq "virtualMachines" }
    )
    foreach ($item in $items) {
        if (-not $item.name) { continue }
        $itemName = [string]$item.name
        $skuKey = $itemName.ToLowerInvariant()
        if (-not $targetSkuSet.ContainsKey($skuKey)) { continue }

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
        if ($isUnavailable -or -not $locationInfo) {
            $result[$itemName] = "no"
        }
        else {
            $result[$itemName] = "yes"
        }
    }

    return $result
}

# Handles Get-SkuPriceMap.
function Get-SkuPriceMap {
    param(
        [string]$Location,
        [string[]]$SkuNames
    )

    $result = @{}
    if (-not $SkuNames -or $SkuNames.Count -eq 0) {
        return $result
    }

    $catalog = Get-ClagnosRetailPricingCatalogForLocation -Location $Location
    foreach ($skuName in $SkuNames) {
        if ([string]::IsNullOrWhiteSpace([string]$skuName)) {
            continue
        }

        $skuKey = ([string]$skuName).ToLowerInvariant()
        if ($catalog.ContainsKey($skuKey)) {
            $result[[string]$skuName] = $catalog[$skuKey]
        }
    }

    return $result
}

# Handles Get-ClagnosHttpStatusCode.
function Get-ClagnosHttpStatusCode {
    param(
        [object]$ExceptionObject
    )

    if ($null -eq $ExceptionObject) {
        return $null
    }

    $statusCodeValue = $null
    $response = $null
    if ($ExceptionObject.PSObject.Properties.Match('Response').Count -gt 0) {
        $response = $ExceptionObject.Response
    }

    if ($null -ne $response -and $response.PSObject.Properties.Match('StatusCode').Count -gt 0 -and $null -ne $response.StatusCode) {
        try {
            $statusCodeValue = [int]$response.StatusCode
        }
        catch {
            try {
                $statusCodeValue = [int]$response.StatusCode.value__
            }
            catch {
                $statusCodeValue = $null
            }
        }
    }

    if ($null -eq $statusCodeValue -and $ExceptionObject.PSObject.Properties.Match('StatusCode').Count -gt 0 -and $null -ne $ExceptionObject.StatusCode) {
        try {
            $statusCodeValue = [int]$ExceptionObject.StatusCode
        }
        catch {
            try {
                $statusCodeValue = [int]$ExceptionObject.StatusCode.value__
            }
            catch {
                $statusCodeValue = $null
            }
        }
    }

    return $statusCodeValue
}

# Handles Get-ClagnosHttpRetryAfterSeconds.
function Get-ClagnosHttpRetryAfterSeconds {
    param(
        [object]$ExceptionObject
    )

    if ($null -eq $ExceptionObject) {
        return $null
    }

    $response = $null
    if ($ExceptionObject.PSObject.Properties.Match('Response').Count -gt 0) {
        $response = $ExceptionObject.Response
    }

    if ($null -eq $response) {
        return $null
    }

    $headers = $null
    if ($response.PSObject.Properties.Match('Headers').Count -gt 0) {
        $headers = $response.Headers
    }
    if ($null -eq $headers) {
        return $null
    }

    $retryAfterRaw = $null
    try {
        $retryAfterRaw = $headers['Retry-After']
    }
    catch {
        $retryAfterRaw = $null
    }
    if ([string]::IsNullOrWhiteSpace([string]$retryAfterRaw)) {
        try {
            $retryAfterValues = $headers.GetValues('Retry-After')
            if ($retryAfterValues -and $retryAfterValues.Count -gt 0) {
                $retryAfterRaw = [string]$retryAfterValues[0]
            }
        }
        catch {
            $retryAfterRaw = $null
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$retryAfterRaw) -and $headers.PSObject.Properties.Match('RetryAfter').Count -gt 0 -and $null -ne $headers.RetryAfter) {
        $retryAfterObject = $headers.RetryAfter
        if ($retryAfterObject.PSObject.Properties.Match('Delta').Count -gt 0 -and $null -ne $retryAfterObject.Delta) {
            try {
                return [int][math]::Ceiling([double]$retryAfterObject.Delta.TotalSeconds)
            }
            catch {}
        }
        if ($retryAfterObject.PSObject.Properties.Match('Date').Count -gt 0 -and $null -ne $retryAfterObject.Date) {
            try {
                $seconds = [int][math]::Ceiling(([datetimeoffset]$retryAfterObject.Date - [datetimeoffset]::UtcNow).TotalSeconds)
                if ($seconds -gt 0) {
                    return $seconds
                }
            }
            catch {}
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$retryAfterRaw)) {
        return $null
    }

    $numeric = 0
    if ([int]::TryParse(([string]$retryAfterRaw).Trim(), [ref]$numeric)) {
        if ($numeric -gt 0) {
            return $numeric
        }
        return $null
    }

    $retryAfterDate = [datetime]::MinValue
    if ([datetime]::TryParse([string]$retryAfterRaw, [ref]$retryAfterDate)) {
        $deltaSeconds = [int][math]::Ceiling(($retryAfterDate.ToUniversalTime() - [datetime]::UtcNow).TotalSeconds)
        if ($deltaSeconds -gt 0) {
            return $deltaSeconds
        }
    }

    return $null
}

# Handles Invoke-ClagnosRetailPricingRequest.
function Invoke-ClagnosRetailPricingRequest {
    param(
        [string]$Uri
    )

    $maxRetries = [math]::Max([int]$script:RetailPricingMaxRetries, 0)
    for ($retry = 0; $true; $retry++) {
        try {
            return Invoke-ClagnosHttpRestMethod -Method Get -Uri $Uri -PerfLabel "http retail pricing api"
        }
        catch {
            $statusCode = Get-ClagnosHttpStatusCode -ExceptionObject $_.Exception
            $isRetryable = $false
            if ($null -ne $statusCode) {
                $retryableCodes = @(429, 500, 502, 503, 504)
                if ($retryableCodes -contains ([int]$statusCode)) {
                    $isRetryable = $true
                }
            }

            if (-not $isRetryable -or $retry -ge $maxRetries) {
                throw
            }

            $retryAfterSeconds = Get-ClagnosHttpRetryAfterSeconds -ExceptionObject $_.Exception
            if ($null -eq $retryAfterSeconds -or $retryAfterSeconds -le 0) {
                $retryAfterSeconds = [int][math]::Min([math]::Pow(2, ($retry + 1)), 30)
            }
            if ($retryAfterSeconds -lt 1) {
                $retryAfterSeconds = 1
            }

            Write-ClagnosActionProgress -Action ("Retail Pricing API returned HTTP {0}; wait {1}s before retry {2}/{3}" -f $statusCode,$retryAfterSeconds,($retry + 1),$maxRetries)
            Start-Sleep -Seconds $retryAfterSeconds
        }
    }
}

# Handles Normalize-ClagnosRetailPricingNextPageLink.
function Normalize-ClagnosRetailPricingNextPageLink {
    param(
        [string]$Uri
    )

    if ([string]::IsNullOrWhiteSpace([string]$Uri)) {
        return $null
    }

    $normalized = ([string]$Uri).Trim()
    $normalized = $normalized -replace '(?i)([?&])\$top=-?\d+', '$1'
    $normalized = $normalized -replace '\?&', '?'
    $normalized = $normalized -replace '&&', '&'
    $normalized = $normalized -replace '[?&]$', ''

    if ([string]::IsNullOrWhiteSpace([string]$normalized)) {
        return $null
    }

    return $normalized
}

# Handles Get-ClagnosRetailPricingCatalogForLocation.
function Get-ClagnosRetailPricingCatalogForLocation {
    param(
        [string]$Location
    )

    if ([string]::IsNullOrWhiteSpace([string]$Location)) {
        return @{}
    }

    $locationKey = ([string]$Location).Trim().ToLowerInvariant()
    if ($script:RetailPricingCacheByLocation.ContainsKey($locationKey)) {
        return $script:RetailPricingCacheByLocation[$locationKey]
    }

    $catalog = @{}
    $baseFilter = "serviceName eq 'Virtual Machines' and armRegionName eq '$Location' and type eq 'Consumption' and unitOfMeasure eq '1 Hour'"
    $nextUri = "https://prices.azure.com/api/retail/prices?`$filter=" + [uri]::EscapeDataString($baseFilter) + "&`$top=1000"

    while ($nextUri) {
        $response = Invoke-ClagnosRetailPricingRequest -Uri $nextUri
        foreach ($item in (ConvertTo-ObjectArrayCompat -InputObject $response.Items)) {
            if (-not $item.armSkuName -or $item.unitPrice -eq $null) {
                continue
            }

            if ($item.productName -like "*Cloud Services*") {
                continue
            }
            $priceText = "$($item.productName) $($item.skuName) $($item.meterName) $($item.meterSubCategory)"
            if ($priceText -match '(?i)\bspot\b' -or $priceText -match '(?i)\blow\s+priority\b') {
                continue
            }

            $catalogKey = ([string]$item.armSkuName).ToLowerInvariant()
            if (-not $catalog.ContainsKey($catalogKey)) {
                $catalog[$catalogKey] = [ordered]@{
                    LinuxPerHour   = $null
                    WindowsPerHour = $null
                    Currency       = $item.currencyCode
                }
            }

            $entry = $catalog[$catalogKey]
            $unitPrice = [double]$item.unitPrice
            if ($item.productName -like "*Windows*") {
                if ($null -eq $entry.WindowsPerHour -or $unitPrice -lt $entry.WindowsPerHour) {
                    $entry.WindowsPerHour = $unitPrice
                }
            }
            else {
                if ($null -eq $entry.LinuxPerHour -or $unitPrice -lt $entry.LinuxPerHour) {
                    $entry.LinuxPerHour = $unitPrice
                }
            }
        }

        $nextUri = Normalize-ClagnosRetailPricingNextPageLink -Uri ([string]$response.NextPageLink)
        if ([string]::IsNullOrWhiteSpace($nextUri)) {
            $nextUri = $null
        }
        elseif ([int]$script:RetailPricingPageDelayMs -gt 0) {
            Start-Sleep -Milliseconds ([int]$script:RetailPricingPageDelayMs)
        }
    }

    $script:RetailPricingCacheByLocation[$locationKey] = $catalog
    return $catalog
}

# Handles Convert-HourlyPriceToMonthlyText.
function Convert-HourlyPriceToMonthlyText {
    param(
        [double]$PricePerHour,
        [int]$Hours
    )

    if ($PricePerHour -le 0) {
        return "N/A"
    }

    return [math]::Round(($PricePerHour * $Hours), 2)
}

# Handles Build-VmSkuSelectionRows.
function Build-VmSkuSelectionRows {
    param(
        [object[]]$Skus,
        [hashtable]$AvailabilityMap,
        [hashtable]$PriceMap,
        [int]$PriceHours
    )

    $linuxPriceColumn = "Linux_{0}h" -f $PriceHours
    $windowsPriceColumn = "Windows_{0}h" -f $PriceHours

    $rows = @()
    for ($i = 0; $i -lt $Skus.Count; $i++) {
        $sku = $Skus[$i]
        $skuName = [string]$sku.name
        $price = $null
        if ($PriceMap.ContainsKey($skuName)) {
            $price = $PriceMap[$skuName]
        }

        $availability = "unknown"
        if ($AvailabilityMap.ContainsKey($skuName)) {
            $availability = [string]$AvailabilityMap[$skuName]
        }

        $row = [ordered]@{
            No          = $i + 1
            Sku         = $skuName
            vCPU        = [int]$sku.numberOfCores
            RAM_GB      = [math]::Round(([double]$sku.memoryInMB / 1024), 2)
        }

        $linuxPrice = if ($price -and $price.LinuxPerHour -ne $null) { Convert-HourlyPriceToMonthlyText -PricePerHour $price.LinuxPerHour -Hours $PriceHours } else { "N/A" }
        $windowsPrice = if ($price -and $price.WindowsPerHour -ne $null) { Convert-HourlyPriceToMonthlyText -PricePerHour $price.WindowsPerHour -Hours $PriceHours } else { "N/A" }
        $row[$linuxPriceColumn] = $linuxPrice
        $row[$windowsPriceColumn] = $windowsPrice
        $row["CreateReady"] = $availability

        $rows += [PSCustomObject]$row
    }

    return (ConvertTo-ObjectArrayCompat -InputObject $rows)
    return
}

# Handles Read-StrictYesNo.
function Read-StrictYesNo {
    param(
        [string]$PromptText
    )

    while ($true) {
        $raw = Read-Host ("{0} (y/n)" -f $PromptText)
        if ($null -eq $raw) {
            $raw = ""
        }

        $value = $raw.Trim().ToLowerInvariant()
        if ($value -eq "y") {
            return $true
        }
        if ($value -eq "n") {
            return $false
        }

        Write-Host "Invalid choice. Please enter 'y' or 'n'." -ForegroundColor Yellow
    }
}

# Handles Get-ClagnosSkuPickerRegionBackToken.
function Get-ClagnosSkuPickerRegionBackToken {
    return "__CLAGNOS_PICK_REGION_AGAIN__"
}

# Handles Select-VmSkuInteractive.
function Select-VmSkuInteractive {
    param(
        [string]$Location,
        [string]$DefaultVmSize,
        [int]$PriceHours
    )

    while ($true) {
        $skuLikeRaw = Read-Host "Enter partial VM type (supports * and ?, examples: b2a, standard_a*, standard_b?a*v2). Leave empty to list all"
        if ($null -eq $skuLikeRaw) {
            $skuLikeRaw = ""
        }
        $skuLike = $skuLikeRaw.Trim()

        $skus = Get-LocationSkusForSelection -Location $Location -SkuLike $skuLike
        $effectiveFilter = if ([string]::IsNullOrWhiteSpace($skuLike)) { "<all>" } else { $skuLike }
        Write-Host ("Partial VM type filter received: {0}" -f $effectiveFilter) -ForegroundColor DarkGray
        Write-Host ("Matching SKU count: {0}" -f @($skus).Count) -ForegroundColor DarkGray
        if (-not $skus -or $skus.Count -eq 0) {
            Write-Host "No matching VM SKU found for '$skuLike' in '$Location'. Try another filter." -ForegroundColor Yellow
            continue
        }

        $skuNames = @($skus | ForEach-Object { [string]$_.name })
        $availabilityMap = Get-SkuAvailabilityMap -Location $Location -SkuNames $skuNames
        $priceMap = @{}
        try {
            $priceMap = Get-SkuPriceMap -Location $Location -SkuNames $skuNames
        }
        catch {
            Write-Warning "Price API lookup failed. Pricing columns will be shown as N/A. Detail: $($_.Exception.Message)"
        }

        Write-Host ""
        Write-Host ("Available VM SKUs in region '{0}' (prices use {1} hours/month):" -f $Location, $PriceHours) -ForegroundColor Cyan
        $rows = @(Build-VmSkuSelectionRows -Skus $skus -AvailabilityMap $availabilityMap -PriceMap $priceMap -PriceHours $PriceHours)
        $linuxPriceProperty = 'Linux_{0}h' -f $PriceHours
        $windowsPriceProperty = 'Windows_{0}h' -f $PriceHours
        $pickerOptions = @(
            $rows | ForEach-Object {
                $detail = ('{0} vCPU | {1} GB RAM | {2} | {3}' -f [int]$_.vCPU, [double]$_.RAM_GB, [string]$_.$linuxPriceProperty, [string]$_.$windowsPriceProperty)
                [pscustomobject]@{ Value = [string]$_.Sku; Label = [string]$_.Sku; Detail = $detail }
            }
        )
        $selection = Select-ClagnosNumberedOptionPage -Options $pickerOptions -Prompt ("Available VM SKUs in region '{0}' (prices use {1} hours/month)" -f $Location, $PriceHours) -DefaultValue $DefaultVmSize -PageSize 12 -ExtraKeys @('x','r')
        if ([string]$selection.Action -eq 'extra' -and [string]$selection.ExtraKey -eq 'r') {
            Write-Host 'Returning to region selection...' -ForegroundColor DarkGray
            return (Get-ClagnosSkuPickerRegionBackToken)
        }
        if ([string]$selection.Action -eq 'extra' -and [string]$selection.ExtraKey -eq 'x') {
            continue
        }
        if ([string]$selection.Action -ne 'selected') { return (Get-ClagnosSkuPickerRegionBackToken) }

        $selectedSku = [string]$selection.Value
        $confirmSelected = Read-StrictYesNo -PromptText ("Selected VM SKU: '{0}'. Continue?" -f $selectedSku)
        if ($confirmSelected) { return $selectedSku }
        Write-Host 'Returning to VM SKU filter search...' -ForegroundColor DarkGray
    }
}
