$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$AzArguments = @()
$argumentMatches = [regex]::Matches([string]$env:CLAGNOS_TUI_AZ_ARGUMENT_LINE, '"([^"]*)"|''([^'']*)''|(\S+)')
foreach ($argumentMatch in @($argumentMatches)) {
    if ($argumentMatch.Groups[1].Success) { $AzArguments += [string]$argumentMatch.Groups[1].Value }
    elseif ($argumentMatch.Groups[2].Success) { $AzArguments += [string]$argumentMatch.Groups[2].Value }
    elseif ($argumentMatch.Groups[3].Success) { $AzArguments += [string]$argumentMatch.Groups[3].Value }
}
$subscriptionId = '00000000-0000-4000-8000-000000000000'
$resourceGroup = 'rg-tui-fixture-eastus-g1'
$vmName = 'tui-fixture-vc'
$argumentsText = @($AzArguments) -join ' '
$logPath = [string]$env:CLAGNOS_TUI_AZ_LOG
if (-not [string]::IsNullOrWhiteSpace($logPath)) {
    Add-Content -LiteralPath $logPath -Value $argumentsText -Encoding UTF8
}

if (@($AzArguments).Count -lt 2) {
    Write-Error 'The TUI Azure fixture received an incomplete command.'
    exit 90
}

$commandGroup = [string]$AzArguments[0]
$commandVerb = [string]$AzArguments[1]
$commandText = if ($commandGroup -eq 'network' -and $AzArguments.Count -gt 2) { (@($AzArguments | Select-Object -First 3) -join ' ') } else { '{0} {1}' -f $commandGroup,$commandVerb }
$mutationVerb = if ($commandGroup -eq 'network' -and $AzArguments.Count -gt 2) { [string]$AzArguments[2] } else { $commandVerb }
$outputFormat = ''
$queryText = ''
for ($index = 0; $index -lt ($AzArguments.Count - 1); $index++) {
    if ([string]$AzArguments[$index] -eq '-o' -or [string]$AzArguments[$index] -eq '--output') { $outputFormat = [string]$AzArguments[$index + 1] }
    if ([string]$AzArguments[$index] -eq '--query') { $queryText = [string]$AzArguments[$index + 1] }
}

$blockedVerbs = @('create','update','delete','set','start','stop','restart','deallocate','resize','reapply','redeploy','attach','detach','power-off','run-command','move')
if ($blockedVerbs -contains $mutationVerb.ToLowerInvariant()) {
    Write-Error ('Blocked Azure mutation attempted in TUI process test: {0}' -f $commandText)
    exit 97
}

$managedGroup = [pscustomobject]@{
    id = ("/subscriptions/{0}/resourceGroups/{1}" -f $subscriptionId,$resourceGroup)
    name = $resourceGroup
    location = 'eastus'
    provisioningState = 'Succeeded'
    tags = [pscustomobject]@{ 'managed-by' = 'clagnos' }
}
$vm = [pscustomobject]@{
    id = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/virtualMachines/{2}" -f $subscriptionId,$resourceGroup,$vmName)
    vmId = 'tui-fixture-vm-id'
    name = $vmName
    resourceGroup = $resourceGroup
    location = 'eastus'
    provisioningState = 'Succeeded'
    hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2as_v5' }
    storageProfile = [pscustomobject]@{
        osDisk = [pscustomobject]@{
            name = 'disk-tui-fixture-os'
            osType = 'Windows'
            diskSizeGB = 128
            caching = 'ReadWrite'
            createOption = 'FromImage'
            deleteOption = 'Detach'
            managedDisk = [pscustomobject]@{ id = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Compute/disks/disk-tui-fixture-os" -f $subscriptionId,$resourceGroup); resourceGroup = $resourceGroup; storageAccountType = 'StandardSSD_LRS' }
        }
        dataDisks = @()
        imageReference = [pscustomobject]@{ publisher = 'MicrosoftWindowsServer'; offer = 'WindowsServer'; sku = '2022-datacenter-azure-edition'; version = 'latest'; exactVersion = '20348.1'; id = '' }
    }
    osProfile = [pscustomobject]@{ computerName = 'TUI-FIXTURE-VC' }
    additionalCapabilities = [pscustomobject]@{ hibernationEnabled = $true }
    securityProfile = [pscustomobject]@{ securityType = 'TrustedLaunch'; uefiSettings = [pscustomobject]@{ secureBootEnabled = $true; vTpmEnabled = $true } }
    diagnosticsProfile = [pscustomobject]@{ bootDiagnostics = [pscustomobject]@{ enabled = $true } }
    identity = [pscustomobject]@{ type = 'SystemAssigned' }
    zones = @('1')
    tags = [pscustomobject]@{ 'managed-by' = 'clagnos'; 'test-surface' = 'tui-fixture' }
    networkProfile = [pscustomobject]@{ networkInterfaces = @([pscustomobject]@{ id = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/networkInterfaces/nic-tui-fixture" -f $subscriptionId,$resourceGroup); resourceGroup = $resourceGroup; primary = $true }) }
}

$result = $null
switch -Regex ($commandText) {
    '^account list$' {
        $result = @([pscustomobject]@{ id = $subscriptionId; name = 'TUI Fixture Subscription'; tenantId = '00000000-0000-4000-8000-000000000001'; state = 'Enabled'; isDefault = $true })
        break
    }
    '^account show$' {
        if ($queryText -eq 'id' -or $outputFormat -eq 'tsv' -and $queryText -eq 'id') { $result = $subscriptionId }
        else { $result = [pscustomobject]@{ id = $subscriptionId; name = 'TUI Fixture Subscription'; tenantId = '00000000-0000-4000-8000-000000000001'; state = 'Enabled'; user = [pscustomobject]@{ name = 'fixture-user' } } }
        break
    }
    '^group list$' {
        $tagIndex = [array]::IndexOf($AzArguments,'--tag')
        if ($tagIndex -ge 0 -and [string]$AzArguments[$tagIndex + 1] -eq 'managed-by=az-vm') { $result = @() }
        else { $result = @($managedGroup) }
        break
    }
    '^vm list$' { $result = @($vm); break }
    '^vm get-instance-view$' {
        $result = [pscustomobject]@{ statuses = @(
            [pscustomobject]@{ code = 'ProvisioningState/succeeded'; displayStatus = 'Provisioning succeeded' },
            [pscustomobject]@{ code = 'PowerState/running'; displayStatus = 'VM running' }
        ) }
        break
    }
    '^vm show$' { $result = $vm; break }
    '^vm list-sizes$' { $result = @([pscustomobject]@{ name = 'Standard_D2as_v5'; numberOfCores = 2; memoryInMb = 8192 }); break }
    '^vm list-ip-addresses$' {
        $result = @([pscustomobject]@{ virtualMachine = [pscustomobject]@{ name = $vmName; network = [pscustomobject]@{
            privateIpAddresses = @('10.20.0.4')
            publicIpAddresses = @([pscustomobject]@{ name = 'pip-tui-fixture'; resourceGroup = $resourceGroup; ipAddress = '203.0.113.8'; ipAllocationMethod = 'Static' })
        } } })
        break
    }
    '^network public-ip show$' { $result = [pscustomobject]@{ name = 'pip-tui-fixture'; ipAddress = '203.0.113.8'; publicIPAllocationMethod = 'Static'; dnsSettings = [pscustomobject]@{ fqdn = 'tui-fixture.eastus.cloudapp.azure.com'; domainNameLabel = 'tui-fixture' }; sku = [pscustomobject]@{ name = 'Standard' }; zones = @('1') }; break }
    '^network nic show$' {
        $result = [pscustomobject]@{
            name = 'nic-tui-fixture'; primary = $true; enableAcceleratedNetworking = $true; enableIPForwarding = $false
            networkSecurityGroup = [pscustomobject]@{ id = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/networkSecurityGroups/nsg-tui-fixture" -f $subscriptionId,$resourceGroup) }
            ipConfigurations = @([pscustomobject]@{
                name = 'ipconfig-primary'; primary = $true; privateIPAddress = '10.20.0.4'; privateIPAllocationMethod = 'Dynamic'
                subnet = [pscustomobject]@{ id = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/virtualNetworks/vnet-tui-fixture/subnets/subnet-tui-fixture" -f $subscriptionId,$resourceGroup) }
                publicIPAddress = [pscustomobject]@{ id = ("/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Network/publicIPAddresses/pip-tui-fixture" -f $subscriptionId,$resourceGroup) }
            })
        }
        break
    }
    '^disk show$' { $result = [pscustomobject]@{ name = 'disk-tui-fixture-os'; diskSizeGb = 128; sku = [pscustomobject]@{ name = 'StandardSSD_LRS' }; encryption = [pscustomobject]@{ type = 'EncryptionAtRestWithPlatformKey' } }; break }
    '^resource list$' { $result = @([pscustomobject]@{ type = 'Microsoft.Compute/virtualMachines'; name = $vmName; location = 'eastus' }, [pscustomobject]@{ type = 'Microsoft.Compute/disks'; name = 'disk-tui-fixture-os'; location = 'eastus' }); break }
    default {
        Write-Error ('Unsupported fake Azure read command: {0}' -f $commandText)
        exit 96
    }
}

if ($outputFormat -eq 'tsv') {
    if ($queryText -eq 'id') { Write-Output ([string]$result); exit 0 }
    if ($result -is [string]) { Write-Output $result; exit 0 }
}
if ($outputFormat -eq 'none') { exit 0 }
if ($null -eq $result) { Write-Output 'null'; exit 0 }
Write-Output (ConvertTo-Json -InputObject $result -Depth 20 -Compress)
exit 0
