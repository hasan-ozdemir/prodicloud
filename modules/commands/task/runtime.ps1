# Task command runtime helpers.

# Handles Get-ClagnosTaskListRows.
function Get-ClagnosTaskListRows {
    param(
        [string]$Stage,
        [object[]]$InventoryTasks,
        [switch]$DisabledOnly
    )

    $rows = @()
    foreach ($task in @($InventoryTasks)) {
        if ($null -eq $task) {
            continue
        }

        $enabled = $true
        if ($task.PSObject.Properties.Match('Enabled').Count -gt 0) {
            $enabled = [bool]$task.Enabled
        }

        if ($DisabledOnly) {
            if ($enabled) {
                continue
            }
        }
        elseif (-not $enabled) {
            continue
        }

        $rows += [pscustomobject]@{
            Stage = ("vm-{0}" -f [string]$Stage)
            Number = [int]$task.TaskNumber
            Source = [string]$task.Source
            TaskType = [string]$task.TaskType
            Priority = [int]$task.Priority
            TimeoutSeconds = [int]$task.TimeoutSeconds
            Status = $(if ($enabled) { 'enabled' } else { 'disabled' })
            DisabledReason = [string]$task.DisabledReason
            Name = [string]$task.Name
            RelativePath = [string]$task.RelativePath
        }
    }

    return @($rows)
}

function Select-ClagnosConfiguredTaskBlocks {
    param(
        [object[]]$ActiveTasks,
        [object[]]$InventoryTasks,
        [string]$SelectionText,
        [ValidateSet('init','update')][string]$Stage
    )

    if ([string]::IsNullOrWhiteSpace([string]$SelectionText)) { return @($ActiveTasks) }
    $tokens = @($SelectionText -split ',' | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($tokens.Count -eq 1 -and [string]::Equals([string]$tokens[0],'all',[System.StringComparison]::OrdinalIgnoreCase)) { return @($ActiveTasks) }
    if ($tokens.Count -eq 1 -and [string]::Equals([string]$tokens[0],'none',[System.StringComparison]::OrdinalIgnoreCase)) { return @() }
    if ($tokens.Count -eq 0) { throw ("VM_{0}_TASKS must be blank, 'all', 'none', or a comma-separated list of task ids/numbers." -f $Stage.ToUpperInvariant()) }

    $selectedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($token in @($tokens)) {
        $match = @($InventoryTasks | Where-Object {
            [string]::Equals([string]$_.Name,[string]$token,[System.StringComparison]::OrdinalIgnoreCase) -or
            ($token -match '^\d+$' -and [int]$_.TaskNumber -eq [int]$token)
        } | Select-Object -First 1)
        if ($match.Count -ne 1) { throw ("VM_{0}_TASKS contains unknown task '{1}'." -f $Stage.ToUpperInvariant(),$token) }
        if (-not [bool]$match[0].Enabled) {
            Write-Host ("Configured task '{0}' remains disabled in tasks.toml and will be skipped." -f [string]$match[0].Name) -ForegroundColor DarkYellow
            continue
        }
        [void]$selectedNames.Add([string]$match[0].Name)
    }
    return @($ActiveTasks | Where-Object { $selectedNames.Contains([string]$_.Name) })
}

# Handles Get-ClagnosTaskRunHistoryPath.
function Get-ClagnosTaskRunHistoryPath {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ClagnosTaskHistoryPathOverride)) {
        return [string]$script:ClagnosTaskHistoryPathOverride
    }

    $repoRoot = Get-ClagnosRepoRoot
    return (Join-Path (Join-Path $repoRoot '.logs') 'task-runs.jsonl')
}

# Handles Write-ClagnosTaskRunHistoryRecord.
function Write-ClagnosTaskRunHistoryRecord {
    param([psobject]$Record)

    $historyPath = Get-ClagnosTaskRunHistoryPath
    $historyDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($historyPath))
    if (-not (Test-Path -LiteralPath $historyDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $historyDirectory -Force | Out-Null
    }

    $jsonLine = ConvertTo-Json -InputObject $Record -Depth 8 -Compress
    [System.IO.File]::AppendAllText($historyPath, ([string]$jsonLine + [Environment]::NewLine), ([System.Text.UTF8Encoding]::new($false)))
}

# Handles Write-ClagnosTaskStageHistoryRecord.
function Write-ClagnosTaskStageHistoryRecord {
    param(
        [string]$Stage,
        [string]$Platform,
        [string]$ResourceGroup,
        [string]$VmName,
        [string[]]$TaskNames = @(),
        [string[]]$FailedTasks = @(),
        [string[]]$WarningTasks = @(),
        [string[]]$DeferredAppStateTasks = @(),
        [int]$SuccessCount = 0,
        [int]$ErrorCount = 0,
        [int]$RebootCount = 0,
        [double]$DurationSeconds = 0
    )

    if ([bool]$script:ClagnosTaskHistoryDisabled) { return }
    $normalizedFailedTasks = @($FailedTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $normalizedWarningTasks = @($WarningTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $normalizedDeferredTasks = @($DeferredAppStateTasks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
    $outcome = if ($normalizedFailedTasks.Count -gt 0 -or $ErrorCount -gt 0) { 'completed-with-failures' } elseif ($normalizedWarningTasks.Count -gt 0) { 'completed-with-warnings' } else { 'completed' }
    $record = [ordered]@{
        SchemaVersion = 1
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
        Operation = 'workflow-stage'
        Stage = [string]$Stage
        Platform = [string]$Platform
        ResourceGroup = [string]$ResourceGroup
        VmName = [string]$VmName
        TaskNumber = 0
        TaskName = ("vm-{0} stage" -f [string]$Stage)
        TaskNames = @($TaskNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        Requested = ''
        Outcome = $outcome
        SuccessCount = [int]$SuccessCount
        FailedCount = [int]$normalizedFailedTasks.Count
        WarningCount = [int]$normalizedWarningTasks.Count
        ErrorCount = [int]$ErrorCount
        RebootCount = [int]$RebootCount
        DeferredAppStateCount = [int]$normalizedDeferredTasks.Count
        DeferredAppStateTasks = @($normalizedDeferredTasks)
        FailedTasks = @($normalizedFailedTasks)
        WarningTasks = @($normalizedWarningTasks)
        DurationSeconds = [Math]::Round([double]$DurationSeconds, 1)
        FailureCategory = ''
        FailureSummary = ''
    }
    try {
        Write-ClagnosTaskRunHistoryRecord -Record $record
    }
    catch {
        Write-Warning ("Local task history could not be saved: {0}" -f [string]$_.Exception.Message)
    }
}

# Handles Get-ClagnosTaskRunHistoryRecords.
function Get-ClagnosTaskRunHistoryRecords {
    param([int]$Limit = 25)

    if ($Limit -lt 1) { $Limit = 1 }
    if ($Limit -gt 200) { $Limit = 200 }
    $historyPath = Get-ClagnosTaskRunHistoryPath
    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        return @()
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in @(Get-Content -LiteralPath $historyPath -Tail $Limit -ErrorAction Stop)) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
        try {
            $record = ConvertFrom-JsonCompat -InputObject ([string]$line)
            if ($null -ne $record) { $records.Add($record) }
        }
        catch {
            Write-Warning 'A malformed local task history row was skipped.'
        }
    }
    return @($records.ToArray())
}

# Handles Show-ClagnosTaskRunHistory.
function Show-ClagnosTaskRunHistory {
    param([int]$Limit = 25)

    $records = @(Get-ClagnosTaskRunHistoryRecords -Limit $Limit)
    Write-Host ("Recent local task runs (last {0}):" -f [Math]::Min([Math]::Max($Limit, 1), 200)) -ForegroundColor Cyan
    if (@($records).Count -eq 0) {
        Write-Host '- No task run history has been recorded on this operator machine.'
        return @()
    }

    foreach ($record in @($records)) {
        $target = if (-not [string]::IsNullOrWhiteSpace([string]$record.ResourceGroup) -or -not [string]::IsNullOrWhiteSpace([string]$record.VmName)) {
            ("{0}/{1}" -f [string]$record.ResourceGroup, [string]$record.VmName)
        }
        else { '(target not resolved)' }
        $taskName = if (-not [string]::IsNullOrWhiteSpace([string]$record.TaskName)) { [string]$record.TaskName } else { [string]$record.Requested }
        Write-Host ("- {0} | {1} | {2} | {3} | {4} | success={5}; failed={6}; warning={7}; error={8}; deferred={9}; duration={10:N1}s" -f [string]$record.CompletedAtUtc, [string]$record.Outcome, [string]$record.Stage, $taskName, $target, [int]$record.SuccessCount, [int]$record.FailedCount, [int]$record.WarningCount, [int]$record.ErrorCount, [int]$record.DeferredAppStateCount, [double]$record.DurationSeconds)
        foreach ($taskNameInStage in @($record.TaskNames)) {
            Write-Host ("  stage task: {0}" -f [string]$taskNameInStage)
        }
        foreach ($failedTaskName in @($record.FailedTasks)) {
            Write-Host ("  failed task: {0}" -f [string]$failedTaskName) -ForegroundColor Red
        }
        foreach ($warningTaskName in @($record.WarningTasks)) {
            Write-Host ("  warning task: {0}" -f [string]$warningTaskName) -ForegroundColor Yellow
        }
        foreach ($deferredTask in @($record.DeferredAppStateTasks)) {
            Write-Host ("  deferred app-state: {0}" -f [string]$deferredTask) -ForegroundColor Yellow
        }
    }
    return @($records)
}

# Handles Resolve-ClagnosTaskSelection.
function Resolve-ClagnosTaskSelection {
    param(
        [object[]]$TaskBlocks,
        [string]$TaskNumberOrName,
        [string]$Stage,
        [switch]$AutoMode
    )

    $allTasks = @($TaskBlocks)
    if ($allTasks.Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("No active {0} tasks were found." -f $Stage) `
            -Code 60 `
            -Summary "Task list is empty." `
            -Hint ("Add files under the '{0}' task directory." -f $Stage)
    }

    $selectedToken = if ($null -eq $TaskNumberOrName) { '' } else { [string]$TaskNumberOrName }
    $selectedToken = $selectedToken.Trim()
    if ([string]::IsNullOrWhiteSpace($selectedToken)) {
        if ($AutoMode) {
            Throw-FriendlyError `
                -Detail ("Option '--run-vm-{0}' requires a value in auto mode." -f $Stage) `
                -Code 60 `
                -Summary "Task selection is required in auto mode." `
                -Hint ("Provide --run-vm-{0} <task-number>." -f $Stage)
        }

        Write-Host ("Available {0} tasks:" -f $Stage) -ForegroundColor Cyan
        for ($i = 0; $i -lt $allTasks.Count; $i++) {
            Write-Host ("{0}. {1}" -f ($i + 1), [string]$allTasks[$i].Name)
        }
        while ($true) {
            $pickRaw = Read-Host ("Enter {0} task number" -f $Stage)
            if ($pickRaw -match '^\d+$') {
                $pickNumber = [int]$pickRaw
                if ($pickNumber -ge 1 -and $pickNumber -le $allTasks.Count) {
                    return $allTasks[$pickNumber - 1]
                }
            }
            Write-Host "Invalid task selection. Please enter a valid number." -ForegroundColor Yellow
        }
    }

    $selectedTask = $null
    if ($selectedToken -match '^\d+$') {
        $requestedTaskNumber = [int]$selectedToken
        $selectedTask = @(
            $allTasks |
                Where-Object {
                    $candidateTaskNumber = -1
                    if ($_.PSObject.Properties.Match('TaskNumber').Count -gt 0 -and $null -ne $_.TaskNumber) {
                        $candidateTaskNumber = [int]$_.TaskNumber
                    }
                    elseif (([string]$_.Name) -match '^(?<n>\d{2,5})-') {
                        $candidateTaskNumber = [int]$Matches.n
                    }

                    $candidateTaskNumber -eq $requestedTaskNumber
                } |
                Select-Object -First 1
        )
    }
    else {
        $selectedTask = @($allTasks | Where-Object { [string]::Equals([string]$_.Name, $selectedToken, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    }

    if ($null -eq $selectedTask -or @($selectedTask).Count -eq 0) {
        Throw-FriendlyError `
            -Detail ("Task '{0}' was not found in {1} catalog." -f $selectedToken, $Stage) `
            -Code 60 `
            -Summary "Task selection is invalid." `
            -Hint ("List valid {0} task numbers with 'clagnos task --list --vm-{0}'." -f $Stage)
    }

    return $selectedTask[0]
}

function Resolve-ClagnosTaskCommandMode {
    param([hashtable]$Options)

    $actions = @(
        @{ Name = 'list'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'list') }
        @{ Name = 'history'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'history') }
        @{ Name = 'save-app-state'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'save-app-state') }
        @{ Name = 'restore-app-state'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'restore-app-state') }
        @{ Name = 'run-vm-init'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'run-vm-init') }
        @{ Name = 'run-vm-update'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'run-vm-update') }
        @{ Name = 'enable'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'enable') }
        @{ Name = 'disable'; Present = (Test-ClagnosCliOptionPresent -Options $Options -Name 'disable') }
    )

    $presentActions = @($actions | Where-Object { [bool]$_.Present })
    if (@($presentActions).Count -lt 1) {
        Throw-FriendlyError `
            -Detail "Task command requires one action path." `
            -Code 2 `
            -Summary "Task command usage is incomplete." `
            -Hint "Use clagnos task --list/--history, --enable/--disable, --run-vm-init, --run-vm-update, --save-app-state, or --restore-app-state."
    }
    if (@($presentActions).Count -gt 1) {
        Throw-FriendlyError `
            -Detail "Task command received conflicting action options." `
            -Code 2 `
            -Summary "Only one task action can run at a time." `
            -Hint "Use exactly one of --list, --history, --enable, --disable, --run-vm-init, --run-vm-update, --save-app-state, or --restore-app-state."
    }

    return [string]$presentActions[0].Name
}

function Resolve-ClagnosTaskStageSelection {
    param(
        [hashtable]$Options,
        [switch]$AutoMode
    )

    $hasVmInit = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-init'
    $hasVmUpdate = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-update'
    $hasInitTask = (Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-init-task')
    $hasUpdateTask = (Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-update-task')

    if (($hasVmInit -and $hasVmUpdate) -or ($hasInitTask -and $hasUpdateTask)) {
        Throw-FriendlyError `
            -Detail "Task stage selectors are conflicting." `
            -Code 2 `
            -Summary "Only one task stage can be selected." `
            -Hint "Use one init selector or one update selector, not both."
    }

    if ($hasVmInit -or $hasVmUpdate) {
        Throw-FriendlyError `
            -Detail "Task save/restore must use task selectors, not inventory stage selectors." `
            -Code 2 `
            -Summary "Task stage selection is invalid." `
            -Hint "Use --vm-init-task=<task-number|task-name> or --vm-update-task=<task-number|task-name>."
    }

    if ($hasInitTask) {
        $requested = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-init-task')
        return [pscustomobject]@{ Stage = 'init'; Requested = $requested }
    }
    if ($hasUpdateTask) {
        $requested = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-update-task')
        return [pscustomobject]@{ Stage = 'update'; Requested = $requested }
    }

    Throw-FriendlyError `
        -Detail "Task save/restore requires one stage selector." `
        -Code 2 `
        -Summary "Task stage selector is missing." `
        -Hint "Use --vm-init-task=<task-number|task-name> or --vm-update-task=<task-number|task-name>."
}

function Resolve-ClagnosTaskAppStateSurface {
    param(
        [string]$Mode,
        [hashtable]$Options
    )

    if ([string]::Equals([string]$Mode, 'save-app-state', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-ClagnosCliOptionPresent -Options $Options -Name 'target') {
            Throw-FriendlyError `
                -Detail "Task save-app-state does not support --target." `
                -Code 2 `
                -Summary "Task save-app-state surface selection is invalid." `
                -Hint "Use --source=vm or --source=lm with --save-app-state."
        }

        $surface = [string](Get-ClagnosCliOptionText -Options $Options -Name 'source')
        if ([string]::IsNullOrWhiteSpace([string]$surface)) {
            $surface = 'vm'
        }
        $surface = $surface.Trim().ToLowerInvariant()
        if ($surface -notin @('vm', 'lm')) {
            Throw-FriendlyError `
                -Detail ("Unsupported --source value '{0}'." -f [string](Get-ClagnosCliOptionText -Options $Options -Name 'source')) `
                -Code 2 `
                -Summary "Task save-app-state surface selection is invalid." `
                -Hint "Use --source=vm or --source=lm."
        }

        return [pscustomobject]@{
            Surface = [string]$surface
            OptionName = 'source'
        }
    }

    if (Test-ClagnosCliOptionPresent -Options $Options -Name 'source') {
        Throw-FriendlyError `
            -Detail "Task restore-app-state does not support --source." `
            -Code 2 `
            -Summary "Task restore-app-state surface selection is invalid." `
            -Hint "Use --target=vm or --target=lm with --restore-app-state."
    }

    $surface = [string](Get-ClagnosCliOptionText -Options $Options -Name 'target')
    if ([string]::IsNullOrWhiteSpace([string]$surface)) {
        $surface = 'vm'
    }
    $surface = $surface.Trim().ToLowerInvariant()
    if ($surface -notin @('vm', 'lm')) {
        Throw-FriendlyError `
            -Detail ("Unsupported --target value '{0}'." -f [string](Get-ClagnosCliOptionText -Options $Options -Name 'target')) `
            -Code 2 `
            -Summary "Task restore-app-state surface selection is invalid." `
            -Hint "Use --target=vm or --target=lm."
    }

    return [pscustomobject]@{
        Surface = [string]$surface
        OptionName = 'target'
    }
}

function Get-ClagnosTaskAppStateRequestedUsersFromOptions {
    param([hashtable]$Options)

    return @(Resolve-ClagnosTaskAppStateRequestedUsers -UserOptionValue ([string](Get-ClagnosCliOptionText -Options $Options -Name 'user')))
}

function Resolve-ClagnosTaskVmAppStateSelectedProfiles {
    param(
        [pscustomobject]$Runtime,
        [string[]]$RequestedUsers = @()
    )

    $tokens = @(Resolve-ClagnosTaskAppStateRequestedUsers -UserOptionValue (@($RequestedUsers) -join ','))
    if (@($tokens).Count -eq 1 -and [string]::Equals([string]$tokens[0], '.all.', [System.StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{
            IsAll = $true
            SelectedProfiles = @('manager', 'assistant')
        }
    }

    $managerUser = ''
    $assistantUser = ''
    if ($null -ne $Runtime -and $Runtime.PSObject.Properties.Match('Context').Count -gt 0 -and $null -ne $Runtime.Context) {
        if ($Runtime.Context.PSObject.Properties.Match('VmUser').Count -gt 0) {
            $managerUser = [string]$Runtime.Context.VmUser
        }
        if ($Runtime.Context.PSObject.Properties.Match('VmAssistantUser').Count -gt 0) {
            $assistantUser = [string]$Runtime.Context.VmAssistantUser
        }
    }

    $canonicalMap = @{
        'manager' = 'manager'
        'assistant' = 'assistant'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$managerUser)) {
        $canonicalMap[[string]$managerUser.Trim().ToLowerInvariant()] = 'manager'
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$assistantUser)) {
        $canonicalMap[[string]$assistantUser.Trim().ToLowerInvariant()] = 'assistant'
    }

    $selectedProfiles = New-Object 'System.Collections.Generic.List[string]'
    $seen = @{}
    foreach ($token in @($tokens)) {
        $lookupKey = [string]$token
        if ([string]::Equals([string]$lookupKey, '.current.', [System.StringComparison]::OrdinalIgnoreCase)) {
            $lookupKey = 'manager'
        }

        $normalizedLookup = if ([string]::IsNullOrWhiteSpace([string]$lookupKey)) { '' } else { $lookupKey.Trim().ToLowerInvariant() }
        if ([string]::IsNullOrWhiteSpace([string]$normalizedLookup) -or -not $canonicalMap.ContainsKey($normalizedLookup)) {
            Throw-FriendlyError `
                -Detail ("VM app-state user '{0}' is invalid for the current managed target." -f [string]$lookupKey) `
                -Code 67 `
                -Summary "Task app-state VM user selection is invalid." `
                -Hint "Use --user=.all., --user=.current., --user=manager, --user=assistant, or the current managed VM usernames."
        }

        $canonicalLabel = [string]$canonicalMap[$normalizedLookup]
        if ($seen.ContainsKey($canonicalLabel)) {
            continue
        }

        $selectedProfiles.Add($canonicalLabel) | Out-Null
        $seen[$canonicalLabel] = $true
    }

    return [pscustomobject]@{
        IsAll = $false
        SelectedProfiles = @($selectedProfiles.ToArray())
    }
}

function Assert-ClagnosTaskCommandOptionScope {
    param(
        [string]$Mode,
        [hashtable]$Options
    )

    if ([string]::Equals($Mode, 'list', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($optionName in @('group', 'vm-name', 'subscription-id', 'vm-init-task', 'vm-update-task', 'package', 'package-catalog', 'run-vm-init', 'run-vm-update', 'source', 'target', 'user')) {
            if (Test-ClagnosCliOptionPresent -Options $Options -Name $optionName) {
                Throw-FriendlyError `
                    -Detail ("Task list mode does not support --{0}." -f [string]$optionName) `
                    -Code 2 `
                    -Summary "Task list received an unsupported option." `
                    -Hint "Use only --list with --vm-init/--vm-update/--disabled plus optional --windows/--linux."
            }
        }

        return
    }

    if ([string]::Equals($Mode, 'history', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($optionName in @('list', 'disabled', 'vm-init', 'vm-update', 'vm-init-task', 'vm-update-task', 'package', 'package-catalog', 'run-vm-init', 'run-vm-update', 'save-app-state', 'restore-app-state', 'source', 'target', 'user', 'enable', 'disable', 'group', 'vm-name', 'subscription-id')) {
            if (Test-ClagnosCliOptionPresent -Options $Options -Name $optionName) {
                Throw-FriendlyError `
                    -Detail ("Task history mode does not support --{0}." -f [string]$optionName) `
                    -Code 2 `
                    -Summary "Task history received an unsupported option." `
                    -Hint "Use only clagnos task --history to show recent local task outcomes."
            }
        }
        return
    }

    if ([string]::Equals($Mode, 'enable', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($Mode, 'disable', [System.StringComparison]::OrdinalIgnoreCase)) {
        $selectors = @(
            [bool](Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-init-task'),
            [bool](Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-update-task')
        )
        if (@($selectors | Where-Object { $_ }).Count -ne 1) {
            Throw-FriendlyError `
                -Detail 'Task availability changes require exactly one --vm-init-task or --vm-update-task selector.' `
                -Code 2 `
                -Summary 'Task stage selection is missing or conflicting.' `
                -Hint 'Choose the task number or name and provide exactly one stage-specific task selector.'
        }
        foreach ($optionName in @('list','disabled','vm-init','vm-update','run-vm-init','run-vm-update','save-app-state','restore-app-state','source','target','user','package','package-catalog','group','vm-name','subscription-id')) {
            if (Test-ClagnosCliOptionPresent -Options $Options -Name $optionName) {
                Throw-FriendlyError `
                    -Detail ("Task availability mode does not support --{0}." -f [string]$optionName) `
                    -Code 2 `
                    -Summary 'Task availability received an unsupported option.' `
                    -Hint 'Use exactly one of --enable/--disable with --vm-init-task or --vm-update-task, plus an optional platform selector.'
            }
        }
        return
    }

    if ([string]::Equals($Mode, 'save-app-state', [System.StringComparison]::OrdinalIgnoreCase) -or
        [string]::Equals($Mode, 'restore-app-state', [System.StringComparison]::OrdinalIgnoreCase)) {
        foreach ($optionName in @('disabled', 'vm-init', 'vm-update', 'run-vm-init', 'run-vm-update')) {
            if (Test-ClagnosCliOptionPresent -Options $Options -Name $optionName) {
                Throw-FriendlyError `
                    -Detail ("Task app-state maintenance does not support --{0}." -f [string]$optionName) `
                    -Code 2 `
                    -Summary "Task app-state mode received an unsupported option." `
                    -Hint "Use --save-app-state or --restore-app-state with --vm-init-task/--vm-update-task plus optional --source/--target, --user, and VM selectors."
            }
        }

        $hasPackage = Test-ClagnosCliOptionPresent -Options $Options -Name 'package'
        $hasPackageCatalog = Test-ClagnosCliOptionPresent -Options $Options -Name 'package-catalog'
        if ($hasPackage -ne $hasPackageCatalog) {
            Throw-FriendlyError `
                -Detail 'Package app-state selectors require both --package and --package-catalog.' `
                -Code 2 `
                -Summary 'Package app-state selection is incomplete.' `
                -Hint 'Provide both --package <id> and --package-catalog <builtin|custom>.'
        }
        $hasInitTask = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-init-task'
        $hasUpdateTask = Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-update-task'
        if (($hasPackage -and ($hasInitTask -or $hasUpdateTask)) -or (-not $hasPackage -and ($hasInitTask -eq $hasUpdateTask))) {
            Throw-FriendlyError `
                -Detail 'Task app-state selection requires either one task selector or one package plus catalog selector.' `
                -Code 2 `
                -Summary 'Task app-state selection is missing or conflicting.' `
                -Hint 'Use exactly one of --vm-init-task, --vm-update-task, or the pair --package and --package-catalog.'
        }

        return
    }

    foreach ($optionName in @('disabled', 'vm-init', 'vm-update', 'vm-init-task', 'vm-update-task', 'package', 'package-catalog', 'save-app-state', 'restore-app-state', 'source', 'target', 'user')) {
        if (Test-ClagnosCliOptionPresent -Options $Options -Name $optionName) {
            Throw-FriendlyError `
                -Detail ("Task run mode does not support --{0}." -f [string]$optionName) `
                -Code 2 `
                -Summary "Task run mode received an unsupported option." `
                -Hint "Use --run-vm-init or --run-vm-update with optional target selectors."
        }
    }
}

function Invoke-ClagnosTaskAvailabilityToggle {
    param(
        [string]$StageRoot,
        [ValidateSet('windows','linux')][string]$Platform,
        [ValidateSet('init','update')][string]$Stage,
        [string]$TaskNumberOrName,
        [ValidateSet('enable','disable')][string]$Action
    )

    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $StageRoot -Platform $Platform -Stage $Stage -SuppressSkipMessages
    $task = Resolve-ClagnosTaskSelection -TaskBlocks @($catalog.InventoryTasks) -TaskNumberOrName $TaskNumberOrName -Stage $Stage
    $shouldEnable = [string]::Equals($Action, 'enable', [System.StringComparison]::OrdinalIgnoreCase)
    if ([bool]$task.Enabled -eq $shouldEnable) {
        Write-Host ("Task '{0}' is already {1}." -f [string]$task.Name, $(if ($shouldEnable) { 'enabled' } else { 'disabled' })) -ForegroundColor Yellow
        return [pscustomobject]@{ Task = $task; Enabled = [bool]$shouldEnable; Changed = $false }
    }

    $confirmationToken = if ($shouldEnable) { 'ENABLE' } else { 'DISABLE' }
    $answer = Read-Host ("This changes the shared {0} task catalog for future runs on any VM. Type {1} to confirm {2} '{3}'" -f $Platform, $confirmationToken, $Action, [string]$task.Name)
    if (-not [string]::Equals([string]$answer, $confirmationToken, [System.StringComparison]::Ordinal)) {
        Write-Host 'Task availability change canceled; no files were changed.' -ForegroundColor Yellow
        return [pscustomobject]@{ Task = $task; Enabled = [bool]$task.Enabled; Changed = $false }
    }

    $changed = Set-ClagnosTaskCatalogEnabled -Path ([string]$task.CatalogPath) -TaskId ([string]$task.Name) -Enabled $shouldEnable
    $verifiedCatalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $StageRoot -Platform $Platform -Stage $Stage -SuppressSkipMessages
    $verifiedTask = @($verifiedCatalog.InventoryTasks | Where-Object { [string]::Equals([string]$_.Name, [string]$task.Name, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($verifiedTask).Count -ne 1 -or [bool]$verifiedTask[0].Enabled -ne $shouldEnable) {
        throw ("Task availability verification failed after attempting to {0} '{1}'." -f $Action, [string]$task.Name)
    }

    $statusText = if ($shouldEnable) { 'enabled' } else { 'disabled' }
    Write-Host ("Task '{0}' is now {1} for future {2} runs." -f [string]$task.Name, $statusText, $Platform) -ForegroundColor Green
    return [pscustomobject]@{ Task = $verifiedTask[0]; Enabled = [bool]$shouldEnable; Changed = [bool]$changed }
}
function Resolve-ClagnosTaskBlockForMaintenance {
    param(
        [pscustomobject]$Runtime,
        [hashtable]$Options,
        [switch]$AutoMode
    )

    $hasPackage = Test-ClagnosCliOptionPresent -Options $Options -Name 'package'
    $hasPackageCatalog = Test-ClagnosCliOptionPresent -Options $Options -Name 'package-catalog'
    if ($hasPackage -or $hasPackageCatalog) {
        $packageId = [string](Get-ClagnosCliOptionText -Options $Options -Name 'package')
        $packageCatalog = [string](Get-ClagnosCliOptionText -Options $Options -Name 'package-catalog')
        if ($packageCatalog -notin @('builtin','custom')) {
            Throw-FriendlyError `
                -Detail ("Unsupported package catalog '{0}'." -f $packageCatalog) `
                -Code 2 `
                -Summary 'Package catalog selection is invalid.' `
                -Hint 'Use --package-catalog=builtin or --package-catalog=custom.'
        }
        $packages = @(Get-ClagnosPackageCatalog -Platform ([string]$Runtime.Platform) -Catalog $packageCatalog)
        $selectedPackage = @($packages | Where-Object { [string]::Equals([string]$_.Id,$packageId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($selectedPackage.Count -ne 1) {
            Throw-FriendlyError `
                -Detail ("Package '{0}' was not found in the {1} catalog." -f $packageId,$packageCatalog) `
                -Code 60 `
                -Summary 'Package app-state target is unavailable.' `
                -Hint 'Choose a package from the selected package catalog.'
        }
        $resolvedPackageTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($selectedPackage[0].PackageTask) -Context $Runtime.Context)[0]
        return [pscustomobject]@{ Stage = 'package'; TaskBlock = $resolvedPackageTask }
    }

    $selection = Resolve-ClagnosTaskStageSelection -Options $Options -AutoMode:$AutoMode
    $stage = [string]$selection.Stage
    $requested = [string]$selection.Requested

    if ($stage -eq 'init') {
        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$Runtime.Context.VmInitTaskDir) -Platform ([string]$Runtime.Platform) -Stage 'init'
        $tasks = Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($catalog.ActiveTasks) -Context $Runtime.Context
        $selectedTask = Resolve-ClagnosTaskSelection -TaskBlocks $tasks -TaskNumberOrName $requested -Stage 'init' -AutoMode:$AutoMode
        return [pscustomobject]@{ Stage = 'init'; TaskBlock = $selectedTask }
    }

    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$Runtime.Context.VmUpdateTaskDir) -Platform ([string]$Runtime.Platform) -Stage 'update'
    $tasks = Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($catalog.ActiveTasks) -Context $Runtime.Context
    $selectedTask = Resolve-ClagnosTaskSelection -TaskBlocks $tasks -TaskNumberOrName $requested -Stage 'update' -AutoMode:$AutoMode
    return [pscustomobject]@{ Stage = 'update'; TaskBlock = $selectedTask }
}

function Resolve-ClagnosTaskRunSelection {
    param(
        [hashtable]$Options
    )

    $hasRunInit = Test-ClagnosCliOptionPresent -Options $Options -Name 'run-vm-init'
    $hasRunUpdate = Test-ClagnosCliOptionPresent -Options $Options -Name 'run-vm-update'

    if ($hasRunInit -and $hasRunUpdate) {
        Throw-FriendlyError `
            -Detail "Both --run-vm-init and --run-vm-update were provided." `
            -Code 2 `
            -Summary "Only one task stage can be selected." `
            -Hint "Use either --run-vm-init or --run-vm-update."
    }

    if ($hasRunInit) {
        return [pscustomobject]@{
            Stage = 'init'
            Requested = [string](Get-ClagnosCliOptionText -Options $Options -Name 'run-vm-init')
        }
    }
    if ($hasRunUpdate) {
        return [pscustomobject]@{
            Stage = 'update'
            Requested = [string](Get-ClagnosCliOptionText -Options $Options -Name 'run-vm-update')
        }
    }

    Throw-FriendlyError `
        -Detail "Task run requires one stage selector." `
        -Code 2 `
        -Summary "Task run selector is missing." `
        -Hint "Use --run-vm-init <task-number|task-name> or --run-vm-update <task-number|task-name>."
}

function Resolve-ClagnosTaskBlockForStage {
    param(
        [pscustomobject]$Runtime,
        [string]$Stage,
        [string]$Requested,
        [switch]$AutoMode
    )

    if ([string]::Equals([string]$Stage, 'init', [System.StringComparison]::OrdinalIgnoreCase)) {
        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$Runtime.Context.VmInitTaskDir) -Platform ([string]$Runtime.Platform) -Stage 'init'
        $tasks = Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($catalog.ActiveTasks) -Context $Runtime.Context
        return (Resolve-ClagnosTaskSelection -TaskBlocks $tasks -TaskNumberOrName $Requested -Stage 'init' -AutoMode:$AutoMode)
    }

    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$Runtime.Context.VmUpdateTaskDir) -Platform ([string]$Runtime.Platform) -Stage 'update'
    $tasks = Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($catalog.ActiveTasks) -Context $Runtime.Context
    return (Resolve-ClagnosTaskSelection -TaskBlocks $tasks -TaskNumberOrName $Requested -Stage 'update' -AutoMode:$AutoMode)
}

function Resolve-ClagnosTaskExecutionPlanForStage {
    param(
        [pscustomobject]$Runtime,
        [string]$Stage,
        [string]$Requested,
        [switch]$AutoMode
    )

    if ([string]::Equals([string]$Stage, 'init', [System.StringComparison]::OrdinalIgnoreCase)) {
        $selectedTaskBlock = Resolve-ClagnosTaskBlockForStage -Runtime $Runtime -Stage $Stage -Requested $Requested -AutoMode:$AutoMode
        return [pscustomobject]@{
            SelectedTaskBlock = $selectedTaskBlock
            ExecutionTaskBlocks = @($selectedTaskBlock)
        }
    }

    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$Runtime.Context.VmUpdateTaskDir) -Platform ([string]$Runtime.Platform) -Stage 'update'
    $tasks = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($catalog.ActiveTasks) -Context $Runtime.Context)
    $selectedTaskBlock = Resolve-ClagnosTaskSelection -TaskBlocks $tasks -TaskNumberOrName $Requested -Stage 'update' -AutoMode:$AutoMode

    return [pscustomobject]@{
        SelectedTaskBlock = $selectedTaskBlock
        ExecutionTaskBlocks = @($selectedTaskBlock)
    }
}

function Invoke-ClagnosWinRmTaskBlocksWithGuestRestart {
    param(
        [psobject]$Runtime,
        [string]$HostName,
        [psobject]$Target,
        [object[]]$TaskBlocks,
        [ValidateSet('continue','strict')][string]$TaskOutcomeMode = 'strict',
        [hashtable]$Options = @{},
        [switch]$AutoMode,
        [switch]$WindowsFlag
    )

    if (@($TaskBlocks).Count -ne 1) { throw 'A WinRM task reboot retry must contain exactly one task.' }
    $result = Invoke-ClagnosWinRmTaskBlocks -Platform 'windows' -HostName $HostName -Runtime $Runtime -Target $Target -TaskBlocks $TaskBlocks -TaskOutcomeMode $TaskOutcomeMode -PerfTaskCategory 'task-run'
    if (-not [bool]$result.RebootRequired -or [string]$TaskBlocks[0].TaskType -eq 'package') {
        return [pscustomobject]@{ Result=$result; Runtime=$Runtime; Target=$Target; HostName=$HostName }
    }

    if ($Options.Count -eq 0) {
        $Options = @{
            group = [string]$Runtime.Context.ResourceGroup
            'vm-name' = [string]$Runtime.Context.VmName
        }
        $subscription = Get-ClagnosResolvedSubscriptionContext
        if ($null -ne $subscription -and -not [string]::IsNullOrWhiteSpace([string]$subscription.SubscriptionId)) { $Options['subscription-id'] = [string]$subscription.SubscriptionId }
    }
    $taskName = [string]$TaskBlocks[0].Name
    Write-ClagnosActionProgress -Action ("apply the requested one-time VM restart for Windows task '{0}'" -f $taskName)
    $restart = Restart-ClagnosPackageVmForPendingReboot -Runtime $Runtime -Target $Target -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -ActionLabel ("Windows task '{0}'" -f $taskName) -WaitTransport 'winrm'
    $Runtime = $restart.Runtime
    $Target = $restart.Target
    $vmDetails = Get-ClagnosVmDetails -Context $Runtime.Context -AllowCachedInventory
    $HostName = [string]$vmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($HostName)) { $HostName = [string]$vmDetails.PublicIP }
    if ([string]::IsNullOrWhiteSpace($HostName)) { throw ("Windows task '{0}' requested a restart, but its WinRM endpoint could not be resolved afterward." -f $taskName) }

    Write-ClagnosActionProgress -Action ("rerun Windows task '{0}' once after restart to verify servicing completion" -f $taskName)
    $retryResult = Invoke-ClagnosWinRmTaskBlocks -Platform 'windows' -HostName $HostName -Runtime $Runtime -Target $Target -TaskBlocks $TaskBlocks -TaskOutcomeMode $TaskOutcomeMode -PerfTaskCategory 'task-run'
    if ([bool]$retryResult.RebootRequired) {
        throw ("Windows task '{0}' still requests a reboot after its one allowed servicing restart. Rerun the task after reviewing target Windows servicing state." -f $taskName)
    }
    $retryResult.RebootCount = 1
    $retryResult.FinalRestartCount = 1
    $retryResult.RebootRequestedTasks = @($taskName)
    return [pscustomobject]@{ Result=$retryResult; Runtime=$Runtime; Target=$Target; HostName=$HostName }
}

function Invoke-ClagnosTaskExecutionWithTargetCore {
    param(
        [pscustomobject]$Runtime,
        [hashtable]$Options,
        [string]$OperationName = 'task',
        [string]$Stage,
        [string]$Requested,
        [psobject]$PackageTaskBlock,
        [switch]$AutoMode,
        [ValidateSet('continue','strict')]
        [string]$TaskOutcomeModeOverride = ''
    )

    $effectiveTaskOutcomeMode = [string]$Runtime.TaskOutcomeMode
    if (-not [string]::IsNullOrWhiteSpace([string]$TaskOutcomeModeOverride)) {
        $effectiveTaskOutcomeMode = [string]$TaskOutcomeModeOverride
    }

    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $Runtime.EffectiveConfigMap -OperationName $OperationName
    $Runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $Runtime.Context.VmName = [string]$target.VmName
    if ($null -ne $PackageTaskBlock) {
        if (-not [string]::Equals([string]$Stage, 'update', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Package installers must use the remote VM update transport.'
        }
        $resolvedPackageBlocks = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($PackageTaskBlock) -Context $Runtime.Context)
        $packageTaskBlock = $resolvedPackageBlocks[0]
        $executionBlocks = New-Object 'System.Collections.Generic.List[object]'
        $executionBlocks.Add($packageTaskBlock) | Out-Null

        $postInstallTaskNames = @()
        if ($null -ne $PackageTaskBlock.PackageSpec -and $null -ne $PackageTaskBlock.PackageSpec.PostInstallTasks) {
            $postInstallTaskNames = @($PackageTaskBlock.PackageSpec.PostInstallTasks | ForEach-Object { [string]$_ })
        }
        if ($postInstallTaskNames.Count -gt 0) {
            $updateCatalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath ([string]$Runtime.Context.VmUpdateTaskDir) -Platform ([string]$Runtime.Platform) -Stage 'update' -SuppressSkipMessages
            $updateTasks = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($updateCatalog.ActiveTasks) -Context $Runtime.Context)
            foreach ($postInstallTaskName in $postInstallTaskNames) {
                $postInstallTask = @($updateTasks | Where-Object { [string]::Equals([string]$_.Name, $postInstallTaskName, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
                if ($postInstallTask.Count -ne 1) {
                    throw ("Package '{0}' requires missing post-install task '{1}'." -f [string]$PackageTaskBlock.Name, $postInstallTaskName)
                }
                $executionBlocks.Add($postInstallTask[0]) | Out-Null
            }
        }
        $executionPlan = [pscustomobject]@{
            SelectedTaskBlock = $packageTaskBlock
            ExecutionTaskBlocks = @($executionBlocks.ToArray())
        }
    }
    else {
        $executionPlan = Resolve-ClagnosTaskExecutionPlanForStage -Runtime $Runtime -Stage $Stage -Requested $Requested -AutoMode:$AutoMode
    }
    $taskBlock = $executionPlan.SelectedTaskBlock
    $executionTaskBlocks = @($executionPlan.ExecutionTaskBlocks)

    if ([string]::Equals([string]$Stage, 'init', [System.StringComparison]::OrdinalIgnoreCase)) {
        $combinedShell = if ([string]::Equals([string]$Runtime.Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) { 'bash' } else { 'powershell' }
        $vmRuntimeDetails = Get-ClagnosVmDetails -Context $Runtime.Context
        $sshHost = [string]$vmRuntimeDetails.VmFqdn
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            $sshHost = [string]$vmRuntimeDetails.PublicIP
        }
        $runCommandResult = Invoke-VmRunCommandBlocks -ResourceGroup ([string]$Runtime.Context.ResourceGroup) -VmName ([string]$Runtime.Context.VmName) -CommandId ([string]$Runtime.PlatformDefaults.RunCommandId) -TaskBlocks @($executionTaskBlocks) -CombinedShell $combinedShell -TaskOutcomeMode $effectiveTaskOutcomeMode -PerfTaskCategory "task-run" -Platform ([string]$Runtime.Platform) -RepoRoot (Get-ClagnosRepoRoot) -ManagerUser ([string]$Runtime.Context.VmUser) -AssistantUser ([string]$Runtime.Context.VmAssistantUser) -SshHost $sshHost -SshUser ([string]$Runtime.Context.VmUser) -SshPassword ([string]$Runtime.Context.VmPass) -SshPort ([string]$Runtime.Context.SshPort) -SshConnectTimeoutSeconds ([int]$Runtime.SshConnectTimeoutSeconds) -ConfiguredPySshClientPath ([string]$Runtime.ConfiguredPySshClientPath)
        return [pscustomobject]@{
            Stage = 'init'
            Task = $taskBlock
            TaskBlocks = @($executionTaskBlocks)
            TaskOutcomeMode = $effectiveTaskOutcomeMode
            Result = $runCommandResult
        }
    }

    $vmRuntimeDetails = Get-ClagnosVmDetails -Context $Runtime.Context
    $sshHost = [string]$vmRuntimeDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($sshHost)) {
        $sshHost = [string]$vmRuntimeDetails.PublicIP
    }
    if ([string]::IsNullOrWhiteSpace($sshHost)) {
        throw "Task execution could not resolve VM SSH host (FQDN/Public IP)."
    }

    $declaredWinRmTransport = @($executionTaskBlocks | Where-Object { $_.PSObject.Properties.Match('Transport').Count -gt 0 -and [string]$_.Transport -eq 'winrm' }).Count -gt 0
    $packageWinRmTransport = ([string]::Equals([string]$OperationName,'package',[System.StringComparison]::OrdinalIgnoreCase) -and
        (Get-ClagnosPackageTransport -ConfigMap ([hashtable]$Runtime.EffectiveConfigMap)) -eq 'winrm')
    if ([string]::Equals([string]$Runtime.Platform,'windows',[System.StringComparison]::OrdinalIgnoreCase) -and ($declaredWinRmTransport -or $packageWinRmTransport)) {
        if ($Runtime.Context.PSObject.Properties.Match('PowerShellPort').Count -eq 0) { $Runtime.Context | Add-Member -NotePropertyName PowerShellPort -NotePropertyValue (Get-ClagnosDefaultPowerShellPortText) }
        if ($declaredWinRmTransport -and -not [string]::Equals([string]$OperationName,'package',[System.StringComparison]::OrdinalIgnoreCase)) {
            $winrmExecution = Invoke-ClagnosWinRmTaskBlocksWithGuestRestart -Runtime $Runtime -HostName $sshHost -Target $target -TaskBlocks @($executionTaskBlocks) -TaskOutcomeMode $effectiveTaskOutcomeMode -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag
            $winrmTaskResult = $winrmExecution.Result
        }
        else {
            $winrmTaskResult = Invoke-ClagnosWinRmTaskBlocks `
                -Platform 'windows' `
                -HostName $sshHost `
                -Runtime $Runtime `
                -Target $target `
                -TaskBlocks @($executionTaskBlocks) `
                -TaskOutcomeMode $effectiveTaskOutcomeMode `
                -PerfTaskCategory 'task-run'
        }
        return [pscustomobject]@{
            Stage = 'update'
            Task = $taskBlock
            TaskBlocks = @($executionTaskBlocks)
            TaskOutcomeMode = $effectiveTaskOutcomeMode
            Result = $winrmTaskResult
        }
    }

    $sshTaskResult = Invoke-ClagnosSshTaskBlocks `
        -Platform ([string]$Runtime.Platform) `
        -RepoRoot (Get-ClagnosRepoRoot) `
        -SshHost $sshHost `
        -SshUser ([string]$Runtime.Context.VmUser) `
        -SshPassword ([string]$Runtime.Context.VmPass) `
        -SshPort ([string]$Runtime.Context.SshPort) `
        -AssistantUser ([string]$Runtime.Context.VmAssistantUser) `
        -ResourceGroup ([string]$Runtime.Context.ResourceGroup) `
        -VmName ([string]$Runtime.Context.VmName) `
        -TaskBlocks @($executionTaskBlocks) `
        -TaskOutcomeMode $effectiveTaskOutcomeMode `
        -PerfTaskCategory 'task-run' `
        -SshMaxRetries 1 `
        -SshTaskTimeoutSeconds ([int]$Runtime.SshTaskTimeoutSeconds) `
        -SshConnectTimeoutSeconds ([int]$Runtime.SshConnectTimeoutSeconds) `
        -ConfiguredPySshClientPath ([string]$Runtime.ConfiguredPySshClientPath)

    return [pscustomobject]@{
        Stage = 'update'
        Task = $taskBlock
        TaskBlocks = @($executionTaskBlocks)
        TaskOutcomeMode = $effectiveTaskOutcomeMode
        Result = $sshTaskResult
    }
}

# Handles Get-ClagnosTaskRunResultCount.
function Get-ClagnosTaskRunResultCount {
    param(
        [psobject]$Result,
        [string]$PropertyName
    )

    if ($null -ne $Result -and $Result.PSObject.Properties.Match($PropertyName).Count -gt 0) {
        $count = 0
        if ([int]::TryParse([string]$Result.$PropertyName, [ref]$count)) { return [int]$count }
    }
    return 0
}

# Handles New-ClagnosTaskRunHistoryRecord.
function New-ClagnosTaskRunHistoryRecord {
    param(
        [psobject]$Runtime,
        [hashtable]$Options,
        [string]$OperationName,
        [string]$Stage,
        [string]$Requested,
        [psobject]$PackageTaskBlock,
        [psobject]$RunResult,
        [System.Management.Automation.ErrorRecord]$Failure,
        [double]$DurationSeconds
    )

    $taskBlock = if ($null -ne $RunResult -and $null -ne $RunResult.Task) { $RunResult.Task } else { $PackageTaskBlock }
    $taskName = if ($null -ne $taskBlock) { [string]$taskBlock.Name } else { '' }
    $taskNumber = if ($null -ne $taskBlock -and $taskBlock.PSObject.Properties.Match('TaskNumber').Count -gt 0) { [int]$taskBlock.TaskNumber } else { 0 }
    if ($taskNumber -lt 1 -and [string]$Requested -match '^(\d{2,5})') { $taskNumber = [int]$Matches[1] }
    $taskNames = @($taskName)
    if ($null -ne $RunResult -and $RunResult.PSObject.Properties.Match('TaskBlocks').Count -gt 0) {
        $taskNames = @($RunResult.TaskBlocks | ForEach-Object { [string]$_.Name } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    $resultPayload = if ($null -ne $RunResult) { $RunResult.Result } else { $null }
    $failedCount = Get-ClagnosTaskRunResultCount -Result $resultPayload -PropertyName 'FailedCount'
    $warningCount = Get-ClagnosTaskRunResultCount -Result $resultPayload -PropertyName 'WarningCount'
    $errorCount = Get-ClagnosTaskRunResultCount -Result $resultPayload -PropertyName 'ErrorCount'
    $successCount = Get-ClagnosTaskRunResultCount -Result $resultPayload -PropertyName 'SuccessCount'
    $rebootCount = Get-ClagnosTaskRunResultCount -Result $resultPayload -PropertyName 'RebootCount'
    $deferredTasks = @()
    if ($null -ne $resultPayload -and $resultPayload.PSObject.Properties.Match('DeferredAppStateTasks').Count -gt 0) {
        $deferredTasks = @($resultPayload.DeferredAppStateTasks | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    }
    $deferredCount = Get-ClagnosTaskRunResultCount -Result $resultPayload -PropertyName 'DeferredAppStateCount'
    if ($deferredCount -lt 1) { $deferredCount = @($deferredTasks).Count }
    $failedTasks = if ($null -ne $resultPayload -and $resultPayload.PSObject.Properties.Match('FailedTasks').Count -gt 0) { @($resultPayload.FailedTasks | ForEach-Object { [string]$_ }) } else { @() }
    $warningTasks = if ($null -ne $resultPayload -and $resultPayload.PSObject.Properties.Match('WarningTasks').Count -gt 0) { @($resultPayload.WarningTasks | ForEach-Object { [string]$_ }) } else { @() }

    $outcome = 'completed'
    $failureSummary = ''
    $failureCategory = ''
    if ($null -ne $Failure) {
        $outcome = 'failed'
        $failureCategory = [string]$Failure.Exception.GetType().Name
        if ($Failure.Exception.Data.Contains('Summary')) { $failureSummary = [string]$Failure.Exception.Data['Summary'] }
    }
    elseif ($failedCount -gt 0 -or $errorCount -gt 0) {
        $outcome = 'completed-with-failures'
    }
    elseif ($warningCount -gt 0) {
        $outcome = 'completed-with-warnings'
    }

    $context = if ($null -ne $Runtime) { $Runtime.Context } else { $null }
    $resourceGroup = if ($null -ne $context) { [string]$context.ResourceGroup } else { [string](Get-ClagnosCliOptionText -Options $Options -Name 'group') }
    $vmName = if ($null -ne $context) { [string]$context.VmName } else { [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name') }
    $platform = if ($null -ne $Runtime) { [string]$Runtime.Platform } else { '' }

    return [ordered]@{
        SchemaVersion = 1
        CompletedAtUtc = [DateTime]::UtcNow.ToString('o')
        Operation = [string]$OperationName
        Stage = if ($null -ne $RunResult -and -not [string]::IsNullOrWhiteSpace([string]$RunResult.Stage)) { [string]$RunResult.Stage } else { [string]$Stage }
        Platform = $platform
        ResourceGroup = $resourceGroup
        VmName = $vmName
        TaskNumber = [int]$taskNumber
        TaskName = $taskName
        TaskNames = @($taskNames)
        Requested = [string]$Requested
        Outcome = $outcome
        SuccessCount = [int]$successCount
        FailedCount = [int]$failedCount
        WarningCount = [int]$warningCount
        ErrorCount = [int]$errorCount
        RebootCount = [int]$rebootCount
        DeferredAppStateCount = [int]$deferredCount
        DeferredAppStateTasks = @($deferredTasks)
        FailedTasks = @($failedTasks)
        WarningTasks = @($warningTasks)
        DurationSeconds = [Math]::Round([double]$DurationSeconds, 1)
        FailureCategory = $failureCategory
        FailureSummary = $failureSummary
    }
}

# Handles Invoke-ClagnosTaskExecutionWithTarget.
function Invoke-ClagnosTaskExecutionWithTarget {
    param(
        [pscustomobject]$Runtime,
        [hashtable]$Options,
        [string]$OperationName = 'task',
        [string]$Stage,
        [string]$Requested,
        [psobject]$PackageTaskBlock,
        [switch]$AutoMode,
        [ValidateSet('continue','strict')]
        [string]$TaskOutcomeModeOverride = ''
    )

    if ([bool]$script:ClagnosTaskHistoryDisabled) {
        return (Invoke-ClagnosTaskExecutionWithTargetCore @PSBoundParameters)
    }

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $runResult = $null
    $failure = $null
    try {
        $runResult = Invoke-ClagnosTaskExecutionWithTargetCore @PSBoundParameters
    }
    catch {
        $failure = $_
    }
    finally {
        if ($watch.IsRunning) { $watch.Stop() }
    }

    $historyRecord = New-ClagnosTaskRunHistoryRecord `
        -Runtime $Runtime `
        -Options $Options `
        -OperationName $OperationName `
        -Stage $Stage `
        -Requested $Requested `
        -PackageTaskBlock $PackageTaskBlock `
        -RunResult $runResult `
        -Failure $failure `
        -DurationSeconds $watch.Elapsed.TotalSeconds
    try {
        Write-ClagnosTaskRunHistoryRecord -Record $historyRecord
    }
    catch {
        Write-Warning ("Local task history could not be saved: {0}" -f [string]$_.Exception.Message)
    }

    if ($null -ne $failure) { throw $failure }
    return $runResult
}
