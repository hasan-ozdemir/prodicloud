# SSH task VM wait helpers.

# Handles Wait-ClagnosVmPowerState.
function Wait-ClagnosVmPowerState {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [string]$DesiredPowerState = "VM running",
        [int]$MaxAttempts = 3,
        [int]$DelaySeconds = 10
    )

    if ([string]::IsNullOrWhiteSpace($DesiredPowerState)) {
        $DesiredPowerState = "VM running"
    }
    if ($MaxAttempts -lt 1) { $MaxAttempts = 1 }
    if ($MaxAttempts -gt 120) { $MaxAttempts = 120 }
    if ($DelaySeconds -lt 1) { $DelaySeconds = 1 }

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $powerState = az vm get-instance-view `
            --resource-group $ResourceGroup `
            --name $VmName `
            --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus | [0]" `
            -o tsv
        Assert-LastExitCode "az vm get-instance-view (power state)"

        if ([string]::IsNullOrWhiteSpace([string]$powerState)) {
            Write-Host ("VM power state is empty (attempt {0}/{1})." -f $attempt, $MaxAttempts) -ForegroundColor Yellow
        }
        else {
            Write-Host ("VM power state: {0} (attempt {1}/{2})" -f [string]$powerState, $attempt, $MaxAttempts)
            if ([string]::Equals([string]$powerState, [string]$DesiredPowerState, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        Start-Sleep -Seconds $DelaySeconds
    }

    return $false
}
