# Managed Azure component inventory and CRUD helpers.

function Get-ClagnosComponentTypeCatalog {
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

function Get-ClagnosComponentTypeIds {
    return @((Get-ClagnosComponentTypeCatalog | ForEach-Object { [string]$_.Id }))
}

function Get-ClagnosComponentAzureJson {
    param([string[]]$Arguments)

    $subscription = Get-ClagnosResolvedSubscriptionContext
    if ($null -eq $subscription -or [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $azArguments = @($Arguments) + @('--subscription', [string]$subscription.SubscriptionId, '-o', 'json', '--only-show-errors')
    $json = az @azArguments 2>$null
    Assert-LastExitCode ('az ' + ($Arguments -join ' '))
    if ([string]::IsNullOrWhiteSpace([string]$json)) { return @() }
    return (ConvertFrom-JsonCompat -InputObject ([string]$json))
}

function Invoke-ClagnosComponentAzMutation {
    param(
        [string[]]$Arguments,
        [string]$Label
    )

    $subscription = Get-ClagnosResolvedSubscriptionContext
    if ($null -eq $subscription -or [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $azArguments = @($Arguments) + @('--subscription', [string]$subscription.SubscriptionId, '--only-show-errors')
    Invoke-TrackedAction -Label ([string]$Label) -Action {
        az @azArguments
        Assert-LastExitCode ([string]$Label)
    } | Out-Null
}

function Get-ClagnosComponentScopedGroups {
    param([hashtable]$Options)

    $requested = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    if (-not [string]::IsNullOrWhiteSpace($requested)) {
        Assert-ClagnosManagedResourceGroup -ResourceGroup $requested -OperationName 'component management'
        return @($requested.Trim())
    }
    $config = Read-DotEnvFile -Path (Join-Path (Get-ClagnosRepoRoot) 'clagnos.env')
    $defaultGroup = [string](Get-ConfigValue -Config $config -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($defaultGroup)) {
        Assert-ClagnosManagedResourceGroup -ResourceGroup $defaultGroup -OperationName 'component management'
        return @($defaultGroup.Trim())
    }
    return @(
        Get-ClagnosManagedResourceGroupRows |
            ForEach-Object { [string]$_.name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
}

function Get-ClagnosComponentRowsForGroup {
    param(
        [string]$Type,
        [string]$ResourceGroup
    )

    Assert-ClagnosManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName 'component inventory'
    switch ([string]$Type) {
        'group' {
            $group = Get-ClagnosComponentAzureJson -Arguments @('group', 'show', '--name', $ResourceGroup)
            return @([pscustomobject]@{ Name = [string]$group.name; Id = [string]$group.id; ResourceGroup = [string]$group.name; Type = 'Microsoft.Resources/resourceGroups'; Resource = $group })
        }
        'vm' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('vm', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Compute/virtualMachines'; Resource = $_ } })
        }
        'disk' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('disk', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Compute/disks'; Resource = $_ } })
        }
        'vnet' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('network', 'vnet', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/virtualNetworks'; Resource = $_ } })
        }
        'subnet' {
            $rows = @()
            foreach ($vnet in @(Get-ClagnosComponentRowsForGroup -Type 'vnet' -ResourceGroup $ResourceGroup)) {
                $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('network', 'vnet', 'subnet', 'list', '--resource-group', $ResourceGroup, '--vnet-name', [string]$vnet.Name)))
                foreach ($item in @($items)) {
                    $rows += [pscustomobject]@{ Name = [string]$item.name; Parent = [string]$vnet.Name; Id = [string]$item.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/virtualNetworks/subnets'; Resource = $item }
                }
            }
            return @($rows)
        }
        'nic' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('network', 'nic', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/networkInterfaces'; Resource = $_ } })
        }
        'ip' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('network', 'public-ip', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/publicIPAddresses'; Resource = $_ } })
        }
        'nsg' {
            $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('network', 'nsg', 'list', '--resource-group', $ResourceGroup)))
            return @($items | ForEach-Object { [pscustomobject]@{ Name = [string]$_.name; Id = [string]$_.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/networkSecurityGroups'; Resource = $_ } })
        }
        'nsg-rule' {
            $rows = @()
            foreach ($nsg in @(Get-ClagnosComponentRowsForGroup -Type 'nsg' -ResourceGroup $ResourceGroup)) {
                $items = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('network', 'nsg', 'rule', 'list', '--resource-group', $ResourceGroup, '--nsg-name', [string]$nsg.Name)))
                foreach ($item in @($items)) {
                    $rows += [pscustomobject]@{ Name = [string]$item.name; Parent = [string]$nsg.Name; Id = [string]$item.id; ResourceGroup = $ResourceGroup; Type = 'Microsoft.Network/networkSecurityGroups/securityRules'; Resource = $item }
                }
            }
            return @($rows)
        }
        default { throw ("Unsupported component type '{0}'." -f [string]$Type) }
    }
}

function Get-ClagnosComponentRows {
    param([string]$Type, [string[]]$ResourceGroups)
    $rows = @()
    foreach ($group in @($ResourceGroups)) {
        $rows += @(Get-ClagnosComponentRowsForGroup -Type $Type -ResourceGroup ([string]$group))
    }
    return @($rows)
}

function Select-ClagnosComponentRow {
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

function Get-ClagnosComponentLocation {
    param([string]$ResourceGroup)
    $group = Get-ClagnosComponentAzureJson -Arguments @('group', 'show', '--name', $ResourceGroup)
    return [string]$group.location
}

function Get-ClagnosComponentGeneratedName {
    param([string]$ResourceGroup, [string]$ResourceType)
    $config = Read-DotEnvFile -Path (Join-Path (Get-ClagnosRepoRoot) 'clagnos.env')
    $vmName = [string](Get-ConfigValue -Config $config -Key 'SELECTED_VM_NAME' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($vmName)) { $vmName = Read-Host 'Virtual computer name seed' }
    $location = Get-ClagnosComponentLocation -ResourceGroup $ResourceGroup
    $regionCode = Get-ClagnosRegionCode -Location $location
    $allocator = New-ClagnosManagedResourceIndexAllocator
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
    return (Resolve-ClagnosNameFromTemplate -Template $template -ResourceType ([string]$templateContract.Type) -VmName $vmName -RegionCode $regionCode -ResourceGroup $ResourceGroup -UseNextIndex -IndexAllocator $allocator -LogicalName $ResourceType)
}

function Invoke-ClagnosComponentCreate {
    param([string]$Type, [string]$ResourceGroup, [hashtable]$Options)

    if ($Type -in @('group','vm')) {
        Write-Host 'Creating a VM creates its managed resource group and required network components as one virtual computer.' -ForegroundColor Cyan
        Invoke-ClagnosCreateCommand -Options @{} -AutoMode:$false -WindowsFlag:$false -LinuxFlag:$false
        return
    }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) { throw 'Choose a managed virtual computer before creating this component.' }
    Assert-ClagnosManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName ('create ' + $Type)
    $defaultType = switch ($Type) { 'disk' { 'disk' } 'vnet' { 'net' } 'subnet' { 'subnet' } 'nic' { 'nic' } 'ip' { 'ip' } 'nsg' { 'nsg' } 'nsg-rule' { 'nsgrule' } default { $Type } }
    $name = Get-ClagnosComponentGeneratedName -ResourceGroup $ResourceGroup -ResourceType $defaultType
    $namePrompt = Read-Host ("Name [{0}]" -f $name)
    if (-not [string]::IsNullOrWhiteSpace([string]$namePrompt)) {
        $name = [string]$namePrompt.Trim()
        $customAllocator = New-ClagnosManagedResourceIndexAllocator
        $customIndex = Register-ClagnosManagedResourceNameIndex -Allocator $customAllocator -Name $name -LogicalName $Type
        if ($customIndex -lt 1) {
            throw "Managed component names must use an unused global nX suffix, such as '$name-n$($customAllocator.NextIndex)'."
        }
    }
    $location = Get-ClagnosComponentLocation -ResourceGroup $ResourceGroup
    switch ($Type) {
        'disk' {
            $size = Read-Host 'Size in GB'
            $sku = Read-Host 'Storage tier (Standard_LRS, StandardSSD_LRS, Premium_LRS)'
            if ([string]::IsNullOrWhiteSpace($sku)) { $sku = 'StandardSSD_LRS' }
            Invoke-ClagnosComponentAzMutation -Arguments @('disk','create','--resource-group',$ResourceGroup,'--name',$name,'--location',$location,'--size-gb',$size,'--sku',$sku) -Label ("az disk create {0}" -f $name)
        }
        'vnet' {
            $prefix = Read-Host 'Address space (for example 10.20.0.0/16)'
            Invoke-ClagnosComponentAzMutation -Arguments @('network','vnet','create','--resource-group',$ResourceGroup,'--name',$name,'--address-prefixes',$prefix) -Label ("az network vnet create {0}" -f $name)
        }
        'subnet' {
            $vnets = @(Get-ClagnosComponentRowsForGroup -Type 'vnet' -ResourceGroup $ResourceGroup)
            $vnet = Select-ClagnosComponentRow -Rows $vnets -Name '' -Type 'virtual network'
            $prefix = Read-Host 'Subnet address prefix'
            Invoke-ClagnosComponentAzMutation -Arguments @('network','vnet','subnet','create','--resource-group',$ResourceGroup,'--vnet-name',[string]$vnet.Name,'--name',$name,'--address-prefixes',$prefix) -Label ("az network vnet subnet create {0}" -f $name)
        }
        'nic' {
            $subnets = @(Get-ClagnosComponentRowsForGroup -Type 'subnet' -ResourceGroup $ResourceGroup)
            $subnet = Select-ClagnosComponentRow -Rows $subnets -Name '' -Type 'subnet'
            $vnetName = [string]$subnet.Parent
            $publicIp = Read-Host 'Public IP name (leave blank for none)'
            $arguments = @('network','nic','create','--resource-group',$ResourceGroup,'--name',$name,'--vnet-name',$vnetName,'--subnet',[string]$subnet.Name)
            if (-not [string]::IsNullOrWhiteSpace($publicIp)) { $arguments += @('--public-ip-address',$publicIp) }
            Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network nic create {0}" -f $name)
        }
        'ip' {
            $arguments = @('network','public-ip','create','--resource-group',$ResourceGroup,'--name',$name,'--location',$location,'--sku','Standard','--allocation-method','Static')
            $dns = Read-Host 'Optional DNS label'
            if (-not [string]::IsNullOrWhiteSpace($dns)) { $arguments += @('--dns-name',$dns) }
            Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network public-ip create {0}" -f $name)
        }
        'nsg' { Invoke-ClagnosComponentAzMutation -Arguments @('network','nsg','create','--resource-group',$ResourceGroup,'--name',$name,'--location',$location) -Label ("az network nsg create {0}" -f $name) }
        'nsg-rule' {
            $nsgs = @(Get-ClagnosComponentRowsForGroup -Type 'nsg' -ResourceGroup $ResourceGroup)
            $nsg = Select-ClagnosComponentRow -Rows $nsgs -Name '' -Type 'network security group'
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
            Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network nsg rule create {0}" -f $name)
        }
    }
    Write-Host ("Created {0} '{1}'." -f $Type, $name) -ForegroundColor Green
}

function Invoke-ClagnosComponentUpdate {
    param([string]$Type, [object]$Row, [string]$ResourceGroup)

    if ($Type -ne 'group') {
        Write-Host 't: edit resource tags | p: edit component properties'
        $mode = (Read-Host 'Update mode').Trim().ToLowerInvariant()
        if ($mode -eq 't') {
            $key = Read-Host 'Tag name (managed-by is reserved)'
            if ([string]::Equals($key,'managed-by',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The managed-by tag is reserved for Clagnos ownership.' }
            $value = Read-Host 'Tag value'
            Invoke-ClagnosComponentAzMutation -Arguments @('tag','update','--resource-id',[string]$Row.Id,'--operation','Merge','--tags',('{0}={1}' -f $key,$value)) -Label ("az tag update {0}" -f [string]$Row.Name)
            Write-Host ("Updated tags for {0}." -f [string]$Row.Name) -ForegroundColor Green
            return
        }
        if ($mode -ne 'p') { throw 'Select tags or component properties.' }
    }

    switch ($Type) {
        'group' {
            $key = Read-Host 'Tag name'
            if ([string]::Equals($key,'managed-by',[System.StringComparison]::OrdinalIgnoreCase)) { throw 'The managed-by tag is reserved for Clagnos ownership.' }
            $value = Read-Host 'Tag value'
            $group = Get-ClagnosComponentAzureJson -Arguments @('group','show','--name',$ResourceGroup)
            $tags = @()
            if ($group.tags) {
                foreach ($property in @($group.tags.PSObject.Properties)) {
                    $tagValue = [string]$property.Value
                    if ([string]::Equals([string]$property.Name,$key,[System.StringComparison]::OrdinalIgnoreCase)) { $tagValue = $value }
                    $tags += ('{0}={1}' -f [string]$property.Name,$tagValue)
                }
            }
            if (@($tags | Where-Object { $_ -like ($key + '=*') }).Count -eq 0) { $tags += ('{0}={1}' -f $key,$value) }
            Invoke-ClagnosComponentAzMutation -Arguments (@('group','update','--name',$ResourceGroup,'--tags') + $tags) -Label ("az group update {0} tags" -f $ResourceGroup)
        }
        'vm' {
            Write-Host 's: change compute size | h: change hibernation | n: change nested virtualization'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            $options = @{ group = $ResourceGroup; 'vm-name' = [string]$Row.Name }
            if ($choice -eq 's') {
                $options['vm-size'] = Read-Host 'New VM size'
                Invoke-ClagnosResizeCommand -Options $options -WindowsFlag:$false -LinuxFlag:$false -AutoMode:$false
            }
            elseif ($choice -in @('h','n')) {
                $value = Read-Host 'Enable? (true or false)'
                if ($choice -eq 'h') { $options['hibernation'] = $value } else { $options['nested-virtualization'] = $value }
                Invoke-ClagnosSetCommand -Options $options -AutoMode:$false -WindowsFlag:$false -LinuxFlag:$false
            }
            else { throw 'Select a supported VM property.' }
        }
        'disk' {
            $size = Read-Host ("New size in GB (current {0})" -f [string]$Row.Resource.diskSizeGb)
            if ([string]::IsNullOrWhiteSpace($size)) { $size = [string]$Row.Resource.diskSizeGb }
            if ([int]$size -lt [int]$Row.Resource.diskSizeGb) {
                throw 'Azure disk shrink is not performed. Use the resize guidance flow to review safe alternatives.'
            }
            Invoke-ClagnosComponentAzMutation -Arguments @('disk','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--size-gb',$size) -Label ("az disk update {0}" -f [string]$Row.Name)
            $sku = Read-Host ("New storage tier (current {0}; blank keeps it)" -f [string]$Row.Resource.sku.name)
            if (-not [string]::IsNullOrWhiteSpace($sku)) { Invoke-ClagnosComponentAzMutation -Arguments @('disk','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--sku',$sku) -Label ("az disk update {0} SKU" -f [string]$Row.Name) }
        }
        'vnet' {
            $prefix = Read-Host 'New address prefixes (comma separated)'
            Invoke-ClagnosComponentAzMutation -Arguments @('network','vnet','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--address-prefixes',$prefix) -Label ("az network vnet update {0}" -f [string]$Row.Name)
        }
        'subnet' {
            $prefix = Read-Host 'New address prefix'
            $arguments = @('network','vnet','subnet','update','--resource-group',$ResourceGroup,'--vnet-name',[string]$Row.Parent,'--name',[string]$Row.Name,'--address-prefixes',$prefix)
            $nsg = Read-Host 'Network security group name (leave blank to keep current association)'
            if (-not [string]::IsNullOrWhiteSpace($nsg)) { $arguments += @('--network-security-group',$nsg) }
            Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network vnet subnet update {0}" -f [string]$Row.Name)
        }
        'nic' {
                Write-Host 'f: IP forwarding | i: private IP configuration | d: DNS servers | p: public IP association'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            if ($choice -eq 'f') {
                $value = (Read-Host 'Enable IP forwarding? (true or false)').Trim().ToLowerInvariant()
                if ($value -notin @('true','false')) { throw 'Enter true or false.' }
                Invoke-ClagnosComponentAzMutation -Arguments @('network','nic','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--ip-forwarding',$value) -Label ("az network nic update {0}" -f [string]$Row.Name)
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
                Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network nic ip-config update {0}" -f [string]$Row.Name)
            }
            elseif ($choice -eq 'd') {
                $dns = Read-Host 'DNS servers (comma separated; blank clears)'
                $arguments = @('network','nic','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name)
                if ([string]::IsNullOrWhiteSpace($dns)) { $arguments += @('--dns-servers','') } else { $arguments += @('--dns-servers') + @($dns -split ',' | ForEach-Object { $_.Trim() }) }
                Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network nic update {0}" -f [string]$Row.Name)
            }
            elseif ($choice -eq 'p') {
                $configs = @(ConvertTo-ObjectArrayCompat -InputObject $Row.Resource.ipConfigurations)
                if ($configs.Count -eq 0) { throw 'The network interface has no IP configuration to update.' }
                $configName = [string]$configs[0].name
                $publicIps = @(Get-ClagnosComponentRowsForGroup -Type 'ip' -ResourceGroup $ResourceGroup)
                Write-Host 'Enter a public IP name to associate it, or type none to detach it.'
                foreach ($publicIp in @($publicIps)) { Write-Host ('  {0}' -f [string]$publicIp.Name) }
                $publicIpName = (Read-Host 'Public IP name or none').Trim()
                $arguments = @('network','nic','ip-config','update','--resource-group',$ResourceGroup,'--nic-name',[string]$Row.Name,'--name',$configName)
                if ([string]::Equals($publicIpName,'none',[System.StringComparison]::OrdinalIgnoreCase)) { $arguments += @('--remove','publicIpAddress') }
                elseif (-not [string]::IsNullOrWhiteSpace($publicIpName)) { $arguments += @('--public-ip-address',$publicIpName) }
                else { throw 'Enter a public IP name or none.' }
                Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network nic ip-config update {0} public IP" -f [string]$Row.Name)
            }
            else { throw 'Select a supported network interface property.' }
        }
        'ip' {
            Write-Host 'd: DNS label | a: IP allocation | s: SKU'
            $choice = (Read-Host 'Property').Trim().ToLowerInvariant()
            $arguments = @('network','public-ip','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name)
            if ($choice -eq 'd') {
                $dns = Read-Host 'New DNS label'
                if ([string]::IsNullOrWhiteSpace($dns)) { $arguments += @('--remove','dnsSettings.domainNameLabel') } else { $arguments += @('--dns-name',$dns) }
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
            Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network public-ip update {0}" -f [string]$Row.Name)
        }
        'nsg' {
            $key = Read-Host 'Tag name'
            $value = Read-Host 'Tag value'
            Invoke-ClagnosComponentAzMutation -Arguments @('network','nsg','update','--resource-group',$ResourceGroup,'--name',[string]$Row.Name,'--add',('tags.{0}={1}' -f $key,$value)) -Label ("az network nsg update {0}" -f [string]$Row.Name)
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
            Invoke-ClagnosComponentAzMutation -Arguments $arguments -Label ("az network nsg rule update {0}" -f [string]$Row.Name)
        }
    }
    Write-Host ("Updated {0} '{1}'." -f $Type, [string]$Row.Name) -ForegroundColor Green
}

function Get-ClagnosComponentReferenceIds {
    param([object]$Value)
    $ids = New-Object 'System.Collections.Generic.List[string]'
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ($Value -match '^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/') { [void]$ids.Add($Value.TrimEnd('/')) }
        return @($ids.ToArray())
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) { foreach ($id in @(Get-ClagnosComponentReferenceIds -Value $item)) { [void]$ids.Add([string]$id) } }
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { foreach ($id in @(Get-ClagnosComponentReferenceIds -Value $item)) { [void]$ids.Add([string]$id) } }
    }
    elseif ($Value -is [psobject]) {
        foreach ($property in @($Value.PSObject.Properties)) { foreach ($id in @(Get-ClagnosComponentReferenceIds -Value $property.Value)) { [void]$ids.Add([string]$id) } }
    }
    return @($ids.ToArray() | Sort-Object -Unique)
}

function Get-ClagnosComponentDeletePlan {
    param([string]$Type, [object]$SelectedRow, [string]$ResourceGroup)

    $allResources = @(ConvertTo-ObjectArrayCompat -InputObject (Get-ClagnosComponentAzureJson -Arguments @('resource','list','--resource-group',$ResourceGroup)))
    foreach ($nestedType in @('subnet','nsg-rule')) {
        foreach ($nestedRow in @(Get-ClagnosComponentRowsForGroup -Type $nestedType -ResourceGroup $ResourceGroup)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$nestedRow.Id) -and @($allResources | Where-Object { [string]::Equals([string]$_.id,[string]$nestedRow.Id,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
                $allResources += [pscustomobject]@{ id = [string]$nestedRow.Id; name = [string]$nestedRow.Name; type = [string]$nestedRow.Type; properties = $nestedRow.Resource }
            }
        }
    }
    $selectedId = [string]$SelectedRow.Id
    if ([string]::IsNullOrWhiteSpace($selectedId)) { throw 'Azure did not return a resource id for the selected component.' }
    $resourceDetails = @()
    foreach ($resource in @($allResources)) {
        try { $resourceDetails += (Get-ClagnosComponentAzureJson -Arguments @('resource','show','--ids',[string]$resource.id)) }
        catch { $resourceDetails += $resource }
    }
    if ([string]::Equals($Type,'group',[System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($resource in @($resourceDetails)) {
            foreach ($referenceId in @(Get-ClagnosComponentReferenceIds -Value $resource)) {
                if ($referenceId -match '(?i)/resourceGroups/(?<group>[^/]+)/providers/' -and -not [string]::Equals([string]$Matches.group,$ResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) {
                    throw ("Resource '{0}' is linked to an Azure resource outside this managed group. Unlink it explicitly before deleting the group." -f [string]$resource.name)
                }
            }
        }
        return @($resourceDetails | Sort-Object { Get-ClagnosComponentDeletePriority -ResourceType ([string]$_.type) }, { [string]$_.name })
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
            $refs = @(Get-ClagnosComponentReferenceIds -Value $resource)
            if (@($refs | Where-Object { $included.ContainsKey(([string]$_).ToLowerInvariant()) }).Count -gt 0) {
                $included[$id.ToLowerInvariant()] = $true
                $changed = $true
            }
        }
        foreach ($resource in @($resourceDetails)) {
            $id = [string]$resource.id
            if ([string]::IsNullOrWhiteSpace($id) -or -not $included.ContainsKey($id.ToLowerInvariant())) { continue }
            foreach ($referenceId in @(Get-ClagnosComponentReferenceIds -Value $resource)) {
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
        foreach ($referenceId in @(Get-ClagnosComponentReferenceIds -Value $resource)) {
            if ($referenceId -match '(?i)/resourceGroups/(?<group>[^/]+)/providers/' -and -not [string]::Equals([string]$Matches.group,$ResourceGroup,[System.StringComparison]::OrdinalIgnoreCase)) {
                throw ("Component '{0}' references a resource outside its managed resource group. Unlink it explicitly before deleting this chain." -f [string]$resource.name)
            }
        }
    }
    return @($plan | Sort-Object { Get-ClagnosComponentDeletePriority -ResourceType ([string]$_.type) }, { [string]$_.name })
}

function Get-ClagnosComponentDeletePriority {
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

function Invoke-ClagnosComponentDelete {
    param([string]$Type, [object]$SelectedRow, [string]$ResourceGroup, [hashtable]$Options)
    $plan = @(Get-ClagnosComponentDeletePlan -Type $Type -SelectedRow $SelectedRow -ResourceGroup $ResourceGroup)
    if ($plan.Count -eq 0) { throw 'No Azure resources were found in the deletion plan.' }
    Write-Host 'These resources and linked dependencies will be deleted:' -ForegroundColor Yellow
    foreach ($resource in @($plan)) { Write-Host ('  - {0}: {1}' -f [string]$resource.type,[string]$resource.name) }
    $approved = Get-ClagnosCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
    if (-not $approved) {
        $required = if ($plan.Count -gt 1) { 'DELETE ALL' } else { [string]$SelectedRow.Name }
        $confirmation = Read-Host ("Type '{0}' to confirm" -f $required)
        $approved = [string]::Equals([string]$confirmation,[string]$required,[System.StringComparison]::Ordinal)
    }
    if (-not $approved) { Write-Host 'Deletion canceled; no resource was changed.' -ForegroundColor Yellow; return }

    if ([string]::Equals($Type,'group',[System.StringComparison]::OrdinalIgnoreCase)) {
        Invoke-ClagnosComponentAzMutation -Arguments @('group','delete','--name',$ResourceGroup,'--yes','--no-wait') -Label ("az group delete {0}" -f $ResourceGroup)
        $subscription = Get-ClagnosResolvedSubscriptionContext
        az group wait --name $ResourceGroup --deleted --subscription ([string]$subscription.SubscriptionId) --only-show-errors
        Assert-LastExitCode 'az group wait --deleted'
        Write-Host ("Resource group '{0}' and all listed resources were deleted." -f $ResourceGroup) -ForegroundColor Green
        return
    }

    foreach ($resource in @($plan)) {
        $resourceId = [string]$resource.id
        $subscription = Get-ClagnosResolvedSubscriptionContext
        az resource show --ids $resourceId --subscription ([string]$subscription.SubscriptionId) -o none --only-show-errors 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("Already absent: {0}" -f [string]$resource.name) -ForegroundColor DarkGray
            continue
        }
        try {
            Invoke-ClagnosComponentAzMutation -Arguments @('resource','delete','--ids',$resourceId) -Label ("az resource delete {0}" -f [string]$resource.name)
        }
        catch {
            az resource show --ids $resourceId --subscription ([string]$subscription.SubscriptionId) -o none --only-show-errors 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { throw }
        }
        $removed = $false
        for ($attempt = 0; $attempt -lt 12; $attempt++) {
            $subscription = Get-ClagnosResolvedSubscriptionContext
            $showArgs = @('resource','show','--ids',$resourceId,'--subscription',[string]$subscription.SubscriptionId,'-o','none','--only-show-errors')
            az @showArgs 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) { $removed = $true; break }
            Write-ClagnosActionProgress -Action ("wait 5s for Azure to confirm deletion of '{0}'" -f [string]$resource.name)
            Start-Sleep -Seconds 5
        }
        if (-not $removed) { throw ("Azure did not confirm deletion of '{0}' within the bounded wait." -f [string]$resource.name) }
        Write-Host ('Deleted: {0}' -f [string]$resource.name) -ForegroundColor Green
    }
}

function Invoke-ClagnosComponentAttachment {
    param([string]$Action, [string]$Type, [string]$ResourceGroup, [object]$Row, [hashtable]$Options)
    if ($Type -notin @('disk','nic')) { throw 'Only managed disks and network interfaces support attach/detach actions.' }
    $vms = @(Get-ClagnosComponentRowsForGroup -Type 'vm' -ResourceGroup $ResourceGroup)
    $requestedVm = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    $vm = Select-ClagnosComponentRow -Rows $vms -Name $requestedVm -Type 'virtual machine'
    if ($Type -eq 'disk') {
        if ($Action -eq 'attach') {
            $vmDetails = Get-ClagnosComponentAzureJson -Arguments @('vm','show','--resource-group',$ResourceGroup,'--name',[string]$vm.Name)
            $existing = @(ConvertTo-ObjectArrayCompat -InputObject $vmDetails.storageProfile.dataDisks)
            $luns = @($existing | ForEach-Object { [int]$_.lun })
            $lun = 0
            while ($luns -contains $lun) { $lun++ }
            Invoke-ClagnosComponentAzMutation -Arguments @('vm','disk','attach','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--name',[string]$Row.Name,'--lun',[string]$lun) -Label ("az vm disk attach {0}" -f [string]$Row.Name)
        }
        else {
            Invoke-ClagnosComponentAzMutation -Arguments @('vm','disk','detach','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--name',[string]$Row.Name) -Label ("az vm disk detach {0}" -f [string]$Row.Name)
        }
    }
    else {
        if ($Action -eq 'attach') {
            Invoke-ClagnosComponentAzMutation -Arguments @('vm','nic','add','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--nics',[string]$Row.Name) -Label ("az vm nic add {0}" -f [string]$Row.Name)
        }
        else {
            Invoke-ClagnosComponentAzMutation -Arguments @('vm','nic','remove','--resource-group',$ResourceGroup,'--vm-name',[string]$vm.Name,'--nics',[string]$Row.Name) -Label ("az vm nic remove {0}" -f [string]$Row.Name)
        }
    }
    Write-Host ("{0} {1} '{2}' {3} VM '{4}'." -f $Action,$Type,[string]$Row.Name,$Action,[string]$vm.Name) -ForegroundColor Green
}

function Invoke-ClagnosComponentOperation {
    param(
        [string]$Action,
        [string]$Type,
        [string]$Name,
        [string]$ResourceGroup,
        [hashtable]$Options,
        [switch]$AutoMode
    )

    if ((Get-ClagnosComponentTypeIds) -notcontains $Type) { throw ("Unsupported Clagnos component type '{0}'." -f $Type) }
    $groups = @(Get-ClagnosComponentScopedGroups -Options $Options)
    if ($Action -eq 'create' -and $Type -in @('group','vm')) {
        Invoke-ClagnosComponentCreate -Type $Type -ResourceGroup $ResourceGroup -Options $Options
        return
    }
    if ([string]::IsNullOrWhiteSpace($ResourceGroup)) {
        if ($groups.Count -eq 0) { throw 'No Clagnos-managed resource group is available.' }
        $selectedGroup = Select-ClagnosResourceGroupInteractive -DefaultResourceGroup '' -VmName ''
        $ResourceGroup = [string]$selectedGroup
    }
    Assert-ClagnosManagedResourceGroup -ResourceGroup $ResourceGroup -OperationName ('component ' + $Action)
    if ($Action -eq 'create') {
        Invoke-ClagnosComponentCreate -Type $Type -ResourceGroup $ResourceGroup -Options $Options
        return
    }
    $rows = @(Get-ClagnosComponentRowsForGroup -Type $Type -ResourceGroup $ResourceGroup)
    if ($Action -eq 'list') {
        if ($rows.Count -eq 0) { Write-Host 'No components of this type were found.' -ForegroundColor Yellow; return }
        foreach ($row in @($rows)) { Write-Host ('{0} | {1} | {2}' -f [string]$row.Name,[string]$row.Type,[string]$ResourceGroup) }
        return
    }
    $row = Select-ClagnosComponentRow -Rows $rows -Name $Name -Type $Type
    if ($Action -in @('attach','detach')) { Invoke-ClagnosComponentAttachment -Action $Action -Type $Type -ResourceGroup $ResourceGroup -Row $row -Options $Options; return }
    if ($Action -eq 'show') {
        Write-Host ('{0}: {1}' -f $Type,[string]$row.Name) -ForegroundColor Cyan
        Write-Host (ConvertTo-JsonCompat -InputObject $row.Resource -Depth 10)
        return
    }
    if ($Action -eq 'update') { Invoke-ClagnosComponentUpdate -Type $Type -Row $row -ResourceGroup $ResourceGroup; return }
    if ($Action -eq 'delete') { Invoke-ClagnosComponentDelete -Type $Type -SelectedRow $row -ResourceGroup $ResourceGroup -Options $Options; return }
    throw ("Unsupported component action '{0}'." -f $Action)
}
