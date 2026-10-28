# UI region and location picker helpers.

# Handles Get-PriceHoursFromConfig.
function Get-PriceHoursFromConfig {
    param(
        [hashtable]$Config,
        [int]$DefaultHours = 730
    )

    $hoursText = Get-ConfigValue -Config $Config -Key "VM_PRICE_COUNT_HOURS" -DefaultValue "$DefaultHours"
    if ($hoursText -match '^\d+$') {
        $hours = [int]$hoursText
        if ($hours -gt 0) {
            return $hours
        }
    }

    return $DefaultHours
}

# Handles Get-AzLocationCatalog.
function Get-AzLocationCatalog {
    $locationsJson = Invoke-ProdicloudWithBypassedAzCliSubscription -Action {
        az account list-locations `
            --only-show-errors `
            --query "[?metadata.regionType=='Physical'].{Name:name,DisplayName:displayName,RegionType:metadata.regionType}" `
            -o json
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($locationsJson)) {
        Throw-FriendlyError `
            -Detail "az account list-locations failed with exit code $LASTEXITCODE." `
            -Code 26 `
            -Summary "Azure region list could not be loaded." `
            -Hint "Run az login and verify subscription access."
    }

    $locations = ConvertFrom-JsonArrayCompat -InputObject $locationsJson
    if (-not $locations -or $locations.Count -eq 0) {
        $alternateLocationsJson = Invoke-ProdicloudWithBypassedAzCliSubscription -Action {
            az account list-locations `
                --only-show-errors `
                --query "[].{Name:name,DisplayName:displayName,RegionType:metadata.regionType}" `
                -o json
        }
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($alternateLocationsJson)) {
            $alternateLocations = ConvertFrom-JsonArrayCompat -InputObject $alternateLocationsJson
            $locations = @($alternateLocations | Where-Object { $_.RegionType -eq "Physical" })
        }
    }
    if (-not $locations -or $locations.Count -eq 0) {
        Throw-FriendlyError `
            -Detail "Azure returned an empty physical deployment region list." `
            -Code 26 `
            -Summary "Azure region list could not be loaded." `
            -Hint "Check Azure account/subscription context and location metadata availability."
    }

    return (ConvertTo-ObjectArrayCompat -InputObject @($locations | Sort-Object DisplayName, Name))
    return
}

# Handles Write-RegionSelectionGrid.
function Write-RegionSelectionGrid {
    param(
        [object[]]$Locations,
        [int]$DefaultIndex,
        [int]$Columns = 9
    )

    if (-not $Locations -or $Locations.Count -eq 0) {
        return
    }

    if ($Columns -lt 1) {
        $Columns = 1
    }

    $labels = @()
    for ($i = 0; $i -lt $Locations.Count; $i++) {
        $regionName = [string]$Locations[$i].Name
        $isDefault = (($i + 1) -eq $DefaultIndex)
        if ($isDefault) {
            $labels += ("*{0}-{1}." -f ($i + 1), $regionName)
        }
        else {
            $labels += ("{0}-{1}." -f ($i + 1), $regionName)
        }
    }

    $maxLength = ($labels | Measure-Object -Property Length -Maximum).Maximum
    $cellWidth = [int]$maxLength + 3

    for ($start = 0; $start -lt $labels.Count; $start += $Columns) {
        $end = [math]::Min($start + $Columns - 1, $labels.Count - 1)
        $lineBuilder = New-Object System.Text.StringBuilder
        for ($idx = $start; $idx -le $end; $idx++) {
            [void]$lineBuilder.Append(($labels[$idx]).PadRight($cellWidth))
        }
        Write-Host $lineBuilder.ToString().TrimEnd()
    }

}

# Handles Resolve-ProdicloudLocationNameFromEntry.
function Resolve-ProdicloudLocationNameFromEntry {
    param(
        [object]$Entry,
        [object[]]$Catalog,
        [string]$DefaultLocation = ''
    )

    $nameCandidates = @()
    if ($null -ne $Entry) {
        $nameCandidates += @(
            [string]$Entry.Name,
            [string]$Entry.name,
            [string]$Entry.Location,
            [string]$Entry.location
        )
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$DefaultLocation)) {
        $nameCandidates += @([string]$DefaultLocation)
    }

    foreach ($candidateRaw in @($nameCandidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateRaw)) {
            continue
        }

        $candidate = ([string]$candidateRaw).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        if ($Catalog -and @($Catalog).Count -gt 0) {
            $matched = @($Catalog | Where-Object {
                [string]::Equals(([string]$_.Name), $candidate, [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals(([string]$_.name), $candidate, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1)
            if ($matched.Count -gt 0) {
                $matchedName = [string]$matched[0].Name
                if ([string]::IsNullOrWhiteSpace([string]$matchedName)) {
                    $matchedName = [string]$matched[0].name
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$matchedName)) {
                    return $matchedName.Trim().ToLowerInvariant()
                }
            }
        }
        else {
            return $candidate
        }
    }

    if ($null -ne $Entry) {
        $displayName = [string]$Entry.DisplayName
        if ([string]::IsNullOrWhiteSpace([string]$displayName)) {
            $displayName = [string]$Entry.displayName
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$displayName) -and $Catalog) {
            $matchByDisplay = @($Catalog | Where-Object {
                [string]::Equals(([string]$_.DisplayName), $displayName, [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals(([string]$_.displayName), $displayName, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1)
            if ($matchByDisplay.Count -gt 0) {
                $matchName = [string]$matchByDisplay[0].Name
                if ([string]::IsNullOrWhiteSpace([string]$matchName)) {
                    $matchName = [string]$matchByDisplay[0].name
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$matchName)) {
                    return $matchName.Trim().ToLowerInvariant()
                }
            }
        }
    }

    return ''
}

# Handles Select-AzLocationInteractive.
function Select-AzLocationInteractive {
    param(
        [string]$DefaultLocation
    )

    $locations = @(Get-AzLocationCatalog)
    $options = @(
        $locations | ForEach-Object {
            $name = [string]$_.Name
            $label = if ([string]::IsNullOrWhiteSpace([string]$_.DisplayName)) { $name } else { [string]$_.DisplayName }
            [pscustomobject]@{ Value = $name; Label = $label; Detail = $name }
        }
    )
    $selection = Select-ProdicloudNumberedOptionPage -Options $options -Prompt 'Available Azure regions' -DefaultValue $DefaultLocation -PageSize 12
    if ([string]$selection.Action -eq 'selected') { return [string]$selection.Value }
    if (-not [string]::IsNullOrWhiteSpace([string]$DefaultLocation)) { return [string]$DefaultLocation }
    if (@($options).Count -gt 0) { return [string]$options[0].Value }
    return ''
}
