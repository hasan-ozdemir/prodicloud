# Network step orchestration.

# Handles Invoke-ProdicloudNetworkStep.
function Invoke-ProdicloudNetworkStep {
    param(
        [hashtable]$Context,
        [ValidateSet("default","update")]
        [string]$ExecutionMode = "default"
    )

    $effectiveMode = if ([string]::IsNullOrWhiteSpace([string]$ExecutionMode)) { "default" } else { [string]$ExecutionMode.Trim().ToLowerInvariant() }
    $alwaysCreate = ($effectiveMode -eq "update")
    Show-ProdicloudStepFirstUseValues `
        -StepLabel "Step 3/7 - network provisioning" `
        -Context $Context `
        -Keys @("ResourceGroup", "VNET", "SUBNET", "NSG", "NsgRule", "IP", "PublicDnsLabel", "NIC", "TcpPorts") `
        -ExtraValues @{
            NetworkExecutionMode = $effectiveMode
        }

    $resourceGroupName = [string]$Context.ResourceGroup
    $groupExistsBeforeNetwork = Test-ProdicloudResourceGroupExists -ResourceGroup $resourceGroupName
    if (-not $groupExistsBeforeNetwork) {
        Write-Host ("Resource group '{0}' was not found before network step; it will be created now." -f $resourceGroupName) -ForegroundColor Yellow
        Ensure-ProdicloudResourceGroupReady -Context $Context
    }

    $createVnet = $alwaysCreate
    if (-not $alwaysCreate) {
        $createVnet = -not (Test-ProdicloudAzResourceExistsByType -ResourceGroup ([string]$Context.ResourceGroup) -ResourceType "Microsoft.Network/virtualNetworks" -ResourceName ([string]$Context.VNET))
        if (-not $createVnet) {
            Write-Host ("Default mode: VNet '{0}' exists; create command is skipped." -f [string]$Context.VNET) -ForegroundColor Yellow
        }
    }
    if ($createVnet) {
        Invoke-TrackedAction -Label "az network vnet create -g $($Context.ResourceGroup) -n $($Context.VNET)" -Action {
            az network vnet create -g $Context.ResourceGroup -n $Context.VNET --address-prefix 10.20.0.0/16 `
                --subnet-name $Context.SUBNET --subnet-prefix 10.20.0.0/24 -o table
            Assert-LastExitCode "az network vnet create"
        } | Out-Null
    }

    $createNsg = $alwaysCreate
    if (-not $alwaysCreate) {
        $createNsg = -not (Test-ProdicloudAzResourceExistsByType -ResourceGroup ([string]$Context.ResourceGroup) -ResourceType "Microsoft.Network/networkSecurityGroups" -ResourceName ([string]$Context.NSG))
        if (-not $createNsg) {
            Write-Host ("Default mode: NSG '{0}' exists; create command is skipped." -f [string]$Context.NSG) -ForegroundColor Yellow
        }
    }
    if ($createNsg) {
        Invoke-TrackedAction -Label "az network nsg create -g $($Context.ResourceGroup) -n $($Context.NSG)" -Action {
            az network nsg create -g $Context.ResourceGroup -n $Context.NSG -o table
            Assert-LastExitCode "az network nsg create"
        } | Out-Null
    }

    $priority = 101
    $ports = @($Context.TcpPorts)
    if ($Context.ContainsKey('TcpPortRanges') -and @($Context.TcpPortRanges).Count -gt 0) {
        $ports = @($Context.TcpPortRanges)
    }
    $createNsgRule = $alwaysCreate
    if (-not $alwaysCreate) {
        $createNsgRule = -not (Test-ProdicloudNsgRuleExists -ResourceGroup ([string]$Context.ResourceGroup) -NsgName ([string]$Context.NSG) -RuleName ([string]$Context.NsgRule))
        if (-not $createNsgRule) {
            Write-Host ("Default mode: NSG rule '{0}' exists; create command is skipped." -f [string]$Context.NsgRule) -ForegroundColor Yellow
        }
    }
    if ($createNsgRule) {
        Invoke-TrackedAction -Label "az network nsg rule create -g $($Context.ResourceGroup) --nsg-name $($Context.NSG) --name $($Context.NsgRule)" -Action {
            $ruleArgs = @(
                "network", "nsg", "rule", "create",
                "-g", [string]$Context.ResourceGroup,
                "--nsg-name", [string]$Context.NSG,
                "--name", [string]$Context.NsgRule,
                "--priority", [string]$priority,
                "--direction", "Inbound",
                "--protocol", "Tcp",
                "--access", "Allow",
                "--destination-port-ranges"
            )
            $ruleArgs += @($ports | ForEach-Object { [string]$_ })
            $ruleArgs += @(
                "--source-address-prefixes", "*",
                "--source-port-ranges", "*",
                "-o", "table"
            )
            az @ruleArgs
            Assert-LastExitCode "az network nsg rule create"
        } | Out-Null
    }

    $createPublicIp = $alwaysCreate
    if (-not $alwaysCreate) {
        $createPublicIp = -not (Test-ProdicloudAzResourceExistsByType -ResourceGroup ([string]$Context.ResourceGroup) -ResourceType "Microsoft.Network/publicIPAddresses" -ResourceName ([string]$Context.IP))
        if (-not $createPublicIp) {
            Write-Host ("Default mode: public IP '{0}' exists; create command is skipped." -f [string]$Context.IP) -ForegroundColor Yellow
        }
    }
    if ($createPublicIp) {
        Write-Host "Creating public IP '$($Context.IP)'..."
        Invoke-TrackedAction -Label "az network public-ip create -g $($Context.ResourceGroup) -n $($Context.IP)" -Action {
            $publicIpCreateArgs = @(
                "network", "public-ip", "create",
                "-g", [string]$Context.ResourceGroup,
                "-n", [string]$Context.IP,
                "--allocation-method", "Static",
                "--sku", "Standard",
                "--dns-name", [string]$Context.PublicDnsLabel
            )
            $publicIpCreateArgs += @(Get-ProdicloudPublicIpZoneArgs -Location ([string]$Context.AzLocation))
            $publicIpCreateArgs += @("-o", "table")
            az @publicIpCreateArgs
            Assert-LastExitCode "az network public-ip create"
        } | Out-Null
    }

    $createNic = $alwaysCreate
    if (-not $alwaysCreate) {
        $createNic = -not (Test-ProdicloudAzResourceExistsByType -ResourceGroup ([string]$Context.ResourceGroup) -ResourceType "Microsoft.Network/networkInterfaces" -ResourceName ([string]$Context.NIC))
        if (-not $createNic) {
            Write-Host ("Default mode: NIC '{0}' exists; create command is skipped." -f [string]$Context.NIC) -ForegroundColor Yellow
        }
    }
    if ($createNic) {
        Write-Host "Creating network NIC '$($Context.NIC)'..."
        Invoke-TrackedAction -Label "az network nic create -g $($Context.ResourceGroup) -n $($Context.NIC)" -Action {
            az network nic create -g $Context.ResourceGroup -n $Context.NIC --vnet-name $Context.VNET --subnet $Context.SUBNET `
                --network-security-group $Context.NSG `
                --public-ip-address $Context.IP `
                -o table
            Assert-LastExitCode "az network nic create"
        } | Out-Null
    }
}
