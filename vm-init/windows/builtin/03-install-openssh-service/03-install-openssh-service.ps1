$ErrorActionPreference = "Stop"
Write-Host "Init task started: install-openssh-service"

$openSshServerMsiUrl = 'https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.0.0.0p2-Preview/OpenSSH-Win64-v10.0.0.0.msi'
$openSshServerMsiPath = 'C:\Windows\Temp\OpenSSH-Win64-v10.0.0.0.msi'

function Get-OpenSshService {
    return (Get-Service sshd -ErrorAction SilentlyContinue)
}

function Get-OpenSshServiceExecutablePath {
    $openSshExecutableCandidates = @(
        'C:\Program Files\OpenSSH\sshd.exe',
        'C:\Program Files\OpenSSH-Win64\sshd.exe',
        'C:\Windows\System32\OpenSSH\sshd.exe'
    )

    return ($openSshExecutableCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Get-OpenSshKeyGenExecutablePath {
    $openSshKeyGenCandidates = @(
        'C:\Program Files\OpenSSH\ssh-keygen.exe',
        'C:\Program Files\OpenSSH-Win64\ssh-keygen.exe',
        'C:\Windows\System32\OpenSSH\ssh-keygen.exe'
    )

    return ($openSshKeyGenCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Get-OpenSshInstallScriptPath {
    $openSshInstallScriptCandidates = @(
        'C:\Program Files\OpenSSH\install-sshd.ps1',
        'C:\Program Files\OpenSSH-Win64\install-sshd.ps1',
        'C:\Windows\System32\OpenSSH\install-sshd.ps1'
    )

    return ($openSshInstallScriptCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Wait-OpenSshServiceRegistration {
    param([int]$TimeoutSeconds = 45)

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $service = Get-OpenSshService
        if ($null -ne $service) {
            return $service
        }

        Start-Sleep -Seconds 1
    }

    return $null
}

function Ensure-OpenSshHostKeyMaterial {
    $keyGenPath = Get-OpenSshKeyGenExecutablePath
    if ([string]::IsNullOrWhiteSpace([string]$keyGenPath)) {
        return
    }

    Write-Host ("Running OpenSSH host key generation: {0} -A" -f [string]$keyGenPath)
    & $keyGenPath -A
    if ($LASTEXITCODE -ne 0) {
        throw ("OpenSSH host key generation failed with exit code {0}." -f $LASTEXITCODE)
    }
}

function Install-OpenSshServerPackage {
    $service = Get-OpenSshService
    if ($null -ne $service) {
        return [pscustomobject]@{
            RebootRequired = $false
        }
    }

    $sshdExecutablePath = Get-OpenSshServiceExecutablePath
    if (-not [string]::IsNullOrWhiteSpace([string]$sshdExecutablePath)) {
        return [pscustomobject]@{
            RebootRequired = $false
        }
    }

    Write-Host ("Downloading OpenSSH MSI from {0}" -f [string]$openSshServerMsiUrl)
    Invoke-WebRequest -Uri $openSshServerMsiUrl -OutFile $openSshServerMsiPath

    Write-Host ("Running OpenSSH MSI installer: msiexec.exe /i {0} /qn /norestart" -f [string]$openSshServerMsiPath)
    $installProcess = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', $openSshServerMsiPath, '/qn', '/norestart') -Wait -PassThru
    if ($installProcess.ExitCode -ne 0 -and $installProcess.ExitCode -ne 3010) {
        throw ("OpenSSH MSI installation exited with code {0}." -f [int]$installProcess.ExitCode)
    }

    return [pscustomobject]@{
        RebootRequired = ($installProcess.ExitCode -eq 3010)
    }
}

function Repair-OpenSshServiceRegistration {
    $installScript = Get-OpenSshInstallScriptPath
    if (-not [string]::IsNullOrWhiteSpace([string]$installScript)) {
        Write-Host ("Running OpenSSH service installer: {0}" -f [string]$installScript)
        powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript
        if ($LASTEXITCODE -ne 0) {
            throw ("OpenSSH install-sshd.ps1 failed with exit code {0}." -f $LASTEXITCODE)
        }

        return (Wait-OpenSshServiceRegistration -TimeoutSeconds 30)
    }

    $sshdExecutablePath = Get-OpenSshServiceExecutablePath
    if ([string]::IsNullOrWhiteSpace([string]$sshdExecutablePath)) {
        return $null
    }

    Ensure-OpenSshHostKeyMaterial
    New-Item -Path 'C:\ProgramData\ssh' -ItemType Directory -Force | Out-Null

    $existingService = Get-OpenSshService
    if ($null -eq $existingService) {
        Write-Host ("Registering sshd service directly from executable: {0}" -f [string]$sshdExecutablePath)
        try {
            New-Service -Name 'sshd' -BinaryPathName ("`"{0}`"" -f [string]$sshdExecutablePath) -DisplayName 'OpenSSH SSH Server' -Description 'SSH protocol based service to provide secure encrypted communications between two untrusted hosts over an insecure network.' -StartupType Automatic | Out-Null
        }
        catch {
            if ($_.Exception.Message -notmatch '(?i)already exists') {
                throw
            }
        }
    }

    return (Wait-OpenSshServiceRegistration -TimeoutSeconds 30)
}

function Ensure-OpenSshServiceInstalled {
    $service = Get-OpenSshService
    if ($null -ne $service) {
        return [pscustomobject]@{
            Service = $service
            RebootRequired = $false
            PendingReason = ''
        }
    }

    $installResult = Install-OpenSshServerPackage
    $service = Wait-OpenSshServiceRegistration -TimeoutSeconds 45
    if ($null -ne $service) {
        return [pscustomobject]@{
            Service = $service
            RebootRequired = [bool]$installResult.RebootRequired
            PendingReason = ''
        }
    }

    $service = Repair-OpenSshServiceRegistration
    if ($null -ne $service) {
        return [pscustomobject]@{
            Service = $service
            RebootRequired = [bool]$installResult.RebootRequired
            PendingReason = ''
        }
    }

    if ([bool]$installResult.RebootRequired) {
        return [pscustomobject]@{
            Service = $null
            RebootRequired = $true
            PendingReason = 'msi-reboot-required'
        }
    }

    throw "OpenSSH setup completed but sshd service was not found."
}

$installResult = Ensure-OpenSshServiceInstalled
$sshdService = $installResult.Service
if ($null -eq $sshdService) {
    Write-Host ("openssh-service-pending-reboot: {0}" -f [string]$installResult.PendingReason)
    Write-Host "TASK_REBOOT_REQUIRED:install-openssh-service"
    Write-Host "openssh-ready"
    Write-Host "Init task completed: install-openssh-service"
    return
}

Set-Service -Name sshd -StartupType Automatic
if (Get-Service ssh-agent -ErrorAction SilentlyContinue) {
    Set-Service -Name ssh-agent -StartupType Automatic
}

if (-not [string]::Equals([string]$sshdService.Status, 'Running', [System.StringComparison]::OrdinalIgnoreCase)) {
    try {
        Start-Service -Name sshd -ErrorAction Stop
    }
    catch {
    }
}

$sshdService = Get-OpenSshService

Write-Host ("openssh-service-ready: status={0}; start-type={1}" -f [string]$sshdService.Status, [string]$sshdService.StartType)
if ([bool]$installResult.RebootRequired) {
    Write-Host "TASK_REBOOT_REQUIRED:install-openssh-service"
}
Write-Host "openssh-ready"
Write-Host "Init task completed: install-openssh-service"
