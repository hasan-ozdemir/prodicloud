# Exec command entry.

# Handles Invoke-ProdicloudExecCommand.
function Invoke-ProdicloudExecCommand {
    param(
        [hashtable]$Options
    )

    $runtime = Initialize-ProdicloudExecCommandRuntimeContext
    $commandSource = Resolve-ProdicloudExecCommandTextFromOptions -Options $Options -RepoRoot ([string]$runtime.RepoRoot)
    $commandText = [string]$commandSource.CommandText
    $scriptFilePath = [string]$commandSource.ScriptFilePath
    $quietRequested = (Test-ProdicloudCliOptionPresent -Options $Options -Name 'quiet')
    if ($quietRequested -and [string]::IsNullOrWhiteSpace([string]$commandText)) {
        Throw-FriendlyError `
            -Detail "exec --quiet requires --command, -c, or --file." `
            -Code 61 `
            -Summary "Quiet exec requires one remote command." `
            -Hint 'Use prodicloud exec --quiet --command "<remote-command>" or prodicloud exec --quiet --file <script-file>.'
    }
    if ($quietRequested) {
        $script:ProdicloudQuietOutput = $true
    }

    Write-ProdicloudActionProgress -Action 'open remote SSH command session'

    $target = Resolve-ProdicloudManagedVmTarget -Options $Options -ConfigMap $runtime.ConfigMap -OperationName 'exec'
    $selectedResourceGroup = [string]$target.ResourceGroup
    $selectedVmName = [string]$target.VmName
    $vmDetailContext = [ordered]@{
        ResourceGroup = $selectedResourceGroup
        VmName = $selectedVmName
        AzLocation = ''
        SshPort = [string](Get-ConfigValue -Config $runtime.ConfigMap -Key 'VM_SSH_PORT' -DefaultValue (Get-ProdicloudDefaultSshPortText))
    }

    $vmRuntimeDetails = Get-ProdicloudVmDetails -Context $vmDetailContext
    $sshHost = [string]$vmRuntimeDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($sshHost)) {
        $sshHost = [string]$vmRuntimeDetails.PublicIP
    }
    if ([string]::IsNullOrWhiteSpace($sshHost)) {
        throw "Exec REPL could not resolve VM SSH host (FQDN/Public IP)."
    }

    $vmUser = [string](Get-ConfigValue -Config $runtime.ConfigMap -Key 'VM_ADMIN_USER' -DefaultValue '')
    $vmPass = [string](Get-ConfigValue -Config $runtime.ConfigMap -Key 'VM_ADMIN_PASS' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace([string]$vmUser)) {
        Throw-FriendlyError `
            -Detail "VM admin user is missing for exec." `
            -Code 61 `
            -Summary "Exec requires VM admin credentials." `
            -Hint "Set VM_ADMIN_USER in the selected <vm-name>.env profile before using exec."
    }
    if ([string]::IsNullOrWhiteSpace([string]$vmPass)) {
        Throw-FriendlyError `
            -Detail "VM admin password is missing for exec." `
            -Code 61 `
            -Summary "Exec requires VM admin credentials." `
            -Hint "Set VM_ADMIN_PASS in the selected <vm-name>.env profile before using exec."
    }

    $vmJson = az vm show -g $selectedResourceGroup -n $selectedVmName -o json --only-show-errors
    Assert-LastExitCode "az vm show (exec repl)"
    $vmObject = ConvertFrom-JsonCompat -InputObject $vmJson
    $osType = [string]$vmObject.storageProfile.osDisk.osType
    $replPlatform = if ([string]::Equals($osType, 'Linux', [System.StringComparison]::OrdinalIgnoreCase)) { 'linux' } else { 'windows' }
    $shell = if ($replPlatform -eq 'linux') { 'bash' } else { 'powershell' }

    $pySsh = Ensure-ProdicloudPySshTools -RepoRoot (Get-ProdicloudRepoRoot) -ConfiguredPySshClientPath ([string]$runtime.ConfiguredPySshClientPath)
    $bootstrap = Initialize-ProdicloudSshHostKey `
        -PySshPythonPath ([string]$pySsh.PythonPath) `
        -PySshClientPath ([string]$pySsh.ClientPath) `
        -HostName $sshHost `
        -UserName $vmUser `
        -Password $vmPass `
        -Port ([string]$vmDetailContext.SshPort) `
        -ConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds)
    if (-not [string]::IsNullOrWhiteSpace([string]$bootstrap.Output)) {
        if (-not $quietRequested) {
            Write-Host ([string]$bootstrap.Output)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$commandText)) {
        $commandWatch = $null
        if ($script:PerfMode -and -not $quietRequested) {
            $commandWatch = [System.Diagnostics.Stopwatch]::StartNew()
        }
        if (-not $quietRequested -and -not [string]::IsNullOrWhiteSpace([string]$scriptFilePath)) {
            Write-Host ("Exec remote command source file: {0}" -f [string]$scriptFilePath) -ForegroundColor DarkCyan
        }
        $remoteCommandText = ConvertTo-ProdicloudExecRemoteCommandText -CommandText $commandText -Platform $replPlatform -Quiet:$quietRequested

        $execArgs = @(
            [string]$pySsh.ClientPath,
            'exec',
            '--host', [string]$sshHost,
            '--port', [string]$vmDetailContext.SshPort,
            '--user', $vmUser,
            '--password', $vmPass,
            '--timeout', [string]$runtime.SshCommandTimeoutSeconds,
            '--command', [string]$remoteCommandText
        )

        & ([string]$pySsh.PythonPath) @execArgs
        $commandExitCode = [int]$LASTEXITCODE

        if ($null -ne $commandWatch -and $commandWatch.IsRunning) {
            $commandWatch.Stop()
            Write-ProdicloudPerfTiming -Category "exec" -Label "remote command" -Seconds $commandWatch.Elapsed.TotalSeconds
        }

        if ($commandExitCode -ne 0) {
            Throw-FriendlyError `
                -Detail ("Remote exec command ended with exit code {0}." -f $commandExitCode) `
                -Code 61 `
                -Summary "Remote exec command failed." `
                -Hint "Review remote command output and retry. Ensure SSH access remains healthy on the VM."
        }

        if (-not $quietRequested) {
            Write-Host ("Exec completed on VM '{0}'." -f $selectedVmName) -ForegroundColor Green
        }
        return
    }

    Write-Host ("Interactive exec shell connected: {0}@{1}:{2} ({3})" -f $vmUser, $sshHost, [string]$vmDetailContext.SshPort, $shell) -ForegroundColor Green
    Write-Host "Type 'exit' in the remote shell to close the session." -ForegroundColor Cyan

    $shellWatch = $null
    if ($script:PerfMode) {
        $shellWatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    $shellArgs = @(
        [string]$pySsh.ClientPath,
        "shell",
        "--host", [string]$sshHost,
        "--port", [string]$vmDetailContext.SshPort,
        "--user", $vmUser,
        "--password", $vmPass,
        "--timeout", [string]$runtime.SshConnectTimeoutSeconds,
        "--reconnect-retries", "3",
        "--keepalive-seconds", "15",
        "--shell", [string]$shell
    )

    & ([string]$pySsh.PythonPath) @shellArgs
    $shellExitCode = [int]$LASTEXITCODE

    if ($null -ne $shellWatch -and $shellWatch.IsRunning) {
        $shellWatch.Stop()
        Write-ProdicloudPerfTiming -Category "exec" -Label "interactive shell session" -Seconds $shellWatch.Elapsed.TotalSeconds
    }

    if ($shellExitCode -ne 0) {
        Throw-FriendlyError `
            -Detail ("Interactive exec shell ended with exit code {0}." -f $shellExitCode) `
            -Code 61 `
            -Summary "Interactive exec shell failed." `
            -Hint "Review remote shell output and retry. Ensure SSH service remains available on the VM."
    }

    Write-Host "Exec REPL session closed." -ForegroundColor Green
}
