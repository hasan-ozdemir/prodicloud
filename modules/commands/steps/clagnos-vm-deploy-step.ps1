# VM deploy step orchestration.

function Invoke-ClagnosUpdateVmRedeploy {
    param(
        [string]$ResourceGroup,
        [string]$VmName,
        [switch]$AutoMode
    )

    $shouldRedeploy = $true
    if ($AutoMode) {
        Write-Host ("Update mode: VM redeploy for '{0}' was approved automatically." -f $VmName)
    }
    else {
        Write-Host ("Interactive review already approved Azure VM redeploy for '{0}'." -f $VmName) -ForegroundColor Yellow
    }

    Write-Host ("Update mode: redeploying existing VM '{0}' in resource group '{1}'..." -f $VmName, $ResourceGroup)
    Invoke-TrackedAction -Label ("az vm redeploy -g {0} -n {1}" -f $ResourceGroup, $VmName) -Action {
        az vm redeploy -g $ResourceGroup -n $VmName -o none --only-show-errors
        Assert-LastExitCode "az vm redeploy"
    } | Out-Null

    $provisioningWaitResult = Wait-ClagnosProvisioningSucceeded -ResourceGroup $ResourceGroup -VmName $VmName -MaxAttempts 30 -DelaySeconds 10
    if (-not [bool]$provisioningWaitResult.Ready) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' did not return to provisioning succeeded after Azure redeploy." -f $VmName) `
            -Code 62 `
            -Summary "Update mode completed Azure redeploy but VM provisioning did not recover." `
            -Hint "Check the VM provisioning state in Azure Portal before rerunning update."
    }

    $running = Wait-ClagnosVmPowerState -ResourceGroup $ResourceGroup -VmName $VmName -DesiredPowerState "VM running" -MaxAttempts 18 -DelaySeconds 10
    if (-not $running) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' did not return to running state after Azure redeploy." -f $VmName) `
            -Code 62 `
            -Summary "Update mode completed Azure redeploy but the VM is not running." `
            -Hint "Check the VM power state in Azure and start the VM manually if needed."
    }

    Write-Host ("Update mode: VM redeploy completed successfully for '{0}'." -f $VmName) -ForegroundColor Green
}

# Handles Invoke-ClagnosVmCreateStep.
function Invoke-ClagnosVmCreateStep {
    param(
        [hashtable]$Context,
        [switch]$AutoMode,
        [switch]$UpdateMode,
        [ValidateSet("default","update")]
        [string]$ExecutionMode = "default",
        [scriptblock]$CreateVmAction
    )

    if (-not $CreateVmAction) {
        throw "CreateVmAction is required."
    }

    $resourceGroup = [string]$Context.ResourceGroup
    $effectiveMode = if ([string]::IsNullOrWhiteSpace([string]$ExecutionMode)) { "default" } else { [string]$ExecutionMode.Trim().ToLowerInvariant() }
    $vmName = [string]$Context.VmName
    Show-ClagnosStepFirstUseValues `
        -StepLabel "Step 4/7 - VM create" `
        -Context $Context `
        -Keys @("ResourceGroup", "VmName", "VmImage", "VmSize", "VmStorageSku", "VmSecurityType", "VmEnableSecureBoot", "VmEnableVtpm", "VmDiskName", "VmDiskSize", "VmUser", "VmPass", "VmAssistantUser", "VmAssistantPass", "NIC") `
        -ExtraValues @{
            VmExecutionMode = $effectiveMode
        }

    $existingVM = az vm list `
        --resource-group $resourceGroup `
        --query "[?name=='$vmName'].name | [0]" `
        -o tsv `
        --only-show-errors 2>$null
    Assert-LastExitCode "az vm list"

    $hasExistingVm = -not [string]::IsNullOrWhiteSpace([string]$existingVM)
    $shouldDeleteVm = $false
    $shouldCreateVm = $true
    $vmDeletedInThisRun = $false
    if ($hasExistingVm) {
        Write-Host "VM '$vmName' exists in resource group '$resourceGroup'."

        switch ($effectiveMode) {
            "default" {
                $shouldCreateVm = $false
                Write-Host "Default mode: existing VM '$vmName' will be kept; create step is skipped." -ForegroundColor Yellow
            }
            "update" {
                Write-Host "Update mode: existing VM will be kept; az vm create will run in create-or-update mode." -ForegroundColor Yellow
            }
        }

        if ($shouldDeleteVm) {
            Write-Host "VM '$vmName' will be deleted..."
            Invoke-TrackedAction -Label "az vm delete --name $vmName --resource-group $resourceGroup --yes" -Action {
                az vm delete --name $vmName --resource-group $resourceGroup --yes -o table
                Assert-LastExitCode "az vm delete"
            } | Out-Null
            Write-Host "VM '$vmName' was deleted from resource group '$resourceGroup'."
            $vmDeletedInThisRun = $true
        }
        elseif ($effectiveMode -ne "default") {
            Write-Host "VM '$vmName' was not deleted by user choice; continuing with az vm create on existing VM." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "VM '$vmName' is not present in resource group '$resourceGroup'. Creating..."
    }

    if (-not $shouldCreateVm) {
        return [pscustomobject]@{
            VmExistsBefore = [bool]$hasExistingVm
            VmDeleted = [bool]$vmDeletedInThisRun
            VmCreateInvoked = $false
            VmCreatedThisRun = $false
            VmId = ""
        }
    }

    $vmCreatedThisRun = (-not $hasExistingVm) -or $vmDeletedInThisRun
    $vmCreateJson = Invoke-TrackedAction -Label "az vm create --resource-group $resourceGroup --name $vmName" -Action {
        $result = & $CreateVmAction
        if ($LASTEXITCODE -ne 0) {
            $createExitCode = [int]$LASTEXITCODE
            $vmExistsAfterCreate = ""
            Write-Warning "az vm create returned a non-zero code; checking VM existence."
            # Azure can return a transient non-zero create result even when the VM deployment
            # eventually lands successfully. Keep the probe bounded so real failures still fail
            # quickly, but do not misclassify a completed VM deployment as a hard create error.
            $shouldUseLongPresenceProbe = (($effectiveMode -eq "update") -and $hasExistingVm)
            $presenceProbeAttempts = if ($shouldUseLongPresenceProbe) { 12 } elseif ($vmCreatedThisRun) { 6 } else { 3 }
            for ($presenceAttempt = 1; $presenceAttempt -le $presenceProbeAttempts; $presenceAttempt++) {
                $vmExistsAfterCreate = if (Test-ClagnosAzResourceExists -AzArgs @("vm", "show", "-g", $resourceGroup, "-n", $vmName)) {
                    az vm show -g $resourceGroup -n $vmName --query "id" -o tsv --only-show-errors 2>$null
                }
                else {
                    ""
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$vmExistsAfterCreate)) {
                    break
                }

                if ($presenceAttempt -lt $presenceProbeAttempts) {
                    Write-ClagnosActionProgress -Action ("wait 10s for VM create result to appear (probe {0}/{1})" -f $presenceAttempt,$presenceProbeAttempts)
                    Start-Sleep -Seconds 10
                }
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$vmExistsAfterCreate)) {
                Write-Host "VM exists; details will be retrieved via az vm show -d."
                $result = az vm show -g $resourceGroup -n $vmName -d -o json --only-show-errors 2>$null
                Assert-LastExitCode "az vm show -d after vm create non-zero"
            }
            else {
                throw "az vm create failed with exit code $createExitCode."
            }
        }

        $result
    }

    $vmCreateObj = ConvertFrom-JsonCompat -InputObject $vmCreateJson
    if (-not $vmCreateObj.id) {
        throw "az vm create completed but VM id was not returned."
    }

    Write-Host "Printing az vm create output..."
    Write-Host $vmCreateJson

    if ($effectiveMode -eq 'update' -and $hasExistingVm -and -not $vmDeletedInThisRun) {
        Invoke-ClagnosUpdateVmRedeploy -ResourceGroup $resourceGroup -VmName $vmName -AutoMode:$AutoMode
    }

    $featureEnablementResult = Invoke-ClagnosPostDeployFeatureEnablement -Context $Context -VmCreatedThisRun:$vmCreatedThisRun

    return [pscustomobject]@{
        VmExistsBefore = [bool]$hasExistingVm
        VmDeleted = [bool]$vmDeletedInThisRun
        VmCreateInvoked = $true
        VmCreatedThisRun = [bool]$vmCreatedThisRun
        VmId = [string]$vmCreateObj.id
        HibernationAttempted = [bool]$featureEnablementResult.HibernationAttempted
        HibernationEnabled = [bool]$featureEnablementResult.HibernationEnabled
        HibernationMessage = [string]$featureEnablementResult.HibernationMessage
        NestedAttempted = [bool]$featureEnablementResult.NestedAttempted
        NestedAvailableToGuest = [bool]$featureEnablementResult.NestedAvailableToGuest
        NestedMessage = [string]$featureEnablementResult.NestedMessage
    }
}
