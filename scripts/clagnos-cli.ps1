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

function Show-ClagnosUiVmDetails {
    param([psobject]$Vm)

    $group = [string]$Vm.ClagnosResourceGroup
    $name = [string]$Vm.name
    $full = Invoke-ClagnosUiAzJson -Arguments @('vm', 'show', '--resource-group', $group, '--name', $name)
    $sizeName = [string]$full.hardwareProfile.vmSize
    $facts = Get-ClagnosUiVmSizeFacts -Location ([string]$full.location) -Size $sizeName
    $memoryGb = if ($facts.MemoryMb -match '^\d+$') { ('{0:N1} GB' -f ([double]$facts.MemoryMb / 1024)) } else { 'Unknown' }
    $power = Get-ClagnosUiPowerState -ResourceGroup $group -VmName $name
    Write-ClagnosUiHeader -Title ('Virtual computer: {0}' -f $name)
    Write-Host ('Resource group: {0}' -f $group)
    Write-Host ('Operating system: {0}' -f [string]$full.storageProfile.osDisk.osType)
    Write-Host ('State: {0} | Provisioning: {1}' -f $power, [string]$full.provisioningState)
    Write-Host ('Region: {0} | Size: {1}' -f [string]$full.location, $sizeName)
    Write-Host ('CPU: {0} vCPU | RAM: {1}' -f [string]$facts.Cores, $memoryGb)
    Write-Host ''
    Write-Host 'Storage and disks:' -ForegroundColor Cyan
    $diskNames = @([string]$full.storageProfile.osDisk.name) + @($full.storageProfile.dataDisks | ForEach-Object { [string]$_.name })
    foreach ($diskName in @($diskNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        try {
            $disk = Invoke-ClagnosUiAzJson -Arguments @('disk', 'show', '--resource-group', $group, '--name', $diskName)
            Write-Host ('  {0} | {1} GB | {2}' -f [string]$disk.name, [string]$disk.diskSizeGb, [string]$disk.sku.name)
        }
        catch { Write-Host ('  {0} | details unavailable' -f $diskName) -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host 'Attached resources:' -ForegroundColor Cyan
    $resources = @(ConvertTo-ObjectArrayCompat -InputObject (Invoke-ClagnosUiAzJson -Arguments @('resource', 'list', '--resource-group', $group)))
    foreach ($resource in @($resources | Sort-Object { [string]$_.type }, { [string]$_.name })) {
        Write-Host ('  {0} | {1}' -f [string]$resource.type, [string]$resource.name)
    }
    Write-Host ''
    Write-Host 'Network addresses:' -ForegroundColor Cyan
    if (-not [string]::IsNullOrWhiteSpace([string]$Vm.publicIps)) { Write-Host ('  Public IP: {0}' -f [string]$Vm.publicIps) }
    if (-not [string]::IsNullOrWhiteSpace([string]$Vm.privateIps)) { Write-Host ('  Private IP: {0}' -f [string]$Vm.privateIps) }
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

function Show-ClagnosUiProgramMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Programs on {0}' -f [string]$Vm.name)
        $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
        $catalog = @(Get-ClagnosProgramCatalog -Platform $platform)
        $statusMap = @{}
        if ($catalog.Count -gt 0) {
            try {
                $statusOptions = New-ClagnosUiTargetOptions -Vm $Vm
                $statusMap = Get-ClagnosProgramStatusSnapshot -Programs $catalog -Options $statusOptions -Platform $platform
            }
            catch {
                Write-Host ('Program status could not be read: {0}' -f $_.Exception.Message) -ForegroundColor Yellow
            }
        }
        if ($catalog.Count -eq 0) {
            Write-Host 'No program installers are registered for this platform yet.' -ForegroundColor Yellow
        }
        else {
            for ($index = 0; $index -lt $catalog.Count; $index++) {
                $status = if ($statusMap.ContainsKey([string]$catalog[$index].Id)) { [string]$statusMap[[string]$catalog[$index].Id] } else { 'unavailable' }
                Write-Host ('{0}. {1} [{2}]' -f ($index + 1), [string]$catalog[$index].DisplayName, [string]$status)
            }
        }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $number = 0
        if (-not [int]::TryParse($choice, [ref]$number) -or $number -lt 1 -or $number -gt $catalog.Count) { continue }
        $program = $catalog[$number - 1]
        Write-ClagnosUiHeader -Title ([string]$program.DisplayName)
        Write-Host 's: status'
        Write-Host 'i: install or update'
        Write-Host 'u: uninstall'
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $action = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($action -eq 'b') { continue }
        if ($action -eq 'q') { exit }
        $programAction = switch ($action) { 's' { 'status' } 'i' { 'install' } 'u' { 'uninstall' } default { '' } }
        if ([string]::IsNullOrWhiteSpace($programAction)) { continue }
        $options = New-ClagnosUiTargetOptions -Vm $Vm
        $options['action'] = $programAction
        $options['program'] = [string]$program.Id
        if ($programAction -eq 'uninstall') {
            $confirm = (Read-ClagnosUiChoice ('Type UNINSTALL to remove {0}' -f [string]$program.DisplayName))
            if ($confirm -cne 'UNINSTALL') { continue }
            $options['yes'] = $true
        }
        Invoke-ClagnosUiCommand -CommandName 'program' -Options $options
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
        Write-Host 'l: list/read'
        Write-Host 'c: create'
        Write-Host 'u: update properties'
        Write-Host 'd: delete'
        if ($type.Id -in @('disk','nic')) { Write-Host 'a: attach or detach' }
        Write-Host 'b: back'
        Write-Host 'q: exit'
        $actionChoice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($actionChoice -eq 'b') { continue }
        if ($actionChoice -eq 'q') { exit }
        if ($actionChoice -eq 'a' -and $type.Id -in @('disk','nic')) {
            $options = New-ClagnosUiTargetOptions -Vm $Vm
            $options['type'] = [string]$type.Id
            $options['action'] = (Read-ClagnosUiChoice 'Action: attach or detach').ToLowerInvariant()
            Invoke-ClagnosUiCommand -CommandName 'component' -Options $options
            continue
        }
        $action = switch ($actionChoice) { 'l' { 'list' } 'c' { 'create' } 'u' { 'update' } 'd' { 'delete' } default { '' } }
        if ([string]::IsNullOrWhiteSpace($action)) { continue }
        $options = New-ClagnosUiTargetOptions -Vm $Vm
        $options['type'] = [string]$type.Id
        $options['action'] = $action
        Invoke-ClagnosUiCommand -CommandName 'component' -Options $options
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
            { $_ -in @('4','5') } {
                $stage = (Read-ClagnosUiChoice 'Task stage: init or update').ToLowerInvariant()
                $number = Read-ClagnosUiChoice 'Task number'
                if ($stage -notin @('init','update')) { continue }
                $target[('vm-{0}-task' -f $stage)] = $number
                $target[$(if ($choice -eq '4') { 'save-app-state' } else { 'restore-app-state' })] = $true
                $surface = (Read-ClagnosUiChoice 'Target: vm or lm (local Windows host)').ToLowerInvariant()
                if ($surface -in @('vm','lm')) { $target[$(if ($choice -eq '4') { 'source' } else { 'target' })] = $surface }
                $target['user'] = Read-ClagnosUiChoice 'User (.all., .current., or name)'
                Invoke-ClagnosUiCommand -CommandName 'task' -Options $target
            }
        }
    }
}

function Show-ClagnosUiAdvancedMenu {
    param([psobject]$Vm)

    while ($true) {
        Write-ClagnosUiHeader -Title ('Operations for {0}' -f [string]$Vm.name)
        Write-Host '1. Power, status, and repair'
        Write-Host '2. Resize VM or disk'
        Write-Host '3. Move to another region'
        Write-Host '4. VM features'
        Write-Host '5. Connect by SSH or RDP'
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
                Write-Host 'Actions: status, start, restart, stop, deallocate, reapply, redeploy, hibernate-stop, hibernate-deallocate'
                $options['vm-action'] = Read-ClagnosUiChoice 'Action'
                Invoke-ClagnosUiCommand -CommandName 'do' -Options $options
            }
            '2' {
                Write-Host 'Leave size blank to change the OS disk instead.'
                $size = Read-ClagnosUiChoice 'New VM size (for example Standard_B2s)'
                if (-not [string]::IsNullOrWhiteSpace($size)) { $options['vm-size'] = $size }
                else {
                    $options['disk-size'] = Read-ClagnosUiChoice 'Target disk size (for example 128GB)'
                    $options[(Read-ClagnosUiChoice 'Intent: expand or shrink').ToLowerInvariant()] = $true
                }
                Invoke-ClagnosUiCommand -CommandName 'resize' -Options $options
            }
            '3' {
                $options['vm-region'] = Read-ClagnosUiChoice 'Target Azure region'
                Invoke-ClagnosUiCommand -CommandName 'move' -Options $options
            }
            '4' {
                Write-Host 'h: hibernation | n: nested virtualization'
                $feature = (Read-ClagnosUiChoice 'Feature').ToLowerInvariant()
                $value = Read-ClagnosUiChoice 'Value: true or false'
                if ($feature -eq 'h') { $options['hibernation'] = $value }
                elseif ($feature -eq 'n') { $options['nested-virtualization'] = $value }
                else { continue }
                Invoke-ClagnosUiCommand -CommandName 'set' -Options $options
            }
            '5' {
                Write-Host 's: SSH | r: RDP | t: test SSH | d: test RDP'
                $transport = (Read-ClagnosUiChoice 'Connection').ToLowerInvariant()
                if ($transport -in @('s','t')) { $options['ssh'] = $true }
                elseif ($transport -in @('r','d') -and [string]::Equals([string]$Vm.storageProfile.osDisk.osType, 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) { $options['rdp'] = $true }
                else { continue }
                if ($transport -in @('t','d')) { $options['test'] = $true }
                Invoke-ClagnosUiCommand -CommandName 'connect' -Options $options
            }
            '6' {
                $command = Read-ClagnosUiChoice 'Remote command (leave blank for interactive shell)'
                if (-not [string]::IsNullOrWhiteSpace($command)) { $options['command'] = $command }
                Invoke-ClagnosUiCommand -CommandName 'exec' -Options $options
            }
            '7' { Show-ClagnosUiTaskMenu -Vm $Vm }
            '8' { Show-ClagnosUiComponentMenu -Vm $Vm }
            '9' { Invoke-ClagnosUiCommand -CommandName 'show' -Options $options }
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
        Write-Host 'a: more operations'
        Write-Host 'd: delete VC and its resources'
        Write-Host 'r: refresh details'
        Write-Host 'b: back to virtual computers'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        if ($choice -eq 'b') { return }
        if ($choice -eq 'q') { exit }
        $target = New-ClagnosUiTargetOptions -Vm $Vm
        switch ($choice) {
            'p' { Show-ClagnosUiProgramMenu -Vm $Vm }
            'i' { Invoke-ClagnosUiCommand -CommandName 'initialize' -Options $target }
            'u' { Invoke-ClagnosUiCommand -CommandName 'update' -Options $target }
            'm' { Show-ClagnosUiComponentMenu -Vm $Vm }
            'a' { Show-ClagnosUiAdvancedMenu -Vm $Vm }
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

function Show-ClagnosUiHome {
    while ($true) {
        Update-ClagnosUiSubscription
        Write-ClagnosUiHeader -Title 'Main menu'
        Write-Host '1. Virtual computers'
        Write-Host 's: select Azure subscription'
        Write-Host 'c: configure settings'
        Write-Host 'h: help'
        Write-Host 'q: exit'
        $choice = (Read-ClagnosUiChoice).ToLowerInvariant()
        switch ($choice) {
            '1' { Show-ClagnosUiVirtualComputers }
            's' {
                try {
                    $rows = @(Get-ClagnosAccessibleSubscriptionRows)
                    $currentId = if ($null -ne $script:ClagnosUiSubscription) { [string]$script:ClagnosUiSubscription.SubscriptionId } else { '' }
                    $selected = Select-ClagnosSubscriptionInteractive -DefaultSubscriptionId $currentId
                    Save-ClagnosSubscriptionIdToDotEnv -EnvFilePath (Join-Path $script:ClagnosUiRepoRoot '.env') -SubscriptionId ([string]$selected.id)
                    Set-ClagnosResolvedSubscriptionContext -SubscriptionId ([string]$selected.id) -SubscriptionName ([string]$selected.name) -TenantId ([string]$selected.tenantId) -ResolutionSource 'interactive'
                }
                catch { Write-ClagnosUiError -ErrorRecord $_; Wait-ClagnosUiContinue }
            }
            'c' { Invoke-ClagnosUiCommand -CommandName 'configure' -Options @{} }
            'h' { Invoke-ClagnosUiCommand -CommandName 'help' -Options @{} }
            'q' { return }
        }
    }
}

Show-ClagnosUiHome
