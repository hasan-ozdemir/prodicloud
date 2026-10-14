# VM detail lookup helpers.

function Get-ClagnosVmPublicDnsSettings {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$PreferredPublicIpName = ''
    )

    function ConvertTo-ClagnosVmPublicDnsSettings {
        param([AllowNull()]$PublicIpObject)

        if ($null -eq $PublicIpObject) {
            return $null
        }

        $domainNameLabel = ''
        $fqdn = ''
        $ipAddress = ''
        $publicIpName = ''

        if ($PublicIpObject.PSObject.Properties.Match('name').Count -gt 0) {
            $publicIpName = [string]$PublicIpObject.name
        }
        if ($PublicIpObject.PSObject.Properties.Match('ipAddress').Count -gt 0) {
            $ipAddress = [string]$PublicIpObject.ipAddress
        }
        if ($PublicIpObject.PSObject.Properties.Match('dnsSettings').Count -gt 0 -and $null -ne $PublicIpObject.dnsSettings) {
            if ($PublicIpObject.dnsSettings.PSObject.Properties.Match('domainNameLabel').Count -gt 0) {
                $domainNameLabel = [string]$PublicIpObject.dnsSettings.domainNameLabel
            }
            if ($PublicIpObject.dnsSettings.PSObject.Properties.Match('fqdn').Count -gt 0) {
                $fqdn = [string]$PublicIpObject.dnsSettings.fqdn
            }
        }

        return [pscustomobject]@{
            PublicIpName = [string]$publicIpName
            IpAddress = [string]$ipAddress
            DomainNameLabel = [string]$domainNameLabel
            Fqdn = [string]$fqdn
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$PreferredPublicIpName)) {
        $preferredPublicIpJson = az network public-ip show -g $ResourceGroup -n $PreferredPublicIpName -o json --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$preferredPublicIpJson)) {
            $preferredPublicIp = ConvertFrom-JsonCompat -InputObject $preferredPublicIpJson
            $preferredSettings = ConvertTo-ClagnosVmPublicDnsSettings -PublicIpObject $preferredPublicIp
            if ($null -ne $preferredSettings) {
                return $preferredSettings
            }
        }
    }

    $vmJson = az vm show -g $ResourceGroup -n $VmName -o json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$vmJson)) {
        return $null
    }

    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    if ($null -eq $vmObject) {
        return $null
    }

    $nicIds = @(
        ConvertTo-ObjectArrayCompat -InputObject $vmObject.networkProfile.networkInterfaces |
            ForEach-Object { [string]$_.id } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Select-Object -Unique
    )

    foreach ($nicId in @($nicIds)) {
        $nicJson = az network nic show --ids $nicId -o json --only-show-errors 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$nicJson)) {
            continue
        }

        $nicObject = ConvertFrom-JsonCompat -InputObject $nicJson
        foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nicObject.ipConfigurations)) {
            $publicIpId = [string]$ipConfig.publicIpAddress.id
            if ([string]::IsNullOrWhiteSpace([string]$publicIpId)) {
                continue
            }

            $publicIpJson = az network public-ip show --ids $publicIpId -o json --only-show-errors 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$publicIpJson)) {
                continue
            }

            $publicIpObject = ConvertFrom-JsonCompat -InputObject $publicIpJson
            $publicDnsSettings = ConvertTo-ClagnosVmPublicDnsSettings -PublicIpObject $publicIpObject
            if ($null -ne $publicDnsSettings) {
                return $publicDnsSettings
            }
        }
    }

    return $null
}

# Handles Get-ClagnosVmDetails.
function Get-ClagnosVmDetails {
    param(
        [hashtable]$Context,
        [switch]$AllowCachedInventory
    )

    if ($AllowCachedInventory -and $null -ne (Get-Command Get-ClagnosUiInventorySnapshotForSharedRuntime -ErrorAction SilentlyContinue)) {
        $inventorySnapshot = Get-ClagnosUiInventorySnapshotForSharedRuntime -MaximumAgeSeconds 60 -SubscriptionId ([string]$Context.AzureSubscriptionId)
        if ($null -ne $inventorySnapshot) {
            $cachedVm = @($inventorySnapshot.VirtualMachines | Where-Object {
                [string]::Equals([string]$_.ClagnosResourceGroup,[string]$Context.ResourceGroup,[System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals([string]$_.name,[string]$Context.VmName,[System.StringComparison]::OrdinalIgnoreCase)
            } | Select-Object -First 1)
            if (@($cachedVm).Count -gt 0) {
                $publicIp = [string]$cachedVm[0].publicIps
                $vmFqdn = [string]$cachedVm[0].fqdns
                if (-not [string]::IsNullOrWhiteSpace($publicIp) -or -not [string]::IsNullOrWhiteSpace($vmFqdn)) {
                    return [ordered]@{ VmDetails = $cachedVm[0]; PublicIP = $publicIp; VmFqdn = $vmFqdn }
                }
            }
        }
    }

    Show-ClagnosStepFirstUseValues `
        -StepLabel "VM details lookup" `
        -Context $Context `
        -Keys @("SELECTED_RESOURCE_GROUP", "SELECTED_VM_NAME", "SELECTED_AZURE_REGION", "VM_SSH_PORT")

    $vmDetailsJson = Invoke-TrackedAction -Label "az vm show -g $($Context.ResourceGroup) -n $($Context.VmName) -d" -Action {
        $result = az vm show -g $Context.ResourceGroup -n $Context.VmName -d -o json --only-show-errors 2>$null
        Assert-LastExitCode "az vm show -d"
        $result
    }

    $vmDetails = ConvertFrom-JsonCompat -InputObject $vmDetailsJson
    if (-not $vmDetails) {
        throw "VM detail output could not be parsed."
    }

    $publicIP = $vmDetails.publicIps
    $vmFqdn = $vmDetails.fqdns
    $effectiveLocation = [string]$Context.AzLocation
    if ([string]::IsNullOrWhiteSpace([string]$effectiveLocation)) {
        $effectiveLocation = [string]$vmDetails.location
    }
    $publicDnsSettings = $null
    if ([string]::IsNullOrWhiteSpace($vmFqdn) -or [string]::IsNullOrWhiteSpace([string]$publicIP)) {
        $publicDnsSettings = Get-ClagnosVmPublicDnsSettings -ResourceGroup ([string]$Context.ResourceGroup) -VmName ([string]$Context.VmName) -PreferredPublicIpName ([string]$Context.IP)
    }

    if ([string]::IsNullOrWhiteSpace([string]$publicIP) -and $null -ne $publicDnsSettings -and -not [string]::IsNullOrWhiteSpace([string]$publicDnsSettings.IpAddress)) {
        $publicIP = [string]$publicDnsSettings.IpAddress
    }

    if ([string]::IsNullOrWhiteSpace($vmFqdn) -and $null -ne $publicDnsSettings) {
        if (-not [string]::IsNullOrWhiteSpace([string]$publicDnsSettings.Fqdn)) {
            $vmFqdn = [string]$publicDnsSettings.Fqdn
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$publicDnsSettings.DomainNameLabel) -and -not [string]::IsNullOrWhiteSpace([string]$effectiveLocation)) {
            $vmFqdn = ("{0}.{1}.cloudapp.azure.com" -f [string]$publicDnsSettings.DomainNameLabel, [string]$effectiveLocation)
        }
    }

    return [ordered]@{
        VmDetails = $vmDetails
        PublicIP = $publicIP
        VmFqdn = $vmFqdn
    }
}
