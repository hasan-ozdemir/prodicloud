# Create/update main pipeline review and barrier helpers.

function Write-ProdicloudMainBanner {
    param(
        [string]$CommandName,
        [string]$Mode,
        [string]$Platform,
        [psobject]$ActionPlan,
        [string]$LogPath,
        [string]$SubscriptionName = '',
        [string]$SubscriptionId = ''
    )

    $stepWindow = 'full'
    if ($null -ne $ActionPlan -and [string]$ActionPlan.Mode -ne 'full') {
        if ([string]::Equals([string]$ActionPlan.Mode, 'single', [System.StringComparison]::OrdinalIgnoreCase)) {
            $stepWindow = [string]$ActionPlan.Target
        }
        else {
            $stepWindow = ("{0}->{1}" -f [string]$ActionPlan.Start, [string]$ActionPlan.Target)
        }
    }

    Write-Host "prodicloud" -ForegroundColor Cyan
    Write-Host ("- command: {0}" -f [string]$CommandName)
    Write-Host ("- mode: {0}" -f [string]$Mode)
    Write-Host ("- platform: {0}" -f [string]$Platform)
    if (-not [string]::IsNullOrWhiteSpace([string]$SubscriptionId)) {
        $subscriptionDisplay = if ([string]::IsNullOrWhiteSpace([string]$SubscriptionName)) { [string]$SubscriptionId } else { ("{0} ({1})" -f [string]$SubscriptionName, [string]$SubscriptionId) }
        Write-Host ("- subscription: {0}" -f $subscriptionDisplay)
    }
    Write-Host ("- steps: {0}" -f [string]$stepWindow)
    Write-Host ("- transcript: {0}" -f [System.IO.Path]::GetFileName([string]$LogPath))
}

function Get-ProdicloudReviewTaskRows {
    param(
        [string]$DirectoryPath,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [hashtable]$Context
    )

    $catalog = Get-ProdicloudTaskBlocksFromDirectory -DirectoryPath $DirectoryPath -Platform $Platform -Stage $Stage
    $activeTemplates = @($catalog.ActiveTasks)
    $disabledTasks = @($catalog.DisabledTasks)

    $selectionKey = if ($Stage -eq 'init') { 'VM_INIT_TASKS' } else { 'VM_UPDATE_TASKS' }
    $selectionText = ''
    if ($Context -and $Context.ContainsKey('ConfigMap') -and $Context['ConfigMap'].ContainsKey($selectionKey)) {
        $selectionText = [string]$Context['ConfigMap'][$selectionKey]
    }
    $selectedTemplates = @(Select-ProdicloudConfiguredTaskBlocks -ActiveTasks $activeTemplates -InventoryTasks @($catalog.InventoryTasks) -SelectionText $selectionText -Stage $Stage)
    $resolved = if ($selectedTemplates.Count -gt 0) {
        @(Resolve-ProdicloudRuntimeTaskBlocks -TemplateTaskBlocks $selectedTemplates -Context $Context)
    }
    else { @() }

    return [pscustomobject]@{
        ActiveTasks = @($resolved)
        DisabledTasks = @($disabledTasks)
    }
}

function Invoke-ProdicloudTaskBlocksByDeclaredTransport {
    param(
        [psobject]$Runtime,
        [string]$HostName,
        [object[]]$TaskBlocks,
        [ValidateSet('continue','strict')][string]$TaskOutcomeMode,
        [int]$SshMaxRetries = 1
    )

    $allResults = New-Object 'System.Collections.Generic.List[object]'
    $cursor = 0
    while ($cursor -lt @($TaskBlocks).Count) {
        $task = $TaskBlocks[$cursor]
        $transport = if ($task.PSObject.Properties.Match('Transport').Count -gt 0) { [string]$task.Transport } else { 'ssh' }
        if ([string]::IsNullOrWhiteSpace($transport)) { $transport = 'ssh' }
        $transport = $transport.ToLowerInvariant()
        if ($transport -notin @('ssh','winrm')) { throw ("Task '{0}' declares unsupported transport '{1}'." -f [string]$task.Name,$transport) }
        if ($transport -eq 'winrm' -and [string]$Runtime.Platform -ne 'windows') { throw ("Task '{0}' requires WinRM, which is available only for Windows guests." -f [string]$task.Name) }
        $end = $cursor + 1
        while ($end -lt @($TaskBlocks).Count) {
            $nextTransport = if ($TaskBlocks[$end].PSObject.Properties.Match('Transport').Count -gt 0) { [string]$TaskBlocks[$end].Transport } else { 'ssh' }
            if ([string]::IsNullOrWhiteSpace($nextTransport)) { $nextTransport = 'ssh' }
            if (-not [string]::Equals($transport,$nextTransport,[System.StringComparison]::OrdinalIgnoreCase)) { break }
            $end++
        }
        $segment = @($TaskBlocks[$cursor..($end - 1)])
        if ($transport -eq 'winrm') {
            if ($Runtime.Context -is [System.Collections.IDictionary] -and -not $Runtime.Context.Contains('PowerShellPort')) { $Runtime.Context['PowerShellPort'] = Get-ProdicloudDefaultPowerShellPortText }
            foreach ($winRmTask in @($segment)) {
                $target = [pscustomobject]@{ VmName=[string]$Runtime.Context.VmName; ResourceGroup=[string]$Runtime.Context.ResourceGroup }
                $options = @{ group=[string]$target.ResourceGroup; 'vm-name'=[string]$target.VmName }
                if (-not [string]::IsNullOrWhiteSpace([string]$Runtime.Context.AzureSubscriptionId)) { $options['subscription-id'] = [string]$Runtime.Context.AzureSubscriptionId }
                $winRmExecution = Invoke-ProdicloudWinRmTaskBlocksWithGuestRestart -Runtime $Runtime -HostName $HostName -Target $target -TaskBlocks @($winRmTask) -TaskOutcomeMode $TaskOutcomeMode -Options $options -AutoMode:$true -WindowsFlag
                $Runtime = $winRmExecution.Runtime
                $HostName = [string]$winRmExecution.HostName
                $allResults.Add($winRmExecution.Result) | Out-Null
            }
        }
        else {
            $result = Invoke-ProdicloudSshTaskBlocks `
                -Platform ([string]$Runtime.Platform) `
                -RepoRoot ([string]$Runtime.RepoRoot) `
                -SshHost $HostName `
                -SshUser ([string]$Runtime.Context.VmUser) `
                -SshPassword ([string]$Runtime.Context.VmPass) `
                -SshPort ([string]$Runtime.Context.SshPort) `
                -AssistantUser ([string]$Runtime.Context.VmAssistantUser) `
                -ResourceGroup ([string]$Runtime.Context.ResourceGroup) `
                -VmName ([string]$Runtime.Context.VmName) `
                -TaskBlocks $segment `
                -TaskOutcomeMode $TaskOutcomeMode `
                -SshMaxRetries $SshMaxRetries `
                -SshTaskTimeoutSeconds ([int]$Runtime.SshTaskTimeoutSeconds) `
                -SshConnectTimeoutSeconds ([int]$Runtime.SshConnectTimeoutSeconds) `
                -ConfiguredPySshClientPath ([string]$Runtime.ConfiguredPySshClientPath)
            $allResults.Add($result) | Out-Null
        }
        $cursor = $end
    }

    $propertyNames = @('SuccessCount','FailedCount','WarningCount','SignalWarningCount','ErrorCount','RebootCount','FinalRestartCount')
    $summary = [ordered]@{}
    foreach ($propertyName in $propertyNames) {
        $summary[$propertyName] = [int](@($allResults | ForEach-Object { if ($_.PSObject.Properties.Match($propertyName).Count -gt 0) { [int]$_.$propertyName } else { 0 } } | Measure-Object -Sum).Sum)
    }
    foreach ($propertyName in @('SuccessTasks','FailedTasks','WarningTasks','SignalWarningTasks','RebootRequestedTasks')) {
        $summary[$propertyName] = @($allResults | ForEach-Object { if ($_.PSObject.Properties.Match($propertyName).Count -gt 0) { @($_.$propertyName) } })
    }
    $summary['TaskOutputs'] = @($allResults | ForEach-Object { if ($_.PSObject.Properties.Match('TaskOutputs').Count -gt 0) { @($_.TaskOutputs) } })
    $summary['RebootRequired'] = @($allResults | Where-Object { $_.PSObject.Properties.Match('RebootRequired').Count -gt 0 -and [bool]$_.RebootRequired }).Count -gt 0
    return [pscustomobject]$summary
}

function Show-ProdicloudTaskReviewRows {
    param(
        [string]$Title,
        [object[]]$TaskBlocks
    )

    Write-Host $Title -ForegroundColor Cyan
    if (@($TaskBlocks).Count -eq 0) {
        Write-Host "- (no active tasks)"
        return
    }

    foreach ($task in @($TaskBlocks)) {
        $priority = if ($task.PSObject.Properties.Match('Priority').Count -gt 0) { [int]$task.Priority } else { 1000 }
        $timeout = if ($task.PSObject.Properties.Match('TimeoutSeconds').Count -gt 0) { [int]$task.TimeoutSeconds } else { 180 }
        $transport = if ($task.PSObject.Properties.Match('Transport').Count -gt 0) { [string]$task.Transport } else { 'ssh' }
        Write-Host ("- #{0} | {1} | priority={2} | timeout={3}s | transport={4}" -f [string]$task.TaskNumber, [string]$task.Name, $priority, $timeout, $transport)
    }
}

function Show-ProdicloudStepReview {
    param(
        [string]$Title,
        [System.Collections.IDictionary]$Values,
        [string]$TaskTitle,
        [object[]]$TaskBlocks
    )

    Write-Host ""
    Write-Host $Title -ForegroundColor DarkCyan
    if ($Values -and $Values.Count -gt 0) {
        $distinctValues = [ordered]@{}
        foreach ($key in @($Values.Keys)) {
            $normalizedKey = [string]$key
            $observed = Register-ProdicloudValueObservation -Key $normalizedKey -Value $Values[$key]
            if (-not [bool]$observed.ShouldPrint) {
                continue
            }

            $distinctValues[$normalizedKey] = [string]$observed.DisplayValue
        }

        if ($distinctValues.Count -gt 0) {
            Show-ProdicloudKeyValueList -Title 'Planned values:' -Values $distinctValues
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$TaskTitle)) {
        Show-ProdicloudTaskReviewRows -Title $TaskTitle -TaskBlocks $TaskBlocks
    }
}

function Stop-ProdicloudWorkflowCancelled {
    param(
        [string]$StageName,
        [string[]]$CompletedStages,
        [string[]]$SkippedStages
    )

    Write-Host ""
    Write-Host "Workflow cancelled by user." -ForegroundColor Yellow
    Write-Host ("Cancelled at: {0}" -f [string]$StageName)
    Write-Host ("Completed stages: {0}" -f (if (@($CompletedStages).Count -gt 0) { @($CompletedStages) -join ', ' } else { '(none)' }))
    Write-Host ("Skipped stages: {0}" -f (if (@($SkippedStages).Count -gt 0) { @($SkippedStages) -join ', ' } else { '(none)' }))

    Throw-FriendlyError `
        -Detail ("Workflow was cancelled before stage '{0}' executed." -f [string]$StageName) `
        -Code 0 `
        -Summary "Operation cancelled by user." `
        -Hint "Rerun the command when you want to continue from a review checkpoint."
}

function Invoke-ProdicloudReviewCheckpoint {
    param(
        [switch]$AutoMode,
        [string]$StageName,
        [System.Collections.IDictionary]$Values,
        [string]$TaskTitle,
        [object[]]$TaskBlocks,
        [string[]]$CompletedStages,
        [string[]]$SkippedStages
    )

    if ($AutoMode) {
        if ($TaskBlocks) {
            Show-ProdicloudStepReview -Title $StageName -Values @{} -TaskTitle $TaskTitle -TaskBlocks $TaskBlocks
        }
        Write-Host ("Auto mode: continuing with {0}." -f [string]$StageName) -ForegroundColor Cyan
        return 'yes'
    }

    Show-ProdicloudStepReview -Title $StageName -Values $Values -TaskTitle $TaskTitle -TaskBlocks $TaskBlocks
    return (Confirm-YesNoCancel -PromptText ("Continue with {0}?" -f [string]$StageName) -DefaultChoice 'yes')
}

function Invoke-ProdicloudPersistPendingSelections {
    param(
        [hashtable]$Context,
        [string]$EnvFilePath
    )

    if ($null -eq $Context) {
        return
    }

    $pendingMap = $null
    if ($Context.ContainsKey('PendingEnvUpdates')) {
        $pendingMap = $Context['PendingEnvUpdates']
    }
    if ($null -eq $pendingMap -or @($pendingMap.Keys).Count -eq 0) {
        return
    }

    Save-ProdicloudStep1ContextPersistenceMap -EnvFilePath $EnvFilePath -PersistMap $pendingMap
    $Context['PendingEnvUpdates'] = [ordered]@{}
    Write-Host "Saved VC settings to the selected <vm-name>.env profile and global settings to prodicloud.env." -ForegroundColor Green
}

function Get-ProdicloudWorkflowSummaryReadbackScriptPath {
    param(
        [string]$RepoRoot,
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Join-Path $RepoRoot 'tools\scripts\prodicloud-summary-readback-linux.sh')
    }

    return (Join-Path $RepoRoot 'tools\scripts\prodicloud-summary-readback-windows.ps1')
}

function New-ProdicloudWorkflowSummaryReadbackTaskBlock {
    param(
        [string]$RepoRoot,
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    $scriptPath = Get-ProdicloudWorkflowSummaryReadbackScriptPath -RepoRoot $RepoRoot -Platform $Platform
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw ("VM summary readback script was not found: {0}" -f $scriptPath)
    }

    $assetSpecs = @()
    if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $assetSpecs = @(
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'modules\core\tasks\prodicloud-session-environment.psm1')
                RemotePath = 'C:/Windows/Temp/prodicloud-session-environment.psm1'
            },
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'modules\core\tasks\prodicloud-store-install-state.psm1')
                RemotePath = 'C:/Windows/Temp/prodicloud-store-install-state.psm1'
            },
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'modules\core\tasks\prodicloud-shortcut-launcher.psm1')
                RemotePath = 'C:/Windows/Temp/prodicloud-shortcut-launcher.psm1'
            },
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'tools\scripts\prodicloud-interactive-session-helper.ps1')
                RemotePath = 'C:/Windows/Temp/prodicloud-interactive-session-helper.ps1'
            }
        )
    }

    return [pscustomobject]@{
        Name = 'vm-summary-readback'
        Script = [string](Get-Content -LiteralPath $scriptPath -Raw)
        RelativePath = ''
        DirectoryPath = [string](Split-Path -Path $scriptPath -Parent)
        TaskRootPath = ''
        TaskMetadataPath = ''
        StageRootDirectoryPath = ''
        AssetSpecs = @($assetSpecs)
        TimeoutSeconds = 360
        Priority = 0
        TaskType = 'builtin'
        Source = 'builtin'
        TaskNumber = 0
        AppStateSpec = $null
        DependsOn = @()
        ObservedDurationSeconds = [double]::PositiveInfinity
    }
}

function Invoke-ProdicloudWorkflowSummaryReadback {
    param(
        [hashtable]$Context,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [string]$RepoRoot,
        [string]$ConfiguredPySshClientPath = '',
        [int]$SshConnectTimeoutSeconds = 30
    )

    if ($null -eq $Context) {
        return
    }

    $resourceGroup = [string]$Context.ResourceGroup
    $vmName = [string]$Context.VmName
    if ([string]::IsNullOrWhiteSpace([string]$resourceGroup) -or [string]::IsNullOrWhiteSpace([string]$vmName)) {
        return
    }

    try {
        $vmRuntimeDetails = Get-ProdicloudVmDetails -Context $Context
        $sshHost = [string]$vmRuntimeDetails.VmFqdn
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            $sshHost = [string]$vmRuntimeDetails.PublicIP
        }
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            Write-Warning 'VM summary readback could not resolve an SSH host. Continuing with connection details only.'
            return
        }

        $pySsh = Ensure-ProdicloudPySshTools -RepoRoot $RepoRoot -ConfiguredPySshClientPath $ConfiguredPySshClientPath
        $resolvedTask = @(
            Resolve-ProdicloudRuntimeTaskBlocks `
                -TemplateTaskBlocks @((New-ProdicloudWorkflowSummaryReadbackTaskBlock -RepoRoot $RepoRoot -Platform $Platform)) `
                -Context $Context
        ) | Select-Object -First 1

        $null = Initialize-ProdicloudSshHostKey `
            -PySshPythonPath ([string]$pySsh.PythonPath) `
            -PySshClientPath ([string]$pySsh.ClientPath) `
            -HostName $sshHost `
            -UserName ([string]$Context.VmUser) `
            -Password ([string]$Context.VmPass) `
            -Port ([string]$Context.SshPort) `
            -ConnectTimeoutSeconds $SshConnectTimeoutSeconds

        Write-Host ''
        Write-Host 'VM summary readback' -ForegroundColor DarkCyan

        foreach ($assetCopy in @($resolvedTask.AssetCopies)) {
            Copy-ProdicloudAssetToVm `
                -PySshPythonPath ([string]$pySsh.PythonPath) `
                -PySshClientPath ([string]$pySsh.ClientPath) `
                -HostName $sshHost `
                -UserName ([string]$Context.VmUser) `
                -Password ([string]$Context.VmPass) `
                -Port ([string]$Context.SshPort) `
                -LocalPath ([string]$assetCopy.LocalPath) `
                -RemotePath ([string]$assetCopy.RemotePath) `
                -ConnectTimeoutSeconds $SshConnectTimeoutSeconds | Out-Null
        }

        $shell = if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) { 'bash' } else { 'powershell' }
        $result = Invoke-ProdicloudOneShotSshTask `
            -PySshPythonPath ([string]$pySsh.PythonPath) `
            -PySshClientPath ([string]$pySsh.ClientPath) `
            -HostName $sshHost `
            -UserName ([string]$Context.VmUser) `
            -Password ([string]$Context.VmPass) `
            -Port ([string]$Context.SshPort) `
            -Shell $shell `
            -TaskName 'vm-summary-readback' `
            -TaskScript ([string]$resolvedTask.Script) `
            -TimeoutSeconds ([int]$resolvedTask.TimeoutSeconds)

        if ([int]$result.ExitCode -ne 0) {
            if (-not ([bool]$result.OutputRelayedLive) -and -not [string]::IsNullOrWhiteSpace([string]$result.Output)) {
                Write-Host ([string]$result.Output)
            }
            Write-Warning ("VM summary readback exited with code {0}. Continuing with connection details." -f [int]$result.ExitCode)
        }
    }
    catch {
        Write-Warning ("VM summary readback could not complete: {0}" -f $_.Exception.Message)
    }
}
