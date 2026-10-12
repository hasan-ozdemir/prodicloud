# Main create/update command pipeline.

function Write-ClagnosWorkflowSummary {
    param(
        [hashtable]$Context,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [hashtable]$PlatformDefaults,
        [string]$RepoRoot = '',
        [string]$ConfiguredPySshClientPath = '',
        [int]$SshConnectTimeoutSeconds = 30,
        [string[]]$CompletedStages,
        [string[]]$SkippedStages,
        [string]$CancelledStage = ''
    )

    Write-Host ""
    Write-Host "Workflow summary" -ForegroundColor DarkCyan
    Write-Host ("- completed: {0}" -f $(if (@($CompletedStages).Count -gt 0) { @($CompletedStages) -join ', ' } else { '(none)' }))
    Write-Host ("- skipped: {0}" -f $(if (@($SkippedStages).Count -gt 0) { @($SkippedStages) -join ', ' } else { '(none)' }))
    if (-not [string]::IsNullOrWhiteSpace([string]$CancelledStage)) {
        Write-Host ("- cancelled at: {0}" -f [string]$CancelledStage) -ForegroundColor Yellow
    }

    if ($null -eq $Context) {
        return
    }

    $resourceGroup = [string]$Context.ResourceGroup
    $vmName = [string]$Context.VmName
    if ([string]::IsNullOrWhiteSpace([string]$resourceGroup) -or [string]::IsNullOrWhiteSpace([string]$vmName)) {
        return
    }

    if (-not (Test-ClagnosAzResourceExists -AzArgs @("vm", "show", "-g", $resourceGroup, "-n", $vmName))) {
        Write-Host ("VM summary: VM '{0}' is not present yet; connection details are unavailable." -f $vmName) -ForegroundColor Yellow
        return
    }

    Invoke-ClagnosWorkflowSummaryReadback `
        -Context $Context `
        -Platform $Platform `
        -RepoRoot $RepoRoot `
        -ConfiguredPySshClientPath $ConfiguredPySshClientPath `
        -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds

    $connectionModel = if ([bool]$PlatformDefaults.IncludeRdp) {
        Get-ClagnosConnectionDisplayModel -Context $Context -ManagerUser ([string]$Context.VmUser) -AssistantUser ([string]$Context.VmAssistantUser) -SshPort ([string]$Context.SshPort) -RdpPort ([string]$Context.RdpPort) -PowerShellPort '5985' -IncludeRdp -IncludePowerShellRemoting
    }
    else {
        Get-ClagnosConnectionDisplayModel -Context $Context -ManagerUser ([string]$Context.VmUser) -AssistantUser ([string]$Context.VmAssistantUser) -SshPort ([string]$Context.SshPort)
    }

    Write-Host ("- public-ip: {0}" -f [string]$connectionModel.PublicIP)
    Write-Host ("- host: {0}" -f [string]$connectionModel.ConnectionHost)
    Write-Host "SSH connection commands:"
    foreach ($sshConnection in @($connectionModel.SshConnections)) {
        Write-Host ("- {0}: {1}" -f ([string]$sshConnection.User), ([string]$sshConnection.Command))
    }

    if ([bool]$PlatformDefaults.IncludeRdp) {
        Write-Host "RDP connection commands:"
        foreach ($rdpConnection in @($connectionModel.RdpConnections)) {
            Write-Host ("- {0}: {1}" -f ([string]$rdpConnection.User), ([string]$rdpConnection.Command))
            Write-Host ("  username: {0}" -f ([string]$rdpConnection.Username))
        }
    }

    if ($connectionModel.Contains('PowerShellConnections')) {
        Write-Host "PowerShell remoting commands:"
        foreach ($psConnection in @($connectionModel.PowerShellConnections)) {
            Write-Host ("- {0}: {1}" -f ([string]$psConnection.User), ([string]$psConnection.EnterPSSessionCommand))
            Write-Host ("  username: {0}" -f ([string]$psConnection.Username))
            Write-Host ("  trusted-hosts: {0}" -f ([string]$psConnection.TrustedHostsCommand))
            Write-Host ("  invoke-command: {0}" -f ([string]$psConnection.InvokeCommand))
        }
    }
}

# Handles Invoke-ClagnosMain.
function Invoke-ClagnosMain {
    param(
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [ValidateSet('create','update','initialize')]
        [string]$CommandName = 'create',
        [ValidateSet('create','update','configure','generic')]
        [string]$Step1OperationName = '',
        [hashtable]$InitialConfigOverrides = @{},
        [psobject]$ActionPlan = $null
    )

    try {
        $script:HadError = $false
        $script:ExitCode = 0
        $script:TranscriptStarted = $false
        $repoRoot = Get-ClagnosRepoRoot
        chcp 65001 | Out-Null
        $Host.UI.RawUI.WindowTitle = 'Clagnos'

        $effectiveActionPlan = $ActionPlan
        if ($null -eq $effectiveActionPlan) {
            $effectiveActionPlan = [pscustomobject]@{
                Mode = 'full'
                Target = 'vm-summary'
                Actions = @(Get-ClagnosActionOrder)
            }
        }

        $logTimestamp = (Get-Date).ToString('ddMMMyy-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture).ToLowerInvariant()
        $logPath = Join-Path $repoRoot ("clagnos-log-{0}.txt" -f $logTimestamp)
        Start-Transcript -Path $logPath -Force
        $script:TranscriptStarted = $true

        $effectiveStep1OperationName = if ([string]::IsNullOrWhiteSpace([string]$Step1OperationName)) { [string]$CommandName } else { [string]$Step1OperationName }
        $runtime = Initialize-ClagnosCommandRuntimeContext `
            -AutoMode:$script:AutoMode `
            -WindowsFlag:$WindowsFlag `
            -LinuxFlag:$LinuxFlag `
            -ConfigMapOverrides $InitialConfigOverrides `
            -OperationName $effectiveStep1OperationName `
            -UseInteractiveStep1 `
            -PersistGeneratedResourceGroup `
            -DeferDotEnvWrites

        $step1Context = $runtime.Context
        $platform = [string]$runtime.Platform
        $platformDefaults = $runtime.PlatformDefaults
        $effectiveConfigMap = $runtime.EffectiveConfigMap
        $envFilePath = [string]$runtime.EnvFilePath
        $taskOutcomeMode = [string]$runtime.TaskOutcomeMode
        $configuredPySshClientPath = [string]$runtime.ConfiguredPySshClientPath
        $sshTaskTimeoutSeconds = [int]$runtime.SshTaskTimeoutSeconds
        $sshConnectTimeoutSeconds = [int]$runtime.SshConnectTimeoutSeconds
        $modeLabel = if ($script:AutoMode) { 'auto' } else { 'interactive' }
        $platformVmImageKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
        $platformVmSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'
        $platformVmDiskSizeKey = Get-ClagnosPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'

        Write-ClagnosMainBanner `
            -CommandName $CommandName `
            -Mode $modeLabel `
            -Platform $platform `
            -ActionPlan $effectiveActionPlan `
            -LogPath $logPath `
            -SubscriptionName ([string]$step1Context.AzureSubscriptionName) `
            -SubscriptionId ([string]$step1Context.AzureSubscriptionId)

        $runGroupAction = Test-ClagnosActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'group'
        $runNetworkAction = Test-ClagnosActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'network'
        $runDeployAction = Test-ClagnosActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'vm-deploy'
        $runInitAction = Test-ClagnosActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'vm-init'
        $runUpdateAction = Test-ClagnosActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'vm-update'
        $shouldRunPrecheck = (Test-ClagnosActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'configure') -or $runGroupAction -or $runNetworkAction -or $runDeployAction

        if ([string]::Equals([string]$effectiveActionPlan.Mode, 'single', [System.StringComparison]::OrdinalIgnoreCase)) {
            $singleTarget = [string]$effectiveActionPlan.Target
            if ($singleTarget -in @('network', 'vm-deploy', 'vm-init', 'vm-update')) {
                Assert-ClagnosSingleActionDependencies -ActionName $singleTarget -Context $step1Context
            }
        }

        $completedStages = New-Object System.Collections.ArrayList
        $skippedStages = New-Object System.Collections.ArrayList
        $cancelledStage = ''

        Invoke-Step 'Step 1/7 - Configuration review' {
            if ($script:AutoMode) {
                Show-ClagnosRuntimeConfigurationSnapshot -Platform $platform -ScriptName 'clagnos.ps1' -ScriptRoot $repoRoot -AutoMode:$script:AutoMode -UpdateMode:$script:UpdateMode -ConfigMap $effectiveConfigMap -ConfigOverrides $script:ConfigOverrides -Context $step1Context
            }
            else {
                Show-ClagnosStepReview -Title 'Configuration review' -Values (New-ClagnosStep1ConfigDisplayMap -Platform $platform -Context $step1Context -OperationName $CommandName) -TaskTitle '' -TaskBlocks @()
            }
            if ($shouldRunPrecheck) {
                Invoke-ClagnosPrecheckStep -Context $step1Context
            }
            else {
                Write-Host "Precheck was skipped because the selected step window does not mutate Azure create/deploy inputs." -ForegroundColor Yellow
            }
        }
        [void]$completedStages.Add('configure')

        if ($runGroupAction) {
            $groupDecision = Invoke-ClagnosReviewCheckpoint `
                -AutoMode:$script:AutoMode `
                -StageName 'resource group step' `
                -Values ([ordered]@{
                    AzureSubscriptionName = [string]$step1Context.AzureSubscriptionName
                    SELECTED_AZURE_SUBSCRIPTION_ID = [string]$step1Context.AzureSubscriptionId
                    SELECTED_RESOURCE_GROUP = [string]$step1Context.ResourceGroup
                    SELECTED_AZURE_REGION = [string]$step1Context.AzLocation
                    EXECUTION_MODE = [string]$script:ExecutionMode
                }) `
                -TaskTitle '' `
                -TaskBlocks @() `
                -CompletedStages @($completedStages) `
                -SkippedStages @($skippedStages)

            switch ($groupDecision) {
                'cancel' {
                    $cancelledStage = 'group'
                }
                'no' {
                    Write-Host "Resource group step was skipped by user choice." -ForegroundColor Yellow
                    [void]$skippedStages.Add('group')
                }
                default {
                    Invoke-ClagnosPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    Invoke-Step 'Step 2/7 - Resource group' {
                        Invoke-ClagnosResourceGroupStep -Context $step1Context -AutoMode:$script:AutoMode -UpdateMode:$script:UpdateMode -ExecutionMode $script:ExecutionMode
                    }
                    [void]$completedStages.Add('group')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cancelledStage)) {
            Write-ClagnosWorkflowSummary -Context $step1Context -Platform $platform -PlatformDefaults $platformDefaults -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
            Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
            return
        }

        if ($runNetworkAction) {
            Invoke-ClagnosPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
            Invoke-Step 'Step 3/7 - Network' {
                Invoke-ClagnosNetworkStep -Context $step1Context -ExecutionMode $script:ExecutionMode
            }
            [void]$completedStages.Add('network')
        }

        if ($runDeployAction) {
            $deployDecision = Invoke-ClagnosReviewCheckpoint `
                -AutoMode:$script:AutoMode `
                -StageName 'vm deploy step' `
                -Values ([ordered]@{
                    AzureSubscriptionName = [string]$step1Context.AzureSubscriptionName
                    SELECTED_AZURE_SUBSCRIPTION_ID = [string]$step1Context.AzureSubscriptionId
                    SELECTED_RESOURCE_GROUP = [string]$step1Context.ResourceGroup
                    SELECTED_VM_NAME = [string]$step1Context.VmName
                    $platformVmImageKey = [string]$step1Context.VmImage
                    $platformVmSizeKey = [string]$step1Context.VmSize
                    VM_STORAGE_SKU = [string]$step1Context.VmStorageSku
                    VM_DISK_NAME = [string]$step1Context.VmDiskName
                    $platformVmDiskSizeKey = [string]$step1Context.VmDiskSize
                    NIC_NAME = [string]$step1Context.NIC
                    EXECUTION_MODE = [string]$script:ExecutionMode
                }) `
                -TaskTitle '' `
                -TaskBlocks @() `
                -CompletedStages @($completedStages) `
                -SkippedStages @($skippedStages)

            switch ($deployDecision) {
                'cancel' {
                    $cancelledStage = 'vm-deploy'
                }
                'no' {
                    Write-Host "VM deploy step was skipped by user choice." -ForegroundColor Yellow
                    [void]$skippedStages.Add('vm-deploy')
                }
                default {
                    Invoke-ClagnosPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    Invoke-Step 'Step 4/7 - VM deploy' {
                        Invoke-ClagnosVmCreateStep -Context $step1Context -AutoMode:$script:AutoMode -UpdateMode:$script:UpdateMode -ExecutionMode $script:ExecutionMode -CreateVmAction {
                            $vmCreateSecurityArgs = @(Get-ClagnosCreateSecurityArgumentsForCurrentVmState -Context $step1Context -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName))
                            az vm create --resource-group ([string]$step1Context.ResourceGroup) --name ([string]$step1Context.VmName) --image ([string]$step1Context.VmImage) --size ([string]$step1Context.VmSize) --storage-sku ([string]$step1Context.VmStorageSku) --os-disk-name ([string]$step1Context.VmDiskName) --os-disk-size-gb ([string]$step1Context.VmDiskSize) --admin-username ([string]$step1Context.VmUser) --admin-password ([string]$step1Context.VmPass) --authentication-type password --nics ([string]$step1Context.NIC) @vmCreateSecurityArgs -o json --only-show-errors
                        } | Out-Null
                    }
                    [void]$completedStages.Add('vm-deploy')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cancelledStage)) {
            Write-ClagnosWorkflowSummary -Context $step1Context -Platform $platform -PlatformDefaults $platformDefaults -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
            Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
            return
        }

        $initReview = $null
        $initTaskBlocks = @()
        $initDisabledTasks = @()
        $vmUpdateStageResult = [pscustomobject]@{
            RebootRequired = $false
            RebootCount = 0
        }

        if ($runInitAction) {
            $initReview = Get-ClagnosReviewTaskRows -DirectoryPath ([string]$step1Context.VmInitTaskDir) -Platform $platform -Stage 'init' -Context $step1Context
            $initTaskBlocks = @($initReview.ActiveTasks)
            $initDisabledTasks = @($initReview.DisabledTasks)

            $initDecision = Invoke-ClagnosReviewCheckpoint `
                -AutoMode:$script:AutoMode `
                -StageName 'vm-init step' `
                -Values ([ordered]@{
                    Platform = $platform
                    VmInitTaskDir = [string]$step1Context.VmInitTaskDir
                    ActiveTaskCount = @($initTaskBlocks).Count
                    DisabledTaskCount = @($initDisabledTasks).Count
                }) `
                -TaskTitle 'vm-init tasks:' `
                -TaskBlocks $initTaskBlocks `
                -CompletedStages @($completedStages) `
                -SkippedStages @($skippedStages)

            switch ($initDecision) {
                'cancel' {
                    $cancelledStage = 'vm-init'
                }
                'no' {
                    Write-Host "VM init step was skipped by user choice." -ForegroundColor Yellow
                    [void]$skippedStages.Add('vm-init')
                }
                default {
                    Invoke-ClagnosPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    Invoke-Step 'Step 5/7 - VM init' {
                        if (@($initDisabledTasks).Count -gt 0) {
                            $disabledNames = @($initDisabledTasks | ForEach-Object { [string]$_.Name })
                            Write-Host ("Disabled init tasks (ignored): {0}" -f ($disabledNames -join ', ')) -ForegroundColor Yellow
                        }

                        if (@($initTaskBlocks).Count -eq 0) {
                            Write-Host 'Init task folder inventory is empty; Step 5 vm-init stage is skipped.' -ForegroundColor Yellow
                        }
                        else {
                            $combinedShell = if ($platform -eq 'linux') { 'bash' } else { 'powershell' }
                            $provisioningWaitResult = Wait-ClagnosProvisioningReadyOrRepair -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName)
                            if (-not [bool]$provisioningWaitResult.Ready) {
                                Throw-FriendlyError `
                                    -Detail ("VM '{0}' is still not provisioning-ready before vm-init." -f [string]$step1Context.VmName) `
                                    -Code 62 `
                                    -Summary "VM init cannot start while Azure provisioning is still not ready." `
                                    -Hint "Wait for Azure provisioning to recover and rerun create, or inspect the VM in Azure Portal if the automatic redeploy repair did not resolve the issue."
                            }
                            $initVmRuntimeDetails = Get-ClagnosVmDetails -Context $step1Context
                            $initSshHost = [string]$initVmRuntimeDetails.VmFqdn
                            if ([string]::IsNullOrWhiteSpace([string]$initSshHost)) {
                                $initSshHost = [string]$initVmRuntimeDetails.PublicIP
                            }
                            Invoke-VmRunCommandBlocks -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName) -CommandId ([string]$platformDefaults.RunCommandId) -TaskBlocks $initTaskBlocks -CombinedShell $combinedShell -TaskOutcomeMode $taskOutcomeMode -Platform $platform -RepoRoot (Get-ClagnosRepoRoot) -ManagerUser ([string]$step1Context.VmUser) -AssistantUser ([string]$step1Context.VmAssistantUser) -SshHost $initSshHost -SshUser ([string]$step1Context.VmUser) -SshPassword ([string]$step1Context.VmPass) -SshPort ([string]$step1Context.SshPort) -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -ConfiguredPySshClientPath $configuredPySshClientPath | Out-Null
                            Write-Host 'Waiting 20 seconds for SSH service to settle after init...'
                            Start-Sleep -Seconds 20
                        }
                    }
                    [void]$completedStages.Add('vm-init')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cancelledStage)) {
            Write-ClagnosWorkflowSummary -Context $step1Context -PlatformDefaults $platformDefaults -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
            Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
            return
        }

        if ($runUpdateAction) {
            $updateReview = Get-ClagnosReviewTaskRows -DirectoryPath ([string]$step1Context.VmUpdateTaskDir) -Platform $platform -Stage 'update' -Context $step1Context
            $allUpdateTaskBlocks = @($updateReview.ActiveTasks)
            $updateTaskBlocks = @($allUpdateTaskBlocks | Where-Object { $null -eq $_.ProgramSpec })
            $programTaskCount = @($allUpdateTaskBlocks | Where-Object { $null -ne $_.ProgramSpec }).Count
            $updateDisabledTasks = @($updateReview.DisabledTasks)

            $updateDecision = Invoke-ClagnosReviewCheckpoint `
                -AutoMode:$script:AutoMode `
                -StageName 'vm-update step' `
                -Values ([ordered]@{
                    Platform = $platform
                    VmUpdateTaskDir = [string]$step1Context.VmUpdateTaskDir
                    ActiveTaskCount = @($updateTaskBlocks).Count
                    ProgramTaskCount = [int]$programTaskCount
                    DisabledTaskCount = @($updateDisabledTasks).Count
                    TaskOutcomeMode = $taskOutcomeMode
                }) `
                -TaskTitle 'vm-update tasks:' `
                -TaskBlocks $updateTaskBlocks `
                -CompletedStages @($completedStages) `
                -SkippedStages @($skippedStages)

            switch ($updateDecision) {
                'cancel' {
                    $cancelledStage = 'vm-update'
                }
                'no' {
                    Write-Host "VM update step was skipped by user choice." -ForegroundColor Yellow
                    [void]$skippedStages.Add('vm-update')
                }
                default {
                    Invoke-ClagnosPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    $vmUpdateStageResult = Invoke-Step 'Step 6/7 - VM update' {
                        if ($programTaskCount -gt 0) {
                            Write-Host ("Program tasks are managed from the program menu and were skipped: {0}" -f [int]$programTaskCount) -ForegroundColor DarkCyan
                        }
                        if (@($updateDisabledTasks).Count -gt 0) {
                            $disabledNames = @($updateDisabledTasks | ForEach-Object { [string]$_.Name })
                            Write-Host ("Disabled update tasks (ignored): {0}" -f ($disabledNames -join ', ')) -ForegroundColor Yellow
                        }

                        if (@($updateTaskBlocks).Count -eq 0) {
                            Write-Host 'Update task folder inventory is empty; Step 6 vm-update stage is skipped.' -ForegroundColor Yellow
                            return $null
                        }
                        $vmRuntimeDetails = Get-ClagnosVmDetails -Context $step1Context
                        $sshHost = [string]$vmRuntimeDetails.VmFqdn
                        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
                            $sshHost = [string]$vmRuntimeDetails.PublicIP
                        }
                        if ([string]::IsNullOrWhiteSpace([string]$sshHost)) {
                            throw 'Step 6 could not resolve VM SSH host (FQDN/Public IP).'
                        }

                        $sshMaxRetries = 1
                        if ($platform -ne 'windows') {
                            $sshMaxRetriesText = [string](Get-ConfigValue -Config $effectiveConfigMap -Key 'SSH_MAX_RETRIES' -DefaultValue '3')
                            $sshMaxRetries = Resolve-ClagnosSshRetryCount -RetryText $sshMaxRetriesText -DefaultValue 3
                        }

                        return (Invoke-ClagnosSshTaskBlocks -Platform $platform -RepoRoot $repoRoot -SshHost $sshHost -SshUser ([string]$step1Context.VmUser) -SshPassword ([string]$step1Context.VmPass) -SshPort ([string]$step1Context.SshPort) -AssistantUser ([string]$step1Context.VmAssistantUser) -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName) -TaskBlocks $updateTaskBlocks -TaskOutcomeMode $taskOutcomeMode -SshMaxRetries $sshMaxRetries -SshTaskTimeoutSeconds $sshTaskTimeoutSeconds -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -ConfiguredPySshClientPath $configuredPySshClientPath -EnableFinalVmRestart)
                    }
                    [void]$completedStages.Add('vm-update')
                }
            }
        }

        [void]$completedStages.Add('vm-summary')
        Invoke-Step 'Step 7/7 - VM summary' {
            Write-ClagnosWorkflowSummary -Context $step1Context -Platform $platform -PlatformDefaults $platformDefaults -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
        }
        Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
    }
    catch {
        $resolvedError = Resolve-ClagnosFriendlyError -ErrorRecord $_ -DefaultErrorSummary $script:DefaultErrorSummary -DefaultErrorHint $script:DefaultErrorHint

        Write-Host ''
        Write-Host 'Script exited gracefully.' -ForegroundColor Yellow
        Write-Host ("Reason: {0}" -f $resolvedError.Summary) -ForegroundColor Red
        Write-Host ("Detail: {0}" -f $resolvedError.ErrorMessage)
        Write-Host ("Suggested action: {0}" -f $resolvedError.Hint) -ForegroundColor Cyan
        $script:HadError = $true
        $script:ExitCode = [int]$resolvedError.Code
    }
    finally {
        if ($script:TranscriptStarted) {
            try {
                Stop-Transcript -ErrorAction Stop | Out-Null
            }
            catch {
                Write-Host ("Transcript stop skipped: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
            }
            finally {
                $script:TranscriptStarted = $false
            }
        }
    }

    if ($script:HadError) {
        exit $script:ExitCode
    }
}
