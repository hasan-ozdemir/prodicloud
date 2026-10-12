# Do command runtime helpers.

# Handles Get-ClagnosDoActionNames.
function Get-ClagnosDoActionNames {
    return @('status','start','resume','restart','reset','shutdown','stop','power-off','deallocate','hibernate-deallocate','hibernate-stop','reapply','redeploy')
}

# Handles Get-ClagnosDoActionHintText.
function Get-ClagnosDoActionHintText {
    return ("Use --vm-action={0}." -f ((Get-ClagnosDoActionNames) -join '|'))
}

# Handles Resolve-ClagnosDoActionName.
function Resolve-ClagnosDoActionName {
    param(
        [string]$RawValue,
        [switch]$AllowEmpty
    )

    $action = if ($null -eq $RawValue) { '' } else { [string]$RawValue }
    $normalized = $action.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace([string]$normalized)) {
        if ($AllowEmpty) {
            return ''
        }

        Throw-FriendlyError `
            -Detail "Option '--vm-action' requires a value." `
            -Code 2 `
            -Summary "VM action is missing." `
            -Hint (Get-ClagnosDoActionHintText)
    }

    if ($normalized -eq 'release') {
        Throw-FriendlyError `
            -Detail "Option '--vm-action=release' is no longer supported." `
            -Code 2 `
            -Summary "VM action is invalid." `
            -Hint "Use --vm-action=deallocate."
    }

    if ($normalized -eq 'hibernate') {
        Throw-FriendlyError `
            -Detail "Option '--vm-action=hibernate' is no longer supported." `
            -Code 2 `
            -Summary "VM action is invalid." `
            -Hint "Use --vm-action=hibernate-deallocate or --vm-action=hibernate-stop."
    }

    if ($normalized -notin @(Get-ClagnosDoActionNames)) {
        Throw-FriendlyError `
            -Detail ("Invalid --vm-action value '{0}'." -f $RawValue) `
            -Code 2 `
            -Summary "VM action is invalid." `
            -Hint (Get-ClagnosDoActionHintText)
    }

    return $normalized
}

# Handles Resolve-ClagnosVmLifecycleFieldText.
function Resolve-ClagnosVmLifecycleFieldText {
    param(
        [string]$DisplayText,
        [string]$CodeText,
        [string]$DefaultText = '(none)'
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$DisplayText)) {
        return [string]$DisplayText
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$CodeText)) {
        return [string]$CodeText
    }

    return [string]$DefaultText
}

# Handles Resolve-ClagnosVmLifecycleStateLabel.
function Resolve-ClagnosVmLifecycleStateLabel {
    param(
        [string]$PowerStateDisplay,
        [string]$PowerStateCode,
        [string]$HibernationStateDisplay,
        [string]$HibernationStateCode
    )

    $powerText = ((@([string]$PowerStateDisplay, [string]$PowerStateCode) -join ' ').Trim()).ToLowerInvariant()
    $hibernationText = ((@([string]$HibernationStateDisplay, [string]$HibernationStateCode) -join ' ').Trim()).ToLowerInvariant()

    if ($hibernationText -match 'hibernat') {
        return 'hibernated'
    }
    if ($powerText -match 'running') {
        return 'started'
    }
    if (($powerText -match 'stopped') -and -not ($powerText -match 'deallocated')) {
        return 'stopped'
    }
    if ($powerText -match 'deallocated') {
        return 'deallocated'
    }

    return 'other'
}

# Handles ConvertTo-ClagnosVmLifecycleSnapshot.
function ConvertTo-ClagnosVmLifecycleSnapshot {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [object]$VmObject,
        [object]$InstanceViewObject
    )

    $powerStateCode = ''
    $powerStateDisplay = ''
    $provisioningStateCode = ''
    $provisioningStateDisplay = ''
    $hibernationStateCode = ''
    $hibernationStateDisplay = ''

    $statusEntries = @()
    if ($null -ne $InstanceViewObject -and $InstanceViewObject.PSObject.Properties.Match('instanceView').Count -gt 0 -and $null -ne $InstanceViewObject.instanceView) {
        $statusEntries = @(ConvertTo-ObjectArrayCompat -InputObject $InstanceViewObject.instanceView.statuses)
    }
    if ($statusEntries.Count -eq 0) {
        $statusEntries = @(ConvertTo-ObjectArrayCompat -InputObject $InstanceViewObject.statuses)
    }

    foreach ($status in @($statusEntries)) {
        $statusCode = [string]$status.code
        $statusDisplay = [string]$status.displayStatus
        if ([string]::IsNullOrWhiteSpace([string]$statusCode)) {
            continue
        }

        if ($statusCode.StartsWith('PowerState/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $powerStateCode = $statusCode
            $powerStateDisplay = $statusDisplay
            continue
        }
        if ($statusCode.StartsWith('ProvisioningState/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $provisioningStateCode = $statusCode
            $provisioningStateDisplay = $statusDisplay
            continue
        }
        if ($statusCode.StartsWith('HibernationState/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $hibernationStateCode = $statusCode
            $hibernationStateDisplay = $statusDisplay
            continue
        }
    }

    $hibernationEnabled = $false
    if ($null -ne $VmObject -and $VmObject.PSObject.Properties.Match('hibernationEnabled').Count -gt 0 -and $null -ne $VmObject.hibernationEnabled) {
        $hibernationEnabled = [bool]$VmObject.hibernationEnabled
    }
    elseif ($null -ne $VmObject -and $VmObject.PSObject.Properties.Match('additionalCapabilities').Count -gt 0 -and $null -ne $VmObject.additionalCapabilities) {
        if ($VmObject.additionalCapabilities.PSObject.Properties.Match('hibernationEnabled').Count -gt 0 -and $null -ne $VmObject.additionalCapabilities.hibernationEnabled) {
            $hibernationEnabled = [bool]$VmObject.additionalCapabilities.hibernationEnabled
        }
    }

    $normalizedState = Resolve-ClagnosVmLifecycleStateLabel `
        -PowerStateDisplay $powerStateDisplay `
        -PowerStateCode $powerStateCode `
        -HibernationStateDisplay $hibernationStateDisplay `
        -HibernationStateCode $hibernationStateCode

    return [pscustomobject]@{
        ResourceGroup = [string]$ResourceGroup
        VmName = [string]$VmName
        OsType = [string]$VmObject.osType
        Location = [string]$VmObject.location
        HibernationEnabled = [bool]$hibernationEnabled
        ProvisioningStateCode = [string]$provisioningStateCode
        ProvisioningStateDisplay = [string]$provisioningStateDisplay
        PowerStateCode = [string]$powerStateCode
        PowerStateDisplay = [string]$powerStateDisplay
        HibernationStateCode = [string]$hibernationStateCode
        HibernationStateDisplay = [string]$hibernationStateDisplay
        NormalizedState = [string]$normalizedState
    }
}

# Handles Get-ClagnosVmLifecycleSnapshot.
function Get-ClagnosVmLifecycleSnapshot {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $vmJson = az vm show `
        -g $ResourceGroup `
        -n $VmName `
        --query "{location:location,osType:storageProfile.osDisk.osType,hibernationEnabled:additionalCapabilities.hibernationEnabled}" `
        -o json `
        --only-show-errors
    Assert-LastExitCode "az vm show (do lifecycle)"
    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    if ($null -eq $vmObject) {
        throw "VM lifecycle metadata could not be parsed."
    }

    $instanceViewJson = az vm get-instance-view -g $ResourceGroup -n $VmName -o json --only-show-errors
    Assert-LastExitCode "az vm get-instance-view (do lifecycle)"
    $instanceViewObject = ConvertFrom-JsonCompat -InputObject $instanceViewJson
    if ($null -eq $instanceViewObject) {
        throw "VM instance view could not be parsed."
    }

    return (ConvertTo-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName -VmObject $vmObject -InstanceViewObject $instanceViewObject)
}

# Handles Format-ClagnosVmLifecycleSummaryText.
function Format-ClagnosVmLifecycleSummaryText {
    param(
        [psobject]$Snapshot
    )

    $powerStateText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.PowerStateDisplay) -CodeText ([string]$Snapshot.PowerStateCode)
    $hibernationStateText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.HibernationStateDisplay) -CodeText ([string]$Snapshot.HibernationStateCode)
    $provisioningStateText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.ProvisioningStateDisplay) -CodeText ([string]$Snapshot.ProvisioningStateCode) -DefaultText '(unknown)'
    $hibernationEnabledText = if ([bool]$Snapshot.HibernationEnabled) { 'true' } else { 'false' }

    return ("lifecycle={0}; power={1}; hibernation={2}; provisioning={3}; hibernationEnabled={4}" -f [string]$Snapshot.NormalizedState, $powerStateText, $hibernationStateText, $provisioningStateText, $hibernationEnabledText)
}

# Handles Get-ClagnosDoAllowedSourceStates.
function Get-ClagnosDoAllowedSourceStates {
    param(
        [string]$ActionName
    )

    switch ($ActionName) {
        'start' { return @('stopped','deallocated','hibernated') }
        'resume' { return @('hibernated') }
        'restart' { return @('started') }
        'reset' { return @('started') }
        'shutdown' { return @('started') }
        'stop' { return @('started') }
        'power-off' { return @('started') }
        'deallocate' { return @('started','stopped','hibernated') }
        'hibernate-deallocate' { return @('started') }
        'hibernate-stop' { return @('started') }
        'reapply' { return @() }
        'redeploy' { return @() }
        default { return @() }
    }
}

# Handles Assert-ClagnosDoActionAllowed.
function Assert-ClagnosDoActionAllowed {
    param(
        [string]$ActionName,
        [psobject]$Snapshot
    )

    if ($ActionName -eq 'status') {
        return
    }

    $provisioningSucceeded = $false
    if ([string]::Equals([string]$Snapshot.ProvisioningStateCode, 'ProvisioningState/succeeded', [System.StringComparison]::OrdinalIgnoreCase)) {
        $provisioningSucceeded = $true
    }
    elseif ([string]::Equals([string]$Snapshot.ProvisioningStateDisplay, 'Provisioning succeeded', [System.StringComparison]::OrdinalIgnoreCase)) {
        $provisioningSucceeded = $true
    }

    if (($ActionName -notin @('reapply','redeploy')) -and -not $provisioningSucceeded) {
        Throw-FriendlyError `
            -Detail ("Requested action '{0}' cannot continue for VM '{1}' in resource group '{2}' because provisioning is not ready. {3}" -f $ActionName, [string]$Snapshot.VmName, [string]$Snapshot.ResourceGroup, (Format-ClagnosVmLifecycleSummaryText -Snapshot $Snapshot)) `
            -Code 66 `
            -Summary "VM action cannot continue because provisioning is not in succeeded state." `
            -Hint "Wait until provisioning succeeds, run '--vm-action=status', then retry."
    }

    if (($ActionName -in @('hibernate-deallocate','hibernate-stop')) -and -not [bool]$Snapshot.HibernationEnabled) {
        Throw-FriendlyError `
            -Detail ("Requested action '{0}' cannot continue for VM '{1}' in resource group '{2}' because hibernation is not enabled. {3}" -f $ActionName, [string]$Snapshot.VmName, [string]$Snapshot.ResourceGroup, (Format-ClagnosVmLifecycleSummaryText -Snapshot $Snapshot)) `
            -Code 66 `
            -Summary "Hibernate action is not available for this VM." `
            -Hint "Enable hibernation support first, or use stop/deallocate instead."
    }

    $allowedStates = @(Get-ClagnosDoAllowedSourceStates -ActionName $ActionName)
    if ($allowedStates.Count -eq 0) {
        return
    }

    if ($allowedStates -notcontains [string]$Snapshot.NormalizedState) {
        Throw-FriendlyError `
            -Detail ("Requested action '{0}' cannot run for VM '{1}' in resource group '{2}'. {3}. Allowed source states: {4}." -f $ActionName, [string]$Snapshot.VmName, [string]$Snapshot.ResourceGroup, (Format-ClagnosVmLifecycleSummaryText -Snapshot $Snapshot), ($allowedStates -join ', ')) `
            -Code 66 `
            -Summary ("VM action '{0}' is not valid for the current VM state." -f $ActionName) `
            -Hint ("Run '--vm-action=status' for current state details and retry only from: {0}." -f ($allowedStates -join ', '))
    }
}

# Handles Resolve-ClagnosDoBoundedTimeoutSeconds.
function Resolve-ClagnosDoBoundedTimeoutSeconds {
    param(
        [hashtable]$ConfigMap,
        [string]$Key,
        [int]$DefaultValue,
        [int]$MinimumValue,
        [int]$MaximumValue
    )

    $rawText = [string](Get-ConfigValue -Config $ConfigMap -Key $Key -DefaultValue ([string]$DefaultValue))
    $resolvedValue = 0
    if (-not [int]::TryParse([string]$rawText, [ref]$resolvedValue)) {
        $resolvedValue = $DefaultValue
    }

    if ($resolvedValue -lt $MinimumValue) {
        $resolvedValue = $MinimumValue
    }
    if ($resolvedValue -gt $MaximumValue) {
        $resolvedValue = $MaximumValue
    }

    return [int]$resolvedValue
}

# Handles Initialize-ClagnosDoHibernateStopRuntime.
function Initialize-ClagnosDoHibernateStopRuntime {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    return (Initialize-ClagnosConnectionCommandContext -Options @{
            group = [string]$ResourceGroup
            'vm-name' = [string]$VmName
            user = 'manager'
        } -OperationName 'hibernate-stop')
}

# Handles Invoke-ClagnosDoGuestHibernateStopCommand.
function Invoke-ClagnosDoGuestHibernateStopCommand {
    param(
        [string]$ResourceGroup,
        [string]$VmName
    )

    $runtime = Initialize-ClagnosDoHibernateStopRuntime -ResourceGroup $ResourceGroup -VmName $VmName
    $sshPort = Resolve-ClagnosConnectionPortNumber -PortText ([string]$runtime.VmSshPort) -PortLabel 'SSH'
    $sshReachable = Wait-ClagnosTcpPortReachable -HostName ([string]$runtime.ConnectionHost) -Port $sshPort -MaxAttempts 3 -DelaySeconds 5 -TimeoutSeconds 5 -Label 'ssh'
    if (-not $sshReachable) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' in resource group '{1}' is running, but SSH port {2} is not reachable on host '{3}'." -f [string]$runtime.VmName, [string]$runtime.ResourceGroup, $sshPort, [string]$runtime.ConnectionHost) `
            -Code 66 `
            -Summary "Hibernate-stop requires a working SSH connection." `
            -Hint "Confirm the guest SSH service is ready and retry, or use --vm-action=hibernate-deallocate."
    }

    $repoRoot = Get-ClagnosRepoRoot
    $configuredPySshClientPath = [string](Get-ConfigValue -Config $runtime.ConfigMap -Key 'PYSSH_CLIENT_PATH' -DefaultValue '')
    $pySshTools = Ensure-ClagnosPySshTools -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath
    $connectTimeoutSeconds = Resolve-ClagnosDoBoundedTimeoutSeconds -ConfigMap $runtime.ConfigMap -Key 'SSH_CONNECT_TIMEOUT_SECONDS' -DefaultValue 30 -MinimumValue 5 -MaximumValue 300

    $launchResult = Invoke-ClagnosProcessWithRetry `
        -FilePath ([string]$pySshTools.PythonPath) `
        -Arguments @(
            [string]$pySshTools.ClientPath,
            'exec',
            '--host', [string]$runtime.ConnectionHost,
            '--port', [string]$runtime.VmSshPort,
            '--user', [string]$runtime.SelectedUserName,
            '--password', [string]$runtime.SelectedPassword,
            '--timeout', [string]$connectTimeoutSeconds,
            '--command', 'shutdown /h /f'
        ) `
        -Label ("pyssh hibernate-stop -> {0}@{1}:{2}" -f [string]$runtime.SelectedUserName, [string]$runtime.ConnectionHost, [string]$runtime.VmSshPort) `
        -MaxAttempts 1 `
        -AllowFailure

    return [pscustomobject]@{
        Runtime = $runtime
        LaunchResult = $launchResult
    }
}

# Handles Wait-ClagnosDoHibernateStopCompletion.
function Wait-ClagnosDoHibernateStopCompletion {
    param(
        [psobject]$Runtime,
        [string]$ResourceGroup,
        [string]$VmName,
        [int]$MaxAttempts = 24,
        [int]$DelaySeconds = 10
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($MaxAttempts -gt 120) { $MaxAttempts = 120 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }

    $sshPort = Resolve-ClagnosConnectionPortNumber -PortText ([string]$Runtime.VmSshPort) -PortLabel 'SSH'
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $snapshot = Get-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName
        $powerText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$snapshot.PowerStateDisplay) -CodeText ([string]$snapshot.PowerStateCode)
        $hibernationText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$snapshot.HibernationStateDisplay) -CodeText ([string]$snapshot.HibernationStateCode)
        $sshReachable = Test-ClagnosTcpPortReachable -HostName ([string]$Runtime.ConnectionHost) -Port $sshPort -TimeoutSeconds 3
        Write-ClagnosActionProgress -Action ("verify hibernate-stop state: lifecycle={0}; power={1}; hibernation={2}; ssh-open={3} (attempt {4}/{5})" -f [string]$snapshot.NormalizedState, $powerText, $hibernationText, [bool]$sshReachable, $attempt, $MaxAttempts)

        if ([string]::Equals([string]$snapshot.NormalizedState, 'deallocated', [System.StringComparison]::OrdinalIgnoreCase)) {
            Throw-FriendlyError `
                -Detail ("VM '{0}' in resource group '{1}' became deallocated while waiting for hibernate-stop. {2}" -f [string]$snapshot.VmName, [string]$snapshot.ResourceGroup, (Format-ClagnosVmLifecycleSummaryText -Snapshot $snapshot)) `
                -Code 66 `
                -Summary "Hibernate-stop ended in a deallocated VM." `
                -Hint "Use --vm-action=hibernate-deallocate when the Azure deallocation-based hibernate path is intended."
        }

        if (([string]$snapshot.NormalizedState -in @('stopped','hibernated')) -and -not $sshReachable) {
            return $snapshot
        }

        Write-ClagnosActionProgress -Action ("wait {0}s for VM hibernate-stop state" -f $DelaySeconds)
        Start-Sleep -Seconds $DelaySeconds
    }

    return $null
}

# Handles Write-ClagnosDoStatusReport.
function Write-ClagnosDoStatusReport {
    param(
        [psobject]$Snapshot
    )

    $hibernationEnabledText = if ([bool]$Snapshot.HibernationEnabled) { 'true' } else { 'false' }
    Write-Host ("VM lifecycle status for '{0}' in group '{1}':" -f [string]$Snapshot.VmName, [string]$Snapshot.ResourceGroup) -ForegroundColor Cyan
    Write-Host ("- lifecycle = {0}" -f [string]$Snapshot.NormalizedState)
    Write-Host ("- power-state = {0}" -f (Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.PowerStateDisplay) -CodeText ([string]$Snapshot.PowerStateCode)))
    Write-Host ("- hibernation-state = {0}" -f (Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.HibernationStateDisplay) -CodeText ([string]$Snapshot.HibernationStateCode)))
    Write-Host ("- provisioning-state = {0}" -f (Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$Snapshot.ProvisioningStateDisplay) -CodeText ([string]$Snapshot.ProvisioningStateCode) -DefaultText '(unknown)'))
    Write-Host ("- hibernation-enabled = {0}" -f $hibernationEnabledText)
}

# Handles Assert-ClagnosConnectionVmRunning.
function Assert-ClagnosConnectionVmRunning {
    param(
        [string]$OperationName,
        [psobject]$Snapshot
    )

    if ([string]::Equals([string]$Snapshot.NormalizedState, 'started', [System.StringComparison]::OrdinalIgnoreCase)) {
        return
    }

    $commandLabel = ([string]$OperationName).ToUpperInvariant()
    Throw-FriendlyError `
        -Detail ("The {0} command cannot launch because VM '{1}' in resource group '{2}' is not running. {3}" -f $OperationName, [string]$Snapshot.VmName, [string]$Snapshot.ResourceGroup, (Format-ClagnosVmLifecycleSummaryText -Snapshot $Snapshot)) `
        -Code 66 `
        -Summary ("{0} requires the VM to be running." -f $commandLabel) `
        -Hint ("Start the VM with 'clagnos do --vm-action=start --group={0} --vm-name={1}' and retry." -f [string]$Snapshot.ResourceGroup, [string]$Snapshot.VmName)
}

# Handles Read-ClagnosDoActionInteractive.
function Read-ClagnosDoActionInteractive {
    param(
        [psobject]$Snapshot
    )

    Write-Host ""
    Write-ClagnosDoStatusReport -Snapshot $Snapshot
    Write-Host ""
    Write-Host "Available VM actions (select by number, default=status):" -ForegroundColor Cyan
    $choices = @(
        [pscustomobject]@{ Number = 1; Action = 'status'; Label = 'status (read-only)' },
        [pscustomobject]@{ Number = 2; Action = 'start'; Label = 'start' },
        [pscustomobject]@{ Number = 3; Action = 'restart'; Label = 'restart' },
        [pscustomobject]@{ Number = 4; Action = 'stop'; Label = 'stop' },
        [pscustomobject]@{ Number = 5; Action = 'deallocate'; Label = 'deallocate' },
        [pscustomobject]@{ Number = 6; Action = 'hibernate-deallocate'; Label = 'hibernate-deallocate (Azure)' },
        [pscustomobject]@{ Number = 7; Action = 'hibernate-stop'; Label = 'hibernate-stop (guest via SSH)' },
        [pscustomobject]@{ Number = 8; Action = 'reapply'; Label = 'reapply (Azure repair)' },
        [pscustomobject]@{ Number = 9; Action = 'redeploy'; Label = 'redeploy (Azure host repair)' },
        [pscustomobject]@{ Number = 10; Action = 'shutdown'; Label = 'shutdown gracefully (stays allocated)' },
        [pscustomobject]@{ Number = 11; Action = 'resume'; Label = 'resume a hibernated VM' },
        [pscustomobject]@{ Number = 12; Action = 'power-off'; Label = 'power off immediately (skip guest shutdown)' },
        [pscustomobject]@{ Number = 13; Action = 'reset'; Label = 'reset (force restart through redeploy)' }
    )

    foreach ($choice in @($choices)) {
        Write-Host ("{0}. {1}" -f [int]$choice.Number, [string]$choice.Label)
    }

    while ($true) {
        $raw = Read-Host "Enter VM action number or name (default=status)"
        if ([string]::IsNullOrWhiteSpace([string]$raw)) {
            return 'status'
        }

        $text = [string]$raw
        $trimmed = $text.Trim()
        if ($trimmed -match '^\d+$') {
            $picked = @($choices | Where-Object { [int]$_.Number -eq [int]$trimmed } | Select-Object -First 1)
            if (@($picked).Count -gt 0) {
                return [string]$picked[0].Action
            }
        }

        try {
            return (Resolve-ClagnosDoActionName -RawValue $trimmed)
        }
        catch {
            Write-Host "Invalid VM action selection. Please enter a valid number or action name." -ForegroundColor Yellow
        }
    }
}

# Handles Wait-ClagnosDoLifecycleState.
function Wait-ClagnosDoLifecycleState {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$DesiredState,
        [int]$MaxAttempts = 18,
        [int]$DelaySeconds = 10
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($MaxAttempts -gt 120) { $MaxAttempts = 120 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $snapshot = Get-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName
        $powerText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$snapshot.PowerStateDisplay) -CodeText ([string]$snapshot.PowerStateCode)
        $hibernationText = Resolve-ClagnosVmLifecycleFieldText -DisplayText ([string]$snapshot.HibernationStateDisplay) -CodeText ([string]$snapshot.HibernationStateCode)
        Write-ClagnosActionProgress -Action ("verify VM lifecycle state: {0}; power: {1}; hibernation: {2} (attempt {3}/{4})" -f [string]$snapshot.NormalizedState, $powerText, $hibernationText, $attempt, $MaxAttempts)

        if ([string]::Equals([string]$snapshot.NormalizedState, [string]$DesiredState, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $snapshot
        }

        Write-ClagnosActionProgress -Action ("wait {0}s for VM lifecycle state '{1}'" -f $DelaySeconds,$DesiredState)
        Start-Sleep -Seconds $DelaySeconds
    }

    return $null
}

# Handles Invoke-ClagnosDoAzureAction.
function Invoke-ClagnosDoAzureAction {
    param(
        [string]$ActionName,
        [string]$ResourceGroup,
        [string]$VmName,
        [string[]]$AzArguments,
        [string]$AzContext
    )

    try {
        Invoke-TrackedAction -Label ("az " + (@($AzArguments) -join ' ')) -Action {
            az @AzArguments
            Assert-LastExitCode $AzContext
        } | Out-Null
    }
    catch {
        Throw-FriendlyError `
            -Detail ("Azure CLI rejected VM action '{0}' for VM '{1}' in resource group '{2}': {3}" -f $ActionName, $VmName, $ResourceGroup, $_.Exception.Message) `
            -Code 66 `
            -Summary ("VM action '{0}' failed." -f $ActionName) `
            -Hint "Review the Azure CLI error text above, correct the blocking condition, then retry."
    }
}

