# Shared runtime step and action wrappers.

function Write-ClagnosActionProgress {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action
    )

    $actionText = [string]$Action
    if ([string]::IsNullOrWhiteSpace($actionText)) { $actionText = 'continue operation' }
    $actionText = $actionText.Trim()
    if ($actionText -notmatch '^doing\s*:') { $actionText = 'Doing: ' + $actionText }
    Write-Host $actionText -ForegroundColor DarkCyan
}

# Handles Invoke-Step.
function Invoke-Step {
    param(
        [string] $prompt,
        [scriptblock] $Action
    )

    function Publish-NewStepVariables {
        param(
            [object[]]$BeforeVariables,
            [object[]]$AfterVariables
        )

        $beforeNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($beforeVar in $BeforeVariables) {
            [void]$beforeNames.Add([string]$beforeVar.Name)
        }

        foreach ($var in $AfterVariables) {
            $varName = [string]$var.Name
            if ($beforeNames.Contains($varName)) {
                continue
            }

            if (($var.Options -band [System.Management.Automation.ScopedItemOptions]::Constant) -ne 0) {
                continue
            }

            try {
                Set-Variable -Name $varName -Value $var.Value -Scope Script -Force -ErrorAction Stop
            }
            catch {
                # Skip transient or restricted variables safely.
            }
        }
    }

    $before = @(Get-Variable)
    $stepResult = $null
    $modeLabel = if ($script:AutoMode) { 'auto' } else { 'interactive' }
    Write-ClagnosActionProgress -Action ("Step: {0} (mode: {1})" -f $prompt, $modeLabel)
    $stepWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $stepResult = . $Action
    if ($stepWatch.IsRunning) { $stepWatch.Stop() }
    if (-not $script:ClagnosQuietOutput) {
        Write-Host ("Completed {0} ({1:N1}s)" -f $prompt, $stepWatch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
    }
    $after = @(Get-Variable)
    Publish-NewStepVariables -BeforeVariables $before -AfterVariables $after
    return $stepResult
}

# Handles Confirm-YesNo.
function Confirm-YesNo {
    param(
        [string]$PromptText,
        [bool]$DefaultYes = $false
    )

    $hintText = if ($DefaultYes) { " [Y/n]" } else { " [y/N]" }
    while ($true) {
        $raw = Read-Host ($PromptText + $hintText)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $DefaultYes
        }

        $value = $raw.Trim().ToLowerInvariant()
        if ($value -eq "y" -or $value -eq "yes") {
            return $true
        }
        if ($value -eq "n" -or $value -eq "no") {
            return $false
        }

        Write-Host "Please answer yes or no." -ForegroundColor Yellow
    }
}

# Handles Confirm-ClagnosYesNoCancel.
function Confirm-ClagnosYesNoCancel {
    param(
        [string]$PromptText,
        [string]$DefaultChoice = 'yes'
    )

    $defaultValue = [string]$DefaultChoice
    if ([string]::IsNullOrWhiteSpace([string]$defaultValue)) {
        $defaultValue = 'yes'
    }
    $defaultValue = $defaultValue.Trim().ToLowerInvariant()
    if ($defaultValue -notin @('yes', 'no', 'cancel')) {
        $defaultValue = 'yes'
    }

    $hintText = switch ($defaultValue) {
        'no' { ' [y/N/c]' }
        'cancel' { ' [y/n/C]' }
        default { ' [Y/n/c]' }
    }

    while ($true) {
        $raw = Read-Host ($PromptText + $hintText)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $defaultValue
        }

        $value = $raw.Trim().ToLowerInvariant()
        if ($value -in @('y', 'yes')) {
            return 'yes'
        }
        if ($value -in @('n', 'no')) {
            return 'no'
        }
        if ($value -in @('c', 'cancel')) {
            return 'cancel'
        }

        Write-Host "Please answer yes, no, or cancel." -ForegroundColor Yellow
    }
}

# Handles Confirm-YesNoCancel.
function Confirm-YesNoCancel {
    param(
        [string]$PromptText,
        [string]$DefaultChoice = 'yes'
    )

    $normalizedDefault = [string]$DefaultChoice
    if ([string]::IsNullOrWhiteSpace([string]$normalizedDefault)) {
        $normalizedDefault = 'yes'
    }
    $normalizedDefault = $normalizedDefault.Trim().ToLowerInvariant()
    if ($normalizedDefault -notin @('yes', 'no', 'cancel')) {
        $normalizedDefault = 'yes'
    }

    $hintText = switch ($normalizedDefault) {
        'yes' { ' [Y/n/c]' }
        'no' { ' [y/N/c]' }
        default { ' [y/n/C]' }
    }

    while ($true) {
        $raw = Read-Host ($PromptText + $hintText)
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $normalizedDefault
        }

        $value = $raw.Trim().ToLowerInvariant()
        if ($value -in @('y', 'yes')) {
            return 'yes'
        }
        if ($value -in @('n', 'no')) {
            return 'no'
        }
        if ($value -in @('c', 'cancel')) {
            return 'cancel'
        }

        Write-Host "Please answer yes, no, or cancel." -ForegroundColor Yellow
    }
}

# Handles Invoke-TrackedAction.
function Invoke-TrackedAction {
    param(
        [string]$Label,
        [scriptblock]$Action
    )

    if ([string]::IsNullOrWhiteSpace($Label)) {
        $Label = "action"
    }

    $isAzLabel = ([string]$Label).TrimStart().ToLowerInvariant().StartsWith("az ")
    if (-not $isAzLabel -or [int]$script:ClagnosTrackedAzureActionDepth -le 0) {
        Write-ClagnosActionProgress -Action $Label
    }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    if ($isAzLabel) {
        $script:ClagnosTrackedAzureActionDepth = [int]$script:ClagnosTrackedAzureActionDepth + 1
        $script:PerfSuppressAzTimingDepth = [int]$script:PerfSuppressAzTimingDepth + 1
    }
    try {
        $result = . $Action
        if ($null -ne $result) {
            return $result
        }
    }
    finally {
        if ($isAzLabel) {
            $script:ClagnosTrackedAzureActionDepth = [Math]::Max(0, ([int]$script:ClagnosTrackedAzureActionDepth - 1))
            $script:PerfSuppressAzTimingDepth = [Math]::Max(0, ([int]$script:PerfSuppressAzTimingDepth - 1))
        }
        if ($watch.IsRunning) {
            $watch.Stop()
        }
        if (-not $script:ClagnosQuietOutput) {
            Write-Host ("completed: {0} ({1:N1}s)" -f $Label, $watch.Elapsed.TotalSeconds) -ForegroundColor DarkCyan
        }
    }
}
