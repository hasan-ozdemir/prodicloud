# Shared VM restart and recovery helpers for task execution and workflow stages.

function New-ProdicloudTaskRestartContext {
    param(
        [AllowNull()]$Context,
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$AzLocation = '',
        [int]$SshPort = 0
    )

    if ($null -ne $Context) {
        return $Context
    }

    return @{
        ResourceGroup = [string]$ResourceGroup
        VmName = [string]$VmName
        AzLocation = [string]$AzLocation
        SshPort = [int]$SshPort
    }
}

function Invoke-ProdicloudRestartAndWait {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [string]$AzLocation = '',
        [string]$StartMessage = 'Restarting VM...',
        [string]$SuccessMessage = 'VM restart completed successfully.',
        [string]$RunningFailureSummary = 'VM could not be restarted.',
        [string]$RunningFailureHint = 'Check the VM in Azure Portal and rerun the operation after it returns to running state.',
        [string]$ProvisioningFailureSummary = 'VM restart recovery did not complete successfully.',
        [string]$ProvisioningFailureHint = 'Check provisioning status and guest boot health before rerunning the operation.',
        [string]$HostFailureSummary = 'VM restart completed, but SSH host resolution failed.',
        [string]$HostFailureHint = 'Verify that the managed VM still has a reachable public IP or FQDN.',
        [string]$SshFailureSummary = 'VM restart completed, but SSH connectivity did not recover in time.',
        [string]$SshFailureHint = 'Verify guest startup health and rerun after SSH becomes reachable.',
        [int]$SshPort = 0,
        [int]$SshConnectTimeoutSeconds = 5,
        [switch]$RequireSsh,
        [hashtable]$Context = $null
    )

    Write-Host ([string]$StartMessage) -ForegroundColor Cyan
    Invoke-ProdicloudWithAzCliTimeoutSeconds -TimeoutSeconds 900 -Action {
        Invoke-TrackedAction -Label ("az vm restart -g {0} -n {1}" -f [string]$ResourceGroup, [string]$VmName) -Action {
            az vm restart -g $ResourceGroup -n $VmName -o none --only-show-errors
            Assert-LastExitCode "az vm restart"
        } | Out-Null
    } | Out-Null

    $running = Wait-ProdicloudVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredPowerState 'VM running' -MaxAttempts 36 -DelaySeconds 10
    if (-not [bool]$running) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' did not return to running state after restart." -f [string]$VmName) `
            -Code 62 `
            -Summary $RunningFailureSummary `
            -Hint $RunningFailureHint
    }

    $provisioningRecovery = Wait-ProdicloudProvisioningReadyOrRepair -ResourceGroup $ResourceGroup -VmName $VmName
    if (-not [bool]$provisioningRecovery.Ready) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' provisioning did not recover after restart. {1}" -f [string]$VmName, (Format-ProdicloudVmLifecycleSummaryText -Snapshot $provisioningRecovery.Snapshot)) `
            -Code 62 `
            -Summary $ProvisioningFailureSummary `
            -Hint $ProvisioningFailureHint
    }

    $vmRuntimeDetails = $null
    $sshHost = ''
    $sshReady = $false
    if ($RequireSsh) {
        if ($SshPort -lt 1 -or $SshPort -gt 65535) {
            Throw-FriendlyError `
                -Detail "A valid SSH port is required for restart recovery." `
                -Code 62 `
                -Summary $HostFailureSummary `
                -Hint $HostFailureHint
        }

        $vmDetailContext = New-ProdicloudTaskRestartContext -Context $Context -ResourceGroup $ResourceGroup -VmName $VmName -AzLocation $AzLocation -SshPort $SshPort
        $vmRuntimeDetails = Get-ProdicloudVmDetails -Context $vmDetailContext
        $sshHost = [string]$vmRuntimeDetails.VmFqdn
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            $sshHost = [string]$vmRuntimeDetails.PublicIP
        }
        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
            Throw-FriendlyError `
                -Detail "SSH host could not be resolved after VM restart." `
                -Code 62 `
                -Summary $HostFailureSummary `
                -Hint $HostFailureHint
        }

        $sshReady = Wait-ProdicloudTcpPortReachable -HostName $sshHost -Port $SshPort -MaxAttempts 30 -DelaySeconds 10 -TimeoutSeconds $SshConnectTimeoutSeconds -Label 'ssh'
        if (-not [bool]$sshReady) {
            Throw-FriendlyError `
                -Detail ("SSH port {0} on '{1}' did not become reachable after VM restart." -f [int]$SshPort, [string]$sshHost) `
                -Code 62 `
                -Summary $SshFailureSummary `
                -Hint $SshFailureHint
        }
    }

    Write-Host ([string]$SuccessMessage) -ForegroundColor Green
    return [pscustomobject]@{
        VmRuntimeDetails = $vmRuntimeDetails
        SshHost = [string]$sshHost
        SshReady = [bool]$sshReady
    }
}
