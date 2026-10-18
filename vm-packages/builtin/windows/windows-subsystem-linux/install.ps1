$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-wsl-feature"

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
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
    $uninstallRoots = @(
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $records = @()
    foreach ($uninstallRoot in @($uninstallRoots)) {
        $records += @(Get-ItemProperty -Path (Join-Path $uninstallRoot '*') -ErrorAction SilentlyContinue | Where-Object {
            $displayNameProperty = $_.PSObject.Properties['DisplayName']
            $null -ne $displayNameProperty -and [string]::Equals([string]$displayNameProperty.Value,'Windows Subsystem for Linux',[StringComparison]::OrdinalIgnoreCase)
        })
    }
    return (@($records).Count -gt 0 -and (Test-Path -LiteralPath 'C:\Program Files\WSL\wsl.exe' -PathType Leaf))
}

function Install-WslMsiUnattended {
    if (Test-WslPackageInstalled) {
        Write-Host 'wsl-step-info: managed WSL MSI is already installed; skipping bootstrap download.'
        return 0
    }

    Write-Host 'Doing: resolve the latest stable WSL x64 MSI from the official Microsoft release metadata'
    $previousSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/WSL/releases/latest' -Headers @{ 'User-Agent' = 'Clagnos-WSL-MSI-Bootstrap' } -TimeoutSec 60 -ErrorAction Stop
    }
    finally { [Net.ServicePointManager]::SecurityProtocol = $previousSecurityProtocol }

    $asset = @($release.assets | Where-Object { [regex]::IsMatch([string]$_.name,'(?i)^wsl\.\d+\.\d+\.\d+\.0\.x64\.msi$') } | Select-Object -First 1)
    if ($asset.Count -ne 1) { throw 'The official WSL release metadata did not contain one stable x64 MSI asset.' }
    $assetName = [string]$asset[0].name
    $assetUrl = [string]$asset[0].browser_download_url
    $expectedHash = ([string]$asset[0].digest -replace '(?i)^sha256:','').ToLowerInvariant()
    $assetUri = $null
    if (-not [Uri]::TryCreate($assetUrl,[UriKind]::Absolute,[ref]$assetUri) -or [string]$assetUri.Host -ne 'github.com' -or [string]$assetUri.AbsolutePath -notmatch '^/microsoft/WSL/releases/download/') {
        throw 'The official WSL MSI release URL failed the Microsoft repository-host validation.'
    }
    if ($expectedHash -notmatch '^[a-f0-9]{64}$') { throw 'The official WSL release metadata did not include a valid SHA-256 digest.' }

    $cacheRoot = Join-Path $env:ProgramData 'clagnos\cache\wsl'
    if (-not (Test-Path -LiteralPath $cacheRoot -PathType Container)) { New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null }
    $msiPath = Join-Path $cacheRoot $assetName
    $cachedHash = ''
    if (Test-Path -LiteralPath $msiPath -PathType Leaf) {
        $cachedHash = [string](Get-FileHash -LiteralPath $msiPath -Algorithm SHA256 -ErrorAction Stop).Hash
    }
    if (-not [string]::Equals($cachedHash,$expectedHash,[StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $msiPath -PathType Leaf) { Remove-Item -LiteralPath $msiPath -Force -ErrorAction Stop }
        Write-Host ('Doing: download the official WSL MSI {0} into the verified package cache' -f $assetName)
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $assetUrl -OutFile $msiPath -UseBasicParsing -TimeoutSec 240 -ErrorAction Stop
        }
        finally { $ProgressPreference = $previousProgressPreference }
        $downloadedHash = [string](Get-FileHash -LiteralPath $msiPath -Algorithm SHA256 -ErrorAction Stop).Hash
        if (-not [string]::Equals($downloadedHash,$expectedHash,[StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $msiPath -Force -ErrorAction SilentlyContinue
            throw 'The downloaded WSL MSI SHA-256 digest does not match the official Microsoft release metadata.'
        }
    }
    else { Write-Host ('wsl-step-ok: verified-msi-cache => {0}' -f $assetName) }

    $signature = Get-AuthenticodeSignature -FilePath $msiPath -ErrorAction Stop
    if ([string]$signature.Status -ne 'Valid') { throw ('The official WSL MSI Authenticode signature is not valid (status: {0}).' -f [string]$signature.Status) }
    $msiexecPath = Join-Path $env:SystemRoot 'System32\msiexec.exe'
    if (-not (Test-Path -LiteralPath $msiexecPath -PathType Leaf)) { throw 'Windows Installer executable is unavailable for WSL MSI installation.' }
    $installExit = Invoke-NativeStep -Label ('install signed WSL MSI {0} silently' -f $assetName) -AcceptedExitCodes @(0,1,3010) -Action {
        & $msiexecPath /i $msiPath /qn /norestart
    }
    $registrationDeadline = [DateTime]::UtcNow.AddSeconds(45)
    $nextRegistrationHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
    do {
        if (Test-WslPackageInstalled) {
            Write-Host 'wsl-step-ok: MSI registration and executable verified'
            if ($installExit -eq 1) { Write-Host 'wsl-step-info: Windows Installer returned 1, but the signed MSI registration and executable verified successfully.' }
            break
        }
        if ([DateTime]::UtcNow -ge $registrationDeadline) { throw 'The signed WSL MSI installer finished but its MSI registration and executable did not become visible within 45 seconds.' }
        if ([DateTime]::UtcNow -ge $nextRegistrationHeartbeat) {
            Write-Host ('Doing: wait for WSL MSI registration after install ({0}s elapsed)' -f [int](45 - ($registrationDeadline - [DateTime]::UtcNow).TotalSeconds))
            $nextRegistrationHeartbeat = [DateTime]::UtcNow.AddSeconds(15)
        }
        Start-Sleep -Seconds 2
    } while ($true)
    return [int]$installExit
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
    $wslPackageInstallExit = Install-WslMsiUnattended
    if ($wslPackageInstallExit -eq 3010) { $rebootRequired = $true }
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

