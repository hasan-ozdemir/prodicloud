# Connect command entry.

function Invoke-ProdicloudConnectCommand {
    param(
        [hashtable]$Options
    )

    $mode = Resolve-ProdicloudConnectMode -Options $Options
    $commandRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'command'
    $testRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'test'
    if ($commandRequested -and -not [string]::Equals([string]$mode, 'powershell', [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail "The --command option is only supported with --powershell." `
            -Code 66 `
            -Summary "Connect command transport is invalid." `
            -Hint "Use prodicloud connect --powershell --command <PowerShell-command>."
    }

    if ([string]::Equals([string]$mode, 'powershell', [System.StringComparison]::OrdinalIgnoreCase)) {
        if ($testRequested -and $commandRequested) {
            Throw-FriendlyError `
                -Detail "Both --test and --command were provided for PowerShell remoting." `
                -Code 66 `
                -Summary "PowerShell remoting mode is ambiguous." `
                -Hint "Use --test by itself, or use --command to execute a remote command."
        }
        if ($testRequested) {
            Invoke-ProdicloudPowerShellConnectivityTest -Options $Options
            return
        }

        $runtime = Initialize-ProdicloudConnectionCommandContext -Options $Options -OperationName 'connect-powershell'
        Assert-ProdicloudPowerShellVm -Runtime $runtime
        $powerShellPort = Resolve-ProdicloudConnectionPortNumber -PortText ([string]$runtime.VmPowerShellPort) -PortLabel 'PowerShell remoting'
        Write-ProdicloudActionProgress -Action ("open remote PowerShell session to '{0}:{1}'" -f [string]$runtime.ConnectionHost, $powerShellPort)
        $session = New-ProdicloudPowerShellRemotingSession -Runtime $runtime
        try {
            if ($commandRequested) {
                $commandText = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'command')
                if ([string]::IsNullOrWhiteSpace([string]$commandText)) {
                    Throw-FriendlyError `
                        -Detail "The --command option was provided without PowerShell command text." `
                        -Code 66 `
                        -Summary "Remote PowerShell command is empty." `
                        -Hint "Provide a command such as --command 'Get-Date'."
                }

                Write-ProdicloudActionProgress -Action ("run a PowerShell command on VM '{0}'" -f [string]$runtime.VmName)
                Invoke-ProdicloudPowerShellRemoteCommand -Session $session -CommandText $commandText
                Write-Host ("PowerShell command completed on VM '{0}'." -f [string]$runtime.VmName) -ForegroundColor Green
            }
            else {
                Invoke-ProdicloudInteractivePowerShellSession -Session $session -ConnectionHost ([string]$runtime.ConnectionHost) -VmName ([string]$runtime.VmName)
            }
        }
        finally {
            if ($null -ne $session) {
                Remove-PSSession -Session $session -ErrorAction SilentlyContinue
            }
        }
        return
    }

    if ([string]::Equals($mode, 'ssh', [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-ProdicloudCliOptionPresent -Options $Options -Name 'test') {
            Invoke-ProdicloudSshConnectivityTest -Options $Options
            return
        }

        $runtime = Initialize-ProdicloudConnectionCommandContext -Options $Options -OperationName 'connect-ssh'
        $sshExePath = Resolve-ProdicloudLocalExecutablePath -Candidates @('ssh.exe', (Join-Path $env:SystemRoot 'System32\OpenSSH\ssh.exe')) -FriendlyName 'Windows OpenSSH'
        $targetText = ("{0}@{1}" -f [string]$runtime.SelectedUserName, [string]$runtime.ConnectionHost)
        $sshArgs = @('-p', [string]$runtime.VmSshPort, $targetText)

        Write-Host ("Launching SSH client for VM '{0}' in group '{1}'..." -f [string]$runtime.VmName, [string]$runtime.ResourceGroup) -ForegroundColor Cyan
        Write-Host ("SSH target: {0}" -f $targetText) -ForegroundColor DarkCyan
        Write-Host "Password entry will appear in the external SSH console window." -ForegroundColor Yellow
        Start-Process -FilePath $sshExePath -ArgumentList $sshArgs | Out-Null
        return
    }

    if (Test-ProdicloudCliOptionPresent -Options $Options -Name 'test') {
        Invoke-ProdicloudRdpConnectivityTest -Options $Options
        return
    }

    $runtime = Initialize-ProdicloudConnectionCommandContext -Options $Options -OperationName 'connect-rdp'
    if (-not [string]::Equals(([string]$runtime.OsType).Trim(), 'Windows', [System.StringComparison]::OrdinalIgnoreCase)) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' reports osType '{1}', so RDP launch is not supported." -f [string]$runtime.VmName, [string]$runtime.OsType) `
            -Code 66 `
            -Summary "Connect --rdp is only available for Windows VMs." `
            -Hint "Use prodicloud connect --ssh for Linux VMs, or target a Windows VM."
    }

    $cmdKeyPath = Resolve-ProdicloudLocalExecutablePath -Candidates @((Join-Path $env:SystemRoot 'System32\cmdkey.exe'), 'cmdkey.exe') -FriendlyName 'Windows Credential Manager'
    $mstscPath = Resolve-ProdicloudLocalExecutablePath -Candidates @((Join-Path $env:SystemRoot 'System32\mstsc.exe'), 'mstsc.exe') -FriendlyName 'Remote Desktop Connection'
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
