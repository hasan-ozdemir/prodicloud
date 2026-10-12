# Connect command entry.

function Invoke-ClagnosConnectCommand {
    param(
        [hashtable]$Options
    )

    $mode = Resolve-ClagnosConnectMode -Options $Options
    if ([string]::Equals($mode, 'ssh', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-ClagnosCliOptionPresent -Options $Options -Name 'test') {
            Invoke-ClagnosSshConnectivityTest -Options $Options
            return
        }

        $runtime = Initialize-ClagnosConnectionCommandContext -Options $Options -OperationName 'connect-ssh'
        $sshExePath = Resolve-ClagnosLocalExecutablePath -Candidates @('ssh.exe', (Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe')) -FriendlyName 'Windows OpenSSH'
        $targetText = ("{0}@{1}" -f [string]$runtime.SelectedUserName, [string]$runtime.ConnectionHost)
        $sshArgs = @('-p', [string]$runtime.VmSshPort, $targetText)

        Write-Host ("Launching SSH client for VM '{0}' in group '{1}'..." -f [string]$runtime.VmName, [string]$runtime.ResourceGroup) -ForegroundColor Cyan
        Write-Host ("SSH target: {0}" -f $targetText) -ForegroundColor DarkCyan
        Write-Host "Password entry will appear in the external SSH console window." -ForegroundColor Yellow
        Start-Process -FilePath $sshExePath -ArgumentList $sshArgs | Out-Null
        return
    }

    if (Test-ClagnosCliOptionPresent -Options $Options -Name 'test') {
        Invoke-ClagnosRdpConnectivityTest -Options $Options
        return
    }

    $runtime = Initialize-ClagnosConnectionCommandContext -Options $Options -OperationName 'connect-rdp'
    if (-not [string]::Equals(([string]$runtime.OsType).Trim(), 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' reports osType '{1}', so RDP launch is not supported." -f [string]$runtime.VmName, [string]$runtime.OsType) `
            -Code 66 `
            -Summary "Connect --rdp is only available for Windows VMs." `
            -Hint "Use clagnos connect --ssh for Linux VMs, or target a Windows VM."
    }

    $cmdKeyPath = Resolve-ClagnosLocalExecutablePath -Candidates @((Join-Path $env:SystemRoot 'System32\cmdkey.exe'), 'cmdkey.exe') -FriendlyName 'Windows Credential Manager'
    $mstscPath = Resolve-ClagnosLocalExecutablePath -Candidates @((Join-Path $env:SystemRoot 'System32\mstsc.exe'), 'mstsc.exe') -FriendlyName 'Remote Desktop Connection'
    $credentialTarget = ("TERMSRV/{0}" -f [string]$runtime.ConnectionHost)
    $rdpUserName = (".\{0}" -f [string]$runtime.SelectedUserName)
    $cmdKeyArgs = @("/generic:$credentialTarget", "/user:$rdpUserName", "/pass:$([string]$runtime.SelectedPassword)")

    Write-Host ("Staging RDP credentials for VM '{0}' in group '{1}'..." -f [string]$runtime.VmName, [string]$runtime.ResourceGroup) -ForegroundColor Cyan
    $cmdKeyProcess = Start-Process -FilePath $cmdKeyPath -ArgumentList $cmdKeyArgs -Wait -PassThru -WindowStyle Hidden
    if ($null -eq $cmdKeyProcess -or [int]$cmdKeyProcess.ExitCode -ne 0) {
        $exitCode = if ($null -eq $cmdKeyProcess) { -1 } else { [int]$cmdKeyProcess.ExitCode }
        Throw-FriendlyError `
            -Detail ("cmdkey failed while staging credentials for target '{0}' (exit={1})." -f $credentialTarget, $exitCode) `
            -Code 66 `
            -Summary "Connect --rdp credential staging failed." `
            -Hint "Verify local Windows credential manager access and retry."
    }

    Write-Host ("Launching mstsc for {0}:{1}..." -f [string]$runtime.ConnectionHost, [string]$runtime.VmRdpPort) -ForegroundColor Cyan
    Start-Process -FilePath $mstscPath -ArgumentList @("/v:{0}:{1}" -f [string]$runtime.ConnectionHost, [string]$runtime.VmRdpPort) | Out-Null
}
