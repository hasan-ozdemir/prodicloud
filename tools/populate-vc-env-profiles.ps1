[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$globalPath = Join-Path $RepoRoot 'prodicloud.env'
$templatePath = Join-Path $RepoRoot 'vc.env.example'
if (-not (Test-Path -LiteralPath $globalPath -PathType Leaf)) { throw 'prodicloud.env is required to populate VC profiles.' }
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'vc.env.example is required to populate VC profiles.' }
. (Join-Path $RepoRoot 'prodicloud.ps1')

$globalConfig = Read-DotEnvFile -Path $globalPath -GlobalOnly
if ([string]::IsNullOrWhiteSpace([string]$SubscriptionId)) { $SubscriptionId = [string]$globalConfig['SELECTED_AZURE_SUBSCRIPTION_ID'] }
if ([string]::IsNullOrWhiteSpace([string]$SubscriptionId)) { throw 'Set SELECTED_AZURE_SUBSCRIPTION_ID in prodicloud.env or pass -SubscriptionId.' }

$logsRoot = Join-Path $RepoRoot '.logs'
if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) { New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null }
$transcriptPath = Join-Path $logsRoot ('prodicloud-populate-vc-env-' + (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-fff',[System.Globalization.CultureInfo]::InvariantCulture) + '.txt')
Start-Transcript -LiteralPath $transcriptPath -Force | Out-Null

function Invoke-PopulateVcAzureJson {
    param([string[]]$AzArguments,[string]$Action)
    Write-Host ("Doing: {0}" -f $Action) -ForegroundColor Cyan
    $completeArguments = @($AzArguments) + @('--subscription',$SubscriptionId,'--output','json','--only-show-errors')
    $output = & az @completeArguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$output)) { return $null }
    try { return (ConvertFrom-JsonCompat -InputObject ([string]($output -join "`n"))) } catch { return $null }
}

function Get-PopulateVcTailName {
    param([string]$ResourceId)
    if ([string]::IsNullOrWhiteSpace([string]$ResourceId)) { return '' }
    return [string](([string]$ResourceId).TrimEnd('/') -split '/')[-1]
}

function Get-PopulateVcProfileAzureState {
    param([hashtable]$Profile,[string]$ProfileVmName)

    $resourceGroup = [string]$Profile['SELECTED_RESOURCE_GROUP']
    $vm = $null
    if (-not [string]::IsNullOrWhiteSpace($resourceGroup)) {
        $vm = Invoke-PopulateVcAzureJson -AzArguments @('vm','show','--resource-group',$resourceGroup,'--name',$ProfileVmName) -Action ("read Azure VM properties for VC '{0}'" -f $ProfileVmName)
    }
    else {
        $vmRows = Invoke-PopulateVcAzureJson -AzArguments @('vm','list','--show-details') -Action ("find Azure resource group for VC '{0}'" -f $ProfileVmName)
        $vmMatch = @($vmRows | Where-Object { [string]::Equals([string]$_.name,$ProfileVmName,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($vmMatch.Count -eq 1) {
            $resourceGroup = [string]$vmMatch[0].resourceGroup
            $vm = Invoke-PopulateVcAzureJson -AzArguments @('vm','show','--resource-group',$resourceGroup,'--name',$ProfileVmName) -Action ("read Azure VM properties for VC '{0}'" -f $ProfileVmName)
        }
    }
    if ($null -eq $vm -or [string]::IsNullOrWhiteSpace($resourceGroup)) { return [pscustomobject]@{ ResourceGroup=$resourceGroup; Values=@{} } }

    $values = @{
        SELECTED_RESOURCE_GROUP = $resourceGroup
        SELECTED_VM_NAME = $ProfileVmName
        SELECTED_AZURE_REGION = [string]$vm.location
        SELECTED_VM_OS = ([string]$vm.storageProfile.osDisk.osType).ToLowerInvariant()
    }
    $platformPrefix = if ([string]$values.SELECTED_VM_OS -eq 'linux') { 'LIN' } else { 'WIN' }
    if (-not [string]::IsNullOrWhiteSpace([string]$vm.hardwareProfile.vmSize)) { $values[($platformPrefix + '_VM_SIZE')] = [string]$vm.hardwareProfile.vmSize }
    if ($vm.storageProfile.imageReference) {
        $image = $vm.storageProfile.imageReference
        $imageTokens = @([string]$image.publisher,[string]$image.offer,[string]$image.sku,[string]$image.version)
        if (@($imageTokens | Where-Object { [string]::IsNullOrWhiteSpace([string]$_) }).Count -eq 0) { $values[($platformPrefix + '_VM_IMAGE')] = $imageTokens -join ':' }
    }
    $diskName = [string]$vm.storageProfile.osDisk.name
    if ([string]::IsNullOrWhiteSpace($diskName)) { $diskName = Get-PopulateVcTailName -ResourceId ([string]$vm.storageProfile.osDisk.managedDisk.id) }
    if (-not [string]::IsNullOrWhiteSpace($diskName)) { $values.VM_DISK_NAME = $diskName }
    if ($null -ne $vm.storageProfile.osDisk.diskSizeGb) { $values[($platformPrefix + '_VM_DISK_SIZE_GB')] = [string]$vm.storageProfile.osDisk.diskSizeGb }
    if ($vm.storageProfile.osDisk.managedDisk.id) {
        $disk = Invoke-PopulateVcAzureJson -AzArguments @('disk','show','--resource-group',$resourceGroup,'--name',$diskName) -Action ("read OS disk properties for VC '{0}'" -f $ProfileVmName)
        if ($null -ne $disk) {
            if (-not [string]::IsNullOrWhiteSpace([string]$disk.sku.name)) { $values.VM_STORAGE_SKU = [string]$disk.sku.name }
            if ($null -ne $disk.diskSizeGb) { $values[($platformPrefix + '_VM_DISK_SIZE_GB')] = [string]$disk.diskSizeGb }
        }
    }

    $nicReference = @(ConvertTo-ObjectArrayCompat -InputObject $vm.networkProfile.networkInterfaces | Select-Object -First 1)
    if ($nicReference.Count -gt 0) {
        $nicName = Get-PopulateVcTailName -ResourceId ([string]$nicReference[0].id)
        if (-not [string]::IsNullOrWhiteSpace($nicName)) { $values.NIC_NAME = $nicName }
        $nic = Invoke-PopulateVcAzureJson -AzArguments @('network','nic','show','--resource-group',$resourceGroup,'--name',$nicName) -Action ("read network interface properties for VC '{0}'" -f $ProfileVmName)
        if ($null -ne $nic) {
            $values.NIC_ENABLE_IP_FORWARDING = ([bool]$nic.enableIpForwarding).ToString().ToLowerInvariant()
            $values.NIC_DNS_SERVERS = if (@($nic.dnsSettings.dnsServers).Count -gt 0) { @($nic.dnsSettings.dnsServers | ForEach-Object { [string]$_ }) -join ',' } else { 'none' }
            $ipConfigs = @(ConvertTo-ObjectArrayCompat -InputObject $nic.ipConfigurations | Select-Object -First 1)
            if ($ipConfigs.Count -gt 0) {
                $ipConfig = $ipConfigs[0]
                $subnetId = [string]$ipConfig.subnet.id
                $subnetName = Get-PopulateVcTailName -ResourceId $subnetId
                $vnetName = ''
                if ($subnetId -match '(?i)/virtualNetworks/(?<vnet>[^/]+)/subnets/') { $vnetName = [string]$Matches.vnet }
                if ($subnetName) { $values.SUBNET_NAME = $subnetName }
                if ($vnetName) {
                    $values.VNET_NAME = $vnetName
                    $vnet = Invoke-PopulateVcAzureJson -AzArguments @('network','vnet','show','--resource-group',$resourceGroup,'--name',$vnetName) -Action ("read virtual network properties for VC '{0}'" -f $ProfileVmName)
                    if ($null -ne $vnet) { $values.VNET_ADDRESS_PREFIXES = @($vnet.addressSpace.addressPrefixes | ForEach-Object { [string]$_ }) -join ',' }
                }
                if ($subnetName -and $vnetName) {
                    $subnet = Invoke-PopulateVcAzureJson -AzArguments @('network','vnet','subnet','show','--resource-group',$resourceGroup,'--vnet-name',$vnetName,'--name',$subnetName) -Action ("read subnet properties for VC '{0}'" -f $ProfileVmName)
                    if ($null -ne $subnet) {
                        $values.SUBNET_ADDRESS_PREFIXES = if (@($subnet.addressPrefixes).Count -gt 0) { @($subnet.addressPrefixes | ForEach-Object { [string]$_ }) -join ',' } else { [string]$subnet.addressPrefix }
                        $values.SUBNET_NSG_NAME = Get-PopulateVcTailName -ResourceId ([string]$subnet.networkSecurityGroup.id)
                    }
                }
                $values.NIC_PRIVATE_IP_ALLOCATION = [string]$ipConfig.privateIPAllocationMethod
                $values.NIC_PRIVATE_IP_ADDRESS = [string]$ipConfig.privateIPAddress
                $publicIpId = [string]$ipConfig.publicIPAddress.id
                $publicIpName = Get-PopulateVcTailName -ResourceId $publicIpId
                if ($publicIpName) {
                    $values.NIC_PUBLIC_IP_NAME = $publicIpName
                    $values.PUBLIC_IP_NAME = $publicIpName
                    $publicIp = Invoke-PopulateVcAzureJson -AzArguments @('network','public-ip','show','--resource-group',$resourceGroup,'--name',$publicIpName) -Action ("read public IP properties for VC '{0}'" -f $ProfileVmName)
                    if ($null -ne $publicIp) {
                        $values.PUBLIC_IP_DNS_LABEL = if ([string]::IsNullOrWhiteSpace([string]$publicIp.dnsSettings.domainNameLabel)) { 'none' } else { [string]$publicIp.dnsSettings.domainNameLabel }
                        $values.PUBLIC_IP_ALLOCATION_METHOD = [string]$publicIp.publicIPAllocationMethod
                        $values.PUBLIC_IP_SKU = [string]$publicIp.sku.name
                    }
                }
                $nsgId = [string]$nic.networkSecurityGroup.id
                if ([string]::IsNullOrWhiteSpace($nsgId) -and $subnetName -and $vnetName) {
                    if ($null -ne $subnet) { $nsgId = [string]$subnet.networkSecurityGroup.id }
                }
                $nsgName = Get-PopulateVcTailName -ResourceId $nsgId
                if ($nsgName) {
                    $values.NSG_NAME = $nsgName
                    $nsg = Invoke-PopulateVcAzureJson -AzArguments @('network','nsg','show','--resource-group',$resourceGroup,'--name',$nsgName) -Action ("read network security group properties for VC '{0}'" -f $ProfileVmName)
                    $rules = @(ConvertTo-ObjectArrayCompat -InputObject $nsg.securityRules)
                    $preferredRuleName = [string]$Profile['NSG_RULE_NAME']
                    $rule = @($rules | Where-Object {
                        [string]$_.direction -eq 'Inbound' -and [string]$_.access -eq 'Allow' -and [string]$_.protocol -in @('Tcp','*')
                    } | Select-Object -First 1)
                    if (-not [string]::IsNullOrWhiteSpace($preferredRuleName)) {
                        $preferred = @($rules | Where-Object { [string]::Equals([string]$_.name,$preferredRuleName,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                        if ($preferred.Count -eq 1) { $rule = $preferred }
                    }
                    if ($rule.Count -eq 1) {
                        $values.NSG_RULE_NAME = [string]$rule[0].name
                        $values.NSG_RULE_PRIORITY = [string]$rule[0].priority
                        $values.NSG_RULE_DIRECTION = [string]$rule[0].direction
                        $values.NSG_RULE_ACCESS = [string]$rule[0].access
                        $values.NSG_RULE_PROTOCOL = [string]$rule[0].protocol
                        foreach ($pair in @(
                            @('NSG_RULE_SOURCE_ADDRESS_PREFIXES','sourceAddressPrefixes','sourceAddressPrefix'),
                            @('NSG_RULE_SOURCE_PORT_RANGES','sourcePortRanges','sourcePortRange'),
                            @('NSG_RULE_DESTINATION_ADDRESS_PREFIXES','destinationAddressPrefixes','destinationAddressPrefix'),
                            @('NSG_RULE_DESTINATION_PORT_RANGES','destinationPortRanges','destinationPortRange')
                        )) {
                            $many = @($rule[0].PSObject.Properties[[string]$pair[1]].Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
                            $one = [string]$rule[0].PSObject.Properties[[string]$pair[2]].Value
                            if (-not [string]::IsNullOrWhiteSpace($one)) { $many += $one }
                            $values[[string]$pair[0]] = if ($many.Count -gt 0) { @($many | Select-Object -Unique) -join ',' } else { 'none' }
                        }
                    }
                }
            }
        }
    }
    return [pscustomobject]@{ ResourceGroup=$resourceGroup; Values=$values }
}

function Set-PopulateVcEnvValue {
    param([System.Collections.Generic.List[string]]$Lines,[string]$Key,[string]$Value)
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=.*$'
    for ($index=0; $index -lt $Lines.Count; $index++) {
        if ($Lines[$index] -match $pattern) { $Lines[$index] = ('{0}={1}' -f $Key,$Value); return }
    }
    $Lines.Add(('{0}={1}' -f $Key,$Value))
}

function Get-PopulateVcFallbackValue {
    param([string]$Key,[string]$VmName,[hashtable]$GlobalConfig,[object]$AzureState)
    if ($AzureState.Values.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$AzureState.Values[$Key])) { return [string]$AzureState.Values[$Key] }
    $globalKey = switch -Exact ($Key) {
        'SELECTED_VM_OS' { 'DEFAULT_VM_OS' }
        'SELECTED_AZURE_REGION' { 'DEFAULT_AZURE_REGION' }
        'VM_STORAGE_SKU' { 'DEFAULT_VM_STORAGE_SKU' }
        'VM_SECURITY_TYPE' { 'DEFAULT_VM_SECURITY_TYPE' }
        'VM_ENABLE_HIBERNATION' { 'DEFAULT_VM_ENABLE_HIBERNATION' }
        'VM_ENABLE_NESTED_VIRTUALIZATION' { 'DEFAULT_VM_ENABLE_NESTED_VIRTUALIZATION' }
        'VM_ENABLE_SECURE_BOOT' { 'DEFAULT_VM_ENABLE_SECURE_BOOT' }
        'VM_ENABLE_VTPM' { 'DEFAULT_VM_ENABLE_VTPM' }
        'VM_ADMIN_USER' { 'DEFAULT_VM_ADMIN_USER' }
        'VM_ASSISTANT_USER' { 'DEFAULT_VM_ASSISTANT_USER' }
        'VM_SSH_PORT' { 'DEFAULT_VM_SSH_PORT' }
        'VM_RDP_PORT' { 'DEFAULT_VM_RDP_PORT' }
        'TCP_PORTS' { 'DEFAULT_TCP_PORTS' }
        'PACKAGE_TRANSPORT' { 'DEFAULT_PACKAGE_TRANSPORT' }
        'WIN_VM_IMAGE' { 'DEFAULT_WIN_VM_IMAGE' }
        'WIN_VM_SIZE' { 'DEFAULT_WIN_VM_SIZE' }
        'WIN_VM_DISK_SIZE_GB' { 'DEFAULT_WIN_VM_DISK_SIZE_GB' }
        'LIN_VM_IMAGE' { 'DEFAULT_LIN_VM_IMAGE' }
        'LIN_VM_SIZE' { 'DEFAULT_LIN_VM_SIZE' }
        'LIN_VM_DISK_SIZE_GB' { 'DEFAULT_LIN_VM_DISK_SIZE_GB' }
        default { $Key }
    }
    if ($Key -eq 'SELECTED_VM_NAME') { return $VmName }
    if ($Key -eq 'VC_PROFILE_SCHEMA_VERSION') { return '2' }
    if ($Key -eq 'VM_INIT_TASKS' -or $Key -eq 'VM_UPDATE_TASKS' -or $Key -eq 'VM_PACKAGE_SETUP_PACKAGES') {
        $selected = [string]$GlobalConfig[$Key]
        return $(if ([string]::IsNullOrWhiteSpace($selected)) { 'all' } else { $selected })
    }
    if ($Key -eq 'VM_TASK_OUTCOME_MODE') { return $(if ([string]::IsNullOrWhiteSpace([string]$GlobalConfig['VM_TASK_OUTCOME_MODE'])) { 'continue' } else { [string]$GlobalConfig['VM_TASK_OUTCOME_MODE'] }) }
    if ($Key -eq 'SSH_TASK_TIMEOUT_SECONDS') { return $(if ([string]::IsNullOrWhiteSpace([string]$GlobalConfig[$Key])) { '180' } else { [string]$GlobalConfig[$Key] }) }
    if ($Key -eq 'SSH_CONNECT_TIMEOUT_SECONDS') { return $(if ([string]::IsNullOrWhiteSpace([string]$GlobalConfig[$Key])) { '30' } else { [string]$GlobalConfig[$Key] }) }
    if ($Key -eq 'SSH_MAX_RETRIES') { return $(if ([string]::IsNullOrWhiteSpace([string]$GlobalConfig[$Key])) { '3' } else { [string]$GlobalConfig[$Key] }) }
    if ($Key -eq 'VM_TASK_OUTCOME_MODE') { return 'continue' }
    if ($Key -eq 'VM_ADMIN_PASS' -or $Key -eq 'VM_ASSISTANT_PASS') { return '@secret-required' }
    if ($Key -eq 'NIC_DNS_SERVERS' -or $Key -like 'NSG_RULE_*' -or $Key -like 'SUBNET_*' -or $Key -like 'VNET_*' -or $Key -like 'NIC_*' -or $Key -like 'PUBLIC_IP_*') { return 'none' }
    if ($GlobalConfig.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$GlobalConfig[$Key])) { return [string]$GlobalConfig[$Key] }
    if (Get-ProdicloudManifestDeclaredSettingKeys | Where-Object { [string]::Equals([string]$_,$Key,[System.StringComparison]::OrdinalIgnoreCase) }) {
        $descriptor = Get-ProdicloudManifestSettingDescriptor -Key $Key
        $settings = @{}; $settings[$Key] = $descriptor
        try { return [string](Get-ProdicloudManifestSettingValueMap -Settings ([pscustomobject]$settings) -ConfigMap @{})[$Key] } catch { }
    }
    if ($Key -like 'SELECTED_COMPANY_*' -or $Key -like 'SELECTED_EMPLOYEE_*' -or $Key -like 'WIN_PUBLIC_SHORTCUT_*') { return '@global' }
    if ($globalKey -and $GlobalConfig.ContainsKey($globalKey) -and -not [string]::IsNullOrWhiteSpace([string]$GlobalConfig[$globalKey])) { return [string]$GlobalConfig[$globalKey] }
    if ($Key -eq 'VM_SECURITY_TYPE') { return 'Standard' }
    return '@global'
}

try {
    $accounts = Invoke-PopulateVcAzureJson -AzArguments @('account','show') -Action 'verify Azure login and selected subscription'
    if ($null -eq $accounts -or -not [string]::Equals([string]$accounts.id,$SubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'Azure CLI account does not match the selected subscription. Run az login and select the configured subscription.' }
    $templateKeys = @(Get-Content -LiteralPath $templatePath | ForEach-Object { if ($_ -match '^([A-Za-z_][A-Za-z0-9_]*)=') { $Matches[1] } })
    $profiles = @(Get-ChildItem -LiteralPath $RepoRoot -File -Filter '*.env' | Where-Object { $_.Name -ine 'prodicloud.env' -and $_.Name -match '^[A-Za-z0-9][A-Za-z0-9-]{0,63}\.env$' })
    foreach ($profileFile in @($profiles)) {
        $vmName = [System.IO.Path]::GetFileNameWithoutExtension($profileFile.Name)
        $profile = Read-DotEnvFile -Path $profileFile.FullName -GlobalOnly
        if ($profile.ContainsKey('SELECTED_VM_NAME') -and -not [string]::Equals([string]$profile['SELECTED_VM_NAME'],$vmName,[System.StringComparison]::OrdinalIgnoreCase)) { throw ("VC profile identity does not match its file name: {0}" -f $profileFile.Name) }
        $azureState = Get-PopulateVcProfileAzureState -Profile $profile -ProfileVmName $vmName
        $rawText = [System.IO.File]::ReadAllText($profileFile.FullName)
        $newline = if ($rawText.Contains("`r`n")) { "`r`n" } else { "`n" }
        $lines = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in @([regex]::Split($rawText,"\r\n|\n|\r"))) { $lines.Add([string]$line) }
        $changedKeys = New-Object 'System.Collections.Generic.List[string]'
        foreach ($key in @($templateKeys)) {
            $current = if ($profile.ContainsKey($key)) { [string]$profile[$key] } else { '' }
            $needsValue = [string]::IsNullOrWhiteSpace($current) -or (Test-ProdicloudConfigPlaceholderValue -Value $current)
            if (-not $needsValue -and $current -ne '@secret-required') { continue }
            if (-not $needsValue) { continue }
            $value = Get-PopulateVcFallbackValue -Key $key -VmName $vmName -GlobalConfig $globalConfig -AzureState $azureState
            if ([string]::IsNullOrWhiteSpace([string]$value)) { $value = '@global' }
            Set-PopulateVcEnvValue -Lines $lines -Key $key -Value ([string]$value)
            $changedKeys.Add([string]$key) | Out-Null
        }
        $valuesAfter = @{}
        foreach ($line in @($lines.ToArray())) { if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)=(.*)$') { $valuesAfter[$Matches[1]] = [string]$Matches[2] } }
        $stillEmpty = @($templateKeys | Where-Object { -not $valuesAfter.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$valuesAfter[$_]) })
        if ($stillEmpty.Count -gt 0) { throw ("VC profile '{0}' still has empty fields after fallback population: {1}" -f $profileFile.Name,($stillEmpty -join ', ')) }
        if ($changedKeys.Count -gt 0 -and $PSCmdlet.ShouldProcess($profileFile.Name,('populate {0} missing values' -f $changedKeys.Count))) {
            $temporaryPath = $profileFile.FullName + '.prodicloud-populate.tmp'
            try {
                [System.IO.File]::WriteAllText($temporaryPath,($lines -join $newline),[System.Text.UTF8Encoding]::new($false))
                Move-Item -LiteralPath $temporaryPath -Destination $profileFile.FullName -Force -ErrorAction Stop
            }
            finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } }
        }
        Write-Host ("VC profile populated: {0}; filled {1} values; missing={2}" -f $profileFile.Name,$changedKeys.Count,$stillEmpty.Count)
    }
}
finally { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
