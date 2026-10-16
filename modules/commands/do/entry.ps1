# Do command entry.

# Handles Invoke-ClagnosDoCommand.
function Invoke-ClagnosDoCommand {
    param(
        [hashtable]$Options
    )

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot 'clagnos.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $configMap -OperationName 'do'
    $action = Resolve-ClagnosDoActionName -RawValue ([string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-action')) -AllowEmpty
    $snapshot = Get-ClagnosVmLifecycleSnapshot -ResourceGroup ([string]$target.ResourceGroup) -VmName ([string]$target.VmName)

    if ([string]::IsNullOrWhiteSpace([string]$action)) {
        $action = Read-ClagnosDoActionInteractive -Snapshot $snapshot
    }

    if ($action -eq 'status') {
        Write-ClagnosDoStatusReport -Snapshot $snapshot
        return
    }

    Assert-ClagnosDoActionAllowed -ActionName $action -Snapshot $snapshot

    $resourceGroup = [string]$target.ResourceGroup
    $vmName = [string]$target.VmName
    $initialNormalizedState = [string]$snapshot.NormalizedState
    $desiredState = ''
    $completionMessage = ''
    $finalSnapshot = $null

    switch ($action) {
        'start' {
            $desiredState = 'started'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' is now started." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','start','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm start'
        }
        'resume' {
            $desiredState = 'started'
            $completionMessage = ("Do completed: hibernated VM '{0}' in resource group '{1}' has resumed and is now started." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','start','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm start (resume)'
        }
        'restart' {
            $desiredState = 'started'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' is now restarted." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','restart','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm restart'
        }
        'reset' {
            $desiredState = 'started'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' was force-restarted through Azure redeploy." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','restart','-g',$resourceGroup,'-n',$vmName,'--force','-o','none','--only-show-errors') `
                -AzContext 'az vm restart --force'
        }
        'shutdown' {
            $desiredState = 'stopped'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' was shut down gracefully and remains allocated." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','stop','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm stop (graceful shutdown)'
        }
        'stop' {
            $desiredState = 'stopped'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' is now stopped." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','stop','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm stop'
        }
        'power-off' {
            $desiredState = 'stopped'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' was powered off immediately and remains allocated." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','stop','-g',$resourceGroup,'-n',$vmName,'--skip-shutdown','-o','none','--only-show-errors') `
                -AzContext 'az vm stop --skip-shutdown'
        }
        'deallocate' {
            $desiredState = 'deallocated'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' is now deallocated." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','deallocate','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm deallocate'
        }
        'hibernate-deallocate' {
            $desiredState = 'hibernated'
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' is now hibernated and deallocated." -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','deallocate','-g',$resourceGroup,'-n',$vmName,'--hibernate','true','-o','none','--only-show-errors') `
                -AzContext 'az vm deallocate --hibernate'
        }
        'hibernate-stop' {
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' accepted guest hibernate-stop and is no longer running." -f $vmName, $resourceGroup)
            $hibernateStopInvocation = Invoke-ClagnosDoGuestHibernateStopCommand -ResourceGroup $resourceGroup -VmName $vmName
            $finalSnapshot = Wait-ClagnosDoHibernateStopCompletion -Runtime $hibernateStopInvocation.Runtime -ResourceGroup $resourceGroup -VmName $vmName -MaxAttempts 24 -DelaySeconds 10
            if ($null -eq $finalSnapshot) {
                $launchOutput = if ($null -eq $hibernateStopInvocation -or $null -eq $hibernateStopInvocation.LaunchResult) { '' } else { [string]$hibernateStopInvocation.LaunchResult.Output }
                $launchExitCode = if ($null -eq $hibernateStopInvocation -or $null -eq $hibernateStopInvocation.LaunchResult) { -1 } else { [int]$hibernateStopInvocation.LaunchResult.ExitCode }
                Throw-FriendlyError `
                    -Detail ("VM '{0}' in resource group '{1}' did not leave the running state after guest hibernate-stop. Remote shutdown exit={2}. Output: {3}" -f $vmName, $resourceGroup, $launchExitCode, $launchOutput) `
                    -Code 66 `
                    -Summary "Hibernate-stop did not finish cleanly." `
                    -Hint "Confirm guest hibernation support, rerun '--vm-action=status', and use --vm-action=hibernate-deallocate if the Azure path is required."
            }
        }
        'reapply' {
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' was reapplied. Current status:" -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','reapply','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm reapply'
            $finalSnapshot = Get-ClagnosVmLifecycleSnapshot -ResourceGroup $resourceGroup -VmName $vmName
        }
        'redeploy' {
            $completionMessage = ("Do completed: VM '{0}' in resource group '{1}' was redeployed. Current status:" -f $vmName, $resourceGroup)
            Invoke-ClagnosDoAzureAction `
                -ActionName $action `
                -ResourceGroup $resourceGroup `
                -VmName $vmName `
                -AzArguments @('vm','redeploy','-g',$resourceGroup,'-n',$vmName,'-o','none','--only-show-errors') `
                -AzContext 'az vm redeploy'

            $provisioningWaitResult = Wait-ClagnosProvisioningSucceeded -ResourceGroup $resourceGroup -VmName $vmName -MaxAttempts 30 -DelaySeconds 10
            if (-not [bool]$provisioningWaitResult.Ready) {
                Throw-FriendlyError `
                    -Detail ("VM '{0}' in resource group '{1}' did not return to provisioning succeeded after Azure redeploy." -f $vmName, $resourceGroup) `
                    -Code 66 `
                    -Summary "VM redeploy completed in Azure but provisioning did not recover." `
                    -Hint "Check the VM provisioning state in Azure, run '--vm-action=status', then retry when the VM is healthy."
            }

            $finalSnapshot = $provisioningWaitResult.Snapshot
            if ([string]$initialNormalizedState -in @('started','stopped')) {
                $stateAfterRedeploy = Wait-ClagnosDoLifecycleState -ResourceGroup $resourceGroup -VmName $vmName -DesiredState $initialNormalizedState -MaxAttempts 24 -DelaySeconds 10
                if ($null -eq $stateAfterRedeploy) {
                    Throw-FriendlyError `
                        -Detail ("VM '{0}' in resource group '{1}' did not return to '{2}' after Azure redeploy." -f $vmName, $resourceGroup, $initialNormalizedState) `
                        -Code 66 `
                        -Summary "VM redeploy finished but the original lifecycle state did not recover." `
                        -Hint "Run '--vm-action=status' to inspect the live state, then start or stop the VM explicitly if Azure left it in a different state."
                }

                $finalSnapshot = $stateAfterRedeploy
            }
        }
        default {
            throw ("Unsupported do action '{0}'." -f $action)
        }
    }

    if ($null -eq $finalSnapshot) {
        $finalSnapshot = Wait-ClagnosDoLifecycleState -ResourceGroup $resourceGroup -VmName $vmName -DesiredState $desiredState -MaxAttempts 24 -DelaySeconds 10
    }
    if ($null -eq $finalSnapshot) {
        Throw-FriendlyError `
            -Detail ("VM '{0}' in resource group '{1}' did not reach expected '{2}' state after action '{3}'." -f $vmName, $resourceGroup, $desiredState, $action) `
            -Code 66 `
            -Summary ("VM action '{0}' did not reach the expected final state." -f $action) `
            -Hint "Check the VM status in Azure, run '--vm-action=status', then retry if needed."
    }

    Write-Host $completionMessage -ForegroundColor Green
    Write-ClagnosDoStatusReport -Snapshot $finalSnapshot
}
