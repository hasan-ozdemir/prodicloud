$ErrorActionPreference = 'Stop'
$taskConfig = [ordered]@{
    ManagerUser = '__VM_ADMIN_USER__'
    ManagerPassword = '__VM_ADMIN_PASS__'
    InteractiveHelperPath = 'C:\Windows\Temp\prodicloud-interactive-session-helper.ps1'
    TaskName = '112-windscribe-unattended-two-phase-uninstall'
    TaskTimeoutSeconds = 480
    SecondPhaseTimeoutSeconds = 450
    AbsenceVerificationSeconds = 10
    UninstallerPath = 'C:\Program Files\Windscribe\uninstall.exe'
}
$packageSpec = '__PRODICLOUD_PACKAGE_SPEC_B64__'

if (-not (Test-Path -LiteralPath ([string]$taskConfig.InteractiveHelperPath) -PathType Leaf)) {
    throw 'The bounded Windows task helper required to run Windscribe unattended was not staged.'
}
. ([string]$taskConfig.InteractiveHelperPath)
Import-Module 'C:\Windows\Temp\prodicloud-package-operations.psm1' -Force -DisableNameChecking -ErrorAction Stop

if (-not (Test-Path -LiteralPath ([string]$taskConfig.UninstallerPath) -PathType Leaf)) {
    throw 'The signed Windscribe uninstaller is missing; no package removal was attempted.'
}
$launcherSignature = Get-AuthenticodeSignature -FilePath ([string]$taskConfig.UninstallerPath) -ErrorAction Stop
$launcherSigner = if ($null -ne $launcherSignature.SignerCertificate) { [string]$launcherSignature.SignerCertificate.Subject } else { '' }
if ([string]$launcherSignature.Status -ne 'Valid' -or $launcherSigner -notmatch '(?i)O=Windscribe Limited') {
    throw ('Windscribe uninstaller signature verification failed (status: {0}); no package removal was attempted.' -f [string]$launcherSignature.Status)
}

$firewallState = Get-ProdicloudWindscribeUnattendedFirewallState
if ($null -eq $firewallState -or [string]$firewallState.State -ne 'Off') {
    $reason = if ($null -ne $firewallState) { [string]$firewallState.Source } else { 'state reader returned no result' }
    $stateLabel = if ($null -ne $firewallState) { [string]$firewallState.State } else { 'unknown' }
    throw ("Windscribe uninstall requires a verified firewall-off state. Observed '{0}' ({1}); no package or firewall mutation was attempted." -f $stateLabel,$reason)
}

$windscribeSettingsPath = 'Registry::HKEY_CURRENT_USER\Software\Windscribe\Windscribe2'
if (Test-Path -LiteralPath $windscribeSettingsPath) {
    $windscribeSettings = Get-ItemProperty -LiteralPath $windscribeSettingsPath -ErrorAction SilentlyContinue
    $userId = if ($null -ne $windscribeSettings.PSObject.Properties['userId']) { [string]$windscribeSettings.userId } else { '' }
    if ($userId -match '^[A-Za-z0-9]+$') {
        throw 'The signed Windscribe uninstaller would launch its vendor feedback page for this logged-in account; no browser or package mutation was started.'
    }
}
Write-Output ("Doing: verified unattended Windscribe firewall state is Off ({0})" -f [string]$firewallState.Source)

$interactivePaths = Get-ProdicloudInteractivePaths -TaskName ([string]$taskConfig.TaskName)
$workerScript = @'
$ErrorActionPreference = 'Stop'
$taskName = '__WINDSCRIBE_TASK_NAME__'
$resultPath = '__WINDSCRIBE_RESULT_PATH__'
$uninstallerPath = 'C:\Program Files\Windscribe\uninstall.exe'
$expectedInstallRoot = [IO.Path]::GetFullPath('C:\Program Files\Windscribe').TrimEnd('\') + '\'
$uninstallerTimeoutSeconds = 20
$secondPhaseTimeoutSeconds = 450
$absenceVerificationSeconds = 10
. 'C:\Windows\Temp\prodicloud-interactive-session-helper.ps1'
Import-Module 'C:\Windows\Temp\prodicloud-package-operations.psm1' -Force -DisableNameChecking -ErrorAction Stop
Stop-ProdicloudStaleWindscribeUninstallerProcesses -MaximumAgeSeconds 480 -WaitTimeoutSeconds 60

function Get-WindscribeWorkerFirewallState {
    $module = Get-Module -Name 'prodicloud-package-operations' -ErrorAction SilentlyContinue
    if ($null -eq $module) { $module = Import-Module 'C:\Windows\Temp\prodicloud-package-operations.psm1' -Force -DisableNameChecking -PassThru -ErrorAction Stop }
    return (& $module { Get-ProdicloudWindscribeUnattendedFirewallState })
}

function Get-WindscribeWorkerResultSummary {
    param([string]$Text)
    $safe = [string]$Text
    $safe = [regex]::Replace($safe,'(?im)^.*(?:email|username|password|token|data usage|public ip|ip address).*$','[redacted account/network status]')
    $safe = [regex]::Replace($safe,'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b','[redacted-email]',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $safe = [regex]::Replace($safe,'\b(?:\d{1,3}\.){3}\d{1,3}\b','[redacted-ip]')
    $safe = [regex]::Replace($safe,'(?i)C:\\Users\\[^\\\s]+','C:\\Users\\<profile>')
    if ($safe.Length -gt 1000) { $safe = $safe.Substring(0,1000) }
    return $safe.Trim()
}

function Start-WindscribeServiceIfStillInstalled {
    if (-not (Test-Path -LiteralPath 'C:\Program Files\Windscribe\Windscribe.exe' -PathType Leaf)) { return }
    foreach ($service in @(Get-CimInstance Win32_Service -Filter "Name LIKE '%Windscribe%' OR DisplayName LIKE '%Windscribe%'" -ErrorAction SilentlyContinue | Where-Object { [string]$_.StartMode -ne 'Disabled' -and [string]$_.State -ne 'Running' })) {
        Write-Output ('Doing: restore Windscribe service {0} after an incomplete uninstall' -f [string]$service.Name)
        Start-Service -Name ([string]$service.Name) -ErrorAction Stop
    }
}

try {
    $activeFirewall = Get-WindscribeWorkerFirewallState
    if ($null -eq $activeFirewall -or [string]$activeFirewall.State -ne 'Off') {
        $state = if ($null -ne $activeFirewall) { [string]$activeFirewall.State } else { 'unknown' }
        $source = if ($null -ne $activeFirewall) { [string]$activeFirewall.Source } else { 'no state result' }
        throw ("Windscribe firewall-off state did not verify in the manager task (state={0}; source={1}); no uninstaller was started." -f $state,$source)
    }

    $settingsPath = 'Registry::HKEY_CURRENT_USER\Software\Windscribe\Windscribe2'
    if (Test-Path -LiteralPath $settingsPath) {
        $settings = Get-ItemProperty -LiteralPath $settingsPath -ErrorAction SilentlyContinue
        $userId = if ($null -ne $settings.PSObject.Properties['userId']) { [string]$settings.userId } else { '' }
        if ($userId -match '^[A-Za-z0-9]+$') { throw 'The vendor uninstaller would launch its account feedback page; no browser or package change was started.' }
    }

    $signature = Get-AuthenticodeSignature -FilePath $uninstallerPath -ErrorAction Stop
    $signer = if ($null -ne $signature.SignerCertificate) { [string]$signature.SignerCertificate.Subject } else { '' }
    if ([string]$signature.Status -ne 'Valid' -or $signer -notmatch '(?i)O=Windscribe Limited') { throw ('Uninstaller Authenticode validation failed (status: {0}).' -f [string]$signature.Status) }

    Write-Output 'Doing: start the signed Windscribe first-phase uninstaller with /VERYSILENT'
    $launcher = Start-Process -FilePath $uninstallerPath -ArgumentList @('/VERYSILENT') -WorkingDirectory (Split-Path -Parent $uninstallerPath) -WindowStyle Hidden -PassThru -ErrorAction Stop
    $launcherDeadline = [DateTime]::UtcNow.AddSeconds([int]$uninstallerTimeoutSeconds)
    while (-not $launcher.HasExited) {
        if ([DateTime]::UtcNow -ge $launcherDeadline) {
            $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
            if (Test-Path -LiteralPath $taskkill -PathType Leaf) { & $taskkill /PID ([string]$launcher.Id) /T /F 2>$null | Out-Null }
            throw 'The Windscribe first-phase uninstaller exceeded its 30-second deadline.'
        }
        Start-Sleep -Milliseconds 250
    }
    $launcher.WaitForExit()
    $secondPhasePid = [int]$launcher.ExitCode
    if ($secondPhasePid -eq -1 -or $secondPhasePid -eq [int]::MinValue) { throw 'The Windscribe first phase returned its failure sentinel before starting the uninstall phase.' }

    if ($secondPhasePid -gt 0) {
        Write-Output ("Doing: wait for Windscribe's second-phase process {0} returned by the first phase" -f $secondPhasePid)
        $secondPhaseDeadline = [DateTime]::UtcNow.AddSeconds([int]$secondPhaseTimeoutSeconds)
        $secondPhaseStarted = [DateTime]::UtcNow
        $nextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
        do {
            $secondPhase = @(Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $secondPhasePid) -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($secondPhase.Count -eq 0) { break }
            $secondPath = [string]$secondPhase[0].ExecutablePath
            $secondCommand = [string]$secondPhase[0].CommandLine
            if (-not $secondPath.StartsWith((Join-Path $env:SystemRoot 'Temp\WindscribeUninstaller'),[StringComparison]::OrdinalIgnoreCase) -or
                $secondCommand -notmatch '(?i)/SECONDPHASE=' -or $secondCommand -notmatch '(?i)(?:^|\s)/VERYSILENT(?:\s|$)') {
                throw ("Returned second-phase PID {0} did not match the validated Windscribe temp-path, second-phase, and unattended argument contract." -f $secondPhasePid)
            }
            $secondSignature = Get-AuthenticodeSignature -FilePath $secondPath -ErrorAction Stop
            $secondSigner = if ($null -ne $secondSignature.SignerCertificate) { [string]$secondSignature.SignerCertificate.Subject } else { '' }
            if ([string]$secondSignature.Status -ne 'Valid' -or $secondSigner -notmatch '(?i)O=Windscribe Limited') { throw ('Second-phase uninstaller Authenticode validation failed (status: {0}).' -f [string]$secondSignature.Status) }
            if ([DateTime]::UtcNow -ge $secondPhaseDeadline) {
                $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                if (Test-Path -LiteralPath $taskkill -PathType Leaf) { & $taskkill /PID ([string]$secondPhasePid) /T /F 2>$null | Out-Null }
                throw ("Windscribe second phase exceeded its finite {0}-second deadline." -f $secondPhaseTimeoutSeconds)
            }
            if ([DateTime]::UtcNow -ge $nextHeartbeat) {
                Write-Output ("Doing: Windscribe second phase is still running ({0}s elapsed)" -f [int]([DateTime]::UtcNow - $secondPhaseStarted).TotalSeconds)
                $nextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
            }
            Start-Sleep -Seconds 1
        } while ($true)
    }

    $absenceDeadline = [DateTime]::UtcNow.AddSeconds([int]$absenceVerificationSeconds)
    $nextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
    do {
        $executablePresent = Test-Path -LiteralPath $uninstallerPath -PathType Leaf
        $services = @(Get-CimInstance Win32_Service -Filter "Name LIKE '%Windscribe%' OR DisplayName LIKE '%Windscribe%'" -ErrorAction Stop)
        if (-not $executablePresent -and $services.Count -eq 0) { break }
        if ([DateTime]::UtcNow -ge $absenceDeadline) { break }
        if ([DateTime]::UtcNow -ge $nextHeartbeat) {
            Write-Output ('Doing: verify Windscribe absence; uninstaller-exe={0}; remaining-service-count={1}' -f $executablePresent,$services.Count)
            $nextHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
        }
        Start-Sleep -Seconds 3
    } while ($true)

    if ((Test-Path -LiteralPath $uninstallerPath -PathType Leaf) -or $services.Count -gt 0) {
        Start-WindscribeServiceIfStillInstalled
        throw ('Windscribe second-phase uninstaller completed but executable or service remains after {0}s; absence was not verified.' -f $absenceVerificationSeconds)
    }
    Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'The signed unattended Windscribe second-phase uninstaller completed; application and service absence were verified.'
}
catch {
    Start-WindscribeServiceIfStillInstalled
    Write-ProdicloudInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ([string]$_.Exception.Message)
}
'@
$workerScript = $workerScript.Replace('__WINDSCRIBE_TASK_NAME__',[string]$taskConfig.TaskName)
$workerScript = $workerScript.Replace('__WINDSCRIBE_RESULT_PATH__',[string]$interactivePaths.ResultPath)

$interactiveResult = Invoke-ProdicloudInteractiveDesktopAutomation `
    -TaskName ([string]$taskConfig.TaskName) `
    -RunAsUser ([string]$taskConfig.ManagerUser) `
    -RunAsPassword ([string]$taskConfig.ManagerPassword) `
    -WorkerScriptText $workerScript `
    -WaitTimeoutSeconds ([int]$taskConfig.TaskTimeoutSeconds) `
    -RunAsMode 'password'
if ($null -eq $interactiveResult -or -not [bool]$interactiveResult.Success) {
    $summary = if ($null -ne $interactiveResult) { [string]$interactiveResult.Summary } else { 'no structured result returned' }
    throw ('The unattended Windscribe second-phase uninstaller failed verification: ' + $summary)
}

$previousUninstallMarker = [string]$env:PRODICLOUD_WINDSCRIBE_UNINSTALL_COMPLETED
$env:PRODICLOUD_WINDSCRIBE_UNINSTALL_COMPLETED = 'true'
try { Invoke-ProdicloudPackageLifecycle -Action uninstall -PackageSpecBase64 $packageSpec }
finally { $env:PRODICLOUD_WINDSCRIBE_UNINSTALL_COMPLETED = $previousUninstallMarker }
