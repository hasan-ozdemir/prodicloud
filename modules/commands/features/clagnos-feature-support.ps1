# Feature-support, hibernation, and nested-virtualization helpers.

# Handles Get-ClagnosNestedVirtualizationSupportInfo.
function Get-ClagnosVmSkuCapabilitySnapshot {
    param(
        [string]$Location,
        [string]$VmSize
    )

    $result = [ordered]@{
        Known = $false
        Message = ''
        Evidence = @()
        CapabilityRows = @()
        Family = ''
    }

    if ([string]::IsNullOrWhiteSpace([string]$Location) -or [string]::IsNullOrWhiteSpace([string]$VmSize)) {
        $result.Message = 'location-or-vm-size-missing'
        return [pscustomobject]$result
    }

    $subscriptionId = az account show --query id -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        $result.Message = 'subscription-read-failed'
        return [pscustomobject]$result
    }

    $filter = [uri]::EscapeDataString(("location eq '{0}'" -f [string]$Location))
    $url = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/skus?api-version=2023-07-01&`$filter=$filter"
    $skuJson = az rest --method get --url $url -o json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$skuJson)) {
        $result.Message = 'compute-skus-read-failed'
        return [pscustomobject]$result
    }

    try {
        $skuPayload = ConvertFrom-JsonCompat -InputObject $skuJson
    }
    catch {
        $result.Message = 'compute-skus-parse-failed'
        return [pscustomobject]$result
    }

    $skuRows = @(
        (ConvertTo-ObjectArrayCompat -InputObject $skuPayload.value) |
            Where-Object {
                [string]::Equals([string]$_.resourceType, 'virtualMachines', [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.name, [string]$VmSize, [System.StringComparison]::OrdinalIgnoreCase)
            }
    )
    if (@($skuRows).Count -eq 0) {
        $result.Message = 'vm-size-metadata-not-found'
        return [pscustomobject]$result
    }

    $capabilityRows = @(
        (ConvertTo-ObjectArrayCompat -InputObject $skuRows[0].capabilities) |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.name)
            }
    )

    $result.Known = $true
    $result.Evidence = @(
        @($capabilityRows) | ForEach-Object {
            "{0}={1}" -f [string]$_.name, [string]$_.value
        }
    )
    $result.CapabilityRows = @($capabilityRows)
    $result.Family = [string]$skuRows[0].family
    return [pscustomobject]$result
}

# Handles Get-ClagnosSafeTrimmedText.
function Get-ClagnosSafeTrimmedText {
    param(
        [AllowNull()]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    if ($null -eq $text) {
        return ''
    }

    return $text.Trim()
}

function Write-ClagnosFeatureIntentMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-Host ("{0} will be enabled." -f [string]$FeatureLabel) -ForegroundColor DarkCyan
    }
}

function Write-ClagnosFeatureActionMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-Host ("Enabling {0}..." -f ([string]$FeatureLabel).ToLowerInvariant()) -ForegroundColor Cyan
    }
}

function Write-ClagnosFeatureSuccessMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-Host ("{0} was enabled successfully." -f [string]$FeatureLabel) -ForegroundColor Green
    }
}

function Write-ClagnosFeatureSkipMessage {
    param(
        [string]$FeatureLabel,
        [string]$Reason
    )

    if ([string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        return
    }

    if ([string]::IsNullOrWhiteSpace([string]$Reason)) {
        Write-Host ("{0} will not be changed." -f [string]$FeatureLabel) -ForegroundColor DarkCyan
        return
    }

    Write-Host ("{0} will not be changed because {1}" -f [string]$FeatureLabel, [string]$Reason) -ForegroundColor DarkCyan
}

function Write-ClagnosFeatureValidationMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-Host ("{0} will be validated on the guest." -f [string]$FeatureLabel) -ForegroundColor DarkCyan
    }
}

function Write-ClagnosFeatureValidationVmStartMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-ClagnosActionProgress -Action ("start VM for {0} validation" -f ([string]$FeatureLabel).ToLowerInvariant())
    }
}

function Write-ClagnosFeatureValidationVmStartedMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-Host ("VM started successfully for {0} validation." -f ([string]$FeatureLabel).ToLowerInvariant()) -ForegroundColor Green
    }
}

function Write-ClagnosFeatureMetadataFallbackMessage {
    param([string]$FeatureLabel)

    if (-not [string]::IsNullOrWhiteSpace([string]$FeatureLabel)) {
        Write-Host ("Azure did not report {0} clearly. Guest validation will be used." -f ([string]$FeatureLabel).ToLowerInvariant()) -ForegroundColor Yellow
    }
}

# Handles Resolve-ClagnosFeatureSupportReasonText.
function Resolve-ClagnosFeatureSupportReasonText {
    param(
        [string]$FeatureLabel,
        [string]$CapabilityLabel,
        [string]$ReasonCode,
        [string[]]$Evidence = @()
    )

    $evidenceText = if (@($Evidence).Count -gt 0) { @($Evidence) -join ', ' } else { '' }
    switch ([string]$ReasonCode) {
        'location-or-vm-size-missing' { return 'Azure region or VM size is empty.' }
        'subscription-read-failed' { return 'Azure subscription details could not be read.' }
        'compute-skus-read-failed' { return 'Azure VM size details could not be read from the REST API.' }
        'compute-skus-parse-failed' { return 'Azure VM size details could not be parsed.' }
        'vm-size-metadata-not-found' { return 'Azure did not return VM size details for the selected region and VM size.' }
        'hibernation-capability-not-advertised' { return ("Azure did not list capability '{0}' for this VM size in this region." -f [string]$CapabilityLabel) }
        'nested-capability-not-advertised' { return 'Azure did not list nested virtualization support for this VM size in this region.' }
        'nested-requires-standard-security' { return "Azure nested virtualization on this VM requires security type 'Standard' instead of 'TrustedLaunch'." }
        'nested-managed-by-security-type' { return 'Nested virtualization depends on VM size and security type for this VM.' }
        'nested-capability-inconclusive' { return 'Azure did not report nested virtualization clearly. Guest validation will be used after deployment.' }
        'hibernation-not-supported' {
            if ([string]::IsNullOrWhiteSpace([string]$evidenceText)) { return 'Azure reported that hibernation is unsupported.' }
            return "Azure reported: $evidenceText."
        }
        'nested-not-supported' {
            if ([string]::IsNullOrWhiteSpace([string]$evidenceText)) { return 'Azure reported that nested virtualization is unsupported.' }
            return "Azure reported: $evidenceText."
        }
        'hibernation-supported' {
            if ([string]::IsNullOrWhiteSpace([string]$evidenceText)) { return 'Azure reported hibernation support.' }
            return "Azure reported: $evidenceText."
        }
        'nested-supported' {
            if ([string]::IsNullOrWhiteSpace([string]$evidenceText)) { return 'Azure reported nested virtualization support.' }
            return "Azure reported: $evidenceText."
        }
        default { return ("{0} support check returned '{1}'." -f [string]$FeatureLabel, [string]$ReasonCode) }
    }
}

# Handles Get-ClagnosHibernationSupportInfo.
function Get-ClagnosHibernationSupportInfo {
    param(
        [string]$Location,
        [string]$VmSize
    )

    $snapshot = Get-ClagnosVmSkuCapabilitySnapshot -Location $Location -VmSize $VmSize
    $result = [ordered]@{
        Known = [bool]$snapshot.Known
        Supported = $false
        Evidence = @()
        Message = [string]$snapshot.Message
        Family = [string]$snapshot.Family
    }

    if (-not [bool]$snapshot.Known) {
        return [pscustomobject]$result
    }

    $hibernationRows = @(
        @($snapshot.CapabilityRows) | Where-Object {
            [string]::Equals([string]$_.name, 'HibernationSupported', [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
    if (@($hibernationRows).Count -eq 0) {
        $result.Known = $true
        $result.Message = 'hibernation-capability-not-advertised'
        return [pscustomobject]$result
    }

    $result.Evidence = @(
        @($hibernationRows) | ForEach-Object {
            "{0}={1}" -f [string]$_.name, [string]$_.value
        }
    )
    foreach ($hibernationRow in @($hibernationRows)) {
        $capValue = (Get-ClagnosSafeTrimmedText -Value $hibernationRow.value).ToLowerInvariant()
        if ($capValue -in @('true', 'yes', 'supported', 'on', '1')) {
            $result.Supported = $true
            $result.Message = 'hibernation-supported'
            return [pscustomobject]$result
        }
    }

    $result.Message = 'hibernation-not-supported'
    return [pscustomobject]$result
}

# Handles Get-ClagnosNestedVirtualizationSupportInfo.
function Get-ClagnosNestedVirtualizationSupportInfo {
    param(
        [string]$Location,
        [string]$VmSize
    )

    $snapshot = Get-ClagnosVmSkuCapabilitySnapshot -Location $Location -VmSize $VmSize
    $result = [ordered]@{
        Known = [bool]$snapshot.Known
        Supported = $false
        Evidence = @()
        Message = [string]$snapshot.Message
        Family = [string]$snapshot.Family
    }

    if (-not [bool]$snapshot.Known) {
        return [pscustomobject]$result
    }

    $capabilities = @(
        @($snapshot.CapabilityRows) | Where-Object {
            $capName = [string]$_.name
            -not [string]::IsNullOrWhiteSpace([string]$capName) -and $capName.ToLowerInvariant().Contains('nested')
        }
    )
    if (@($capabilities).Count -eq 0) {
        $result.Known = $false
        $result.Message = 'nested-capability-inconclusive'
        return [pscustomobject]$result
    }

    $result.Evidence = @(
        @($capabilities) | ForEach-Object {
            "{0}={1}" -f [string]$_.name, [string]$_.value
        }
    )

    foreach ($capability in @($capabilities)) {
        $capValue = (Get-ClagnosSafeTrimmedText -Value $capability.value).ToLowerInvariant()
        if ($capValue -in @('true', 'yes', 'supported', 'on', '1')) {
            $result.Supported = $true
            $result.Message = 'nested-supported'
            return [pscustomobject]$result
        }
    }

    $result.Message = 'nested-not-supported'
    return [pscustomobject]$result
}

# Handles Assert-ClagnosFeaturePreconditions.
function Assert-ClagnosFeaturePreconditions {
    param(
        [hashtable]$Context
    )

    if ($null -eq $Context) {
        return
    }

    $vmName = Get-ClagnosSafeTrimmedText -Value $Context.VmName
    $location = Get-ClagnosSafeTrimmedText -Value $Context.AzLocation
    $vmSize = Get-ClagnosSafeTrimmedText -Value $Context.VmSize
    $securityType = Get-ClagnosSafeTrimmedText -Value $Context.VmSecurityType
    $hibernationDesired = $false
    $nestedDesired = $false
    if ($Context.ContainsKey('VmEnableHibernation')) {
        $hibernationDesired = [bool]$Context.VmEnableHibernation
    }
    if ($Context.ContainsKey('VmEnableNestedVirtualization')) {
        $nestedDesired = [bool]$Context.VmEnableNestedVirtualization
    }

    if (-not $hibernationDesired) {
        Write-ClagnosFeatureSkipMessage -FeatureLabel 'Hibernation' -Reason 'VM_ENABLE_HIBERNATION=false.'
    }
    else {
        $hibernationSupport = Get-ClagnosHibernationSupportInfo -Location $location -VmSize $vmSize
        $hibernationSupportReason = Resolve-ClagnosFeatureSupportReasonText -FeatureLabel 'Hibernation' -CapabilityLabel 'HibernationSupported' -ReasonCode ([string]$hibernationSupport.Message) -Evidence @($hibernationSupport.Evidence)
        if ([bool]$hibernationSupport.Known -and [bool]$hibernationSupport.Supported) {
            Write-Host ("Azure confirmed hibernation support for VM size '{0}' in region '{1}'." -f $vmSize, $location) -ForegroundColor DarkCyan
        }
        elseif ([bool]$hibernationSupport.Known) {
            Throw-FriendlyError `
                -Detail ("VM_ENABLE_HIBERNATION=true requires Azure hibernation support for VM '{0}', but VM size '{1}' in region '{2}' cannot enable it. {3}" -f $vmName, $vmSize, $location, $hibernationSupportReason) `
                -Code 22 `
                -Summary "Hibernation precheck failed." `
                -Hint "Use a VM size that supports hibernation, or set VM_ENABLE_HIBERNATION=false before retrying."
        }
        else {
            Write-ClagnosFeatureMetadataFallbackMessage -FeatureLabel 'Hibernation'
        }
    }

    if (-not $nestedDesired) {
        Write-ClagnosFeatureSkipMessage -FeatureLabel 'Nested virtualization' -Reason 'VM_ENABLE_NESTED_VIRTUALIZATION=false.'
        return
    }

    if ([string]::Equals([string]$securityType, 'TrustedLaunch', [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail ("VM_ENABLE_NESTED_VIRTUALIZATION=true requires security type 'Standard', but VM '{0}' is configured with security type '{1}'. {2}" -f $vmName, $securityType, (Resolve-ClagnosFeatureSupportReasonText -FeatureLabel 'Nested virtualization' -CapabilityLabel 'nested' -ReasonCode 'nested-requires-standard-security')) `
            -Code 22 `
            -Summary "Nested virtualization precheck failed." `
            -Hint "Use VM_SECURITY_TYPE=Standard for this VM, or set VM_ENABLE_NESTED_VIRTUALIZATION=false before retrying."
    }

    $nestedSupport = Get-ClagnosNestedVirtualizationSupportInfo -Location $location -VmSize $vmSize
    $nestedSupportReason = Resolve-ClagnosFeatureSupportReasonText -FeatureLabel 'Nested virtualization' -CapabilityLabel 'nested' -ReasonCode ([string]$nestedSupport.Message) -Evidence @($nestedSupport.Evidence)
    if ([bool]$nestedSupport.Known -and [bool]$nestedSupport.Supported) {
        Write-Host ("Azure confirmed nested virtualization support for VM size '{0}' in region '{1}'." -f $vmSize, $location) -ForegroundColor DarkCyan
        return
    }

    if ([bool]$nestedSupport.Known) {
        Throw-FriendlyError `
            -Detail ("VM_ENABLE_NESTED_VIRTUALIZATION=true requires Azure nested virtualization support for VM '{0}', but VM size '{1}' in region '{2}' cannot enable it. {3}" -f $vmName, $vmSize, $location, $nestedSupportReason) `
            -Code 22 `
            -Summary "Nested virtualization precheck failed." `
            -Hint "Use a VM size that supports nested virtualization, or set VM_ENABLE_NESTED_VIRTUALIZATION=false before retrying."
    }

    Write-ClagnosFeatureMetadataFallbackMessage -FeatureLabel 'Nested virtualization'
}

# Handles Ensure-ClagnosDeallocatedForFeatureUpdate.
function Ensure-ClagnosDeallocatedForFeatureUpdate {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [ref]$DeallocatedFlag
    )

    if ($DeallocatedFlag.Value) {
        return
    }

    Invoke-TrackedAction -Label ("az vm deallocate -g {0} -n {1}" -f $ResourceGroup, $VmName) -Action {
        az vm deallocate -g $ResourceGroup -n $VmName -o none --only-show-errors
        Assert-LastExitCode "az vm deallocate"
    } | Out-Null
    $DeallocatedFlag.Value = $true
}

# Handles Get-ClagnosVmAdditionalCapabilityFlag.
function Get-ClagnosVmAdditionalCapabilityFlag {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$QueryPath
    )

    $rawValue = az vm show -g $ResourceGroup -n $VmName --query $QueryPath -o tsv --only-show-errors 2>$null
    $querySucceeded = ($LASTEXITCODE -eq 0)
    $stateText = Get-ClagnosSafeTrimmedText -Value $rawValue

    return [pscustomobject]@{
        Known = [bool]$querySucceeded
        RawValue = [string]$stateText
        Enabled = ($querySucceeded -and [string]::Equals([string]$stateText, 'true', [System.StringComparison]::OrdinalIgnoreCase))
    }
}

# Handles Wait-ClagnosProvisioningSucceeded.
function Wait-ClagnosProvisioningSucceeded {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [int]$MaxAttempts = 24,
        [int]$DelaySeconds = 10
    )

    return (Wait-ClagnosProvisioningReadyOrRepair -ResourceGroup $ResourceGroup -VmName $VmName -MaxAttempts $MaxAttempts -DelaySeconds $DelaySeconds)
}

# Handles Invoke-ClagnosPostDeployFeatureEnablement.
function Invoke-ClagnosPostDeployFeatureEnablement {
    param(
        [hashtable]$Context,
        [switch]$VmCreatedThisRun
    )

    $resourceGroup = [string]$Context.ResourceGroup
    $vmName = [string]$Context.VmName
    $vmDiskName = [string]$Context.VmDiskName
    $deallocated = $false
    $hibernationAttempted = $false
    $hibernationEnabled = $false
    $hibernationMessage = ''
    $nestedAttempted = $false
    $nestedEnabled = $false
    $nestedMessage = ''
    $hibernationDesired = $true
    $nestedDesired = $true
    if ($Context.ContainsKey('VmEnableHibernation')) {
        $hibernationDesired = [bool]$Context.VmEnableHibernation
    }
    if ($Context.ContainsKey('VmEnableNestedVirtualization')) {
        $nestedDesired = [bool]$Context.VmEnableNestedVirtualization
    }
    $hibernationSupport = Get-ClagnosHibernationSupportInfo -Location ([string]$Context.AzLocation) -VmSize ([string]$Context.VmSize)
    $nestedSupport = Get-ClagnosNestedVirtualizationSupportInfo -Location ([string]$Context.AzLocation) -VmSize ([string]$Context.VmSize)
    $nestedSecurityState = Get-ClagnosSafeTrimmedText -Value $Context.VmSecurityType
    $vmLifecycleLabel = if ($VmCreatedThisRun) { 'newly created' } else { 'existing' }
    Write-ClagnosActionProgress -Action ("configure post-deploy features for the {0} VM '{1}'" -f $vmLifecycleLabel,$vmName)

    try {
        $provisioningWaitResult = Wait-ClagnosProvisioningSucceeded -ResourceGroup $resourceGroup -VmName $vmName -MaxAttempts 30 -DelaySeconds 10
        if (-not [bool]$provisioningWaitResult.Ready) {
            $snapshot = $provisioningWaitResult.Snapshot
            $provisioningText = if ($null -ne $snapshot) { Get-ClagnosSafeTrimmedText -Value $snapshot.provisioningDisplay } else { '(unknown)' }
            $powerText = if ($null -ne $snapshot) { Get-ClagnosSafeTrimmedText -Value $snapshot.powerDisplay } else { '(unknown)' }
            Throw-FriendlyError `
                -Detail ("VM '{0}' in resource group '{1}' did not reach provisioning succeeded before feature verification. provisioning='{2}', power='{3}'." -f $vmName, $resourceGroup, $provisioningText, $powerText) `
                -Code 66 `
                -Summary "VM provisioning is not ready for feature verification." `
                -Hint "Wait until provisioning succeeds, then retry the create/update flow."
        }

        $securityProfileJson = az vm show -g $resourceGroup -n $vmName --query "{securityType:securityProfile.securityType,secureBoot:securityProfile.uefiSettings.secureBootEnabled,vTpm:securityProfile.uefiSettings.vTpmEnabled}" -o json --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$securityProfileJson)) {
            $securityProfile = ConvertFrom-JsonCompat -InputObject $securityProfileJson
            Write-Host ("Current VM security settings: SecurityType={0}, SecureBoot={1}, vTPM={2}" -f [string]$securityProfile.securityType, [string]$securityProfile.secureBoot, [string]$securityProfile.vTpm) -ForegroundColor DarkCyan
            $resolvedSecurityType = Get-ClagnosSafeTrimmedText -Value $securityProfile.securityType
            if (-not [string]::IsNullOrWhiteSpace([string]$resolvedSecurityType)) {
                $nestedSecurityState = $resolvedSecurityType
            }
        }
    }
    catch {
    }

    try {
        if (-not $hibernationDesired) {
            $hibernationMessage = 'disabled-by-config'
            Write-ClagnosFeatureSkipMessage -FeatureLabel 'Hibernation' -Reason 'VM_ENABLE_HIBERNATION=false.'
        }
        else {
            $hibernationAttempted = $true
            Write-ClagnosFeatureIntentMessage -FeatureLabel 'Hibernation'
            $hibernationSupportReason = Resolve-ClagnosFeatureSupportReasonText -FeatureLabel 'Hibernation' -CapabilityLabel 'HibernationSupported' -ReasonCode ([string]$hibernationSupport.Message) -Evidence @($hibernationSupport.Evidence)
            if ([bool]$hibernationSupport.Known -and [bool]$hibernationSupport.Supported) {
                Write-Host ("Azure confirmed hibernation support for VM size '{0}'." -f [string]$Context.VmSize) -ForegroundColor DarkCyan
            }
            elseif ([bool]$hibernationSupport.Known) {
                Throw-FriendlyError `
                    -Detail ("VM_ENABLE_HIBERNATION=true requires Azure hibernation support for VM '{0}', but VM size '{1}' cannot enable it. {2}" -f $vmName, [string]$Context.VmSize, $hibernationSupportReason) `
                    -Code 66 `
                    -Summary "Hibernation could not be enabled." `
                    -Hint "Use a VM size that supports hibernation, or set VM_ENABLE_HIBERNATION=false before retrying."
            }
            else {
                Write-ClagnosFeatureMetadataFallbackMessage -FeatureLabel 'Hibernation'
            }

            $hibernationState = Get-ClagnosVmAdditionalCapabilityFlag -ResourceGroup $resourceGroup -VmName $vmName -QueryPath 'additionalCapabilities.hibernationEnabled'
            if ([bool]$hibernationState.Enabled) {
                Write-Host ("Hibernation is already enabled on VM '{0}'." -f $vmName) -ForegroundColor Green
                $hibernationEnabled = $true
                $hibernationMessage = 'already-enabled'
            }
            else {
                Write-ClagnosFeatureActionMessage -FeatureLabel 'Hibernation'
                Ensure-ClagnosDeallocatedForFeatureUpdate -ResourceGroup $resourceGroup -VmName $vmName -DeallocatedFlag ([ref]$deallocated)

                Invoke-TrackedAction -Label ("az disk update -g {0} -n {1} --set supportsHibernation=true" -f $resourceGroup, $vmDiskName) -Action {
                    az disk update -g $resourceGroup -n $vmDiskName --set supportsHibernation=true -o none --only-show-errors
                    Assert-LastExitCode "az disk update --set supportsHibernation=true"
                } | Out-Null

                Invoke-TrackedAction -Label ("az vm update -g {0} -n {1} --enable-hibernation true" -f $resourceGroup, $vmName) -Action {
                    az vm update -g $resourceGroup -n $vmName --enable-hibernation true -o none --only-show-errors
                    Assert-LastExitCode "az vm update --enable-hibernation true"
                } | Out-Null

                $hibernationStateAfter = Get-ClagnosVmAdditionalCapabilityFlag -ResourceGroup $resourceGroup -VmName $vmName -QueryPath 'additionalCapabilities.hibernationEnabled'
                if ([bool]$hibernationStateAfter.Enabled) {
                    $hibernationEnabled = $true
                    $hibernationMessage = 'enabled'
                    Write-ClagnosFeatureSuccessMessage -FeatureLabel 'Hibernation'
                }
                else {
                    $hibernationMessage = if ([bool]$hibernationStateAfter.Known) { "Azure reported hibernationEnabled='{0}' after the update command." -f [string]$hibernationStateAfter.RawValue } else { 'Azure could not report hibernationEnabled after the update command.' }
                    Throw-FriendlyError `
                        -Detail ("Hibernation verification failed for VM '{0}'. {1}" -f $vmName, $hibernationMessage) `
                        -Code 66 `
                        -Summary "Hibernation could not be enabled." `
                        -Hint "Check Azure VM and disk feature support, then retry the create/update flow."
                }
            }
        }

        if (-not $nestedDesired) {
            $nestedMessage = 'disabled-by-config'
            Write-ClagnosFeatureSkipMessage -FeatureLabel 'Nested virtualization' -Reason 'VM_ENABLE_NESTED_VIRTUALIZATION=false.'
        }
        else {
            $nestedAttempted = $true
            Write-ClagnosFeatureIntentMessage -FeatureLabel 'Nested virtualization'
            if ([string]::Equals([string]$nestedSecurityState, 'TrustedLaunch', [System.StringComparison]::OrdinalIgnoreCase)) {
                $nestedMessage = 'nested-requires-standard-security'
                Throw-FriendlyError `
                    -Detail ("VM_ENABLE_NESTED_VIRTUALIZATION=true requires security type 'Standard', but VM '{0}' currently reports security type '{1}'. {2}" -f $vmName, [string]$nestedSecurityState, (Resolve-ClagnosFeatureSupportReasonText -FeatureLabel 'Nested virtualization' -CapabilityLabel 'nested' -ReasonCode $nestedMessage -Evidence @($nestedSupport.Evidence))) `
                    -Code 66 `
                    -Summary "Nested virtualization could not be enabled." `
                    -Hint "Use VM_SECURITY_TYPE=Standard for this VM and retry."
            }

            $nestedSupportReason = Resolve-ClagnosFeatureSupportReasonText -FeatureLabel 'Nested virtualization' -CapabilityLabel 'nested' -ReasonCode ([string]$nestedSupport.Message) -Evidence @($nestedSupport.Evidence)
            if ([bool]$nestedSupport.Known -and [bool]$nestedSupport.Supported) {
                Write-Host ("Azure confirmed nested virtualization support for VM size '{0}'." -f [string]$Context.VmSize) -ForegroundColor DarkCyan
            }
            elseif ([bool]$nestedSupport.Known) {
                $nestedMessage = [string]$nestedSupport.Message
                Throw-FriendlyError `
                    -Detail ("VM_ENABLE_NESTED_VIRTUALIZATION=true requires Azure nested virtualization support for VM '{0}', but VM size '{1}' cannot enable it. {2}" -f $vmName, [string]$Context.VmSize, $nestedSupportReason) `
                    -Code 66 `
                    -Summary "Nested virtualization could not be enabled." `
                    -Hint "Use a VM size that supports nested virtualization, or set VM_ENABLE_NESTED_VIRTUALIZATION=false before retrying."
            }
            else {
                $nestedMessage = 'nested-capability-inconclusive'
                Write-ClagnosFeatureMetadataFallbackMessage -FeatureLabel 'Nested virtualization'
            }
        }

        if ($nestedAttempted) {
            if ($deallocated) {
                Write-ClagnosFeatureValidationVmStartMessage -FeatureLabel 'Nested virtualization'
                Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
                    az vm start -g $resourceGroup -n $vmName -o none --only-show-errors
                    Assert-LastExitCode "az vm start"
                } | Out-Null
                $deallocated = $false
                Write-ClagnosFeatureValidationVmStartedMessage -FeatureLabel 'Nested virtualization'
            }

            Write-ClagnosFeatureValidationMessage -FeatureLabel 'Nested virtualization'
            Write-ClagnosFeatureActionMessage -FeatureLabel 'Nested virtualization'
            $nestedValidation = Get-ClagnosNestedVirtualizationGuestValidation `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -OsType ([string]$Context.VmOsType) `
                -MaxAttempts 8 `
                -RetryDelaySeconds 20

            if ([bool]$nestedValidation.Known -and [bool]$nestedValidation.Enabled) {
                $nestedEnabled = $true
                $nestedMessage = 'guest-validated'
                Write-ClagnosFeatureSuccessMessage -FeatureLabel 'Nested virtualization'
                if (@($nestedValidation.Evidence).Count -gt 0) {
                    Write-Host ("Nested virtualization validation details: {0}" -f ((@($nestedValidation.Evidence) -join '; '))) -ForegroundColor DarkCyan
                }
            }
            else {
                $nestedEvidenceText = if (@($nestedValidation.Evidence).Count -gt 0) { (@($nestedValidation.Evidence) -join '; ') } else { [string]$nestedValidation.ErrorMessage }
                Throw-FriendlyError `
                    -Detail ("Nested virtualization guest validation failed for VM '{0}'. {1}" -f $vmName, [string]$nestedEvidenceText) `
                    -Code 66 `
                    -Summary "Nested virtualization could not be enabled." `
                    -Hint "Check the VM size, security type, and guest virtualization requirements, then retry the create/update flow."
            }
        }
    }
    finally {
        if ($deallocated) {
            try {
                Invoke-TrackedAction -Label ("az vm start -g {0} -n {1}" -f $resourceGroup, $vmName) -Action {
                    az vm start -g $resourceGroup -n $vmName -o none --only-show-errors
                    Assert-LastExitCode "az vm start"
                } | Out-Null
                Write-Host 'VM was started successfully after feature configuration.' -ForegroundColor Green
            }
            catch {
                Write-Warning ("VM '{0}' could not be started after feature enablement: {1}" -f $vmName, $_.Exception.Message)
            }
        }
    }

    return [pscustomobject]@{
        HibernationAttempted = [bool]$hibernationAttempted
        HibernationEnabled = [bool]$hibernationEnabled
        HibernationMessage = [string]$hibernationMessage
        NestedAttempted = [bool]$nestedAttempted
        NestedEnabled = [bool]$nestedEnabled
        NestedMessage = [string]$nestedMessage
    }
}
