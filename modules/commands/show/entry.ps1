# Show command entry.

# Handles Invoke-ProdicloudShowCommand.
function Invoke-ProdicloudShowCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $exportRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'export-json'
    $overwriteRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'overwrite'
    if ($overwriteRequested -and -not $exportRequested) {
        Throw-FriendlyError `
            -Detail "Option '--overwrite' requires '--export-json'." `
            -Code 64 `
            -Summary "Show export options are incomplete." `
            -Hint "Use --export-json <path> with --overwrite only when replacing an existing report file."
    }
    $exportPath = ''
    if ($exportRequested) {
        $rawExportPath = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'export-json')
        if ([string]::IsNullOrWhiteSpace([string]$rawExportPath)) {
            Throw-FriendlyError `
                -Detail "Option '--export-json' requires an output file path." `
                -Code 64 `
                -Summary "Show JSON export path is missing." `
                -Hint "Use --export-json <path> to select a report file."
        }
        $exportPath = [System.IO.Path]::GetFullPath([string]$rawExportPath)
        $exportParent = [System.IO.Path]::GetDirectoryName($exportPath)
        if (-not (Test-Path -LiteralPath $exportParent -PathType Container)) {
            Throw-FriendlyError `
                -Detail ("JSON export directory does not exist: {0}" -f $exportParent) `
                -Code 64 `
                -Summary "Show JSON export directory was not found." `
                -Hint "Create the directory first or select an existing output directory."
        }
        if ((Test-Path -LiteralPath $exportPath) -and -not $overwriteRequested) {
            Throw-FriendlyError `
                -Detail ("JSON export file already exists: {0}" -f $exportPath) `
                -Code 64 `
                -Summary "Show JSON export would overwrite an existing file." `
                -Hint "Choose another filename or add --overwrite after reviewing the target path."
        }
    }

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Join-Path $repoRoot 'prodicloud.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $accountSnapshot = Get-ProdicloudAzAccountSnapshot

    $targetGroupValue = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'group')
    $targetGroup = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$targetGroupValue)) {
        $targetGroup = $targetGroupValue.Trim()
    }
    $targetVmName = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-name')
    if ([string]::IsNullOrWhiteSpace([string]$targetVmName)) {
        $targetVmName = ''
    }
    else {
        $targetVmName = $targetVmName.Trim()
    }

    $allGroupRows = @()
    try {
        $allGroupRows = @(Get-ProdicloudManagedResourceGroupRows)
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
        Assert-ProdicloudManagedResourceGroup -ResourceGroup $targetGroup -OperationName 'show'
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
        $groupDumps += (Get-ProdicloudResourceGroupInventoryDump -ResourceGroup ([string]$resourceGroup))
    }

    $focusedTarget = Resolve-ProdicloudShowFocusedTarget -Options $Options -ConfigMap $configMap -SelectedGroupDumps $groupDumps
    $targetDerivedConfiguration = $null
    if ($null -ne $focusedTarget) {
        $targetDerivedConfiguration = Get-ProdicloudShowTargetDerivedConfiguration -ResourceGroup ([string]$focusedTarget.ResourceGroup) -VmName ([string]$focusedTarget.VmName) -ConfigMap $configMap
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

    if ($exportRequested) {
        Export-ProdicloudShowReportJson -Dump $dump -OutputPath $exportPath -Overwrite:$overwriteRequested | Out-Null
    }
    Write-ProdicloudShowReport -Dump $dump
}
