$ErrorActionPreference = 'Stop'

$sessionEnvironmentHelperPath = 'C:\Windows\Temp\prodicloud-session-environment.psm1'
if (Test-Path -LiteralPath $sessionEnvironmentHelperPath) {
    Import-Module $sessionEnvironmentHelperPath -Force -DisableNameChecking
}

function Invoke-ProdicloudRefreshSessionPath {
    if (Get-Command Refresh-ProdicloudSessionPath -ErrorAction SilentlyContinue) {
        return (Refresh-ProdicloudSessionPath)
    }

    $machinePath = [Environment]::ExpandEnvironmentVariables([string][Environment]::GetEnvironmentVariable('Path', 'Machine'))
    $userPath = [Environment]::ExpandEnvironmentVariables([string][Environment]::GetEnvironmentVariable('Path', 'User'))
    if ([string]::IsNullOrWhiteSpace([string]$userPath)) {
        $env:Path = [string]$machinePath
    }
    else {
        $env:Path = ("{0};{1}" -f [string]$machinePath, [string]$userPath).Trim(';')
    }
}

function Resolve-ProdicloudWingetExe {
    param(
        [string]$PortableCandidate = 'C:\ProgramData\prodicloud\tools\winget-x64\winget.exe'
    )

    if (-not [string]::IsNullOrWhiteSpace([string]$PortableCandidate) -and (Test-Path -LiteralPath $PortableCandidate)) {
        return [string]$PortableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ''
}

function Get-ProdicloudStoreInstallStateRoot {
    $rootPath = 'C:\ProgramData\prodicloud\state\store-installs'
    if (-not (Test-Path -LiteralPath $rootPath)) {
        New-Item -Path $rootPath -ItemType Directory -Force | Out-Null
    }

    return [string]$rootPath
}

function Get-ProdicloudStoreInstallStatePath {
    param([string]$TaskName)

    if ([string]::IsNullOrWhiteSpace([string]$TaskName)) {
        throw 'Store install state task name is empty.'
    }

    $safeName = (([string]$TaskName -replace '[^A-Za-z0-9\-]', '-').Trim('-'))
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
        $safeName = 'task'
    }

    return (Join-Path (Get-ProdicloudStoreInstallStateRoot) ($safeName + '.json'))
}

function Get-ProdicloudStoreInstallStateCandidateTaskNames {
    param([string]$TaskName)

    $candidateTaskNames = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace([string]$TaskName)) {
        [void]$candidateTaskNames.Add([string]$TaskName)
    }

    switch ([string]$TaskName) {
        '114-install-teams-application' {
            foreach ($legacyTaskName in @('117-install-teams-application', '118-install-teams-application')) {
                [void]$candidateTaskNames.Add([string]$legacyTaskName)
            }
        }
        '118-install-be-my-eyes-application-application' {
            foreach ($legacyTaskName in @('125-install-be-my-eyes-application', '126-install-be-my-eyes-application')) {
                [void]$candidateTaskNames.Add([string]$legacyTaskName)
            }
        }
        '119-install-whatsapp-application' {
            foreach ($legacyTaskName in @('120-install-whatsapp-application', '121-install-whatsapp-application')) {
                [void]$candidateTaskNames.Add([string]$legacyTaskName)
            }
        }
        '120-install-codex-application' {
            [void]$candidateTaskNames.Add('116-install-codex-application')
        }
        '122-install-icloud-application' {
            foreach ($legacyTaskName in @('129-install-icloud-application', '131-install-icloud-application')) {
                [void]$candidateTaskNames.Add([string]$legacyTaskName)
            }
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $resolved = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidateTaskName in @($candidateTaskNames)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidateTaskName)) {
            continue
        }

        if ($seen.Add([string]$candidateTaskName)) {
            [void]$resolved.Add([string]$candidateTaskName)
        }
    }

    return @($resolved.ToArray())
}

function Read-ProdicloudStoreInstallState {
    param([string]$TaskName)

    foreach ($candidateTaskName in @(Get-ProdicloudStoreInstallStateCandidateTaskNames -TaskName $TaskName)) {
        $statePath = Get-ProdicloudStoreInstallStatePath -TaskName $candidateTaskName
        if (-not (Test-Path -LiteralPath $statePath)) {
            continue
        }

        $stateText = [string](Get-Content -LiteralPath $statePath -Raw -ErrorAction SilentlyContinue)
        if ([string]::IsNullOrWhiteSpace([string]$stateText)) {
            continue
        }

        try {
            $stateRecord = ConvertFrom-Json -InputObject $stateText -ErrorAction Stop
            if ($null -ne $stateRecord) {
                if ($stateRecord.PSObject.Properties.Match('requestedTaskName').Count -lt 1) {
                    $stateRecord | Add-Member -NotePropertyName requestedTaskName -NotePropertyValue ([string]$TaskName)
                }
                if ($stateRecord.PSObject.Properties.Match('resolvedTaskName').Count -lt 1) {
                    $stateRecord | Add-Member -NotePropertyName resolvedTaskName -NotePropertyValue ([string]$candidateTaskName)
                }
            }

            return $stateRecord
        }
        catch {
            continue
        }
    }

    return $null
}

function Remove-ProdicloudStoreInstallState {
    param([string]$TaskName)

    $statePath = Get-ProdicloudStoreInstallStatePath -TaskName $TaskName
    if (Test-Path -LiteralPath $statePath) {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
}

function Write-ProdicloudStoreInstallState {
    param(
        [string]$TaskName,
        [ValidateSet('installed','degraded','skipped')]
        [string]$State,
        [string]$Summary,
        [string]$PackageId = '',
        [string]$RunOnceName = '',
        [string]$LaunchTarget = '',
        [string]$LaunchKind = '',
        [string]$InstallSource = 'msstore'
    )

    $statePath = Get-ProdicloudStoreInstallStatePath -TaskName $TaskName
    $runOnceRegistered = $false
    if (-not [string]::IsNullOrWhiteSpace([string]$RunOnceName)) {
        $runOnceRegistered = Test-ProdicloudRunOnceEntryPresent -Name $RunOnceName
    }

    $payload = [ordered]@{
        taskName = [string]$TaskName
        state = [string]$State
        summary = [string]$Summary
        packageId = [string]$PackageId
        installSource = [string]$InstallSource
        runOnceName = [string]$RunOnceName
        runOnceRegistered = [bool]$runOnceRegistered
        launchKind = [string]$LaunchKind
        launchTarget = [string]$LaunchTarget
        updatedAtUtc = ((Get-Date).ToUniversalTime().ToString('o'))
    }

    $json = ($payload | ConvertTo-Json -Depth 6)
    Set-Content -LiteralPath $statePath -Value $json -Encoding UTF8
    return ([pscustomobject]$payload)
}

function Write-ProdicloudStoreInstallStateStatusLine {
    param(
        [string]$TaskName,
        [AllowNull()]
        [psobject]$StateRecord
    )

    if ($null -eq $StateRecord) {
        Write-Host ("store-install-state => task={0}; state=none" -f [string]$TaskName)
        return
    }

    $summary = ''
    if ($StateRecord.PSObject.Properties.Match('summary').Count -gt 0) {
        $summary = [string]$StateRecord.summary
    }
    $launchKind = ''
    if ($StateRecord.PSObject.Properties.Match('launchKind').Count -gt 0) {
        $launchKind = [string]$StateRecord.launchKind
    }
    $runOnceRegistered = $false
    if ($StateRecord.PSObject.Properties.Match('runOnceRegistered').Count -gt 0) {
        $runOnceRegistered = [bool]$StateRecord.runOnceRegistered
    }

    Write-Host ("store-install-state => task={0}; state={1}; launch-kind={2}; run-once={3}; summary={4}" -f [string]$TaskName, [string]$StateRecord.state, $launchKind, [bool]$runOnceRegistered, $summary)
}

function Test-ProdicloudRunOnceEntryPresent {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace([string]$Name)) {
        return $false
    }

    $runOncePath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    if (-not (Test-Path -LiteralPath $runOncePath)) {
        return $false
    }

    $property = Get-ItemProperty -Path $runOncePath -Name ([string]$Name) -ErrorAction SilentlyContinue
    if ($null -eq $property) {
        return $false
    }

    $value = $property.PSObject.Properties[[string]$Name].Value
    return (-not [string]::IsNullOrWhiteSpace([string]$value))
}

function Remove-ProdicloudRunOnceEntry {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace([string]$Name)) {
        return
    }

    $runOncePath = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    if (-not (Test-Path -LiteralPath $runOncePath)) {
        return
    }

    Remove-ItemProperty -Path $runOncePath -Name ([string]$Name) -ErrorAction SilentlyContinue
}

function Test-ProdicloudStoreInstallNeedsInteractiveCompletion {
    param(
        [string]$MessageText,
        [bool]$TimedOut = $false
    )

    if ([bool]$TimedOut) {
        return $true
    }

    if ([string]::IsNullOrWhiteSpace([string]$MessageText)) {
        return $false
    }

    return ([string]$MessageText -match '(?i)0x80070520|logon session|microsoft store|msstore|interactive')
}

Export-ModuleMember -Function @(
    'Invoke-ProdicloudRefreshSessionPath',
    'Resolve-ProdicloudWingetExe',
    'Get-ProdicloudStoreInstallStateRoot',
    'Get-ProdicloudStoreInstallStatePath',
    'Read-ProdicloudStoreInstallState',
    'Remove-ProdicloudStoreInstallState',
    'Write-ProdicloudStoreInstallState',
    'Write-ProdicloudStoreInstallStateStatusLine',
    'Test-ProdicloudRunOnceEntryPresent',
    'Remove-ProdicloudRunOnceEntry',
    'Test-ProdicloudStoreInstallNeedsInteractiveCompletion'
)
