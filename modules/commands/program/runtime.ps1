# Program catalog, status, and managed guest install/uninstall operations.

function Get-ClagnosProgramCatalog {
    param([ValidateSet('windows','linux')][string]$Platform)

    $stageRoot = Join-Path (Get-ClagnosRepoRoot) (Join-Path $Platform 'update')
    if (-not (Test-Path -LiteralPath $stageRoot)) { return @() }
    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $stageRoot -Platform $Platform -Stage 'update' -SuppressSkipMessages
    $programs = @(
        $catalog.ActiveTasks |
            Where-Object { $null -ne $_.ProgramSpec } |
            ForEach-Object {
                [pscustomobject]@{
                    Id = [string]$_.ProgramSpec.Id
                    DisplayName = [string]$_.ProgramSpec.DisplayName
                    Category = [string]$_.ProgramSpec.Category
                    StatusCheck = $_.ProgramSpec.StatusCheck
                    Uninstall = $_.ProgramSpec.Uninstall
                    TaskName = [string]$_.Name
                    TaskNumber = [int]$_.TaskNumber
                    Task = $_
                    Platform = [string]$Platform
                }
            }
    )
    $duplicates = @($programs | Group-Object { [string]$_.Id } | Where-Object { $_.Count -gt 1 })
    if ($duplicates.Count -gt 0) {
        throw ("Program ids must be unique in the active task catalog: {0}" -f (($duplicates | ForEach-Object { [string]$_.Name }) -join ', '))
    }
    return @($programs | Sort-Object { [int]$_.TaskNumber }, { [string]$_.DisplayName })
}

function Get-ClagnosProgramStatusCacheKey {
    param([hashtable]$Options, [string]$Platform)
    return ('{0}|{1}|{2}|{3}' -f [string](Get-ClagnosCliOptionText -Options $Options -Name 'subscription-id'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'group'), [string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-name'), [string]$Platform).ToLowerInvariant()
}

function New-ClagnosProgramGuestScript {
    param(
        [string]$Action,
        [object[]]$Programs,
        [ValidateSet('windows','linux')][string]$Platform
    )

    $payload = @(
        $Programs | ForEach-Object {
            [ordered]@{
                id = [string]$_.Id
                displayName = [string]$_.DisplayName
                statusCheck = $_.StatusCheck
                uninstall = $_.Uninstall
            }
        }
    )
    $json = ConvertTo-Json -InputObject $payload -Depth 20 -Compress
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$json))
    if ([string]::Equals([string]$Platform,'linux',[System.StringComparison]::OrdinalIgnoreCase)) {
        if ([string]::Equals([string]$Action,'status',[System.StringComparison]::OrdinalIgnoreCase)) {
            $records = @($Programs | ForEach-Object { '{0}|{1}|{2}' -f [string]$_.Id,[string]$_.StatusCheck.kind,[string]$_.StatusCheck.value }) -join "`n"
            $recordBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$records))
            $bash = @'
records=$(printf '%s' '__RECORDS__' | base64 -d)
json='['
separator=''
while IFS='|' read -r id kind value; do
    [ -z "$id" ] && continue
    status='unknown'
    case "$kind" in
        command) if command -v "$value" >/dev/null 2>&1; then status='installed'; else status='not-installed'; fi ;;
        dpkg) if dpkg-query -W -f='${Status}' -- "$value" 2>/dev/null | grep -q 'install ok installed'; then status='installed'; else status='not-installed'; fi ;;
        rpm) if rpm -q -- "$value" >/dev/null 2>&1; then status='installed'; else status='not-installed'; fi ;;
    esac
    json="${json}${separator}{\"id\":\"${id}\",\"status\":\"${status}\"}"
    separator=','
done <<EOF
$records
EOF
json="${json}]"
printf 'CLAGNOS_PROGRAM_RESULTS:%s\n' "$json"
'@
            return $bash.Replace('__RECORDS__',$recordBase64)
        }
        $program = @($Programs)[0]
        $uninstall = $program.Uninstall
        $value = [string]$uninstall.value
        $quoteBreak = "'" + '"' + "'" + '"' + "'"
        $quoted = "'" + $value.Replace("'",$quoteBreak) + "'"
        $bashAction = switch ([string]$uninstall.kind) {
            'apt' { "sudo -n apt-get remove --purge -y $quoted" }
            'dnf' { "sudo -n dnf remove -y $quoted" }
            'snap' { "sudo -n snap remove $quoted" }
            default { throw ("Unsupported Linux uninstall kind '{0}'." -f [string]$uninstall.kind) }
        }
        return ("set -e`n{0}`nprintf 'CLAGNOS_PROGRAM_REMOVED:{1}\\n' '{1}'" -f $bashAction,[string]$program.Id)
    }
    if ([string]::Equals([string]$Action, 'status', [System.StringComparison]::OrdinalIgnoreCase)) {
        return @"
`$payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64'))
`$programs = @(ConvertFrom-Json -InputObject `$payload)
function Get-ProgramStatus {
    param([object]`$Program)
    `$check = `$Program.statusCheck
    if (`$null -eq `$check -or [string]::IsNullOrWhiteSpace([string]`$check.kind) -or [string]::IsNullOrWhiteSpace([string]`$check.value)) { return 'unknown' }
    `$value = [string]`$check.value
    switch ([string]`$check.kind) {
        'command' { if (Get-Command `$value -ErrorAction SilentlyContinue) { return 'installed' }; return 'not-installed' }
        'winget' {
            `$exe = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not `$exe) { return 'not-installed' }
            `$output = & `$exe.Source list --id `$value --exact --accept-source-agreements --disable-interactivity 2>`$null | Out-String
            if (`$LASTEXITCODE -eq 0 -and `$output -match [regex]::Escape(`$value)) { return 'installed' }
            return 'not-installed'
        }
        'choco' {
            `$exe = Get-Command choco.exe -ErrorAction SilentlyContinue
            if (-not `$exe) { return 'not-installed' }
            `$output = & `$exe.Source list --local-only --exact --limit-output `$value 2>`$null | Out-String
            if (`$LASTEXITCODE -eq 0 -and `$output -match ('(?im)^' + [regex]::Escape(`$value) + '\|')) { return 'installed' }
            return 'not-installed'
        }
        'npm' {
            `$exe = Get-Command npm.cmd -ErrorAction SilentlyContinue
            if (-not `$exe) { return 'not-installed' }
            `$output = & `$exe.Source list -g --depth=0 `$value 2>`$null | Out-String
            if (`$LASTEXITCODE -eq 0 -and `$output.Contains(`$value)) { return 'installed' }
            return 'not-installed'
        }
        'appx' {
            `$matches = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like ('*' + `$value + '*') -or `$_.PackageFamilyName -like ('*' + `$value + '*') -or `$_.PackageFullName -like ('*' + `$value + '*') })
            if (`$matches.Count -gt 0) { return 'installed' }
            return 'not-installed'
        }
        'store-state' {
            `$safeName = [regex]::Replace(`$value, '[^A-Za-z0-9._-]', '_')
            `$path = Join-Path 'C:\ProgramData\clagnos\state\store-installs' (`$safeName + '.json')
            if (-not (Test-Path -LiteralPath `$path)) { return 'unknown' }
            try { `$state = Get-Content -LiteralPath `$path -Raw | ConvertFrom-Json; if ([string]`$state.State -eq 'installed') { return 'installed' }; return 'not-installed' } catch { return 'unknown' }
        }
        'choco-self' { if (Test-Path -LiteralPath 'C:\ProgramData\chocolatey') { return 'installed' }; return 'not-installed' }
        default { return 'unknown' }
    }
}
`$results = @()
foreach (`$program in `$programs) {
    `$results += [pscustomobject]@{ id = [string]`$program.id; status = (Get-ProgramStatus -Program `$program) }
}
`$jsonResult = ConvertTo-Json -InputObject `$results -Depth 4 -Compress
Write-Output ('CLAGNOS_PROGRAM_RESULTS:' + `$jsonResult)
"@
    }

    return @"
`$payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64'))
`$programs = @(ConvertFrom-Json -InputObject `$payload)
`$results = @()
foreach (`$program in `$programs) {
    `$check = `$program.statusCheck
    `$status = 'unknown'
    if (`$null -ne `$check) {
        switch ([string]`$check.kind) {
            'command' { if (Get-Command ([string]`$check.value) -ErrorAction SilentlyContinue) { `$status = 'installed' } else { `$status = 'not-installed' } }
            'dpkg' { if (Get-Command dpkg-query -ErrorAction SilentlyContinue) { dpkg-query -W -f='`${Status}' -- ([string]`$check.value) 2>/dev/null | grep -q 'install ok installed'; if (`$LASTEXITCODE -eq 0) { `$status = 'installed' } else { `$status = 'not-installed' } } }
            'rpm' { if (Get-Command rpm -ErrorAction SilentlyContinue) { rpm -q -- ([string]`$check.value) >/dev/null 2>&1; if (`$LASTEXITCODE -eq 0) { `$status = 'installed' } else { `$status = 'not-installed' } } }
        }
    }
    `$results += [pscustomobject]@{ id = [string]`$program.id; status = `$status }
}
`$jsonResult = ConvertTo-Json -InputObject `$results -Depth 4 -Compress
Write-Output ('CLAGNOS_PROGRAM_RESULTS:' + `$jsonResult)
"@
}

function New-ClagnosProgramUninstallScript {
    param([object]$Program, [ValidateSet('windows','linux')][string]$Platform = 'windows')

    $actionProgram = [pscustomobject]@{
        Id = [string]$Program.Id
        DisplayName = [string]$Program.DisplayName
        StatusCheck = $Program.StatusCheck
        Uninstall = $Program.Uninstall
    }
    $json = ConvertTo-Json -InputObject @($actionProgram) -Depth 20 -Compress
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes([string]$json))
    if ($Platform -eq 'linux') {
        $uninstall = $Program.Uninstall
        $value = [string]$uninstall.value
        $quoteBreak = "'" + '"' + "'" + '"' + "'"
        $quoted = "'" + $value.Replace("'",$quoteBreak) + "'"
        $bashAction = switch ([string]$uninstall.kind) {
            'apt' { "sudo -n apt-get remove --purge -y $quoted" }
            'dnf' { "sudo -n dnf remove -y $quoted" }
            'snap' { "sudo -n snap remove $quoted" }
            default { throw ("Unsupported Linux uninstall kind '{0}'." -f [string]$uninstall.kind) }
        }
        return ("set -e`n{0}`nprintf 'CLAGNOS_PROGRAM_REMOVED:{1}\\n' '{1}'" -f $bashAction,[string]$program.Id)
    }
    return @"
`$payload = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$base64'))
`$program = @(ConvertFrom-Json -InputObject `$payload)[0]
`$uninstall = `$program.uninstall
if (`$null -eq `$uninstall -or [string]::IsNullOrWhiteSpace([string]`$uninstall.kind) -or [string]::IsNullOrWhiteSpace([string]`$uninstall.value)) { throw 'This catalog entry has no safe uninstall action.' }
`$value = [string]`$uninstall.value
switch ([string]`$uninstall.kind) {
    'winget' { `$exe = Get-Command winget.exe -ErrorAction SilentlyContinue; if (-not `$exe) { throw 'Windows Package Manager is not available.' }; & `$exe.Source uninstall --id `$value --exact --silent --accept-source-agreements --disable-interactivity; if (`$LASTEXITCODE -ne 0) { throw ('winget uninstall failed with exit code ' + `$LASTEXITCODE) } }
    'choco' { `$exe = Get-Command choco.exe -ErrorAction SilentlyContinue; if (-not `$exe) { throw 'Chocolatey is not available.' }; & `$exe.Source uninstall `$value -y --no-progress; if (`$LASTEXITCODE -ne 0) { throw ('Chocolatey uninstall failed with exit code ' + `$LASTEXITCODE) } }
    'npm' { `$exe = Get-Command npm.cmd -ErrorAction SilentlyContinue; if (-not `$exe) { throw 'npm is not available.' }; & `$exe.Source uninstall -g `$value; if (`$LASTEXITCODE -ne 0) { throw ('npm uninstall failed with exit code ' + `$LASTEXITCODE) } }
    'appx' { `$packages = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { `$_.Name -like ('*' + `$value + '*') -or `$_.PackageFamilyName -like ('*' + `$value + '*') -or `$_.PackageFullName -like ('*' + `$value + '*') }); foreach (`$package in `$packages) { Remove-AppxPackage -Package `$package.PackageFullName -AllUsers -ErrorAction Stop } }
    'windows-feature' { Disable-WindowsOptionalFeature -Online -FeatureName `$value -NoRestart -ErrorAction Stop | Out-Null }
    'choco-self' { if (Test-Path -LiteralPath `$value) { Remove-Item -LiteralPath `$value -Recurse -Force }; Write-Output 'Chocolatey files removed.' }
    default { throw ('Unsupported safe uninstall type: ' + [string]`$uninstall.kind) }
}
if ([string]`$program.statusCheck.kind -eq 'store-state') {
    `$safeName = [regex]::Replace([string]`$program.statusCheck.value, '[^A-Za-z0-9._-]', '_')
    `$statePath = Join-Path 'C:\ProgramData\clagnos\state\store-installs' (`$safeName + '.json')
    if (Test-Path -LiteralPath `$statePath) { Remove-Item -LiteralPath `$statePath -Force }
}
Write-Output ('CLAGNOS_PROGRAM_REMOVED:' + [string]`$program.id)
"@
}

function Invoke-ClagnosProgramGuestScript {
    param(
        [hashtable]$Options,
        [string]$Platform,
        [string]$ScriptText,
        [string]$TaskLabel
    )

    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$false -WindowsFlag:([string]$Platform -eq 'windows') -LinuxFlag:([string]$Platform -eq 'linux')
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'program'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $vmDetails = Get-ClagnosVmDetails -Context $runtime.Context
    $sshHost = [string]$vmDetails.VmFqdn
    if ([string]::IsNullOrWhiteSpace($sshHost)) { $sshHost = [string]$vmDetails.PublicIP }
    if ([string]::IsNullOrWhiteSpace($sshHost)) { throw 'Program management could not resolve the VM SSH host.' }
    $pySsh = Ensure-ClagnosPySshTools -RepoRoot (Get-ClagnosRepoRoot) -ConfiguredPySshClientPath ([string]$runtime.ConfiguredPySshClientPath)
    $block = [pscustomobject]@{
        Name = [string]$TaskLabel
        Script = [string]$ScriptText
        RelativePath = ('programs/{0}' -f [string]$TaskLabel)
        DirectoryPath = (Get-ClagnosRepoRoot)
        TaskRootPath = (Get-ClagnosRepoRoot)
        StageRootDirectoryPath = (Get-ClagnosRepoRoot)
        TimeoutSeconds = 300
        Priority = 1
        TaskType = 'normal'
        Source = 'managed-program-catalog'
        TaskNumber = 1
        AssetCopies = @()
        AppStateSpec = $null
        ProgramSpec = $null
        Extensions = $null
        DependsOn = @()
    }
    $resolvedBlock = Apply-ClagnosTaskBlockReplacements -TaskBlocks @($block) -Replacements (Get-ClagnosTaskTokenReplacements -Context $runtime.Context) -Context $runtime.Context
    return (Invoke-ClagnosSshTaskBlocks `
        -Platform $Platform `
        -RepoRoot (Get-ClagnosRepoRoot) `
        -SshHost $sshHost `
        -SshUser ([string]$runtime.Context.VmUser) `
        -SshPassword ([string]$runtime.Context.VmPass) `
        -SshPort ([string]$runtime.Context.SshPort) `
        -AssistantUser ([string]$runtime.Context.VmAssistantUser) `
        -ResourceGroup ([string]$target.ResourceGroup) `
        -VmName ([string]$target.VmName) `
        -TaskBlocks @($resolvedBlock) `
        -TaskOutcomeMode 'strict' `
        -PerfTaskCategory 'task-run' `
        -SshMaxRetries 1 `
        -SshTaskTimeoutSeconds 300 `
        -SshConnectTimeoutSeconds ([int]$runtime.SshConnectTimeoutSeconds) `
        -ConfiguredPySshClientPath ([string]$runtime.ConfiguredPySshClientPath))
}

function Get-ClagnosProgramStatusSnapshot {
    param(
        [object[]]$Programs,
        [hashtable]$Options,
        [string]$Platform
    )

    $key = Get-ClagnosProgramStatusCacheKey -Options $Options -Platform $Platform
    if ($null -eq $script:ClagnosProgramStatusCache) { $script:ClagnosProgramStatusCache = @{} }
    if ($script:ClagnosProgramStatusCache -and $script:ClagnosProgramStatusCache.ContainsKey($key)) {
        return $script:ClagnosProgramStatusCache[$key]
    }
    $scriptText = New-ClagnosProgramGuestScript -Action 'status' -Programs $Programs -Platform $Platform
    $result = Invoke-ClagnosProgramGuestScript -Options $Options -Platform $Platform -ScriptText $scriptText -TaskLabel 'program-status'
    $output = ''
    if ($result.TaskOutputs.Count -gt 0) { $output = [string]$result.TaskOutputs[0].Output }
    $match = [regex]::Match($output,'(?m)^CLAGNOS_PROGRAM_RESULTS:(?<json>\[.*\])\s*$')
    if (-not $match.Success) { throw 'Program status response could not be read from the VM.' }
    $rows = @(ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject ([string]$match.Groups['json'].Value)))
    $map = @{}
    foreach ($row in @($rows)) { $map[[string]$row.id] = [string]$row.status }
    $script:ClagnosProgramStatusCache[$key] = $map
    return $map
}

function Get-ClagnosProgramStatus {
    param([object]$Program, [psobject]$Vm)
    $options = @{
        group = [string]$Vm.ClagnosResourceGroup
        'vm-name' = [string]$Vm.name
        'subscription-id' = [string]$Vm.ClagnosSubscriptionId
    }
    $platform = if ([string]::Equals([string]$Vm.storageProfile.osDisk.osType,'Windows',[System.StringComparison]::OrdinalIgnoreCase)) { 'windows' } else { 'linux' }
    $catalog = @(Get-ClagnosProgramCatalog -Platform $platform)
    $snapshot = Get-ClagnosProgramStatusSnapshot -Programs $catalog -Options $options -Platform $platform
    if ($snapshot.ContainsKey([string]$Program.Id)) { return [string]$snapshot[[string]$Program.Id] }
    return 'unknown'
}

function Invoke-ClagnosProgramOperation {
    param(
        [string]$Action,
        [string]$ProgramId,
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $runtime = Initialize-ClagnosTaskExecutionRuntimeContext -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
    $platform = [string]$runtime.Platform
    $catalog = @(Get-ClagnosProgramCatalog -Platform $platform)
    if (@($catalog).Count -eq 0) { Write-Host ("No program installers are registered for '{0}'." -f $platform) -ForegroundColor Yellow; return }
    if ($Action -eq 'list') {
        $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'program'
        $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
        $runtime.Context.VmName = [string]$target.VmName
        $Options['group'] = [string]$target.ResourceGroup
        $Options['vm-name'] = [string]$target.VmName
        $Options['subscription-id'] = [string](Get-ClagnosResolvedSubscriptionContext).SubscriptionId
        $programList = @(Get-ClagnosProgramStatusSnapshot -Programs $catalog -Options $Options -Platform $platform)
        foreach ($program in @($catalog)) { Write-Host ("{0} | {1} | {2}" -f [string]$program.DisplayName,[string]$program.Category,[string]$programList[[string]$program.Id]) }
        return
    }
    $selected = @($catalog | Where-Object { [string]::Equals([string]$_.Id,[string]$ProgramId,[System.StringComparison]::OrdinalIgnoreCase) -or [string]::Equals([string]$_.TaskName,[string]$ProgramId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
    if (@($selected).Count -eq 0) { throw ("Program '{0}' was not found in the active {1} task catalog." -f $ProgramId,$platform) }
    $program = $selected[0]
    $target = Resolve-ClagnosManagedVmTarget -Options $Options -ConfigMap $runtime.EffectiveConfigMap -OperationName 'program'
    $runtime.Context.ResourceGroup = [string]$target.ResourceGroup
    $runtime.Context.VmName = [string]$target.VmName
    $script:ClagnosProgramStatusCache = @{}
    if ($Action -eq 'status') {
        $snapshot = Get-ClagnosProgramStatusSnapshot -Programs @($program) -Options $Options -Platform $platform
        Write-Host ("{0}: {1}" -f [string]$program.DisplayName,[string]$snapshot[[string]$program.Id])
        return
    }
    if ($Action -eq 'install') {
        $installOptions = @{} + $Options
        $installOptions['run-vm-update'] = [string]$program.TaskName
        $run = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options $installOptions -OperationName 'program' -Stage 'update' -Requested ([string]$program.TaskName) -AutoMode:$AutoMode -TaskOutcomeModeOverride 'strict'
        Write-Host ("Installed or updated {0}." -f [string]$program.DisplayName) -ForegroundColor Green
        return $run
    }
    if ($Action -eq 'uninstall') {
        if ($null -eq $program.Uninstall -or [string]::IsNullOrWhiteSpace([string]$program.Uninstall.kind) -or [string]::IsNullOrWhiteSpace([string]$program.Uninstall.value)) {
            throw ("'{0}' has no validated uninstall action in its task manifest." -f [string]$program.DisplayName)
        }
        $approved = Get-ClagnosCliOptionBool -Options $Options -Name 'yes' -DefaultValue $false
        if (-not $approved -and -not $AutoMode) {
            $answer = Read-Host ("Uninstall {0} from VM '{1}'? Type UNINSTALL to confirm" -f [string]$program.DisplayName,[string]$target.VmName)
            $approved = [string]::Equals([string]$answer,'UNINSTALL',[System.StringComparison]::Ordinal)
        }
        if (-not $approved) { Write-Host 'Uninstall canceled.' -ForegroundColor Yellow; return }
        $scriptText = New-ClagnosProgramUninstallScript -Program $program -Platform $platform
        $result = Invoke-ClagnosProgramGuestScript -Options $Options -Platform $platform -ScriptText $scriptText -TaskLabel ('program-uninstall-' + [string]$program.Id)
        $script:ClagnosProgramStatusCache = @{}
        $verify = Get-ClagnosProgramStatusSnapshot -Programs @($program) -Options $Options -Platform $platform
        if ([string]$verify[[string]$program.Id] -eq 'installed') {
            throw ("The uninstall command completed but {0} is still detected on the VM." -f [string]$program.DisplayName)
        }
        Write-Host ("Uninstall completed for {0}." -f [string]$program.DisplayName) -ForegroundColor Green
        return $result
    }
    throw ("Unsupported program action '{0}'." -f $Action)
}
