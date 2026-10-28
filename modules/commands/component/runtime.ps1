# Managed Azure component inventory and CRUD helpers.

function Get-ProdicloudComponentTypeCatalog {
    return @(
        [pscustomobject]@{ Id = 'group'; Label = 'Resource group'; AzureType = 'Microsoft.Resources/resourceGroups' }
        [pscustomobject]@{ Id = 'vm'; Label = 'Virtual machine'; AzureType = 'Microsoft.Compute/virtualMachines' }
        [pscustomobject]@{ Id = 'disk'; Label = 'Managed disk'; AzureType = 'Microsoft.Compute/disks' }
        [pscustomobject]@{ Id = 'vnet'; Label = 'Virtual network'; AzureType = 'Microsoft.Network/virtualNetworks' }
        [pscustomobject]@{ Id = 'subnet'; Label = 'Subnet'; AzureType = 'Microsoft.Network/virtualNetworks/subnets' }
        [pscustomobject]@{ Id = 'nic'; Label = 'Network interface'; AzureType = 'Microsoft.Network/networkInterfaces' }
        [pscustomobject]@{ Id = 'ip'; Label = 'Public IP'; AzureType = 'Microsoft.Network/publicIPAddresses' }
        [pscustomobject]@{ Id = 'nsg'; Label = 'Network security group'; AzureType = 'Microsoft.Network/networkSecurityGroups' }
        [pscustomobject]@{ Id = 'nsg-rule'; Label = 'Network security rule'; AzureType = 'Microsoft.Network/networkSecurityGroups/securityRules' }
    )
}

function Get-ProdicloudComponentTypeIds {
    return @((Get-ProdicloudComponentTypeCatalog | ForEach-Object { [string]$_.Id }))
}

function Get-ProdicloudComponentAzureJson {
    param([string[]]$Arguments)

    $subscription = Get-ProdicloudResolvedSubscriptionContext
    if ($null -eq $subscription -or [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $azArguments = @($Arguments) + @('--subscription', [string]$subscription.SubscriptionId, '-o', 'json', '--only-show-errors')
    $json = az @azArguments 2>$null
    Assert-LastExitCode ('az ' + ($Arguments -join ' '))
    if ([string]::IsNullOrWhiteSpace([string]$json)) { return @() }
    return (ConvertFrom-JsonCompat -InputObject ([string]$json))
}

function Invoke-ProdicloudComponentAzMutation {
    param(
        [string[]]$Arguments,
        [string]$Label
    )

    $subscription = Get-ProdicloudResolvedSubscriptionContext
    if ($null -eq $subscription -or [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $azArguments = @($Arguments) + @('--subscription', [string]$subscription.SubscriptionId, '--only-show-errors')
    Invoke-TrackedAction -Label ([string]$Label) -Action {
        az @azArguments
        Assert-LastExitCode ([string]$Label)
    } | Out-Null
}

function Sync-ProdicloudVmPublicDnsLabel {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Context)

    $vmName = [string]$Context.VmName
    $resourceGroup = [string]$Context.ResourceGroup
    $publicIpName = [string]$Context.IP
    $location = [string]$Context.AzLocation
    $desiredLabel = Resolve-ProdicloudPublicDnsLabel -PublicIpName $publicIpName -VmName $vmName
    if ([string]::IsNullOrWhiteSpace($resourceGroup) -or [string]::IsNullOrWhiteSpace($publicIpName) -or [string]::IsNullOrWhiteSpace($location)) {
        throw 'The selected managed VM is missing its resource group, public IP name, or Azure region; its DNS label cannot be synchronized.'
    }

    Write-Host ("Doing: inspect Azure public IP '{0}' DNS settings for VM '{1}'" -f $publicIpName,$vmName) -ForegroundColor Cyan
    $publicIp = Get-ProdicloudComponentAzureJson -Arguments @('network','public-ip','show','--resource-group',$resourceGroup,'--name',$publicIpName)
    $currentLabel = [string]$publicIp.dnsSettings.domainNameLabel
    $changed = -not [string]::Equals($currentLabel,$desiredLabel,[System.StringComparison]::OrdinalIgnoreCase)
    if ($changed) {
        $subscription = Get-ProdicloudResolvedSubscriptionContext
        if ($null -eq $subscription -or [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) {
            throw "Azure CLI sign-in is required. Run 'az login' and select the target subscription before updating the VM DNS label."
        }
        Assert-ProdicloudPublicDnsLabelAvailable -Label $desiredLabel -Location $location -SubscriptionId ([string]$subscription.SubscriptionId) | Out-Null
        Invoke-ProdicloudComponentAzMutation `
            -Arguments @('network','public-ip','update','--resource-group',$resourceGroup,'--name',$publicIpName,'--dns-name',$desiredLabel,'-o','none') `
            -Label ("az network public-ip update --dns-name {0} for VM {1}" -f $desiredLabel,$vmName)
        Write-Host ("Doing: verify Azure public IP '{0}' DNS settings for VM '{1}'" -f $publicIpName,$vmName) -ForegroundColor Cyan
        $publicIp = Get-ProdicloudComponentAzureJson -Arguments @('network','public-ip','show','--resource-group',$resourceGroup,'--name',$publicIpName)
        $currentLabel = [string]$publicIp.dnsSettings.domainNameLabel
        if (-not [string]::Equals($currentLabel,$desiredLabel,[System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Azure did not confirm public DNS label '{0}' for VM '{1}'." -f $desiredLabel,$vmName)
        }
        Write-Host ("Public DNS label for VM '{0}' is now '{1}' ({2})." -f $vmName,$currentLabel,[string]$publicIp.dnsSettings.fqdn) -ForegroundColor Green
    }
    else {
        Write-Host ("Public DNS label for VM '{0}' is already '{1}'." -f $vmName,$currentLabel) -ForegroundColor Green
    }

    $profilePath = Get-ProdicloudVmEnvPath -VmName $vmName
    $profileDnsLabel = ''
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $profileConfig = Read-DotEnvFile -Path $profilePath -GlobalOnly
        $profileDnsLabel = [string](Get-ConfigValue -Config $profileConfig -Key 'PUBLIC_IP_DNS_LABEL' -DefaultValue '')
    }
    if (-not [string]::Equals($profileDnsLabel,$currentLabel,[System.StringComparison]::OrdinalIgnoreCase)) {
        Set-DotEnvValue -Path $profilePath -Key 'PUBLIC_IP_DNS_LABEL' -Value $currentLabel -VmName $vmName
    }
    return [pscustomobject]@{ Label = $currentLabel; Fqdn = [string]$publicIp.dnsSettings.fqdn; Changed = [bool]$changed }
}

function Get-ProdicloudComponentScopedGroups {
    param([hashtable]$Options)

    $requested = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'group')
    if (-not [string]::IsNullOrWhiteSpace($requested)) {
        Assert-ProdicloudManagedResourceGroup -ResourceGroup $requested -OperationName 'component management'
        return @($requested.Trim())
    }
    $config = Read-DotEnvFile -Path (Join-Path (Get-ProdicloudRepoRoot) 'prodicloud.env')
    $defaultGroup = [string](Get-ConfigValue -Config $config -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($defaultGroup)) {
        Assert-ProdicloudManagedResourceGroup -ResourceGroup $defaultGroup -OperationName 'component management'
        return @($defaultGroup.Trim())
    }
    return @(
        Get-ProdicloudManagedResourceGroupRows |
            ForEach-Object { [string]$_.name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
}

function Get-ProdicloudComponentRowsForGroup {
    param(
        [string]$Type,
        [string]$ResourceGroup
    )

    Assert-ProdicloudManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName 'component inventory'
    switch ([string]$Type) {
        'group' {
            $group = Get-ProdicloudComponentAzureJson -Arguments @('group', 'show', '--name', $ResourceGroup)
            return @([pscustomobject]@{ Name = [string]$group.name; Id = [string]$group.id; ResourceGroup = [string]$group.name; Type = 'Microsoft.Resources/resourceGroups'; Resource = $group })
        }
        'vm' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('vm', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Compute/virtualMachines'; Resource = $_ } })
        }
        'disk' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('disk', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Compute/disks'; Resource = $_ } })
        }
        'vnet' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('network', 'vnet', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/virtualNetworks'; Resource = $_ } })
        }
        'subnet' {
            $rows = @()
            foreach ($vnet in @(Get-ProdicloudComponentRowsForGroup -Type 'vnet' -ResourceGroup $ResourceGroup)) {
                $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('network', 'vnet', 'subnet', 'list', '--resource-group', $ResourceGroup, '--vnet-name', [string]$vnet.Name)))
                foreach ($item in @($items)) {
                    $rows += [pscustomobject]@{ Name = [string]$item.name; Parent = [string]$vnet.Name; Id = [string]$item.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/virtualNetworks/subnets'; Resource = $item }
                }
            }
            return @($rows)
        }
        'nic' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('network', 'nic', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/networkInterfaces'; Resource = $_ } })
        }
        'ip' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('network', 'public-ip', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/publicIPAddresses'; Resource = $_ } })
        }
        'nsg' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('network', 'nsg', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/networkSecurityGroups'; Resource = $_ } })
        }
        'nsg-rule' {
            $rows = @()
            foreach ($nsg in @(Get-ProdicloudComponentRowsForGroup -Type 'nsg' -ResourceGroup $ResourceGroup)) {
                $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('network', 'nsg', 'rule', 'list', '--resource-group', $ResourceGroup, '--nsg-name', [string]$nsg.Name)))
                foreach ($item in @($items)) {
                    $rows += [pscustomobject]@{ Name = [string]$item.name; Parent = [string]$nsg.Name; Id = [string]$item.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/networkSecurityGroups/securityRules'; Resource = $item }
                }
            }
            return @($rows)
        }
        default { throw ("Unsupported component type '{0}'." -f [string]$Type) }
    }
}

function Get-ProdicloudComponentRows {
    param([string]$Type, [string[]]$ResourceGroups)
    $rows = @()
    foreach ($group in @($ResourceGroups)) {
        $rows += @(Get-ProdicloudComponentRowsForGroup -Type $Type -ResourceGroup ([string]$group))
    }
    return @($rows)
}

function Select-ProdicloudComponentRow {
    param([object[]]$Rows, [string]$Name, [string]$Type)
    if (@($Rows).Count -eq 0) { throw ("No {0} components were found in the selected managed resource group." -f [string]$Type) }
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        $match = @($Rows | Where-Object { [string]::Equals([string]$_.Name, $Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($match).Count -eq 0) { throw ("Component '{0}' was not found in the selected resource group." -f $Name) }
        return $match[0]
    }
    for ($index = 0; $index -lt $Rows.Count; $index++) {
        $parentText = if ($Rows[$index].PSObject.Properties.Match('Parent').Count -gt 0) { (' ({0})' -f [string]$Rows[$index].Parent) } else { '' }
        Write-Host ('{0}. {1}{2}' -f ($index + 1), [string]$Rows[$index].Name, $parentText)
    }
    $choice = Read-Host 'Select a component number'
    $number = 0
    if (-not [int]::TryParse([string]$choice, [ref]$number) -or $number -lt 1 -or $number -gt $Rows.Count) {
        throw 'Component selection is invalid.'
    }
    return $Rows[$number - 1]
}

function Get-ProdicloudComponentLocation {
    param([string]$ResourceGroup)
    $group = Get-ProdicloudComponentAzureJson -Arguments @('group', 'show', '--name', $ResourceGroup)
    return [string]$group.location
}

function Get-ProdicloudComponentGeneratedName {
    param([string]$ResourceGroup, [string]$ResourceType)
    $config = Read-DotEnvFile -Path (Join-Path (Get-ProdicloudRepoRoot) 'prodicloud.env')
    $vmName = [string](Get-ConfigValue -Config $config -Key 'SELECTED_VM_NAME' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($vmName)) { $vmName = Read-Host 'Virtual computer name seed' }
    $location = Get-ProdicloudComponentLocation -ResourceGroup $ResourceGroup
    $regionCode = Get-ProdicloudRegionCode -Location $location
    $allocator = New-ProdicloudManagedResourceIndexAllocator
    $templateContract = switch ($ResourceType) {
        'disk' { @{ Key = 'VM_DISK_NAME_TEMPLATE'; Default = 'disk-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'disk' } }
        'net' { @{ Key = 'VNET_NAME_TEMPLATE'; Default = 'vnet-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'net' } }
        'subnet' { @{ Key = 'SUBNET_NAME_TEMPLATE'; Default = 'subnet-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'subnet' } }
        'nic' { @{ Key = 'NIC_NAME_TEMPLATE'; Default = 'nic-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'nic' } }
        'ip' { @{ Key = 'PUBLIC_IP_NAME_TEMPLATE'; Default = 'ip-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'ip' } }
        'nsg' { @{ Key = 'NSG_NAME_TEMPLATE'; Default = 'nsg-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'nsg' } }
        'nsgrule' { @{ Key = 'NSG_RULE_NAME_TEMPLATE'; Default = 'nsg-rule-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'; Type = 'nsgrule' } }
        default { @{ Key = ''; Default = ("{0}-{1}-{2}-n{N}" -f $ResourceType,$vmName,$regionCode); Type = $ResourceType } }
    }
    $template = if ([string]::IsNullOrWhiteSpace([string]$templateContract.Key)) { [string]$templateContract.Default } else { [string](Get-ConfigValue -Config $config -Key ([string]$templateContract.Key) -DefaultValue ([string]$templateContract.Default)) }
    return (Resolve-ProdicloudNameFromTemplate -Template $template -ResourceType ([string]$templateContract.Type) -VmName $vmName -RegionCode $regionCode -ResourceGroup $ResourceGroup -UseNextIndex -IndexAllocator $allocator -LogicalName $ResourceType)
}

function Invoke-ProdicloudComponentCreate {
    param([string]$Type, [string]$ResourceGroup, [hashtable]$Options)

    if ($Type -in @('group','vm')) {
        Write-Host 'Creating a VM creates its managed resource group and required network components as one virtual computer.' -ForegroundColor Cyan
        Invoke-ProdicloudCreateCommand -Options @{} -AutoMode:$false -WindowsFlag:$false -LinuxFlag:$false
        return
    }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { throw 'Choose a managed virtual computer before creating this component.' }
    Assert-ProdicloudManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName ('create ' + $Type)
    $defaultType = switch ($Type) { 'disk' { 'disk' } 'vnet' { 'net' } 'subnet' { 'subnet' } 'nic' { 'nic' } 'ip' { 'ip' } 'nsg' { 'nsg' } 'nsg-rule' { 'nsgrule' } default { $Type } }
    $name = Get-ProdicloudComponentGeneratedName -ResourceGroup $ResourceGroup -ResourceType $defaultType
    $namePrompt = Read-Host ("Name [{0}]" -f $name)
    if (-not [string]::IsNullOrWhiteSpace([string]$namePrompt)) {
        $name = [string]$namePrompt.Trim()
        $customAllocator = New-ProdicloudManagedResourceIndexAllocator
        $customIndex = Register-ProdicloudManagedResourceNameIndex -Allocator $customAllocator -Name $name -LogicalName $Type
        if ($customIndex -lt 1) {
            throw "Managed component names must use an unused global nX suffix, such as '$name-n$($customAllocator.NextIndex)'."
        }
    }
    $location = Get-ProdicloudComponentLocation -ResourceGroup $ResourceGroup
    switch ($Type) {
        'disk' {
            $size = Read-Host 'Size in GB'
            $sku = Read-Host 'Storage tier (Standard_LRS, StandardSSD_LRS, Premium_LRS)'
            if ([string]::IsNullOrWhiteSpace($sku)) { $sku = 'StandardSSD_LRS' }
            Invoke-ProdicloudComponentAzMutation -Arguments @('disk','create','--resource-group',$ResourceGroup,'--name',$name,'--location',$location,'--size-gb',$size,'--sku',$sku) -Label ("az disk create {0}" -f $name)
        }
        'vnet' {
            $prefix = Read-Host 'Address space (for example 10.20.0.0/16)'
            Invoke-ProdicloudComponentAzMutation -Arguments @('network','vnet','create','--resource-group',$ResourceGroup,'--name',$name,'--address-prefixes',$prefix) -Label ("az network vnet create {0}" -f $name)
        }
        'subnet' {
            $vnets = @(Get-ProdicloudComponentRowsForGroup -Type 'vnet' -ResourceGroup $ResourceGroup)
            $vnet = Select-ProdicloudComponentRow -Rows $vnets -Name '' -Type 'virtual network'
            $prefix = Read-Host 'Subnet address prefix'
            Invoke-ProdicloudComponentAzMutation -Arguments @('network','vnet','subnet','create','--resource-group',$ResourceGroup,'--vnet-name',[string]$vnet.Name,'--name',$name,'--address-prefixes',$prefix) -Label ("az network vnet subnet create {0}" -f $name)
        }
        'nic' {
            $subnets = @(Get-ProdicloudComponentRowsForGroup -Type 'subnet' -ResourceGroup $ResourceGroup)
            $subnet = Select-ProdicloudComponentRow -Rows $subnets -Name '' -Type 'subnet'
            $vnetName = [string]$subnet.Parent
            $publicIp = Read-Host 'Public IP name (leave blank for none)'
            $arguments = @('network','nic','create','--resource-group',$ResourceGroup,'--name',$name,'--vnet-name',$vnetName,'--subnet',[string]$subnet.Name)
            if (-not [string]::IsNullOrWhiteSpace($publicIp)) { $arguments += @('--public-ip-address',$publicIp) }
            Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network nic create {0}" -f $name)
        }
        'ip' {
            $arguments = @('network','public-ip','create','--resource-group',$ResourceGroup,'--name',$name,'--location',$location,'--sku','Standard','--allocation-method','Static')
            $dns = Read-Host 'Optional DNS label'
            if (-not [string]::IsNullOrWhiteSpace($dns)) { $arguments += @('--dns-name',$dns) }
            Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network public-ip create {0}" -f $name)
        }
        'nsg' { Invoke-ProdicloudComponentAzMutation -Arguments @('network','nsg','create','--resource-group',$ResourceGroup,'--name',$name,'--location',$location) -Label ("az network nsg create {0}" -f $name) }
        'nsg-rule' {
            $nsgs = @(Get-ProdicloudComponentRowsForGroup -Type 'nsg' -ResourceGroup $ResourceGroup)
            $nsg = Select-ProdicloudComponentRow -Rows $nsgs -Name '' -Type 'network security group'
            $direction = Read-Host 'Direction (Inbound or Outbound)'
            if ($direction -notin @('Inbound','Outbound')) { throw 'Choose Inbound or Outbound.' }
            $access = Read-Host 'Access (Allow or Deny)'
            if ($access -notin @('Allow','Deny')) { throw 'Choose Allow or Deny.' }
            $priority = Read-Host 'Priority (100-4096)'
            if ($priority -notmatch '^\d+$' -or [int]$priority -lt 100 -or [int]$priority -gt 4096) { throw 'Priority must be a number from 100 through 4096.' }
            $protocol = Read-Host 'Protocol (Tcp, Udp, Icmp, or *)'
            if ($protocol -notin @('Tcp','Udp','Icmp','*')) { throw 'Choose Tcp, Udp, Icmp, or *.' }
            $source = Read-Host 'Source address prefix (for example *, Internet, or CIDR)'
            $port = Read-Host 'Destination port or range'
            if ([string]::IsNullOrWhiteSpace($source) -or [string]::IsNullOrWhiteSpace($port)) { throw 'Source and destination port values are required.' }
            $sourcePort = Read-Host 'Source port or range (blank means *)'
            $destination = Read-Host 'Destination address prefix (blank means *)'
            if ([string]::IsNullOrWhiteSpace($sourcePort)) { $sourcePort = '*' }
            if ([string]::IsNullOrWhiteSpace($destination)) { $destination = '*' }
            $arguments = @('network','nsg','rule','create','--resource-group',$ResourceGroup,'--nsg-name',[string]$nsg.Name,'--name',$name,'--priority',$priority,'--direction',$direction,'--access',$access,'--protocol',$protocol,'--source-address-prefixes',$source,'--source-port-ranges',$sourcePort,'--destination-address-prefixes',$destination,'--destination-port-ranges',$port)
            Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network nsg rule create {0}" -f $name)
        }
    }
    Write-Host ("Created {0} '{1}'." -f $Type, $name) -ForegroundColor Green
}

function Sync-ProdicloudComponentProfileAfterVerifiedUpdate {
    param([string]$Type,[object]$Row,[string]$ResourceGroup)

    $repoRoot = Get-ProdicloudRepoRoot
    $globalPath = Get-ProdicloudGlobalEnvPath
    if (-not (Test-Path -LiteralPath $globalPath -PathType Leaf)) { return }
    $globalConfig = Read-DotEnvFile -Path $globalPath -GlobalOnly
    $activeVmName = [string]$globalConfig['ACTIVE_VM_NAME']
    $profiles = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($activeVmName)) {
        $activePath = Get-ProdicloudVmEnvPath -VmName $activeVmName -RepoRoot $repoRoot
        if (Test-Path -LiteralPath $activePath -PathType Leaf) { $profiles.Add($activePath) | Out-Null }
    }
    foreach ($profileFile in @(Get-ChildItem -LiteralPath $repoRoot -File -Filter '*.env' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^[A-Za-z0-9][A-Za-z0-9-]{0,63}\.env$' })) {
        $profilePathCandidate = [string]$profileFile.FullName
        if (-not $profiles.Contains($profilePathCandidate)) { $profiles.Add($profilePathCandidate) | Out-Null }
    }
    $matchingProfiles = @()
    foreach ($profilePath in @($profiles.ToArray())) {
        try {
            $profile = Read-DotEnvFile -Path $profilePath -GlobalOnly
            if ([string]::Equals([string]$profile['SELECTED_RESOURCE_GROUP'],$ResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) { $matchingProfiles += $profilePath }
        }
        catch { continue }
    }
    if ($matchingProfiles.Count -ne 1) { return }
    $profilePath = [string]$matchingProfiles[0]
    $profile = Read-DotEnvFile -Path $profilePath -GlobalOnly
    $vmName = [string]$profile['SELECTED_VM_NAME']
    $ownedDiskName = [string]$profile['VM_DISK_NAME']
    $freshRows = @(Get-ProdicloudComponentRowsForGroup -Type $Type -ResourceGroup $ResourceGroup)
    $verified = @($freshRows | Where-Object { [string]::Equals([string]$_.Name,[string]$Row.Name,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if ($verified.Count -ne 1) { throw ("Updated component '{0}' was not found during Azure readback; its VC profile was not changed." -f [string]$Row.Name) }

    $values = [ordered]@{}
    switch ($Type) {
        'disk' {
            if (-not [string]::Equals([string]$verified[0].Name,$ownedDiskName,[System.StringComparison]::OrdinalIgnoreCase)) { return }
            $platform = [string]$profile['SELECTED_VM_OS']
            $sizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'
            $values[$sizeKey] = [string]$verified[0].Resource.diskSizeGb
            $values['VM_STORAGE_SKU'] = [string]$verified[0].Resource.sku.name
        }
        'vnet' {
            $values['VNET_ADDRESS_PREFIXES'] = @($verified[0].Resource.addressSpace.addressPrefixes | ForEach-Object { [string]$_ }) -join ','
        }
        'subnet' {
            $values['SUBNET_ADDRESS_PREFIXES'] = [string]$verified[0].Resource.addressPrefix
            if ($verified[0].Resource.PSObject.Properties.Match('addressPrefixes').Count -gt 0 -and $verified[0].Resource.addressPrefixes) { $values['SUBNET_ADDRESS_PREFIXES'] = @($verified[0].Resource.addressPrefixes | ForEach-Object { [string]$_ }) -join ',' }
            $nsgId = [string]$verified[0].Resource.networkSecurityGroup.id
            $values['SUBNET_NSG_NAME'] = if ([string]::IsNullOrWhiteSpace($nsgId)) { '' } else { [string]($nsgId -split '/')[-1] }
        }
        'nic' {
            $resource = $verified[0].Resource
            $values['NIC_ENABLE_IP_FORWARDING'] = ([bool]$resource.enableIpForwarding).ToString().ToLowerInvariant()
            $values['NIC_DNS_SERVERS'] = @($resource.dnsSettings.dnsServers | ForEach-Object { [string]$_ }) -join ','
            $ipConfiguration = @(ConvertTo-ObjectArrayCompat -InputObject $resource.ipConfigurations | Select-Object -First 1)
            if ($ipConfiguration.Count -gt 0) {
                $values['NIC_PRIVATE_IP_ALLOCATION'] = [string]$ipConfiguration[0].privateIPAllocationMethod
                $values['NIC_PRIVATE_IP_ADDRESS'] = [string]$ipConfiguration[0].privateIPAddress
                $publicIpId = [string]$ipConfiguration[0].publicIPAddress.id
                $values['NIC_PUBLIC_IP_NAME'] = if ([string]::IsNullOrWhiteSpace($publicIpId)) { '' } else { [string]($publicIpId -split '/')[-1] }
            }
        }
        'ip' {
            $values['PUBLIC_IP_DNS_LABEL'] = [string]$verified[0].Resource.dnsSettings.domainNameLabel
            $values['PUBLIC_IP_ALLOCATION_METHOD'] = [string]$verified[0].Resource.publicIPAllocationMethod
            $values['PUBLIC_IP_SKU'] = [string]$verified[0].Resource.sku.name
        }
        'nsg-rule' {
            $resource = $verified[0].Resource
            $values['NSG_RULE_PRIORITY'] = [string]$resource.priority
            $values['NSG_RULE_DIRECTION'] = [string]$resource.direction
            $values['NSG_RULE_ACCESS'] = [string]$resource.access
            $values['NSG_RULE_PROTOCOL'] = [string]$resource.protocol
            $values['NSG_RULE_SOURCE_ADDRESS_PREFIXES'] = @(@($resource.sourceAddressPrefixes) + @($resource.sourceAddressPrefix) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Select-Object -Unique) -join ','
            $values['NSG_RULE_SOURCE_PORT_RANGES'] = @(@($resource.sourcePortRanges) + @($resource.sourcePortRange) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Select-Object -Unique) -join ','
            $values['NSG_RULE_DESTINATION_ADDRESS_PREFIXES'] = @(@($resource.destinationAddressPrefixes) + @($resource.destinationAddressPrefix) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Select-Object -Unique) -join ','
            $values['NSG_RULE_DESTINATION_PORT_RANGES'] = @(@($resource.destinationPortRanges) + @($resource.destinationPortRange) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ } | Select-Object -Unique) -join ','
        }
        default { return }
    }
    foreach ($key in @($values.Keys)) { Set-DotEnvValue -Path $profilePath -Key ([string]$key) -Value ([string]$values[$key]) }
    Write-Host ("Verified component properties were saved to {0}.env for VC '{1}'." -f [System.IO.Path]::GetFileNameWithoutExtension($profilePath),$vmName) -ForegroundColor Green
}

function Invoke-ProdicloudComponentUpdate {
    param([string]$Type, [object]$Row, [string]$ResourceGroup)

    if ($Type -ne 'group') {
        Write-Host 't: edit resource tags | p: edit component properties'
        $mode = (Read-Host 'Update mode').Trim().ToLowerInvariant()
        if ($mode -eq 't') {
            $key = Read-Host 'Tag name (managed-by is reserved)'
            if ([string]::Equals($key,'managed-by',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The managed-by tag is reserved for Prodicloud ownership.' }
            $value = Read-Host 'Tag value'
            Invoke-ProdicloudComponentAzMutation -Arguments @('tag','update','--resource-id',[string]$Row.Id,'--operation','Merge','--tags',('{0}={1}' -f $key,$value)) -Label ("az tag update {0}" -f [string]$Row.Name)
            Write-Host ("Updated tags for {0}." -f [string]$Row.Name) -ForegroundColor Green
            return
        }
        if ($mode -ne 'p') { throw 'Select tags or component properties.' }
    }

    switch ($Type) {
        'group' {
            $key = Read-Host 'Tag name'
            if ([string]::Equals($key,'managed-by',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The managed-by tag is reserved for Prodicloud ownership.' }
            $value = Read-Host 'Tag value'
            $group = Get-ProdicloudComponentAzureJson -Arguments @('group','show','--name',$ResourceGroup)
            $tags = @()
            if ($group.tags) {
                foreach ($property in @($group.tags.PSObject.Properties)) {
                    $tagValue = [string]$property.Value
                    if ([string]::Equals([string]$property.Name,$key,[System.StringComparison]::OrdinalIgnoreCase)) { $tagValue = $value }
                    $tags += ('{0}={1}' -f [string]$property.Name,$tagValue)
                }
            }
            if (@($tags | Where-Object { $_ -like ($key + '=*') }).Count -eq 0) { $tags += ('{0}={1}' -f $key,$value) }
            Invoke-ProdicloudComponentAzMutation -Arguments (@('group','update','--name',$ResourceGroup,'--tags') + $tags) -Label ("az group update {0} tags" -f $ResourceGroup)
        }
        'vm' {
            Write-Host 's: change compute size | h: change hibernation | n: change nested virtualization'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            $options = @{ group = $ResourceGroup; 'vm-name' = [string]$Row.Name }
            if ($choice -eq 's') {
                $options['vm-size'] = Read-Host 'New VM size'
                Invoke-ProdicloudResizeCommand -Options $options -WindowsFlag:$false -LinuxFlag:$false -AutoMode:$false
            }
            elseif ($choice -in @('h','n')) {
                $value = Read-Host 'Enable? (true or false)'
                if ($choice -eq 'h') { $options['hibernation'] = $value } else { $options['nested-virtualization'] = $value }
                Invoke-ProdicloudSetCommand -Options $options -AutoMode:$false -WindowsFlag:$false -LinuxFlag:$false
            }
            else { throw 'Select a supported VM property.' }
        }
        'disk' {
            $size = Read-Host ("New size in GB (current {0})" -f [string]$Row.Resource.diskSizeGb)
            if ([string]::IsNullOrWhiteSpace($size)) { $size = [string]$Row.Resource.diskSizeGb }
            if ([int]$size -lt [int]$Row.Resource.diskSizeGb) {
                throw 'Azure disk shrink is not performed. Use the resize guidance flow to review safe alternatives.'
            }
            Invoke-ProdicloudComponentAzMutation -Arguments @('disk','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--size-gb',$size) -Label ("az disk update {0}" -f [string]$Row.Name)
            $sku = Read-Host ("New storage tier (current {0}; blank keeps it)" -f [string]$Row.Resource.sku.name)
            if (-not [string]::IsNullOrWhiteSpace($sku)) { Invoke-ProdicloudComponentAzMutation -Arguments @('disk','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--sku',$sku) -Label ("az disk update {0} SKU" -f [string]$Row.Name) }
        }
        'vnet' {
            $prefix = Read-Host 'New address prefixes (comma separated)'
            Invoke-ProdicloudComponentAzMutation -Arguments @('network','vnet','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--address-prefixes',$prefix) -Label ("az network vnet update {0}" -f [string]$Row.Name)
        }
        'subnet' {
            $prefix = Read-Host 'New address prefix'
            $arguments = @('network','vnet','subnet','update','--resource-group',$ResourceGroup,'--vnet-name',[string]$Row.Parent,'--name',[string]$Row.Name,'--address-prefixes',$prefix)
            $nsg = Read-Host 'Network security group name (leave blank to keep current association)'
            if (-not [string]::IsNullOrWhiteSpace($nsg)) { $arguments += @('--network-security-group',$nsg) }
            Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network vnet subnet update {0}" -f [string]$Row.Name)
        }
        'nic' {
                Write-Host 'f: IP forwarding | i: private IP configuration | d: DNS servers | p: public IP association'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            if ($choice -eq 'f') {
                $value = (Read-Host 'Enable IP forwarding? (true or false)').Trim().ToLowerInvariant()
                if ($value -notin @('true','false')) { throw 'Enter true or false.' }
                Invoke-ProdicloudComponentAzMutation -Arguments @('network','nic','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--ip-forwarding',$value) -Label ("az network nic update {0}" -f [string]$Row.Name)
            }
            elseif ($choice -eq 'i') {
                $configs = @(ConvertTo-ObjectArrayCompat -InputObject $Row.Resource.ipConfigurations)
                if ($configs.Count -eq 0) { throw 'The network interface has no IP configuration to update.' }
                $configName = [string]$configs[0].name
                $mode = (Read-Host 'Private IP allocation: Dynamic or Static').Trim()
                $arguments = @('network','nic','ip-config','update','--resource-group',$ResourceGroup,'--nic-name',[string]$Row.Name,'--name',$configName,'--private-ip-address-version','IPv4')
                if ([string]::Equals($mode,'Static',[System.StringComparison]::OrdinalIgnoreCase)) {
                    $address = Read-Host 'Private IP address'
                    $arguments += @('--private-ip-address',$address,'--private-ip-allocation','Static')
                }
                else { $arguments += @('--private-ip-allocation','Dynamic') }
                Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network nic ip-config update {0}" -f [string]$Row.Name)
            }
            elseif ($choice -eq 'd') {
                $dns = Read-Host 'DNS servers (comma separated; blank clears)'
                $arguments = @('network','nic','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name)
                if ([string]::IsNullOrWhiteSpace($dns)) { $arguments += @('--dns-servers','') } else { $arguments += @('--dns-servers') + @($dns -split ',' | ForEach-Object { $_.Trim() }) }
                Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network nic update {0}" -f [string]$Row.Name)
            }
            elseif ($choice -eq 'p') {
                $configs = @(ConvertTo-ObjectArrayCompat -InputObject $Row.Resource.ipConfigurations)
                if ($configs.Count -eq 0) { throw 'The network interface has no IP configuration to update.' }
                $configName = [string]$configs[0].name
                $publicIps = @(Get-ProdicloudComponentRowsForGroup -Type 'ip' -ResourceGroup $ResourceGroup)
                Write-Host 'Enter a public IP name to associate it, or type none to detach it.'
                foreach ($publicIp in @($publicIps)) { Write-Host ('  {0}' -f [string]$publicIp.Name) }
                $publicIpName = (Read-Host 'Public IP name or none').Trim()
                $arguments = @('network','nic','ip-config','update','--resource-group',$ResourceGroup,'--nic-name',[string]$Row.Name,'--name',$configName)
                if ([string]::Equals($publicIpName,'none',[System.StringComparison]::OrdinalIgnoreCase)) { $arguments += @('--remove','publicIpAddress') }
                elseif (-not [string]::IsNullOrWhiteSpace($publicIpName)) { $arguments += @('--public-ip-address',$publicIpName) }
                else { throw 'Enter a public IP name or none.' }
                Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network nic ip-config update {0} public IP" -f [string]$Row.Name)
            }
            else { throw 'Select a supported network interface property.' }
        }
        'ip' {
            Write-Host 'd: DNS label | a: IP allocation | s: SKU'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            $arguments = @('network','public-ip','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name)
            if ($choice -eq 'd') {
                $dns = Read-Host 'New DNS label'
                if ([string]::IsNullOrWhiteSpace($dns)) { $arguments += @('--remove','dnsSettings.domainNameLabel') }
                else {
                    $currentDns = [string]$Row.Resource.dnsSettings.domainNameLabel
                    if (-not [string]::Equals($currentDns,$dns,[System.StringComparison]::OrdinalIgnoreCase)) {
                        $location = [string]$Row.Resource.location
                        if ([string]::IsNullOrWhiteSpace($location)) { $location = Get-ProdicloudComponentLocation -ResourceGroup $ResourceGroup }
                        $subscription = Get-ProdicloudResolvedSubscriptionContext
                        if ($null -eq $subscription -or [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) { throw "Azure CLI sign-in is required. Run 'az login' and select a subscription before changing the public DNS label." }
                        Assert-ProdicloudPublicDnsLabelAvailable -Label $dns -Location $location -SubscriptionId ([string]$subscription.SubscriptionId) | Out-Null
                    }
                    $arguments += @('--dns-name',$dns)
                }
            }
            elseif ($choice -eq 'a') {
                $method = (Read-Host 'Allocation: Static or Dynamic').Trim()
                if ($method -notin @('Static','Dynamic')) { throw 'Choose Static or Dynamic.' }
                $arguments += @('--allocation-method',$method)
            }
            elseif ($choice -eq 's') {
                $sku = (Read-Host 'SKU: Standard or Basic').Trim()
                if ($sku -notin @('Standard','Basic')) { throw 'Choose Standard or Basic.' }
                $arguments += @('--sku',$sku)
            }
            else { throw 'Select a supported public IP property.' }
            Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network public-ip update {0}" -f [string]$Row.Name)
        }
        'nsg' {
            $key = Read-Host 'Tag name'
            $value = Read-Host 'Tag value'
            Invoke-ProdicloudComponentAzMutation -Arguments @('network','nsg','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--add',('tags.{0}={1}' -f $key,$value)) -Label ("az network nsg update {0}" -f [string]$Row.Name)
        }
        'nsg-rule' {
            Write-Host 'p: priority | d: direction | a: allow/deny | r: protocol | s: source | t: destination'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            $arguments = @('network','nsg','rule','update','--resource-group',$ResourceGroup,'--nsg-name',[string]$Row.Parent,'--name',[string]$Row.Name)
            switch ($choice) {
                'p' {
                    $value = Read-Host 'Priority (100-4096)'
                    if ($value -notmatch '^\d+$' -or [int]$value -lt 100 -or [int]$value -gt 4096) { throw 'Priority must be a number from 100 through 4096.' }
                    $arguments += @('--priority',$value)
                }
                'd' {
                    $value = Read-Host 'Direction (Inbound or Outbound)'
                    if ($value -notin @('Inbound','Outbound')) { throw 'Choose Inbound or Outbound.' }
                    $arguments += @('--direction',$value)
                }
                'a' {
                    $value = Read-Host 'Access (Allow or Deny)'
                    if ($value -notin @('Allow','Deny')) { throw 'Choose Allow or Deny.' }
                    $arguments += @('--access',$value)
                }
                'r' {
                    $value = Read-Host 'Protocol (Tcp, Udp, Icmp, or *)'
                    if ($value -notin @('Tcp','Udp','Icmp','*')) { throw 'Choose Tcp, Udp, Icmp, or *.' }
                    $arguments += @('--protocol',$value)
                }
                's' {
                    $address = Read-Host 'Source address prefix'
                    $port = Read-Host 'Source port range'
                    $arguments += @('--source-address-prefixes',$address,'--source-port-ranges',$port)
                }
                't' {
                    $address = Read-Host 'Destination address prefix'
                    $port = Read-Host 'Destination port range'
                    $arguments += @('--destination-address-prefixes',$address,'--destination-port-ranges',$port)
                }
                default { throw 'Choose a supported network security rule property.' }
            }
            Invoke-ProdicloudComponentAzMutation -Arguments $arguments -Label ("az network nsg rule update {0}" -f [string]$Row.Name)
        }
    }
    Write-Host ("Updated {0} '{1}'." -f $Type, [string]$Row.Name) -ForegroundColor Green
    if ($Type -in @('disk','vnet','subnet','nic','ip','nsg-rule')) {
        Sync-ProdicloudComponentProfileAfterVerifiedUpdate -Type $Type -Row $Row -ResourceGroup $ResourceGroup
    }
}

function Get-ProdicloudComponentReferenceIds {
    param([object]$Value)
    $ids = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ($Value -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/') { [void]$ids.Add($Value.TrimEnd('/')) }
        return @($ids.ToArray())
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) { foreach ($id in @(Get-ProdicloudComponentReferenceIds -Value $item)) { [void]$ids.Add([string]$id) } }
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { foreach ($id in @(Get-ProdicloudComponentReferenceIds -Value $item)) { [void]$ids.Add([string]$id) } }
    }
    elseif ($Value -is [psobject]) {
        foreach ($property in @($Value.PSObject.Properties)) { foreach ($id in @(Get-ProdicloudComponentReferenceIds -Value $property.Value)) { [void]$ids.Add([string]$id) } }
    }
    return @($ids.ToArray() | Sort-Object -Unique)
}

function Get-ProdicloudComponentDeletePlan {
    param([string]$Type, [object]$SelectedRow, [string]$ResourceGroup)

    $allResources = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ProdicloudComponentAzureJson -Arguments @('resource','list','--resource-group',$ResourceGroup)))
    foreach ($nestedType in @('subnet','nsg-rule')) {
        foreach ($nestedRow in @(Get-ProdicloudComponentRowsForGroup -Type $nestedType -ResourceGroup $ResourceGroup)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$nestedRow.Id) -and @($allResources | Where-Object { [string]::Equals([string]$_.id,[string]$nestedRow.Id,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                $allResources += [pscustomobject]@{ id = [string]$nestedRow.Id; name = [string]$nestedRow.Name; type = [string]$nestedRow.Type; properties = $nestedRow.Resource }
            }
        }
    }
    $selectedId = [string]$SelectedRow.Id
    if ([string]::IsNullOrWhiteSpace($selectedId)) { throw 'Azure did not return a resource id for the selected component.' }
    $resourceDetails = @()
    foreach ($resource in @($allResources)) {
        try { $resourceDetails += (Get-ProdicloudComponentAzureJson -Arguments @('resource','show','--ids',[string]$resource.id)) }
        catch { $resourceDetails += $resource }
    }
    if ([string]::Equals($Type,'group',[System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($resource in @($resourceDetails)) {
            foreach ($referenceId in @(Get-ProdicloudComponentReferenceIds -Value $resource)) {
                if ($referenceId -match '(?i)/resourceGroups/(?<group>[^/]+)/providers/' -and -not [string]::Equals([string]$Matches.group,$ResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ("Resource '{0}' is linked to an Azure resource outside this managed group. Unlink it explicitly before deleting the group." -f [string]$resource.name)
                }
            }
        }
        return @($resourceDetails | Sort-Object { Get-ProdicloudComponentDeletePriority -ResourceType ([string]$_.type) }, { [string]$_.name })
    }
    $selected = @($resourceDetails | Where-Object { [string]::Equals([string]$_.id,$selectedId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($selected).Count -eq 0) { $selected = @($SelectedRow.Resource) }
    $included = @{}
    $included[$selectedId.ToLowerInvariant()] = $true
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($resource in @($resourceDetails)) {
            $id = [string]$resource.id
            if ([string]::IsNullOrWhiteSpace($id) -or $included.ContainsKey($id.ToLowerInvariant())) { continue }
            $refs = @(Get-ProdicloudComponentReferenceIds -Value $resource)
            if (@($refs | Where-Object { $included.ContainsKey(([string]$_).ToLowerInvariant()) }).Count -gt 0) {
                $included[$id.ToLowerInvariant()] = $true
                $changed = $true
            }
        }
        foreach ($resource in @($resourceDetails)) {
            $id = [string]$resource.id
            if ([string]::IsNullOrWhiteSpace($id) -or -not $included.ContainsKey($id.ToLowerInvariant())) { continue }
            foreach ($referenceId in @(Get-ProdicloudComponentReferenceIds -Value $resource)) {
                $referenced = @($resourceDetails | Where-Object { [string]::Equals([string]$_.id,[string]$referenceId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                if (@($referenced).Count -gt 0 -and -not $included.ContainsKey(([string]$referenceId).ToLowerInvariant())) {
                    $included[([string]$referenceId).ToLowerInvariant()] = $true
                    $changed = $true
                }
            }
        }
    }
    $plan = @($resourceDetails | Where-Object { $included.ContainsKey(([string]$_.id).ToLowerInvariant()) })
    foreach ($resource in @($plan)) {
        foreach ($referenceId in @(Get-ProdicloudComponentReferenceIds -Value $resource)) {
            if ($referenceId -match '(?i)/resourceGroups/(?<group>[^/]+)/providers/' -and -not [string]::Equals([string]$Matches.group,$ResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) {
                throw ("Component '{0}' references a resource outside its managed resource group. Unlink it explicitly before deleting this chain." -f [string]$resource.name)
            }
        }
    }
    return @($plan | Sort-Object { Get-ProdicloudComponentDeletePriority -ResourceType ([string]$_.type) }, { [string]$_.name })
}

function Get-ProdicloudComponentDeletePriority {
    param([string]$ResourceType)
    switch -Regex ($ResourceType) {
        'Microsoft.Compute/virtualMachines' { return 10 }
        'Microsoft.Compute/disks' { return 20 }
        'Microsoft.Network/networkInterfaces' { return 30 }
        'Microsoft.Network/publicIPAddresses' { return 40 }
        'Microsoft.Network/virtualNetworks/subnets' { return 50 }
        'Microsoft.Network/networkSecurityGroups/securityRules' { return 60 }
        'Microsoft.Network/networkSecurityGroups' { return 70 }
        'Microsoft.Network/virtualNetworks' { return 80 }
        default { return 90 }
    }
}

function Invoke-ProdicloudComponentDelete {
    param([string]$Type, [object]$SelectedRow, [string]$ResourceGroup, [hashtable]$Options)
    $plan = @(Get-ProdicloudComponentDeletePlan -Type $Type -SelectedRow $SelectedRow -ResourceGroup $ResourceGroup)
    if ($plan.Count -eq 0) { throw 'No Azure resources were found in the deletion plan.' }
    Write-Host 'These resources and linked dependencies will be deleted:' -ForegroundColor Yellow
    foreach ($resource in @($plan)) { Write-Host ('  - {0}: {1}' -f [string]$resource.type,[string]$resource.name) }
    $approved = Get-ProdicloudCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
    if (-not $approved) {
        $required = if ($plan.Count -gt 1) { 'DELETE ALL' } else { [string]$SelectedRow.Name }
        $confirmation = Read-Host ("Type '{0}' to confirm" -f $required)
        $approved = [string]::Equals([string]$confirmation,[string]$required,[System.StringComparison]::Ordinal)
    }
    if (-not $approved) { Write-Host 'Deletion canceled; no resource was changed.' -ForegroundColor Yellow; return }

    if ([string]::Equals($Type,'group',[System.StringComparison]::OrdinalIgnoreCase)) {
        Invoke-ProdicloudComponentAzMutation -Arguments @('group','delete','--name',$ResourceGroup,'--yes','--no-wait') -Label ("az group delete {0}" -f $ResourceGroup)
        $deletionWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $groupDeleted = $false
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            $subscription = Get-ProdicloudResolvedSubscriptionContext
            Write-ProdicloudActionProgress -Action ("verify resource group '{0}' deletion (check {1}/20)" -f $ResourceGroup,$attempt)
            $groupExists = az group exists --name $ResourceGroup --subscription ([string]$subscription.SubscriptionId) --only-show-errors
            Assert-LastExitCode 'az group exists (delete verification)'
            if ([string]::Equals([string]$groupExists,'false',[System.StringComparison]::OrdinalIgnoreCase)) {
                $groupDeleted = $true
                break
            }
            if ($attempt -lt 20) {
                Write-ProdicloudActionProgress -Action ("resource group '{0}' is still deleting; next check in 30 seconds ({1:N0}s elapsed)" -f $ResourceGroup,$deletionWatch.Elapsed.TotalSeconds)
                Start-Sleep -Seconds 30
            }
        }
        $deletionWatch.Stop()
        if (-not $groupDeleted) { throw ("Resource group '{0}' was not deleted within the bounded 600-second verification window." -f $ResourceGroup) }
        Write-Host ("Resource group '{0}' and all listed resources were deleted ({1:N1}s)." -f $ResourceGroup,$deletionWatch.Elapsed.TotalSeconds) -ForegroundColor Green
        return
    }

    foreach ($resource in @($plan)) {
        $resourceId = [string]$resource.id
        $subscription = Get-ProdicloudResolvedSubscriptionContext
        az resource show --ids $resourceId --subscription ([string]$subscription.SubscriptionId) -o none --only-show-errors 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("Already absent: {0}" -f [string]$resource.name) -ForegroundColor DarkGray
            continue
        }
        try {
            Invoke-ProdicloudComponentAzMutation -Arguments @('resource','delete','--ids',$resourceId) -Label ("az resource delete {0}" -f [string]$resource.name)
        }
        catch {
            az resource show --ids $resourceId --subscription ([string]$subscription.SubscriptionId) -o none --only-show-errors 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { throw }
        }
        $removed = $false
        for ($attempt = 0; $attempt -lt 12; $attempt++) {
            $subscription = Get-ProdicloudResolvedSubscriptionContext
            $showArgs = @('resource','show','--ids',$resourceId,'--subscription',[string]$subscription.SubscriptionId,'-o','none','--only-show-errors')
            az @showArgs 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $removed = $true; break }
            Write-ProdicloudActionProgress -Action ("wait 5s for Azure to confirm deletion of '{0}'" -f [string]$resource.name)
            Start-Sleep -Seconds 5
        }
        if (-not $removed) { throw ("Azure did not confirm deletion of '{0}' within the bounded wait." -f [string]$resource.name) }
        Write-Host ('Deleted: {0}' -f [string]$resource.name) -ForegroundColor Green
    }
}

function Invoke-ProdicloudComponentAttachment {
    param([string]$Action, [string]$Type, [string]$ResourceGroup, [object]$Row, [hashtable]$Options)
    if ($Type -notin @('disk','nic')) { throw 'Only managed disks and network interfaces support attach/detach actions.' }
    $vms = @(Get-ProdicloudComponentRowsForGroup -Type 'vm' -ResourceGroup $ResourceGroup)
    $requestedVm = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-name')
    $vm = Select-ProdicloudComponentRow -Rows $vms -Name $requestedVm -Type 'virtual machine'
    if ($Type -eq 'disk') {
        if ($Action -eq 'attach') {
            $vmDetails = Get-ProdicloudComponentAzureJson -Arguments @('vm','show','--resource-group',$ResourceGroup,'--name',[string]$vm.Name)
            $existing = @(ConvertTo-ObjectArrayCompat -InputObject $vmDetails.storageProfile.dataDisks)
            $luns = @($existing | ForEach-Object { [int]$_.lun })
            $lun = 0
            while ($luns -contains $lun) { $lun++ }
            Invoke-ProdicloudComponentAzMutation -Arguments @('vm','disk','attach','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--name',[string]$Row.Name,'--lun',[string]$lun) -Label ("az vm disk attach {0}" -f [string]$Row.Name)
        }
        else {
            Invoke-ProdicloudComponentAzMutation -Arguments @('vm','disk','detach','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--name',[string]$Row.Name) -Label ("az vm disk detach {0}" -f [string]$Row.Name)
        }
    }
    else {
        if ($Action -eq 'attach') {
            Invoke-ProdicloudComponentAzMutation -Arguments @('vm','nic','add','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--nics',[string]$Row.Name) -Label ("az vm nic add {0}" -f [string]$Row.Name)
        }
        else {
            Invoke-ProdicloudComponentAzMutation -Arguments @('vm','nic','remove','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--nics',[string]$Row.Name) -Label ("az vm nic remove {0}" -f [string]$Row.Name)
        }
    }
    Write-Host ("{0} {1} '{2}' {3} VM '{4}'." -f $Action,$Type,[string]$Row.Name,$Action,[string]$vm.Name) -ForegroundColor Green
}

function Invoke-ProdicloudComponentOperation {
    param(
        [string]$Action,
        [string]$Type,
        [string]$Name,
        [string]$ResourceGroup,
        [hashtable]$Options,
        [switch]$AutoMode
    )

    if ((Get-ProdicloudComponentTypeIds) -notcontains $Type) { throw ("Unsupported Prodicloud component type '{0}'." -f $Type) }
    $groups = @(Get-ProdicloudComponentScopedGroups -Options $Options)
    if ($Action -eq 'create' -and $Type -in @('group','vm')) {
        Invoke-ProdicloudComponentCreate -Type $Type -ResourceGroup $ResourceGroup -Options $Options
        return
    }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        if ($groups.Count -eq 0) { throw 'No Prodicloud-managed resource group is available.' }
        $selectedGroup = Select-ProdicloudResourceGroupInteractive -DefaultResourceGroup '' -VmName ''
        $ResourceGroup = [string]$selectedGroup
    }
    Assert-ProdicloudManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName ('component ' + $Action)
    if ($Action -eq 'create') {
        Invoke-ProdicloudComponentCreate -Type $Type -ResourceGroup $ResourceGroup -Options $Options
        return
    }
    $rows = @(Get-ProdicloudComponentRowsForGroup -Type $Type -ResourceGroup $ResourceGroup)
    if ($Action -eq 'list') {
        if ($rows.Count -eq 0) { Write-Host 'No components of this type were found.' -ForegroundColor Yellow; return }
        foreach ($row in @($rows)) { Write-Host ('{0} | {1} | {2}' -f [string]$row.Name,[string]$row.Type,[string]$ResourceGroup) }
        return
    }
    $row = Select-ProdicloudComponentRow -Rows $rows -Name $Name -Type $Type
    if ($Action -in @('attach','detach')) { Invoke-ProdicloudComponentAttachment -Action $Action -Type $Type -ResourceGroup $ResourceGroup -Row $row -Options $Options; return }
    if ($Action -eq 'show') {
        Write-Host ('{0}: {1}' -f $Type,[string]$row.Name) -ForegroundColor Cyan
        Write-Host (ConvertTo-JsonCompat -InputObject $row.Resource -Depth 10)
        return
    }
    if ($Action -eq 'update') { Invoke-ProdicloudComponentUpdate -Type $Type -Row $row -ResourceGroup $ResourceGroup; return }
    if ($Action -eq 'delete') { Invoke-ProdicloudComponentDelete -Type $Type -SelectedRow $row -ResourceGroup $ResourceGroup -Options $Options; return }
    throw ("Unsupported component action '{0}'." -f $Action)
}
