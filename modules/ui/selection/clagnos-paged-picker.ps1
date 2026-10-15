# Shared numbered picker with stable, page-aware indices for console users.

function Read-ClagnosNumberedChoice {
    param([string]$Prompt)

    if ($null -ne (Get-Command Read-ClagnosUiMenuChoice -ErrorAction SilentlyContinue)) {
        return [string](Read-ClagnosUiMenuChoice -Prompt $Prompt)
    }
    if ($null -ne (Get-Command Read-ClagnosUiChoice -ErrorAction SilentlyContinue)) {
        return [string](Read-ClagnosUiChoice -Prompt $Prompt)
    }
    return ([string](Read-Host $Prompt)).Trim()
}

function Select-ClagnosNumberedOptionPage {
    param(
        [object[]]$Options,
        [string]$Prompt = 'Select an option',
        [string]$DefaultValue = '',
        [ValidateRange(5,30)][int]$PageSize = 12,
        [switch]$WizardControls,
        [string[]]$ExtraKeys = @(),
        [hashtable]$ExtraKeyLabels = @{}
    )

    $normalizedOptions = @()
    foreach ($option in @(ConvertTo-ObjectArrayCompat -InputObject $Options)) {
        if ($null -eq $option) { continue }
        $value = if ($option.PSObject.Properties.Match('Value').Count -gt 0) { [string]$option.Value } else { [string]$option.name }
        $label = if ($option.PSObject.Properties.Match('Label').Count -gt 0) { [string]$option.Label } else { $value }
        $detail = if ($option.PSObject.Properties.Match('Detail').Count -gt 0) { [string]$option.Detail } else { '' }
        $enabled = if ($option.PSObject.Properties.Match('Enabled').Count -gt 0) { [bool]$option.Enabled } else { $true }
        if ([string]::IsNullOrWhiteSpace([string]$value)) { continue }
        $normalizedOptions += [pscustomobject]@{ Value = $value; Label = $label; Detail = $detail; Enabled = $enabled }
    }

    if (@($normalizedOptions).Count -eq 0) {
        return [pscustomobject]@{ Action = 'empty'; Value = ''; Index = 0 }
    }

    $defaultIndex = 0
    for ($index = 0; $index -lt $normalizedOptions.Count; $index++) {
        if ([string]::Equals([string]$normalizedOptions[$index].Value, [string]$DefaultValue, [System.StringComparison]::OrdinalIgnoreCase)) {
            $defaultIndex = $index + 1
            break
        }
    }
    $pageCount = [int][Math]::Ceiling([double]$normalizedOptions.Count / [double]$PageSize)
    $pageNumber = if ($defaultIndex -gt 0) { [int][Math]::Ceiling([double]$defaultIndex / [double]$PageSize) } else { 1 }

    while ($true) {
        Write-Host ''
        Write-Host $Prompt -ForegroundColor Cyan
        $startIndex = ($pageNumber - 1) * $PageSize
        $endIndex = [Math]::Min($normalizedOptions.Count, $startIndex + $PageSize)
        for ($index = $startIndex; $index -lt $endIndex; $index++) {
            $absoluteNumber = $index + 1
            $marker = if ($absoluteNumber -eq $defaultIndex) { '>' } else { ' ' }
            $detailText = if ([string]::IsNullOrWhiteSpace([string]$normalizedOptions[$index].Detail)) { '' } else { (' | {0}' -f [string]$normalizedOptions[$index].Detail) }
            $availabilityText = if ([bool]$normalizedOptions[$index].Enabled) { '' } else { ' [unavailable]' }
            Write-Host ('{0}{1}. {2}{3}{4}' -f $marker, $absoluteNumber, [string]$normalizedOptions[$index].Label, $detailText, $availabilityText)
        }
        if ($pageCount -gt 1) {
            Write-Host ('Page {0}/{1} ({2} options)' -f $pageNumber, $pageCount, $normalizedOptions.Count) -ForegroundColor DarkGray
            Write-Host 'p: previous page | n: next page | g: go to page | f: first page | t: last page'
        }
        if ($WizardControls) {
            Write-Host 's: skip | k: skip all remaining | a: apply default | l: apply all defaults | c: close wizard'
        }
        else {
            $hasCloseExtra = @($ExtraKeys | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains 'c'
            if ($hasCloseExtra) { Write-Host 'b/Esc: back | q: quit' }
            else { Write-Host 'b/Esc: back | c: close current flow | q: quit' }
        }
        if (@($ExtraKeys).Count -gt 0) {
            $extraLabels = @($ExtraKeys | ForEach-Object {
                $key = ([string]$_).ToLowerInvariant()
                $label = if ($ExtraKeyLabels.ContainsKey($key)) { [string]$ExtraKeyLabels[$key] } else { 'additional choice' }
                '{0}: {1}' -f $key, $label
            })
            Write-Host ($extraLabels -join ' | ') -ForegroundColor DarkGray
        }

        $choice = ([string](Read-ClagnosNumberedChoice -Prompt ('Enter option number or page key for {0}' -f $Prompt))).Trim()
        if ($WizardControls) {
            switch ($choice.ToLowerInvariant()) {
                'b' { return [pscustomobject]@{ Action = 'close'; Value = ''; Index = 0 } }
                's' { return [pscustomobject]@{ Action = 'skip'; Value = [string]$DefaultValue; Index = $defaultIndex } }
                'k' { return [pscustomobject]@{ Action = 'skip-all'; Value = [string]$DefaultValue; Index = $defaultIndex } }
                'a' {
                    if ($defaultIndex -gt 0 -and [bool]$normalizedOptions[$defaultIndex - 1].Enabled) { return [pscustomobject]@{ Action = 'apply-default'; Value = [string]$normalizedOptions[$defaultIndex - 1].Value; Index = $defaultIndex } }
                    Write-Host 'There is no default to apply on this step; select a numbered option or skip it.' -ForegroundColor Yellow
                    continue
                }
                'l' { return [pscustomobject]@{ Action = 'apply-all'; Value = [string]$DefaultValue; Index = $defaultIndex } }
                'c' { return [pscustomobject]@{ Action = 'close'; Value = ''; Index = 0 } }
            }
        }
        elseif ($choice -in @('b','q')) {
            return [pscustomobject]@{ Action = 'back'; Input = $choice.ToLowerInvariant(); Value = ''; Index = 0 }
        }
        if (@($ExtraKeys | ForEach-Object { ([string]$_).ToLowerInvariant() }) -contains $choice.ToLowerInvariant()) {
            return [pscustomobject]@{ Action = 'extra'; ExtraKey = $choice.ToLowerInvariant(); Value = ''; Index = 0 }
        }
        if (-not $WizardControls -and $choice -eq 'c') {
            return [pscustomobject]@{ Action = 'close'; Input = 'c'; Value = ''; Index = 0 }
        }

        switch ($choice.ToLowerInvariant()) {
            'p' {
                if ($pageCount -gt 1) { $pageNumber = [Math]::Max(1, $pageNumber - 1) }
                else { Write-Host 'This list has one page.' -ForegroundColor Yellow }
                continue
            }
            'n' {
                if ($pageCount -gt 1) { $pageNumber = [Math]::Min($pageCount, $pageNumber + 1) }
                else { Write-Host 'This list has one page.' -ForegroundColor Yellow }
                continue
            }
            'f' {
                if ($pageCount -gt 1) { $pageNumber = 1; continue }
            }
            't' {
                if ($pageCount -gt 1) { $pageNumber = $pageCount; continue }
            }
            'g' {
                if ($pageCount -gt 1) {
                    $pageText = ([string](Read-ClagnosNumberedChoice -Prompt ("Go to page (1-{0})" -f $pageCount))).Trim()
                    $requestedPage = 0
                    if ([int]::TryParse($pageText, [ref]$requestedPage) -and $requestedPage -ge 1 -and $requestedPage -le $pageCount) {
                        $pageNumber = $requestedPage
                    }
                    else {
                        Write-Host ('Page must be a number from 1 to {0}.' -f $pageCount) -ForegroundColor Yellow
                    }
                    continue
                }
            }
        }

        $selectedNumber = 0
        if ([int]::TryParse($choice, [ref]$selectedNumber) -and $selectedNumber -ge $startIndex + 1 -and $selectedNumber -le $endIndex) {
            if (-not [bool]$normalizedOptions[$selectedNumber - 1].Enabled) {
                Write-Host 'This option is not available for the active subscription or selected context.' -ForegroundColor Yellow
                continue
            }
            return [pscustomobject]@{ Action = 'selected'; Value = [string]$normalizedOptions[$selectedNumber - 1].Value; Index = $selectedNumber }
        }
        if ([int]::TryParse($choice, [ref]$selectedNumber) -and $selectedNumber -ge 1 -and $selectedNumber -le $normalizedOptions.Count) {
            Write-Host ('Choose a number shown on the current page ({0}-{1}), or navigate to its page first.' -f ($startIndex + 1), $endIndex) -ForegroundColor Yellow
            continue
        }
        if ([string]::IsNullOrWhiteSpace($choice) -and $defaultIndex -ge ($startIndex + 1) -and $defaultIndex -le $endIndex) {
            if ([bool]$normalizedOptions[$defaultIndex - 1].Enabled) {
                return [pscustomobject]@{ Action = 'selected'; Value = [string]$normalizedOptions[$defaultIndex - 1].Value; Index = $defaultIndex }
            }
            Write-Host 'The marked default is unavailable. Choose an available option.' -ForegroundColor Yellow
        }
        elseif ([string]::IsNullOrWhiteSpace($choice) -and $defaultIndex -gt 0) {
            $defaultPage = [int][Math]::Ceiling([double]$defaultIndex / [double]$PageSize)
            Write-Host ('The default is on page {0}; navigate to that page or select a number shown here.' -f $defaultPage) -ForegroundColor Yellow
        }
        Write-Host ('Select an option number from 1 to {0} or use a listed navigation key.' -f $normalizedOptions.Count) -ForegroundColor Yellow
    }
}
