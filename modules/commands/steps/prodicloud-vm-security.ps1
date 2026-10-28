# VM security-step helpers.

# Handles Get-ProdicloudCreateSecurityArguments.
function Get-ProdicloudCreateSecurityArguments {
    param(
        [hashtable]$Context
    )

    $arguments = @()
    $securityType = [string]$Context.VmSecurityType
    if ([string]::IsNullOrWhiteSpace([string]$securityType)) {
        return @($arguments)
    }

    $secureBootText = 'false'
    if ([bool]$Context.VmEnableSecureBoot) {
        $secureBootText = 'true'
    }

    $vtpmText = 'false'
    if ([bool]$Context.VmEnableVtpm) {
        $vtpmText = 'true'
    }

    $arguments += @('--security-type', $securityType)
    $arguments += @('--enable-secure-boot', $secureBootText)
    $arguments += @('--enable-vtpm', $vtpmText)
    return @($arguments)
}

# Handles Get-ProdicloudCreateSecurityArgumentsForCurrentVmState.
function Get-ProdicloudCreateSecurityArgumentsForCurrentVmState {
    param(
        [hashtable]$Context,
        [string]$ResourceGroup,
        [string]$VmName,
        [switch]$SuppressNotice
    )

    $desiredArguments = @(Get-ProdicloudCreateSecurityArguments -Context $Context)
    if (@($desiredArguments).Count -eq 0) {
        return @()
    }

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::IsNullOrWhiteSpace([string]$VmName)) {
        return @($desiredArguments)
    }

    $vmExists = $false
    try {
        $vmExists = Test-ProdicloudAzResourceExists -AzArgs @('vm', 'show', '-g', $ResourceGroup, '-n', $VmName)
    }
    catch {
        $vmExists = $false
    }

    if (-not $vmExists) {
        return @($desiredArguments)
    }

    if (-not $SuppressNotice) {
        Write-Host ("Existing VM '{0}' already exists in resource group '{1}'. Security-type create arguments are omitted because Azure does not allow changing securityProfile.securityType during create-or-update on an existing VM." -f $VmName, $ResourceGroup) -ForegroundColor DarkCyan
    }

    return @()
}

# Handles Get-ProdicloudSecurityTypeFeatureRegistrationSnapshot.
function Get-ProdicloudSecurityTypeFeatureRegistrationSnapshot {
    $result = [ordered]@{
        UseStandardSecurityType = ''
        StandardSecurityTypeAsFirstClassEnum = ''
    }

    $result.UseStandardSecurityType = Get-ProdicloudSafeTrimmedText -Value (az feature show --namespace Microsoft.Compute --name UseStandardSecurityType --query properties.state -o tsv --only-show-errors 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $result.UseStandardSecurityType = ''
    }

    $result.StandardSecurityTypeAsFirstClassEnum = Get-ProdicloudSafeTrimmedText -Value (az feature show --namespace Microsoft.Compute --name StandardSecurityTypeAsFirstClassEnum --query properties.state -o tsv --only-show-errors 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $result.StandardSecurityTypeAsFirstClassEnum = ''
    }

    return [pscustomobject]$result
}

# Handles Assert-ProdicloudSecurityTypePreconditions.
function Assert-ProdicloudSecurityTypePreconditions {
    param(
        [hashtable]$Context
    )

    $securityType = Get-ProdicloudSafeTrimmedText -Value $Context.VmSecurityType
    if (-not [string]::Equals([string]$securityType, 'Standard', [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $featureStates = Get-ProdicloudSecurityTypeFeatureRegistrationSnapshot
    $stateTexts = @(
        "UseStandardSecurityType=$([string]$featureStates.UseStandardSecurityType)"
        "StandardSecurityTypeAsFirstClassEnum=$([string]$featureStates.StandardSecurityTypeAsFirstClassEnum)"
    )

    $isRegistered = [string]::Equals([string]$featureStates.UseStandardSecurityType, 'Registered', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals([string]$featureStates.StandardSecurityTypeAsFirstClassEnum, 'Registered', [System.StringComparison]::OrdinalIgnoreCase)

    if ($isRegistered) {
        Write-Host ("Standard VM security type is available in this subscription. Feature states: {0}" -f ($stateTexts -join ', ')) -ForegroundColor DarkCyan
        return
    }

    Throw-FriendlyError `
        -Detail ("VM_SECURITY_TYPE=Standard requires an Azure subscription feature registration. Current states: {0}." -f ($stateTexts -join ', ')) `
        -Code 22 `
        -Summary "Standard VM security type is not available in this subscription." `
        -Hint "Register Microsoft.Compute/UseStandardSecurityType or Microsoft.Compute/StandardSecurityTypeAsFirstClassEnum, wait for state Registered, then retry."
}
