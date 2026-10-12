# Run-command VM wait helpers.

# Handles Wait-ClagnosVmRunningState.
function Wait-ClagnosVmRunningState {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 10
    )

    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($MaxAttempts -gt 3) { $MaxAttempts = 3 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $powerState = az vm get-instance-view `
            --resource-group $ResourceGroup `
            --name $VmName `
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" `
            -o tsv
        Assert-LastExitCode "az vm get-instance-view (power state)"

        if ([string]::IsNullOrWhiteSpace([string]$powerState)) {
            Write-ClagnosActionProgress -Action ("VM power state is empty (attempt {0}/{1})" -f $attempt,$MaxAttempts)
        }
        else {
            Write-ClagnosActionProgress -Action ("VM power state: {0} (attempt {1}/{2})" -f [string]$powerState, $attempt, $MaxAttempts)
            if ([string]$powerState -eq "VM running") {
                return $true
            }
        }

        Write-ClagnosActionProgress -Action ("wait {0}s before checking VM power state again" -f $DelaySeconds)
        Start-Sleep -Seconds $DelaySeconds
    }

    return $false
}
