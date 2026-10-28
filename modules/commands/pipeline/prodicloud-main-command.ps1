# Main create/update command pipeline.

function Write-ProdicloudWorkflowSummary {
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

    if (-not (Test-ProdicloudAzResourceExists -AzArgs @("vm", "show", "-g", $resourceGroup, "-n", $vmName))) {
        Write-Host ("VM summary: VM '{0}' is not present yet; connection details are unavailable." -f $vmName) -ForegroundColor Yellow
        return
    }

    Invoke-ProdicloudWorkflowSummaryReadback `
        -Context $Context `
        -Platform $Platform `
        -RepoRoot $RepoRoot `
        -ConfiguredPySshClientPath $ConfiguredPySshClientPath `
        -SshConnectTimeoutSeconds $SshConnectTimeoutSeconds

    $connectionModel = if ([bool]$PlatformDefaults.IncludeRdp) {
        Get-ProdicloudConnectionDisplayModel -Context $Context -ManagerUser ([string]$Context.VmUser) -AssistantUser ([string]$Context.VmAssistantUser) -SshPort ([string]$Context.SshPort) -RdpPort ([string]$Context.RdpPort) -PowerShellPort (Get-ProdicloudDefaultPowerShellPortText) -IncludeRdp -IncludePowerShellRemoting
    }
    else {
        Get-ProdicloudConnectionDisplayModel -Context $Context -ManagerUser ([string]$Context.VmUser) -AssistantUser ([string]$Context.VmAssistantUser) -SshPort ([string]$Context.SshPort)
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
            Write-Host ("- prodicloud: pd.cmd connect --powershell --group {0} --vm-name {1} --user {2}" -f [string]$Context.ResourceGroup, [string]$Context.VmName, [string]$psConnection.User)
            Write-Host ("  test: pd.cmd connect --powershell --group {0} --vm-name {1} --user {2} --test" -f [string]$Context.ResourceGroup, [string]$Context.VmName, [string]$psConnection.User)
            Write-Host ("- {0}: {1}" -f ([string]$psConnection.User), ([string]$psConnection.EnterPSSessionCommand))
            Write-Host ("  username: {0}" -f ([string]$psConnection.Username))
            Write-Host ("  trusted-hosts: {0}" -f ([string]$psConnection.TrustedHostsCommand))
            Write-Host ("  invoke-command: {0}" -f ([string]$psConnection.InvokeCommand))
        }
    }
}

# Handles Invoke-ProdicloudMain.
function Invoke-ProdicloudMain {
    param(
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [ValidateSet('create','update','initialize')]
        [string]$CommandName = 'create',
        [ValidateSet('create','update','configure','generic')]
        [string]$Step1OperationName = '',
        [hashtable]$InitialConfigOverrides = @{},
        [psobject]$ActionPlan = $null,
        [switch]$WizardMode
    )

    try {
        $script:HadError = $false
        $script:ExitCode = 0
        $script:TranscriptStarted = $false
        $repoRoot = Get-ProdicloudRepoRoot
        chcp 65001 | Out-Null
        $Host.UI.RawUI.WindowTitle = 'Prodicloud'

        $effectiveActionPlan = $ActionPlan
        if ($null -eq $effectiveActionPlan) {
            $effectiveActionPlan = [pscustomobject]@{
                Mode = 'full'
                Target = 'vm-summary'
                Actions = @(Get-ProdicloudActionOrder)
            }
        }

        $logTimestamp = (Get-Date).ToString('ddMMMyy-HHmmss', [System.Globalization.CultureInfo]::InvariantCulture).ToLowerInvariant()
        $logRoot = Join-Path $repoRoot '.logs'
        if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }
        $logPath = Join-Path $logRoot ("prodicloud-log-{0}.txt" -f $logTimestamp)
        Start-Transcript -Path $logPath -Force
        $script:TranscriptStarted = $true

        $effectiveStep1OperationName = if ([string]::IsNullOrWhiteSpace([string]$Step1OperationName)) { [string]$CommandName } else { [string]$Step1OperationName }
        $runtime = Initialize-ProdicloudCommandRuntimeContext `
            -AutoMode:$script:AutoMode `
            -WindowsFlag:$WindowsFlag `
            -LinuxFlag:$LinuxFlag `
            -ConfigMapOverrides $InitialConfigOverrides `
            -OperationName $effectiveStep1OperationName `
            -UseInteractiveStep1 `
            -WizardMode:$WizardMode `
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
        $platformVmImageKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_IMAGE'
        $platformVmSizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_SIZE'
        $platformVmDiskSizeKey = Get-ProdicloudPlatformVmConfigKey -Platform $platform -BaseKey 'VM_DISK_SIZE_GB'

        Write-ProdicloudMainBanner `
            -CommandName $CommandName `
            -Mode $modeLabel `
            -Platform $platform `
            -ActionPlan $effectiveActionPlan `
            -LogPath $logPath `
            -SubscriptionName ([string]$step1Context.AzureSubscriptionName) `
            -SubscriptionId ([string]$step1Context.AzureSubscriptionId)

        $runGroupAction = Test-ProdicloudActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'group'
        $runNetworkAction = Test-ProdicloudActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'network'
        $runDeployAction = Test-ProdicloudActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'vm-deploy'
        $runInitAction = Test-ProdicloudActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'vm-init'
        $runUpdateAction = Test-ProdicloudActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'vm-update'
        $shouldRunPrecheck = (Test-ProdicloudActionIncluded -ActionPlan $effectiveActionPlan -ActionName 'configure') -or $runGroupAction -or $runNetworkAction -or $runDeployAction

        if ([string]::Equals([string]$effectiveActionPlan.Mode, 'single', [System.StringComparison]::OrdinalIgnoreCase)) {
            $singleTarget = [string]$effectiveActionPlan.Target
            if ($singleTarget -in @('network', 'vm-deploy', 'vm-init', 'vm-update')) {
                Assert-ProdicloudSingleActionDependencies -ActionName $singleTarget -Context $step1Context
            }
        }

        $completedStages = New-Object System.Collections.ArrayList
        $skippedStages = New-Object System.Collections.ArrayList
        $cancelledStage = ''

        Invoke-Step 'Step 1/7 - Configuration review' {
            if ($script:AutoMode) {
                Show-ProdicloudRuntimeConfigurationSnapshot -Platform $platform -ScriptName 'prodicloud.ps1' -ScriptRoot $repoRoot -AutoMode:$script:AutoMode -UpdateMode:$script:UpdateMode -ConfigMap $effectiveConfigMap -ConfigOverrides $script:ConfigOverrides -Context $step1Context
            }
            else {
                Show-ProdicloudStepReview -Title 'Configuration review' -Values (New-ProdicloudStep1ConfigDisplayMap -Platform $platform -Context $step1Context -OperationName $CommandName) -TaskTitle '' -TaskBlocks @()
            }
            if ($shouldRunPrecheck) {
                Invoke-ProdicloudPrecheckStep -Context $step1Context
            }
            else {
                Write-Host "Precheck was skipped because the selected step window does not mutate Azure create/deploy inputs." -ForegroundColor Yellow
            }
        }
        [void]$completedStages.Add('configure')

        if ($runGroupAction) {
            $groupDecision = Invoke-ProdicloudReviewCheckpoint `
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
                    Invoke-ProdicloudPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    Invoke-Step 'Step 2/7 - Resource group' {
                        Invoke-ProdicloudResourceGroupStep -Context $step1Context -AutoMode:$script:AutoMode -UpdateMode:$script:UpdateMode -ExecutionMode $script:ExecutionMode
                    }
                    [void]$completedStages.Add('group')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cancelledStage)) {
            Write-ProdicloudWorkflowSummary -Context $step1Context -Platform $platform -PlatformDefaults $platformDefaults -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
            Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
            return
        }

        if ($runNetworkAction) {
            Invoke-ProdicloudPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
            Invoke-Step 'Step 3/7 - Network' {
                Invoke-ProdicloudNetworkStep -Context $step1Context -ExecutionMode $script:ExecutionMode
            }
            [void]$completedStages.Add('network')
        }

        if ($runDeployAction) {
            $deployDecision = Invoke-ProdicloudReviewCheckpoint `
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
                    Invoke-ProdicloudPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    Invoke-Step 'Step 4/7 - VM deploy' {
                        Invoke-ProdicloudVmCreateStep -Context $step1Context -AutoMode:$script:AutoMode -UpdateMode:$script:UpdateMode -ExecutionMode $script:ExecutionMode -CreateVmAction {
                            $vmCreateSecurityArgs = @(Get-ProdicloudCreateSecurityArgumentsForCurrentVmState -Context $step1Context -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName))
                            az vm create --resource-group ([string]$step1Context.ResourceGroup) --name ([string]$step1Context.VmName) --image ([string]$step1Context.VmImage) --size ([string]$step1Context.VmSize) --storage-sku ([string]$step1Context.VmStorageSku) --os-disk-name ([string]$step1Context.VmDiskName) --os-disk-size-gb ([string]$step1Context.VmDiskSize) --admin-username ([string]$step1Context.VmUser) --admin-password ([string]$step1Context.VmPass) --authentication-type password --nics ([string]$step1Context.NIC) @vmCreateSecurityArgs -o json --only-show-errors
                        } | Out-Null
                    }
                    [void]$completedStages.Add('vm-deploy')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cancelledStage)) {
            Write-ProdicloudWorkflowSummary -Context $step1Context -Platform $platform -PlatformDefaults $platformDefaults -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
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
            $initReview = Get-ProdicloudReviewTaskRows -DirectoryPath ([string]$step1Context.VmInitTaskDir) -Platform $platform -Stage 'init' -Context $step1Context
            $initTaskBlocks = @($initReview.ActiveTasks)
            $initDisabledTasks = @($initReview.DisabledTasks)

            $initDecision = Invoke-ProdicloudReviewCheckpoint `
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
                    Invoke-ProdicloudPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
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
                            $provisioningWaitResult = Wait-ProdicloudProvisioningReadyOrRepair -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName)
                            if (-not [bool]$provisioningWaitResult.Ready) {
                                Throw-FriendlyError `
                                    -Detail ("VM '{0}' is still not provisioning-ready before vm-init." -f [string]$step1Context.VmName) `
                                    -Code 62 `
                                    -Summary "VM init cannot start while Azure provisioning is still not ready." `
                                    -Hint "Wait for Azure provisioning to recover and rerun create, or inspect the VM in Azure Portal if the automatic redeploy repair did not resolve the issue."
                            }
                            $initVmRuntimeDetails = Get-ProdicloudVmDetails -Context $step1Context
                            $initSshHost = [string]$initVmRuntimeDetails.VmFqdn
                            if ([string]::IsNullOrWhiteSpace([string]$initSshHost)) {
                                $initSshHost = [string]$initVmRuntimeDetails.PublicIP
                            }
                            Invoke-VmRunCommandBlocks -ResourceGroup ([string]$step1Context.ResourceGroup) -VmName ([string]$step1Context.VmName) -CommandId ([string]$platformDefaults.RunCommandId) -TaskBlocks $initTaskBlocks -CombinedShell $combinedShell -TaskOutcomeMode $taskOutcomeMode -Platform $platform -RepoRoot (Get-ProdicloudRepoRoot) -ManagerUser ([string]$step1Context.VmUser) -AssistantUser ([string]$step1Context.VmAssistantUser) -SshHost $initSshHost -SshUser ([string]$step1Context.VmUser) -SshPassword ([string]$step1Context.VmPass) -SshPort ([string]$step1Context.SshPort) -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -ConfiguredPySshClientPath $configuredPySshClientPath | Out-Null
                            Write-ProdicloudActionProgress -Action 'wait 20 seconds for SSH service to settle after init'
                            Start-Sleep -Seconds 20
                        }
                    }
                    [void]$completedStages.Add('vm-init')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$cancelledStage)) {
            Write-ProdicloudWorkflowSummary -Context $step1Context -PlatformDefaults $platformDefaults -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
            Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
            return
        }

        if ($runUpdateAction) {
            $updateReview = Get-ProdicloudReviewTaskRows -DirectoryPath ([string]$step1Context.VmUpdateTaskDir) -Platform $platform -Stage 'update' -Context $step1Context
            $updateTaskBlocks = @($updateReview.ActiveTasks)
            $updateDisabledTasks = @($updateReview.DisabledTasks)

            $updateDecision = Invoke-ProdicloudReviewCheckpoint `
                -AutoMode:$script:AutoMode `
                -StageName 'vm-update step' `
                -Values ([ordered]@{
                    Platform = $platform
                    VmUpdateTaskDir = [string]$step1Context.VmUpdateTaskDir
                    ActiveTaskCount = @($updateTaskBlocks).Count
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
                    Invoke-ProdicloudPersistPendingSelections -Context $step1Context -EnvFilePath $envFilePath
                    $vmUpdateStageResult = Invoke-Step 'Step 6/7 - VM update' {
                        if ([string]::Equals([string]$CommandName,'update',[System.StringComparison]::OrdinalIgnoreCase)) {
                            Sync-ProdicloudVmPublicDnsLabel -Context $step1Context | Out-Null
                        }
                        if (@($updateDisabledTasks).Count -gt 0) {
                            $disabledNames = @($updateDisabledTasks | ForEach-Object { [string]$_.Name })
                            Write-Host ("Disabled update tasks (ignored): {0}" -f ($disabledNames -join ', ')) -ForegroundColor Yellow
                        }

                        if (@($updateTaskBlocks).Count -eq 0) {
                            Write-Host 'Update task folder inventory is empty; Step 6 vm-update stage is skipped.' -ForegroundColor Yellow
                            return $null
                        }
                        $vmRuntimeDetails = Get-ProdicloudVmDetails -Context $step1Context
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
                            $sshMaxRetries = Resolve-ProdicloudSshRetryCount -RetryText $sshMaxRetriesText -DefaultValue 3
                        }

                        $stageRuntime = [pscustomobject]@{
                            Context = $step1Context
                            Platform = [string]$platform
                            RepoRoot = [string]$repoRoot
                            EffectiveConfigMap = $effectiveConfigMap
                            SshTaskTimeoutSeconds = [int]$sshTaskTimeoutSeconds
                            SshConnectTimeoutSeconds = [int]$sshConnectTimeoutSeconds
                            ConfiguredPySshClientPath = [string]$configuredPySshClientPath
                        }
                        return (Invoke-ProdicloudTaskBlocksByDeclaredTransport -Runtime $stageRuntime -HostName $sshHost -TaskBlocks $updateTaskBlocks -TaskOutcomeMode $taskOutcomeMode -SshMaxRetries $sshMaxRetries)
                    }
                    [void]$completedStages.Add('vm-update')
                }
            }
        }

        [void]$completedStages.Add('vm-summary')
        Invoke-Step 'Step 7/7 - VM summary' {
            Write-ProdicloudWorkflowSummary -Context $step1Context -Platform $platform -PlatformDefaults $platformDefaults -RepoRoot $repoRoot -ConfiguredPySshClientPath $configuredPySshClientPath -SshConnectTimeoutSeconds $sshConnectTimeoutSeconds -CompletedStages @($completedStages) -SkippedStages @($skippedStages) -CancelledStage $cancelledStage
        }
        Write-Host ("All console output was saved to '{0}'." -f [System.IO.Path]::GetFileName($logPath))
    }
    catch {
        $resolvedError = Resolve-ProdicloudFriendlyError -ErrorRecord $_ -DefaultErrorSummary $script:DefaultErrorSummary -DefaultErrorHint $script:DefaultErrorHint

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
