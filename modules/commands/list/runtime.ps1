# List command runtime helpers.

function Get-ClagnosListSupportedTypes {
    return @('group', 'vm', 'disk', 'vnet', 'subnet', 'nic', 'ip', 'nsg', 'nsg-rule')
}

function Resolve-ClagnosListRequestedTypes {
    param(
        [hashtable]$Options
    )

    $supportedTypes = @(Get-ClagnosListSupportedTypes)
    $rawText = [string](Get-ClagnosCliOptionText -Options $Options -Name 'type')
    if ([string]::IsNullOrWhiteSpace([string]$rawText)) {
        return @($supportedTypes)
    }

    $values = @(
        [string]$rawText -split ',' |
            ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
    if (@($values).Count -eq 0) {
        Throw-FriendlyError `
            -Detail "Option '--type' was provided without any value." `
            -Code 2 `
            -Summary "List type filter is empty." `
            -Hint ("Use --type={0}" -f (@($supportedTypes) -join ','))
    }

    $unknownValues = @(
        @($values) | Where-Object { $supportedTypes -notcontains [string]$_ }
    )
    if (@($unknownValues).Count -gt 0) {
        Throw-FriendlyError `
            -Detail ("Option '--type' contains unsupported value(s): {0}." -f (@($unknownValues) -join ', ')) `
            -Code 2 `
            -Summary "List type filter is invalid." `
            -Hint ("Valid values: {0}" -f (@($supportedTypes) -join ', '))
    }

    return @($supportedTypes | Where-Object { $values -contains [string]$_ })
}

function Get-ClagnosListTargetResourceGroups {
    param(
        [hashtable]$Options,
        [hashtable]$ConfigMap
    )

    $requestedGroup = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    if (-not [string]::IsNullOrWhiteSpace([string]$requestedGroup)) {
        $resourceGroup = $requestedGroup.Trim()
        Assert-ClagnosManagedResourceGroup -ResourceGroup $resourceGroup -OperationName 'list'
        return @([string]$resourceGroup)
    }

    $rows = @(Get-ClagnosManagedResourceGroupRows)
    return @(
        ConvertTo-ObjectArrayCompat -InputObject $rows |
            ForEach-Object { [string]$_.name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )
}

function Invoke-ClagnosListAzJson {
    param(
        [string[]]$AzArgs,
        [string]$OperationLabel
    )

    $json = az @AzArgs 2>$null
    Assert-LastExitCode ([string]$OperationLabel)
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        return @()
    }

    return (ConvertFrom-JsonCompat -InputObject $json)
}

function Get-ClagnosListSectionRows {
    param(
        [string]$TypeName,
        [string[]]$ResourceGroups,
        [hashtable]$ConfigMap
    )

    $activeGroup = [string](Get-ConfigValue -Config $ConfigMap -Key 'SELECTED_RESOURCE_GROUP' -DefaultValue '')
    $rows = New-Object 'System.Collections.Generic.List[string]'

    switch ([string]$TypeName) {
        'group' {
            foreach ($resourceGroup in @($ResourceGroups | Sort-Object -Unique)) {
                if ([string]::Equals([string]$resourceGroup, [string]$activeGroup, [System.StringComparison]::OrdinalIgnoreCase)) {
                    [void]$rows.Add(("{0} [active]" -f [string]$resourceGroup))
                }
                else {
                    [void]$rows.Add([string]$resourceGroup)
                }
            }
            break
        }
        'vm' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $vmRows = @(Invoke-ClagnosListAzJson -AzArgs @('vm', 'list', '-g', [string]$resourceGroup, '-o', 'json', '--only-show-errors') -OperationLabel ("az vm list ({0})" -f [string]$resourceGroup))
                foreach ($vm in @(ConvertTo-ObjectArrayCompat -InputObject $vmRows)) {
                    $name = [string]$vm.name
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        [void]$rows.Add(("{0} | {1}" -f [string]$resourceGroup, $name))
                    }
                }
            }
            break
        }
        'disk' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $resourceRows = @(Invoke-ClagnosListAzJson -AzArgs @('resource', 'list', '-g', [string]$resourceGroup, '--resource-type', 'Microsoft.Compute/disks', '-o', 'json', '--only-show-errors') -OperationLabel ("az resource list disks ({0})" -f [string]$resourceGroup))
                foreach ($resource in @(ConvertTo-ObjectArrayCompat -InputObject $resourceRows)) {
                    $name = [string]$resource.name
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        [void]$rows.Add(("{0} | {1}" -f [string]$resourceGroup, $name))
                    }
                }
            }
            break
        }
        'vnet' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $resourceRows = @(Invoke-ClagnosListAzJson -AzArgs @('resource', 'list', '-g', [string]$resourceGroup, '--resource-type', 'Microsoft.Network/virtualNetworks', '-o', 'json', '--only-show-errors') -OperationLabel ("az resource list vnet ({0})" -f [string]$resourceGroup))
                foreach ($resource in @(ConvertTo-ObjectArrayCompat -InputObject $resourceRows)) {
                    $name = [string]$resource.name
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        [void]$rows.Add(("{0} | {1}" -f [string]$resourceGroup, $name))
                    }
                }
            }
            break
        }
        'subnet' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $vnetRows = @(Invoke-ClagnosListAzJson -AzArgs @('network', 'vnet', 'list', '-g', [string]$resourceGroup, '-o', 'json', '--only-show-errors') -OperationLabel ("az network vnet list ({0})" -f [string]$resourceGroup))
                foreach ($vnet in @(ConvertTo-ObjectArrayCompat -InputObject $vnetRows)) {
                    $vnetName = [string]$vnet.name
                    foreach ($subnet in @(ConvertTo-ObjectArrayCompat -InputObject $vnet.subnets)) {
                        $subnetName = [string]$subnet.name
                        if (-not [string]::IsNullOrWhiteSpace([string]$vnetName) -and -not [string]::IsNullOrWhiteSpace([string]$subnetName)) {
                            [void]$rows.Add(("{0} | {1} | {2}" -f [string]$resourceGroup, $vnetName, $subnetName))
                        }
                    }
                }
            }
            break
        }
        'nic' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $resourceRows = @(Invoke-ClagnosListAzJson -AzArgs @('resource', 'list', '-g', [string]$resourceGroup, '--resource-type', 'Microsoft.Network/networkInterfaces', '-o', 'json', '--only-show-errors') -OperationLabel ("az resource list nic ({0})" -f [string]$resourceGroup))
                foreach ($resource in @(ConvertTo-ObjectArrayCompat -InputObject $resourceRows)) {
                    $name = [string]$resource.name
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        [void]$rows.Add(("{0} | {1}" -f [string]$resourceGroup, $name))
                    }
                }
            }
            break
        }
        'ip' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $resourceRows = @(Invoke-ClagnosListAzJson -AzArgs @('resource', 'list', '-g', [string]$resourceGroup, '--resource-type', 'Microsoft.Network/publicIPAddresses', '-o', 'json', '--only-show-errors') -OperationLabel ("az resource list public ip ({0})" -f [string]$resourceGroup))
                foreach ($resource in @(ConvertTo-ObjectArrayCompat -InputObject $resourceRows)) {
                    $name = [string]$resource.name
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        [void]$rows.Add(("{0} | {1}" -f [string]$resourceGroup, $name))
                    }
                }
            }
            break
        }
        'nsg' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $resourceRows = @(Invoke-ClagnosListAzJson -AzArgs @('resource', 'list', '-g', [string]$resourceGroup, '--resource-type', 'Microsoft.Network/networkSecurityGroups', '-o', 'json', '--only-show-errors') -OperationLabel ("az resource list nsg ({0})" -f [string]$resourceGroup))
                foreach ($resource in @(ConvertTo-ObjectArrayCompat -InputObject $resourceRows)) {
                    $name = [string]$resource.name
                    if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
                        [void]$rows.Add(("{0} | {1}" -f [string]$resourceGroup, $name))
                    }
                }
            }
            break
        }
        'nsg-rule' {
            foreach ($resourceGroup in @($ResourceGroups)) {
                $nsgRows = @(Invoke-ClagnosListAzJson -AzArgs @('resource', 'list', '-g', [string]$resourceGroup, '--resource-type', 'Microsoft.Network/networkSecurityGroups', '-o', 'json', '--only-show-errors') -OperationLabel ("az resource list nsg for rules ({0})" -f [string]$resourceGroup))
                foreach ($nsg in @(ConvertTo-ObjectArrayCompat -InputObject $nsgRows)) {
                    $nsgName = [string]$nsg.name
                    if ([string]::IsNullOrWhiteSpace([string]$nsgName)) {
                        continue
                    }

                    $ruleRows = @(Invoke-ClagnosListAzJson -AzArgs @('network', 'nsg', 'rule', 'list', '-g', [string]$resourceGroup, '--nsg-name', [string]$nsgName, '-o', 'json', '--only-show-errors') -OperationLabel ("az network nsg rule list ({0}/{1})" -f [string]$resourceGroup, $nsgName))
                    foreach ($rule in @(ConvertTo-ObjectArrayCompat -InputObject $ruleRows)) {
                        $ruleName = [string]$rule.name
                        if (-not [string]::IsNullOrWhiteSpace([string]$ruleName)) {
                            [void]$rows.Add(("{0} | {1} | {2}" -f [string]$resourceGroup, $nsgName, $ruleName))
                        }
                    }
                }
            }
            break
        }
        default {
            throw ("Unsupported list type '{0}'." -f [string]$TypeName)
        }
    }

    return @($rows.ToArray() | Sort-Object -Unique)
}
