# Configure command runtime helpers.

function Convert-ClagnosConfigBooleanText {
    param(
        [bool]$Value
    )

    if ($Value) {
        return 'true'
    }

    return 'false'
}

function Get-ClagnosConfigureFlagPlatform {
    param(
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    if ($WindowsFlag -and $LinuxFlag) {
        Throw-FriendlyError `
            -Detail 'Both --windows and --linux were provided.' `
            -Code 2 `
            -Summary 'Conflicting platform flags were provided.' `
            -Hint 'Use only one of --windows or --linux.'
    }

    if ($WindowsFlag) {
        return 'windows'
    }
    if ($LinuxFlag) {
        return 'linux'
    }

    return ''
}

function Invoke-ClagnosConfigureAzJson {
    param(
        [string[]]$AzArgs,
        [string]$ContextLabel,
        [string]$FailureSummary,
        [string]$FailureHint
    )

    $raw = az @AzArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        Throw-FriendlyError `
            -Detail ("Azure query failed while reading {0}." -f [string]$ContextLabel) `
            -Code 64 `
            -Summary $FailureSummary `
            -Hint $FailureHint
    }

    $parsed = ConvertFrom-JsonCompat -InputObject $raw
    if ($null -eq $parsed) {
        Throw-FriendlyError `
            -Detail ("Azure returned unreadable JSON for {0}." -f [string]$ContextLabel) `
            -Code 64 `
            -Summary $FailureSummary `
            -Hint $FailureHint
    }

    return $parsed
}

function Resolve-ClagnosConfigureMarketplaceImage {
    param(
        [object]$VmObject,
        [string]$VmName,
        [string]$ResourceGroup
    )

    if ($null -eq $VmObject -or $null -eq $VmObject.storageProfile -or $null -eq $VmObject.storageProfile.imageReference) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' in resource group '{1}' does not expose a marketplace image reference." -f [string]$VmName, [string]$ResourceGroup) `
            -Code 66 `
            -Summary 'Configure command could not persist VM image.' `
            -Hint 'Use a VM created from an exact marketplace image, or set the platform image manually in clagnos.env.'
    }

    $imageReference = $VmObject.storageProfile.imageReference
    $publisher = [string]$imageReference.publisher
    $offer = [string]$imageReference.offer
    $sku = [string]$imageReference.sku
    $version = [string]$imageReference.version
    if ([string]::IsNullOrWhiteSpace([string]$publisher) -or
        [string]::IsNullOrWhiteSpace([string]$offer) -or
        [string]::IsNullOrWhiteSpace([string]$sku) -or
        [string]::IsNullOrWhiteSpace([string]$version)) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' in resource group '{1}' is not backed by an exact marketplace image reference." -f [string]$VmName, [string]$ResourceGroup) `
            -Code 66 `
            -Summary 'Configure command could not persist VM image.' `
            -Hint 'Use a VM created from an exact marketplace image, or update the platform image keys manually in clagnos.env.'
    }

    return ("{0}:{1}:{2}:{3}" -f $publisher.Trim(), $offer.Trim(), $sku.Trim(), $version.Trim())
}

function Resolve-ClagnosConfigureNsgRuleDescriptor {
    param(
        [string]$ResourceGroup,
        [string]$NsgName,
        [hashtable]$ConfigBefore
    )

    if ([string]::IsNullOrWhiteSpace([string]$NsgName)) {
        Throw-FriendlyError `
            -Detail ("Selected target in resource group '{0}' does not expose a network security group." -f [string]$ResourceGroup) `
            -Code 66 `
            -Summary 'Configure command could not resolve managed network rule state.' `
            -Hint 'Use a managed VM with the expected NSG attached, or repair the network resources before rerunning configure.'
    }

    $ruleRows = Invoke-ClagnosConfigureAzJson `
        -AzArgs @('network', 'nsg', 'rule', 'list', '-g', [string]$ResourceGroup, '--nsg-name', [string]$NsgName, '-o', 'json', '--only-show-errors') `
        -ContextLabel ("NSG rule list for '{0}'" -f [string]$NsgName) `
        -FailureSummary 'Configure command could not read NSG rules.' `
        -FailureHint 'Verify Azure access and the selected managed NSG.'
    $rules = @(
        ConvertTo-ObjectArrayCompat -InputObject $ruleRows |
            Where-Object { $_ -ne $null }
    )
    if (@($rules).Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("NSG '{0}' in resource group '{1}' does not contain any custom rule." -f [string]$NsgName, [string]$ResourceGroup) `
            -Code 66 `
            -Summary 'Configure command could not resolve managed network rule state.' `
            -Hint 'Repair the managed NSG rule before rerunning configure.'
    }

    $compatibleRules = @(
        @($rules) | Where-Object {
            $direction = ([string]$_.direction).Trim()
            $access = ([string]$_.access).Trim()
            $protocol = ([string]$_.protocol).Trim()
            [string]::Equals($direction, 'Inbound', [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals($access, 'Allow', [System.StringComparison]::OrdinalIgnoreCase) -and
            (
                [string]::Equals($protocol, 'Tcp', [System.StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($protocol, '*', [System.StringComparison]::OrdinalIgnoreCase)
            )
        }
    )

    $preferredRuleName = [string](Get-ConfigValue -Config $ConfigBefore -Key 'NSG_RULE_NAME' -DefaultValue '')
    $selectedRule = $null
    if (-not [string]::IsNullOrWhiteSpace([string]$preferredRuleName)) {
        $selectedRule = @(
            @($compatibleRules) | Where-Object {
                [string]::Equals([string]$_.name, [string]$preferredRuleName, [System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1
        )
        if (@($selectedRule).Count -gt 0) {
            $selectedRule = [object]$selectedRule[0]
        }
        else {
            $selectedRule = $null
        }
    }

    if ($null -eq $selectedRule -and @($compatibleRules).Count -eq 1) {
        $selectedRule = [object]$compatibleRules[0]
    }

    if ($null -eq $selectedRule) {
        $candidateNames = @(
            @($compatibleRules) | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        if (@($candidateNames).Count -eq 0) {
            $candidateNames = @(
                @($rules) | ForEach-Object { [string]$_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
            )
        }

        Throw-FriendlyError `
            -Detail ("NSG '{0}' in resource group '{1}' exposes multiple candidate rules and configure cannot pick one safely: {2}." -f [string]$NsgName, [string]$ResourceGroup, (@($candidateNames) -join ', ')) `
            -Code 66 `
            -Summary 'Configure command needs one unambiguous managed NSG rule.' `
            -Hint 'Keep one managed inbound TCP allow rule, or reduce the NSG to one exact active rule and retry.'
    }

    $portValues = @()
    if ($selectedRule.PSObject.Properties.Match('destinationPortRanges').Count -gt 0 -and $null -ne $selectedRule.destinationPortRanges) {
        $portValues += @(
            ConvertTo-ObjectArrayCompat -InputObject $selectedRule.destinationPortRanges |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
    }
    if ($selectedRule.PSObject.Properties.Match('destinationPortRange').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$selectedRule.destinationPortRange)) {
        $portValues += [string]$selectedRule.destinationPortRange
    }

    $portTokens = @(
        @($portValues) |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
    if (@($normalizedPorts).Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("NSG rule '{0}' in resource group '{1}' does not contain any destination port values." -f [string]$selectedRule.name, [string]$ResourceGroup) `
            -Code 66 `
            -Summary 'Configure command could not persist TCP port settings.' `
            -Hint 'Repair the managed NSG rule so it carries explicit destination ports.'
    }

    $portSpecification = Resolve-ClagnosTcpPortSpecification -Text (@($portTokens) -join ',') -MaximumExpandedPorts 65535

    return [pscustomobject]@{
        Name = [string]$selectedRule.name
        Ports = @($portSpecification.Ports)
        PortsCsv = [string]$portSpecification.CanonicalText
    }
}

function Resolve-ClagnosConfigurePortValues {
    param(
        [string]$Platform,
        [string[]]$Ports,
        [hashtable]$ConfigBefore
    )

    $portSet = New-Object System.Collections.Generic.HashSet[string] ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($portText in @($Ports)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$portText)) {
            [void]$portSet.Add(([string]$portText).Trim())
        }
    }

    $configuredSshPort = [string](Get-ConfigValue -Config $ConfigBefore -Key 'VM_SSH_PORT' -DefaultValue '')
    $configuredRdpPort = [string](Get-ConfigValue -Config $ConfigBefore -Key 'VM_RDP_PORT' -DefaultValue '')

    $sshPort = ''
    foreach ($candidate in @($configuredSshPort, (Get-ClagnosDefaultSshPortText), '22')) {
        $candidateText = [string]$candidate
        if ($candidateText -match '^\d+$' -and $portSet.Contains($candidateText)) {
            $sshPort = $candidateText
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace([string]$sshPort)) {
        Throw-FriendlyError `
            -Detail ("Configure command could not determine the SSH port from managed TCP ports: {0}." -f (@($Ports) -join ', ')) `
            -Code 66 `
            -Summary 'Configure command could not persist SSH port settings.' `
            -Hint 'Ensure the managed NSG rule includes the SSH port, or keep VM_SSH_PORT aligned manually.'
    }

    $rdpPort = ''
    $clearRdp = $false
    if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($candidate in @($configuredRdpPort, (Get-ClagnosDefaultRdpPortText))) {
            $candidateText = [string]$candidate
            if ($candidateText -match '^\d+$' -and $portSet.Contains($candidateText)) {
                $rdpPort = $candidateText
                break
            }
        }
        if ([string]::IsNullOrWhiteSpace([string]$rdpPort)) {
            Throw-FriendlyError `
                -Detail ("Configure command could not determine the RDP port from managed TCP ports: {0}." -f (@($Ports) -join ', ')) `
                -Code 66 `
                -Summary 'Configure command could not persist RDP port settings.' `
                -Hint 'Ensure the managed NSG rule includes the Windows RDP port, or keep VM_RDP_PORT aligned manually.'
        }
    }
    else {
        $clearRdp = $true
    }

    return [pscustomobject]@{
        SshPort = [string]$sshPort
        RdpPort = [string]$rdpPort
        ClearRdp = [bool]$clearRdp
    }
}

function Get-ClagnosConfigureFeatureSync {
    param(
        [object]$VmObject,
        [string]$Platform,
        [string]$AzLocation,
        [string]$VmSize
    )

    $persist = [ordered]@{}
    $skipped = @()

    if ($null -ne $VmObject -and $VmObject.PSObject.Properties.Match('securityProfile').Count -gt 0 -and $null -ne $VmObject.securityProfile) {
        $securityProfile = $VmObject.securityProfile
        if ($securityProfile.PSObject.Properties.Match('securityType').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$securityProfile.securityType)) {
            $persist['VM_SECURITY_TYPE'] = [string]$securityProfile.securityType
        }
        else {
            $skipped += 'VM_SECURITY_TYPE'
        }

        if ($securityProfile.PSObject.Properties.Match('uefiSettings').Count -gt 0 -and $null -ne $securityProfile.uefiSettings) {
            $uefiSettings = $securityProfile.uefiSettings
            if ($uefiSettings.PSObject.Properties.Match('secureBootEnabled').Count -gt 0 -and $null -ne $uefiSettings.secureBootEnabled) {
                $persist['VM_ENABLE_SECURE_BOOT'] = Convert-ClagnosConfigBooleanText -Value ([bool]$uefiSettings.secureBootEnabled)
            }
            else {
                $skipped += 'VM_ENABLE_SECURE_BOOT'
            }

            if ($uefiSettings.PSObject.Properties.Match('vTpmEnabled').Count -gt 0 -and $null -ne $uefiSettings.vTpmEnabled) {
                $persist['VM_ENABLE_VTPM'] = Convert-ClagnosConfigBooleanText -Value ([bool]$uefiSettings.vTpmEnabled)
            }
            else {
                $skipped += 'VM_ENABLE_VTPM'
            }
        }
        else {
            $skipped += @('VM_ENABLE_SECURE_BOOT', 'VM_ENABLE_VTPM')
        }
    }
    else {
        $skipped += @('VM_SECURITY_TYPE', 'VM_ENABLE_SECURE_BOOT', 'VM_ENABLE_VTPM')
    }

    if ($null -ne $VmObject -and $VmObject.PSObject.Properties.Match('additionalCapabilities').Count -gt 0 -and $null -ne $VmObject.additionalCapabilities -and $VmObject.additionalCapabilities.PSObject.Properties.Match('hibernationEnabled').Count -gt 0 -and $null -ne $VmObject.additionalCapabilities.hibernationEnabled) {
        $persist['VM_ENABLE_HIBERNATION'] = Convert-ClagnosConfigBooleanText -Value ([bool]$VmObject.additionalCapabilities.hibernationEnabled)
    }
    else {
        $skipped += 'VM_ENABLE_HIBERNATION'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$AzLocation) -and -not [string]::IsNullOrWhiteSpace([string]$VmSize)) {
        $nestedSupport = Get-ClagnosNestedVirtualizationSupportInfo -Location ([string]$AzLocation) -VmSize ([string]$VmSize)
        $securityTypeText = ''
        if ($persist.Contains('VM_SECURITY_TYPE')) {
            $securityTypeText = [string]$persist['VM_SECURITY_TYPE']
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$securityTypeText) -and [string]::Equals([string]$securityTypeText, 'TrustedLaunch', [System.StringComparison]::OrdinalIgnoreCase)) {
            $persist['VM_ENABLE_NESTED_VIRTUALIZATION'] = 'false'
        }
        elseif ([bool]$nestedSupport.Known) {
            $persist['VM_ENABLE_NESTED_VIRTUALIZATION'] = Convert-ClagnosConfigBooleanText -Value ([bool]$nestedSupport.Supported)
        }
        else {
            $skipped += 'VM_ENABLE_NESTED_VIRTUALIZATION'
        }
    }
    else {
        $skipped += 'VM_ENABLE_NESTED_VIRTUALIZATION'
    }

    return [pscustomobject]@{
        PersistMap = $persist
        SkippedKeys = @($skipped | Sort-Object -Unique)
    }
}

function Get-ClagnosConfigureTargetState {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [hashtable]$ConfigBefore
    )

    $vmObject = Invoke-ClagnosConfigureAzJson `
        -AzArgs @('vm', 'show', '-g', [string]$ResourceGroup, '-n', [string]$VmName, '-o', 'json', '--only-show-errors') `
        -ContextLabel ("VM '{0}'" -f [string]$VmName) `
        -FailureSummary 'Configure command could not read VM metadata.' `
        -FailureHint 'Verify the selected managed VM and Azure access.'
    $actualPlatform = Get-ClagnosPlatformNameFromOsType -OsType ([string]$vmObject.storageProfile.osDisk.osType)
    if ([string]::IsNullOrWhiteSpace([string]$actualPlatform)) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' in resource group '{1}' reported unsupported osType '{2}'." -f [string]$VmName, [string]$ResourceGroup, [string]$vmObject.storageProfile.osDisk.osType) `
            -Code 66 `
            -Summary 'Configure command could not detect VM platform.' `
            -Hint 'Use a Windows or Linux VM managed by this application.'
    }

    $networkDescriptor = Get-ClagnosVmNetworkDescriptor -ResourceGroup $ResourceGroup -VmName $VmName
    $diskObject = Invoke-ClagnosConfigureAzJson `
        -AzArgs @('disk', 'show', '-g', [string]$ResourceGroup, '-n', [string]$networkDescriptor.OsDiskName, '-o', 'json', '--only-show-errors') `
        -ContextLabel ("OS disk '{0}'" -f [string]$networkDescriptor.OsDiskName) `
        -FailureSummary 'Configure command could not read OS disk metadata.' `
        -FailureHint 'Verify the selected VM OS disk still exists and Azure access is healthy.'
    $marketplaceImage = Resolve-ClagnosConfigureMarketplaceImage -VmObject $vmObject -VmName $VmName -ResourceGroup $ResourceGroup
    $ruleDescriptor = Resolve-ClagnosConfigureNsgRuleDescriptor -ResourceGroup $ResourceGroup -NsgName ([string]$networkDescriptor.NsgName) -ConfigBefore $ConfigBefore
    $portDescriptor = Resolve-ClagnosConfigurePortValues -Platform $actualPlatform -Ports @($ruleDescriptor.Ports) -ConfigBefore $ConfigBefore
    $featureSync = Get-ClagnosConfigureFeatureSync -VmObject $vmObject -Platform $actualPlatform -AzLocation ([string]$vmObject.location) -VmSize ([string]$vmObject.hardwareProfile.vmSize)

    $clearReasons = @{}
    if ([string]::IsNullOrWhiteSpace([string]$networkDescriptor.PublicIpName)) {
        $clearReasons['PUBLIC_IP_NAME'] = 'Selected target has no attached public IP resource.'
    }
    if ([bool]$portDescriptor.ClearRdp) {
        $clearReasons['VM_RDP_PORT'] = 'Selected Linux VM does not use RDP; stale RDP port value was cleared.'
    }

    $persistMap = [ordered]@{
        SELECTED_VM_OS = [string]$actualPlatform
        SELECTED_AZURE_SUBSCRIPTION_ID = [string]$((Get-ClagnosResolvedSubscriptionContext).SubscriptionId)
        SELECTED_AZURE_REGION = ([string]$vmObject.location).Trim().ToLowerInvariant()
        SELECTED_RESOURCE_GROUP = [string]$ResourceGroup
        SELECTED_VM_NAME = [string]$VmName
        VM_STORAGE_SKU = [string]$diskObject.sku.name
        VM_SSH_PORT = [string]$portDescriptor.SshPort
        VM_RDP_PORT = [string]$portDescriptor.RdpPort
        TCP_PORTS = [string]$ruleDescriptor.PortsCsv
    }

    $vmImageConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_IMAGE'
    $vmSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_SIZE'
    $vmDiskSizeConfigKey = Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_DISK_SIZE_GB'
    $persistMap[$vmImageConfigKey] = [string]$marketplaceImage
    $persistMap[$vmSizeConfigKey] = [string]$vmObject.hardwareProfile.vmSize
    $persistMap[$vmDiskSizeConfigKey] = [string]$diskObject.diskSizeGb

    foreach ($featureKey in @($featureSync.PersistMap.Keys)) {
        $persistMap[[string]$featureKey] = [string]$featureSync.PersistMap[$featureKey]
    }

    if ([string]::Equals([string]$actualPlatform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($key in @('LIN_VM_IMAGE', 'LIN_VM_SIZE', 'LIN_VM_DISK_SIZE_GB')) {
            $persistMap[$key] = ''
            $clearReasons[$key] = 'Selected target is a Windows VM; Linux platform keys were cleared.'
        }
    }
    else {
        foreach ($key in @('WIN_VM_IMAGE', 'WIN_VM_SIZE', 'WIN_VM_DISK_SIZE_GB')) {
            $persistMap[$key] = ''
            $clearReasons[$key] = 'Selected target is a Linux VM; Windows platform keys were cleared.'
        }
    }

    $platformVmImageKey = Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_IMAGE'
    $platformVmSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_SIZE'
    $platformVmDiskSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $actualPlatform -BaseKey 'VM_DISK_SIZE_GB'

    return [pscustomobject]@{
        Platform = [string]$actualPlatform
        PersistMap = $persistMap
        ClearReasonMap = $clearReasons
        SkippedFeatureKeys = @($featureSync.SkippedKeys)
        SummaryMap = [ordered]@{
            AzureSubscriptionName = [string]$((Get-ClagnosResolvedSubscriptionContext).SubscriptionName)
            SELECTED_AZURE_SUBSCRIPTION_ID = [string]$((Get-ClagnosResolvedSubscriptionContext).SubscriptionId)
            SELECTED_VM_OS = [string]$actualPlatform
            SELECTED_RESOURCE_GROUP = [string]$ResourceGroup
            SELECTED_VM_NAME = [string]$VmName
            SELECTED_AZURE_REGION = ([string]$vmObject.location).Trim().ToLowerInvariant()
            $platformVmSizeKey = [string]$vmObject.hardwareProfile.vmSize
            VM_DISK_NAME = [string]$networkDescriptor.OsDiskName
            $platformVmDiskSizeKey = [string]$diskObject.diskSizeGb
            VM_STORAGE_SKU = [string]$diskObject.sku.name
            $platformVmImageKey = [string]$marketplaceImage
            VNET_NAME = [string]$networkDescriptor.VnetName
            SUBNET_NAME = [string]$networkDescriptor.SubnetName
            NSG_NAME = [string]$networkDescriptor.NsgName
            NSG_RULE_NAME = [string]$ruleDescriptor.Name
            PUBLIC_IP_NAME = [string]$networkDescriptor.PublicIpName
            NIC_NAME = [string]$networkDescriptor.NicName
            VM_SSH_PORT = [string]$portDescriptor.SshPort
            VM_RDP_PORT = [string]$portDescriptor.RdpPort
            TCP_PORTS = [string]$ruleDescriptor.PortsCsv
        }
    }
}

# Handles Save-ClagnosConfigToDotEnv.
function Save-ClagnosConfigToDotEnv {
    param(
        [string]$EnvFilePath,
        [hashtable]$ConfigBefore,
        [hashtable]$PersistMap,
        [hashtable]$ClearReasonMap = @{}
    )

    $vmName = if ($PersistMap -and $PersistMap.ContainsKey('SELECTED_VM_NAME')) { [string]$PersistMap['SELECTED_VM_NAME'] } else { '' }
    if ([string]::IsNullOrWhiteSpace([string]$vmName) -and $ConfigBefore -and $ConfigBefore.ContainsKey('SELECTED_VM_NAME')) { $vmName = [string]$ConfigBefore['SELECTED_VM_NAME'] }
    if ([string]::IsNullOrWhiteSpace([string]$vmName) -and $script:ConfigOverrides -and $script:ConfigOverrides.ContainsKey('SELECTED_VM_NAME')) { $vmName = [string]$script:ConfigOverrides['SELECTED_VM_NAME'] }

    $before = @{}
    if ($ConfigBefore) {
        foreach ($key in @($ConfigBefore.Keys)) {
            $before[[string]$key] = [string]$ConfigBefore[$key]
        }
    }

    $changes = @()
    foreach ($key in @($PersistMap.Keys)) {
        $name = [string]$key
        if ([string]::IsNullOrWhiteSpace([string]$name)) {
            continue
        }

        $newValue = [string]$PersistMap[$name]
        $oldValue = ''
        if ($before.ContainsKey($name)) {
            $oldValue = [string]$before[$name]
        }

        if ([string]::Equals($oldValue, $newValue, [System.StringComparison]::Ordinal)) {
            continue
        }

        Set-DotEnvValue -Path $EnvFilePath -Key $name -Value $newValue -VmName $vmName
        $changeKind = if ([string]::IsNullOrWhiteSpace([string]$newValue)) { 'cleared' } else { 'updated' }
        $reason = ''
        if ($ClearReasonMap -and $ClearReasonMap.ContainsKey($name)) {
            $reason = [string]$ClearReasonMap[$name]
        }

        $changes += [pscustomobject]@{
            Key = $name
            OldValue = $oldValue
            NewValue = $newValue
            ChangeKind = $changeKind
            Reason = $reason
        }
    }

    Remove-ClagnosUnsupportedDotEnvKeys -Path $EnvFilePath
    if (-not [string]::IsNullOrWhiteSpace([string]$vmName)) { Remove-ClagnosUnsupportedDotEnvKeys -Path (Get-ClagnosVmEnvPath -VmName $vmName) }

    return @($changes)
}
