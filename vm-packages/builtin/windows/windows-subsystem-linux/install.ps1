$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-wsl-feature"

$taskConfig = [ordered]@{
    ManagerUser = '__VM_ADMIN_USER__'
    ManagerPassword = '__VM_ADMIN_PASS__'
    InteractiveHelperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
    InteractiveTaskName = '121-install-wsl-feature-store-install'
    InteractiveDesktopWaitSeconds = 30
    StoreInstallTimeoutSeconds = 360
}

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = "C:\ProgramData\clagnos\tools\winget-x64\winget.exe"
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Invoke-NativeStep {
    param(
        [string]$Label,
        [scriptblock]$Action,
        [int[]]$AcceptedExitCodes = @(0)
    )

    Write-Host ("Running: {0}" -f $Label)
    $previousErrorActionPreference = $ErrorActionPreference
    $commandOutput = @()
    $exitCode = 0
    try {
        # Native stderr from first-run WSL bootstrap can surface as NativeCommandError records;
        # rely on the command exit code and local filtering instead of letting that abort the task.
        $ErrorActionPreference = 'Continue'
        $commandOutput = @(& $Action 2>&1)
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    foreach ($line in @($commandOutput)) {
        $lineText = [string]$line
        if (-not [string]::IsNullOrWhiteSpace([string]$lineText)) {
            if (Test-WslBenignBootstrapLine -Text $lineText) {
                continue
            }
            Write-Host $lineText
        }
    }
    if (-not ($AcceptedExitCodes -contains $exitCode)) {
        Write-Warning ("{0} returned exit code {1}." -f $Label, $exitCode)
    }
    else {
        Write-Host ("{0} exit code: {1}" -f $Label, $exitCode)
    }
    return $exitCode
}

function Test-WslBenignBootstrapLine {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return $false
    }

    return (
        ([string]$Text -match '^(?i)The Windows Subsystem for Linux is not installed\. You can install by running ''wsl\.exe --install''\.$') -or
        ([string]$Text -match '^(?i)wsl\.exe : The Windows Subsystem for Linux is not installed\. You\s*$') -or
        ([string]$Text -match '^(?i)can install by running ''wsl\.exe --install''\.$') -or
        ([string]$Text -match '^(?i)For more information please visit https://aka\.ms/wslinstall$') -or
        ([string]$Text -match '^(?i)At .+clagnos-task-.*\.ps1:\d+ char:\d+$') -or
        ([string]$Text -match '^(?i)\+\s+wsl\.exe --install --no-distribution$') -or
        ([string]$Text -match '^(?i)\+\s+~+$') -or
        ([string]$Text -match '^(?i)\+\s+CategoryInfo\s+:.*NativeCommandError$') -or
        ([string]$Text -match '^(?i)\+\s+FullyQualifiedErrorId\s+: NativeCommandError$')
    )
}

function Test-WslPackageInstalled {
    $package = @(Get-AppxPackage -AllUsers -Name "MicrosoftCorporationII.WindowsSubsystemForLinux" -ErrorAction SilentlyContinue)
    return (@($package).Count -gt 0)
}

function Install-WslAppxThroughInteractiveSession {
    $helperPath = [string]$taskConfig.InteractiveHelperPath
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
        throw ("The interactive desktop helper asset was not found: {0}" -f $helperPath)
    }
    . $helperPath
    $desktopStatus = Wait-ClagnosUserInteractiveDesktopReady -UserName ([string]$taskConfig.ManagerUser) -WaitSeconds ([int]$taskConfig.InteractiveDesktopWaitSeconds) -PollSeconds 5
    Write-ClagnosInteractiveDesktopStatusLine -Status $desktopStatus
    if (-not [bool]$desktopStatus.Ready) {
        $blockMessage = New-ClagnosInteractiveDesktopBlockMessage -ActivityDescription 'WSL Store package installation' -ExpectedUserName ([string]$taskConfig.ManagerUser) -Status $desktopStatus
        throw ([string]$blockMessage.WarningMessage)
    }

    $workerTaskName = [string]$taskConfig.InteractiveTaskName
    $paths = Get-ClagnosInteractivePaths -TaskName $workerTaskName
    $workerScript = @'
$ErrorActionPreference = 'Stop'
$helperPath = 'C:\Windows\Temp\clagnos-interactive-session-helper.ps1'
$resultPath = '__RESULT_PATH__'
$taskName = '__TASK_NAME__'
. $helperPath

function Resolve-InteractiveWingetPath {
    $command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command winget -ErrorAction SilentlyContinue }
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) { return [string]$command.Source }

    $installerPackages = @()
    try { $installerPackages = @(Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Sort-Object Version -Descending) } catch { }
    if ($installerPackages.Count -eq 0) {
        try { $installerPackages = @(Get-AppxPackage -AllUsers -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue | Sort-Object Version -Descending) } catch { }
    }
    foreach ($installerPackage in @($installerPackages)) {
        if ([string]::IsNullOrWhiteSpace([string]$installerPackage.InstallLocation)) { continue }
        $candidate = Join-Path ([string]$installerPackage.InstallLocation) 'winget.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [string]$candidate }
    }
    return ''
}
$wingetPath = Resolve-InteractiveWingetPath

function Test-WslAppxInstalled {
    return (@(Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForLinux' -ErrorAction SilentlyContinue).Count -gt 0)
}

if (Test-WslAppxInstalled) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary 'The WSL Store package is already registered for the interactive manager user.'
    exit 0
}
if ([string]::IsNullOrWhiteSpace([string]$wingetPath)) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'The Windows Package Manager executable was not found for the interactive WSL installation.'
    exit 1
}

$installOutput = @(& $wingetPath install --id Microsoft.WSL --accept-source-agreements --accept-package-agreements --silent --disable-interactivity 2>&1)
$installExit = [int]$LASTEXITCODE
$installText = (@($installOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
if ($installExit -ne 0 -and $installExit -ne 3010 -and $installExit -ne -1978335189 -and $installExit -ne -1978335159) {
    Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary ("Interactive winget install Microsoft.WSL failed with exit code {0}." -f $installExit) -Details @($installText)
    exit 1
}

$deadline = [DateTime]::UtcNow.AddSeconds(180)
while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-WslAppxInstalled) {
        Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $true -Summary ("WSL Store package is registered for the interactive manager user. wingetExit={0}" -f $installExit)
        exit 0
    }
    Start-Sleep -Seconds 3
}

Write-ClagnosInteractiveResult -ResultPath $resultPath -TaskName $taskName -Success $false -Summary 'The WSL Store package did not register within the bounded wait.' -Details @($installText)
exit 1
'@
    $workerScript = $workerScript.Replace('__RESULT_PATH__',[string]$paths.ResultPath)
    $workerScript = $workerScript.Replace('__TASK_NAME__',$workerTaskName)
    $interactiveResult = Invoke-ClagnosInteractiveDesktopAutomation `
        -TaskName $workerTaskName `
        -RunAsUser ([string]$taskConfig.ManagerUser) `
        -RunAsPassword ([string]$taskConfig.ManagerPassword) `
        -WorkerScriptText $workerScript `
        -WaitTimeoutSeconds ([int]$taskConfig.StoreInstallTimeoutSeconds) `
        -RunAsMode 'interactiveToken'
    if ($null -eq $interactiveResult -or -not [bool]$interactiveResult.Success) {
        throw 'Interactive WSL Store installation did not report a successful result.'
    }
    Write-Host ([string]$interactiveResult.Summary)
}

function Test-WslReady {
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        return $false
    }

    $previousErrorActionPreference = $ErrorActionPreference
    $wslVersionOutput = @()
    $exitCode = 0
    try {
        $ErrorActionPreference = 'Continue'
        $wslVersionOutput = @(& wsl.exe --version 2>&1)
        $exitCode = [int]$LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    foreach ($line in @($wslVersionOutput)) {
        $lineText = [string]$line
        if (-not [string]::IsNullOrWhiteSpace([string]$lineText)) {
            if (Test-WslBenignBootstrapLine -Text $lineText) {
                continue
            }
            Write-Host $lineText
        }
    }

    return ($exitCode -eq 0)
}

function Test-WslBootstrapSatisfied {
    if (Test-WslReady) {
        return $true
    }

    $wslFeatureState = Get-WindowsOptionalFeatureState -FeatureName 'Microsoft-Windows-Subsystem-Linux'
    $vmpFeatureState = Get-WindowsOptionalFeatureState -FeatureName 'VirtualMachinePlatform'
    return (
        [string]::Equals([string]$wslFeatureState, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase) -and
        [string]::Equals([string]$vmpFeatureState, 'Enabled', [System.StringComparison]::OrdinalIgnoreCase)
    )
}

function Invoke-WslBootstrapInstall {
    $bootstrapExit = Invoke-NativeStep -Label "wsl --install --no-distribution" -AcceptedExitCodes @(0,1,3010) -Action {
        wsl.exe --install --no-distribution
    }

    if ($bootstrapExit -eq 0) {
        Write-Host "wsl-step-ok: bootstrap-install"
    }
    elseif ($bootstrapExit -eq 3010) {
        Write-Host "wsl-step-ok: bootstrap-install-pending-restart"
    }
    else {
        Write-Host ("wsl-step-info: bootstrap-install-exit={0}" -f $bootstrapExit)
    }

    return $bootstrapExit
}

function Get-WindowsOptionalFeatureState {
    param([string]$FeatureName)

    if ([string]::IsNullOrWhiteSpace([string]$FeatureName)) {
        return ''
    }

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop
        if ($null -ne $feature -and $feature.PSObject.Properties.Match('State').Count -gt 0) {
            return [string]$feature.State
        }
    }
    catch {
    }

    return ''
}

function Write-WslFeatureState {
    param([string]$FeatureName)

    $state = Get-WindowsOptionalFeatureState -FeatureName $FeatureName
    if ([string]::IsNullOrWhiteSpace([string]$state)) {
        Write-Warning ("{0} feature state could not be resolved." -f $FeatureName)
        return
    }

    if ([string]::Equals([string]$FeatureName, 'Microsoft-Windows-Subsystem-Linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("wsl-feature-state => Microsoft-Windows-Subsystem-Linux => state={0}" -f $state)
        return
    }

    if ([string]::Equals([string]$FeatureName, 'VirtualMachinePlatform', [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("wsl-feature-state => VirtualMachinePlatform => state={0}" -f $state)
        return
    }

    Write-Host ("wsl-feature-state => {0} => {1}" -f $FeatureName, $state)
}

Refresh-SessionPath

$rebootRequired = $false

$bootstrapInstallExit = Invoke-WslBootstrapInstall
if ($bootstrapInstallExit -eq 3010) {
    $rebootRequired = $true
}

if ((Invoke-NativeStep -Label "dism enable-feature Microsoft-Windows-Subsystem-Linux" -AcceptedExitCodes @(0,3010) -Action {
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
}) -eq 3010) {
    $rebootRequired = $true
}
Write-WslFeatureState -FeatureName 'Microsoft-Windows-Subsystem-Linux'

if ((Invoke-NativeStep -Label "dism enable-feature VirtualMachinePlatform" -AcceptedExitCodes @(0,3010) -Action {
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
}) -eq 3010) {
    $rebootRequired = $true
}
Write-WslFeatureState -FeatureName 'VirtualMachinePlatform'

$wslReadyBeforeBootstrap = Test-WslReady
$wslPackageInstalled = Test-WslPackageInstalled
if (-not $wslReadyBeforeBootstrap -or -not $wslPackageInstalled) {
    $wingetExe = Resolve-WingetExe
    if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
        throw "winget command is not available. WSL bootstrap requires winget."
    }

    Write-Host "Resolved winget executable: $wingetExe"
    Write-Host "Installing the WSL Store package through the interactive manager desktop."
    Install-WslAppxThroughInteractiveSession
    Refresh-SessionPath
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw "wsl command is not available after bootstrap."
}

$wslUpdateExit = Invoke-NativeStep -Label "wsl --update --web-download" -AcceptedExitCodes @(0,3010) -Action {
    wsl.exe --update --web-download
}
if ($wslUpdateExit -eq 3010) {
    $rebootRequired = $true
}

$defaultVersionExit = Invoke-NativeStep -Label "wsl --set-default-version 2" -AcceptedExitCodes @(0,1) -Action {
    wsl.exe --set-default-version 2
}
if ($defaultVersionExit -eq 0) {
    Write-Host "wsl-step-ok: default-version-2"
}
else {
    Write-Warning "wsl --set-default-version 2 did not complete successfully. A reboot or follow-up WSL bootstrap may still be required."
}

$versionExit = Invoke-NativeStep -Label "wsl --version" -AcceptedExitCodes @(0) -Action {
    wsl.exe --version
}

if ($versionExit -eq 0) {
    [void](Invoke-NativeStep -Label "wsl --status" -AcceptedExitCodes @(0) -Action {
        wsl.exe --status
    })
    Write-WslFeatureState -FeatureName 'Microsoft-Windows-Subsystem-Linux'
    Write-WslFeatureState -FeatureName 'VirtualMachinePlatform'
    Write-Host "wsl-step-ok: wsl-version"
}
else {
    if ($rebootRequired) {
        Write-Warning "WSL verification is deferred until the next reboot."
    }
    else {
        throw "WSL is still unavailable after bootstrap and update."
    }
}

if ($rebootRequired) {
    Write-Host "TASK_REBOOT_REQUIRED:install-wsl-feature"
}

Write-Host "install-wsl-feature-completed"
Write-Host "Update task completed: install-wsl-feature"

