# Create/update main pipeline review and barrier helpers.

function Write-ClagnosMainBanner {
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

    Write-Host "clagnos" -ForegroundColor Cyan
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

function Get-ClagnosReviewTaskRows {
    param(
        [string]$DirectoryPath,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [hashtable]$Context
    )

    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $DirectoryPath -Platform $Platform -Stage $Stage
    $activeTemplates = @($catalog.ActiveTasks)
    $disabledTasks = @($catalog.DisabledTasks)
    $resolved = if (@($activeTemplates).Count -gt 0) {
        @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks $activeTemplates -Context $Context)
    }
    else {
        @()
    }

    return [pscustomobject]@{
        ActiveTasks = @($resolved)
        DisabledTasks = @($disabledTasks)
    }
}

function Show-ClagnosTaskReviewRows {
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
        Write-Host ("- #{0} | {1} | priority={2} | timeout={3}s" -f [string]$task.TaskNumber, [string]$task.Name, $priority, $timeout)
    }
}

function Show-ClagnosStepReview {
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
            $observed = Register-ClagnosValueObservation -Key $normalizedKey -Value $Values[$key]
            if (-not [bool]$observed.ShouldPrint) {
                continue
            }

            $distinctValues[$normalizedKey] = [string]$observed.DisplayValue
        }

        if ($distinctValues.Count -gt 0) {
            Show-ClagnosKeyValueList -Title 'Planned values:' -Values $distinctValues
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$TaskTitle)) {
        Show-ClagnosTaskReviewRows -Title $TaskTitle -TaskBlocks $TaskBlocks
    }
}

function Stop-ClagnosWorkflowCancelled {
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

function Invoke-ClagnosReviewCheckpoint {
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
            Show-ClagnosStepReview -Title $StageName -Values @{} -TaskTitle $TaskTitle -TaskBlocks $TaskBlocks
        }
        Write-Host ("Auto mode: continuing with {0}." -f [string]$StageName) -ForegroundColor Cyan
        return 'yes'
    }

    Show-ClagnosStepReview -Title $StageName -Values $Values -TaskTitle $TaskTitle -TaskBlocks $TaskBlocks
    return (Confirm-YesNoCancel -PromptText ("Continue with {0}?" -f [string]$StageName) -DefaultChoice 'yes')
}

function Invoke-ClagnosPersistPendingSelections {
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

    Save-ClagnosStep1ContextPersistenceMap -EnvFilePath $EnvFilePath -PersistMap $pendingMap
    $Context['PendingEnvUpdates'] = [ordered]@{}
    Write-Host "Saved VC settings to the selected <vm-name>.env profile and global settings to clagnos.env." -ForegroundColor Green
}

function Get-ClagnosWorkflowSummaryReadbackScriptPath {
    param(
        [string]$RepoRoot,
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Join-Path $RepoRoot 'tools\scripts\clagnos-summary-readback-linux.sh')
    }

    return (Join-Path $RepoRoot 'tools\scripts\clagnos-summary-readback-windows.ps1')
}

function New-ClagnosWorkflowSummaryReadbackTaskBlock {
    param(
        [string]$RepoRoot,
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    $scriptPath = Get-ClagnosWorkflowSummaryReadbackScriptPath -RepoRoot $RepoRoot -Platform $Platform
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw ("VM summary readback script was not found: {0}" -f $scriptPath)
    }

    $assetSpecs = @()
    if ([string]::Equals([string]$Platform, 'windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        $assetSpecs = @(
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'modules\core\tasks\clagnos-session-environment.psm1')
                RemotePath = 'C:/Windows/Temp/clagnos-session-environment.psm1'
            },
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'modules\core\tasks\clagnos-store-install-state.psm1')
                RemotePath = 'C:/Windows/Temp/clagnos-store-install-state.psm1'
            },
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'modules\core\tasks\clagnos-shortcut-launcher.psm1')
                RemotePath = 'C:/Windows/Temp/clagnos-shortcut-launcher.psm1'
            },
            [pscustomobject]@{
                LocalPath = (Join-Path $RepoRoot 'tools\scripts\clagnos-interactive-session-helper.ps1')
                RemotePath = 'C:/Windows/Temp/clagnos-interactive-session-helper.ps1'
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

function Invoke-ClagnosWorkflowSummaryReadback {
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
        $vmRuntimeDetails = Get-ClagnosVmDetails -Context $Context
        $sshHost = [string]$vmRuntimeDetails.VmFqdn
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            $sshHost = [string]$vmRuntimeDetails.PublicIP
        }
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            Write-Warning 'VM summary readback could not resolve an SSH host. Continuing with connection details only.'
            return
        }

        $pySsh = Ensure-ClagnosPySshTools -RepoRoot $RepoRoot -ConfiguredPySshClientPath $ConfiguredPySshClientPath
        $resolvedTask = @(
            Resolve-ClagnosRuntimeTaskBlocks `
                -TemplateTaskBlocks @((New-ClagnosWorkflowSummaryReadbackTaskBlock -RepoRoot $RepoRoot -Platform $Platform)) `
                -Context $Context
        ) | Select-Object -First 1

        $null = Initialize-ClagnosSshHostKey `
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
            Copy-ClagnosAssetToVm `
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
        $result = Invoke-ClagnosOneShotSshTask `
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
