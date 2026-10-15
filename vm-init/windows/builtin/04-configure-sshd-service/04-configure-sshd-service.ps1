$ErrorActionPreference = "Stop"
Write-Host "Init task started: configure-sshd-service"

function Get-OpenSshService {
    return (Get-Service sshd -ErrorAction SilentlyContinue)
}

function Get-OpenSshServiceExecutablePath {
    $openSshExecutableCandidates = @(
        'C:\Windows\System32\OpenSSH\sshd.exe',
        'C:\Program Files\OpenSSH-Win64\sshd.exe',
        'C:\Program Files\OpenSSH\sshd.exe'
    )

    return ($openSshExecutableCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Get-OpenSshKeyGenExecutablePath {
    $openSshKeyGenCandidates = @(
        'C:\Windows\System32\OpenSSH\ssh-keygen.exe',
        'C:\Program Files\OpenSSH-Win64\ssh-keygen.exe',
        'C:\Program Files\OpenSSH\ssh-keygen.exe'
    )

    return ($openSshKeyGenCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Get-OpenSshInstallScriptPath {
    $openSshInstallScriptCandidates = @(
        "C:\Windows\System32\OpenSSH\install-sshd.ps1",
        "C:\Program Files\OpenSSH-Win64\install-sshd.ps1",
        "C:\Program Files\OpenSSH\install-sshd.ps1"
    )

    return ($openSshInstallScriptCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
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

function Wait-SshdListener {
    param(
        [int]$Port,
        [int]$TimeoutSeconds = 20
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($null -ne $listener) {
            return $true
        }

        Start-Sleep -Seconds 1
    }

    return $false
}

function Recover-OpenSshService {
    $installScript = Get-OpenSshInstallScriptPath
    if (-not [string]::IsNullOrWhiteSpace([string]$installScript)) {
        Write-Host "OpenSSH service is missing. Running service installer before sshd_config changes."
        powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $installScript
        if ($LASTEXITCODE -ne 0) {
            throw "OpenSSH install-sshd.ps1 failed while recovering the sshd service."
        }

        return (Get-OpenSshService)
    }

    $sshdExecutablePath = Get-OpenSshServiceExecutablePath
    if ([string]::IsNullOrWhiteSpace([string]$sshdExecutablePath)) {
        return $null
    }

    Write-Host ("OpenSSH service is missing. Attempting direct service recovery before sshd_config changes from {0}." -f [string]$sshdExecutablePath)
    Ensure-OpenSshHostKeyMaterial
    New-Item -Path 'C:\ProgramData\ssh' -ItemType Directory -Force | Out-Null
    try {
        New-Service -Name 'sshd' -BinaryPathName ("`"{0}`"" -f [string]$sshdExecutablePath) -DisplayName 'OpenSSH SSH Server' -Description 'SSH protocol based service to provide secure encrypted communications between two untrusted hosts over an insecure network.' -StartupType Automatic | Out-Null
    }
    catch {
        if ($_.Exception.Message -notmatch '(?i)already exists') {
            throw
        }
    }
    Start-Sleep -Seconds 2
    return (Get-OpenSshService)
}

$sshdService = Get-OpenSshService
if ($null -eq $sshdService) {
    $sshdService = Recover-OpenSshService
    if ($null -eq $sshdService) {
        throw "OpenSSH service is still missing after the recovery path completed."
    }
}

$sshdConfig = "C:\ProgramData\ssh\sshd_config"
if (-not (Test-Path -LiteralPath $sshdConfig)) {
    New-Item -Path $sshdConfig -ItemType File -Force
}

$content = @(Get-Content -Path $sshdConfig -ErrorAction SilentlyContinue)
$originalContent = @($content)
if ($content.Count -eq 0) {
    $content = @(
        "# Generated baseline sshd_config",
        "Port 22",
        "PasswordAuthentication no",
        "PubkeyAuthentication yes",
        "PermitEmptyPasswords no",
        "AllowTcpForwarding yes",
        "GatewayPorts no",
        "Subsystem sftp C:/Windows/System32/OpenSSH/sftp-server.exe"
    )
}

function Set-OrAdd {
    param([string]$Key,[string]$Value)
    $regex = "^\s*#?\s*" + [regex]::Escape($Key) + "\s+.*$"
    $replacement = "$Key $Value"
    $updated = $false
    for ($i = 0; $i -lt $content.Count; $i++) {
        if ($content[$i] -match $regex) {
            $content[$i] = $replacement
            $updated = $true
        }
    }
    if (-not $updated) {
        $content += $replacement
    }
}

Set-OrAdd -Key "Port" -Value "__SSH_PORT__"
Set-OrAdd -Key "PasswordAuthentication" -Value "yes"
Set-OrAdd -Key "PubkeyAuthentication" -Value "no"
Set-OrAdd -Key "PermitEmptyPasswords" -Value "no"
Set-OrAdd -Key "AllowTcpForwarding" -Value "yes"
Set-OrAdd -Key "GatewayPorts" -Value "yes"
Set-OrAdd -Key "Subsystem sftp" -Value "C:/Windows/System32/OpenSSH/sftp-server.exe"
$sshdConfigChanged = -not [string]::Equals(($originalContent -join "`n"),($content -join "`n"),[System.StringComparison]::Ordinal)
if ($sshdConfigChanged) {
    Write-Host 'Doing: write the updated sshd configuration'
    Set-Content -Path $sshdConfig -Value $content -Encoding ascii
}

$defaultShellPath = "HKLM:\SOFTWARE\OpenSSH"
New-Item -Path $defaultShellPath -Force | Out-Null
$defaultShellChanged = $false
$currentDefaultShell = [string](Get-ItemProperty -Path $defaultShellPath -Name 'DefaultShell' -ErrorAction SilentlyContinue).DefaultShell
if (-not [string]::Equals($currentDefaultShell,'C:\Windows\System32\cmd.exe',[System.StringComparison]::OrdinalIgnoreCase)) {
    Set-ItemProperty -Path $defaultShellPath -Name "DefaultShell" -Value "C:\Windows\System32\cmd.exe"
    $defaultShellChanged = $true
}

$sshdService = Get-OpenSshService
Ensure-OpenSshHostKeyMaterial
Set-Service -Name sshd -StartupType Automatic
if ([string]::Equals([string]$sshdService.Status, 'Running', [System.StringComparison]::OrdinalIgnoreCase)) {
    if ($sshdConfigChanged -or $defaultShellChanged) {
        Write-Host 'Doing: restart sshd because its configuration changed'
        Restart-Service -Name sshd -Force
    }
    else {
        Write-Host 'sshd settings are already current; the running service remains active.'
    }
}
else {
    Start-Service -Name sshd
}

$sshRuleName = "Allow-SSH-__SSH_PORT__"
if (-not (Get-NetFirewallRule -DisplayName $sshRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $sshRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort __SSH_PORT__ -RemoteAddress Any -Profile Any
}

if (-not (Wait-SshdListener -Port __SSH_PORT__ -TimeoutSeconds 20)) {
    throw "sshd was configured, but the listener did not bind to the configured port in time."
}

Write-Host "sshd-config-ready"
Write-Host "Init task completed: configure-sshd-service"

