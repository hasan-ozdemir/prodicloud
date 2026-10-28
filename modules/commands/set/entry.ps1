# Set command entry.

# Handles Invoke-ProdicloudSetCommand.
function Invoke-ProdicloudSetCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Join-Path $repoRoot 'prodicloud.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $target = Resolve-ProdicloudManagedVmTarget -Options $Options -ConfigMap $configMap -OperationName 'set'
    $resourceGroup = [string]$target.ResourceGroup
    $vmName = [string]$target.VmName

    $hasHibernation = Test-ProdicloudCliOptionPresent -Options $Options -Name 'hibernation'
    $hasNested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'nested-virtualization'
    $hibernationTarget = ''
    $nestedTarget = ''

    if ($hasHibernation) {
        $hibernationTarget = Resolve-ProdicloudToggleValue -Name 'hibernation' -RawValue ([string](Get-ProdicloudCliOptionText -Options $Options -Name 'hibernation'))
    }
    if ($hasNested) {
        $nestedTarget = Resolve-ProdicloudToggleValue -Name 'nested-virtualization' -RawValue ([string](Get-ProdicloudCliOptionText -Options $Options -Name 'nested-virtualization'))
    }

    if ($AutoMode -and -not $hasHibernation -and -not $hasNested) {
        Throw-FriendlyError `
            -Detail "Auto mode requires at least one set target (--hibernation or --nested-virtualization)." `
            -Code 62 `
            -Summary "Set command has no update target in auto mode." `
            -Hint "Provide --hibernation=on|off and/or --nested-virtualization=on|off."
    }

    if (-not $hasHibernation -and -not $hasNested) {
        Write-Host "Set command interactive mode: select feature values." -ForegroundColor Cyan
        $hibernationTarget = Read-ProdicloudToggleInteractive -PromptText "Set hibernation"
        $nestedTarget = Read-ProdicloudToggleInteractive -PromptText "Set nested virtualization"
        $hasHibernation = $true
        $hasNested = $true
    }
    elseif ($hasHibernation -and [string]::IsNullOrWhiteSpace([string]$hibernationTarget)) {
        if ($AutoMode) {
            Throw-FriendlyError `
                -Detail "Option '--hibernation' was provided without a value in auto mode." `
                -Code 62 `
                -Summary "Set command cannot continue in auto mode." `
                -Hint "Use --hibernation=on|off."
        }
        $hibernationTarget = Read-ProdicloudToggleInteractive -PromptText "Set hibernation"
    }
    elseif ($hasNested -and [string]::IsNullOrWhiteSpace([string]$nestedTarget)) {
        if ($AutoMode) {
            Throw-FriendlyError `
                -Detail "Option '--nested-virtualization' was provided without a value in auto mode." `
                -Code 62 `
                -Summary "Set command cannot continue in auto mode." `
                -Hint "Use --nested-virtualization=on|off."
        }
        $nestedTarget = Read-ProdicloudToggleInteractive -PromptText "Set nested virtualization"
    }

    if (-not $hasHibernation -and -not $hasNested) {
        Write-Host "No set operation was requested." -ForegroundColor Yellow
        return
    }

    $configBefore = @{}
    foreach ($key in @($configMap.Keys)) {
        $configBefore[[string]$key] = [string]$configMap[$key]
    }

    $persistMap = [ordered]@{}
    $envChanges = @()
    try {
        if ($hasHibernation) {
            $hibernationBool = if ([string]::Equals($hibernationTarget, 'on', [System.StringComparison]::OrdinalIgnoreCase)) { 'true' } else { 'false' }
            if ($hibernationBool -eq 'true') {
                Write-Host 'Hibernation will be enabled.' -ForegroundColor DarkCyan
            }
            else {
                Write-Host 'Hibernation will be disabled.' -ForegroundColor DarkCyan
            }
            Write-Host 'Applying hibernation setting...' -ForegroundColor Cyan
            Invoke-TrackedAction -Label ("az vm update -g {0} -n {1} --enable-hibernation {2}" -f $resourceGroup, $vmName, $hibernationBool) -Action {
                az vm update -g $resourceGroup -n $vmName --enable-hibernation $hibernationBool -o none --only-show-errors
                Assert-LastExitCode "az vm update --enable-hibernation"
            } | Out-Null
            $persistMap['VM_ENABLE_HIBERNATION'] = $hibernationBool
            if ($hibernationBool -eq 'true') {
                Write-Host 'Hibernation was enabled successfully.' -ForegroundColor Green
            }
            else {
                Write-Host 'Hibernation was disabled successfully.' -ForegroundColor Green
            }
        }

        if ($hasNested) {
            $nestedBool = if ([string]::Equals($nestedTarget, 'on', [System.StringComparison]::OrdinalIgnoreCase)) { 'true' } else { 'false' }
            if ($nestedBool -eq 'true') {
                Write-Host 'Nested virtualization is requested for this VM.' -ForegroundColor DarkCyan
                $lifecycleSnapshot = Get-ProdicloudVmLifecycleSnapshot -ResourceGroup $resourceGroup -VmName $vmName
                if ([string]$lifecycleSnapshot.NormalizedState -ne 'started') {
                    Throw-FriendlyError `
                        -Detail ("Nested virtualization validation requires the target VM '{0}' in resource group '{1}' to be running. Current state: {2}" -f $vmName, $resourceGroup, (Format-ProdicloudVmLifecycleSummaryText -Snapshot $lifecycleSnapshot)) `
                        -Code 62 `
                        -Summary "Nested virtualization validation requires a running VM." `
                        -Hint "Start the VM first, then rerun set --nested-virtualization=on."
                }

                $vmOsTypeNormalized = if ($LinuxFlag) {
                    'linux'
                }
                elseif ($WindowsFlag) {
                    'windows'
                }
                else {
                    $vmOsType = az vm show -g $resourceGroup -n $vmName --query "storageProfile.osDisk.osType" -o tsv --only-show-errors 2>$null
                    if ([string]$vmOsType -match '(?i)linux') { 'linux' } else { 'windows' }
                }
                $nestedValidation = Get-ProdicloudNestedVirtualizationGuestValidation -ResourceGroup $resourceGroup -VmName $vmName -OsType $vmOsTypeNormalized
                if (-not [bool]$nestedValidation.AvailableToGuest) {
                    $nestedEvidenceText = if (@($nestedValidation.Evidence).Count -gt 0) { (@($nestedValidation.Evidence) -join '; ') } else { [string]$nestedValidation.ErrorMessage }
                    Throw-FriendlyError `
                        -Detail ("Nested virtualization guest validation failed for VM '{0}'. {1}" -f $vmName, [string]$nestedEvidenceText) `
                        -Code 62 `
                        -Summary "Nested virtualization is unavailable to the guest." `
                        -Hint "Check VM SKU, security type, and guest virtualization readiness, then retry."
                }

                Write-Host 'Guest virtualization extensions are available for nested virtualization.' -ForegroundColor Green
                if (@($nestedValidation.Evidence).Count -gt 0) {
                    Write-Host ("Nested virtualization validation details: {0}" -f ((@($nestedValidation.Evidence) -join '; '))) -ForegroundColor DarkCyan
                }
            }
            else {
                Write-Host 'Azure VM hardware exposure will not be changed; the Prodicloud nested-virtualization request will be saved as false.' -ForegroundColor DarkCyan
            }
            $persistMap['VM_ENABLE_NESTED_VIRTUALIZATION'] = $nestedBool
        }
    }
    finally {
        if ($persistMap.Count -gt 0) {
            $persistMap['SELECTED_RESOURCE_GROUP'] = $resourceGroup
            $persistMap['SELECTED_VM_NAME'] = $vmName
            $envChanges = @(Save-ProdicloudConfigToDotEnv -EnvFilePath $envFilePath -ConfigBefore $configBefore -PersistMap $persistMap)
        }
    }

    if (@($envChanges).Count -gt 0) {
        Write-Host ("Saved VC settings to {0}.env after set:" -f $vmName) -ForegroundColor Green
        foreach ($change in @($envChanges)) {
            Write-Host ("- {0} = {1}" -f [string]$change.Key, (ConvertTo-ProdicloudDisplayValue -Value $change.NewValue))
        }
    }

    Write-Host ("Set command completed for VM '{0}' in resource group '{1}'." -f $vmName, $resourceGroup) -ForegroundColor Green
}
