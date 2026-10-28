# Shared VM run-command JSON helpers.

# Handles Get-ProdicloudRunCommandChannelMessage.
function Get-ProdicloudRunCommandChannelMessage {
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunCommandObject,
        [ValidateSet('StdOut','StdErr')]
        [string]$Channel = 'StdOut'
    )

    foreach ($entry in @(ConvertTo-ObjectArrayCompat -InputObject $RunCommandObject.value)) {
        $code = [string]$entry.code
        if ([string]::IsNullOrWhiteSpace([string]$code)) {
            continue
        }

        if ($code -like ("ComponentStatus/{0}/*" -f [string]$Channel)) {
            return [string]$entry.message
        }
    }

    return ''
}

# Handles Invoke-ProdicloudVmRunCommandJson.
function Invoke-ProdicloudVmRunCommandJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [Parameter(Mandatory = $true)]
        [string]$CommandId,
        [Parameter(Mandatory = $true)]
        [string[]]$Scripts,
        [string]$ContextLabel = 'az vm run-command invoke',
        [int]$MaxAttempts = 6,
        [int]$RetryDelaySeconds = 20
    )

    if ($MaxAttempts -lt 1) {
        $MaxAttempts = 1
    }
    if ($RetryDelaySeconds -lt 1) {
        $RetryDelaySeconds = 1
    }

    $lastError = ''
    $lastStdErr = ''
    $lastStdOut = ''
    $lastParsedResult = $null
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        Write-ProdicloudActionProgress -Action ("run {0} on VM '{1}' (attempt {2}/{3})" -f [string]$ContextLabel,[string]$VmName,$attempt,$MaxAttempts)
        $azArgs = @('vm', 'run-command', 'invoke', '-g', $ResourceGroup, '-n', $VmName, '--command-id', $CommandId, '--scripts')
        $azArgs += @($Scripts)
        $azArgs += @('-o', 'json', '--only-show-errors')

        try {
            $rawOutput = Invoke-ProdicloudWithSuppressedAzCliStderr -Action { az @azArgs }
            if ($LASTEXITCODE -ne 0) {
                $lastError = ("{0} returned exit code {1}." -f [string]$ContextLabel, [int]$LASTEXITCODE)
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$rawOutput)) {
                $lastError = ("{0} returned empty output." -f [string]$ContextLabel)
            }
            else {
                $parsedResult = ConvertFrom-JsonCompat -InputObject $rawOutput
                $lastParsedResult = $parsedResult
                $stdOutText = [string](Get-ProdicloudRunCommandChannelMessage -RunCommandObject $parsedResult -Channel 'StdOut')
                $stdErrText = [string](Get-ProdicloudRunCommandChannelMessage -RunCommandObject $parsedResult -Channel 'StdErr')
                $lastStdOut = [string]$stdOutText
                $lastStdErr = [string]$stdErrText
                if ([string]::IsNullOrWhiteSpace([string]$stdOutText)) {
                    $lastError = if ([string]::IsNullOrWhiteSpace([string]$stdErrText)) {
                        ("{0} returned empty StdOut." -f [string]$ContextLabel)
                    }
                    else {
                        ("{0} returned empty StdOut. StdErr: {1}" -f [string]$ContextLabel, [string]$stdErrText)
                    }
                }
                else {
                    try {
                        $jsonOutput = ConvertFrom-JsonCompat -InputObject $stdOutText
                        return [pscustomobject]@{
                            Success = $true
                            OutputObject = $jsonOutput
                            StdOut = [string]$stdOutText
                            StdErr = [string]$stdErrText
                            RawResult = $parsedResult
                            ErrorMessage = ''
                        }
                    }
                    catch {
                        $lastError = ("{0} returned non-JSON StdOut: {1}" -f [string]$ContextLabel, $_.Exception.Message)
                    }
                }
            }
        }
        catch {
            $lastError = [string]$_.Exception.Message
        }

        if ($attempt -lt $MaxAttempts) {
            Write-ProdicloudActionProgress -Action ("{0} is not ready; wait {1}s before attempt {2}/{3}" -f [string]$ContextLabel, $RetryDelaySeconds, ($attempt + 1), $MaxAttempts)
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }

    return [pscustomobject]@{
        Success = $false
        OutputObject = $null
        StdOut = [string]$lastStdOut
        StdErr = [string]$lastStdErr
        RawResult = $lastParsedResult
        ErrorMessage = [string]$lastError
    }
}

# Converts a guest probe field to a nullable Boolean without turning unknown values into false.
function ConvertTo-ProdicloudNullableBoolean {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return [bool]$Value }
    switch (([string]$Value).Trim().ToLowerInvariant()) {
        'true' { return $true }
        'false' { return $false }
        default { return $null }
    }
}

# Handles Get-ProdicloudNestedVirtualizationGuestValidation.
function Get-ProdicloudNestedVirtualizationGuestValidation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true)]
        [string]$VmName,
        [ValidateSet('windows','linux')]
        [string]$OsType = 'windows',
        [int]$MaxAttempts = 6,
        [int]$RetryDelaySeconds = 20,
        [switch]$SuppressError
    )

    $normalizedOsType = if ([string]::IsNullOrWhiteSpace([string]$OsType)) { 'windows' } else { [string]$OsType.Trim().ToLowerInvariant() }
    $commandId = 'RunPowerShellScript'
    $scripts = @(
        '$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,VMMonitorModeExtensions,VirtualizationFirmwareEnabled,SecondLevelAddressTranslationExtensions',
        '[pscustomobject]@{',
        '  ProcessorName = [string]$cpu.Name',
        '  VMMonitorModeExtensions = if ($null -ne $cpu) { $cpu.VMMonitorModeExtensions } else { $null }',
        '  VirtualizationFirmwareEnabled = if ($null -ne $cpu) { $cpu.VirtualizationFirmwareEnabled } else { $null }',
        '  SecondLevelAddressTranslationExtensions = if ($null -ne $cpu) { $cpu.SecondLevelAddressTranslationExtensions } else { $null }',
        '} | ConvertTo-Json -Compress'
    )
    $contextLabel = "nested virtualization guest validation"

    if ($normalizedOsType -eq 'linux') {
        $commandId = 'RunShellScript'
        $scripts = @(
            "if [ ! -r /proc/cpuinfo ]; then",
            '  printf ''{"VirtualizationExtensionsVisible":null}\n''',
            "elif grep -Eq '(vmx|svm)' /proc/cpuinfo; then",
            '  printf ''{"VirtualizationExtensionsVisible":true}\n''',
            "else",
            '  printf ''{"VirtualizationExtensionsVisible":false}\n''',
            "fi"
        )
    }
    else {
        $scripts = @(
            '$featureMap = @{}',
            'foreach ($featureName in @(''VirtualMachinePlatform'',''Microsoft-Hyper-V'',''Microsoft-Hyper-V-All'',''HypervisorPlatform'')) {',
            '  $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue',
            '  if ($null -ne $feature) {',
            '    $featureMap[$featureName] = [string]$feature.State',
            '  }',
            '  else {',
            '    $featureMap[$featureName] = ''''',
            '  }',
            '}',
            '$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1 Name,VMMonitorModeExtensions,VirtualizationFirmwareEnabled,SecondLevelAddressTranslationExtensions',
            '$hyperVisorInfo = Get-ComputerInfo -Property HyperVisorPresent',
            '$bcdText = [string](bcdedit /enum ''{current}'' | Out-String)',
            '[pscustomobject]@{',
            '  ProcessorName = [string]$cpu.Name',
            '  VMMonitorModeExtensions = if ($null -ne $cpu) { $cpu.VMMonitorModeExtensions } else { $null }',
            '  VirtualizationFirmwareEnabled = if ($null -ne $cpu) { $cpu.VirtualizationFirmwareEnabled } else { $null }',
            '  SecondLevelAddressTranslationExtensions = if ($null -ne $cpu) { $cpu.SecondLevelAddressTranslationExtensions } else { $null }',
            '  HyperVisorPresent = [bool]$hyperVisorInfo.HyperVisorPresent',
            '  VirtualMachinePlatformState = [string]$featureMap[''VirtualMachinePlatform'']',
            '  HypervisorPlatformState = [string]$featureMap[''HypervisorPlatform'']',
            '  MicrosoftHyperVState = [string]$featureMap[''Microsoft-Hyper-V'']',
            '  MicrosoftHyperVAllState = [string]$featureMap[''Microsoft-Hyper-V-All'']',
            '  BcdHypervisorLaunchType = $(if ($bcdText -match ''hypervisorlaunchtype\s+(\S+)'') { [string]$Matches[1] } else { '''' })',
            '} | ConvertTo-Json -Compress'
        )
    }

    $runResult = Invoke-ProdicloudVmRunCommandJson `
        -ResourceGroup $ResourceGroup `
        -VmName $VmName `
        -CommandId $commandId `
        -Scripts $scripts `
        -ContextLabel $contextLabel `
        -MaxAttempts $MaxAttempts `
        -RetryDelaySeconds $RetryDelaySeconds

    if (-not [bool]$runResult.Success) {
        $result = [pscustomobject]@{
            Known = $false
            AvailableToGuest = $null
            Evidence = @()
            Data = $null
            ErrorMessage = [string]$runResult.ErrorMessage
        }
        if ($SuppressError) {
            return $result
        }

        throw ("Nested virtualization guest validation failed for VM '{0}' in resource group '{1}': {2}" -f $VmName, $ResourceGroup, [string]$runResult.ErrorMessage)
    }

    $data = $runResult.OutputObject
    $evidence = @()
    $availableToGuest = $false

    if ($normalizedOsType -eq 'linux') {
        $visibleValue = if ($null -ne $data) { ConvertTo-ProdicloudNullableBoolean -Value $data.VirtualizationExtensionsVisible } else { $null }
        if ($null -eq $visibleValue) {
            return [pscustomobject]@{
                Known = $false
                AvailableToGuest = $null
                Evidence = @('VirtualizationExtensionsVisible=(missing or invalid)')
                Data = $data
                ErrorMessage = 'The Linux guest probe did not return a valid virtualization-extension value.'
            }
        }
        $availableToGuest = [bool]$visibleValue
        $evidence = @(
            ("VirtualizationExtensionsVisible={0}" -f [bool]$visibleValue)
        )
    }
    else {
        $vmMonitorModeExtensions = if ($null -ne $data) { ConvertTo-ProdicloudNullableBoolean -Value $data.VMMonitorModeExtensions } else { $null }
        $virtualizationFirmwareEnabled = if ($null -ne $data) { ConvertTo-ProdicloudNullableBoolean -Value $data.VirtualizationFirmwareEnabled } else { $null }
        $slatEnabled = if ($null -ne $data) { ConvertTo-ProdicloudNullableBoolean -Value $data.SecondLevelAddressTranslationExtensions } else { $null }
        $hyperVisorPresent = if ($null -ne $data) { ConvertTo-ProdicloudNullableBoolean -Value $data.HyperVisorPresent } else { $null }
        $virtualMachinePlatformState = if ($null -ne $data) { [string]$data.VirtualMachinePlatformState } else { '' }
        $hypervisorPlatformState = if ($null -ne $data) { [string]$data.HypervisorPlatformState } else { '' }
        $microsoftHyperVState = if ($null -ne $data) { [string]$data.MicrosoftHyperVState } else { '' }
        $microsoftHyperVAllState = if ($null -ne $data) { [string]$data.MicrosoftHyperVAllState } else { '' }
        $bcdHypervisorLaunchType = if ($null -ne $data) { [string]$data.BcdHypervisorLaunchType } else { '' }
        if ($null -eq $vmMonitorModeExtensions -or $null -eq $virtualizationFirmwareEnabled -or $null -eq $slatEnabled) {
            $incompleteEvidence = @(
                ("VMMonitorModeExtensions={0}" -f $(if ($null -eq $vmMonitorModeExtensions) { '(missing or invalid)' } else { [string]$vmMonitorModeExtensions })),
                ("VirtualizationFirmwareEnabled={0}" -f $(if ($null -eq $virtualizationFirmwareEnabled) { '(missing or invalid)' } else { [string]$virtualizationFirmwareEnabled })),
                ("SecondLevelAddressTranslationExtensions={0}" -f $(if ($null -eq $slatEnabled) { '(missing or invalid)' } else { [string]$slatEnabled }))
            )
            return [pscustomobject]@{
                Known = $false
                AvailableToGuest = $null
                Evidence = @($incompleteEvidence)
                Data = $data
                ErrorMessage = 'The Windows guest probe did not return all required CPU virtualization flags.'
            }
        }
        $cpuFlagsAvailable = ([bool]$vmMonitorModeExtensions -and [bool]$virtualizationFirmwareEnabled -and [bool]$slatEnabled)
        # HyperVisorPresent can describe Azure's outer hypervisor, and Windows
        # optional features can be enabled without exposed VMX/SLAT extensions.
        # Neither condition proves that this VM can run a nested hypervisor.
        $availableToGuest = $cpuFlagsAvailable
        if (-not [string]::IsNullOrWhiteSpace([string]$data.ProcessorName)) {
            $evidence += ("ProcessorName={0}" -f [string]$data.ProcessorName)
        }
        $evidence += @(
            ("VMMonitorModeExtensions={0}" -f [bool]$vmMonitorModeExtensions),
            ("VirtualizationFirmwareEnabled={0}" -f [bool]$virtualizationFirmwareEnabled),
            ("SecondLevelAddressTranslationExtensions={0}" -f [bool]$slatEnabled),
            ("CpuVirtualizationExtensionsExposed={0}" -f [bool]$cpuFlagsAvailable),
            ("HyperVisorPresent={0}" -f [bool]$hyperVisorPresent),
            ("VirtualMachinePlatformState={0}" -f $virtualMachinePlatformState),
            ("HypervisorPlatformState={0}" -f $hypervisorPlatformState),
            ("MicrosoftHyperVState={0}" -f $microsoftHyperVState),
            ("MicrosoftHyperVAllState={0}" -f $microsoftHyperVAllState)
        )
        if (-not [string]::IsNullOrWhiteSpace([string]$bcdHypervisorLaunchType)) {
            $evidence += ("BcdHypervisorLaunchType={0}" -f $bcdHypervisorLaunchType)
        }
    }

    return [pscustomobject]@{
        Known = $true
        AvailableToGuest = [bool]$availableToGuest
        Evidence = @($evidence)
        Data = $data
        ErrorMessage = ''
    }
}
