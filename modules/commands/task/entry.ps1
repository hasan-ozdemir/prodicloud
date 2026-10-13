# Task command entry.

function Assert-ClagnosTaskAppStatePluginReadyOrThrow {
    param(
        [psobject]$TaskBlock,
        [string]$Stage
    )

    $pluginInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $TaskBlock
    if ($pluginInfo.Status -eq 'missing-plugin') {
        $saveHint = if ($null -ne $TaskBlock.PackageSpec) { "Save package state first with 'clagnos task --save-app-state --package=$($TaskBlock.PackageSpec.Id) --package-catalog=$($TaskBlock.PackageSpec.Catalog)'." } else { ("Save state first with 'clagnos task --save-app-state --vm-{0}-task={1}'." -f [string]$Stage, [string]$TaskBlock.TaskNumber) }
        Throw-FriendlyError `
            -Detail ("App-state plugin folder was not found for task '{0}'." -f [string]$TaskBlock.Name) `
            -Code 61 `
            -Summary "Task app-state restore input is missing." `
            -Hint $saveHint
    }
    if ($pluginInfo.Status -eq 'missing-zip') {
        $saveHint = if ($null -ne $TaskBlock.PackageSpec) { "Save package state first with 'clagnos task --save-app-state --package=$($TaskBlock.PackageSpec.Id) --package-catalog=$($TaskBlock.PackageSpec.Catalog)'." } else { ("Save state first with 'clagnos task --save-app-state --vm-{0}-task={1}'." -f [string]$Stage, [string]$TaskBlock.TaskNumber) }
        Throw-FriendlyError `
            -Detail ("app-state.zip was not found for task '{0}'." -f [string]$TaskBlock.Name) `
            -Code 61 `
            -Summary "Task app-state restore input is missing." `
            -Hint $saveHint
    }
    if ($pluginInfo.Status -eq 'invalid') {
        Throw-FriendlyError `
            -Detail ("Task app-state payload for '{0}' is invalid: {1}" -f [string]$TaskBlock.Name, [string]$pluginInfo.Message) `
            -Code 61 `
            -Summary "Task app-state restore input is invalid." `
            -Hint "Fix or re-save the task app-state payload, then retry the restore."
    }

    return $pluginInfo
}

function New-ClagnosTaskAppStateFilteredTaskBlock {
    param(
        [psobject]$TaskBlock,
        [string[]]$SelectedProfiles = @()
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-task-app-state-filter-{0}' -f ([guid]::NewGuid().ToString('N')))
    $tempTaskRoot = Join-Path $tempRoot (Get-ClagnosTaskAppStateIdentity -TaskBlock $TaskBlock)
    $tempAppStateRoot = Join-Path $tempTaskRoot 'app-state'
    Ensure-ClagnosAppStatePluginDirectory -Path $tempAppStateRoot

    $sourceZipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $TaskBlock
    $filteredZipPath = Join-Path $tempAppStateRoot 'app-state.zip'
    [void](New-ClagnosTaskAppStateFilteredZip -SourceZipPath $sourceZipPath -TaskName (Get-ClagnosTaskAppStateIdentity -TaskBlock $TaskBlock) -SelectedProfiles $SelectedProfiles -DestinationZipPath $filteredZipPath)

    $clone = [pscustomobject]@{}
    foreach ($property in @($TaskBlock.PSObject.Properties)) {
        $clone | Add-Member -NotePropertyName ([string]$property.Name) -NotePropertyValue $property.Value -Force
    }
    $clone | Add-Member -NotePropertyName 'TaskRootPath' -NotePropertyValue ([string]$tempTaskRoot) -Force
    $clone | Add-Member -NotePropertyName 'DirectoryPath' -NotePropertyValue ([string]$tempTaskRoot) -Force

    return [pscustomobject]@{
        TaskBlock = $clone
        TempRoot = [string]$tempRoot
    }
}

# Handles Invoke-ClagnosTaskCommand.
function Invoke-ClagnosTaskCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $mode = Resolve-ClagnosTaskCommandMode -Options $Options
    Assert-ClagnosTaskCommandOptionScope -Mode $mode -Options $Options
    if ([string]::Equals($mode, 'history', [System.StringComparison]::OrdinalIgnoreCase)) {
        $historyRecords = @(Show-ClagnosTaskRunHistory -Limit 25)
        return [pscustomobject]@{
            Mode = 'history'
            Records = @($historyRecords)
        }
    }

    if ([string]::Equals($mode, 'list', [System.StringComparison]::OrdinalIgnoreCase)) {
        $runtime = Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
        $includeInit = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-init'
        $includeUpdate = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-update'
        if (-not $includeInit -and -not $includeUpdate) {
            $includeInit = $true
            $includeUpdate = $true
        }

        $disabledOnly = Test-ClagnosCliOptionPresent -Options $Options -Name 'disabled'
        $rows = @()

        if ($includeInit) {
            $initCatalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$runtime.VmInitTaskDir) -Platform ([string]$runtime.Platform) -Stage 'init' -SuppressSkipMessages
            $rows += @(Get-ClagnosTaskListRows -Stage 'init' -InventoryTasks @($initCatalog.InventoryTasks) -DisabledOnly:$disabledOnly)
        }
        if ($includeUpdate) {
            $updateCatalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$runtime.VmUpdateTaskDir) -Platform ([string]$runtime.Platform) -Stage 'update' -SuppressSkipMessages
            $rows += @(Get-ClagnosTaskListRows -Stage 'update' -InventoryTasks @($updateCatalog.InventoryTasks) -DisabledOnly:$disabledOnly)
        }

        $rows = @(
            $rows | Sort-Object `
                @{ Expression = { if ([string]::Equals([string]$_.Stage, 'vm-init', [System.StringComparison]::OrdinalIgnoreCase)) { 1 } else { 2 } } }, `
                @{ Expression = { [int]$_.Priority } }, `
                @{ Expression = { [int]$_.Number } }, `
                @{ Expression = { [string]$_.Name } }
        )

        $statusLabel = if ($disabledOnly) { 'disabled' } else { 'active' }
        Write-Host ("Discovered {0} {1} tasks for platform '{2}':" -f $statusLabel, ($(if ($includeInit -and $includeUpdate) { 'init/update' } elseif ($includeInit) { 'init' } else { 'update' })), [string]$runtime.Platform) -ForegroundColor Cyan
        if (@($rows).Count -eq 0) {
            Write-Host "- (none)"
            return [pscustomobject]@{
                Platform = [string]$runtime.Platform
                Rows = @()
                DisabledOnly = [bool]$disabledOnly
            }
        }

        @($rows) |
            Select-Object Stage, Number, Source, TaskType, Priority, TimeoutSeconds, Status, DisabledReason, Name, RelativePath |
            Format-Table -AutoSize |
            Out-Host

        return [pscustomobject]@{
            Platform = [string]$runtime.Platform
            Rows = @($rows)
            DisabledOnly = [bool]$disabledOnly
        }
    }

    if ([string]::Equals($mode, 'enable', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($mode, 'disable', [System.StringComparison]::OrdinalIgnoreCase)) {
        $runtime = Initialize-ClagnosTaskCommandRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
        $taskSelection = Resolve-ClagnosTaskStageSelection -Options $Options -AutoMode:$AutoMode
        $stageRoot = if ([string]::Equals([string]$taskSelection.Stage, 'init', [System.StringComparison]::OrdinalIgnoreCase)) {
            [string]$runtime.VmInitTaskDir
        }
        else {
            [string]$runtime.VmUpdateTaskDir
        }
        $toggleResult = Invoke-ClagnosTaskAvailabilityToggle `
            -StageRoot $stageRoot `
            -Platform ([string]$runtime.Platform) `
            -Stage ([string]$taskSelection.Stage) `
            -TaskNumberOrName ([string]$taskSelection.Requested) `
            -Action $mode
        return [pscustomobject]@{
            Mode = [string]$mode
            Platform = [string]$runtime.Platform
            Stage = [string]$taskSelection.Stage
            Task = $toggleResult.Task
            Enabled = [bool]$toggleResult.Enabled
            Changed = [bool]$toggleResult.Changed
        }
    }

    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
    if ([string]::Equals($mode, 'run-vm-init', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($mode, 'run-vm-update', [System.StringComparison]::OrdinalIgnoreCase)) {
        $runSelection = Resolve-ClagnosTaskRunSelection -Options $Options
        $runResult = Invoke-ClagnosTaskExecutionWithTarget `
            -Runtime $runtime `
            -Options $Options `
            -OperationName 'task' `
            -Stage ([string]$runSelection.Stage) `
            -Requested ([string]$runSelection.Requested) `
            -AutoMode:$AutoMode
        Write-Host ("Task completed: {0} task '{1}'." -f [string]$runResult.Stage, [string]$runResult.Task.Name) -ForegroundColor Green
        return [pscustomobject]@{
            Mode = 'run'
            Stage = [string]$runResult.Stage
            Task = $runResult.Task
            Result = $runResult.Result
        }
    }

    $context = $runtime.Context
    $platform = [string]$runtime.Platform
    $appStateSurface = Resolve-ClagnosTaskAppStateSurface -Mode $mode -Options $Options
    $requestedUsers = @(Get-ClagnosTaskAppStateRequestedUsersFromOptions -Options $Options)
    $taskSelection = Resolve-ClagnosTaskBlockForMaintenance -Runtime $runtime -Options $Options -AutoMode:$AutoMode
    $taskBlock = $taskSelection.TaskBlock
    $taskTimeoutSeconds = Get-ClagnosTaskTimeoutSeconds -TaskBlock $taskBlock -DefaultTimeoutSeconds ([int]$runtime.SshTaskTimeoutSeconds)
    $appStateTimeoutSeconds = [Math]::Max([int]$taskTimeoutSeconds, 900)

    if ([string]::Equals([string]$appStateSurface.Surface, 'lm', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::Equals($mode, 'save-app-state', [System.StringComparison]::OrdinalIgnoreCase)) {
            $saveResult = Save-ClagnosTaskAppStateFromLocalMachine -TaskBlock $taskBlock -RequestedUsers $requestedUsers
            Write-Host ("Task completed: save app-state for '{0}'." -f [string]$taskBlock.Name) -ForegroundColor Green
            return [pscustomobject]@{
                Mode = 'save-app-state'
                Surface = 'lm'
                Stage = [string]$taskSelection.Stage
                Task = $taskBlock
                Result = $saveResult
            }
        }

        [void](Assert-ClagnosTaskAppStatePluginReadyOrThrow -TaskBlock $taskBlock -Stage ([string]$taskSelection.Stage))
        $restoreResult = Restore-ClagnosTaskAppStateToLocalMachine -TaskBlock $taskBlock -RequestedUsers $requestedUsers
        Write-Host ("Task completed: restore app-state for '{0}'." -f [string]$taskBlock.Name) -ForegroundColor Green
        return [pscustomobject]@{
            Mode = 'restore-app-state'
            Surface = 'lm'
            Stage = [string]$taskSelection.Stage
            Task = $taskBlock
            Result = $restoreResult
        }
    }

    $vmProfileSelection = Resolve-ClagnosTaskVmAppStateSelectedProfiles -Runtime $runtime -RequestedUsers $requestedUsers
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'task'
    $context.ResourceGroup = [string]$target.ResourceGroup
    $context.VmName = [string]$target.VmName

    $vmRuntimeDetails = Get-ClagnosVmDetails -Context $context
    $sshHost = [string]$vmRuntimeDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
        $sshHost = [string]$vmRuntimeDetails.PublicIP
    }
    if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
        throw "Task command could not resolve VM SSH host (FQDN/Public IP)."
    }

    $pySsh = Ensure-ClagnosPySshTools -RepoRoot (Get-ClagnosRepoRoot) -ConfiguredPySshClientPath ([string]$runtime.ConfiguredPySshClientPath)
    $bootstrap = Initialize-ClagnosSshHostKey `
        -PySshPythonPath ([string]$pySsh.PythonPath) `
        -PySshClientPath ([string]$pySsh.ClientPath) `
        -HostName $sshHost `
        -UserName ([string]$context.VmUser) `
        -Password ([string]$context.VmPass) `
        -Port ([string]$context.SshPort) `
        -ConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds)
    if (-not [string]::IsNullOrWhiteSpace([string]$bootstrap.Output)) {
        Write-Host ([string]$bootstrap.Output)
    }

    $shell = if ($platform -eq 'linux') { 'bash' } else { 'powershell' }
    $session = $null
    $filteredTaskScope = $null
    $effectiveTaskBlock = $taskBlock
    try {
        if ([string]::Equals($mode, 'restore-app-state', [System.StringComparison]::OrdinalIgnoreCase) -and -not [bool]$vmProfileSelection.IsAll) {
            [void](Assert-ClagnosTaskAppStatePluginReadyOrThrow -TaskBlock $taskBlock -Stage ([string]$taskSelection.Stage))
            $filteredTaskScope = New-ClagnosTaskAppStateFilteredTaskBlock -TaskBlock $taskBlock -SelectedProfiles @($vmProfileSelection.SelectedProfiles)
            $effectiveTaskBlock = $filteredTaskScope.TaskBlock
        }

        if ($platform -eq 'linux') {
            try {
                $session = Start-ClagnosPersistentSshSession `
                    -PySshPythonPath ([string]$pySsh.PythonPath) `
                    -PySshClientPath ([string]$pySsh.ClientPath) `
                    -HostName $sshHost `
                    -UserName ([string]$context.VmUser) `
                    -Password ([string]$context.VmPass) `
                    -Port ([string]$context.SshPort) `
                    -Shell $shell `
                    -ConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds) `
                    -DefaultTaskTimeoutSeconds ([int]$taskTimeoutSeconds)
            }
            catch {
                $session = $null
                Write-Warning ("Persistent SSH session bootstrap failed for task app-state maintenance. Switching to one-shot transport: {0}" -f $_.Exception.Message)
            }
        }

        if ([string]::Equals($mode, 'save-app-state', [System.StringComparison]::OrdinalIgnoreCase)) {
            $saveResult = Save-ClagnosTaskAppStateFromVm `
                -Platform $platform `
                -RepoRoot (Get-ClagnosRepoRoot) `
                -TaskBlock $taskBlock `
                -Session $session `
                -PySshPythonPath ([string]$pySsh.PythonPath) `
                -PySshClientPath ([string]$pySsh.ClientPath) `
                -HostName $sshHost `
                -UserName ([string]$context.VmUser) `
                -Password ([string]$context.VmPass) `
                -Port ([string]$context.SshPort) `
                -ConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds) `
                -TimeoutSeconds ([int]$appStateTimeoutSeconds) `
                -ManagerUser ([string]$context.VmUser) `
                -AssistantUser ([string]$context.VmAssistantUser)
            if (-not [bool]$vmProfileSelection.IsAll) {
                $savedZipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $taskBlock
                if (Test-Path -LiteralPath $savedZipPath) {
                    $tempFilteredZipPath = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-task-app-state-save-filter-{0}.zip' -f ([guid]::NewGuid().ToString('N')))
                    try {
                        [void](New-ClagnosTaskAppStateFilteredZip -SourceZipPath $savedZipPath -TaskName (Get-ClagnosTaskAppStateIdentity -TaskBlock $taskBlock) -SelectedProfiles @($vmProfileSelection.SelectedProfiles) -DestinationZipPath $tempFilteredZipPath)
                        Copy-Item -LiteralPath $tempFilteredZipPath -Destination $savedZipPath -Force
                    }
                    finally {
                        Remove-Item -LiteralPath $tempFilteredZipPath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            Write-Host ("Task completed: save app-state for '{0}'." -f [string]$taskBlock.Name) -ForegroundColor Green
            return [pscustomobject]@{
                Mode = 'save-app-state'
                Surface = 'vm'
                Stage = [string]$taskSelection.Stage
                Task = $taskBlock
                Result = $saveResult
            }
        }

        [void](Assert-ClagnosTaskAppStatePluginReadyOrThrow -TaskBlock $effectiveTaskBlock -Stage ([string]$taskSelection.Stage))

        $restoreResult = Invoke-ClagnosTaskAppStatePostProcess `
            -Platform $platform `
            -RepoRoot (Get-ClagnosRepoRoot) `
            -TaskBlock $effectiveTaskBlock `
            -Session $session `
            -PySshPythonPath ([string]$pySsh.PythonPath) `
            -PySshClientPath ([string]$pySsh.ClientPath) `
            -HostName $sshHost `
            -UserName ([string]$context.VmUser) `
            -Password ([string]$context.VmPass) `
            -Port ([string]$context.SshPort) `
            -ConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds) `
            -TimeoutSeconds ([int]$appStateTimeoutSeconds) `
            -ManagerUser ([string]$context.VmUser) `
            -AssistantUser ([string]$context.VmAssistantUser)
        Write-Host ("Task completed: restore app-state for '{0}'." -f [string]$taskBlock.Name) -ForegroundColor Green
        return [pscustomobject]@{
            Mode = 'restore-app-state'
            Surface = 'vm'
            Stage = [string]$taskSelection.Stage
            Task = $taskBlock
            Result = $restoreResult
        }
    }
    finally {
        if ($null -ne $session) {
            Stop-ClagnosPersistentSshSession -Session $session
        }
        if ($null -ne $filteredTaskScope -and $filteredTaskScope.PSObject.Properties.Match('TempRoot').Count -gt 0) {
            Remove-Item -LiteralPath ([string]$filteredTaskScope.TempRoot) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
