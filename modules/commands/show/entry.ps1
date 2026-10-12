# Show command entry.

# Handles Invoke-ClagnosShowCommand.
function Invoke-ClagnosShowCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $accountSnapshot = Get-ClagnosAzAccountSnapshot

    $targetGroupValue = [string](Get-ClagnosCliOptionText -Options $Options -Name 'group')
    $targetGroup = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$targetGroupValue)) {
        $targetGroup = $targetGroupValue.Trim()
    }
    $targetVmName = [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name')
    if ([string]::IsNullOrWhiteSpace([string]$targetVmName)) {
        $targetVmName = ''
    }
    else {
        $targetVmName = $targetVmName.Trim()
    }

    $allGroupRows = @()
    try {
        $allGroupRows = @(Get-ClagnosManagedResourceGroupRows)
    }
    catch {
        Throw-FriendlyError `
            -Detail "Managed resource groups could not be loaded for show command." `
            -Code 64 `
            -Summary "Show command cannot continue." `
            -Hint "Run az login and verify subscription access."
    }
    $allGroups = @(
        ConvertTo-ObjectArrayCompat -InputObject $allGroupRows |
            ForEach-Object { [string]$_.name } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            Sort-Object -Unique
    )

    $selectedGroups = @()
    if (-not [string]::IsNullOrWhiteSpace([string]$targetGroup)) {
        Assert-ClagnosManagedResourceGroup -ResourceGroup $targetGroup -OperationName 'show'
        $selectedGroups = @($targetGroup)
    }
    else {
        $selectedGroups = @($allGroups)
    }

    if (@($selectedGroups).Count -eq 0) {
        Throw-FriendlyError `
            -Detail "No resource groups were found for show command." `
            -Code 64 `
            -Summary "Show command cannot continue because no resource groups were found." `
            -Hint "Run az login, verify subscription, and create resources first."
    }

    $platformRequest = ''
    if ($WindowsFlag) {
        $platformRequest = 'windows'
    }
    elseif ($LinuxFlag) {
        $platformRequest = 'linux'
    }

    $groupDumps = @()
    foreach ($resourceGroup in @($selectedGroups)) {
        $groupDumps += (Get-ClagnosResourceGroupInventoryDump -ResourceGroup ([string]$resourceGroup))
    }

    $focusedTarget = Resolve-ClagnosShowFocusedTarget -Options $Options -ConfigMap $configMap -SelectedGroupDumps $groupDumps
    $targetDerivedConfiguration = $null
    if ($null -ne $focusedTarget) {
        $targetDerivedConfiguration = Get-ClagnosShowTargetDerivedConfiguration -ResourceGroup ([string]$focusedTarget.ResourceGroup) -VmName ([string]$focusedTarget.VmName) -ConfigMap $configMap
    }

    $totalVmCount = 0
    $runningVmCount = 0
    foreach ($groupDump in @($groupDumps)) {
        $groupVmCount = @($groupDump.Vms).Count
        $totalVmCount += [int]$groupVmCount
        foreach ($vmDump in @($groupDump.Vms)) {
            $powerStateText = [string]$vmDump.PowerState
            if (-not [string]::IsNullOrWhiteSpace([string]$powerStateText) -and $powerStateText.ToLowerInvariant().Contains("running")) {
                $runningVmCount += 1
            }
        }
    }

    $configOrdered = [ordered]@{}
    foreach ($key in @($configMap.Keys | Sort-Object)) {
        $configOrdered[[string]$key] = [string]$configMap[$key]
    }

    $overridesOrdered = [ordered]@{}
    foreach ($key in @($script:ConfigOverrides.Keys | Sort-Object)) {
        $overridesOrdered[[string]$key] = [string]$script:ConfigOverrides[$key]
    }

    $dump = [ordered]@{
        GeneratedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        Command = "show"
        Mode = "auto"
        RequestedPlatform = [string]$platformRequest
        EnvFilePath = [string]$envFilePath
        AzureAccount = $accountSnapshot
        Config = [ordered]@{
            DotEnvValues = $configOrdered
            RuntimeOverrides = $overridesOrdered
        }
        Selection = [ordered]@{
            TargetGroup = [string]$targetGroup
            TargetVmName = [string]$targetVmName
            IncludedResourceGroups = @($selectedGroups)
        }
        Summary = [ordered]@{
            ResourceGroupCount = @($groupDumps).Count
            TotalVmCount = [int]$totalVmCount
            RunningVmCount = [int]$runningVmCount
        }
        TargetDerivedConfiguration = $targetDerivedConfiguration
        ResourceGroups = @($groupDumps)
    }

    Write-ClagnosShowReport -Dump $dump
}
