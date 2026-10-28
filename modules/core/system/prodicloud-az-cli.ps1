# Shared repo/system/Azure CLI helpers.

# Handles Get-ProdicloudRepoRoot.
function Get-ProdicloudRepoRoot {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudRepoRoot) -and (Test-Path -LiteralPath ([string]$script:ProdicloudRepoRoot))) {
        return [string]$script:ProdicloudRepoRoot
    }

    $repoRootCandidate = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    $script:ProdicloudRepoRoot = [string]$repoRootCandidate
    return [string]$script:ProdicloudRepoRoot
}

# Handles Convert-ProdicloudPerfSecondsText.
function Convert-ProdicloudPerfSecondsText {
    param(
        [double]$Seconds
    )

    if ($Seconds -lt 0) {
        $Seconds = 0
    }

    return ("{0:N1} seconds" -f [double]$Seconds)
}

# Handles Write-ProdicloudPerfTiming.
function Write-ProdicloudPerfTiming {
    param(
        [string]$Category,
        [string]$Label,
        [double]$Seconds
    )

    if (-not $script:PerfMode -or $script:ProdicloudQuietOutput) {
        return
    }

    $categoryText = if ([string]::IsNullOrWhiteSpace([string]$Category)) { "metric" } else { ([string]$Category).Trim() }
    $labelText = if ([string]::IsNullOrWhiteSpace([string]$Label)) { "operation" } else { ([string]$Label).Trim() }
    if ($labelText.Length -gt 240) {
        $labelText = $labelText.Substring(0, 237) + "..."
    }

    $durationText = Convert-ProdicloudPerfSecondsText -Seconds $Seconds
    Write-Host ("perf: {0} -> {1} ({2})" -f $categoryText, $labelText, $durationText) -ForegroundColor DarkGray
}

# Handles Get-ProdicloudAzCliExecutable.
function Get-ProdicloudAzCliExecutable {
    if (-not [string]::IsNullOrWhiteSpace([string]$script:AzCliExecutable)) {
        return [string]$script:AzCliExecutable
    }

    $azApps = @(Get-Command az -All -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' -and -not [string]::IsNullOrWhiteSpace([string]$_.Source) })
    $azApp = $null
    if ($azApps.Count -gt 0) {
        $azApp = @($azApps | Where-Object { -not ([string]$_.Source).ToLowerInvariant().EndsWith('.cmd') -and -not ([string]$_.Source).ToLowerInvariant().EndsWith('.bat') } | Select-Object -First 1)
        if ($null -eq $azApp -or @($azApp).Count -eq 0) {
            $azApp = @($azApps | Select-Object -First 1)
        }
        if ($azApp -is [System.Array]) {
            $azApp = [object]$azApp[0]
        }
    }
    if ($null -eq $azApp -or [string]::IsNullOrWhiteSpace([string]$azApp.Source)) {
        throw "Azure CLI executable could not be resolved from PATH."
    }

    $script:AzCliExecutable = [string]$azApp.Source
    return [string]$script:AzCliExecutable
}

function Resolve-ProdicloudAzCliLaunchInfo {
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [string[]]$Arguments = @(),
        [ValidateRange(1000,8000)][int]$CommandHostLengthLimit = 7000
    )
    $resolvedExecutable = [string]$ExecutablePath
    $useCmdHost = -not $resolvedExecutable.ToLowerInvariant().EndsWith('.exe')
    $prefixArguments = @()
    $argumentLength = 0
    foreach ($argument in @($Arguments)) { $argumentLength += ([string]$argument).Length + 1 }
    $routedToEmbeddedPython = $false
    if ($useCmdHost -and $argumentLength -gt $CommandHostLengthLimit) {
        $wbinPath = [System.IO.Path]::GetDirectoryName($resolvedExecutable)
        $azureCliRoot = [System.IO.Path]::GetDirectoryName($wbinPath)
        $pythonPath = if ([string]::IsNullOrWhiteSpace([string]$azureCliRoot)) { '' } else { Join-Path $azureCliRoot 'python.exe' }
        if ([string]::IsNullOrWhiteSpace($pythonPath) -or -not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
            throw ("Azure CLI request has {0} characters, beyond the safe Windows command-host limit, and its embedded Python runtime was not found beside '{1}'." -f $argumentLength,$resolvedExecutable)
        }
        $resolvedExecutable = [string]$pythonPath
        $useCmdHost = $false
        $prefixArguments = @('-IBm','azure.cli')
        $routedToEmbeddedPython = $true
    }
    if (($argumentLength + 256) -ge 30000) { throw ("Azure CLI request has {0} argument characters and exceeds the safe direct process limit." -f $argumentLength) }
    return [pscustomobject]@{
        ExecutablePath = $resolvedExecutable
        UseCmdHost = [bool]$useCmdHost
        PrefixArguments = @($prefixArguments)
        ArgumentLength = [int]$argumentLength
        RoutedToEmbeddedPython = [bool]$routedToEmbeddedPython
    }
}

function Get-ProdicloudAzCliProgressLabel {
    param([string[]]$Arguments)

    $safeTokens = @()
    $safeCommandWords = @(
        'account','ad','aks','appconfig','backup','capacity','cloud','compute','deployment','disk','extension','feature','group','image','keyvault','lock','monitor','network','nsg','nic','operation','policy','public-ip','quota','resource','resource-mover','rest','role','rule','snapshot','storage','subnet','vm','vnet','workspace',
        'access','account','assign','create','deallocate','delete','discard','enable','extension','get-access-token','image','invoke','list','list-locations','list-skus','move-collection','move-resource','public-ip','resize','restart','revoke-access','rule','run-command','set','show','start','stop','subnet','update','wait','ip-config'
    )
    foreach ($argument in @($Arguments)) {
        $token = [string]$argument
        if ([string]::IsNullOrWhiteSpace($token) -or $token.StartsWith('-')) { break }
        if ($safeCommandWords -notcontains $token.ToLowerInvariant()) { break }
        $safeTokens += $token
        if ($safeTokens.Count -ge 4) { break }
    }
    if ($safeTokens.Count -eq 0) { return 'az request' }

    $label = 'az ' + ($safeTokens -join ' ')
    if ([string]::Equals([string]$safeTokens[0], 'rest', [System.StringComparison]::OrdinalIgnoreCase)) {
        $methodIndex = [Array]::IndexOf([string[]]$Arguments, '--method')
        if ($methodIndex -ge 0 -and $methodIndex + 1 -lt @($Arguments).Count) {
            $method = [string]$Arguments[$methodIndex + 1]
            if ($method -match '^(?i)(get|post|put|patch|delete|head|options)$') { $label = 'az rest ' + $method.ToUpperInvariant() }
        }
    }
    return $label
}

# Handles Invoke-ProdicloudAzCliCommand.
function Invoke-ProdicloudAzCliCommand {
    param(
        [string[]]$Arguments
    )

    $argValues = @($Arguments | ForEach-Object { [string]$_ })
    $bypassSubscription = ($script:BypassAzCliSubscription -and ([int]$script:BypassAzCliSubscription -gt 0))
    if (-not $bypassSubscription -and -not [string]::IsNullOrWhiteSpace([string]$script:ProdicloudActiveSubscriptionId)) {
        $hasSubscriptionArgument = $false
        foreach ($argValue in @($argValues)) {
            $candidate = [string]$argValue
            if ([string]::Equals($candidate, '--subscription', [System.StringComparison]::OrdinalIgnoreCase) -or
                $candidate.StartsWith('--subscription=', [System.StringComparison]::OrdinalIgnoreCase)) {
                $hasSubscriptionArgument = $true
                break
            }
        }
        if (-not $hasSubscriptionArgument) {
            $argValues += @('--subscription', [string]$script:ProdicloudActiveSubscriptionId)
        }
    }

    $perfWatch = $null
    $perfLabel = Get-ProdicloudAzCliProgressLabel -Arguments $argValues
    if ($script:PerfMode -and ([int]$script:PerfSuppressAzTimingDepth -le 0)) {
        $perfWatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    if ([int]$script:ProdicloudTrackedAzureActionDepth -le 0) {
        Write-ProdicloudActionProgress -Action $perfLabel
    }

    try {
        $azExecutable = Get-ProdicloudAzCliExecutable
        $timeoutSeconds = [int]$script:AzCommandTimeoutSeconds
        if ($timeoutSeconds -lt 0) { $timeoutSeconds = 0 }
        $azExecutableText = [string]$azExecutable
        $launchInfo = Resolve-ProdicloudAzCliLaunchInfo -ExecutablePath $azExecutableText -Arguments $argValues
        $cmdHost = if ([string]::IsNullOrWhiteSpace([string]$env:ComSpec)) { 'cmd.exe' } else { [string]$env:ComSpec }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ([bool]$launchInfo.UseCmdHost) {
            $psi.FileName = $cmdHost
            $cmdArgs = @('/d', '/c', $azExecutableText)
            $cmdArgs += $argValues
            $psi.Arguments = ($cmdArgs | ForEach-Object { Convert-ProdicloudProcessArgument -Value ([string]$_) }) -join ' '
        }
        else {
            $psi.FileName = [string]$launchInfo.ExecutablePath
            $directArguments = @($launchInfo.PrefixArguments) + @($argValues)
            $psi.Arguments = ($directArguments | ForEach-Object { Convert-ProdicloudProcessArgument -Value ([string]$_) }) -join ' '
        }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi
        [void]$proc.Start()

        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $elapsedSeconds = 0.0
        $lastProgressSeconds = 0
        while (-not $proc.WaitForExit(1000)) {
            $elapsedSeconds += 1.0
            if ($elapsedSeconds -ge 30 -and (($elapsedSeconds - $lastProgressSeconds) -ge 30)) {
                $lastProgressSeconds = $elapsedSeconds
                Write-ProdicloudActionProgress -Action ("{0} (still running; {1:N0}s elapsed)" -f $perfLabel, $elapsedSeconds)
            }
            if ($timeoutSeconds -gt 0 -and $elapsedSeconds -ge $timeoutSeconds) {
                try { $proc.Kill() } catch { }
                try { [void]$proc.WaitForExit() } catch { }
                $global:LASTEXITCODE = 124
                throw ("az command timed out after {0} second(s)." -f $timeoutSeconds)
            }
        }

        [void]$proc.WaitForExit()
        $stdoutText = ""
        $stderrText = ""
        try { $stdoutText = [string]$stdoutTask.Result } catch { }
        try { $stderrText = [string]$stderrTask.Result } catch { }
        $global:LASTEXITCODE = [int]$proc.ExitCode

        $suppressAzStderrEcho = $false
        if ($script:SuppressAzCliStderrEcho) {
            $suppressAzStderrEcho = $true
        }
        if ((-not $suppressAzStderrEcho) -and -not $script:ProdicloudQuietOutput -and -not [string]::IsNullOrWhiteSpace($stderrText)) {
            Write-Host ($stderrText.TrimEnd())
        }

        if ([string]::IsNullOrWhiteSpace($stdoutText)) {
            return @()
        }

        $stdoutLines = @($stdoutText -split "`r?`n" | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($stdoutLines.Count -eq 0) {
            return @()
        }
        if ($stdoutLines.Count -eq 1) {
            return [string]$stdoutLines[0]
        }

        return $stdoutLines
    }
    finally {
        if ($null -ne $perfWatch -and $perfWatch.IsRunning) {
            $perfWatch.Stop()
        }
    }
}

# Handles Invoke-ProdicloudWithBypassedAzCliSubscription.
function Invoke-ProdicloudWithBypassedAzCliSubscription {
    param(
        [scriptblock]$Action
    )

    if ($null -eq $Action) {
        throw 'Invoke-ProdicloudWithBypassedAzCliSubscription requires an action.'
    }

    $previousDepth = 0
    if ($script:BypassAzCliSubscription) {
        $previousDepth = [int]$script:BypassAzCliSubscription
    }

    $script:BypassAzCliSubscription = $previousDepth + 1
    try {
        return (& $Action)
    }
    finally {
        if ($previousDepth -gt 0) {
            $script:BypassAzCliSubscription = $previousDepth
        }
        else {
            $script:BypassAzCliSubscription = 0
        }
    }
}

# Handles Invoke-ProdicloudWithSuppressedAzCliStderr.
function Invoke-ProdicloudWithSuppressedAzCliStderr {
    param(
        [scriptblock]$Action
    )

    $previousValue = $false
    if ($script:SuppressAzCliStderrEcho) {
        $previousValue = $true
    }

    $script:SuppressAzCliStderrEcho = $true
    try {
        return (& $Action)
    }
    finally {
        $script:SuppressAzCliStderrEcho = $previousValue
    }
}

# Handles Invoke-ProdicloudWithAzCliTimeoutSeconds.
function Invoke-ProdicloudWithAzCliTimeoutSeconds {
    param(
        [int]$TimeoutSeconds,
        [scriptblock]$Action
    )

    if ($null -eq $Action) {
        throw 'Invoke-ProdicloudWithAzCliTimeoutSeconds requires an action.'
    }

    $previousTimeoutSeconds = [int]$script:AzCommandTimeoutSeconds
    $effectiveTimeoutSeconds = [int]$TimeoutSeconds
    if ($effectiveTimeoutSeconds -lt 30) {
        $effectiveTimeoutSeconds = 30
    }
    if ($effectiveTimeoutSeconds -lt $previousTimeoutSeconds) {
        $effectiveTimeoutSeconds = $previousTimeoutSeconds
    }
    if ($effectiveTimeoutSeconds -gt 7200) {
        $effectiveTimeoutSeconds = 7200
    }

    $script:AzCommandTimeoutSeconds = $effectiveTimeoutSeconds
    try {
        return (& $Action)
    }
    finally {
        $script:AzCommandTimeoutSeconds = $previousTimeoutSeconds
    }
}

# Handles az.
function az {
    $argList = @()
    foreach ($arg in @($args)) {
        $argList += [string]$arg
    }

    return (Invoke-ProdicloudAzCliCommand -Arguments $argList)
}

# Handles Invoke-ProdicloudHttpRestMethod.
function Invoke-ProdicloudHttpRestMethod {
    param(
        [ValidateSet("Get","Post","Put","Delete","Patch","Head","Options")]
        [string]$Method = "Get",
        [string]$Uri,
        [hashtable]$Headers,
        [AllowNull()]
        [object]$Body,
        [string]$PerfLabel = "http request"
    )

    if ([string]::IsNullOrWhiteSpace([string]$Uri)) {
        throw "HTTP request URI is required."
    }

    Write-ProdicloudActionProgress -Action ("send HTTP {0} request ({1})" -f [string]$Method,[string]$PerfLabel)

    $requestTimeoutSeconds = 1800
    $invokeParams = @{
        Method = [string]$Method
        Uri = [string]$Uri
        ErrorAction = 'Stop'
    }
    if ($null -ne $Headers) { $invokeParams['Headers'] = $Headers }
    if ($PSBoundParameters.ContainsKey('Body')) { $invokeParams['Body'] = $Body }
    $invokeParams['TimeoutSec'] = $requestTimeoutSeconds
    $httpJob = Start-Job -ScriptBlock {
        param([hashtable]$RequestParameters)
        $ErrorActionPreference = 'Stop'
        Invoke-RestMethod @RequestParameters
    } -ArgumentList (,$invokeParams)
    $watch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $elapsedSeconds = 0
        $lastHeartbeatSeconds = 0
        $completed = $null
        while ($elapsedSeconds -lt $requestTimeoutSeconds) {
            $completed = Wait-Job -Job $httpJob -Timeout 1
            if ($null -ne $completed -or [string]$httpJob.State -in @('Completed','Failed','Stopped')) { break }
            $elapsedSeconds++
            if ($elapsedSeconds -ge 30 -and ($elapsedSeconds - $lastHeartbeatSeconds) -ge 30) {
                $lastHeartbeatSeconds = $elapsedSeconds
                Write-ProdicloudActionProgress -Action ("HTTP {0} request ({1}) is still running; {2}s elapsed" -f [string]$Method,[string]$PerfLabel,$elapsedSeconds)
            }
        }
        if ($null -eq $completed -and [string]$httpJob.State -in @('Completed','Failed','Stopped')) { $completed = $httpJob }
        if (-not $completed) {
            Stop-Job -Job $httpJob -Force -ErrorAction SilentlyContinue | Out-Null
            throw ("HTTP {0} request timed out after {1}s ({2})." -f [string]$Method,$requestTimeoutSeconds,[string]$PerfLabel)
        }
        return (Receive-Job -Job $httpJob -ErrorAction Stop)
    }
    finally {
        if ($null -ne $watch -and $watch.IsRunning) {
            $watch.Stop()
        }
        if ($script:PerfMode -and $null -ne $watch) { Write-ProdicloudPerfTiming -Category "http" -Label $PerfLabel -Seconds $watch.Elapsed.TotalSeconds }
        Remove-Job -Job $httpJob -Force -ErrorAction SilentlyContinue | Out-Null
    }
}
