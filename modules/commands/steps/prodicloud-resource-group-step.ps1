# Resource-group and Azure resource-state helpers.

# Handles Invoke-ProdicloudResourceGroupStep.
function Invoke-ProdicloudResourceGroupStep {
    param(
        [hashtable]$Context,
        [switch]$AutoMode,
        [switch]$UpdateMode,
        [ValidateSet("default","update")]
        [string]$ExecutionMode = "default"
    )

    $resourceGroup = [string]$Context.ResourceGroup
    $azLocation = [string]$Context.AzLocation
    if ([string]::IsNullOrWhiteSpace([string]$azLocation)) {
        Throw-FriendlyError `
            -Detail "SELECTED_AZURE_REGION is empty. Resource group creation cannot continue without a region." `
            -Code 22 `
            -Summary "Azure region is required before resource group creation." `
            -Hint "Set DEFAULT_AZURE_REGION in prodicloud.env or complete interactive region selection. The selected VC region is saved to <vm-name>.env."
    }

    $effectiveMode = if ([string]::IsNullOrWhiteSpace([string]$ExecutionMode)) { "default" } else { [string]$ExecutionMode.Trim().ToLowerInvariant() }
    Show-ProdicloudStepFirstUseValues `
        -StepLabel "Step 2/7 - resource group check" `
        -Context $Context `
        -Keys @("ResourceGroup", "AzLocation") `
        -ExtraValues @{
            ResourceExecutionMode = $effectiveMode
        }
    Write-Host "'$resourceGroup'"
    $resourceExists = az group exists -n $resourceGroup --only-show-errors
    Assert-LastExitCode "az group exists"
    $resourceExistsBool = [string]::Equals([string]$resourceExists, "true", [System.StringComparison]::OrdinalIgnoreCase)
    $shouldCreateResourceGroup = $true

    switch ($effectiveMode) {
        "default" {
            if ($resourceExistsBool) {
                Write-Host "Default mode: existing resource group '$resourceGroup' will be kept; create step is skipped." -ForegroundColor Yellow
                $shouldCreateResourceGroup = $false
            }
        }
        "update" {
            if ($resourceExistsBool) {
                Write-Host "Update mode: existing resource group '$resourceGroup' will be kept; create-or-update command will run." -ForegroundColor Yellow
            }
        }
    }

    if (-not $shouldCreateResourceGroup) {
        Set-ProdicloudManagedTagOnResourceGroup -ResourceGroup $resourceGroup
        return
    }

    Write-Host "Creating resource group '$resourceGroup'..."
    $groupCreateSucceeded = $false
    $groupCreateAttempts = 12
    $groupCreateDelaySeconds = 10
    for ($groupCreateAttempt = 1; $groupCreateAttempt -le $groupCreateAttempts; $groupCreateAttempt++) {
        $attemptLabel = "az group create -n $resourceGroup -l $($Context.AzLocation)"
        if ($groupCreateAttempts -gt 1) {
            $attemptLabel = "$attemptLabel (attempt $groupCreateAttempt/$groupCreateAttempts)"
        }

        $groupCreateOutput = Invoke-TrackedAction -Label $attemptLabel -Action {
            az group create -n $resourceGroup -l $Context.AzLocation --tags ("{0}={1}" -f [string]$script:ManagedByTagKey, [string]$script:ManagedByTagValue) -o json 2>&1
        }
        $groupCreateExitCode = [int]$LASTEXITCODE
        if ($groupCreateExitCode -eq 0) {
            $groupCreateSucceeded = $true
            break
        }

        $groupCreateText = (@($groupCreateOutput) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        $isGroupBeingDeleted = ($groupCreateText -match '(?i)(ResourceGroupBeingDeleted|deprovisioning state)')
        if ($isGroupBeingDeleted -and $groupCreateAttempt -lt $groupCreateAttempts) {
            Write-ProdicloudActionProgress -Action ("wait {0}s for resource group '{1}' deprovisioning before retrying create" -f $groupCreateDelaySeconds,$resourceGroup)
            Start-Sleep -Seconds $groupCreateDelaySeconds
            continue
        }

        throw "az group create failed with exit code $groupCreateExitCode."
    }

    if (-not $groupCreateSucceeded) {
        throw "az group create failed because resource group '$resourceGroup' did not become ready in time."
    }

    Set-ProdicloudManagedTagOnResourceGroup -ResourceGroup $resourceGroup
}

# Handles Test-ProdicloudAzResourceExists.
function Test-ProdicloudAzResourceExists {
    param(
        [string[]]$AzArgs
    )

    $null = Invoke-ProdicloudWithSuppressedAzCliStderr -Action {
        az @AzArgs --only-show-errors -o none
    }
    return ($LASTEXITCODE -eq 0)
}

# Handles Test-ProdicloudResourceGroupExists.
function Test-ProdicloudResourceGroupExists {
    param(
        [string]$ResourceGroup
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        return $false
    }

    $existsRaw = az group exists -n ([string]$ResourceGroup) --only-show-errors
    Assert-LastExitCode "az group exists"
    return [string]::Equals([string]$existsRaw, "true", [System.StringComparison]::OrdinalIgnoreCase)
}

# Handles Get-ProdicloudManagedResourceGroupRows.
function Get-ProdicloudManagedResourceGroupRows {
    $rows = @()
    foreach ($tagValue in @([string]$script:ManagedByTagValue, [string]$script:LegacyManagedByTagValue)) {
        $tagFilter = ("{0}={1}" -f [string]$script:ManagedByTagKey, $tagValue)
        $json = az group list --tag $tagFilter -o json --only-show-errors
        Assert-LastExitCode "az group list (managed-by filter)"
        $rows += @(ConvertFrom-JsonArrayCompat -InputObject $json)
    }

    $uniqueRows = @{}
    foreach ($row in @($rows)) {
        $name = [string]$row.name
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $uniqueRows[$name.ToLowerInvariant()] = $row
        }
    }
    return @($uniqueRows.Values | Sort-Object { [string]$_.name })
}

# Handles Test-ProdicloudResourceGroupManaged.
function Test-ProdicloudResourceGroupManaged {
    param(
        [string]$ResourceGroup
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        return $false
    }

    $groupJson = az group show -n ([string]$ResourceGroup) -o json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$groupJson)) {
        return $false
    }

    $groupObj = ConvertFrom-JsonCompat -InputObject $groupJson
    if (-not $groupObj -or -not $groupObj.tags) {
        return $false
    }

    $tagValue = ''
    if ($groupObj.tags.PSObject.Properties.Match([string]$script:ManagedByTagKey).Count -gt 0) {
        $tagValue = [string]$groupObj.tags.([string]$script:ManagedByTagKey)
    }
    $normalizedTag = ([string]$tagValue).Trim()
    return (
        [string]::Equals($normalizedTag, [string]$script:ManagedByTagValue, [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($normalizedTag, [string]$script:LegacyManagedByTagValue, [System.StringComparison]::OrdinalIgnoreCase)
    )
}

# Handles Assert-ProdicloudManagedResourceGroup.
function Assert-ProdicloudManagedResourceGroup {
    param(
        [string]$ResourceGroup,
        [string]$OperationName = 'operation'
    )

    if (-not (Test-ProdicloudResourceGroupExists -ResourceGroup $ResourceGroup)) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' was not found." -f $ResourceGroup) `
            -Code 61 `
            -Summary ("Resource group check failed before {0}." -f $OperationName) `
            -Hint "Provide a valid resource group name and verify Azure subscription context."
    }

    if (-not (Test-ProdicloudResourceGroupManaged -ResourceGroup $ResourceGroup)) {
        Throw-FriendlyError `
            -Detail ("Resource group '{0}' is not managed by this application (required tag: {1}={2})." -f $ResourceGroup, [string]$script:ManagedByTagKey, [string]$script:ManagedByTagValue) `
            -Code 61 `
            -Summary ("Resource group is outside prodicloud managed scope for {0}." -f $OperationName) `
            -Hint ("Use a resource group tagged with {0}={1}, or run create to generate managed resources." -f [string]$script:ManagedByTagKey, [string]$script:ManagedByTagValue)
    }
}

# Handles Set-ProdicloudManagedTagOnResourceGroup.
function Set-ProdicloudManagedTagOnResourceGroup {
    param(
        [string]$ResourceGroup
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        return
    }

    $groupJson = az group show -n $ResourceGroup -o json --only-show-errors
    Assert-LastExitCode "az group show (tag merge)"
    $groupObj = ConvertFrom-JsonCompat -InputObject $groupJson

    $merged = [ordered]@{}
    if ($groupObj -and $groupObj.tags) {
        foreach ($prop in @($groupObj.tags.PSObject.Properties)) {
            $merged[[string]$prop.Name] = [string]$prop.Value
        }
    }
    $merged[[string]$script:ManagedByTagKey] = [string]$script:ManagedByTagValue
    $tagArgs = @()
    foreach ($key in @($merged.Keys)) {
        $tagArgs += ("{0}={1}" -f [string]$key, [string]$merged[$key])
    }

    Invoke-TrackedAction -Label ("az group update -n {0} --tags ..." -f $ResourceGroup) -Action {
        $groupUpdateArgs = @("group", "update", "-n", [string]$ResourceGroup, "--tags")
        $groupUpdateArgs += @($tagArgs)
        $groupUpdateArgs += @("-o", "none", "--only-show-errors")
        az @groupUpdateArgs
        Assert-LastExitCode "az group update (managed-by tag)"
    } | Out-Null
}

# Handles Test-ProdicloudAzResourceExistsByType.
function Test-ProdicloudAzResourceExistsByType {
    param(
        [string]$ResourceGroup,
        [string]$ResourceType,
        [string]$ResourceName
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::IsNullOrWhiteSpace([string]$ResourceType) -or [string]::IsNullOrWhiteSpace([string]$ResourceName)) {
        return $false
    }

    $namesJson = az resource list -g ([string]$ResourceGroup) --resource-type ([string]$ResourceType) --query "[].name" -o json --only-show-errors
    Assert-LastExitCode ("az resource list ({0})" -f [string]$ResourceType)
    $names = @(
        ConvertFrom-JsonArrayCompat -InputObject $namesJson |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    foreach ($name in $names) {
        if ([string]::Equals([string]$name, [string]$ResourceName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

# Handles Test-ProdicloudNsgRuleExists.
function Test-ProdicloudNsgRuleExists {
    param(
        [string]$ResourceGroup,
        [string]$NsgName,
        [string]$RuleName
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::IsNullOrWhiteSpace([string]$NsgName) -or [string]::IsNullOrWhiteSpace([string]$RuleName)) {
        return $false
    }

    $namesJson = az network nsg rule list -g ([string]$ResourceGroup) --nsg-name ([string]$NsgName) --query "[].name" -o json --only-show-errors
    Assert-LastExitCode "az network nsg rule list"
    $names = @(
        ConvertFrom-JsonArrayCompat -InputObject $namesJson |
            ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
    foreach ($name in $names) {
        if ([string]::Equals([string]$name, [string]$RuleName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

# Handles Ensure-ProdicloudResourceGroupReady.
function Ensure-ProdicloudResourceGroupReady {
    param(
        [hashtable]$Context
    )

    $resourceGroup = [string]$Context.ResourceGroup
    if ([string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
        throw "ResourceGroup is required for Ensure-ProdicloudResourceGroupReady."
    }

    $exists = Test-ProdicloudResourceGroupExists -ResourceGroup $resourceGroup
    if ($exists) {
        Set-ProdicloudManagedTagOnResourceGroup -ResourceGroup $resourceGroup
        return
    }

    Invoke-TrackedAction -Label ("az group create -n {0} -l {1}" -f $resourceGroup, [string]$Context.AzLocation) -Action {
        az group create -n $resourceGroup -l $Context.AzLocation --tags ("{0}={1}" -f [string]$script:ManagedByTagKey, [string]$script:ManagedByTagValue) -o none --only-show-errors
        Assert-LastExitCode "az group create (ensure)"
    } | Out-Null

    Set-ProdicloudManagedTagOnResourceGroup -ResourceGroup $resourceGroup
}

# Handles Assert-ProdicloudSingleActionDependencies.
function Assert-ProdicloudSingleActionDependencies {
    param(
        [ValidateSet('configure','group','network','vm-deploy','vm-init','vm-update','vm-summary')]
        [string]$ActionName,
        [hashtable]$Context
    )

    if ($ActionName -in @('configure', 'group')) {
        return
    }

    $resourceGroup = [string]$Context.ResourceGroup
    $vmName = [string]$Context.VmName

    if ($ActionName -eq 'network') {
        $groupExists = az group exists -n $resourceGroup
        Assert-LastExitCode "az group exists"
        $groupExistsBool = [string]::Equals([string]$groupExists, "true", [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $groupExistsBool) {
            Throw-FriendlyError `
                -Detail ("step '{0}' requires existing resource group '{1}', but it was not found." -f $ActionName, $resourceGroup) `
                -Code 63 `
                -Summary "Step dependency is missing." `
                -Hint "Run create/update with --step=group first, or run with --step-to=network."
        }
        return
    }

    if ($ActionName -eq 'vm-deploy') {
        $groupExists = az group exists -n $resourceGroup
        Assert-LastExitCode "az group exists"
        $groupExistsBool = [string]::Equals([string]$groupExists, "true", [System.StringComparison]::OrdinalIgnoreCase)
        if (-not $groupExistsBool) {
            Throw-FriendlyError `
                -Detail ("step '{0}' requires existing resource group '{1}', but it was not found." -f $ActionName, $resourceGroup) `
                -Code 63 `
                -Summary "Step dependency is missing." `
                -Hint "Run create/update with --step=group first."
        }

        $nicExists = Test-ProdicloudAzResourceExists -AzArgs @("network", "nic", "show", "-g", $resourceGroup, "-n", [string]$Context.NIC)
        if (-not $nicExists) {
            Throw-FriendlyError `
                -Detail ("step '{0}' requires existing NIC '{1}', but it was not found." -f $ActionName, [string]$Context.NIC) `
                -Code 63 `
                -Summary "Step dependency is missing." `
                -Hint "Run create/update with --step=network first."
        }
        return
    }

    if ($ActionName -in @('vm-init', 'vm-update', 'vm-summary')) {
        $vmExists = Test-ProdicloudAzResourceExists -AzArgs @("vm", "show", "-g", $resourceGroup, "-n", $vmName)
        if (-not $vmExists) {
            Throw-FriendlyError `
                -Detail ("step '{0}' requires existing VM '{1}', but it was not found." -f $ActionName, $vmName) `
                -Code 63 `
                -Summary "Step dependency is missing." `
                -Hint "Run create/update with --step=vm-deploy first."
        }
        return
    }
}
