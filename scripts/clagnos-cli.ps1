[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliTokens
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:PYTHONDONTWRITEBYTECODE = '1'

$script:ClagnosUiRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:ClagnosUiBackendPath = Join-Path $script:ClagnosUiRepoRoot 'clagnos.ps1'
$script:ClagnosUiSubscription = $null
$script:ClagnosUiSubscriptionError = ''

if (-not (Test-Path -LiteralPath $script:ClagnosUiBackendPath)) {
    throw "Clagnos runtime was not found: $script:ClagnosUiBackendPath"
}

. $script:ClagnosUiBackendPath

if ($null -ne $CliTokens -and @($CliTokens).Count -gt 0) {
    if (@($CliTokens).Count -eq 1 -and [string]$CliTokens[0] -match '^(?i)--version(?:=(?:1|true|yes|on)?)?$') {
        Write-Host ("clagnos version {0}" -f (Get-ClagnosCliVersionInfo))
        return
    }
    try {
        $commandName = [string]$CliTokens[0]
        $rawArguments = if (@($CliTokens).Count -gt 1) { @($CliTokens[1..(@($CliTokens).Count - 1)]) } else { @() }
        $parsedCli = Parse-ClagnosCliArguments -CommandToken $commandName -RawArgs $rawArguments
        Invoke-ClagnosCommandDispatcher -CommandName ([string]$parsedCli.Command) -Options $parsedCli.Options -HelpTopic ([string]$parsedCli.HelpTopic)
        return
    }
    catch {
        Write-ClagnosUiError -ErrorRecord $_
        exit 2
    }
}

function Update-ClagnosUiSubscription {
    try {
        $script:ClagnosUiSubscription = Initialize-ClagnosCommandSubscriptionState -CommandName 'list' -Options @{}
        $script:ClagnosUiSubscriptionError = ''
    }
    catch {
        $script:ClagnosUiSubscription = $null
        $script:ClagnosUiSubscriptionError = [string]$_.Exception.Message
    }

    if ($null -eq $script:ClagnosUiSubscription) {
        $envPath = Join-Path $script:ClagnosUiRepoRoot '.env'
        $config = Read-DotEnvFile -Path $envPath
        $configuredId = [string](Get-ConfigValue -Config $config -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -DefaultValue '')
        if (-not [string]::IsNullOrWhiteSpace($configuredId)) {
            $script:ClagnosUiSubscription = [pscustomobject]@{
                SubscriptionId = $configuredId
                SubscriptionName = 'Sign-in required to resolve subscription name'
                ResolutionSource = 'env'
            }
        }
    }
}

function Get-ClagnosUiAzureCliActiveSubscriptionId {
    $activeId = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account show --query id -o tsv --only-show-errors 2>$null
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$activeId)) {
        throw "Azure CLI could not resolve its active subscription. Run 'az login' and retry."
    }
    return ([string]$activeId).Trim()
}

function Get-ClagnosUiCloudSubscriptionRows {
    $raw = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account list --all --refresh -o json --only-show-errors 2>$null
    }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$raw)) {
        throw "Azure CLI could not refresh the subscription list. Run 'az login' and retry."
    }
    $rows = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $raw) | Where-Object {
        $_ -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$_.id)
    })
    return @($rows | Sort-Object @{ Expression = { if ([bool]$_.isDefault) { 0 } else { 1 } } }, @{ Expression = { [string]$_.name } }, @{ Expression = { [string]$_.id } })
}

function Set-ClagnosUiActiveSubscription {
    param([psobject]$Subscription)

    if ($null -eq $Subscription -or [string]::IsNullOrWhiteSpace([string]$Subscription.id)) {
        throw 'Select an accessible Azure subscription first.'
    }
    if (-not [string]::Equals([string]$Subscription.state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'A disabled Azure subscription cannot be activated.'
    }

    $previousCliId = Get-ClagnosUiAzureCliActiveSubscriptionId
    $previousContext = Get-ClagnosResolvedSubscriptionContext
    $subscriptionId = [string]$Subscription.id
    try {
        az account set --subscription $subscriptionId --only-show-errors
        Assert-LastExitCode 'az account set'
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        throw
    }

    $verifiedId = Get-ClagnosUiAzureCliActiveSubscriptionId
    if (-not [string]::Equals($verifiedId, $subscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        throw 'Azure CLI did not confirm the selected active subscription; the previous CLI subscription was restored.'
    }

    try {
        Save-ClagnosSubscriptionIdToDotEnv `
            -EnvFilePath (Join-Path $script:ClagnosUiRepoRoot '.env') `
            -SubscriptionId $subscriptionId
    }
    catch {
        if (-not [string]::IsNullOrWhiteSpace($previousCliId)) {
            az account set --subscription $previousCliId --only-show-errors
            $null = $LASTEXITCODE
        }
        if ($null -ne $previousContext) {
            Set-ClagnosResolvedSubscriptionContext `
                -SubscriptionId ([string]$previousContext.SubscriptionId) `
                -SubscriptionName ([string]$previousContext.SubscriptionName) `
                -TenantId ([string]$previousContext.TenantId) `
                -ResolutionSource ([string]$previousContext.ResolutionSource)
        }
        throw
    }

    Set-ClagnosResolvedSubscriptionContext `
        -SubscriptionId $subscriptionId `
        -SubscriptionName ([string]$Subscription.name) `
        -TenantId ([string]$Subscription.tenantId) `
        -ResolutionSource 'interactive'
    $script:ClagnosUiSubscription = [pscustomobject]@{
        SubscriptionId = $subscriptionId
        SubscriptionName = [string]$Subscription.name
        TenantId = [string]$Subscription.tenantId
        ResolutionSource = 'interactive'
    }
    Write-Host ('Active Azure subscription: {0} ({1})' -f [string]$Subscription.name, $subscriptionId) -ForegroundColor Green
}

function Show-ClagnosUiCloudSubscriptions {
    while ($true) {
        Update-ClagnosUiSubscription
        Write-ClagnosUiHeader -Title 'Cloud subscriptions'
        try {
            $rows = @(Get-ClagnosUiCloudSubscriptionRows)
            $selectedContext = Get-ClagnosResolvedSubscriptionContext
            $activeId = Get-ClagnosUiAzureCliActiveSubscriptionId
            $selectedName = if ($null -ne $selectedContext) { [string]$selectedContext.SubscriptionName } else { '(none)' }
            $activeRow = @($rows | Where-Object { [string]::Equals([string]$_.id, $activeId, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
            $activeName = if (@($activeRow).Count -gt 0) { [string]$activeRow[0].name } else { $activeId }
            Write-Host ('Clagnos selected: {0}' -f $selectedName)
            Write-Host ('Azure CLI active: {0}' -f $activeName)
            Write-Host ''
            for ($index = 0; $index -lt $rows.Count; $index++) {
                $markers = @()
                if ($null -ne $selectedContext -and [string]::Equals([string]$rows[$index].id, [string]$selectedContext.SubscriptionId, [System.StringComparison]::OrdinalIgnoreCase)) { $markers += 'Clagnos selected' }
                if ([string]::Equals([string]$rows[$index].id, $activeId, [System.StringComparison]::OrdinalIgnoreCase)) { $markers += 'Azure CLI active' }
                $markerText = if ($markers.Count -gt 0) { ' [' + ($markers -join '; ') + ']' } else { '' }
                $stateText = if ([string]::Equals([string]$rows[$index].state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)) { '' } else { ' [not enabled]' }
                Write-Host ('{0}. {1} ({2}){3}{4}' -f ($index + 1), [string]$rows[$index].name, [string]$rows[$index].id, $markerText, $stateText)
            }
            Write-Host 'b: back'
            Write-Host 'q: exit'
            $choice = (Read-ClagnosUiChoice 'Select active cloud subscription').ToLowerInvariant()
            if ($choice -eq 'b') { return }
            if ($choice -eq 'q') { exit }
            $number = 0
            if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $rows.Count) { continue }
            if (-not [string]::Equals([string]$rows[$number - 1].state, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Host 'This subscription is not enabled and cannot become the active Azure subscription.' -ForegroundColor Yellow
                Wait-ClagnosUiContinue
                continue
            }
            Set-ClagnosUiActiveSubscription -Subscription $rows[$number - 1]
            Wait-ClagnosUiContinue
        }
        catch {
            Write-ClagnosUiError -ErrorRecord $_
            Wait-ClagnosUiContinue
            return
        }
    }
}

function Write-ClagnosUiHeader {
    param([string]$Title = 'Clagnos')

    Clear-Host
    Write-Host 'CLAGNOS' -ForegroundColor Cyan
    Write-Host 'one tool for all common cloud operations' -ForegroundColor DarkCyan
    if ($null -ne $script:ClagnosUiSubscription) {
        Write-Host ('Azure subscription: {0} ({1})' -f [string]$script:ClagnosUiSubscription.SubscriptionName, [string]$script:ClagnosUiSubscription.SubscriptionId) -ForegroundColor Gray
    }
    else {
        Write-Host 'Azure subscription: not signed in' -ForegroundColor Yellow
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Title)) {
        Write-Host ''
        Write-Host $Title -ForegroundColor White
    }
    Write-Host ''
}

function Read-ClagnosUiChoice {
    param([string]$Prompt = 'Select an option')
    return ([string](Read-Host $Prompt)).Trim()
}

function Wait-ClagnosUiContinue {
    [void](Read-Host 'Press Enter to return')
}

function Write-ClagnosUiError {
    param([object]$ErrorRecord)

    $friendly = Resolve-ClagnosFriendlyError -ErrorRecord $ErrorRecord -DefaultErrorSummary 'The operation did not complete.' -DefaultErrorHint "Review the reason and retry. Azure operations require 'az login'."
    Write-Host ''
    Write-Host ([string]$friendly.Summary) -ForegroundColor Red
    if (-not [string]::IsNullOrWhiteSpace([string]$friendly.ErrorMessage)) {
        Write-Host ([string]$friendly.ErrorMessage) -ForegroundColor Gray
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$friendly.Hint)) {
        Write-Host ('Next: {0}' -f [string]$friendly.Hint) -ForegroundColor Cyan
    }
}

function Invoke-ClagnosUiCommand {
    param(
        [Parameter(Mandatory = $true)][string]$CommandName,
        [hashtable]$Options = @{}
    )

    try {
        Invoke-ClagnosCommandDispatcher -CommandName $CommandName -Options $Options | Out-Null
    }
    catch {
        Write-ClagnosUiError -ErrorRecord $_
    }
    Wait-ClagnosUiContinue
    Update-ClagnosUiSubscription
}

function Invoke-ClagnosUiAzJson {
    param([string[]]$Arguments)

    $subscriptionId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        throw "Azure CLI sign-in is required. Run 'az login' and retry."
    }
    $azArguments = @($Arguments) + @('--subscription', $subscriptionId, '-o', 'json', '--only-show-errors')
    $json = & az @azArguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI could not complete the read request. Run 'az login' and verify the selected subscription."
    }
    if ([string]::IsNullOrWhiteSpace([string]$json)) {
        return @()
    }
    return (ConvertFrom-JsonCompat -InputObject ([string]$json))
}

function Get-ClagnosUiManagedGroups {
    param([switch]$IncludeLegacy)

    $rows = @()
    $current = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('group', 'list', '--tag', 'managed-by=clagnos')))
    $rows += @($current)
    if ($IncludeLegacy) {
        $legacy = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('group', 'list', '--tag', 'managed-by=az-vm')))
        $rows += @($legacy)
    }
    $unique = @{}
    foreach ($row in @($rows)) {
        $name = [string]$row.name
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $unique[$name.ToLowerInvariant()] = $row
        }
    }
    return @($unique.Values | Sort-Object { [string]$_.name })
}

function Invoke-ClagnosUiLegacyTagMigration {
    param([object[]]$LegacyGroups)

    if (@($LegacyGroups).Count -eq 0) {
        return
    }
    Write-Host 'Legacy managed resource groups were found:' -ForegroundColor Yellow
    foreach ($group in @($LegacyGroups | Sort-Object { [string]$_.name })) {
        Write-Host ('  - {0}' -f [string]$group.name)
    }
    $answer = (Read-ClagnosUiChoice 'Move these groups to the Clagnos management tag now? Type yes or no').ToLowerInvariant()
    if ($answer -notin @('yes', 'y')) {
        Write-Host 'Legacy groups remain visible and were not changed.' -ForegroundColor Yellow
        return
    }

    foreach ($group in @($LegacyGroups)) {
        $groupName = [string]$group.name
        try {
            $tags = @()
            if ($null -ne $group.tags) {
                foreach ($property in @($group.tags.PSObject.Properties)) {
                    $key = [string]$property.Name
                    $value = [string]$property.Value
                    if ([string]::Equals($key, 'managed-by', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $value = 'clagnos'
                    }
                    $tags += ('{0}={1}' -f $key, $value)
                }
            }
            if (-not (@($tags | Where-Object { $_ -like 'managed-by=*' }).Count -gt 0)) {
                $tags += 'managed-by=clagnos'
            }
            $subscriptionId = [string]$script:ClagnosUiSubscription.SubscriptionId
            & az group update --name $groupName --subscription $subscriptionId --tags @tags -o none --only-show-errors 2>$null
            if ($LASTEXITCODE -ne 0) {
                throw 'Azure rejected the resource group tag update.'
            }
            Write-Host ('Migrated management tag: {0}' -f $groupName) -ForegroundColor Green
        }
        catch {
            Write-Host ('Tag migration failed for {0}: {1}' -f $groupName, $_.Exception.Message) -ForegroundColor Red
        }
    }
}

function Get-ClagnosUiVirtualComputers {
    $groups = @(Get-ClagnosUiManagedGroups -IncludeLegacy)
    $legacyGroups = @($groups | Where-Object {
        $value = ''
        if ($_.tags -and $_.tags.PSObject.Properties.Match('managed-by').Count -gt 0) { $value = [string]$_.tags.'managed-by' }
        [string]::Equals($value, 'az-vm', [System.StringComparison]::OrdinalIgnoreCase)
    })
    if (@($legacyGroups).Count -gt 0) {
        Invoke-ClagnosUiLegacyTagMigration -LegacyGroups $legacyGroups
        $groups = @(Get-ClagnosUiManagedGroups -IncludeLegacy)
    }

    $vms = @()
    foreach ($group in @($groups)) {
        $groupName = [string]$group.name
        $vmRows = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('vm', 'list', '--resource-group', $groupName)))
        foreach ($vm in @($vmRows)) {
            $vm | Add-Member -NotePropertyName 'ClagnosResourceGroup' -NotePropertyValue $groupName -Force
            $vm | Add-Member -NotePropertyName 'ClagnosSubscriptionId' -NotePropertyValue ([string]$script:ClagnosUiSubscription.SubscriptionId) -Force
            $vms += $vm
        }
    }
    return @($vms | Sort-Object { [string]$_.name }, { [string]$_.ClagnosResourceGroup })
}

function Get-ClagnosUiPowerState {
    param([string]$ResourceGroup, [string]$VmName)

    try {
        $instance = Invoke-ClagnosUiAzJson -Arguments @('vm', 'get-instance-view', '--resource-group', $ResourceGroup, '--name', $VmName)
        foreach ($status in @(ConvertTo-ObjectArrayCompat -InputObject $instance.statuses)) {
            if ([string]$status.code -like 'PowerState/*') { return [string]$status.displayStatus }
        }
    }
    catch { return 'Unknown' }
    return 'Unknown'
}

function Get-ClagnosUiVmSizeFacts {
    param([string]$Location, [string]$Size)

    try {
        $sizes = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('vm', 'list-sizes', '--location', $Location)))
        $match = @($sizes | Where-Object { [string]::Equals([string]$_.name, $Size, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if (@($match).Count -gt 0) {
            return [pscustomobject]@{ Cores = [string]$match[0].numberOfCores; MemoryMb = [string]$match[0].memoryInMb }
        }
    }
    catch { }
    return [pscustomobject]@{ Cores = 'Unknown'; MemoryMb = 'Unknown' }
}

function Format-ClagnosUiDetailValue {
    param(
        [AllowNull()][object]$Value,
        [string]$EmptyText = '(not available)'
    )

    if ($null -eq $Value) { return $EmptyText }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $EmptyText }
    return $text
}

function Get-ClagnosUiAzureResourceIdSegment {
    param(
        [string]$ResourceId,
        [string]$SegmentName
    )

    $parts = @(([string]$ResourceId).Trim('/') -split '/')
    for ($index = 0; $index -lt ($parts.Count - 1); $index++) {
        if ([string]::Equals([string]$parts[$index], [string]$SegmentName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$parts[$index + 1]
        }
    }
    return ''
}

function Show-ClagnosUiVmDetails {
    param([psobject]$Vm)

    $group = [string]$Vm.ClagnosResourceGroup
    $name = [string]$Vm.name
    $full = Invoke-ClagnosUiAzJson -Arguments @('vm', 'show', '--resource-group', $group, '--name', $name)
    $sizeName = [string]$full.hardwareProfile.vmSize
    $facts = Get-ClagnosUiVmSizeFacts -Location ([string]$full.location) -Size $sizeName
    $memoryGb = if ($facts.MemoryMb -match '^\d+$') { ('{0:N1} GB' -f ([double]$facts.MemoryMb / 1024)) } else { 'Unknown' }
    $power = Get-ClagnosUiPowerState -ResourceGroup $group -VmName $name
    $envPath = Join-Path $script:ClagnosUiRepoRoot '.env'
    $config = Read-DotEnvFile -Path $envPath

    $privateAddresses = @()
    $publicAddresses = @()
    try {
        $ipRows = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('vm', 'list-ip-addresses', '--resource-group', $group, '--name', $name)))
        $ipVm = @($ipRows | Where-Object { [string]::Equals([string]$_.virtualMachine.name, $name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($ipVm.Count -gt 0) {
            $privateAddresses = @($ipVm[0].virtualMachine.network.privateIpAddresses | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            foreach ($publicAddress in @($ipVm[0].virtualMachine.network.publicIpAddresses)) {
                $publicDetail = $null
                $publicName = [string]$publicAddress.name
                $publicGroup = [string]$publicAddress.resourceGroup
                if ([string]::IsNullOrWhiteSpace($publicGroup)) { $publicGroup = $group }
                if (-not [string]::IsNullOrWhiteSpace($publicName)) {
                    try {
                        $publicDetail = Invoke-ClagnosUiAzJson -Arguments @('network', 'public-ip', 'show', '--resource-group', $publicGroup, '--name', $publicName)
                    }
                    catch { }
                }
                $publicAddresses += [pscustomobject]@{
                    Name = $publicName
                    IpAddress = [string]$publicAddress.ipAddress
                    Fqdn = if ($null -ne $publicDetail) { [string]$publicDetail.dnsSettings.fqdn } else { '' }
                    DnsLabel = if ($null -ne $publicDetail) { [string]$publicDetail.dnsSettings.domainNameLabel } else { '' }
                    Allocation = if ($null -ne $publicDetail) { [string]$publicDetail.publicIPAllocationMethod } else { [string]$publicAddress.ipAllocationMethod }
                    Sku = if ($null -ne $publicDetail) { [string]$publicDetail.sku.name } else { '' }
                    Zone = if ($null -ne $publicDetail) { (@($publicDetail.zones) -join ', ') } else { '' }
                }
            }
        }
    }
    catch { }

    if ($privateAddresses.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$Vm.privateIps)) {
        $privateAddresses = @(([string]$Vm.privateIps -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ($publicAddresses.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$Vm.publicIps)) {
        $fallbackPublicIps = @(([string]$Vm.publicIps -split ',') | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach ($fallbackPublicIp in @($fallbackPublicIps)) {
            $publicAddresses += [pscustomobject]@{ Name = ''; IpAddress = [string]$fallbackPublicIp; Fqdn = [string]$Vm.fqdns; DnsLabel = ''; Allocation = ''; Sku = ''; Zone = '' }
        }
    }

    Write-ClagnosUiHeader -Title ('Virtual computer: {0}' -f $name)
    Write-Host 'Virtual computer:' -ForegroundColor Cyan
    Write-Host ('  Name: {0}' -f $name)
    Write-Host ('Resource group: {0}' -f $group)
    Write-Host ('Subscription: {0} ({1})' -f (Format-ClagnosUiDetailValue -Value $script:ClagnosUiSubscription.SubscriptionName), (Format-ClagnosUiDetailValue -Value $Vm.ClagnosSubscriptionId))
    Write-Host ('Resource ID: {0}' -f (Format-ClagnosUiDetailValue -Value $full.id))
    Write-Host ('VM ID: {0}' -f (Format-ClagnosUiDetailValue -Value $full.vmId))
    Write-Host ('Operating system: {0}' -f [string]$full.storageProfile.osDisk.osType)
    Write-Host ('State: {0} | Provisioning: {1}' -f $power, [string]$full.provisioningState)
    Write-Host ('Region: {0} | Size: {1}' -f [string]$full.location, $sizeName)
    Write-Host ('CPU: {0} vCPU | RAM: {1}' -f [string]$facts.Cores, $memoryGb)
    $image = $full.storageProfile.imageReference
    if ($null -ne $image) {
        $imageText = '{0}:{1}:{2}:{3}' -f [string]$image.publisher, [string]$image.offer, [string]$image.sku, [string]$image.version
        if (-not [string]::IsNullOrWhiteSpace([string]$image.id)) { $imageText = [string]$image.id }
        if (-not [string]::IsNullOrWhiteSpace([string]$image.exactVersion)) { $imageText += (' (exact version {0})' -f [string]$image.exactVersion) }
        Write-Host ('Image: {0}' -f $imageText)
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$full.storageProfile.osDisk.image)) {
        Write-Host ('Image: {0}' -f [string]$full.storageProfile.osDisk.image)
    }
    Write-Host ('Computer name: {0}' -f (Format-ClagnosUiDetailValue -Value $full.osProfile.computerName))
    Write-Host ('Availability zone: {0}' -f (Format-ClagnosUiDetailValue -Value (@($full.zones) -join ', ')))
    Write-Host ''

    Write-Host 'Storage and disks:' -ForegroundColor Cyan
    $diskReferences = @()
    if ($null -ne $full.storageProfile.osDisk) {
        $diskReferences += [pscustomobject]@{
            Kind = 'OS disk'
            Name = [string]$full.storageProfile.osDisk.name
            ResourceGroup = [string]$full.storageProfile.osDisk.managedDisk.resourceGroup
            SizeGb = [string]$full.storageProfile.osDisk.diskSizeGb
            Caching = [string]$full.storageProfile.osDisk.caching
            Lun = ''
            CreateOption = [string]$full.storageProfile.osDisk.createOption
            DeleteOption = [string]$full.storageProfile.osDisk.deleteOption
            StorageType = [string]$full.storageProfile.osDisk.managedDisk.storageAccountType
        }
    }
    foreach ($dataDisk in @($full.storageProfile.dataDisks)) {
        $diskReferences += [pscustomobject]@{
            Kind = 'Data disk'
            Name = [string]$dataDisk.name
            ResourceGroup = [string]$dataDisk.managedDisk.resourceGroup
            SizeGb = [string]$dataDisk.diskSizeGb
            Caching = [string]$dataDisk.caching
            Lun = [string]$dataDisk.lun
            CreateOption = [string]$dataDisk.createOption
            DeleteOption = [string]$dataDisk.deleteOption
            StorageType = [string]$dataDisk.managedDisk.storageAccountType
        }
    }
    foreach ($diskReference in @($diskReferences)) {
        $diskName = [string]$diskReference.Name
        if ([string]::IsNullOrWhiteSpace($diskName)) { continue }
        $diskGroup = [string]$diskReference.ResourceGroup
        if ([string]::IsNullOrWhiteSpace($diskGroup)) { $diskGroup = $group }
        try {
            $disk = Invoke-ClagnosUiAzJson -Arguments @('disk', 'show', '--resource-group', $diskGroup, '--name', $diskName)
            $sizeGb = if ([string]::IsNullOrWhiteSpace([string]$diskReference.SizeGb)) { [string]$disk.diskSizeGb } else { [string]$diskReference.SizeGb }
            $detail = ('  {0}: {1} | {2} GB | {3} | caching {4} | create {5}' -f [string]$diskReference.Kind, [string]$disk.name, $sizeGb, [string]$disk.sku.name, (Format-ClagnosUiDetailValue -Value $diskReference.Caching), (Format-ClagnosUiDetailValue -Value $diskReference.CreateOption))
            if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.Lun)) { $detail += (' | LUN {0}' -f [string]$diskReference.Lun) }
            if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.DeleteOption)) { $detail += (' | delete {0}' -f [string]$diskReference.DeleteOption) }
            if (-not [string]::IsNullOrWhiteSpace([string]$diskReference.StorageType)) { $detail += (' | storage {0}' -f [string]$diskReference.StorageType) }
            if (-not [string]::IsNullOrWhiteSpace([string]$disk.encryption.type)) { $detail += (' | encryption {0}' -f [string]$disk.encryption.type) }
            Write-Host $detail
        }
        catch { Write-Host ('  {0}: {1} | details unavailable' -f [string]$diskReference.Kind, $diskName) -ForegroundColor Yellow }
    }
    if ($diskReferences.Count -eq 0) { Write-Host '  (no managed disks reported)' -ForegroundColor Gray }
    Write-Host ''

    Write-Host 'Networking:' -ForegroundColor Cyan
    $nicReferences = @(ConvertTo-ObjectArrayCompat -InputObject $full.networkProfile.networkInterfaces)
    foreach ($nicReference in @($nicReferences)) {
        $nicName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$nicReference.id) -SegmentName 'networkInterfaces'
        if ([string]::IsNullOrWhiteSpace($nicName)) { continue }
        $nicGroup = [string]$nicReference.resourceGroup
        if ([string]::IsNullOrWhiteSpace($nicGroup)) { $nicGroup = $group }
        try {
            $nic = Invoke-ClagnosUiAzJson -Arguments @('network', 'nic', 'show', '--resource-group', $nicGroup, '--name', $nicName)
            Write-Host ('  NIC: {0} | primary {1} | accelerated networking {2} | IP forwarding {3}' -f [string]$nic.name, [bool]$nic.primary, [bool]$nic.enableAcceleratedNetworking, [bool]$nic.enableIPForwarding)
            $nsgName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$nic.networkSecurityGroup.id) -SegmentName 'networkSecurityGroups'
            if (-not [string]::IsNullOrWhiteSpace($nsgName)) { Write-Host ('    Network security group: {0}' -f $nsgName) }
            foreach ($ipConfig in @(ConvertTo-ObjectArrayCompat -InputObject $nic.ipConfigurations)) {
                $vnetName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.subnet.id) -SegmentName 'virtualNetworks'
                $subnetName = Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.subnet.id) -SegmentName 'subnets'
                Write-Host ('    IP config {0}: private {1} ({2}) | primary {3} | VNet {4} | subnet {5}' -f [string]$ipConfig.name, (Format-ClagnosUiDetailValue -Value $ipConfig.privateIPAddress), (Format-ClagnosUiDetailValue -Value $ipConfig.privateIPAllocationMethod), [bool]$ipConfig.primary, (Format-ClagnosUiDetailValue -Value $vnetName), (Format-ClagnosUiDetailValue -Value $subnetName))
                if ($null -ne $ipConfig.publicIPAddress -and -not [string]::IsNullOrWhiteSpace([string]$ipConfig.publicIPAddress.id)) {
                    Write-Host ('      Public IP resource: {0}' -f (Get-ClagnosUiAzureResourceIdSegment -ResourceId ([string]$ipConfig.publicIPAddress.id) -SegmentName 'publicIPAddresses'))
                }
            }
        }
        catch { Write-Host ('  NIC: {0} | details unavailable' -f $nicName) -ForegroundColor Yellow }
    }
    if ($privateAddresses.Count -gt 0) { Write-Host ('  Private IP address(es): {0}' -f ($privateAddresses -join ', ')) }
    else { Write-Host '  Private IP address(es): (none reported)' -ForegroundColor Gray }
    if ($publicAddresses.Count -gt 0) {
        foreach ($publicAddress in @($publicAddresses)) {
            Write-Host ('  Public IP: {0} | resource {1}' -f (Format-ClagnosUiDetailValue -Value $publicAddress.IpAddress), (Format-ClagnosUiDetailValue -Value $publicAddress.Name))
            Write-Host ('    Public DNS: {0} | DNS label: {1}' -f (Format-ClagnosUiDetailValue -Value $publicAddress.Fqdn -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $publicAddress.DnsLabel -EmptyText '(not configured)'))
            Write-Host ('    Allocation: {0} | SKU: {1} | zone: {2}' -f (Format-ClagnosUiDetailValue -Value $publicAddress.Allocation), (Format-ClagnosUiDetailValue -Value $publicAddress.Sku), (Format-ClagnosUiDetailValue -Value $publicAddress.Zone))
        }
    }
    else { Write-Host '  Public IP/DNS: (no public endpoint reported)' -ForegroundColor Gray }
    Write-Host ''

    $hibernationEnabled = if ($null -ne $full.additionalCapabilities) { [string]$full.additionalCapabilities.hibernationEnabled } else { 'false' }
    $securityType = [string]$full.securityProfile.securityType
    $secureBoot = if ($null -ne $full.securityProfile.uefiSettings) { [string]$full.securityProfile.uefiSettings.secureBootEnabled } else { '(not reported)' }
    $vTpm = if ($null -ne $full.securityProfile.uefiSettings) { [string]$full.securityProfile.uefiSettings.vTpmEnabled } else { '(not reported)' }
    $nestedVirtualization = [string](Get-ConfigValue -Config $config -Key 'VM_ENABLE_NESTED_VIRTUALIZATION' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($nestedVirtualization)) { $nestedVirtualization = '(not configured)' }
    Write-Host 'Security and VM features:' -ForegroundColor Cyan
    Write-Host ('  Hibernation enabled: {0}' -f (Format-ClagnosUiDetailValue -Value $hibernationEnabled -EmptyText 'false'))
    Write-Host ('  Nested virtualization setting (.env): {0}' -f $nestedVirtualization)
    Write-Host ('  Security type: {0}' -f (Format-ClagnosUiDetailValue -Value $securityType))
    Write-Host ('  Secure Boot: {0} | vTPM: {1}' -f $secureBoot, $vTpm)
    Write-Host ('  Boot diagnostics: {0}' -f (Format-ClagnosUiDetailValue -Value $full.diagnosticsProfile.bootDiagnostics.enabled))
    Write-Host ('  Managed identity: {0}' -f (Format-ClagnosUiDetailValue -Value $full.identity.type '(none)'))
    if ($null -ne $full.tags) {
        foreach ($tag in @($full.tags.PSObject.Properties | Sort-Object Name)) {
            Write-Host ('  Tag {0}: {1}' -f [string]$tag.Name, [string]$tag.Value)
        }
    }
    Write-Host ''

    $adminUser = [string](Get-ConfigValue -Config $config -Key 'VM_ADMIN_USER' -DefaultValue '')
    $adminPass = [string](Get-ConfigValue -Config $config -Key 'VM_ADMIN_PASS' -DefaultValue '')
    $assistantUser = [string](Get-ConfigValue -Config $config -Key 'VM_ASSISTANT_USER' -DefaultValue '')
    $assistantPass = [string](Get-ConfigValue -Config $config -Key 'VM_ASSISTANT_PASS' -DefaultValue '')
    $sshPort = [string](Get-ConfigValue -Config $config -Key 'VM_SSH_PORT' -DefaultValue (Get-ClagnosDefaultSshPortText))
    $rdpPort = [string](Get-ConfigValue -Config $config -Key 'VM_RDP_PORT' -DefaultValue (Get-ClagnosDefaultRdpPortText))
    $powerShellPort = Get-ClagnosDefaultPowerShellPortText
    $connectionHost = if ($publicAddresses.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$publicAddresses[0].Fqdn)) { [string]$publicAddresses[0].Fqdn }
    elseif ($publicAddresses.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$publicAddresses[0].IpAddress)) { [string]$publicAddresses[0].IpAddress }
    elseif ($privateAddresses.Count -gt 0) { [string]$privateAddresses[0] }
    else { '(no reachable address reported)' }
    Write-Host 'Connection and login credentials (.env):' -ForegroundColor Cyan
    Write-Host ('  SSH endpoint: {0}:{1} | default role: manager' -f $connectionHost, $sshPort)
    Write-Host ('    manager username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $adminUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $adminPass -EmptyText '(not configured)'))
    Write-Host ('    assistant username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $assistantUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $assistantPass -EmptyText '(not configured)'))
    if ([string]::Equals([string]$full.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ('  RDP endpoint: {0}:{1} | default role: manager' -f $connectionHost, $rdpPort)
        Write-Host ('    manager username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $adminUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $adminPass -EmptyText '(not configured)'))
        Write-Host ('    assistant username: {0} | password: {1}' -f (Format-ClagnosUiDetailValue -Value $assistantUser -EmptyText '(not configured)'), (Format-ClagnosUiDetailValue -Value $assistantPass -EmptyText '(not configured)'))
        Write-Host ('  PowerShell remoting endpoint: {0}:{1} | roles: manager and assistant | authentication: Negotiate' -f $connectionHost, $powerShellPort)
    }
    else { Write-Host '  RDP: not applicable to this Linux VC.' }
    Write-Host '  Credentials are read from .env; passwords are excluded from progress and operation log messages.' -ForegroundColor Gray
    Write-Host ''

    Write-Host 'Attached resources:' -ForegroundColor Cyan
    $resources = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('resource', 'list', '--resource-group', $group)))
    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) {
        Write-Host ('  {0} | {1} | {2}' -f [string]$resource.type, [string]$resource.name, (Format-ClagnosUiDetailValue -Value $resource.location))
    }
}

function New-ClagnosUiTargetOptions {
    param([psobject]$Vm)

    $options = @{
        group = [string]$Vm.ClagnosResourceGroup
        'vm-name' = [string]$Vm.name
        'subscription-id' = [string]$Vm.ClagnosSubscriptionId
    }
    if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $options['windows'] = $true
    }
    else {
        $options['linux'] = $true
    }
    return $options
}

function Show-ClagnosUiPackageAppStateMenu {
    param(
        [psobject]$Vm,
        [psobject]$Package,
        [ValidateSet('builtin','custom')][string]$Catalog,
        [string]$Platform
    )

    Write-ClagnosUiHeader -Title ('App-state for {0}' -f [string]$Package.DisplayName)
    Write-Host '1. Save package app-state'
    Write-Host '2. Restore package app-state'
    Write-Host 'b: back'
    $choice = (Read-ClagnosUiChoice 'App-state action').ToLowerInvariant()
    if ($choice -eq 'b' -or $choice -notin @('1','2')) { return }
    $save = $choice -eq '1'
    Write-Host 'v: virtual computer | l: local Windows host'
    $surfaceChoice = (Read-ClagnosUiChoice 'App-state source or target').ToLowerInvariant()
    $surface = switch ($surfaceChoice) { 'v' { 'vm' } 'l' { 'lm' } default { '' } }
    if ([string]::IsNullOrWhiteSpace($surface)) { return }
    if ($surface -eq 'lm' -and $Platform -ne 'windows') {
        Write-Host 'Local-machine package app-state is available only on a Windows host.' -ForegroundColor Yellow
        Wait-ClagnosUiContinue
        return
    }

    $options = New-ClagnosUiTargetOptions -Vm $Vm
    $options['package'] = [string]$Package.Id
    $options['package-catalog'] = $Catalog
    $options[$(if ($save) { 'save-app-state' } else { 'restore-app-state' })] = $true
    $options[$(if ($save) { 'source' } else { 'target' })] = $surface
    $options['user'] = Read-ClagnosUiChoice 'User (.all., .current., manager, or assistant)'
    Invoke-ClagnosUiCommand -CommandName 'task' -Options $options
}

function Show-ClagnosUiPackageCatalogMenu {
    param([psobject]$Vm, [ValidateSet('builtin','custom')][string]$Catalog)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    while ($true) {
        Write-ClagnosUiHeader -Title (('{0} package catalog on {1}' -f $Catalog, [string]$Vm.name))
        $packages = @(Get-ClagnosPackageCatalog -Platform $platform -Catalog $Catalog)
        $statusMap = @{}
        if ($packages.Count -gt 0) {
            try {
                $statusOptions = New-ClagnosUiTargetOptions -Vm $Vm
                $statusMap = Get-ClagnosPackageStatusSnapshot -Packages $packages -Options $statusOptions -Platform $platform
            }
            catch {
                Write-Host ('Package status could not be read: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
            }
        }
        if ($packages.Count -eq 0) {
            Write-Host ('No packages are registered in the {0} catalog for {1}.' -f $Catalog, $platform) -ForegroundColor Yellow
        }
        else {
            for ($index = 0; $index -lt $packages.Count; $index++) {
                $status = if ($statusMap.ContainsKey([string]$packages[$index].Id)) { [string]$statusMap[[string]$packages[$index].Id] } else { 'unavailable' }
                $disabledLabel = if ([bool]$packages[$index].Enabled) { '' } else { ' (disabled)' }
                $catalogLabel = if ($Catalog -eq 'builtin') { '[builtin]' } else { '[custom]' }
                Write-Host ('{0}. {1} {2}{3} [{4}]' -f ($index + 1), [string]$packages[$index].DisplayName, $catalogLabel, $disabledLabel, $status)
            }
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $packages.Count) { continue }
        $package = $packages[$number - 1]
        Write-ClagnosUiHeader -Title ([string]$package.DisplayName)
        Write-Host ('Catalog: [{0}]' -f $Catalog)
        if (@($package.PackageTask.PackageSpec.DependsOn).Count -gt 0) {
            Write-Host ('Package prerequisites: {0}' -f (@($package.PackageTask.PackageSpec.DependsOn) -join ', ')) -ForegroundColor Yellow
        }
        Write-Host 'e: enable package'
        Write-Host 'd: disable package'
        Write-Host 'u: uninstall'
        Write-Host 'i: install or update'
        Write-Host 's: status'
        if ($null -ne $package.PackageTask.AppStateSpec) { Write-Host 'a: manage package app-state' }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $action = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'q') { exit }
        if ($action -eq 'a' -and $null -ne $package.PackageTask.AppStateSpec) {
            Show-ClagnosUiPackageAppStateMenu -Vm $Vm -Package $package -Catalog $Catalog -Platform $platform
            continue
        }
        if ($action -notin @('e','d','u','i','s')) { continue }
        $packageAction = switch ($action) { 'e' { 'enable' } 'd' { 'disable' } 'u' { 'uninstall' } 'i' { 'install' } 's' { 'status' } default { '' } }
        $options = @{ catalog = $Catalog; package = [string]$package.Id }
        $options[$platform] = $true
        if ($packageAction -notin @('enable','disable')) {
            $targetOptions = New-ClagnosUiTargetOptions -Vm $Vm
            foreach ($optionName in $targetOptions.Keys) { $options[[string]$optionName] = $targetOptions[$optionName] }
        }
        if ($packageAction -eq 'uninstall') {
            $confirm = (Read-ClagnosUiChoice ('Type UNINSTALL to remove {0}' -f [string]$package.DisplayName))
            if ($confirm -cne 'UNINSTALL') { continue }
            $options['yes'] = $true
        }
        $commandOptions = @{ action = $packageAction }
        foreach ($optionName in $options.Keys) { $commandOptions[[string]$optionName] = $options[$optionName] }
        Invoke-ClagnosUiCommand -CommandName 'package' -Options $commandOptions
    }
}

function Show-ClagnosUiPackageMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Manage programs on {0}' -f [string]$Vm.name)
        Write-Host '1. Builtin package catalog'
        Write-Host '2. Custom package catalog'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        switch ($choice) {
            '1' { Show-ClagnosUiPackageCatalogMenu -Vm $Vm -Catalog 'builtin' }
            '2' { Show-ClagnosUiPackageCatalogMenu -Vm $Vm -Catalog 'custom' }
        }
    }
}

function Show-ClagnosUiComponentMenu {
    param([psobject]$Vm)

    $types = @(
        @{ Id = 'group'; Label = 'Resource group' },
        @{ Id = 'vm'; Label = 'Virtual machine' },
        @{ Id = 'disk'; Label = 'Managed disk' },
        @{ Id = 'vnet'; Label = 'Virtual network' },
        @{ Id = 'subnet'; Label = 'Subnet' },
        @{ Id = 'nic'; Label = 'Network interface' },
        @{ Id = 'ip'; Label = 'Public IP' },
        @{ Id = 'nsg'; Label = 'Network security group' },
        @{ Id = 'nsg-rule'; Label = 'Network security rule' }
    )
    while ($true) {
        Write-ClagnosUiHeader -Title ('Components of {0}' -f [string]$Vm.name)
        for ($index = 0; $index -lt $types.Count; $index++) {
            Write-Host ('{0}. {1}' -f ($index + 1), [string]$types[$index].Label)
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $types.Count) { continue }
        $type = $types[$number - 1]
        Write-ClagnosUiHeader -Title ([string]$type.Label)
        Write-Host 'l: list'
        Write-Host 's: show properties'
        Write-Host 'c: create'
        Write-Host 'u: update properties'
        Write-Host 'd: delete'
        if ($type.Id -in @('disk','nic')) {
            Write-Host 'a: attach'
            Write-Host 't: detach'
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $actionChoice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($actionChoice -eq 'b') { continue }
        if ($actionChoice -eq 'q') { exit }
        if ($actionChoice -in @('a','t') -and $type.Id -in @('disk','nic')) {
            $options = New-ClagnosUiTargetOptions -Vm $Vm
            $options['type'] = [string]$type.Id
            $options['action'] = if ($actionChoice -eq 'a') { 'attach' } else { 'detach' }
            Invoke-ClagnosUiCommand -CommandName 'component' -Options $options
            continue
        }
        $action = switch ($actionChoice) { 'l' { 'list' } 's' { 'show' } 'c' { 'create' } 'u' { 'update' } 'd' { 'delete' } default { '' } }
        if ([string]::IsNullOrWhiteSpace($action)) { continue }
        $options = New-ClagnosUiTargetOptions -Vm $Vm
        $options['type'] = [string]$type.Id
        $options['action'] = $action
        Invoke-ClagnosUiCommand -CommandName 'component' -Options $options
    }
}

function Show-ClagnosUiTaskAvailabilityMenu {
    param([psobject]$Vm)

    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $runtime = if ($platform -eq 'windows') {
        Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$false -WindowsFlag
    }
    else {
        Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$false -LinuxFlag
    }

    while ($true) {
        Write-ClagnosUiHeader -Title ('Task availability for {0}' -f [string]$Vm.name)
        Write-Host 'Task availability is shared by this repository and affects future runs on matching VMs.' -ForegroundColor Yellow
        Write-Host '1. Initialization tasks'
        Write-Host '2. Maintenance tasks'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $stageChoice = (Read-ClagnosUiChoice 'Task stage').ToLowerInvariant()
        if ($stageChoice -eq 'b') { return }
        if ($stageChoice -eq 'q') { exit }
        if ($stageChoice -notin @('1','2')) { continue }

        $stage = if ($stageChoice -eq '1') { 'init' } else { 'update' }
        $stageRoot = if ($stage -eq 'init') { [string]$runtime.VmInitTaskDir } else { [string]$runtime.VmUpdateTaskDir }
        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $stageRoot -Platform $platform -Stage $stage -SuppressSkipMessages
        $tasks = @($catalog.InventoryTasks)
        if ($tasks.Count -eq 0) {
            Write-Host 'No tasks are registered for this stage.' -ForegroundColor Yellow
            Wait-ClagnosUiContinue
            continue
        }

        Write-ClagnosUiHeader -Title ('{0} tasks' -f $(if ($stage -eq 'init') { 'Initialization' } else { 'Maintenance' }))
        for ($index = 0; $index -lt $tasks.Count; $index++) {
            $state = if ([bool]$tasks[$index].Enabled) { 'enabled' } else { ('disabled: ' + [string]$tasks[$index].DisabledReason) }
            Write-Host ('{0}. #{1} {2} [{3}]' -f ($index + 1), [int]$tasks[$index].TaskNumber, [string]$tasks[$index].Name, $state)
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $taskChoice = (Read-ClagnosUiChoice 'Task number from this list').ToLowerInvariant()
        if ($taskChoice -eq 'b') { continue }
        if ($taskChoice -eq 'q') { exit }
        $taskIndex = 0
        if (-not [int]::TryParse($taskChoice, [ref]$taskIndex) -or $taskIndex -lt 1 -or $taskIndex -gt $tasks.Count) { continue }

        $selectedTask = $tasks[$taskIndex - 1]
        Write-ClagnosUiHeader -Title ([string]$selectedTask.Name)
        Write-Host 'e: enable'
        Write-Host 'd: disable'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $action = (Read-ClagnosUiChoice 'Availability action').ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'q') { exit }
        if ($action -notin @('e','d')) { continue }

        $options = @{}
        $options[('vm-{0}-task' -f $stage)] = [string]$selectedTask.Name
        $options[$(if ($action -eq 'e') { 'enable' } else { 'disable' })] = $true
        $options[$platform] = $true
        Invoke-ClagnosUiCommand -CommandName 'task' -Options $options
    }
}

function Show-ClagnosUiTaskMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Tasks on {0}' -f [string]$Vm.name)
        Write-Host '1. List init and update tasks'
        Write-Host '2. Run one init task'
        Write-Host '3. Run one update task'
        Write-Host '4. Save task app-state'
        Write-Host '5. Restore task app-state'
        Write-Host '6. List disabled tasks'
        Write-Host '7. Enable/disable a task'
        Write-Host '8. View recent task run history'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $target = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            '1' { $target['list'] = $true; $target['vm-init'] = $true; $target['vm-update'] = $true; Invoke-ClagnosUiCommand -CommandName 'task' -Options $target }
            '2' { $taskNumber = Read-ClagnosUiChoice 'Task number'; $target['run-vm-init'] = $taskNumber; Invoke-ClagnosUiCommand -CommandName 'task' -Options $target }
            '3' { $taskNumber = Read-ClagnosUiChoice 'Task number'; $target['run-vm-update'] = $taskNumber; Invoke-ClagnosUiCommand -CommandName 'task' -Options $target }
            { $_ -in @('4','5','6') } {
                if ($choice -eq '6') {
                    $target['list'] = $true
                    $target['vm-init'] = $true
                    $target['vm-update'] = $true
                    $target['disabled'] = $true
                    Invoke-ClagnosUiCommand -CommandName 'task' -Options $target
                    break
                }
                Write-Host 'i: init | u: update'
                $stageChoice = (Read-ClagnosUiChoice 'Task stage').ToLowerInvariant()
                $stage = switch ($stageChoice) { 'i' { 'init' } 'u' { 'update' } default { '' } }
                $number = Read-ClagnosUiChoice 'Task number'
                if ([string]::IsNullOrWhiteSpace($stage)) { continue }
                $target[('vm-{0}-task' -f $stage)] = $number
                $target[$(if ($choice -eq '4') { 'save-app-state' } else { 'restore-app-state' })] = $true
                Write-Host 'v: virtual computer | l: local Windows host'
                $surfaceChoice = (Read-ClagnosUiChoice 'App-state target').ToLowerInvariant()
                $surface = switch ($surfaceChoice) { 'v' { 'vm' } 'l' { 'lm' } default { '' } }
                if ($surface -in @('vm','lm')) { $target[$(if ($choice -eq '4') { 'source' } else { 'target' })] = $surface }
                else { continue }
                $target['user'] = Read-ClagnosUiChoice 'User (.all., .current., or name)'
                Invoke-ClagnosUiCommand -CommandName 'task' -Options $target
            }
            '7' { Show-ClagnosUiTaskAvailabilityMenu -Vm $Vm }
            '8' { Invoke-ClagnosUiCommand -CommandName 'task' -Options @{ history = $true } }
        }
    }
}

function Show-ClagnosUiOperationsMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Operations for {0}' -f [string]$Vm.name)
        Write-Host '1. Power, status, and repair'
        Write-Host '2. Resize VM or disk'
        Write-Host '3. Move to another region'
        Write-Host '4. VM features'
        Write-Host '5. Connect by SSH, RDP, or PowerShell'
        Write-Host '6. Run a remote command or shell'
        Write-Host '7. Tasks and app-state'
        Write-Host '8. Component CRUD'
        Write-Host '9. Full read-only report'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $options = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            '1' {
                $actions = @(
                    [pscustomobject]@{ Action = 'status'; Label = 'status (read-only)' },
                    [pscustomobject]@{ Action = 'start'; Label = 'start VM' },
                    [pscustomobject]@{ Action = 'shutdown'; Label = 'shutdown gracefully (stays allocated)' },
                    [pscustomobject]@{ Action = 'hibernate-stop'; Label = 'hibernate through guest OS (stays allocated)' },
                    [pscustomobject]@{ Action = 'hibernate-deallocate'; Label = 'hibernate and deallocate' },
                    [pscustomobject]@{ Action = 'resume'; Label = 'resume hibernated VM' },
                    [pscustomobject]@{ Action = 'restart'; Label = 'restart VM' },
                    [pscustomobject]@{ Action = 'power-off'; Label = 'power off immediately (skip guest shutdown)' },
                    [pscustomobject]@{ Action = 'reset'; Label = 'reset (force restart through Azure redeploy)' },
                    [pscustomobject]@{ Action = 'deallocate'; Label = 'deallocate VM' },
                    [pscustomobject]@{ Action = 'reapply'; Label = 'reapply VM configuration' },
                    [pscustomobject]@{ Action = 'redeploy'; Label = 'redeploy VM to Azure host' }
                )
                for ($index = 0; $index -lt $actions.Count; $index++) { Write-Host ('{0}. {1}' -f ($index + 1), [string]$actions[$index].Label) }
                $actionChoice = Read-ClagnosUiChoice 'VM action number'
                $actionIndex = 0
                if (-not [int]::TryParse($actionChoice, [ref]$actionIndex) -or $actionIndex -lt 1 -or $actionIndex -gt $actions.Count) { continue }
                $selectedAction = [string]$actions[$actionIndex - 1].Action
                if ($selectedAction -eq 'power-off') {
                    if ((Read-ClagnosUiChoice 'Type POWER OFF to force an immediate guest power-off') -cne 'POWER OFF') { continue }
                }
                elseif ($selectedAction -eq 'reset') {
                    if ((Read-ClagnosUiChoice 'Type RESET to force a restart through Azure redeploy') -cne 'RESET') { continue }
                }
                $options['vm-action'] = $selectedAction
                Invoke-ClagnosUiCommand -CommandName 'do' -Options $options
            }
            '2' {
                Write-Host '1. Change VM size'
                Write-Host '2. Expand OS disk'
                Write-Host '3. Show safe shrink guidance'
                $resizeChoice = Read-ClagnosUiChoice 'Resize action'
                if ($resizeChoice -eq '1') {
                    # The resize runtime opens the region-aware Azure SKU picker.
                }
                elseif ($resizeChoice -in @('2','3')) {
                    $options['disk-size'] = Read-ClagnosUiChoice 'Target disk size (for example 128GB)'
                    $options[$(if ($resizeChoice -eq '2') { 'expand' } else { 'shrink' })] = $true
                }
                else { continue }
                Invoke-ClagnosUiCommand -CommandName 'resize' -Options $options
            }
            '3' {
                $options['vm-region'] = Select-AzLocationInteractive -DefaultLocation ([string]$Vm.location)
                Invoke-ClagnosUiCommand -CommandName 'move' -Options $options
            }
            '4' {
                Write-Host 'h: hibernation | n: nested virtualization'
                $feature = (Read-ClagnosUiChoice 'Feature').ToLowerInvariant()
                Write-Host '1: enable | 2: disable'
                $valueChoice = Read-ClagnosUiChoice 'Feature state'
                $value = switch ($valueChoice) { '1' { 'true' } '2' { 'false' } default { '' } }
                if ([string]::IsNullOrWhiteSpace($value)) { continue }
                if ($feature -eq 'h') { $options['hibernation'] = $value }
                elseif ($feature -eq 'n') { $options['nested-virtualization'] = $value }
                else { continue }
                Invoke-ClagnosUiCommand -CommandName 'set' -Options $options
            }
            '5' {
                $isWindowsVm = [string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)
                if ($isWindowsVm) {
                    Write-Host 's: SSH | r: RDP | t: test SSH | d: test RDP | p: PowerShell session | c: PowerShell command | w: test PowerShell'
                }
                else {
                    Write-Host 's: SSH | t: test SSH'
                }
                $transport = (Read-ClagnosUiChoice 'Connection').ToLowerInvariant()
                if ($transport -in @('s','t')) { $options['ssh'] = $true }
                elseif ($transport -in @('r','d') -and $isWindowsVm) { $options['rdp'] = $true }
                elseif ($transport -in @('p','c','w') -and $isWindowsVm) { $options['powershell'] = $true }
                else { continue }
                if ($transport -in @('t','d','w')) { $options['test'] = $true }
                if ($transport -eq 'c') { $options['command'] = Read-ClagnosUiChoice 'Remote PowerShell command' }
                Invoke-ClagnosUiCommand -CommandName 'connect' -Options $options
            }
            '6' {
                $command = Read-ClagnosUiChoice 'Remote command (leave blank for interactive shell)'
                if (-not [string]::IsNullOrWhiteSpace($command)) { $options['command'] = $command }
                Invoke-ClagnosUiCommand -CommandName 'exec' -Options $options
            }
            '7' { Show-ClagnosUiTaskMenu -Vm $Vm }
            '8' { Show-ClagnosUiComponentMenu -Vm $Vm }
            '9' {
                Write-Host 't: show report on screen | j: export redacted JSON'
                $reportMode = (Read-ClagnosUiChoice 'Report output').ToLowerInvariant()
                if ($reportMode -eq 'j') {
                    $exportPath = Read-ClagnosUiChoice 'JSON export path'
                    if ([string]::IsNullOrWhiteSpace([string]$exportPath)) { continue }
                    $options['export-json'] = $exportPath
                    if (Test-Path -LiteralPath $exportPath -PathType Leaf) {
                        if ((Read-ClagnosUiChoice 'Type OVERWRITE to replace the existing report file') -cne 'OVERWRITE') { continue }
                        $options['overwrite'] = $true
                    }
                }
                elseif ($reportMode -notin @('','t')) {
                    continue
                }
                Invoke-ClagnosUiCommand -CommandName 'show' -Options $options
            }
        }
    }
}

function Show-ClagnosUiVmMenu {
    param([psobject]$Vm)

    while ($true) {
        try { Show-ClagnosUiVmDetails -Vm $Vm }
        catch { Write-ClagnosUiHeader -Title ('Virtual computer: {0}' -f [string]$Vm.name); Write-ClagnosUiError -ErrorRecord $_ }
        Write-Host 'p: manage programs'
        Write-Host 'i: initialize VC'
        Write-Host 'u: update VC'
        Write-Host 'm: manage VC components'
        Write-Host 'o: operations'
        Write-Host 'd: delete VC and its resources'
        Write-Host 'r: refresh details'
        Write-Host 'b: back to virtual computers'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $target = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            'p' { Show-ClagnosUiPackageMenu -Vm $Vm }
            'i' { Invoke-ClagnosUiCommand -CommandName 'initialize' -Options $target }
            'u' { Invoke-ClagnosUiCommand -CommandName 'update' -Options $target }
            'm' { Show-ClagnosUiComponentMenu -Vm $Vm }
            'o' { Show-ClagnosUiOperationsMenu -Vm $Vm }
            'd' {
                try {
                    $resources = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('resource', 'list', '--resource-group', [string]$Vm.ClagnosResourceGroup)))
                    Write-Host 'The following Azure resources will be removed:' -ForegroundColor Yellow
                    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) { Write-Host ('  - {0}: {1}' -f [string]$resource.type, [string]$resource.name) }
                    $confirm = Read-ClagnosUiChoice "Type DELETE ALL to remove this VC's complete resource group"
                    if ($confirm -ceq 'DELETE ALL') {
                        $target['target'] = 'group'
                        $target['yes'] = $true
                        Invoke-ClagnosUiCommand -CommandName 'delete' -Options $target
                        return
                    }
                }
                catch { Write-ClagnosUiError -ErrorRecord $_; Wait-ClagnosUiContinue }
            }
        }
    }
}

function Show-ClagnosUiVirtualComputers {
    while ($true) {
        Write-ClagnosUiHeader -Title 'Virtual computers'
        try { $vms = @(Get-ClagnosUiVirtualComputers) }
        catch { Write-ClagnosUiError -ErrorRecord $_; $vms = @() }
        if ($vms.Count -eq 0) {
            Write-Host 'No managed virtual computers were found.' -ForegroundColor Yellow
        }
        else {
            for ($index = 0; $index -lt $vms.Count; $index++) {
                $vm = $vms[$index]
                $power = Get-ClagnosUiPowerState -ResourceGroup ([string]$vm.ClagnosResourceGroup) -VmName ([string]$vm.name)
                Write-Host ('{0}. {1} | {2} | {3} | {4} | {5}' -f ($index + 1), [string]$vm.name, [string]$vm.storageProfile.osDisk.osType, [string]$vm.hardwareProfile.vmSize, [string]$vm.location, $power)
            }
        }
        Write-Host 'c: create virtual computer'
        Write-Host 'r: refresh list'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        if ($choice -eq 'c') { Invoke-ClagnosUiCommand -CommandName 'create' -Options @{}; Update-ClagnosUiSubscription; continue }
        if ($choice -eq 'r') { Update-ClagnosUiSubscription; continue }
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $vms.Count) {
            Show-ClagnosUiVmMenu -Vm $vms[$number - 1]
        }
    }
}

function Show-ClagnosUiInventoryMenu {
    $types = @(
        @{ Id = 'group'; Label = 'Resource groups' },
        @{ Id = 'vm'; Label = 'Virtual machines' },
        @{ Id = 'disk'; Label = 'Managed disks' },
        @{ Id = 'vnet'; Label = 'Virtual networks' },
        @{ Id = 'subnet'; Label = 'Subnets' },
        @{ Id = 'nic'; Label = 'Network interfaces' },
        @{ Id = 'ip'; Label = 'Public IP addresses' },
        @{ Id = 'nsg'; Label = 'Network security groups' },
        @{ Id = 'nsg-rule'; Label = 'Network security rules' }
    )

    while ($true) {
        Write-ClagnosUiHeader -Title 'Managed resource inventory'
        Write-Host '1. All managed resource types'
        for ($index = 0; $index -lt $types.Count; $index++) {
            Write-Host ('{0}. {1}' -f ($index + 2), [string]$types[$index].Label)
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }

        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt ($types.Count + 1)) { continue }
        $options = @{}
        if ($number -gt 1) { $options['type'] = [string]$types[$number - 2].Id }
        $group = Read-ClagnosUiChoice 'Exact resource group filter (press Enter for all managed groups)'
        if (-not [string]::IsNullOrWhiteSpace($group)) { $options['group'] = $group }
        Invoke-ClagnosUiCommand -CommandName 'list' -Options $options
    }
}

function Show-ClagnosUiHome {
    while ($true) {
        Update-ClagnosUiSubscription
        Write-ClagnosUiHeader -Title 'Main menu'
        Write-Host '1. Virtual computers'
        Write-Host '2. Managed resource inventory'
        Write-Host '3. Cloud subscriptions'
        Write-Host 'c: configure settings'
        Write-Host 'h: help'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        switch ($choice) {
            '1' { Show-ClagnosUiVirtualComputers }
            '2' { Show-ClagnosUiInventoryMenu }
            '3' { Show-ClagnosUiCloudSubscriptions }
            'c' { Invoke-ClagnosUiCommand -CommandName 'configure' -Options @{} }
            'h' { Invoke-ClagnosUiCommand -CommandName 'help' -Options @{} }
            'q' { return }
        }
    }
}

Show-ClagnosUiHome
