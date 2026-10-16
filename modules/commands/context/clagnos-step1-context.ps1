# Shared Step-1 context builders and security-value helpers.

function ConvertTo-ClagnosOsDiskSizeGb {
    param(
        [string]$Value,
        [string]$FieldName = 'OS disk size'
    )

    $text = if ($null -eq $Value) { '' } else { [string]$Value.Trim() }
    if ($text -notmatch '^(?<amount>\d+(?:\.\d+)?)\s*(?<unit>mb|gb|tb)?$') {
        Throw-FriendlyError -Detail ("{0} '{1}' is not valid. Use a positive number with MB, GB, or TB, such as 1MB, 128GB, or 1TB." -f $FieldName, $text) -Code 25 -Summary 'OS disk size is invalid.' -Hint 'Enter a positive disk size such as 128GB or 1TB.'
    }

    $amount = 0.0
    if (-not [double]::TryParse([string]$Matches.amount, [System.Globalization.NumberStyles]::AllowDecimalPoint, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$amount) -or $amount -le 0) {
        Throw-FriendlyError -Detail ("{0} '{1}' must be greater than zero." -f $FieldName, $text) -Code 25 -Summary 'OS disk size is invalid.' -Hint 'Enter a positive disk size such as 128GB or 1TB.'
    }
    $unit = ([string]$Matches.unit).ToLowerInvariant()
    $sizeGb = switch ($unit) {
        'mb' { [Math]::Ceiling($amount / 1024.0) }
        'tb' { [Math]::Ceiling($amount * 1024.0) }
        default { [Math]::Ceiling($amount) }
    }
    if ($sizeGb -lt 1) { $sizeGb = 1 }
    if ($sizeGb -gt 4095) {
        Throw-FriendlyError -Detail ("{0} '{1}' resolves to {2} GB, exceeding the Azure OS disk limit of 4095 GiB." -f $FieldName, $text, [int]$sizeGb) -Code 25 -Summary 'OS disk size exceeds the Azure limit.' -Hint 'Enter an OS disk size no larger than 4095GB.'
    }
    return [string][int]$sizeGb
}

function Resolve-ClagnosTcpPortSpecification {
    param(
        [string]$Text,
        [string[]]$RequiredPorts = @(),
        [int]$MaximumExpandedPorts = 4096
    )

    $rawText = if ($null -eq $Text) { '' } else { [string]$Text.Trim() }
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        Throw-FriendlyError -Detail 'TCP_PORTS must contain at least one port or port range.' -Code 25 -Summary 'Allowed port input is empty.' -Hint 'Enter comma-separated ports and ranges, such as 80,443,3000-3300.'
    }

    $intervals = New-Object 'System.Collections.Generic.List[object]'
    foreach ($rawToken in @($rawText -split ',')) {
        $token = ([string]$rawToken).Trim()
        if ($token -match '^(?<first>\d{1,5})\s*-\s*(?<last>\d{1,5})$') {
            $first = [int]$Matches.first
            $last = [int]$Matches.last
        }
        elseif ($token -match '^\d{1,5}$') {
            $first = [int]$token
            $last = $first
        }
        else {
            Throw-FriendlyError -Detail ("TCP port token '{0}' is invalid." -f $token) -Code 25 -Summary 'Allowed port input is invalid.' -Hint 'Use comma-separated ports and ascending ranges, such as 80,443,3000-3300.'
        }

        if ($first -lt 1 -or $last -gt 65535 -or $last -lt $first) {
            Throw-FriendlyError -Detail ("TCP port or range '{0}' must be between 1 and 65535 with the range start no greater than its end." -f $token) -Code 25 -Summary 'Allowed port input is outside the valid range.' -Hint 'Use ports from 1 through 65535 and ascending ranges.'
        }
        $intervals.Add([pscustomobject]@{ First = $first; Last = $last })
    }

    foreach ($requiredPortText in @($RequiredPorts)) {
        $requiredPort = 0
        if (-not [int]::TryParse([string]$requiredPortText, [ref]$requiredPort) -or $requiredPort -lt 1 -or $requiredPort -gt 65535) {
            Throw-FriendlyError -Detail ("Required TCP port '{0}' is invalid." -f [string]$requiredPortText) -Code 25 -Summary 'A required VM connection port is invalid.' -Hint 'Set VM_SSH_PORT and VM_RDP_PORT to numbers from 1 through 65535.'
        }
        $intervals.Add([pscustomobject]@{ First = $requiredPort; Last = $requiredPort })
    }

    $sortedIntervals = @($intervals.ToArray() | Sort-Object First, Last)
    $merged = New-Object 'System.Collections.Generic.List[object]'
    foreach ($interval in @($sortedIntervals)) {
        if ($merged.Count -eq 0) {
            $merged.Add([pscustomobject]@{ First = [int]$interval.First; Last = [int]$interval.Last })
            continue
        }
        $current = $merged[$merged.Count - 1]
        if ([int]$interval.First -le ([int]$current.Last + 1)) {
            if ([int]$interval.Last -gt [int]$current.Last) { $current.Last = [int]$interval.Last }
        }
        else {
            $merged.Add([pscustomobject]@{ First = [int]$interval.First; Last = [int]$interval.Last })
        }
    }

    $expandedCount = 0
    foreach ($interval in @($merged.ToArray())) { $expandedCount += ([int]$interval.Last - [int]$interval.First + 1) }
    if ($expandedCount -gt $MaximumExpandedPorts) {
        Throw-FriendlyError -Detail ("TCP port input expands to {0} ports; the maximum supported for guest initialization is {1}." -f $expandedCount, $MaximumExpandedPorts) -Code 25 -Summary 'Too many allowed TCP ports were entered.' -Hint 'Use a narrower range or separate only the required ports.'
    }

    $normalizedRanges = @()
    $expandedPorts = New-Object 'System.Collections.Generic.List[string]'
    foreach ($interval in @($merged.ToArray())) {
        if ([int]$interval.First -eq [int]$interval.Last) { $normalizedRanges += [string]$interval.First }
        else { $normalizedRanges += ('{0}-{1}' -f [int]$interval.First, [int]$interval.Last) }
        for ($port = [int]$interval.First; $port -le [int]$interval.Last; $port++) { $expandedPorts.Add([string]$port) }
    }

    return [pscustomobject]@{
        CanonicalText = [string](@($normalizedRanges) -join ',')
        PortRanges = @($normalizedRanges)
        Ports = @($expandedPorts.ToArray())
    }
}

function Resolve-ClagnosTcpPortNumber {
    param([string]$Value, [string]$Label = 'TCP port')

    $text = if ($null -eq $Value) { '' } else { [string]$Value.Trim() }
    $port = 0
    if ($text -notmatch '^\d{1,5}$' -or -not [int]::TryParse($text, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        Throw-FriendlyError -Detail ("{0} '{1}' must be a whole number from 1 through 65535." -f $Label, $text) -Code 25 -Summary 'TCP port value is invalid.' -Hint 'Enter a port number from 1 through 65535.'
    }
    return [string]$port
}

function Get-ClagnosStep1ContextPersistenceMap {
    param(
        [string]$Platform,
        [hashtable]$Context
    )

    $tcpPortsCsv = [string]$Context.TcpPortsConfiguredCsv
    if ([string]::IsNullOrWhiteSpace([string]$tcpPortsCsv)) {
        $tcpPortsCsv = (@($Context.TcpPorts) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ','
    }

    $vmImageConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_IMAGE"
    $vmSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_SIZE"
    $vmDiskSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_DISK_SIZE_GB"

    $persist = [ordered]@{
        SELECTED_VM_OS = [string]$Platform
        SELECTED_AZURE_REGION = [string]$Context.AzLocation
        SELECTED_RESOURCE_GROUP = [string]$Context.ResourceGroup
        SELECTED_VM_NAME = [string]$Context.VmName
        VM_STORAGE_SKU = [string]$Context.VmStorageSku
        VM_SECURITY_TYPE = [string]$Context.VmSecurityType
        VM_ENABLE_HIBERNATION = ([bool]$Context.VmEnableHibernation).ToString().ToLowerInvariant()
        VM_ENABLE_NESTED_VIRTUALIZATION = ([bool]$Context.VmEnableNestedVirtualization).ToString().ToLowerInvariant()
        VM_ENABLE_SECURE_BOOT = ([bool]$Context.VmEnableSecureBoot).ToString().ToLowerInvariant()
        VM_ENABLE_VTPM = ([bool]$Context.VmEnableVtpm).ToString().ToLowerInvariant()
        VM_ADMIN_USER = [string]$Context.VmUser
        VM_ADMIN_PASS = [string]$Context.VmPass
        VM_ASSISTANT_USER = [string]$Context.VmAssistantUser
        VM_ASSISTANT_PASS = [string]$Context.VmAssistantPass
        VM_SSH_PORT = [string]$Context.SshPort
        VM_RDP_PORT = [string]$Context.RdpPort
        TCP_PORTS = [string]$tcpPortsCsv
        PACKAGE_TRANSPORT = [string]$Context.PackageTransport
    }

    $persist[$vmImageConfigKey] = [string]$Context.VmImage
    $persist[$vmSizeConfigKey] = [string]$Context.VmSize
    $persist[$vmDiskSizeConfigKey] = [string]$Context.VmDiskSize
    $persist['SELECTED_AZURE_SUBSCRIPTION_ID'] = [string]$Context.AzureSubscriptionId
    return $persist
}

function ConvertFrom-ClagnosStep1SecureString {
    param([System.Security.SecureString]$Value)
    if ($null -eq $Value) { return '' }
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

function Get-ClagnosStep1PasswordValue {
    param(
        [hashtable]$ConfigMap,
        [hashtable]$ConfigOverrides,
        [string]$Key,
        [string]$Label,
        [string]$VmName,
        [string]$OperationName,
        [switch]$AutoMode
    )
    $value = [string](Get-ConfigValue -Config $ConfigMap -Key $Key -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace([string]$value) -and -not (Test-ClagnosConfigPlaceholderValue -Value $value)) { return $value }
    $profilePath = Get-ClagnosVmEnvPath -VmName $VmName
    if ($AutoMode -or -not [string]::Equals([string]$OperationName,'create',[System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError -Detail ("VC-specific {0} is missing from '{1}'." -f $Label,$profilePath) -Code 14 -Summary 'VC credentials are not configured.' -Hint ("Set {0} in '{1}' before running non-interactive operations." -f $Key,$profilePath)
    }

    $firstSecure = Read-Host -Prompt ("Enter {0} for VC '{1}'" -f $Label,$VmName) -AsSecureString
    $confirmSecure = Read-Host -Prompt ("Confirm {0} for VC '{1}'" -f $Label,$VmName) -AsSecureString
    $first = ConvertFrom-ClagnosStep1SecureString -Value $firstSecure
    $confirmed = ConvertFrom-ClagnosStep1SecureString -Value $confirmSecure
    if ([string]::IsNullOrWhiteSpace([string]$first) -or -not [string]::Equals([string]$first,[string]$confirmed,[System.StringComparison]::Ordinal)) {
        Throw-FriendlyError -Detail ("The {0} was empty or did not match its confirmation." -f $Label) -Code 14 -Summary 'VC credential entry did not verify.' -Hint 'Enter matching, non-empty values and retry create.'
    }
    $ConfigMap[$Key] = $first
    if ($ConfigOverrides) { $ConfigOverrides[$Key] = $first }
    return [string]$first
}

function Save-ClagnosStep1ContextPersistenceMap {
    param(
        [string]$EnvFilePath,
        [System.Collections.IDictionary]$PersistMap
    )

    $vmName = if ($PersistMap.Contains('SELECTED_VM_NAME')) { [string]$PersistMap['SELECTED_VM_NAME'] } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$vmName) -and $script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME')) {
        $vmName = [string]$script:ConfigOverrides['SELECTED_VM_NAME']
    }
    if ([string]::IsNullOrWhiteSpace([string]$vmName)) { throw 'Saving VC settings requires a selected VM name.' }
    $vmEnvPath = Get-ClagnosVmEnvPath -VmName $vmName
    if (-not (Test-Path -LiteralPath $vmEnvPath -PathType Leaf)) {
        $templatePath = Join-Path (Get-ClagnosRepoRoot) 'vc.env.example'
        if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw "VC environment template is missing: $templatePath" }
        Copy-Item -LiteralPath $templatePath -Destination $vmEnvPath -ErrorAction Stop
    }
    foreach ($key in @($PersistMap.Keys)) {
        $name = [string]$key
        if ([string]::IsNullOrWhiteSpace([string]$name)) {
            continue
        }

        Set-DotEnvValue -Path $EnvFilePath -Key $name -Value ([string]$PersistMap[$name]) -VmName $vmName
    }

    Remove-ClagnosUnsupportedDotEnvKeys -Path $EnvFilePath
    Remove-ClagnosUnsupportedDotEnvKeys -Path $vmEnvPath
}

function New-ClagnosStep1ConfigDisplayMap {
    param(
        [string]$Platform,
        [hashtable]$Context,
        [string]$OperationName
    )

    $vmImageConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey 'VM_IMAGE'
    $vmSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey 'VM_SIZE'
    $vmDiskSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey 'VM_DISK_SIZE_GB'
    $platformInitDirKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform $Platform -Stage 'init'
    $platformUpdateDirKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform $Platform -Stage 'update'

    $values = [ordered]@{
        OPERATION = [string]$OperationName
        SELECTED_VM_OS = [string]$Platform
        AzureSubscriptionName = [string]$Context.AzureSubscriptionName
        SELECTED_AZURE_SUBSCRIPTION_ID = [string]$Context.AzureSubscriptionId
        SELECTED_RESOURCE_GROUP = [string]$Context.ResourceGroup
        SELECTED_AZURE_REGION = [string]$Context.AzLocation
        SELECTED_VM_NAME = [string]$Context.VmName
        $vmImageConfigKey = [string]$Context.VmImage
        VM_STORAGE_SKU = [string]$Context.VmStorageSku
        $vmSizeConfigKey = [string]$Context.VmSize
        VM_DISK_NAME = [string]$Context.VmDiskName
        $vmDiskSizeConfigKey = [string]$Context.VmDiskSize
        VNET_NAME = [string]$Context.VNET
        SUBNET_NAME = [string]$Context.SUBNET
        NSG_NAME = [string]$Context.NSG
        NSG_RULE_NAME = [string]$Context.NsgRule
        PUBLIC_IP_NAME = [string]$Context.IP
        NIC_NAME = [string]$Context.NIC
        VM_ADMIN_USER = [string]$Context.VmUser
        VM_ASSISTANT_USER = [string]$Context.VmAssistantUser
        VM_SSH_PORT = [string]$Context.SshPort
        VM_RDP_PORT = [string]$Context.RdpPort
        TCP_PORTS = [string]$Context.TcpPortsConfiguredCsv
        $platformInitDirKey = [string]$Context.VmInitTaskDir
        $platformUpdateDirKey = [string]$Context.VmUpdateTaskDir
    }

    return $values
}

function Read-ClagnosStep1OverrideValue {
    param(
        [string]$Label,
        [string]$CurrentValue,
        [switch]$AllowEmpty
    )

    $raw = Read-Host ("{0} (current={1})" -f $Label, $CurrentValue)
    if ([string]::IsNullOrWhiteSpace([string]$raw)) {
        return [string]$CurrentValue
    }

    $candidate = [string]$raw.Trim()
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace([string]$candidate)) {
        return [string]$CurrentValue
    }

    return $candidate
}

function Invoke-ClagnosInteractiveStep1Editor {
    param(
        [hashtable]$ConfigMap,
        [string]$EnvFilePath,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [string]$ScriptRoot,
        [string]$VmNameDefault,
        [string]$VmImageDefault,
        [string]$VmSizeDefault,
        [string]$VmDiskSizeDefault,
        [hashtable]$ConfigOverrides,
        [ValidateSet('create','update','configure','generic')]
        [string]$OperationName,
        [hashtable]$Context,
        [switch]$PersistGeneratedResourceGroup,
        [switch]$DeferEnvWrites
    )

    Write-Host ""
    Show-ClagnosKeyValueList -Title "VM configuration review (leave blank to keep current value):" -Values (New-ClagnosStep1ConfigDisplayMap -Platform $Platform -Context $Context -OperationName $OperationName)

    if ([string]::Equals([string]$OperationName, 'update', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "Locked target values: SELECTED_RESOURCE_GROUP, SELECTED_AZURE_REGION, SELECTED_VM_NAME, VNET_NAME, SUBNET_NAME, NSG_NAME, PUBLIC_IP_NAME, NIC_NAME, and VM_DISK_NAME are taken from the existing managed VM target." -ForegroundColor Yellow
    }

    $vmImageConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_IMAGE"
    $vmSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_SIZE"
    $vmDiskSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_DISK_SIZE_GB"

    if ([string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
        while ($true) {
            $candidateVmName = Read-ClagnosStep1OverrideValue -Label 'SELECTED_VM_NAME' -CurrentValue ([string]$Context.VmName)
            if (Test-ClagnosVmNameFormat -VmName $candidateVmName) {
                $ConfigOverrides['SELECTED_VM_NAME'] = [string]$candidateVmName
                Set-ClagnosConfigValueSource -Key 'SELECTED_VM_NAME' -Source 'interactive value'
                break
            }

            Write-Host "Invalid VM name. Use 3-16 characters, start with a letter, then continue with letters, numbers, or hyphen." -ForegroundColor Yellow
        }

        while ($true) {
            $candidateLocation = Read-ClagnosStep1OverrideValue -Label 'SELECTED_AZURE_REGION' -CurrentValue ([string]$Context.AzLocation)
            try {
                Assert-LocationExists -Location $candidateLocation
                $ConfigOverrides['SELECTED_AZURE_REGION'] = ([string]$candidateLocation).Trim().ToLowerInvariant()
                Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_REGION' -Source 'interactive value'
                break
            }
            catch {
                Write-Host "Invalid Azure region. Enter a valid Azure location value." -ForegroundColor Yellow
            }
        }
    }

    $ConfigOverrides['VM_SIZE'] = Read-ClagnosStep1OverrideValue -Label 'VM_SIZE' -CurrentValue ([string]$Context.VmSize)
    $ConfigOverrides[$vmImageConfigKey] = Read-ClagnosStep1OverrideValue -Label $vmImageConfigKey -CurrentValue ([string]$Context.VmImage)
    $ConfigOverrides[$vmDiskSizeConfigKey] = Read-ClagnosStep1OverrideValue -Label $vmDiskSizeConfigKey -CurrentValue ([string]$Context.VmDiskSize)
    $ConfigOverrides['VM_STORAGE_SKU'] = Read-ClagnosStep1OverrideValue -Label 'VM_STORAGE_SKU' -CurrentValue ([string]$Context.VmStorageSku)
    foreach ($key in @('VM_SIZE', $vmImageConfigKey, $vmDiskSizeConfigKey, 'VM_STORAGE_SKU')) {
        if ($ConfigOverrides.ContainsKey([string]$key) -and -not [string]::IsNullOrWhiteSpace([string]$ConfigOverrides[[string]$key])) {
            Set-ClagnosConfigValueSource -Key ([string]$key) -Source 'interactive value'
        }
    }

    $resolvedContext = Invoke-ClagnosStep1Common `
        -ConfigMap $ConfigMap `
        -EnvFilePath $EnvFilePath `
        -Platform $Platform `
        -AutoMode `
        -PersistGeneratedResourceGroup:$PersistGeneratedResourceGroup `
        -ScriptRoot $ScriptRoot `
        -VmNameDefault $VmNameDefault `
        -VmImageDefault $VmImageDefault `
        -VmSizeDefault $VmSizeDefault `
        -VmDiskSizeDefault $VmDiskSizeDefault `
        -ConfigOverrides $ConfigOverrides `
        -OperationName $OperationName `
        -DeferEnvWrites:$DeferEnvWrites `
        -SkipInteractiveConfigEditor

    if ([string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($fieldName in @('SELECTED_RESOURCE_GROUP','VNET_NAME','SUBNET_NAME','NSG_NAME','NSG_RULE_NAME','PUBLIC_IP_NAME','NIC_NAME','VM_DISK_NAME')) {
            $currentValue = switch ($fieldName) {
                'SELECTED_RESOURCE_GROUP' { [string]$resolvedContext.ResourceGroup }
                'VNET_NAME' { [string]$resolvedContext.VNET }
                'SUBNET_NAME' { [string]$resolvedContext.SUBNET }
                'NSG_NAME' { [string]$resolvedContext.NSG }
                'NSG_RULE_NAME' { [string]$resolvedContext.NsgRule }
                'PUBLIC_IP_NAME' { [string]$resolvedContext.IP }
                'NIC_NAME' { [string]$resolvedContext.NIC }
                'VM_DISK_NAME' { [string]$resolvedContext.VmDiskName }
            }

            $candidateValue = Read-ClagnosStep1OverrideValue -Label $fieldName -CurrentValue $currentValue
            if ([string]::Equals([string]$fieldName, 'SELECTED_RESOURCE_GROUP', [System.StringComparison]::OrdinalIgnoreCase)) {
                $ConfigOverrides['SELECTED_RESOURCE_GROUP'] = [string]$candidateValue
                Set-ClagnosConfigValueSource -Key 'SELECTED_RESOURCE_GROUP' -Source 'interactive value'
            }
            else {
                $ConfigOverrides[$fieldName] = [string]$candidateValue
            }
        }

        $resolvedContext = Invoke-ClagnosStep1Common `
            -ConfigMap $ConfigMap `
            -EnvFilePath $EnvFilePath `
            -Platform $Platform `
            -AutoMode `
            -PersistGeneratedResourceGroup:$PersistGeneratedResourceGroup `
            -ScriptRoot $ScriptRoot `
            -VmNameDefault $VmNameDefault `
            -VmImageDefault $VmImageDefault `
            -VmSizeDefault $VmSizeDefault `
            -VmDiskSizeDefault $VmDiskSizeDefault `
            -ConfigOverrides $ConfigOverrides `
            -OperationName $OperationName `
            -DeferEnvWrites:$DeferEnvWrites `
            -SkipInteractiveConfigEditor
    }

    return $resolvedContext
}

function Get-ClagnosManagedNameSeed {
    param(
        [hashtable]$ConfigMap,
        [hashtable]$ConfigOverrides,
        [string]$OperationName,
        [string]$NameKey,
        [string]$TemplateKey,
        [string]$TemplateDefaultValue
    )

    $explicitOverride = ''
    if ($ConfigOverrides -and $ConfigOverrides.ContainsKey($NameKey) -and -not [string]::IsNullOrWhiteSpace([string]$ConfigOverrides[$NameKey])) {
        $explicitOverride = [string]$ConfigOverrides[$NameKey]
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$explicitOverride)) {
        return [pscustomobject]@{
            Value = [string]$explicitOverride
            Explicit = $true
        }
    }

    if (-not [string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
        $configuredName = [string](Get-ConfigValue -Config $ConfigMap -Key $NameKey -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace([string]$configuredName)) {
            return [pscustomobject]@{
                Value = [string]$configuredName
                Explicit = $true
            }
        }
    }

    return [pscustomobject]@{
        Value = [string](Get-ConfigValue -Config $ConfigMap -Key $TemplateKey -DefaultValue $TemplateDefaultValue)
        Explicit = $false
    }
}

# Handles Invoke-ClagnosStep1Common.
function Invoke-ClagnosStep1Common {
    param(
        [hashtable]$ConfigMap,
        [string]$EnvFilePath,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [switch]$AutoMode,
        [switch]$PersistGeneratedResourceGroup,
        [string]$ScriptRoot,
        [string]$VmNameDefault,
        [string]$VmImageDefault,
        [string]$VmSizeDefault,
        [string]$VmDiskSizeDefault,
        [hashtable]$ConfigOverrides,
        [ValidateSet('create','update','configure','generic')]
        [string]$OperationName = 'generic',
        [switch]$DeferEnvWrites,
        [switch]$SkipInteractiveConfigEditor,
        [switch]$WizardInputComplete
    )

    $pendingEnvUpdates = [ordered]@{}

    $vmNameDefaultResolved = ''
    if ($ConfigOverrides -and $ConfigOverrides.ContainsKey('SELECTED_VM_NAME') -and -not [string]::IsNullOrWhiteSpace([string]$ConfigOverrides['SELECTED_VM_NAME'])) {
        $vmNameDefaultResolved = [string]$ConfigOverrides['SELECTED_VM_NAME']
    }
    else {
        $vmNameDefaultResolved = [string](Get-ConfigValue -Config $ConfigMap -Key "SELECTED_VM_NAME" -DefaultValue $VmNameDefault)
    }

    $vmName = $vmNameDefaultResolved
    do {
        if ($AutoMode) {
            if ([string]::IsNullOrWhiteSpace([string]$vmNameDefaultResolved)) {
                Throw-FriendlyError `
                    -Detail "SELECTED_VM_NAME is required for this non-interactive command flow." `
                    -Code 2 `
                    -Summary "VM name is required." `
                    -Hint "Set ACTIVE_VM_NAME in clagnos.env or pass --vm-name; VM-specific settings belong in <vm-name>.env."
            }
            $userInput = $vmNameDefaultResolved
        }
        else {
            if ([string]::Equals([string]$OperationName, 'update', [System.StringComparison]::OrdinalIgnoreCase)) {
                $userInput = $vmNameDefaultResolved
                Write-Host ("Update target VM '{0}' is fixed by the selected managed VM target." -f [string]$userInput) -ForegroundColor Cyan
            }
            elseif ($WizardInputComplete) {
                $userInput = $vmNameDefaultResolved
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$vmNameDefaultResolved)) {
                $userInput = Read-Host "Enter VM name (actual Azure VM name)"
            }
            else {
                $userInput = Read-Host "Enter VM name (actual Azure VM name; default=$vmNameDefaultResolved)"
            }
        }

        if ([string]::IsNullOrWhiteSpace($userInput)) {
            $userInput = $vmNameDefaultResolved
        }

        if (Test-ClagnosVmNameFormat -VmName $userInput) {
            $isValid = $true
        }
        else {
            if ($AutoMode) {
                Throw-FriendlyError `
                    -Detail ("VM name '{0}' is invalid." -f [string]$userInput) `
                    -Code 2 `
                    -Summary "VM name format is invalid." `
                    -Hint "Use 3-16 characters, start with a letter, then continue with letters, numbers, or hyphen."
            }

            Write-Host "Invalid VM name. Use 3-16 characters, start with a letter, then continue with letters, numbers, or hyphen." -ForegroundColor Red
            $isValid = $false
        }
    } until ($isValid)

    $vmName = $userInput
    if ($ConfigOverrides) {
        $ConfigOverrides["SELECTED_VM_NAME"] = $vmName
    }

    Write-Host "VM name '$vmName' will be used for the Azure VM and default resource naming." -ForegroundColor Green

    $vmImageConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_IMAGE"
    $vmSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_SIZE"
    $vmDiskSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $Platform -BaseKey "VM_DISK_SIZE_GB"
    $vmInitTaskDirConfigKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform $Platform -Stage 'init'
    $vmUpdateTaskDirConfigKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform $Platform -Stage 'update'
    $baseTokens = @{ SELECTED_VM_NAME = [string]$vmName }

    $defaultAzLocation = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key "SELECTED_AZURE_REGION" -DefaultValue "") -Tokens $baseTokens
    $vmImage = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key $vmImageConfigKey -DefaultValue $VmImageDefault) -Tokens $baseTokens
    $vmStorageSku = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key "VM_STORAGE_SKU" -DefaultValue "StandardSSD_LRS") -Tokens $baseTokens
    $defaultVmSize = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key $vmSizeConfigKey -DefaultValue $VmSizeDefault) -Tokens $baseTokens
    $vmSecurityType = Resolve-ClagnosSecurityTypeValue -RawValue ([string](Get-ConfigValue -Config $ConfigMap -Key "VM_SECURITY_TYPE" -DefaultValue ""))
    $vmEnableSecureBoot = $false
    $vmEnableVtpm = $false
    $vmEnableHibernation = Resolve-ClagnosBooleanConfigValue -RawValue ([string](Get-ConfigValue -Config $ConfigMap -Key "VM_ENABLE_HIBERNATION" -DefaultValue "true")) -KeyName 'VM_ENABLE_HIBERNATION' -DefaultValue $true -TreatEmptyAsDefault
    $vmEnableNestedVirtualization = Resolve-ClagnosBooleanConfigValue -RawValue ([string](Get-ConfigValue -Config $ConfigMap -Key "VM_ENABLE_NESTED_VIRTUALIZATION" -DefaultValue "true")) -KeyName 'VM_ENABLE_NESTED_VIRTUALIZATION' -DefaultValue $true -TreatEmptyAsDefault
    if ([string]::Equals([string]$vmSecurityType, 'TrustedLaunch', [System.StringComparison]::OrdinalIgnoreCase)) {
        $vmEnableSecureBoot = Resolve-ClagnosBooleanConfigValue -RawValue ([string](Get-ConfigValue -Config $ConfigMap -Key "VM_ENABLE_SECURE_BOOT" -DefaultValue "true")) -KeyName 'VM_ENABLE_SECURE_BOOT' -DefaultValue $true -TreatEmptyAsDefault
        $vmEnableVtpm = Resolve-ClagnosBooleanConfigValue -RawValue ([string](Get-ConfigValue -Config $ConfigMap -Key "VM_ENABLE_VTPM" -DefaultValue "true")) -KeyName 'VM_ENABLE_VTPM' -DefaultValue $true -TreatEmptyAsDefault
    }
    $azLocation = $defaultAzLocation
    $vmSize = $defaultVmSize
    $forcedAzLocation = ''
    $forcedVmSize = ''
    $forcedVmImage = ''
    $forcedVmDiskSize = ''
    $forcedVmStorageSku = ''
    if ($ConfigOverrides) {
        if ($ConfigOverrides.ContainsKey('SELECTED_AZURE_REGION')) {
            $forcedAzLocation = [string]$ConfigOverrides['SELECTED_AZURE_REGION']
        }
        if ($ConfigOverrides.ContainsKey('VM_SIZE')) {
            $forcedVmSize = [string]$ConfigOverrides['VM_SIZE']
        }
        if ($ConfigOverrides.ContainsKey($vmImageConfigKey)) {
            $forcedVmImage = [string]$ConfigOverrides[$vmImageConfigKey]
        }
        if ($ConfigOverrides.ContainsKey($vmDiskSizeConfigKey)) {
            $forcedVmDiskSize = [string]$ConfigOverrides[$vmDiskSizeConfigKey]
        }
        if ($ConfigOverrides.ContainsKey('VM_STORAGE_SKU')) {
            $forcedVmStorageSku = [string]$ConfigOverrides['VM_STORAGE_SKU']
        }
    }

    $hasForcedAzLocation = -not [string]::IsNullOrWhiteSpace([string]$forcedAzLocation)
    $hasForcedVmSize = -not [string]::IsNullOrWhiteSpace([string]$forcedVmSize)
    if ($hasForcedAzLocation) {
        $azLocation = [string]$forcedAzLocation
    }
    if ($hasForcedVmSize) {
        $vmSize = [string]$forcedVmSize
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$forcedVmImage)) {
        $vmImage = [string]$forcedVmImage
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$forcedVmStorageSku)) {
        $vmStorageSku = [string]$forcedVmStorageSku
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$defaultAzLocation)) {
        $defaultAzLocation = ([string]$defaultAzLocation).Trim().ToLowerInvariant()
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$azLocation)) {
        $azLocation = ([string]$azLocation).Trim().ToLowerInvariant()
    }

    $shouldPromptLocationAndSku = (-not $AutoMode) -and (-not $WizardInputComplete) -and -not ($hasForcedAzLocation -or $hasForcedVmSize) -and -not [string]::Equals([string]$OperationName, 'update', [System.StringComparison]::OrdinalIgnoreCase)
    if ($shouldPromptLocationAndSku) {
        $priceHours = Get-PriceHoursFromConfig -Config $ConfigMap -DefaultHours 730
        $regionBackToken = Get-ClagnosSkuPickerRegionBackToken
        while ($true) {
            $azLocation = Select-AzLocationInteractive -DefaultLocation $azLocation
            if ([string]::IsNullOrWhiteSpace([string]$azLocation)) {
                Write-Host "Selected Azure region is empty. Please select a valid region." -ForegroundColor Yellow
                continue
            }
            $vmSizeSelection = Select-VmSkuInteractive -Location $azLocation -DefaultVmSize $defaultVmSize -PriceHours $priceHours
            if ([string]::Equals([string]$vmSizeSelection, [string]$regionBackToken, [System.StringComparison]::Ordinal)) {
                continue
            }

            $vmSize = [string]$vmSizeSelection
            break
        }
        if ($ConfigOverrides) {
            $ConfigOverrides["SELECTED_AZURE_REGION"] = $azLocation
            $ConfigOverrides["VM_SIZE"] = $vmSize
            Set-ClagnosConfigValueSource -Key 'SELECTED_AZURE_REGION' -Source 'interactive value'
            Set-ClagnosConfigValueSource -Key 'VM_SIZE' -Source 'interactive value'
        }

        Write-Host "Interactive selection -> SELECTED_AZURE_REGION='$azLocation', VM_SIZE='$vmSize'." -ForegroundColor Green
    }

    if ([string]::IsNullOrWhiteSpace([string]$azLocation)) {
        Throw-FriendlyError `
            -Detail "SELECTED_AZURE_REGION is empty. Region selection is required before resource group creation." `
            -Code 22 `
            -Summary "Azure region is required." `
            -Hint "Set DEFAULT_AZURE_REGION in clagnos.env or select a region interactively; the chosen value is saved in <vm-name>.env."
    }

    Assert-LocationExists -Location $azLocation
    $regionCode = Get-ClagnosRegionCode -Location $azLocation

    $nameTokens = @{
        SELECTED_VM_NAME = [string]$vmName
        REGION_CODE = [string]$regionCode
        N = "1"
    }

    $resourceGroupTemplate = [string](Get-ConfigValue -Config $ConfigMap -Key "RESOURCE_GROUP_TEMPLATE" -DefaultValue "rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}")

    $configuredResourceGroupRaw = [string](Get-ConfigValue -Config $ConfigMap -Key "SELECTED_RESOURCE_GROUP" -DefaultValue "")
    $configuredResourceGroup = ''
    if ($ConfigOverrides -and $ConfigOverrides.ContainsKey('SELECTED_RESOURCE_GROUP') -and -not [string]::IsNullOrWhiteSpace([string]$ConfigOverrides['SELECTED_RESOURCE_GROUP'])) {
        $configuredResourceGroup = [string]$ConfigOverrides['SELECTED_RESOURCE_GROUP']
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$configuredResourceGroupRaw)) {
        $configuredResourceGroup = Resolve-ClagnosTemplate -Template $configuredResourceGroupRaw -Tokens $nameTokens
    }

    $resourceGroup = ''
    $resourceGroupGenerated = $false
    if ([string]::Equals([string]$OperationName, 'update', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::IsNullOrWhiteSpace([string]$configuredResourceGroup)) {
            Throw-FriendlyError `
                -Detail "Update target resource group is empty." `
                -Code 66 `
                -Summary "Update command could not resolve the managed resource group." `
                -Hint "Provide --group together with update, or select an existing managed resource group interactively."
        }

        $resourceGroup = [string]$configuredResourceGroup
        Assert-ClagnosManagedResourceGroup -ResourceGroup $resourceGroup -OperationName 'update'
    }
    elseif ([string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$configuredResourceGroup) -and $ConfigOverrides -and $ConfigOverrides.ContainsKey('SELECTED_RESOURCE_GROUP')) {
            $resourceGroup = [string]$configuredResourceGroup
            Write-Host ("Create command will use the requested new resource group name '{0}'." -f $resourceGroup) -ForegroundColor Green
        }
        else {
            $resourceGroup = Resolve-ClagnosResourceGroupNameFromTemplate `
                -Template $resourceGroupTemplate `
                -VmName $vmName `
                -RegionCode $regionCode `
                -UseNextIndex
            $resourceGroupGenerated = $true
            Write-Host ("Generated resource group name: {0}" -f [string]$resourceGroup) -ForegroundColor Cyan
        }

        if (Test-ClagnosResourceGroupExists -ResourceGroup $resourceGroup) {
            Throw-FriendlyError `
                -Detail ("Create command generated resource group '{0}', but it already exists." -f [string]$resourceGroup) `
                -Code 62 `
                -Summary "Create command requires a new managed resource group." `
                -Hint "Retry create so the next global gX identifier can be selected, or choose another unused managed resource group name."
        }
    }
    else {
        $resourceGroupForced = ($ConfigOverrides -and $ConfigOverrides.ContainsKey('SELECTED_RESOURCE_GROUP') -and -not [string]::IsNullOrWhiteSpace([string]$ConfigOverrides['SELECTED_RESOURCE_GROUP']))
        if ($resourceGroupForced -and -not [string]::IsNullOrWhiteSpace([string]$configuredResourceGroup)) {
            $resourceGroup = [string]$configuredResourceGroup
            Write-Host ("Resource group override '{0}' will be used." -f $resourceGroup) -ForegroundColor Green
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$configuredResourceGroup)) {
            $configuredExists = Test-ClagnosResourceGroupExists -ResourceGroup $configuredResourceGroup
            if ($configuredExists) {
                $resourceGroup = [string]$configuredResourceGroup
                Write-Host ("Resource group '{0}' exists and will be used." -f $resourceGroup) -ForegroundColor Green
            }
            else {
                Write-Host ("Configured resource group '{0}' does not exist. A new resource group name will be generated." -f $configuredResourceGroup) -ForegroundColor Yellow
            }
        }

        if ([string]::IsNullOrWhiteSpace([string]$resourceGroup)) {
            $resourceGroup = Resolve-ClagnosResourceGroupNameFromTemplate `
                -Template $resourceGroupTemplate `
                -VmName $vmName `
                -RegionCode $regionCode `
                -UseNextIndex
            $resourceGroupGenerated = $true
            Write-Host ("Generated resource group name: {0}" -f [string]$resourceGroup) -ForegroundColor Cyan
        }
    }

    $resourceGroupExists = Test-ClagnosResourceGroupExists -ResourceGroup $resourceGroup
    if ($resourceGroupExists) {
        if ([string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
            Throw-FriendlyError `
                -Detail ("Create command requires a new managed resource group, but '{0}' already exists." -f [string]$resourceGroup) `
                -Code 62 `
                -Summary "Create command cannot continue with an existing resource group." `
                -Hint "Accept the suggested next gX resource group name, or enter another unused managed resource group name."
        }

        Assert-ClagnosManagedResourceGroup -ResourceGroup $resourceGroup -OperationName 'provisioning'
    }

    $managedResourceIndexAllocator = $null
    if (-not [string]::Equals([string]$OperationName, 'update', [System.StringComparison]::OrdinalIgnoreCase)) {
        $managedResourceIndexAllocator = New-ClagnosManagedResourceIndexAllocator
    }

    $vnetSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'VNET_NAME' -TemplateKey 'VNET_NAME_TEMPLATE' -TemplateDefaultValue 'net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $vnetRaw = [string]$vnetSeed.Value
    $vnetExplicit = [bool]$vnetSeed.Explicit
    if ($vnetExplicit) {
        $VNET = [string]$vnetRaw
    }
    else {
        $VNET = Resolve-ClagnosNameFromTemplate -Template $vnetRaw -ResourceType 'net' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'VNET_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $VNET -LogicalName 'VNET_NAME' | Out-Null

    $subnetSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'SUBNET_NAME' -TemplateKey 'SUBNET_NAME_TEMPLATE' -TemplateDefaultValue 'subnet-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $subnetRaw = [string]$subnetSeed.Value
    $subnetExplicit = [bool]$subnetSeed.Explicit
    if ($subnetExplicit) {
        $SUBNET = [string]$subnetRaw
    }
    else {
        $SUBNET = Resolve-ClagnosNameFromTemplate -Template $subnetRaw -ResourceType 'subnet' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'SUBNET_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $SUBNET -LogicalName 'SUBNET_NAME' | Out-Null

    $nsgSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'NSG_NAME' -TemplateKey 'NSG_NAME_TEMPLATE' -TemplateDefaultValue 'nsg-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $nsgRaw = [string]$nsgSeed.Value
    $nsgExplicit = [bool]$nsgSeed.Explicit
    if ($nsgExplicit) {
        $NSG = [string]$nsgRaw
    }
    else {
        $NSG = Resolve-ClagnosNameFromTemplate -Template $nsgRaw -ResourceType 'nsg' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'NSG_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $NSG -LogicalName 'NSG_NAME' | Out-Null

    $nsgRuleSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'NSG_RULE_NAME' -TemplateKey 'NSG_RULE_NAME_TEMPLATE' -TemplateDefaultValue 'nsg-rule-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $nsgRuleRaw = [string]$nsgRuleSeed.Value
    $nsgRuleExplicit = [bool]$nsgRuleSeed.Explicit
    if ($nsgRuleExplicit) {
        $nsgRule = [string]$nsgRuleRaw
    }
    else {
        $nsgRule = Resolve-ClagnosNameFromTemplate -Template $nsgRuleRaw -ResourceType 'nsgrule' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'NSG_RULE_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $nsgRule -LogicalName 'NSG_RULE_NAME' | Out-Null

    $ipSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'PUBLIC_IP_NAME' -TemplateKey 'PUBLIC_IP_NAME_TEMPLATE' -TemplateDefaultValue 'ip-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $ipRaw = [string]$ipSeed.Value
    $ipExplicit = [bool]$ipSeed.Explicit
    if ($ipExplicit) {
        $IP = [string]$ipRaw
    }
    else {
        $IP = Resolve-ClagnosNameFromTemplate -Template $ipRaw -ResourceType 'ip' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'PUBLIC_IP_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $IP -LogicalName 'PUBLIC_IP_NAME' | Out-Null

    $nicSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'NIC_NAME' -TemplateKey 'NIC_NAME_TEMPLATE' -TemplateDefaultValue 'nic-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $nicRaw = [string]$nicSeed.Value
    $nicExplicit = [bool]$nicSeed.Explicit
    if ($nicExplicit) {
        $NIC = [string]$nicRaw
    }
    else {
        $NIC = Resolve-ClagnosNameFromTemplate -Template $nicRaw -ResourceType 'nic' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'NIC_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $NIC -LogicalName 'NIC_NAME' | Out-Null

    $vmDiskSeed = Get-ClagnosManagedNameSeed -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -OperationName $OperationName -NameKey 'VM_DISK_NAME' -TemplateKey 'VM_DISK_NAME_TEMPLATE' -TemplateDefaultValue 'disk-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $vmDiskNameRaw = [string]$vmDiskSeed.Value
    $vmDiskExplicit = [bool]$vmDiskSeed.Explicit
    if ($vmDiskExplicit) {
        $vmDiskName = [string]$vmDiskNameRaw
    }
    else {
        $vmDiskName = Resolve-ClagnosNameFromTemplate -Template $vmDiskNameRaw -ResourceType 'disk' -VmName $vmName -RegionCode $regionCode -ResourceGroup $resourceGroup -UseNextIndex -IndexAllocator $managedResourceIndexAllocator -LogicalName 'VM_DISK_NAME'
    }
    Register-ClagnosManagedResourceNameIndex -Allocator $managedResourceIndexAllocator -Name $vmDiskName -LogicalName 'VM_DISK_NAME' | Out-Null

    Assert-ClagnosManagedResourceNamesValid -NameMap ([ordered]@{
        RESOURCE_GROUP = [string]$resourceGroup
        VNET_NAME = [string]$VNET
        SUBNET_NAME = [string]$SUBNET
        NSG_NAME = [string]$NSG
        NSG_RULE_NAME = [string]$nsgRule
        PUBLIC_IP_NAME = [string]$IP
        NIC_NAME = [string]$NIC
        VM_DISK_NAME = [string]$vmDiskName
    })

    Invoke-ClagnosExplicitOverridePrecheck `
        -ResourceGroup $resourceGroup `
        -VnetName $VNET `
        -SubnetName $SUBNET `
        -NsgName $NSG `
        -NsgRuleName $nsgRule `
        -PublicIpName $IP `
        -NicName $NIC `
        -VmDiskName $vmDiskName `
        -ResourceGroupExists:$resourceGroupExists `
        -VnetExplicit:$vnetExplicit `
        -SubnetExplicit:$subnetExplicit `
        -NsgExplicit:$nsgExplicit `
        -NsgRuleExplicit:$nsgRuleExplicit `
        -PublicIpExplicit:$ipExplicit `
        -NicExplicit:$nicExplicit `
        -VmDiskExplicit:$vmDiskExplicit

    if ([string]::Equals([string]$OperationName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
        Assert-ClagnosVmNameConflictFree -VmName $vmName -TargetResourceGroup $resourceGroup
    }

    $vmDiskSizeRaw = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key $vmDiskSizeConfigKey -DefaultValue $VmDiskSizeDefault) -Tokens $baseTokens
    if (-not [string]::IsNullOrWhiteSpace([string]$forcedVmDiskSize)) {
        $vmDiskSizeRaw = [string]$forcedVmDiskSize
    }
    $vmDiskSize = ConvertTo-ClagnosOsDiskSizeGb -Value ([string]$vmDiskSizeRaw) -FieldName $vmDiskSizeConfigKey

    $companyName = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key "SELECTED_COMPANY_NAME" -DefaultValue '')) -Tokens $baseTokens
    $companyWebAddress = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_COMPANY_WEB_ADDRESS' -DefaultValue '')) -Tokens $baseTokens
    $companyEmailAddress = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_COMPANY_EMAIL_ADDRESS' -DefaultValue '')) -Tokens $baseTokens
    $employeeEmailAddress = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_EMPLOYEE_EMAIL_ADDRESS' -DefaultValue '')) -Tokens $baseTokens
    $employeeFullName = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_EMPLOYEE_FULL_NAME' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessLinkedInUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessYouTubeUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessGitHubUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessTikTokUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessInstagramUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessFacebookUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessXUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessSnapchatUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialBusinessNextSosyalUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalLinkedInUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalYouTubeUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalGitHubUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalTikTokUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalInstagramUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalFacebookUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutSocialPersonalXUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutWebBusinessHomeUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL' -DefaultValue '')) -Tokens $baseTokens
    $shortcutWebBusinessBlogUrl = Resolve-ClagnosTemplate -Template ([string](Get-ConfigValue -Config $ConfigMap -Key 'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL' -DefaultValue '')) -Tokens $baseTokens
    $vmUser = [string](Get-ConfigValue -Config $ConfigMap -Key 'VM_ADMIN_USER' -DefaultValue 'manager')
    $vmAssistantUser = [string](Get-ConfigValue -Config $ConfigMap -Key 'VM_ASSISTANT_USER' -DefaultValue 'assistant')
    if ([string]::IsNullOrWhiteSpace([string]$vmUser)) { $vmUser = 'manager' }
    if ([string]::IsNullOrWhiteSpace([string]$vmAssistantUser)) { $vmAssistantUser = 'assistant' }
    if ($ConfigOverrides) { $ConfigOverrides['VM_ADMIN_USER'] = $vmUser; $ConfigOverrides['VM_ASSISTANT_USER'] = $vmAssistantUser }
    $vmPass = Get-ClagnosStep1PasswordValue -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -Key 'VM_ADMIN_PASS' -Label 'manager password' -VmName $vmName -OperationName $OperationName -AutoMode:$AutoMode
    $vmAssistantPass = Get-ClagnosStep1PasswordValue -ConfigMap $ConfigMap -ConfigOverrides $ConfigOverrides -Key 'VM_ASSISTANT_PASS' -Label 'assistant password' -VmName $vmName -OperationName $OperationName -AutoMode:$AutoMode
    $sshPortValue = [string](Get-ConfigValue -Config $ConfigMap -Key "VM_SSH_PORT" -DefaultValue (Get-ClagnosDefaultSshPortText))
    $sshPort = Resolve-ClagnosTemplate -Template $sshPortValue -Tokens $baseTokens
    $rdpPortValue = [string](Get-ConfigValue -Config $ConfigMap -Key "VM_RDP_PORT" -DefaultValue (Get-ClagnosDefaultRdpPortText))
    $rdpPort = Resolve-ClagnosTemplate -Template $rdpPortValue -Tokens $baseTokens
    $vmInitTaskDirName = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key $vmInitTaskDirConfigKey -DefaultValue ([string]$((Get-ClagnosPlatformDefaults -Platform $Platform).VmInitTaskDirDefault))) -Tokens $baseTokens
    $vmUpdateTaskDirName = Resolve-ClagnosTemplate -Template (Get-ConfigValue -Config $ConfigMap -Key $vmUpdateTaskDirConfigKey -DefaultValue ([string]$((Get-ClagnosPlatformDefaults -Platform $Platform).VmUpdateTaskDirDefault))) -Tokens $baseTokens
    $vmInitTaskDir = Resolve-ConfigPath -PathValue $vmInitTaskDirName -RootPath $ScriptRoot
    $vmUpdateTaskDir = Resolve-ConfigPath -PathValue $vmUpdateTaskDirName -RootPath $ScriptRoot
    $publicDnsLabel = Resolve-ClagnosPublicDnsLabel -PublicIpName ([string]$IP) -VmName ([string]$vmName)

    $defaultPortsCsv = Get-ClagnosDefaultTcpPortsCsv
    $tcpPortsConfiguredCsv = [string](Get-ConfigValue -Config $ConfigMap -Key "TCP_PORTS" -DefaultValue $defaultPortsCsv)
    if ([string]::IsNullOrWhiteSpace([string]$tcpPortsConfiguredCsv)) { $tcpPortsConfiguredCsv = [string]$defaultPortsCsv }

    $sshPort = Resolve-ClagnosTcpPortNumber -Value ([string]$sshPort) -Label 'VM_SSH_PORT'
    $includeRdp = [bool]((Get-ClagnosPlatformDefaults -Platform $Platform).IncludeRdp)
    if ($includeRdp) {
        $rdpPort = Resolve-ClagnosTcpPortNumber -Value ([string]$rdpPort) -Label 'VM_RDP_PORT'
    }
    $requiredPorts = @([string]$sshPort)
    if ($includeRdp) { $requiredPorts += [string]$rdpPort }
    $tcpPortSpecification = Resolve-ClagnosTcpPortSpecification -Text $tcpPortsConfiguredCsv -RequiredPorts $requiredPorts
    $tcpPortsConfiguredCsv = [string]$tcpPortSpecification.CanonicalText
    $tcpPorts = @($tcpPortSpecification.Ports)

    $context = [ordered]@{
        RegionCode = $regionCode
        ResourceGroup = $resourceGroup
        AzLocation = $azLocation
        DefaultAzLocation = $defaultAzLocation
        VNET = $VNET
        SUBNET = $SUBNET
        NSG = $NSG
        NsgRule = $nsgRule
        IP = $IP
        PublicDnsLabel = [string]$publicDnsLabel
        NIC = $NIC
        VmName = $vmName
        VmImage = $vmImage
        VmStorageSku = $vmStorageSku
        VmSecurityType = $vmSecurityType
        VmEnableSecureBoot = [bool]$vmEnableSecureBoot
        VmEnableVtpm = [bool]$vmEnableVtpm
        VmEnableHibernation = [bool]$vmEnableHibernation
        VmEnableNestedVirtualization = [bool]$vmEnableNestedVirtualization
        VmSize = $vmSize
        DefaultVmSize = $defaultVmSize
        VmDiskName = $vmDiskName
        VmDiskSize = $vmDiskSize
        CompanyName = [string]$companyName
        CompanyWebAddress = [string]$companyWebAddress
        CompanyEmailAddress = [string]$companyEmailAddress
        EmployeeEmailAddress = [string]$employeeEmailAddress
        EmployeeFullName = [string]$employeeFullName
        ShortcutSocialBusinessLinkedInUrl = [string]$shortcutSocialBusinessLinkedInUrl
        ShortcutSocialBusinessYouTubeUrl = [string]$shortcutSocialBusinessYouTubeUrl
        ShortcutSocialBusinessGitHubUrl = [string]$shortcutSocialBusinessGitHubUrl
        ShortcutSocialBusinessTikTokUrl = [string]$shortcutSocialBusinessTikTokUrl
        ShortcutSocialBusinessInstagramUrl = [string]$shortcutSocialBusinessInstagramUrl
        ShortcutSocialBusinessFacebookUrl = [string]$shortcutSocialBusinessFacebookUrl
        ShortcutSocialBusinessXUrl = [string]$shortcutSocialBusinessXUrl
        ShortcutSocialBusinessSnapchatUrl = [string]$shortcutSocialBusinessSnapchatUrl
        ShortcutSocialBusinessNextSosyalUrl = [string]$shortcutSocialBusinessNextSosyalUrl
        ShortcutSocialPersonalLinkedInUrl = [string]$shortcutSocialPersonalLinkedInUrl
        ShortcutSocialPersonalYouTubeUrl = [string]$shortcutSocialPersonalYouTubeUrl
        ShortcutSocialPersonalGitHubUrl = [string]$shortcutSocialPersonalGitHubUrl
        ShortcutSocialPersonalTikTokUrl = [string]$shortcutSocialPersonalTikTokUrl
        ShortcutSocialPersonalInstagramUrl = [string]$shortcutSocialPersonalInstagramUrl
        ShortcutSocialPersonalFacebookUrl = [string]$shortcutSocialPersonalFacebookUrl
        ShortcutSocialPersonalXUrl = [string]$shortcutSocialPersonalXUrl
        ShortcutWebBusinessHomeUrl = [string]$shortcutWebBusinessHomeUrl
        ShortcutWebBusinessBlogUrl = [string]$shortcutWebBusinessBlogUrl
        VmUser = $vmUser
        VmPass = $vmPass
        VmAssistantUser = $vmAssistantUser
        VmAssistantPass = $vmAssistantPass
        PackageTransport = [string](Get-ConfigValue -Config $ConfigMap -Key 'PACKAGE_TRANSPORT' -DefaultValue 'ssh')
        SshPort = $sshPort
        RdpPort = $rdpPort
        TcpPorts = @($tcpPorts)
        TcpPortRanges = @($tcpPortSpecification.PortRanges)
        TcpPortsConfiguredCsv = [string]$tcpPortsConfiguredCsv
        VmInitTaskDir = $vmInitTaskDir
        VmUpdateTaskDir = $vmUpdateTaskDir
    }

    if (-not $AutoMode -and -not $SkipInteractiveConfigEditor -and ($OperationName -in @('create','update'))) {
        $context = Invoke-ClagnosInteractiveStep1Editor `
            -ConfigMap $ConfigMap `
            -EnvFilePath $EnvFilePath `
            -Platform $Platform `
            -ScriptRoot $ScriptRoot `
            -VmNameDefault $VmNameDefault `
            -VmImageDefault $VmImageDefault `
            -VmSizeDefault $VmSizeDefault `
            -VmDiskSizeDefault $VmDiskSizeDefault `
            -ConfigOverrides $ConfigOverrides `
            -OperationName $OperationName `
            -Context $context `
            -PersistGeneratedResourceGroup:$PersistGeneratedResourceGroup `
            -DeferEnvWrites:$DeferEnvWrites
    }

    $persistMap = Get-ClagnosStep1ContextPersistenceMap -Platform $Platform -Context $context
    if (-not $AutoMode -and $PersistGeneratedResourceGroup) {
        if ($DeferEnvWrites) {
            $pendingEnvUpdates = $persistMap
        }
        else {
            Save-ClagnosStep1ContextPersistenceMap -EnvFilePath $EnvFilePath -PersistMap $persistMap
        }
    }

    $context['PendingEnvUpdates'] = $pendingEnvUpdates
    return $context
}

# Handles Assert-ClagnosVmNameConflictFree.
function Assert-ClagnosVmNameConflictFree {
    param(
        [string]$VmName,
        [string]$TargetResourceGroup
    )

    if ([string]::IsNullOrWhiteSpace([string]$VmName)) {
        Throw-FriendlyError `
            -Detail "VM name is empty." `
            -Code 2 `
            -Summary "VM name validation failed." `
            -Hint "Provide a valid VM name before continuing; the configuration will be saved in that VM's profile."
    }

    $vmMatchesJson = az resource list --resource-type "Microsoft.Compute/virtualMachines" --query "[?name=='$VmName'].{name:name,resourceGroup:resourceGroup,id:id}" -o json --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        Throw-FriendlyError `
            -Detail "az resource list failed while checking VM name uniqueness." `
            -Code 62 `
            -Summary "VM name uniqueness check could not be completed." `
            -Hint "Check Azure login status and subscription access."
    }

    $vmMatches = @(
        ConvertFrom-JsonArrayCompat -InputObject $vmMatchesJson |
            Where-Object { $_ -ne $null }
    )
    if (@($vmMatches).Count -eq 0) {
        return
    }

    $targetGroupMatches = @(
        @($vmMatches) | Where-Object {
            $candidateGroup = [string]$_.resourceGroup
            [string]::Equals($candidateGroup, [string]$TargetResourceGroup, [System.StringComparison]::OrdinalIgnoreCase)
        }
    )
    if (@($targetGroupMatches).Count -eq 0) {
        return
    }

    Throw-FriendlyError `
        -Detail ("VM name '{0}' already exists in target resource group '{1}'." -f [string]$VmName, [string]$TargetResourceGroup) `
        -Code 62 `
        -Summary "VM name already exists in the target resource group." `
        -Hint "Choose another VM name or choose a different fresh target resource group."
}

# Handles Resolve-ClagnosSecurityTypeValue.
function Resolve-ClagnosSecurityTypeValue {
    param(
        [string]$RawValue
    )

    $valueText = [string]$RawValue
    if ([string]::IsNullOrWhiteSpace([string]$valueText)) {
        return ''
    }

    $normalized = $valueText.Trim().ToLowerInvariant()
    switch ($normalized) {
        'standard' { return 'Standard' }
        'trustedlaunch' { return 'TrustedLaunch' }
    }

    Throw-FriendlyError `
        -Detail ("VM_SECURITY_TYPE '{0}' is invalid." -f $RawValue) `
        -Code 22 `
        -Summary "VM security type is invalid." `
        -Hint "Use VM_SECURITY_TYPE=Standard or VM_SECURITY_TYPE=TrustedLaunch."
}

# Handles Resolve-ClagnosBooleanConfigValue.
function Resolve-ClagnosBooleanConfigValue {
    param(
        [string]$RawValue,
        [string]$KeyName,
        [bool]$DefaultValue = $false,
        [switch]$TreatEmptyAsDefault
    )

    $valueText = [string]$RawValue
    if ([string]::IsNullOrWhiteSpace([string]$valueText)) {
        if ($TreatEmptyAsDefault) {
            return [bool]$DefaultValue
        }

        Throw-FriendlyError `
            -Detail ("Config key '{0}' is empty." -f $KeyName) `
            -Code 22 `
            -Summary "Boolean config value is missing." `
            -Hint ("Set {0}=true or {0}=false." -f $KeyName)
    }

    $normalized = $valueText.Trim().ToLowerInvariant()
    if ($normalized -in @('1','true','yes','y','on')) {
        return $true
    }
    if ($normalized -in @('0','false','no','n','off')) {
        return $false
    }

    Throw-FriendlyError `
        -Detail ("Config key '{0}' has invalid boolean value '{1}'." -f $KeyName, $RawValue) `
        -Code 22 `
        -Summary "Boolean config value is invalid." `
        -Hint ("Use {0}=true or {0}=false." -f $KeyName)
}
