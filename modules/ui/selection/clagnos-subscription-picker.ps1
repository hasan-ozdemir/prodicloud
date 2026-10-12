# Azure subscription selection helpers.

function Test-ClagnosSubscriptionIdFormat {
    param(
        [string]$SubscriptionId
    )

    $text = if ($null -eq $SubscriptionId) { '' } else { [string]$SubscriptionId.Trim() }
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return $false
    }

    return ($text -match '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$')
}

function Assert-ClagnosSubscriptionIdFormat {
    param(
        [string]$SubscriptionId,
        [string]$OptionSource = 'subscription selection'
    )

    if (Test-ClagnosSubscriptionIdFormat -SubscriptionId $SubscriptionId) {
        return ([string]$SubscriptionId).Trim()
    }

    Throw-FriendlyError `
        -Detail ("Invalid Azure subscription id '{0}' from {1}." -f [string]$SubscriptionId, [string]$OptionSource) `
        -Code 2 `
        -Summary 'Azure subscription id format is invalid.' `
        -Hint "Use a GUID-form Azure subscription id, for example '--subscription-id=<subscription-guid>'."
}

function Get-ClagnosAccessibleSubscriptionRows {
    $raw = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account list -o json --only-show-errors 2>$null
    }

    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        Throw-FriendlyError `
            -Detail 'Azure subscription list could not be loaded from Azure CLI.' `
            -Code 64 `
            -Summary 'Azure CLI sign-in is required.' `
            -Hint "Run 'az login' first, then retry the clagnos command."
    }

    $rows = @(
        ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $raw) |
            Where-Object { $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.id) }
    )
    if (@($rows).Count -eq 0) {
        Throw-FriendlyError `
            -Detail 'Azure CLI returned no accessible subscriptions.' `
            -Code 64 `
            -Summary 'Azure CLI sign-in is required.' `
            -Hint "Run 'az login' and ensure at least one subscription is accessible."
    }

    return @(
        @($rows) |
            Sort-Object @{ Expression = { if ($_.isDefault) { 0 } else { 1 } } }, @{ Expression = { [string]$_.name } }, @{ Expression = { [string]$_.id } }
    )
}

function Find-ClagnosSubscriptionRowById {
    param(
        [object[]]$SubscriptionRows,
        [string]$SubscriptionId
    )

    $normalizedId = [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $SubscriptionId -OptionSource 'subscription lookup')
    $matchedRow = @(
        @($SubscriptionRows) | Where-Object {
            [string]::Equals([string]$_.id, $normalizedId, [System.StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1
    )
    if (@($matchedRow).Count -eq 0) {
        return $null
    }

    return [object]$matchedRow[0]
}

function Get-ClagnosDefaultSubscriptionRow {
    param(
        [object[]]$SubscriptionRows
    )

    $defaultRow = @(
        @($SubscriptionRows) | Where-Object { [bool]$_.isDefault } | Select-Object -First 1
    )
    if (@($defaultRow).Count -gt 0) {
        return [object]$defaultRow[0]
    }

    $accountRaw = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account show -o json --only-show-errors 2>$null
    }
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$accountRaw)) {
        $accountObj = ConvertFrom-JsonCompat -InputObject $accountRaw
        if ($null -ne $accountObj -and -not [string]::IsNullOrWhiteSpace([string]$accountObj.id)) {
            $matchedRow = Find-ClagnosSubscriptionRowById -SubscriptionRows $SubscriptionRows -SubscriptionId ([string]$accountObj.id)
            if (@($matchedRow).Count -gt 0) {
                return [object]$matchedRow[0]
            }
        }
    }

    return [object](@($SubscriptionRows)[0])
}

function Get-ClagnosResolvedSubscriptionContext {
    if ($null -eq $script:ClagnosResolvedSubscriptionContext) {
        return $null
    }

    return [pscustomobject]$script:ClagnosResolvedSubscriptionContext
}

function Set-ClagnosResolvedSubscriptionContext {
    param(
        [string]$SubscriptionId,
        [string]$SubscriptionName,
        [string]$TenantId,
        [string]$ResolutionSource
    )

    $normalizedId = [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $SubscriptionId -OptionSource 'resolved subscription')
    $script:ClagnosActiveSubscriptionId = $normalizedId
    $script:ClagnosResolvedSubscriptionContext = [ordered]@{
        SubscriptionId = $normalizedId
        SubscriptionName = [string]$SubscriptionName
        TenantId = [string]$TenantId
        ResolutionSource = [string]$ResolutionSource
    }
}

function Clear-ClagnosResolvedSubscriptionContext {
    $script:ClagnosActiveSubscriptionId = ''
    $script:ClagnosResolvedSubscriptionContext = $null
    if ($script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_AZURE_SUBSCRIPTION_ID')) {
        $null = $script:ConfigOverrides.Remove('SELECTED_AZURE_SUBSCRIPTION_ID')
    }
}

function Save-ClagnosSubscriptionIdToDotEnv {
    param(
        [string]$EnvFilePath,
        [string]$SubscriptionId
    )

    $normalizedId = [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $SubscriptionId -OptionSource 'SELECTED_AZURE_SUBSCRIPTION_ID persistence')
    Set-DotEnvValue -Path $EnvFilePath -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Value $normalizedId
    Remove-ClagnosUnsupportedDotEnvKeys -Path $EnvFilePath
}

function Test-ClagnosAzureTouchingCommand {
    param(
        [string]$CommandName,
        [hashtable]$Options = @{}
    )

    if ([string]$CommandName -eq 'task') {
        return (
            (Test-ClagnosCliOptionPresent -Options $Options -Name 'run-vm-init') -or
            (Test-ClagnosCliOptionPresent -Options $Options -Name 'run-vm-update') -or
            (Test-ClagnosCliOptionPresent -Options $Options -Name 'save-app-state') -or
            (Test-ClagnosCliOptionPresent -Options $Options -Name 'restore-app-state')
        )
    }

    return ([string]$CommandName -in @('create','initialize','update','list','show','do','program','component','move','resize','set','exec','connect','delete'))
}

function Initialize-ClagnosCommandSubscriptionState {
    param(
        [string]$CommandName,
        [hashtable]$Options
    )

    Clear-ClagnosResolvedSubscriptionContext
    if (-not (Test-ClagnosAzureTouchingCommand -CommandName $CommandName -Options $Options)) {
        return $null
    }

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $accessibleRows = @(Get-ClagnosAccessibleSubscriptionRows)
    $cliSubscriptionId = [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id')
    $configSubscriptionId = ''
    if ($configMap) {
        $configSubscriptionId = [string](Get-ConfigValue -Config $configMap -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -DefaultValue '')
    }

    $resolutionSource = 'active'
    $requestedSubscriptionId = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$cliSubscriptionId)) {
        $requestedSubscriptionId = [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $cliSubscriptionId -OptionSource 'CLI option --subscription-id')
        $resolutionSource = 'cli'
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$configSubscriptionId)) {
        $requestedSubscriptionId = [string](Assert-ClagnosSubscriptionIdFormat -SubscriptionId $configSubscriptionId -OptionSource '.env SELECTED_AZURE_SUBSCRIPTION_ID')
        $resolutionSource = 'env'
    }

    $selectedRow = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$requestedSubscriptionId)) {
        $selectedRow = Find-ClagnosSubscriptionRowById -SubscriptionRows $accessibleRows -SubscriptionId $requestedSubscriptionId
        if ($null -eq $selectedRow -or @($selectedRow).Count -eq 0) {
            $detailText = if ($resolutionSource -eq 'cli') {
                ("CLI subscription id '{0}' is not accessible through the current Azure CLI login." -f [string]$requestedSubscriptionId)
            }
            else {
                (".env SELECTED_AZURE_SUBSCRIPTION_ID '{0}' is not accessible through the current Azure CLI login." -f [string]$requestedSubscriptionId)
            }
            Throw-FriendlyError `
                -Detail $detailText `
                -Code 64 `
                -Summary 'Azure subscription selection could not be resolved.' `
                -Hint "Run 'az login', fix the subscription id, or pass a reachable '--subscription-id=<subscription-guid>'."
        }
    }
    else {
        $selectedRow = Get-ClagnosDefaultSubscriptionRow -SubscriptionRows $accessibleRows
    }

    Set-ClagnosResolvedSubscriptionContext `
        -SubscriptionId ([string]$selectedRow.id) `
        -SubscriptionName ([string]$selectedRow.name) `
        -TenantId ([string]$selectedRow.tenantId) `
        -ResolutionSource $resolutionSource

    if ($resolutionSource -eq 'cli') {
        Save-ClagnosSubscriptionIdToDotEnv -EnvFilePath $envFilePath -SubscriptionId ([string]$selectedRow.id)
    }

    if ($script:ConfigOverrides -eq $null) {
        $script:ConfigOverrides = @{}
    }
    $script:ConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] = [string]$selectedRow.id
    $sourceLabel = switch ([string]$resolutionSource) {
        'cli' { 'cli value' }
        'env' { '.env value' }
        default { 'azure value' }
    }
    Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Source $sourceLabel
    return (Get-ClagnosResolvedSubscriptionContext)
}

function Select-ClagnosSubscriptionInteractive {
    param(
        [string]$DefaultSubscriptionId
    )

    $subscriptionRows = @(Get-ClagnosAccessibleSubscriptionRows)
    $defaultIndex = 1
    for ($i = 0; $i -lt @($subscriptionRows).Count; $i++) {
        $rowId = [string]$subscriptionRows[$i].id
        if ([string]::Equals($rowId, [string]$DefaultSubscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) {
            $defaultIndex = $i + 1
            break
        }
    }

    Write-Host ''
    Write-Host 'Available Azure subscriptions (select by number):' -ForegroundColor Cyan
    for ($i = 0; $i -lt @($subscriptionRows).Count; $i++) {
        $row = $subscriptionRows[$i]
        $prefix = if (($i + 1) -eq $defaultIndex) { '*' } else { '' }
        $nameText = [string]$row.name
        $idText = [string]$row.id
        $defaultText = if ([bool]$row.isDefault) { ' [active default]' } else { '' }
        Write-Host ("{0}{1}-{2} ({3}){4}" -f $prefix, ($i + 1), $nameText, $idText, $defaultText)
    }

    while ($true) {
        $raw = Read-Host ("Enter subscription number (default={0})" -f $defaultIndex)
        if ([string]::IsNullOrWhiteSpace([string]$raw)) {
            return [object]$subscriptionRows[$defaultIndex - 1]
        }
        if ($raw -match '^\d+$') {
            $index = [int]$raw
            if ($index -ge 1 -and $index -le @($subscriptionRows).Count) {
                return [object]$subscriptionRows[$index - 1]
            }
        }

        Write-Host 'Invalid subscription selection. Please enter a valid number.' -ForegroundColor Yellow
    }
}
