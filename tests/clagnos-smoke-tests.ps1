param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$script:ClagnosTaskHistoryDisabled = $true
$script:ClagnosTaskHistoryPathOverride = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-smoke-history-' + [guid]::NewGuid().ToString('N') + '\task-runs.jsonl')

$passCount = 0
$failCount = 0

function Invoke-Test {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    try {
        . $Action
        $script:passCount++
        Write-Host ("[PASS] {0}" -f $Name) -ForegroundColor Green
    }
    catch {
        $script:failCount++
        Write-Host ("[FAIL] {0}: {1}" -f $Name, $_.Exception.Message) -ForegroundColor Red
    }
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function ConvertFrom-JsonObjectArrayCompat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputObject
    )

    $parsed = ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop
    return @($parsed | ForEach-Object { $_ })
}

function ConvertFrom-UnicodeCodePoints {
    param([int[]]$CodePoints)

    if ($null -eq $CodePoints -or @($CodePoints).Count -eq 0) {
        return ''
    }

    $builder = New-Object System.Text.StringBuilder
    foreach ($codePoint in @($CodePoints)) {
        [void]$builder.Append([char][int]$codePoint)
    }

    return $builder.ToString()
}

function Get-CurrentSmokeTaskName {
    param([string]$TaskName)

    $map = @{
        '02-install-choco-tool' = '01-install-choco-tool'
        '03-install-openssh-service' = '03-install-openssh-service'
        '04-configure-sshd-service' = '04-configure-sshd-service'
        '05-configure-rdp-service' = '02-configure-rdp-service'
        '101-install-powershell-tool' = '127-install-powershell-tool'
        '102-install-git-tool' = '123-install-git-tool'
        '103-install-python-tool' = '128-install-python-tool'
        '104-install-node-tool' = '111-install-node-tool'
        '105-install-azure-cli-tool' = '130-install-azure-cli-tool'
        '106-install-7zip-tool' = '106-install-7zip-tool'
        '108-install-sysinternals-tool' = '101-install-sysinternals-tool'
        '108-install-ffmpeg-tool' = '113-install-ffmpeg-tool'
        '109-install-vscode-application' = '116-install-vscode-application'
        '110-install-edge-application' = '103-install-edge-application'
        '130-configure-autologon-settings' = '102-configure-autologon-settings'
        '109-install-ffmpeg-tool' = '113-install-ffmpeg-tool'
        '110-install-vscode-application' = '116-install-vscode-application'
        '111-install-edge-application' = '103-install-edge-application'
        '112-install-azd-tool' = '108-install-azd-tool'
        '113-install-wsl-feature' = '121-install-wsl-feature'
        '114-install-docker-desktop-application' = '134-install-docker-desktop-application'
        '116-install-codex-application' = '120-install-codex-application'
        '116-install-ollama-tool' = '135-install-ollama-tool'
        '120-install-codex-application' = '120-install-codex-application'
        '118-install-teams-application' = '114-install-teams-application'
        '118-install-onedrive-application' = '104-install-onedrive-application'
        '119-install-onedrive-application' = '104-install-onedrive-application'
        '119-install-google-drive-application' = '129-install-google-drive-application'
        '120-install-google-drive-application' = '129-install-google-drive-application'
        '120-install-whatsapp-application' = '119-install-whatsapp-application'
        '121-install-whatsapp-application' = '119-install-whatsapp-application'
        '121-install-anydesk-application' = '109-install-anydesk-application'
        '122-install-anydesk-application' = '109-install-anydesk-application'
        '123-install-windscribe-application' = '112-install-windscribe-application'
        '123-install-vlc-application' = '131-install-vlc-application'
        '124-install-itunes-application' = '117-install-itunes-application'
        '124-install-vlc-application' = '131-install-vlc-application'
        '125-install-itunes-application' = '117-install-itunes-application'
        '125-install-be-my-eyes-application' = '118-install-be-my-eyes-application'
        '126-install-be-my-eyes-application' = '118-install-be-my-eyes-application'
        '127-install-nvda-application' = '115-install-nvda-application'
        '128-install-rclone-tool' = '105-install-rclone-tool'
        '129-install-icloud-application' = '122-install-icloud-application'
        '129-configure-unlocker-settings' = '110-configure-unlocker-settings'
        '131-install-icloud-application' = '122-install-icloud-application'
        '130-install-vs2022community-application' = '132-install-vs2022community-application'
        '131-install-jaws-application' = '133-install-jaws-application'
        '132-install-vs2022community-application' = '132-install-vs2022community-application'
        '132-configure-language-settings' = '136-configure-language-settings'
        '133-install-sysinternals-tool' = '101-install-sysinternals-tool'
        '134-configure-autologon-settings' = '102-configure-autologon-settings'
        '10001-configure-startup-settings' = '10002-configure-startup-settings'
        '10002-create-public-desktop-shortcuts' = '10003-create-public-desktop-shortcuts'
        '10003-configure-windows-experience' = '10004-configure-windows-experience'
        '10004-configure-advanced-settings' = '10001-configure-advanced-settings'
        '1090-export-local-app-state-snapshot' = '1002-export-local-app-state-snapshot'
        '1004-disable-services-conservative' = '1001-disable-services-conservative'
    }

    if ($map.ContainsKey([string]$TaskName)) {
        return [string]$map[[string]$TaskName]
    }

    return [string]$TaskName
}

function Get-RepoTaskScriptPath {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [string]$TaskName
    )

    $resolvedTaskName = Get-CurrentSmokeTaskName -TaskName $TaskName
    $extension = if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) { '.sh' } else { '.ps1' }
    if ($Stage -eq 'update' -and $Platform -eq 'windows') {
        $packageIds = @{
            '01-install-choco-tool' = 'chocolatey'; '02-install-winget-tool' = 'windows-package-manager'; '03-install-chrome-application' = 'google-chrome'
            '101-install-sysinternals-tool' = 'sysinternals'; '103-install-edge-application' = 'microsoft-edge'; '104-install-onedrive-application' = 'onedrive'
            '105-install-rclone-tool' = 'rclone'; '106-install-7zip-tool' = '7zip'; '107-install-gh-tool' = 'github-cli'; '108-install-azd-tool' = 'azure-developer-cli'
            '109-install-anydesk-application' = 'anydesk'; '111-install-node-tool' = 'nodejs'; '112-install-windscribe-application' = 'windscribe'; '113-install-ffmpeg-tool' = 'ffmpeg'
            '114-install-teams-application' = 'microsoft-teams'; '115-install-nvda-application' = 'nvda'; '116-install-vscode-application' = 'visual-studio-code'; '117-install-itunes-application' = 'itunes'
            '118-install-be-my-eyes-application' = 'be-my-eyes'; '119-install-whatsapp-application' = 'whatsapp'; '120-install-codex-application' = 'codex-app'; '121-install-wsl-feature' = 'windows-subsystem-linux'
            '122-install-icloud-application' = 'icloud'; '123-install-git-tool' = 'git'; '124-install-openai-codex-tool' = 'openai-codex-cli'; '125-install-github-copilot-tool' = 'github-copilot-cli'
            '126-install-google-gemini-tool' = 'google-gemini-cli'; '127-install-powershell-tool' = 'powershell'; '128-install-python-tool' = 'python'; '129-install-google-drive-application' = 'google-drive'
            '130-install-azure-cli-tool' = 'azure-cli'; '131-install-vlc-application' = 'vlc'; '132-install-vs2022community-application' = 'visual-studio-community'; '133-install-jaws-application' = 'jaws'
            '134-install-docker-desktop-application' = 'docker-desktop'; '135-install-ollama-tool' = 'ollama'
        }
        if ($packageIds.ContainsKey([string]$resolvedTaskName)) {
            return (Join-Path $RepoRoot (Join-Path 'packages\builtin\windows' (Join-Path ([string]$packageIds[[string]$resolvedTaskName]) 'install.ps1')))
        }
    }
    if ($Stage -eq 'update' -and $Platform -eq 'windows') {
        $packageIds = @{
            '01-install-choco-tool' = 'chocolatey'
            '02-install-winget-tool' = 'windows-package-manager'
            '03-install-chrome-application' = 'google-chrome'
            '101-install-sysinternals-tool' = 'sysinternals'
            '103-install-edge-application' = 'microsoft-edge'
            '104-install-onedrive-application' = 'onedrive'
            '105-install-rclone-tool' = 'rclone'
            '106-install-7zip-tool' = '7zip'
            '107-install-gh-tool' = 'github-cli'
            '108-install-azd-tool' = 'azure-developer-cli'
            '109-install-anydesk-application' = 'anydesk'
            '111-install-node-tool' = 'nodejs'
            '112-install-windscribe-application' = 'windscribe'
            '113-install-ffmpeg-tool' = 'ffmpeg'
            '114-install-teams-application' = 'microsoft-teams'
            '115-install-nvda-application' = 'nvda'
            '116-install-vscode-application' = 'visual-studio-code'
            '117-install-itunes-application' = 'itunes'
            '118-install-be-my-eyes-application' = 'be-my-eyes'
            '119-install-whatsapp-application' = 'whatsapp'
            '120-install-codex-application' = 'codex-app'
            '121-install-wsl-feature' = 'windows-subsystem-linux'
            '122-install-icloud-application' = 'icloud'
            '123-install-git-tool' = 'git'
            '124-install-openai-codex-tool' = 'openai-codex-cli'
            '125-install-github-copilot-tool' = 'github-copilot-cli'
            '126-install-google-gemini-tool' = 'google-gemini-cli'
            '127-install-powershell-tool' = 'powershell'
            '128-install-python-tool' = 'python'
            '129-install-google-drive-application' = 'google-drive'
            '130-install-azure-cli-tool' = 'azure-cli'
            '131-install-vlc-application' = 'vlc'
            '132-install-vs2022community-application' = 'visual-studio-community'
            '133-install-jaws-application' = 'jaws'
            '134-install-docker-desktop-application' = 'docker-desktop'
            '135-install-ollama-tool' = 'ollama'
        }
        if ($packageIds.ContainsKey([string]$resolvedTaskName)) {
            return (Join-Path $RepoRoot (Join-Path 'packages\builtin\windows' (Join-Path ([string]$packageIds[[string]$resolvedTaskName]) 'install.ps1')))
        }
    }
    $stageRoot = Join-Path $RepoRoot ("{0}\{1}" -f [string]$Platform, [string]$Stage)
    foreach ($candidate in @(
        (Join-Path $stageRoot ("{0}\{0}{1}" -f [string]$resolvedTaskName, [string]$extension)),
        (Join-Path $stageRoot ("disabled\{0}\{0}{1}" -f [string]$resolvedTaskName, [string]$extension)),
        (Join-Path $stageRoot ("local\{0}\{0}{1}" -f [string]$resolvedTaskName, [string]$extension)),
        (Join-Path $stageRoot ("local\disabled\{0}\{0}{1}" -f [string]$resolvedTaskName, [string]$extension))
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return (Join-Path $stageRoot ("{0}\{0}{1}" -f [string]$resolvedTaskName, [string]$extension))
}

function Get-RepoTaskRootPath {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [string]$TaskName
    )

    return [string](Split-Path -Path (Get-RepoTaskScriptPath -Platform $Platform -Stage $Stage -TaskName $TaskName) -Parent)
}

function Get-RepoTaskJsonPath {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [string]$TaskName
    )

    $taskRoot = Get-RepoTaskRootPath -Platform $Platform -Stage $Stage -TaskName $TaskName
    $packageManifest = Join-Path $taskRoot 'package.json'
    if (Test-Path -LiteralPath $packageManifest -PathType Leaf) { return $packageManifest }
    return (Join-Path $taskRoot 'task.json')
}

function Get-RepoSummaryReadbackScriptPath {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform
    )

    if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) {
        return (Join-Path $RepoRoot 'tools\scripts\clagnos-summary-readback-linux.sh')
    }

    return (Join-Path $RepoRoot 'tools\scripts\clagnos-summary-readback-windows.ps1')
}

function New-RepoTaskTemplate {
    param(
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [ValidateSet('init','update')]
        [string]$Stage,
        [string]$TaskName,
        [int]$TimeoutSeconds = 180
    )

    $stageRootPath = Join-Path $RepoRoot ("{0}\{1}" -f [string]$Platform, [string]$Stage)
    $resolvedTaskName = Get-CurrentSmokeTaskName -TaskName $TaskName
    $scriptPath = Get-RepoTaskScriptPath -Platform $Platform -Stage $Stage -TaskName $resolvedTaskName
    $packageRoot = Split-Path -Path $scriptPath -Parent
    if (Test-Path -LiteralPath (Join-Path $packageRoot 'package.json') -PathType Leaf) {
        $packageId = Split-Path -Path $packageRoot -Leaf
        $package = @(Get-ClagnosPackageCatalog -Platform $Platform -Catalog builtin | Where-Object { [string]::Equals([string]$_.Id,$packageId,[System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1)
        if ($package.Count -ne 1) { throw ("Repo package template could not be resolved: {0}/{1}/{2}" -f [string]$Platform,$Stage,$packageId) }
        $packageTask = $package[0].PackageTask | Select-Object *
        $packageTask.TimeoutSeconds = [int]$TimeoutSeconds
        return $packageTask
    }
    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $stageRootPath -Platform $Platform -Stage $Stage -SuppressSkipMessages
    $taskBlock = @(
        @($catalog.ActiveTasks) + @($catalog.DisabledTasks) |
            Where-Object { [string]$_.Name -eq [string]$resolvedTaskName } |
            Select-Object -First 1
    )[0]
    if ($null -eq $taskBlock) {
        throw ("Repo task template could not be resolved: {0}/{1}/{2}" -f [string]$Platform, [string]$Stage, [string]$resolvedTaskName)
    }

    $template = $taskBlock | Select-Object *
    $template.TimeoutSeconds = [int]$TimeoutSeconds
    return $template
}

function New-SmokeTaskFolder {
    param(
        [string]$RootPath,
        [string]$RelativeFolderPath,
        [ValidateSet('windows','linux')]
        [string]$Platform,
        [string]$ScriptText,
        [hashtable]$TaskJson
    )

    $taskRootPath = Join-Path $RootPath $RelativeFolderPath
    New-Item -Path $taskRootPath -ItemType Directory -Force | Out-Null
    $taskName = Split-Path -Path $RelativeFolderPath -Leaf
    $extension = if ([string]::Equals([string]$Platform, 'linux', [System.StringComparison]::OrdinalIgnoreCase)) { '.sh' } else { '.ps1' }
    Set-Content -LiteralPath (Join-Path $taskRootPath ($taskName + $extension)) -Value $ScriptText -Encoding UTF8
    if ($null -eq $TaskJson) {
        $TaskJson = @{}
    }
    Set-Content -LiteralPath (Join-Path $taskRootPath 'task.json') -Value ($TaskJson | ConvertTo-Json -Depth 12) -Encoding UTF8
    return [pscustomobject]@{
        TaskRootPath = [string]$taskRootPath
        TaskName = [string]$taskName
        ScriptPath = [string](Join-Path $taskRootPath ($taskName + $extension))
        TaskJsonPath = [string](Join-Path $taskRootPath 'task.json')
    }
}

$script:UnifiedScriptPath = Join-Path $RepoRoot "clagnos.ps1"
if (Test-Path -LiteralPath $script:UnifiedScriptPath) {
    . $script:UnifiedScriptPath
}

Invoke-Test -Name "Parse all .ps1 files" -Action {
    $ps1Files = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.ps1 | Sort-Object FullName
    Assert-True -Condition ($ps1Files.Count -gt 0) -Message "No .ps1 files found."

    foreach ($file in $ps1Files) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors -and $errors.Count -gt 0) {
            $firstError = $errors[0]
            throw ("Parse error in '{0}' at line {1}: {2}" -f $file.FullName, $firstError.Extent.StartLineNumber, $firstError.Message)
        }
    }
}

Invoke-Test -Name "Dot-source unified clagnos.ps1" -Action {
    Assert-True -Condition (Test-Path -LiteralPath $script:UnifiedScriptPath) -Message "clagnos.ps1 was not found."
    Assert-True -Condition ($null -ne (Get-Command Get-ClagnosPlatformDefaults -ErrorAction SilentlyContinue)) -Message "Get-ClagnosPlatformDefaults was not loaded."
    Assert-True -Condition ($null -ne (Get-Command Get-ClagnosTaskBlocksFromDirectory -ErrorAction SilentlyContinue)) -Message "Get-ClagnosTaskBlocksFromDirectory was not loaded."
}

Invoke-Test -Name "Launcher loads the modern runtime manifest without legacy root loaders" -Action {
    $launcherText = Get-Content -LiteralPath $script:UnifiedScriptPath -Raw
    $manifestPath = Join-Path $RepoRoot 'modules\clagnos-runtime-manifest.ps1'
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw

    Assert-True -Condition ($launcherText -match [regex]::Escape('modules/clagnos-runtime-manifest.ps1')) -Message "clagnos.ps1 must load the modern runtime manifest."

    foreach ($legacyRelativePath in @(
        'modules\core\clagnos-core-foundation.ps1',
        'modules\core\clagnos-core-runtime.ps1',
        'modules\config\clagnos-config-runtime.ps1',
        'modules\tasks\clagnos-run-command-runtime.ps1',
        'modules\tasks\clagnos-ssh-runtime.ps1',
        'modules\ui\clagnos-ui-runtime.ps1',
        'modules\commands\clagnos-orchestration-runtime.ps1',
        'modules\commands\clagnos-command-main.ps1'
    )) {
        Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $legacyRelativePath))) -Message ("Legacy root loader must not exist: {0}" -f $legacyRelativePath)
        Assert-True -Condition (-not ($launcherText -match [regex]::Escape($legacyRelativePath.Replace('\', '/')))) -Message ("clagnos.ps1 must not reference legacy root loader '{0}'." -f $legacyRelativePath)
        Assert-True -Condition (-not ($manifestText -match [regex]::Escape($legacyRelativePath.Replace('\', '/')))) -Message ("Runtime manifest must not reference legacy root loader '{0}'." -f $legacyRelativePath)
    }
}

Invoke-Test -Name "Platform defaults contract" -Action {
    $win = Get-ClagnosPlatformDefaults -Platform windows
    $lin = Get-ClagnosPlatformDefaults -Platform linux
    Assert-True -Condition ([string]$win.RunCommandId -eq "RunPowerShellScript") -Message "Windows RunCommandId mismatch."
    Assert-True -Condition ([string]$lin.RunCommandId -eq "RunShellScript") -Message "Linux RunCommandId mismatch."
    Assert-True -Condition ([bool]$win.IncludeRdp) -Message "Windows IncludeRdp should be true."
    Assert-True -Condition (-not [bool]$lin.IncludeRdp) -Message "Linux IncludeRdp should be false."
    Assert-True -Condition ([string]$win.VmSizeDefault -eq "Standard_B4as_v2") -Message "Windows VmSizeDefault mismatch."
    Assert-True -Condition ([string]$lin.VmSizeDefault -eq "Standard_B2as_v2") -Message "Linux VmSizeDefault mismatch."
}

Invoke-Test -Name "Azure location picker resolver contract" -Action {
    $catalog = @(
        [pscustomobject]@{ Name = "austriaeast"; DisplayName = "Austria East" },
        [pscustomobject]@{ Name = "centralindia"; DisplayName = "Central India" }
    )

    $entryWithLowercaseName = [pscustomobject]@{ name = "centralindia"; displayName = "Central India" }
    $resolvedFromLowercase = Resolve-ClagnosLocationNameFromEntry -Entry $entryWithLowercaseName -Catalog $catalog -DefaultLocation ""
    Assert-True -Condition ([string]::Equals([string]$resolvedFromLowercase, "centralindia", [System.StringComparison]::OrdinalIgnoreCase)) -Message "Lowercase name location resolution failed."

    $entryWithOnlyDisplay = [pscustomobject]@{ Name = ""; DisplayName = "Austria East" }
    $resolvedFromDisplay = Resolve-ClagnosLocationNameFromEntry -Entry $entryWithOnlyDisplay -Catalog $catalog -DefaultLocation ""
    Assert-True -Condition ([string]::Equals([string]$resolvedFromDisplay, "austriaeast", [System.StringComparison]::OrdinalIgnoreCase)) -Message "Display-name location resolution failed."

    $resolvedFromDefault = Resolve-ClagnosLocationNameFromEntry -Entry $null -Catalog $catalog -DefaultLocation "centralindia"
    Assert-True -Condition ([string]::Equals([string]$resolvedFromDefault, "centralindia", [System.StringComparison]::OrdinalIgnoreCase)) -Message "Default location resolution failed."
}

Invoke-Test -Name "VM name format contract" -Action {
    Assert-True -Condition (Test-ClagnosVmNameFormat -VmName "samplevm") -Message "Expected valid VM name to pass."
    Assert-True -Condition (Test-ClagnosVmNameFormat -VmName "samplelinux-1") -Message "Expected valid VM name with hyphen to pass."
    Assert-True -Condition (-not (Test-ClagnosVmNameFormat -VmName "1samplevm")) -Message "VM name starting with digit should fail."
    Assert-True -Condition (-not (Test-ClagnosVmNameFormat -VmName "ab")) -Message "Too-short VM name should fail."
    Assert-True -Condition (-not (Test-ClagnosVmNameFormat -VmName "samplevm_name")) -Message "VM name with underscore should fail."
}

Invoke-Test -Name "Derived VM name fallback contract" -Action {
    $testEmployeeEmail = ('first.last+ops' + [char]64 + 'example.test')
    $derivedVmName = Get-ClagnosDerivedVmNameFromEmployeeEmailAddress -EmployeeEmailAddress $testEmployeeEmail
    Assert-True -Condition ([string]$derivedVmName -eq 'first-last-ops-vm') -Message "Derived VM name must sanitize the employee email local-part and append -vm."

    $configMap = @{
        SELECTED_EMPLOYEE_EMAIL_ADDRESS = $testEmployeeEmail
        SELECTED_VM_NAME = ''
        VM_IMAGE = ''
        VM_SIZE = ''
        VM_DISK_SIZE_GB = ''
        WIN_VM_IMAGE = 'win:image:latest'
        WIN_VM_SIZE = 'Standard_B4as_v2'
        WIN_VM_DISK_SIZE_GB = '128'
    }
    $resolvedMap = Resolve-ClagnosPlatformConfigMap -ConfigMap $configMap -Platform windows
    Assert-True -Condition ([string]$resolvedMap.SELECTED_VM_NAME -eq 'first-last-ops-vm') -Message "Platform config resolution must derive SELECTED_VM_NAME from SELECTED_EMPLOYEE_EMAIL_ADDRESS when SELECTED_VM_NAME is blank."
}

Invoke-Test -Name "Managed resource naming contract" -Action {
    Assert-ClagnosManagedResourceNamesValid -NameMap @{
        RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
        VNET_NAME = 'net-samplevm-ate1-n1'
        SUBNET_NAME = 'subnet-samplevm-ate1-n1'
        NSG_NAME = 'nsg-samplevm-ate1-n1'
        NSG_RULE_NAME = 'nsg-rule-samplevm-ate1-n1'
        PUBLIC_IP_NAME = 'ip-samplevm-ate1-n1'
        NIC_NAME = 'nic-samplevm-ate1-n1'
        VM_DISK_NAME = 'disk-samplevm-ate1-n1'
    }

    $invalidCases = @(
        @{ Key = 'RESOURCE_GROUP'; Value = 'rg-samplevm-ate1-g1.' },
        @{ Key = 'VNET_NAME'; Value = 'net samplevm' },
        @{ Key = 'NIC_NAME'; Value = 'nic/samplevm' }
    )
    foreach ($case in @($invalidCases)) {
        $threw = $false
        try {
            Assert-ClagnosManagedResourceNamesValid -NameMap @{ ([string]$case.Key) = [string]$case.Value }
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Expected managed name validation to fail for {0}='{1}'." -f [string]$case.Key, [string]$case.Value)
    }
}

Invoke-Test -Name "Platform config precedence mapping" -Action {
    $legacyInitTaskDirKey = (@('VM','INIT','TASK','DIR') -join '_')
    $legacyUpdateTaskDirKey = (@('VM','UPDATE','TASK','DIR') -join '_')
    $platformOnlyConfig = @{
        VM_IMAGE = ""
        VM_SIZE = ""
        VM_DISK_SIZE_GB = ""
        WIN_VM_IMAGE = "win:image:latest"
        WIN_VM_SIZE = "Standard_B4as_v2"
        WIN_VM_DISK_SIZE_GB = "128"
        LIN_VM_IMAGE = "lin:image:latest"
        LIN_VM_SIZE = "Standard_B2as_v2"
        LIN_VM_DISK_SIZE_GB = "40"
    }

    $winMap = Resolve-ClagnosPlatformConfigMap -ConfigMap $platformOnlyConfig -Platform windows
    $linMap = Resolve-ClagnosPlatformConfigMap -ConfigMap $platformOnlyConfig -Platform linux

    Assert-True -Condition ([string]$winMap.VM_IMAGE -eq "win:image:latest") -Message "Windows VM_IMAGE platform mapping failed."
    Assert-True -Condition ([string]$winMap.VM_SIZE -eq "Standard_B4as_v2") -Message "Windows VM_SIZE platform mapping failed."
    Assert-True -Condition ([string]$winMap.VM_DISK_SIZE_GB -eq "128") -Message "Windows VM_DISK_SIZE_GB platform mapping failed."
    Assert-True -Condition ([string]$linMap.VM_IMAGE -eq "lin:image:latest") -Message "Linux VM_IMAGE platform mapping failed."
    Assert-True -Condition ([string]$linMap.VM_SIZE -eq "Standard_B2as_v2") -Message "Linux VM_SIZE platform mapping failed."
    Assert-True -Condition ([string]$linMap.VM_DISK_SIZE_GB -eq "40") -Message "Linux VM_DISK_SIZE_GB platform mapping failed."
    Assert-True -Condition (-not $winMap.ContainsKey($legacyInitTaskDirKey)) -Message "Legacy init task dir key should not be synthesized for windows."
    Assert-True -Condition (-not $winMap.ContainsKey($legacyUpdateTaskDirKey)) -Message "Legacy update task dir key should not be synthesized for windows."
    Assert-True -Condition (-not $linMap.ContainsKey($legacyInitTaskDirKey)) -Message "Legacy init task dir key should not be synthesized for linux."
    Assert-True -Condition (-not $linMap.ContainsKey($legacyUpdateTaskDirKey)) -Message "Legacy update task dir key should not be synthesized for linux."

    $genericFirstConfig = @{
        VM_IMAGE = "generic:image:latest"
        VM_SIZE = "Standard_D2as_v5"
        VM_DISK_SIZE_GB = "256"
        WIN_VM_IMAGE = "win:image:latest"
        WIN_VM_SIZE = "Standard_B4as_v2"
        WIN_VM_DISK_SIZE_GB = "128"
        LIN_VM_IMAGE = "lin:image:latest"
        LIN_VM_SIZE = "Standard_B2as_v2"
        LIN_VM_DISK_SIZE_GB = "40"
    }

    $genericWinMap = Resolve-ClagnosPlatformConfigMap -ConfigMap $genericFirstConfig -Platform windows
    $genericLinMap = Resolve-ClagnosPlatformConfigMap -ConfigMap $genericFirstConfig -Platform linux

    Assert-True -Condition ([string]$genericWinMap.VM_IMAGE -eq "generic:image:latest") -Message "Generic-first VM_IMAGE mapping failed on windows."
    Assert-True -Condition ([string]$genericWinMap.VM_SIZE -eq "Standard_D2as_v5") -Message "Generic-first VM_SIZE mapping failed on windows."
    Assert-True -Condition ([string]$genericWinMap.VM_DISK_SIZE_GB -eq "256") -Message "Generic-first VM_DISK_SIZE_GB mapping failed on windows."
    Assert-True -Condition ([string]$genericLinMap.VM_IMAGE -eq "generic:image:latest") -Message "Generic-first VM_IMAGE mapping failed on linux."
    Assert-True -Condition ([string]$genericLinMap.VM_SIZE -eq "Standard_D2as_v5") -Message "Generic-first VM_SIZE mapping failed on linux."
    Assert-True -Condition ([string]$genericLinMap.VM_DISK_SIZE_GB -eq "256") -Message "Generic-first VM_DISK_SIZE_GB mapping failed on linux."
    Assert-True -Condition (-not $genericWinMap.ContainsKey($legacyInitTaskDirKey)) -Message "Legacy init task dir key should remain unused on windows."
    Assert-True -Condition (-not $genericWinMap.ContainsKey($legacyUpdateTaskDirKey)) -Message "Legacy update task dir key should remain unused on windows."
    Assert-True -Condition (-not $genericLinMap.ContainsKey($legacyInitTaskDirKey)) -Message "Legacy init task dir key should remain unused on linux."
    Assert-True -Condition (-not $genericLinMap.ContainsKey($legacyUpdateTaskDirKey)) -Message "Legacy update task dir key should remain unused on linux."
}

Invoke-Test -Name "Platform task catalog keys stay platform-specific" -Action {
    $config = @{
        WIN_VM_INIT_TASK_DIR = "windows/init"
        WIN_VM_UPDATE_TASK_DIR = "windows/update"
        LIN_VM_INIT_TASK_DIR = "linux/init"
        LIN_VM_UPDATE_TASK_DIR = "linux/update"
    }

    $winInitKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform windows -Stage 'init'
    $winUpdateKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform windows -Stage 'update'
    $linInitKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform linux -Stage 'init'
    $linUpdateKey = Get-ClagnosPlatformTaskCatalogConfigKey -Platform linux -Stage 'update'

    Assert-True -Condition ([string]$winInitKey -eq 'WIN_VM_INIT_TASK_DIR') -Message "Windows init catalog key mapping failed."
    Assert-True -Condition ([string]$winUpdateKey -eq 'WIN_VM_UPDATE_TASK_DIR') -Message "Windows update catalog key mapping failed."
    Assert-True -Condition ([string]$linInitKey -eq 'LIN_VM_INIT_TASK_DIR') -Message "Linux init catalog key mapping failed."
    Assert-True -Condition ([string]$linUpdateKey -eq 'LIN_VM_UPDATE_TASK_DIR') -Message "Linux update catalog key mapping failed."
    Assert-True -Condition ([string](Get-ConfigValue -Config $config -Key $winInitKey -DefaultValue '') -eq 'windows/init') -Message "Windows init catalog path lookup failed."
    Assert-True -Condition ([string](Get-ConfigValue -Config $config -Key $winUpdateKey -DefaultValue '') -eq 'windows/update') -Message "Windows update catalog path lookup failed."
    Assert-True -Condition ([string](Get-ConfigValue -Config $config -Key $linInitKey -DefaultValue '') -eq 'linux/init') -Message "Linux init catalog path lookup failed."
    Assert-True -Condition ([string](Get-ConfigValue -Config $config -Key $linUpdateKey -DefaultValue '') -eq 'linux/update') -Message "Linux update catalog path lookup failed."
}

Invoke-Test -Name ".env.example runtime contract" -Action {
    $envExamplePath = Join-Path $RepoRoot '.env.example'
    Assert-True -Condition (Test-Path -LiteralPath $envExamplePath) -Message ".env.example was not found."

    $envExampleKeys = @(Get-Content $envExamplePath | Where-Object { $_ -match '^[A-Za-z0-9_]+=' } | ForEach-Object { ($_ -split '=', 2)[0] })
    $requiredKeys = @(
        'SELECTED_VM_OS','SELECTED_VM_NAME','SELECTED_RESOURCE_GROUP','SELECTED_COMPANY_NAME','SELECTED_COMPANY_WEB_ADDRESS','SELECTED_COMPANY_EMAIL_ADDRESS','SELECTED_EMPLOYEE_EMAIL_ADDRESS','SELECTED_EMPLOYEE_FULL_NAME','SELECTED_AZURE_SUBSCRIPTION_ID','SELECTED_AZURE_REGION',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_YOUTUBE_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_GITHUB_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_TIKTOK_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_INSTAGRAM_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_FACEBOOK_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_X_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_SNAPCHAT_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_NEXTSOSYAL_URL',
        'WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_LINKEDIN_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_YOUTUBE_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_GITHUB_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_TIKTOK_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_INSTAGRAM_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_FACEBOOK_URL','WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL',
        'WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL','WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_BLOG_URL',
        'RESOURCE_GROUP_TEMPLATE','VNET_NAME_TEMPLATE','SUBNET_NAME_TEMPLATE','NSG_NAME_TEMPLATE','NSG_RULE_NAME_TEMPLATE','PUBLIC_IP_NAME_TEMPLATE','NIC_NAME_TEMPLATE','VM_DISK_NAME_TEMPLATE',
        'VM_STORAGE_SKU','VM_SECURITY_TYPE','VM_ENABLE_HIBERNATION','VM_ENABLE_NESTED_VIRTUALIZATION','VM_ENABLE_SECURE_BOOT','VM_ENABLE_VTPM','VM_PRICE_COUNT_HOURS','VM_ADMIN_USER','VM_ADMIN_PASS','VM_ASSISTANT_USER','VM_ASSISTANT_PASS','VM_SSH_PORT','VM_RDP_PORT',
        'AZURE_COMMAND_TIMEOUT_SECONDS','SSH_CONNECT_TIMEOUT_SECONDS','SSH_TASK_TIMEOUT_SECONDS',
        'WIN_VM_IMAGE','WIN_VM_SIZE','WIN_VM_DISK_SIZE_GB','LIN_VM_IMAGE','LIN_VM_SIZE','LIN_VM_DISK_SIZE_GB',
        'WIN_VM_INIT_TASK_DIR','WIN_VM_UPDATE_TASK_DIR','LIN_VM_INIT_TASK_DIR','LIN_VM_UPDATE_TASK_DIR',
        'VM_TASK_OUTCOME_MODE','SSH_MAX_RETRIES','PYSSH_CLIENT_PATH','TCP_PORTS'
    )

    foreach ($requiredKey in $requiredKeys) {
        Assert-True -Condition ($envExampleKeys -contains $requiredKey) -Message (".env.example is missing required key '{0}'." -f $requiredKey)
    }

    $legacyInitTaskDirKey = (@('VM','INIT','TASK','DIR') -join '_')
    $legacyUpdateTaskDirKey = (@('VM','UPDATE','TASK','DIR') -join '_')
    $legacySshPortKey = (@('SSH','PORT') -join '_')
    Assert-True -Condition (-not ($envExampleKeys -contains $legacyInitTaskDirKey)) -Message ".env.example must not contain the legacy generic init task dir key."
    Assert-True -Condition (-not ($envExampleKeys -contains $legacyUpdateTaskDirKey)) -Message ".env.example must not contain the legacy generic update task dir key."
    Assert-True -Condition (-not ($envExampleKeys -contains $legacySshPortKey)) -Message ".env.example must not contain the legacy SSH_PORT key."

    $envExampleText = Get-Content -LiteralPath $envExamplePath -Raw
    Assert-True -Condition ($envExampleText -match [regex]::Escape('VM_ADMIN_PASS=<CHANGE_ME_STRONG_ADMIN_PASSWORD>')) -Message '.env.example must keep the admin password as a placeholder.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('VM_ASSISTANT_PASS=<CHANGE_ME_STRONG_ASSISTANT_PASSWORD>')) -Message '.env.example must keep the assistant password as a placeholder.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_* values are the committed active-selection contract.')) -Message '.env.example must document the selected-only contract.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_RESOURCE_GROUP=')) -Message '.env.example must expose SELECTED_RESOURCE_GROUP.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('VM_ENABLE_HIBERNATION=true')) -Message '.env.example must expose VM_ENABLE_HIBERNATION as a shared feature toggle.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('VM_ENABLE_NESTED_VIRTUALIZATION=true')) -Message '.env.example must expose VM_ENABLE_NESTED_VIRTUALIZATION as a shared feature toggle.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('NSG_RULE_NAME_TEMPLATE=nsg-rule-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}')) -Message '.env.example must keep the nsg-rule naming prefix on the selected VM placeholder.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('PYSSH_CLIENT_PATH=tools/pyssh/ssh_client.py')) -Message '.env.example must keep a non-empty repo-relative PYSSH client default.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_COMPANY_NAME controls the default Google Chrome profile directory for repo-managed Windows business web shortcuts.')) -Message '.env.example must document SELECTED_COMPANY_NAME for the Windows business public desktop shortcut flow.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('Repo-managed Chrome profile-directory values are normalized to lowercase.')) -Message '.env.example must document lowercase Chrome profile-directory normalization.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('# Optional Windows Public Desktop social/web URL overrides.')) -Message '.env.example must document the optional Windows social/web override block.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL=')) -Message '.env.example must expose the business LinkedIn shortcut override key.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL=')) -Message '.env.example must expose the personal X shortcut override key.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL=')) -Message '.env.example must expose the business home shortcut override key.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_COMPANY_WEB_ADDRESS=<https-url>')) -Message '.env.example must keep the committed SELECTED_COMPANY_WEB_ADDRESS default.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_COMPANY_EMAIL_ADDRESS=<email>')) -Message '.env.example must keep the committed SELECTED_COMPANY_EMAIL_ADDRESS default.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_EMPLOYEE_EMAIL_ADDRESS=<email>')) -Message '.env.example must keep the committed SELECTED_EMPLOYEE_EMAIL_ADDRESS default.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('SELECTED_EMPLOYEE_FULL_NAME=<person-name>')) -Message '.env.example must keep the committed SELECTED_EMPLOYEE_FULL_NAME default.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('VM_PRICE_COUNT_HOURS=730')) -Message '.env.example must expose VM_PRICE_COUNT_HOURS.'
    Assert-True -Condition ($envExampleText -match [regex]::Escape('AZURE_COMMAND_TIMEOUT_SECONDS=1800')) -Message '.env.example must expose AZURE_COMMAND_TIMEOUT_SECONDS.'
    Assert-True -Condition (-not ($envExampleText -match [regex]::Escape('<runtime-secret>'))) -Message '.env.example must not keep the old committed assistant password.'
}

Invoke-Test -Name "Shared feature toggles and pyssh path are wired into runtime defaults" -Action {
    $platformDefaultsText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\platform\clagnos-platform-defaults.ps1') -Raw
    $commandContextText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\context\clagnos-step1-context.ps1') -Raw
    $featureSupportText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\features\clagnos-feature-support.ps1') -Raw
    $commandRuntimeText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\shared\runtime\clagnos-command-runtime-context.ps1') -Raw
    $mainText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-command.ps1') -Raw
    $mainWorkflowText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-workflow.ps1') -Raw

    Assert-True -Condition ($platformDefaultsText -match [regex]::Escape("return 'tools/pyssh/ssh_client.py'")) -Message 'Platform defaults must publish a non-empty PYSSH client path.'
    Assert-True -Condition ($commandContextText -match [regex]::Escape('VM_ENABLE_HIBERNATION')) -Message 'Command context must read VM_ENABLE_HIBERNATION.'
    Assert-True -Condition ($commandContextText -match [regex]::Escape('VM_ENABLE_NESTED_VIRTUALIZATION')) -Message 'Command context must read VM_ENABLE_NESTED_VIRTUALIZATION.'
    Assert-True -Condition ($featureSupportText -match [regex]::Escape('VM_ENABLE_HIBERNATION=false.')) -Message 'Feature support must honor disabling hibernation by config.'
    Assert-True -Condition ($featureSupportText -match [regex]::Escape('VM_ENABLE_NESTED_VIRTUALIZATION=false.')) -Message 'Feature support must honor disabling nested virtualization by config.'
    Assert-True -Condition ($commandContextText -match [regex]::Escape('nsg-rule-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}')) -Message 'Command context must use the selected VM naming template prefix.'
    Assert-True -Condition ($commandRuntimeText -match [regex]::Escape('Get-ClagnosDefaultPySshClientPathText')) -Message 'Shared command runtime must consume the shared PYSSH client default.'
    Assert-True -Condition ($mainText -match [regex]::Escape('Write-ClagnosMainBanner')) -Message 'Command main must render the review-first banner helper.'
    Assert-True -Condition ($mainWorkflowText -match [regex]::Escape('function Write-ClagnosMainBanner')) -Message 'Main workflow helper must publish the banner renderer.'
    Assert-True -Condition ($commandContextText -match [regex]::Escape('SELECTED_COMPANY_NAME')) -Message 'Command context must read SELECTED_COMPANY_NAME from config.'
    Assert-True -Condition ($commandContextText -match [regex]::Escape('SELECTED_EMPLOYEE_EMAIL_ADDRESS')) -Message 'Command context must read SELECTED_EMPLOYEE_EMAIL_ADDRESS from config.'
    Assert-True -Condition ($commandContextText -match [regex]::Escape('SELECTED_EMPLOYEE_FULL_NAME')) -Message 'Command context must read SELECTED_EMPLOYEE_FULL_NAME from config.'
    Assert-True -Condition ($commandRuntimeText -match [regex]::Escape('SELECTED_COMPANY_NAME')) -Message 'Command runtime must read SELECTED_COMPANY_NAME from config.'
    Assert-True -Condition ($commandRuntimeText -match [regex]::Escape('SELECTED_EMPLOYEE_EMAIL_ADDRESS')) -Message 'Command runtime must read SELECTED_EMPLOYEE_EMAIL_ADDRESS from config.'
    Assert-True -Condition ($commandRuntimeText -match [regex]::Escape('SELECTED_EMPLOYEE_FULL_NAME')) -Message 'Command runtime must read SELECTED_EMPLOYEE_FULL_NAME from config.'
    Assert-True -Condition ($commandRuntimeText -match [regex]::Escape('AZURE_COMMAND_TIMEOUT_SECONDS')) -Message 'Command runtime must read AZURE_COMMAND_TIMEOUT_SECONDS from config.'
}

Invoke-Test -Name "Runtime modules no longer carry personal or secret defaults" -Action {
    $filesToScan = @(
        (Get-ChildItem -Path (Join-Path $RepoRoot 'modules') -Recurse -Filter *.ps1 | ForEach-Object { $_.FullName })
        (Join-Path $RepoRoot 'tools\install-pyssh-tool.ps1')
    )

    foreach ($filePath in @($filesToScan)) {
        $text = Get-Content -LiteralPath $filePath -Raw
        foreach ($forbiddenFragment in @('examplevm','otherexamplevm','<runtime-secret>','<runtime-secret>')) {
            Assert-True -Condition (($text.IndexOf($forbiddenFragment, [System.StringComparison]::OrdinalIgnoreCase)) -lt 0) -Message ("Runtime file '{0}' must not contain '{1}'." -f $filePath, $forbiddenFragment)
        }
    }
}

Invoke-Test -Name "Task outcome mode is not platform-forced" -Action {
    $mainPath = Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-command.ps1'
    $runtimeContextPath = Join-Path $RepoRoot 'modules\commands\shared\runtime\clagnos-command-runtime-context.ps1'

    $mainText = Get-Content -LiteralPath $mainPath -Raw
    $runtimeContextText = Get-Content -LiteralPath $runtimeContextPath -Raw

    Assert-True -Condition ($mainText -notmatch "platform\s*-eq\s*'windows'[\s\S]{0,120}taskOutcomeMode\s*=\s*'strict'") -Message "Main command runtime must not force windows task outcome mode to strict."
    Assert-True -Condition ($runtimeContextText -notmatch "platform\s*-eq\s*'windows'[\s\S]{0,120}taskOutcomeMode\s*=\s*'strict'") -Message "Shared command runtime must not force windows task outcome mode to strict."

    $runCommandDefinition = Get-Command Invoke-VmRunCommandBlocks -CommandType Function
    Assert-True -Condition ($null -ne $runCommandDefinition) -Message "Run-command task runner function was not loaded."
    Assert-True -Condition ($runCommandDefinition.Parameters.ContainsKey('TaskOutcomeMode')) -Message "Run-command task runner must expose TaskOutcomeMode parameter."
}

Invoke-Test -Name "Create, initialize, and update have separate lifecycle stages" -Action {
    $createPlan = Resolve-ClagnosActionPlan -CommandName 'create' -Options @{}
    $updatePlan = Resolve-ClagnosActionPlan -CommandName 'update' -Options @{}
    $initializeEntry = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\initialize\entry.ps1') -Raw
    $helpText = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\cli\clagnos-help.ps1') -Raw

    Assert-True -Condition ((@($createPlan.Actions) -join ',') -eq 'configure,group,network,vm-deploy,vm-summary') -Message 'Create must provision infrastructure and stop after the summary.'
    Assert-True -Condition ((@($updatePlan.Actions) -join ',') -eq 'configure,vm-update,vm-summary') -Message 'Update must run only the maintenance stage and summary.'
    Assert-True -Condition ($initializeEntry -match [regex]::Escape("Target = 'vm-init'")) -Message 'Initialize must dispatch the vm-init stage for an existing VM.'
    Assert-True -Condition ($initializeEntry -match [regex]::Escape("-CommandName 'initialize'")) -Message 'Initialize must be visible as its own command operation.'
    Assert-True -Condition ($helpText -match [regex]::Escape('Allowed steps: configure, group, network, vm-deploy, vm-summary')) -Message 'Create help must list only its infrastructure steps.'
    Assert-True -Condition ($helpText -match [regex]::Escape('Allowed steps: configure, vm-update, vm-summary')) -Message 'Update help must list only its maintenance steps.'
    Assert-True -Condition ($helpText -match [regex]::Escape('It does not create, redeploy, or initialize Azure resources')) -Message 'Update help must not describe infrastructure or init work.'
    Assert-True -Condition ($helpText -notmatch [regex]::Escape('Existing VMs are redeployed after Azure create-or-update.')) -Message 'Update help must not claim existing VMs are redeployed.'
}

Invoke-Test -Name "Create and update use review-first workflow checkpoints" -Action {
    $mainPath = Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-command.ps1'
    $mainWorkflowPath = Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-workflow.ps1'
    $mainText = Get-Content -LiteralPath $mainPath -Raw
    $mainWorkflowText = Get-Content -LiteralPath $mainWorkflowPath -Raw

    $checkpointMatches = [regex]::Matches($mainText, [regex]::Escape('Invoke-ClagnosReviewCheckpoint'))
    Assert-True -Condition ($checkpointMatches.Count -eq 4) -Message 'Main command must invoke exactly four review checkpoints.'
    Assert-True -Condition ($mainText -match [regex]::Escape("Show-ClagnosStepReview -Title 'Configuration review'")) -Message 'Main command must always show the configuration review screen.'
    Assert-True -Condition ($mainText -match [regex]::Escape("Write-ClagnosWorkflowSummary")) -Message 'Main command must always print the workflow summary stage.'
    Assert-True -Condition ($mainText -match [regex]::Escape('$groupDecision = Invoke-ClagnosReviewCheckpoint')) -Message 'Group stage must use a review checkpoint.'
    Assert-True -Condition ($mainText -match [regex]::Escape('$deployDecision = Invoke-ClagnosReviewCheckpoint')) -Message 'VM deploy stage must use a review checkpoint.'
    Assert-True -Condition ($mainText -match [regex]::Escape('$initDecision = Invoke-ClagnosReviewCheckpoint')) -Message 'VM init stage must use a review checkpoint.'
    Assert-True -Condition ($mainText -match [regex]::Escape('$updateDecision = Invoke-ClagnosReviewCheckpoint')) -Message 'VM update stage must use a review checkpoint.'
    Assert-True -Condition (-not ($mainText -match [regex]::Escape('$configureDecision = Invoke-ClagnosReviewCheckpoint'))) -Message 'Configure stage must not request confirmation.'
    Assert-True -Condition (-not ($mainText -match [regex]::Escape('$summaryDecision = Invoke-ClagnosReviewCheckpoint'))) -Message 'VM summary stage must not request confirmation.'
    Assert-True -Condition ($mainWorkflowText -match [regex]::Escape('Confirm-YesNoCancel')) -Message 'Review workflow must use yes/no/cancel prompts.'
}

Invoke-Test -Name "Task catalog discovery" -Action {
    $winInit = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath (Join-Path $RepoRoot "windows\init") -Platform windows -Stage init
    $winUpdate = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath (Join-Path $RepoRoot "windows\update") -Platform windows -Stage update
    $linInit = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath (Join-Path $RepoRoot "linux\init") -Platform linux -Stage init
    $linUpdate = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath (Join-Path $RepoRoot "linux\update") -Platform linux -Stage update

    Assert-True -Condition (@($winInit.ActiveTasks).Count -ge 1) -Message "Windows init active tasks are missing."
    Assert-True -Condition (@($winUpdate.ActiveTasks).Count -ge 1) -Message "Windows update active tasks are missing."
    Assert-True -Condition (@($linInit.ActiveTasks).Count -ge 1) -Message "Linux init active tasks are missing."
    Assert-True -Condition (@($linUpdate.ActiveTasks).Count -ge 1) -Message "Linux update active tasks are missing."

    foreach ($catalog in @($winInit, $winUpdate, $linInit, $linUpdate)) {
        foreach ($task in @($catalog.ActiveTasks)) {
            $hasTimeout = ($task.PSObject.Properties.Match('TimeoutSeconds').Count -gt 0)
            Assert-True -Condition $hasTimeout -Message ("Task '{0}' must expose TimeoutSeconds from catalog." -f [string]$task.Name)
            Assert-True -Condition ([int]$task.TimeoutSeconds -ge 5) -Message ("Task '{0}' has invalid TimeoutSeconds value '{1}'." -f [string]$task.Name, [string]$task.TimeoutSeconds)
        }
    }
}

Invoke-Test -Name "Task availability actions move and verify catalog entries safely" -Action {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-task-toggle-{0}' -f ([guid]::NewGuid().ToString('N')))
    $stageRoot = Join-Path $testRoot 'windows\update'
    $taskName = '101-install-toggle-tool'
    $activeTaskRoot = Join-Path $stageRoot $taskName
    $script:ClagnosTaskAvailabilityToggleAnswer = 'DISABLE'
    New-Item -ItemType Directory -Path $activeTaskRoot -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $activeTaskRoot ($taskName + '.ps1')), "Write-Output 'toggle-test'`r`n", [System.Text.UTF8Encoding]::new($false))
    $manifestText = @'
{
  "priority": 101,
  "enabled": true,
  "timeout": 60,
  "customMetadata": "preserve-me"
}
'@
    [System.IO.File]::WriteAllText((Join-Path $activeTaskRoot 'task.json'), $manifestText, [System.Text.UTF8Encoding]::new($false))

    try {
        function Read-Host {
            param([string]$Prompt)
            return [string]$script:ClagnosTaskAvailabilityToggleAnswer
        }

        $disabled = Invoke-ClagnosTaskAvailabilityToggle -StageRoot $stageRoot -Platform 'windows' -Stage 'update' -TaskNumberOrName $taskName -Action 'disable'
        Assert-True -Condition (-not [bool]$disabled.Enabled -and [bool]$disabled.Changed) -Message 'Disable must move an active task into the disabled inventory.'
        $disabledPath = Join-Path (Join-Path $stageRoot 'disabled') $taskName
        Assert-True -Condition (Test-Path -LiteralPath $disabledPath) -Message 'Disable must preserve the full task folder under disabled/.'
        $disabledCatalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $stageRoot -Platform windows -Stage update -SuppressSkipMessages
        $disabledTask = @($disabledCatalog.DisabledTasks | Where-Object { [string]$_.Name -eq $taskName } | Select-Object -First 1)
        Assert-True -Condition (@($disabledTask).Count -eq 1 -and [string]$disabledTask[0].DisabledReason -eq 'disabled-by-location') -Message 'Disabled task folders must remain visible with their location reason.'

        $script:ClagnosTaskAvailabilityToggleAnswer = 'ENABLE'
        $enabled = Invoke-ClagnosTaskAvailabilityToggle -StageRoot $stageRoot -Platform 'windows' -Stage 'update' -TaskNumberOrName '101' -Action 'enable'
        Assert-True -Condition ([bool]$enabled.Enabled -and [bool]$enabled.Changed) -Message 'Enable by task number must restore the task to the active catalog.'
        Assert-True -Condition (Test-Path -LiteralPath $activeTaskRoot) -Message 'Enable must move the task folder back to the active stage root.'
        $manifest = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath (Join-Path $activeTaskRoot 'task.json') -Raw))
        Assert-True -Condition ([bool]$manifest.enabled) -Message 'Enable must update a false task.json enabled value.'
        Assert-True -Condition ([string]$manifest.customMetadata -eq 'preserve-me') -Message 'Enable must preserve unrelated task.json metadata.'

        Set-ClagnosTaskManifestEnabled -ManifestPath (Join-Path $activeTaskRoot 'task.json') -Enabled $false
        $manifestDisabled = Invoke-ClagnosTaskAvailabilityToggle -StageRoot $stageRoot -Platform 'windows' -Stage 'update' -TaskNumberOrName $taskName -Action 'enable'
        Assert-True -Condition ([bool]$manifestDisabled.Enabled -and [bool]$manifestDisabled.Changed) -Message 'Enable must also clear an explicit task.json disabled state.'

        $script:ClagnosTaskAvailabilityToggleAnswer = 'NO'
        $cancelled = Invoke-ClagnosTaskAvailabilityToggle -StageRoot $stageRoot -Platform 'windows' -Stage 'update' -TaskNumberOrName $taskName -Action 'disable'
        Assert-True -Condition (-not [bool]$cancelled.Changed -and [bool]$cancelled.Enabled) -Message 'A rejected typed confirmation must leave the task enabled.'
        Assert-True -Condition (Test-Path -LiteralPath $activeTaskRoot) -Message 'A rejected typed confirmation must leave the task folder in place.'
    }
    finally {
        Remove-Item -LiteralPath 'Function:\Read-Host' -Force -ErrorAction SilentlyContinue
        $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
        $script:ClagnosTaskAvailabilityToggleAnswer = $null
    }
}

Invoke-Test -Name "Builtin and custom package catalogs stay isolated and availability updates only package manifests" -Action {
    $testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-package-catalog-{0}' -f ([guid]::NewGuid().ToString('N')))
    $builtinRoot = Join-Path $testRoot 'builtin\windows'
    $customRoot = Join-Path $testRoot 'custom\windows'
    $packageId = 'shared-tool'
    $builtinFolder = Join-Path $builtinRoot $packageId
    $customFolder = Join-Path $customRoot $packageId
    $script:ClagnosPackageToggleAnswer = 'DISABLE'
    New-Item -ItemType Directory -Path $builtinFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $customFolder -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $builtinFolder 'install.ps1'), "Write-Output 'builtin'`r`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $customFolder 'install.ps1'), "Write-Output 'custom'`r`n", [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $customFolder 'helper.ps1'), "Write-Output 'asset'`r`n", [System.Text.UTF8Encoding]::new($false))
    $builtinManifest = [ordered]@{
        id = $packageId
        displayName = 'Builtin Shared Tool'
        category = 'tool'
        enabled = $true
        timeout = 45
        sortOrder = 1
        installScript = 'install.ps1'
        statusCheck = @{ kind = 'command'; value = 'shared-tool' }
        uninstall = @{ kind = 'choco'; value = 'shared-tool' }
    }
    $customManifest = [ordered]@{
        id = $packageId
        displayName = 'Custom Shared Tool'
        category = 'tool'
        enabled = $true
        timeout = 90
        sortOrder = 2
        installScript = 'install.ps1'
        statusCheck = @{ kind = 'command'; value = 'custom-shared-tool' }
        uninstall = @{ kind = 'choco'; value = 'custom-shared-tool' }
        appStateKey = 'previous-shared-tool-installer'
        appState = @{ profileFiles = @() }
        assets = @(@{ local = 'helper.ps1'; remote = 'C:/Windows/Temp/package-helper.ps1' })
        customMetadata = 'preserve-me'
    }
    [System.IO.File]::WriteAllText((Join-Path $builtinFolder 'package.json'), (ConvertTo-Json $builtinManifest -Depth 20), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $customFolder 'package.json'), (ConvertTo-Json $customManifest -Depth 20), [System.Text.UTF8Encoding]::new($false))

    try {
        function Read-Host {
            param([string]$Prompt)
            return [string]$script:ClagnosPackageToggleAnswer
        }

        $builtin = @(Get-ClagnosPackageCatalog -Platform windows -Catalog builtin -CatalogRoot $builtinRoot)
        $custom = @(Get-ClagnosPackageCatalog -Platform windows -Catalog custom -CatalogRoot $customRoot)
        Assert-True -Condition ($builtin.Count -eq 1 -and $custom.Count -eq 1 -and $builtin[0].Id -eq $custom[0].Id) -Message 'The same package id may exist in isolated builtin and custom catalogs.'
        Assert-True -Condition ($builtin[0].Catalog -eq 'builtin' -and $custom[0].Catalog -eq 'custom') -Message 'Each catalog row must preserve its builtin/custom origin.'
        Assert-True -Condition ([string]$custom[0].PackageTask.AppStateKey -eq 'previous-shared-tool-installer' -and [string]$custom[0].PackageTask.AppStateSpec.taskName -eq 'previous-shared-tool-installer') -Message 'Package appStateKey must preserve the identity used by existing app-state archives.'
        $resolvedCustom = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($custom[0].PackageTask) -Context @{})[0]
        Assert-True -Condition ($resolvedCustom.AssetCopies.Count -ge 1 -and (Test-Path -LiteralPath $resolvedCustom.AssetCopies[0].LocalPath)) -Message 'Custom package assets must resolve relative to their package folder.'
        $appStateRuntime = [pscustomobject]@{ Platform = 'windows'; Context = @{} }
        $packageAppStateOptions = @{ 'save-app-state' = $true; package = 'google-chrome'; 'package-catalog' = 'builtin' }
        Assert-ClagnosTaskCommandOptionScope -Mode 'save-app-state' -Options $packageAppStateOptions
        $packageSelection = Resolve-ClagnosTaskBlockForMaintenance -Runtime $appStateRuntime -Options $packageAppStateOptions
        Assert-True -Condition ($packageSelection.Stage -eq 'package' -and $packageSelection.TaskBlock.Name -eq 'google-chrome' -and $packageSelection.TaskBlock.AppStateKey -eq '03-install-chrome-application') -Message 'Task app-state selection must resolve packages by id and catalog while keeping their archive identity.'

        $disabled = Invoke-ClagnosPackageOperation -Action disable -PackageId $packageId -Catalog custom -CatalogRoot $customRoot -Options @{} -WindowsFlag
        Assert-True -Condition (-not [bool]$disabled.Enabled -and [bool]$disabled.Changed) -Message 'Disabling a package must update only its selected catalog entry.'
        Assert-True -Condition ((Test-Path -LiteralPath $customFolder) -and (Test-Path -LiteralPath (Join-Path $builtinFolder 'package.json'))) -Message 'Availability changes must not move packages between catalogs.'
        $customAfterDisable = @(Get-ClagnosPackageCatalog -Platform windows -Catalog custom -CatalogRoot $customRoot)
        Assert-True -Condition ($customAfterDisable.Count -eq 1 -and -not [bool]$customAfterDisable[0].Enabled) -Message 'Disabled packages must remain visible in their catalog.'
        $updatedManifest = ConvertFrom-Json -InputObject ([string](Get-Content -LiteralPath (Join-Path $customFolder 'package.json') -Raw))
        Assert-True -Condition ([string]$updatedManifest.customMetadata -eq 'preserve-me' -and [string]$updatedManifest.appStateKey -eq 'previous-shared-tool-installer') -Message 'Availability changes must preserve unrelated package manifest metadata.'

        $installBlocked = $false
        try { [void](Invoke-ClagnosPackageOperation -Action install -PackageId $packageId -Catalog custom -CatalogRoot $customRoot -Options @{} -WindowsFlag) }
        catch { $installBlocked = $_.Exception.Message -match 'disabled in the custom package catalog' }
        Assert-True -Condition $installBlocked -Message 'Disabled packages must be blocked from install before target resolution.'

        $script:ClagnosPackageToggleAnswer = 'ENABLE'
        $enabled = Invoke-ClagnosPackageOperation -Action enable -PackageId $packageId -Catalog custom -CatalogRoot $customRoot -Options @{} -WindowsFlag
        Assert-True -Condition ([bool]$enabled.Enabled -and [bool]$enabled.Changed) -Message 'Enabling a package must restore its install availability.'
        $script:ClagnosPackageToggleAnswer = 'NO'
        $cancelled = Invoke-ClagnosPackageOperation -Action disable -PackageId $packageId -Catalog custom -CatalogRoot $customRoot -Options @{} -WindowsFlag
        Assert-True -Condition (-not [bool]$cancelled.Changed -and [bool]$cancelled.Enabled) -Message 'A rejected package confirmation must leave package.json unchanged.'
    }
    finally {
        Remove-Item -LiteralPath 'Function:\Read-Host' -Force -ErrorAction SilentlyContinue
        $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
        $resolvedTestRoot = [System.IO.Path]::GetFullPath($testRoot)
        if ($resolvedTestRoot.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTestRoot)) {
            Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
        }
        $script:ClagnosPackageToggleAnswer = $null
    }
}

Invoke-Test -Name "Package status catalog payloads flatten Windows PowerShell 5.1 JSON root arrays" -Action {
    $packageRuntimePath = Join-Path $RepoRoot 'modules\commands\package\runtime.ps1'
    $packageRuntimeText = [string](Get-Content -LiteralPath $packageRuntimePath -Raw -ErrorAction Stop)
    Assert-True -Condition ($packageRuntimeText.IndexOf('parsedPackageInput = ConvertFrom-Json -InputObject',[System.StringComparison]::Ordinal) -ge 0) -Message 'Package status must parse the complete catalog payload before iterating.'
    Assert-True -Condition ($packageRuntimeText.IndexOf('entry -is [System.Collections.IList]',[System.StringComparison]::Ordinal) -ge 0) -Message 'Package status must flatten a nested PowerShell 5.1 JSON array before evaluating status checks.'
    Assert-True -Condition ($packageRuntimeText.IndexOf('nestedPackage in',[System.StringComparison]::Ordinal) -ge 0) -Message 'Package status must evaluate every nested catalog package row.'
    $fixtureJson = ConvertTo-Json -InputObject @(@{ id = 'first-package' },@{ id = 'second-package' }) -Depth 5 -Compress
    $parsedPackageInput = ConvertFrom-Json -InputObject $fixtureJson -ErrorAction Stop
    $flattenedPackages = @()
    foreach ($entry in @($parsedPackageInput)) {
        if ($entry -is [System.Collections.IList] -and $entry -isnot [string]) {
            foreach ($nestedPackage in $entry) { $flattenedPackages += $nestedPackage }
        }
        elseif ($null -ne $entry) { $flattenedPackages += $entry }
    }
    Assert-True -Condition ($flattenedPackages.Count -eq 2 -and [string]$flattenedPackages[0].id -eq 'first-package' -and [string]$flattenedPackages[1].id -eq 'second-package') -Message 'Package status normalization must preserve every JSON package row under Windows PowerShell.'
}

Invoke-Test -Name "Package status cache persists fresh results and SSH bootstrap reuses a successful probe" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-read-cache-' + [guid]::NewGuid().ToString('N'))
    $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
    $tempPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
    Assert-True -Condition ($resolvedTempRoot.StartsWith($tempPrefix,[System.StringComparison]::OrdinalIgnoreCase)) -Message 'Read-cache fixture must stay under the system temporary directory.'
    $previousLocalAppData = [string]$env:LOCALAPPDATA
    $previousPackageCache = $script:ClagnosPackageStatusCache
    $previousPackageTtl = [int]$script:ClagnosPackageStatusCacheTtlSeconds
    $previousSshCache = $script:ClagnosSshBootstrapCache
    $previousSshTtl = [int]$script:ClagnosSshBootstrapCacheTtlSeconds
    $originalProcessRunner = (Get-Command Invoke-ClagnosProcessWithRetry -CommandType Function -ErrorAction Stop).ScriptBlock
    $sshPythonPath = Join-Path $tempRoot 'python-fixture.exe'
    $sshClientPath = Join-Path $tempRoot 'ssh-client-fixture.py'

    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Set-Content -LiteralPath $sshPythonPath -Value 'fixture' -Encoding ASCII
        Set-Content -LiteralPath $sshClientPath -Value 'fixture' -Encoding ASCII
        $env:LOCALAPPDATA = $tempRoot
        $script:ClagnosPackageStatusCache = @{}
        $script:ClagnosPackageStatusCacheTtlSeconds = 45
        $script:ClagnosSshBootstrapCache = @{}
        $script:ClagnosSshBootstrapCacheTtlSeconds = 20

        $packages = @([pscustomobject]@{ Catalog = 'builtin'; Id = 'cache-fixture'; StatusCheck = [pscustomobject]@{ kind = 'command'; value = 'cache-fixture-command' } })
        $options = @{ 'subscription-id' = 'sub-cache-fixture'; group = 'rg-cache-fixture'; 'vm-name' = 'vm-cache-fixture' }
        $cacheKey = Get-ClagnosPackageStatusCacheKey -Packages $packages -Options $options -Platform 'windows'
        $cacheEntry = @{ CreatedAtUtc = [DateTime]::UtcNow; Complete = $true; StatusByPackage = @{ 'cache-fixture' = 'installed' } }
        Save-ClagnosPackageStatusCacheEntry -Key $cacheKey -Entry $cacheEntry
        $freshCache = Get-ClagnosPackageStatusCacheEntry -Packages $packages -Options $options -Platform 'windows'
        Assert-True -Condition ($null -ne $freshCache -and [bool]$freshCache.IsFresh -and [string]$freshCache.Entry.StatusByPackage['cache-fixture'] -eq 'installed') -Message ('A complete package status snapshot must persist and be reusable within its freshness window. Path={0}; Exists={1}; Fresh={2}; Status={3}; DiskWritesDisabled={4}' -f (Get-ClagnosPackageStatusDiskCachePath -Key $cacheKey),(Test-Path -LiteralPath (Get-ClagnosPackageStatusDiskCachePath -Key $cacheKey)),[bool]$freshCache.IsFresh,[string]$freshCache.Entry.StatusByPackage['cache-fixture'],[string]$env:CLAGNOS_PACKAGE_STATUS_CACHE_NO_DISK_WRITE)

        $freshCache.Entry.CreatedAtUtc = [DateTime]::UtcNow.AddSeconds(-46)
        Save-ClagnosPackageStatusCacheEntry -Key $cacheKey -Entry $freshCache.Entry
        $expiredCache = Get-ClagnosPackageStatusCacheEntry -Packages $packages -Options $options -Platform 'windows'
        Assert-True -Condition ($null -ne $expiredCache -and -not [bool]$expiredCache.IsFresh -and [string]$expiredCache.Entry.StatusByPackage['cache-fixture'] -eq 'installed') -Message 'Expired status may be displayed as cached but must be marked stale for background revalidation.'

        $changedPackages = @([pscustomobject]@{ Catalog = 'builtin'; Id = 'cache-fixture'; StatusCheck = [pscustomobject]@{ kind = 'command'; value = 'changed-cache-fixture-command' } })
        $changedKey = Get-ClagnosPackageStatusCacheKey -Packages $changedPackages -Options $options -Platform 'windows'
        Assert-True -Condition ($changedKey -cne $cacheKey) -Message 'Changing the package status-check definition must invalidate its previous status snapshot.'

        $script:ClagnosSshProbeCount = 0
        Set-Item -Path Function:\Invoke-ClagnosProcessWithRetry -Value {
            param([string]$FilePath,[string[]]$Arguments,[string]$Label,[int]$MaxAttempts,[switch]$AllowFailure)
            $script:ClagnosSshProbeCount++
            return [pscustomobject]@{ ExitCode = 0; Output = 'manager-fixture' }
        }
        $probeArgs = @{ PySshPythonPath = $sshPythonPath; PySshClientPath = $sshClientPath; HostName = 'host-fixture'; UserName = 'manager-fixture'; Password = 'transient-fixture-secret'; Port = '22222'; ConnectTimeoutSeconds = 10 }
        $firstProbe = Initialize-ClagnosSshHostKey @probeArgs
        $secondProbe = Initialize-ClagnosSshHostKey @probeArgs
        $forcedProbe = Initialize-ClagnosSshHostKey @probeArgs -Force
        Assert-True -Condition ($script:ClagnosSshProbeCount -eq 2 -and -not [bool]$firstProbe.Cached -and [bool]$secondProbe.Cached -and -not [bool]$forcedProbe.Cached) -Message 'A successful SSH probe must be reused briefly and an explicit forced probe must reconnect.'
        $sshCacheText = ConvertTo-Json -InputObject $script:ClagnosSshBootstrapCache -Depth 8 -Compress
        Assert-True -Condition ($sshCacheText -notmatch [regex]::Escape('transient-fixture-secret')) -Message 'SSH bootstrap cache contents must not retain the password.'
    }
    finally {
        Set-Item -Path Function:\Invoke-ClagnosProcessWithRetry -Value $originalProcessRunner
        $script:ClagnosPackageStatusCache = $previousPackageCache
        $script:ClagnosPackageStatusCacheTtlSeconds = $previousPackageTtl
        $script:ClagnosSshBootstrapCache = $previousSshCache
        $script:ClagnosSshBootstrapCacheTtlSeconds = $previousSshTtl
        $script:ClagnosSshProbeCount = 0
        if ([string]::IsNullOrWhiteSpace($previousLocalAppData)) { Remove-Item Env:\LOCALAPPDATA -ErrorAction SilentlyContinue }
        else { $env:LOCALAPPDATA = $previousLocalAppData }
        if ($resolvedTempRoot.StartsWith($tempPrefix,[System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTempRoot)) { Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force }
    }
}

Invoke-Test -Name "Package status reads the same ProgramData stores used by installers" -Action {
    $packageRuntimeText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\package\runtime.ps1') -Raw -ErrorAction Stop)
    Assert-True -Condition ($packageRuntimeText.IndexOf('clagnos\state\store-installs',[System.StringComparison]::Ordinal) -ge 0) -Message 'Store package status must read the shared ProgramData install-state root.'
    Assert-True -Condition ($packageRuntimeText.IndexOf("ProgramData 'chocolatey'",[System.StringComparison]::Ordinal) -ge 0) -Message 'Chocolatey status must read the Chocolatey ProgramData root.'
    Assert-True -Condition ($packageRuntimeText -notlike '*C:\PackageData\clagnos\state\store-installs*') -Message 'Package status must not use the obsolete PackageData store-state root.'

    $windscribe = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\windscribe\package.json') -Raw) -ErrorAction Stop
    $vsCode = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\visual-studio-code\package.json') -Raw) -ErrorAction Stop
    Assert-True -Condition ([string]$windscribe.statusCheck.value -eq 'Windscribe.Windscribe') -Message 'Windscribe status must use the canonical winget package id.'
    Assert-True -Condition ([string]$vsCode.statusCheck.kind -eq 'command' -and [string]$vsCode.statusCheck.value -eq 'code') -Message 'VS Code status must use the installed command rather than a winget alias.'
}

Invoke-Test -Name "Unlocker setup skips an unavailable package and Windows UX respects its machine-policy privilege boundary" -Action {
    $unlockerPath = Join-Path $RepoRoot 'windows\update\110-configure-unlocker-settings\110-configure-unlocker-settings.ps1'
    $unlockerText = [string](Get-Content -LiteralPath $unlockerPath -Raw -ErrorAction Stop)
    Assert-True -Condition ($unlockerText -like '*unlocker-settings-skip => IObit Unlocker is not installed*') -Message 'Unlocker settings task must skip cleanly when its optional package is absent.'
    Assert-True -Condition ($unlockerText -notlike '*choco install io-unlocker*') -Message 'Unlocker settings must not invoke the outdated checksum-mismatched Chocolatey installer.'

    $experiencePath = Join-Path $RepoRoot 'windows\update\10004-configure-windows-experience\10004-configure-windows-experience.ps1'
    $experienceText = [string](Get-Content -LiteralPath $experiencePath -Raw -ErrorAction Stop)
    Assert-True -Condition ($experienceText -like '*-SkipMachineDshPolicy*') -Message 'Interactive UX worker must defer the machine DSH policy write.'
    Assert-True -Condition ($experienceText -like '*ux-worker-machine-policy-verification-deferred => Microsoft.Dsh.AllowNewsAndInterests*') -Message 'Interactive UX worker must also defer machine DSH policy readback.'
    Assert-True -Condition ($experienceText.Contains('New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $taskIdentity') -and $experienceText.Contains('IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)')) -Message 'Windows UX task must check its administrator token before writing the DSH machine policy.'
    Assert-True -Condition ($experienceText -like '*Doing: skip optional machine policy Microsoft.Dsh.AllowNewsAndInterests; task identity has no administrator token*') -Message 'Windows UX task must gracefully skip its optional machine policy when the task identity is not an administrator.'
    Assert-True -Condition ($experienceText -like '*Start-Process -FilePath $regExecutable*') -Message 'Windows UX task must capture reg.exe output without converting access-denied status into a PowerShell warning.'
    Assert-True -Condition ($experienceText -like '*Doing: skip optional machine policy Microsoft.Dsh.AllowNewsAndInterests; registry access is denied*') -Message 'Windows UX task must gracefully skip the optional machine policy when registry ACLs deny access.'
    Assert-True -Condition ($experienceText -like '*Doing: verified machine policy Microsoft.Dsh.AllowNewsAndInterests=0*') -Message 'Windows UX task must verify the DSH policy when the registry write succeeds.'
}

Invoke-Test -Name "CLI parse help contracts" -Action {
    $parsedGlobalHelp = Parse-ClagnosCliArguments -CommandToken "--help" -RawArgs @()
    Assert-True -Condition ([string]$parsedGlobalHelp.Command -eq "help") -Message "Global --help should resolve to help command."
    Assert-True -Condition ([string]$parsedGlobalHelp.HelpTopic -eq "__overview__") -Message "Global --help should resolve to overview help."

    $parsedGlobalShortHelp = Parse-ClagnosCliArguments -CommandToken "-h" -RawArgs @()
    Assert-True -Condition ([string]$parsedGlobalShortHelp.Command -eq "help") -Message "Global -h should resolve to help command."
    Assert-True -Condition ([string]$parsedGlobalShortHelp.HelpTopic -eq "__overview__") -Message "Global -h should resolve to overview help."

    $parsedHelpTopic = Parse-ClagnosCliArguments -CommandToken "help" -RawArgs @("create")
    Assert-True -Condition ([string]$parsedHelpTopic.Command -eq "help") -Message "help command parse failed."
    Assert-True -Condition ([string]$parsedHelpTopic.HelpTopic -eq "create") -Message "Help topic positional parse failed."

    $parsedHelpShortFlag = Parse-ClagnosCliArguments -CommandToken "help" -RawArgs @("-h")
    Assert-True -Condition ([string]$parsedHelpShortFlag.Command -eq "help") -Message "help -h parse failed."
    Assert-True -Condition ([string]$parsedHelpShortFlag.HelpTopic -eq "") -Message "help -h should keep detailed-catalog behavior."

    $parsedDoTopic = Parse-ClagnosCliArguments -CommandToken "help" -RawArgs @("do")
    Assert-True -Condition ([string]$parsedDoTopic.Command -eq "help") -Message "help do parse failed."
    Assert-True -Condition ([string]$parsedDoTopic.HelpTopic -eq "do") -Message "Help topic parse failed for do."

    $parsedCommandHelp = Parse-ClagnosCliArguments -CommandToken "create" -RawArgs @("--help")
    Assert-True -Condition ([string]$parsedCommandHelp.Command -eq "create") -Message "Command with --help parse failed."
    Assert-True -Condition ($parsedCommandHelp.Options.ContainsKey("help")) -Message "Command --help option was not captured."

    $parsedCommandShortHelp = Parse-ClagnosCliArguments -CommandToken "create" -RawArgs @("-h")
    Assert-True -Condition ([string]$parsedCommandShortHelp.Command -eq "create") -Message "Command with -h parse failed."
    Assert-True -Condition ($parsedCommandShortHelp.Options.ContainsKey("help")) -Message "Command -h option was not captured."

    $parsedConfigureHelp = Parse-ClagnosCliArguments -CommandToken "configure" -RawArgs @("--help")
    Assert-True -Condition ([string]$parsedConfigureHelp.Command -eq "configure") -Message "Configure command with --help parse failed."

    $parsedConfigureShortHelp = Parse-ClagnosCliArguments -CommandToken "configure" -RawArgs @("-h")
    Assert-True -Condition ([string]$parsedConfigureShortHelp.Command -eq "configure") -Message "Configure command with -h parse failed."

    $parsedConnectHelp = Parse-ClagnosCliArguments -CommandToken "connect" -RawArgs @("--help")
    Assert-True -Condition ([string]$parsedConnectHelp.Command -eq "connect") -Message "Connect command with --help parse failed."

    $parsedConnectShortHelp = Parse-ClagnosCliArguments -CommandToken "connect" -RawArgs @("-h")
    Assert-True -Condition ([string]$parsedConnectShortHelp.Command -eq "connect") -Message "Connect command with -h parse failed."

    $parsedConnectSshTest = Parse-ClagnosCliArguments -CommandToken "connect" -RawArgs @("--ssh", "--test")
    Assert-True -Condition ([string]$parsedConnectSshTest.Command -eq "connect") -Message "Connect --ssh parse failed."
    Assert-True -Condition ($parsedConnectSshTest.Options.ContainsKey("ssh")) -Message "Connect --ssh option was not captured."
    Assert-True -Condition ($parsedConnectSshTest.Options.ContainsKey("test")) -Message "Connect --test option was not captured."

    $parsedConnectRdpTest = Parse-ClagnosCliArguments -CommandToken "connect" -RawArgs @("--rdp", "--test")
    Assert-True -Condition ($parsedConnectRdpTest.Options.ContainsKey("rdp")) -Message "Connect --rdp option was not captured."

    $parsedConnectPowerShellCommand = Parse-ClagnosCliArguments -CommandToken 'connect' -RawArgs @('--powershell', '--command', 'Get-Date')
    Assert-True -Condition ($parsedConnectPowerShellCommand.Options.ContainsKey('powershell')) -Message 'Connect --powershell option was not captured.'
    Assert-True -Condition ([string]$parsedConnectPowerShellCommand.Options['command'] -eq 'Get-Date') -Message 'Connect --powershell --command value was not captured.'

    $parsedConnectPowerShellTest = Parse-ClagnosCliArguments -CommandToken 'connect' -RawArgs @('--powershell', '--test')
    Assert-True -Condition ($parsedConnectPowerShellTest.Options.ContainsKey('test')) -Message 'Connect --powershell --test option was not captured.'

    $parsedTaskRunInit = Parse-ClagnosCliArguments -CommandToken "task" -RawArgs @("--run-vm-init", "01")
    Assert-True -Condition ([string]$parsedTaskRunInit.Options['run-vm-init'] -eq '01') -Message "Task --run-vm-init <value> parse failed."

    $parsedTaskRunUpdate = Parse-ClagnosCliArguments -CommandToken "task" -RawArgs @("--run-vm-update=10002")
    Assert-True -Condition ([string]$parsedTaskRunUpdate.Options['run-vm-update'] -eq '10002') -Message "Task --run-vm-update=value parse failed."

    $parsedTaskHistory = Parse-ClagnosCliArguments -CommandToken 'task' -RawArgs @('--history')
    Assert-True -Condition ($parsedTaskHistory.Options.ContainsKey('history')) -Message 'Task --history option was not captured.'

    $parsedExecCommand = Parse-ClagnosCliArguments -CommandToken "exec" -RawArgs @("--command", "Get-Date")
    Assert-True -Condition ([string]$parsedExecCommand.Options['command'] -eq 'Get-Date') -Message "Exec --command <value> parse failed."

    $parsedExecShortCommand = Parse-ClagnosCliArguments -CommandToken "exec" -RawArgs @("-c", "Get-Date")
    Assert-True -Condition ([string]$parsedExecShortCommand.Options['command'] -eq 'Get-Date') -Message "Exec -c <value> parse failed."

    $parsedExecFile = Parse-ClagnosCliArguments -CommandToken "exec" -RawArgs @("--file", ".\\script.ps1")
    Assert-True -Condition ([string]$parsedExecFile.Options['file'] -eq '.\\script.ps1') -Message "Exec --file <value> parse failed."

    $parsedExecQuiet = Parse-ClagnosCliArguments -CommandToken "exec" -RawArgs @("--quiet", "--command", "Get-Date")
    Assert-True -Condition ($parsedExecQuiet.Options.ContainsKey('quiet')) -Message "Exec --quiet option was not captured."
    Assert-True -Condition ([string]$parsedExecQuiet.Options['command'] -eq 'Get-Date') -Message "Exec --quiet must preserve the one-shot command value."

    $parsedDoHelp = Parse-ClagnosCliArguments -CommandToken "do" -RawArgs @("--help")
    Assert-True -Condition ([string]$parsedDoHelp.Command -eq "do") -Message "Do command with --help parse failed."
    Assert-True -Condition ($parsedDoHelp.Options.ContainsKey("help")) -Message "Do command --help option was not captured."

    $parsedDoShortHelp = Parse-ClagnosCliArguments -CommandToken "do" -RawArgs @("-h")
    Assert-True -Condition ([string]$parsedDoShortHelp.Command -eq "do") -Message "Do command with -h parse failed."
    Assert-True -Condition ($parsedDoShortHelp.Options.ContainsKey("help")) -Message "Do command -h option was not captured."

    $parsedResizeHelp = Parse-ClagnosCliArguments -CommandToken "resize" -RawArgs @("--help")
    Assert-True -Condition ([string]$parsedResizeHelp.Command -eq "resize") -Message "Resize command with --help parse failed."
    Assert-True -Condition ($parsedResizeHelp.Options.ContainsKey("help")) -Message "Resize command --help option was not captured."

    $parsedResizeShortHelp = Parse-ClagnosCliArguments -CommandToken "resize" -RawArgs @("-h")
    Assert-True -Condition ([string]$parsedResizeShortHelp.Command -eq "resize") -Message "Resize command with -h parse failed."
    Assert-True -Condition ($parsedResizeShortHelp.Options.ContainsKey("help")) -Message "Resize command -h option was not captured."

    $parsedSubscriptionShort = Parse-ClagnosCliArguments -CommandToken "show" -RawArgs @("-s", "11111111-1111-1111-1111-111111111111")
    Assert-True -Condition ([string]$parsedSubscriptionShort.Command -eq "show") -Message "Subscription short option must preserve the command token."
    Assert-True -Condition ([string]$parsedSubscriptionShort.Options['subscription-id'] -eq '11111111-1111-1111-1111-111111111111') -Message "Short -s must normalize into subscription-id."

    $parsedSubscriptionInline = Parse-ClagnosCliArguments -CommandToken "show" -RawArgs @("-s=22222222-2222-2222-2222-222222222222")
    Assert-True -Condition ([string]$parsedSubscriptionInline.Options['subscription-id'] -eq '22222222-2222-2222-2222-222222222222') -Message "Inline -s=value must normalize into subscription-id."

    $parsedShowJsonExport = Parse-ClagnosCliArguments -CommandToken 'show' -RawArgs @('--export-json', '.\reports\vm.json', '--overwrite')
    Assert-True -Condition ([string]$parsedShowJsonExport.Options['export-json'] -eq '.\reports\vm.json') -Message 'Show --export-json must preserve the selected file path.'
    Assert-True -Condition ($parsedShowJsonExport.Options.ContainsKey('overwrite')) -Message 'Show --overwrite option was not captured.'

    $parsedConnectShortSelectors = Parse-ClagnosCliArguments -CommandToken "connect" -RawArgs @("--ssh", "-g", "rg-samplevm-ate1-g1", "-v", "samplevm", "-s", "33333333-3333-3333-3333-333333333333")
    Assert-True -Condition ([string]$parsedConnectShortSelectors.Options['group'] -eq 'rg-samplevm-ate1-g1') -Message "Short -g must normalize into group."
    Assert-True -Condition ([string]$parsedConnectShortSelectors.Options['vm-name'] -eq 'samplevm') -Message "Short -v must normalize into vm-name."
    Assert-True -Condition ([string]$parsedConnectShortSelectors.Options['subscription-id'] -eq '33333333-3333-3333-3333-333333333333') -Message "Short -s must normalize into subscription-id for connect."

    $parsedResizeDiskSize = Parse-ClagnosCliArguments -CommandToken "resize" -RawArgs @("--group", "rg-samplevm-ate1-g1", "--vm-name", "samplevm", "--disk-size", "196gb", "--expand")
    Assert-True -Condition ([string]$parsedResizeDiskSize.Options['group'] -eq 'rg-samplevm-ate1-g1') -Message "Resize --group <value> parse failed."
    Assert-True -Condition ([string]$parsedResizeDiskSize.Options['vm-name'] -eq 'samplevm') -Message "Resize --vm-name <value> parse failed."
    Assert-True -Condition ([string]$parsedResizeDiskSize.Options['disk-size'] -eq '196gb') -Message "Resize --disk-size <value> parse failed."
    Assert-True -Condition ($parsedResizeDiskSize.Options.ContainsKey('expand')) -Message "Resize --expand option was not captured."
}

Invoke-Test -Name "Azure and guest operations expose safe Doing labels and bounded wait heartbeats" -Action {
    $previousQuietOutput = [bool]$script:ClagnosQuietOutput
    try {
        $script:ClagnosQuietOutput = $true
        Write-ClagnosActionProgress -Action 'quiet-mode progress probe'

        $safeVmLabel = Get-ClagnosAzCliProgressLabel -Arguments @('vm','create','--admin-password','secret-value')
        $safeNetworkLabel = Get-ClagnosAzCliProgressLabel -Arguments @('network','vnet','subnet','create','--name','private-name')
        $stepRunnerText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\runtime\clagnos-step-runner.ps1') -Raw)
        $actionLoggerText = [string]($stepRunnerText -split '# Handles Invoke-Step\.' | Select-Object -First 1)
        $azCliText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\system\clagnos-az-cli.ps1') -Raw)
        $diagnosticsText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\runtime\clagnos-diagnostics.ps1') -Raw)
        $httpRuntimeText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\system\clagnos-az-cli.ps1') -Raw)
        $sshProcessText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\ssh\process.ps1') -Raw)
        $e2eText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'tests\live-vc-e2e.ps1') -Raw)

        Assert-True -Condition ($actionLoggerText.Contains('Write-Host $actionText -ForegroundColor DarkCyan') -and $actionLoggerText -notlike '*ClagnosQuietOutput*') -Message 'The Doing logger must remain visible during explicit quiet output mode.'
        Assert-True -Condition ([string]$safeVmLabel -eq 'az vm create' -and [string]$safeVmLabel -notmatch 'secret-value') -Message 'Azure progress labels must identify the action without exposing argument secrets.'
        Assert-True -Condition ([string]$safeNetworkLabel -eq 'az network vnet subnet create' -and [string]$safeNetworkLabel -notmatch 'private-name') -Message 'Azure network progress labels must identify nested actions without exposing resource values.'
        Assert-True -Condition ($azCliText -like '*still running; {1:N0}s elapsed*') -Message 'Azure CLI calls must emit periodic Doing heartbeats while they run.'
        Assert-True -Condition ($diagnosticsText -like '*still running; {1}s elapsed*') -Message 'Azure REST-backed job waits must emit periodic Doing heartbeats.'
        Assert-True -Condition ($httpRuntimeText -like '*while ($elapsedSeconds -lt $requestTimeoutSeconds)*' -and $httpRuntimeText -like '*HTTP {0} request ({1}) is still running*') -Message 'Direct Azure HTTP requests must have a bounded timeout and periodic Doing heartbeats.'
        Assert-True -Condition ($sshProcessText.Contains("ProgressLabel = 'guest process'") -and $sshProcessText -like '*Write-ClagnosActionProgress -Action*') -Message 'Long-running guest SSH processes must emit periodic Doing heartbeats even between output lines.'
        Assert-True -Condition ($e2eText -like '*Write-Host $line*') -Message 'The live E2E wrapper must relay child CLI progress output while a command is running.'
        Assert-True -Condition ($e2eText.Contains('function Get-ClagnosE2eStatusRows') -and $e2eText.Contains('IsNullOrWhiteSpace([string]$row.code)')) -Message 'Live E2E power and hibernation checks must ignore empty root status entries and fall back to instanceView.statuses.'
    }
    finally {
        $script:ClagnosQuietOutput = $previousQuietOutput
    }
}

Invoke-Test -Name "CLI entrypoint keeps a normal banner path and a pre-banner version fast path" -Action {
    $entryText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'clagnos.ps1') -Raw)

    Assert-True -Condition ($entryText -like '*function Get-ClagnosCliVersionInfo*') -Message 'CLI entrypoint must resolve the displayed CLI version info.'
    Assert-True -Condition ($entryText -like '*function Write-ClagnosCliBanner*') -Message 'CLI entrypoint must define the welcome banner writer.'
    Assert-True -Condition ($entryText -like '*CLAGNOS CLI V{0}*') -Message 'CLI entrypoint banner must print the CLAGNOS CLI version header.'
    Assert-True -Condition ($entryText -like '*Provision, update, connect, and maintain managed Windows or Linux Azure VMs from one deterministic CLI.*') -Message 'CLI entrypoint banner must print the first descriptive line.'
    Assert-True -Condition ($entryText -like '*Run lifecycle actions, isolated tasks, app-state save/restore, and SSH or RDP access through one repo-driven workflow.*') -Message 'CLI entrypoint banner must print the second descriptive line.'
    Assert-True -Condition ($entryText -match '(?s)if \(\$MyInvocation\.InvocationName -ne ''\.'' -and \@\(\$preParsedRawArgs\)\.Count -eq 0 .*?Write-Host \("clagnos version \{0\}" -f \(Get-ClagnosCliVersionInfo\)\)\s*return\s*\}.*?# Load modular function files') -Message 'CLI entrypoint must handle --version before module loading and banner output.'
    Assert-True -Condition ($entryText -match '(?s)# Load modular function files.*?if \(\$MyInvocation\.InvocationName -eq ''\.''\) \{\s*return\s*\}\s*Write-ClagnosCliBanner\s*try \{') -Message 'CLI entrypoint must still load modules when dot-sourced and print the banner only for normal command dispatch.'
}

Invoke-Test -Name "Workflow pipeline delegates restarts to task runners and starts vm-summary with readback" -Action {
    $pipelineText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-command.ps1') -Raw)
    $workflowText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-workflow.ps1') -Raw)

    foreach ($stepLabel in @(
        'Step 1/7 - Configuration review',
        'Step 2/7 - Resource group',
        'Step 3/7 - Network',
        'Step 4/7 - VM deploy',
        'Step 5/7 - VM init',
        'Step 6/7 - VM update',
        'Step 7/7 - VM summary'
    )) {
        Assert-True -Condition ($pipelineText -match [regex]::Escape([string]$stepLabel)) -Message ("Pipeline must use the step label '{0}'." -f [string]$stepLabel)
    }

    Assert-True -Condition ($pipelineText -match [regex]::Escape('$vmUpdateStageResult = Invoke-Step ''Step 6/7 - VM update''')) -Message 'Pipeline must capture the vm-update stage result from the shared step wrapper.'
    Assert-True -Condition ($pipelineText -match [regex]::Escape('return (Invoke-ClagnosSshTaskBlocks')) -Message 'VM update step must return the SSH stage result explicitly.'
    Assert-True -Condition ($pipelineText -match [regex]::Escape('-EnableFinalVmRestart')) -Message 'Pipeline vm-update stage must request the final vm-update restart only for end-to-end workflow runs.'
    Assert-True -Condition (-not ($pipelineText -match [regex]::Escape('Invoke-ClagnosWorkflowRestartBarrier'))) -Message 'Pipeline must not keep the retired deferred restart barrier call.'
    Assert-True -Condition (-not ($pipelineText -match [regex]::Escape('-SuppressDeferredRestartHint'))) -Message 'Pipeline must not keep the retired deferred restart hint suppression flag.'
    Assert-True -Condition ($pipelineText -match [regex]::Escape('Invoke-ClagnosWorkflowSummaryReadback')) -Message 'Pipeline summary must invoke the shared summary readback helper.'
    Assert-True -Condition ($workflowText -match [regex]::Escape('function Invoke-ClagnosWorkflowSummaryReadback')) -Message 'Workflow helpers must expose the vm-summary readback helper.'
    Assert-True -Condition ($workflowText -match [regex]::Escape('vm-summary-readback')) -Message 'Workflow summary readback helper must build a dedicated readback task block.'
}

Invoke-Test -Name "Create waits for provisioning recovery before vm-init and extends redeploy timeout" -Action {
    $pipelineText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-command.ps1') -Raw)
    $lifecycleText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\ui\connection\clagnos-lifecycle.ps1') -Raw)

    foreach ($fragment in @(
        'Wait-ClagnosProvisioningReadyOrRepair -ResourceGroup',
        'VM init cannot start while Azure provisioning is still not ready.'
    )) {
        Assert-True -Condition ($pipelineText -like ('*' + [string]$fragment + '*')) -Message ("Pipeline must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds 900',
        'Triggering Azure redeploy repair...'
    )) {
        Assert-True -Condition ($lifecycleText -like ('*' + [string]$fragment + '*')) -Message ("Lifecycle helper must include fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Task restart helper extends Azure restart timeout" -Action {
    $taskRestartText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-task-restart.ps1') -Raw)

    foreach ($fragment in @(
        'Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds 900',
        'az vm restart -g {0} -n {1}',
        'Wait-ClagnosVmPowerState',
        'Wait-ClagnosProvisioningReadyOrRepair'
    )) {
        Assert-True -Condition ($taskRestartText -like ('*' + [string]$fragment + '*')) -Message ("Task restart helper must include fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Isolated vm-update task runs do not request the final vm-update restart" -Action {
    $taskRuntimeText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\task\runtime.ps1') -Raw)
    $sshTaskRunnerText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-ssh-task-runner.ps1') -Raw)

    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('[switch]$EnableFinalVmRestart')) -Message 'SSH task runner must expose an explicit final vm-update restart switch.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('if ($EnableFinalVmRestart -and @($TaskBlocks).Count -gt 0')) -Message 'SSH task runner must gate the final vm-update restart behind the explicit workflow switch.'
    Assert-True -Condition (-not ($taskRuntimeText -match [regex]::Escape('-EnableFinalVmRestart'))) -Message 'Isolated task --run vm-update execution must not request the workflow-only final restart.'
}

Invoke-Test -Name "Shared step wrapper returns the action result to callers" -Action {
    $stepRunnerText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\runtime\clagnos-step-runner.ps1') -Raw)

    Assert-True -Condition ($stepRunnerText -match [regex]::Escape('$stepResult = . $Action')) -Message 'Step wrapper must capture the action result.'
    Assert-True -Condition ($stepRunnerText -match [regex]::Escape('return $stepResult')) -Message 'Step wrapper must return the captured action result.'
}

Invoke-Test -Name "Guest task output relay is enabled for vm-init and vm-update transports" -Action {
    $sshProcessText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\ssh\process.ps1') -Raw)
    $sshSessionText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\ssh\session.ps1') -Raw)
    $sshRunnerText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\ssh\runner.ps1') -Raw)
    $sshTaskRunnerText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-ssh-task-runner.ps1') -Raw)
    $appStatePluginText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-plugin.ps1') -Raw)
    $appStateCaptureText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-capture.ps1') -Raw)
    $runCommandParserText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\run-command\parser.ps1') -Raw)
    $runCommandRunnerText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\run-command\runner.ps1') -Raw)

    Assert-True -Condition ($sshProcessText -match [regex]::Escape('function Invoke-ClagnosStreamingCapturedProcess')) -Message 'SSH process helpers must define the streaming capture path.'
    Assert-True -Condition ($sshProcessText -match [regex]::Escape('Write-Host ([string]$normalizedLine)')) -Message 'Streaming SSH capture must mirror normalized stdout lines live.'
    Assert-True -Condition ($sshProcessText -match [regex]::Escape('Write-Warning ([string]$normalizedLine)')) -Message 'Streaming SSH capture must mirror normalized stderr lines live.'
    Assert-True -Condition ($sshProcessText -match [regex]::Escape('Normalize-ClagnosProtocolLine -Text $lineText')) -Message 'Streaming SSH capture must normalize protocol-prefixed task output before relaying it.'
    Assert-True -Condition ($sshProcessText -match [regex]::Escape('Test-ClagnosTaskOutputNoiseLine -Text ([string]$normalizedLine)')) -Message 'Streaming SSH capture must suppress known task-output noise before relaying it.'
    Assert-True -Condition ($sshProcessText -match [regex]::Escape('[switch]$RelayOutput')) -Message 'SSH process retry helper must accept live output relay.'
    Assert-True -Condition ($sshSessionText -match [regex]::Escape('-RelayOutput')) -Message 'One-shot SSH task execution must enable live output relay.'
    Assert-True -Condition ($sshRunnerText -match [regex]::Escape('OutputRelayedLive = $true')) -Message 'Persistent SSH task execution must mark output as already relayed.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('$warningTasks = @()')) -Message 'SSH task runner must track warning tasks separately from hard failures.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('Warning tasks:')) -Message 'SSH task runner must summarize warning tasks explicitly.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('Test-ClagnosTaskOutputNoiseLine -Text ([string]$line)')) -Message 'SSH task runner must exclude known noise lines from warning-signal counting.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('WarningTasks = @($uniqueWarningTasks)')) -Message 'SSH task runner result contract must expose warning task names.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape("requested a restart. Restarting VM now")) -Message 'SSH task runner must restart immediately after reboot-signaling update tasks.'
    Assert-True -Condition ($sshTaskRunnerText -match [regex]::Escape('Running the final VM restart before vm-summary')) -Message 'SSH task runner must still support the workflow final vm-update restart.'
    Assert-True -Condition ($runCommandRunnerText -match [regex]::Escape("requested a restart. Restarting VM now")) -Message 'Run-command task runner must restart immediately after reboot-signaling init tasks.'
    Assert-True -Condition ($appStatePluginText -match [regex]::Escape('OutputRelayedLive')) -Message 'App-state replay must avoid re-printing live-relayed task output.'
    Assert-True -Condition ($appStateCaptureText -match [regex]::Escape('OutputRelayedLive')) -Message 'App-state capture must avoid re-printing live-relayed task output.'
    Assert-True -Condition ($runCommandParserText -match [regex]::Escape('function Get-ClagnosRunCommandResultEnvelope')) -Message 'Run-command parsing must expose a non-throwing envelope helper.'
    Assert-True -Condition ($runCommandRunnerText -match [regex]::Escape('Get-ClagnosRunCommandResultEnvelope')) -Message 'Run-command task runner must consume the envelope helper.'
    Assert-True -Condition ($runCommandRunnerText -match [regex]::Escape('Guest output relay:')) -Message 'Run-command task runner must label relayed guest output.'
    Assert-True -Condition ($runCommandRunnerText.Contains('Write-ClagnosActionProgress -Action') -and $runCommandRunnerText.Contains('run guest task') -and $runCommandRunnerText.Contains('with Azure Run Command')) -Message 'Run-command task runner must announce task start through the Doing progress logger.'
    Assert-True -Condition ($runCommandRunnerText -match [regex]::Escape('Task completed:')) -Message 'Run-command task runner must announce task completion.'
}

Invoke-Test -Name "CLI entrypoint keeps raw token parsing compatible with exec command flags" -Action {
    $entryText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'clagnos.ps1') -Raw)
    $expectedReinjectLine = '$rawArgs = @(''-c'', [string]$PassthroughShortCommand) + @($rawArgs)'
    $expectedPreparsedReinjectLine = '$preParsedRawArgs = @(''-c'', [string]$PassthroughShortCommand) + @($preParsedRawArgs)'

    Assert-True -Condition ($entryText -like '*[CmdletBinding(PositionalBinding = $false)]*') -Message 'CLI entrypoint must disable positional binding so command tokens remain in the raw CLI stream.'
    Assert-True -Condition ($entryText -like '*[string[]]$CliTokens*') -Message 'CLI entrypoint must keep one raw token array parameter.'
    Assert-True -Condition ($entryText -like '*[Alias(''c'')]*') -Message 'CLI entrypoint must reserve the short -c token so PowerShell does not reject exec -c at the script boundary.'
    Assert-True -Condition ($entryText -like '*ValueFromRemainingArguments = $true*') -Message 'CLI entrypoint must capture the full raw token stream.'
    Assert-True -Condition (-not ($entryText -like '*[string]$Command*')) -Message 'CLI entrypoint must not expose a top-level Command parameter that collides with exec --command.'
    $commandTokenPatterns = @(
        '$commandToken = [string]$CliTokens[0]',
        '$preParsedCommandToken = [string]$CliTokens[0]'
    )
    Assert-True -Condition ((@($commandTokenPatterns | Where-Object { $entryText -match [regex]::Escape([string]$_) }).Count) -gt 0) -Message 'CLI entrypoint must derive the command token from the raw token stream.'
    Assert-True -Condition (($entryText -match [regex]::Escape($expectedReinjectLine)) -or ($entryText -match [regex]::Escape($expectedPreparsedReinjectLine))) -Message 'CLI entrypoint must re-inject the captured short -c option into the raw CLI argument stream.'
    Assert-True -Condition ($entryText -like '*$parsedCli = Parse-ClagnosCliArguments -CommandToken $commandToken -RawArgs $rawArgs*') -Message 'CLI entrypoint must parse CLI options from the reconstructed raw argument stream.'
}

Invoke-Test -Name "Task folder defaults" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-task-folder-defaults-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try {
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '01-initial-default' -Platform windows -ScriptText "Write-Host 'task01'" -TaskJson @{}
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '101-normal-default' -Platform windows -ScriptText "Write-Host 'task101'" -TaskJson @{ enabled = $true }

        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update
        $active = @($catalog.ActiveTasks)
        Assert-True -Condition ($active.Count -eq 2) -Message "Expected 2 active tasks."
        Assert-True -Condition ([string]$active[0].Name -eq "01-initial-default") -Message "Initial tracked task must keep its initial-band order."
        Assert-True -Condition ([string]$active[1].Name -eq "101-normal-default") -Message "Normal tracked task must keep its normal-band order."

        $initialTask = $active | Where-Object { [string]$_.Name -eq "01-initial-default" } | Select-Object -First 1
        $normalTask = $active | Where-Object { [string]$_.Name -eq "101-normal-default" } | Select-Object -First 1
        Assert-True -Condition ([int]$initialTask.Priority -eq 1) -Message "Missing task.json priority must default to the task number."
        Assert-True -Condition ([int]$normalTask.Priority -eq 101) -Message "Tracked task priority must default to the task number when task.json omits it."
        Assert-True -Condition ([int]$initialTask.TimeoutSeconds -eq 180) -Message "Missing task.json timeout must default to 180."
        Assert-True -Condition ([int]$normalTask.TimeoutSeconds -eq 180) -Message "Missing task.json timeout must default to 180."
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "CLI option assertions allow command help" -Action {
    Assert-ClagnosCommandOptions -CommandName "create" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "update" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "configure" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "list" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "show" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "do" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "task" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "move" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "resize" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "set" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "exec" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "connect" -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName "delete" -Options @{ help = $true }
}

Invoke-Test -Name "Connect command accepts SSH, RDP, and PowerShell remoting modes" -Action {
    Assert-ClagnosCommandOptions -CommandName "connect" -Options @{ ssh = $true; test = $true }
    Assert-ClagnosCommandOptions -CommandName "connect" -Options @{ ssh = $true; 'vm-name' = 'samplevm'; user = 'manager'; test = $true }
    Assert-ClagnosCommandOptions -CommandName "connect" -Options @{ rdp = $true; test = $true }
    Assert-ClagnosCommandOptions -CommandName "connect" -Options @{ rdp = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; user = 'assistant'; test = $true }
    Assert-ClagnosCommandOptions -CommandName 'connect' -Options @{ powershell = $true; test = $true }
    Assert-ClagnosCommandOptions -CommandName 'connect' -Options @{ powershell = $true; command = 'Get-Date'; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; user = 'manager' }
}

Invoke-Test -Name "Create and update accept vm-name override" -Action {
    Assert-ClagnosCommandOptions -CommandName 'create' -Options @{ 'vm-name' = 'samplevm'; auto = $true }
    Assert-ClagnosCommandOptions -CommandName 'update' -Options @{ 'vm-name' = 'samplevm'; auto = $true }
}

Invoke-Test -Name "Configure and list accept the current option contract" -Action {
    Assert-ClagnosCommandOptions -CommandName 'configure' -Options @{ perf = $true }
    Assert-ClagnosCommandOptions -CommandName 'configure' -Options @{ help = $true }
    Assert-ClagnosCommandOptions -CommandName 'list' -Options @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
    Assert-ClagnosCommandOptions -CommandName 'list' -Options @{ type = 'group,vm'; 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
    Assert-ClagnosCommandOptions -CommandName 'list' -Options @{ type = 'nsg,nsg-rule'; group = 'rg-samplevm-ate1-g1'; 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
    Assert-ClagnosCommandOptions -CommandName 'show' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
    Assert-ClagnosCommandOptions -CommandName 'show' -Options @{ 'export-json' = 'report.json' }
    Assert-ClagnosCommandOptions -CommandName 'show' -Options @{ 'export-json' = 'report.json'; overwrite = $true }
}

Invoke-Test -Name "Interactive Clagnos CLI exposes the complete command surface" -Action {
    $expectedCommands = @('configure','create','initialize','update','list','show','do','task','package','component','connect','move','resize','set','exec','delete','help')
    $actualCommands = @(Get-ClagnosValidCommandList)
    foreach ($command in @($expectedCommands)) {
        Assert-True -Condition ($actualCommands -contains $command) -Message ("Public command '{0}' must be registered." -f $command)
    }

    Assert-ClagnosCommandOptions -CommandName 'initialize' -Options @{ auto = $true; windows = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
    Assert-ClagnosCommandOptions -CommandName 'package' -Options @{ action = 'install'; package = 'git'; catalog = 'builtin'; windows = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
    Assert-ClagnosCommandOptions -CommandName 'package' -Options @{ action = 'uninstall'; package = 'git'; catalog = 'builtin'; yes = $true; windows = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
    Assert-ClagnosCommandOptions -CommandName 'package' -Options @{ action = 'disable'; package = 'my-tool'; catalog = 'custom'; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'component' -Options @{ action = 'list'; type = 'disk'; group = 'rg-samplevm-ate1-g1' }
    Assert-ClagnosCommandOptions -CommandName 'component' -Options @{ action = 'attach'; type = 'nic'; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ enable = $true; 'vm-update-task' = '115'; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ disable = $true; 'vm-update-task' = '115'; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ 'save-app-state' = $true; package = 'visual-studio-code'; 'package-catalog' = 'builtin'; windows = $true }
    Assert-True -Condition ((Resolve-ClagnosTaskCommandMode -Options @{ enable = $true }) -eq 'enable') -Message 'Task enable must resolve as a distinct task availability action.'
    Assert-True -Condition ((Resolve-ClagnosTaskCommandMode -Options @{ disable = $true }) -eq 'disable') -Message 'Task disable must resolve as a distinct task availability action.'

    $builtinPackages = @(Get-ClagnosPackageCatalog -Platform 'windows' -Catalog 'builtin')
    $packageRuntime = Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\package\runtime.ps1') -Raw
    Assert-True -Condition ($builtinPackages.Count -ge 36) -Message 'Builtin package folders must be discoverable outside task-stage directories.'
    Assert-True -Condition (@($builtinPackages | Where-Object { $_.Catalog -ne 'builtin' -or [string]::IsNullOrWhiteSpace([string]$_.DisplayName) -or $null -eq $_.StatusCheck -or $null -eq $_.Uninstall }).Count -eq 0) -Message 'Builtin package rows must carry their catalog label and validated package metadata.'
    Assert-True -Condition (@($builtinPackages | Where-Object { -not (Test-Path -LiteralPath (Join-Path $_.DirectoryPath 'package.json')) -or -not (Test-Path -LiteralPath $_.PackageTask.Path) }).Count -eq 0) -Message 'Every package entry must resolve to its package.json and installer script.'
    Assert-True -Condition ($packageRuntime -match [regex]::Escape("Join-Path 'packages' (Join-Path `$Catalog `$Platform)")) -Message 'Builtin and custom packages must resolve under separate physical catalog roots.'
    Assert-True -Condition ($packageRuntime -match [regex]::Escape("if (`$Action -eq 'install' -and -not [bool]`$package.Enabled)")) -Message 'Disabled packages must be rejected before install/update target resolution.'
    Assert-True -Condition ($packageRuntime -match [regex]::Escape("Move-Item -LiteralPath `$tempPath -Destination `$ManifestPath -Force")) -Message 'Package enable/disable must atomically update only package.json.'
    $updateInventory = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath (Join-Path $RepoRoot 'windows\update') -Platform windows -Stage update -SuppressSkipMessages
    Assert-True -Condition (@($updateInventory.InventoryTasks).Count -gt 0) -Message 'The update task catalog must remain independently discoverable after packages are moved out.'
    Assert-True -Condition (@($updateInventory.InventoryTasks | Where-Object { $_.Name -eq '01-install-choco-tool' -or $_.Name -eq '03-install-chrome-application' }).Count -eq 0) -Message 'Builtin package installers must no longer appear as vm-update tasks.'
    Assert-True -Condition ((@(Get-ClagnosComponentTypeIds) -join ',') -eq 'group,vm,disk,vnet,subnet,nic,ip,nsg,nsg-rule') -Message 'The component catalog must expose all managed VC resource types.'

    $uiPath = Join-Path $RepoRoot 'scripts\clagnos-cli.ps1'
    $pagedPickerPath = Join-Path $RepoRoot 'modules\ui\selection\clagnos-paged-picker.ps1'
    $launcherPath = Join-Path $RepoRoot 'cg.cmd'
    $uiText = Get-Content -LiteralPath $uiPath -Raw
    $pagedPickerText = Get-Content -LiteralPath $pagedPickerPath -Raw
    $launcherText = Get-Content -LiteralPath $launcherPath -Raw
    Assert-True -Condition ($launcherText -match [regex]::Escape('scripts\clagnos-cli.ps1')) -Message 'cg.cmd must launch scripts/clagnos-cli.ps1.'
    Assert-True -Condition ($uiText -match [regex]::Escape('one tool for all common cloud operations')) -Message 'The welcome screen must show the requested one-line product description.'
    foreach ($menuRoute in @("'create'", "'initialize'", "'update'", "'package'", "'component'", "'connect'", "'move'", "'resize'", "'set'", "'exec'", "'task'", "'show'", "'list'", "'delete'", "'configure'", "'help'")) {
        Assert-True -Condition ($uiText.Contains($menuRoute)) -Message ("The interactive UI must expose route {0}." -f $menuRoute)
    }
    foreach ($menuLabel in @('2. Managed resource inventory','3. Cloud subscriptions','p: manage programs','1. Builtin package catalog','2. Custom package catalog','[builtin]','[custom]','i: initialize VC','u: update VC','m: manage VC components','d: delete VC and its resources','q: exit','s: show properties','a: attach','t: detach','6. List disabled tasks','7. Enable/disable a task','e: enable package','d: disable package','u: uninstall','i: install or update','s: status','a: manage package app-state',' (disabled)','1. Change VM size','2. Expand OS disk','3. Show safe shrink guidance','VM action number','Clagnos selected:','Azure CLI active:')) {
        Assert-True -Condition ($uiText.Contains($menuLabel)) -Message ("The VC menu must expose '{0}'." -f $menuLabel)
    }
    Assert-True -Condition ($uiText -match [regex]::Escape('Get-ClagnosUiCachedInventoryRows -TypeName')) -Message 'The inventory submenu must render managed inventory from the validated snapshot.'
    Assert-True -Condition ($uiText -match [regex]::Escape("@('vm','list','--show-details')")) -Message 'Startup inventory must cache VM details and power state.'
    Assert-True -Condition ($uiText -match [regex]::Escape('ClagnosUiInventoryValidationSeconds = 60')) -Message 'Inventory cache freshness must have an explicit bounded validation interval.'
    Assert-True -Condition ($pagedPickerText -match [regex]::Escape('p: previous page | n: next page | g: go to page | f: first page | t: last page')) -Message 'Numbered pickers must expose page navigation instead of arrow-key selection.'
    Assert-True -Condition ($uiText -match [regex]::Escape('1MB, 128GB, or 1TB')) -Message 'The create wizard must document and validate disk-size text units.'
    Assert-True -Condition ($uiText -match [regex]::Escape('22,80,443,3000-3300')) -Message 'The create wizard must accept and validate comma-separated TCP ranges.'
    Assert-True -Condition ($uiText -match [regex]::Escape("'s' { 'show' }")) -Message 'The component submenu must expose property details for the selected resource.'
    Assert-True -Condition ($uiText -match [regex]::Escape('az account set --subscription')) -Message 'Cloud subscription selection must update the Azure CLI active subscription.'
    Assert-True -Condition ($uiText -match [regex]::Escape('Save-ClagnosSubscriptionIdToDotEnv')) -Message 'Cloud subscription selection must persist the Clagnos default subscription.'
    Assert-True -Condition ($uiText -match [regex]::Escape('az account list --all --refresh')) -Message 'Cloud subscriptions must refresh and list all Azure CLI subscriptions.'
    Assert-True -Condition ($pagedPickerText -match [regex]::Escape('This option is not available for the active subscription or selected context.')) -Message 'Cloud subscriptions must prevent selecting a disabled subscription.'
}

Invoke-Test -Name "Azure-touching commands accept subscription-id and local-only commands reject it" -Action {
    $commandOptionCases = @(
        @{ Command = 'create'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'update'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'list'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'show'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'do'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'move'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'resize'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'set'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'exec'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'connect'; Options = @{ ssh = $true; 'subscription-id' = '11111111-1111-1111-1111-111111111111' } },
        @{ Command = 'delete'; Options = @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111'; target = 'vm' } }
    )
    foreach ($case in @($commandOptionCases)) {
        Assert-ClagnosCommandOptions -CommandName ([string]$case.Command) -Options ([hashtable]$case.Options)
    }

    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ 'run-vm-update' = '10002'; 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ 'save-app-state' = $true; 'vm-update-task' = '115'; 'subscription-id' = '11111111-1111-1111-1111-111111111111' }

    $taskListSubscriptionThrew = $false
    try {
        Assert-ClagnosTaskCommandOptionScope -Mode 'list' -Options @{ list = $true; 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
    }
    catch {
        $taskListSubscriptionThrew = $true
    }
    Assert-True -Condition $taskListSubscriptionThrew -Message "Task --list must reject subscription-id."

    foreach ($commandName in @('help','configure')) {
        $threw = $false
        try {
            Assert-ClagnosCommandOptions -CommandName $commandName -Options $subscriptionOptions
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Command '{0}' must reject subscription-id." -f [string]$commandName)
    }
}

Invoke-Test -Name "Configure rejects retired targeting flags with interactive editor guidance" -Action {
    foreach ($optionName in @('group','vm-name','windows','linux','subscription-id','auto')) {
        $threw = $false
        try {
            $options = @{}
            switch ([string]$optionName) {
                'group' { $options[$optionName] = 'rg-samplevm-ate1-g1' }
                'vm-name' { $options[$optionName] = 'samplevm' }
                'subscription-id' { $options[$optionName] = '11111111-1111-1111-1111-111111111111' }
                default { $options[$optionName] = $true }
            }
            Assert-ClagnosCommandOptions -CommandName 'configure' -Options $options
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like "*Option '--$optionName' is no longer supported for 'configure'.*") -Message ("Configure rejection for '{0}' must identify the retired configure flag cleanly." -f [string]$optionName)
        }
        Assert-True -Condition $threw -Message ("Configure must reject retired option '{0}'." -f [string]$optionName)
    }
}

Invoke-Test -Name "Configure field schema covers supported dotenv keys and picker-backed multi-option fields" -Action {
    $schema = @(Get-ClagnosConfigureFieldSchema -SelectedPlatform 'windows')
    $schemaKeys = @($schema | ForEach-Object { [string]$_.Key } | Sort-Object -Unique)
    $supportedKeys = @(Get-ClagnosSupportedDotEnvKeys | Sort-Object -Unique)
    Assert-True -Condition (($supportedKeys -join '|') -eq ($schemaKeys -join '|')) -Message 'Configure field schema must cover every supported dotenv key exactly once.'

    foreach ($pickerKind in @(
        'vm-os-picker',
        'resource-group-picker',
        'subscription-picker',
        'region-picker',
        'storage-sku-picker',
        'security-type-picker',
        'toggle-picker',
        'vm-image-picker',
        'vm-size-picker',
        'task-dir-picker',
        'task-outcome-picker',
        'pyssh-path-picker',
        'tcp-ports-picker'
    )) {
        Assert-True -Condition (@($schema | Where-Object { [string]$_.EditorKind -eq [string]$pickerKind }).Count -gt 0) -Message ("Configure schema must include picker kind '{0}'." -f [string]$pickerKind)
    }

    Assert-True -Condition (-not (Test-ClagnosAzureTouchingCommand -CommandName 'configure')) -Message 'Configure must not be treated as an Azure-touching command.'
    Assert-True -Condition (Test-ClagnosAzureTouchingCommand -CommandName 'show') -Message 'Show must remain an Azure-touching command.'
}

Invoke-Test -Name "Configure choice picker rejects stale current values and supports filter plus clear" -Action {
    try {
        $script:ConfigurePickerResponses = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($response in @('', 'f', 'beta', '1')) {
            $script:ConfigurePickerResponses.Enqueue([string]$response)
        }

        function Read-Host {
            param([string]$Prompt)
            if ($script:ConfigurePickerResponses.Count -le 0) {
                throw "No queued Read-Host response remained for prompt '$Prompt'."
            }
            return [string]$script:ConfigurePickerResponses.Dequeue()
        }

        $rows = @(
            [pscustomobject]@{ Value = 'alpha'; Label = 'alpha'; Description = 'First option' }
            [pscustomobject]@{ Value = 'beta'; Label = 'beta'; Description = 'Second option' }
        )

        $selected = Select-ClagnosConfigureChoiceInteractive -Title 'Sample picker' -Rows $rows -CurrentValue 'stale'
        Assert-True -Condition ([string]$selected -eq 'beta') -Message 'Configure choice picker must not keep a stale current value when Enter is pressed.'

        $script:ConfigurePickerResponses = New-Object 'System.Collections.Generic.Queue[string]'
        $script:ConfigurePickerResponses.Enqueue('c')
        $cleared = Select-ClagnosConfigureChoiceInteractive -Title 'Sample picker' -Rows $rows -CurrentValue 'alpha' -AllowEmptySelection
        Assert-True -Condition ([string]::IsNullOrWhiteSpace([string]$cleared)) -Message 'Configure choice picker must support clearing blank-permitted values.'
    }
    finally {
        Remove-Item Function:\global:Read-Host -ErrorAction SilentlyContinue
        Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
        Remove-Variable -Name ConfigurePickerResponses -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Configure managed resource group picker clears when the managed list is empty" -Action {
    $field = [pscustomobject]@{
        Key = 'SELECTED_RESOURCE_GROUP'
        Label = 'Selected resource group'
        EditorKind = 'resource-group-picker'
        AzureBacked = $true
        Secret = $false
    }

    try {
        function Get-ClagnosManagedResourceGroupRows { return @() }

        $state = @{
            RepoRoot = $RepoRoot
            Values = @{ SELECTED_RESOURCE_GROUP = 'rg-stale-ate1-g1' }
            Azure = @{ Available = $true; Hint = ''; SubscriptionRows = @() }
        }

        $selectedGroup = Edit-ClagnosConfigureField -Field $field -State $state
        Assert-True -Condition ([string]::IsNullOrWhiteSpace([string]$selectedGroup)) -Message 'Configure must clear SELECTED_RESOURCE_GROUP when no managed resource groups exist.'
    }
    finally {
        Remove-Item Function:\global:Get-ClagnosManagedResourceGroupRows -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ClagnosManagedResourceGroupRows -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Configure managed resource group picker forces reselection when the current group is stale" -Action {
    $field = [pscustomobject]@{
        Key = 'SELECTED_RESOURCE_GROUP'
        Label = 'Selected resource group'
        EditorKind = 'resource-group-picker'
        AzureBacked = $true
        Secret = $false
    }

    try {
        $script:ConfigureRgResponses = New-Object 'System.Collections.Generic.Queue[string]'
        foreach ($response in @('', 'f', 'ate1', '1')) {
            $script:ConfigureRgResponses.Enqueue([string]$response)
        }

        function Read-Host {
            param([string]$Prompt)
            if ($script:ConfigureRgResponses.Count -le 0) {
                throw "No queued Read-Host response remained for prompt '$Prompt'."
            }
            return [string]$script:ConfigureRgResponses.Dequeue()
        }

        function Get-ClagnosManagedResourceGroupRows {
            return @(
                [pscustomobject]@{ name = 'rg-samplevm-ate1-g2'; location = 'austriaeast'; id = '/subscriptions/example/resourceGroups/rg-samplevm-ate1-g2' }
                [pscustomobject]@{ name = 'rg-samplevm-cin1-g3'; location = 'centralindia'; id = '/subscriptions/example/resourceGroups/rg-samplevm-cin1-g3' }
            )
        }

        $state = @{
            RepoRoot = $RepoRoot
            Values = @{ SELECTED_RESOURCE_GROUP = 'rg-samplevm-ate1-g1' }
            Azure = @{ Available = $true; Hint = ''; SubscriptionRows = @() }
        }

        $selectedGroup = Edit-ClagnosConfigureField -Field $field -State $state
        Assert-True -Condition ([string]$selectedGroup -eq 'rg-samplevm-ate1-g2') -Message 'Configure must force the operator to choose a real managed resource group when the current value is stale.'
    }
    finally {
        Remove-Item Function:\global:Read-Host -ErrorAction SilentlyContinue
        Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Get-ClagnosManagedResourceGroupRows -ErrorAction SilentlyContinue
        Remove-Item Function:\Get-ClagnosManagedResourceGroupRows -ErrorAction SilentlyContinue
        Remove-Variable -Name ConfigureRgResponses -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Configure save readiness blocks unresolved create-critical values but ignores blank resource-group defaults" -Action {
    $baseValues = @{
        SELECTED_VM_OS = 'windows'
        SELECTED_VM_NAME = 'samplevm'
        SELECTED_RESOURCE_GROUP = ''
        SELECTED_AZURE_SUBSCRIPTION_ID = ''
        SELECTED_AZURE_REGION = 'austriaeast'
        WIN_VM_IMAGE = 'publisher:offer:sku:latest'
        WIN_VM_SIZE = 'Standard_B4as_v2'
        VM_ADMIN_USER = 'manager'
        VM_ADMIN_PASS = 'secret-value'
        VM_ASSISTANT_USER = 'assistant'
        VM_ASSISTANT_PASS = 'secret-value'
    }

    try {
        $blockedState = @{
            RepoRoot = $RepoRoot
            Values = $baseValues.Clone()
            Azure = @{ Available = $false; Hint = 'Run az login to edit or verify this field.' }
        }

        $threw = $false
        try {
            Assert-ClagnosConfigureSaveReady -State $blockedState
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Data['Summary'] -eq 'Configure cannot save until all create-critical values are valid.') -Message 'Configure save gating must identify unresolved create-critical values.'
            Assert-True -Condition ([string]$_.Exception.Message -notlike '*SELECTED_RESOURCE_GROUP*') -Message 'Blank SELECTED_RESOURCE_GROUP must not block configure save readiness.'
        }
        Assert-True -Condition $threw -Message 'Configure save readiness must block unresolved Azure-backed create-critical values.'

        function Assert-LocationExists { param([string]$Location) }
        function Assert-VmSkuAvailableViaRest { param([string]$Location, [string]$VmSize) }
        function Assert-VmImageAvailable { param([string]$Location, [string]$ImageUrn) }

        $readyState = @{
            RepoRoot = $RepoRoot
            Values = $baseValues.Clone()
            Azure = @{ Available = $true; Hint = '' }
        }

        Assert-ClagnosConfigureSaveReady -State $readyState
    }
    finally {
        foreach ($functionName in @('Assert-LocationExists','Assert-VmSkuAvailableViaRest','Assert-VmImageAvailable')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "SKU precheck rejects subscription-restricted sizes before VM mutation" -Action {
    $script:SkuPrecheckCalls = @()
    $script:SkuPrecheckAvailable = $true
    try {
        function az {
            $commandLine = @($args | ForEach-Object { [string]$_ }) -join ' '
            $script:SkuPrecheckCalls += $commandLine
            $global:LASTEXITCODE = 0
            if ($commandLine -like 'account show*') { return 'subscription-fixture' }
            if ($commandLine -like 'rest*') { return 'Standard_B2ls_v2' }
            if ($commandLine -like 'vm list-skus*') {
                if ([bool]$script:SkuPrecheckAvailable) { return '[{"name":"Standard_B2ls_v2"}]' }
                return '[]'
            }
            return ''
        }

        Assert-VmSkuAvailableViaRest -Location 'eastus' -VmSize 'Standard_B2ls_v2'
        Assert-True -Condition (@($script:SkuPrecheckCalls | Where-Object { $_ -like 'vm list-skus*' }).Count -eq 1) -Message 'SKU validation must query the active-subscription-aware Azure VM SKU list.'

        $script:SkuPrecheckAvailable = $false
        $threw = $false
        try {
            Assert-VmSkuAvailableViaRest -Location 'eastus' -VmSize 'Standard_B2ls_v2'
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Data['Summary'] -eq 'The VM size is not available to the active Azure subscription.') -Message 'A subscription-restricted SKU must fail with a clear availability error.'
            Assert-True -Condition ([string]$_.Exception.Data['Hint'] -like '*has not been deallocated*') -Message 'The restricted-SKU guidance must state that resize did not deallocate the target.'
        }
        Assert-True -Condition $threw -Message 'A SKU absent from the active-subscription list must be rejected before resize can deallocate a VM.'
        Assert-True -Condition (@($script:SkuPrecheckCalls | Where-Object { $_ -match '(?i)\bdeallocate\b|\bresize\b|\bstart\b' }).Count -eq 0) -Message 'The SKU availability precheck must not attempt VM lifecycle mutations.'
    }
    finally {
        Remove-Item Function:\global:az -ErrorAction SilentlyContinue
        Remove-Item Function:\az -ErrorAction SilentlyContinue
        Remove-Variable -Name SkuPrecheckCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name SkuPrecheckAvailable -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Feature preconditions fail fast when hibernation is unsupported" -Action {
    try {
        function Get-ClagnosHibernationSupportInfo {
            param([string]$Location, [string]$VmSize)
            return [pscustomobject]@{
                Known = $true
                Supported = $false
                Evidence = @('HibernationSupported=false')
                Message = 'hibernation-not-supported'
            }
        }
        function Get-ClagnosNestedVirtualizationSupportInfo {
            param([string]$Location, [string]$VmSize)
            return [pscustomobject]@{
                Known = $true
                Supported = $true
                Evidence = @('NestedVirtualizationSupported=true')
                Message = 'nested-supported'
            }
        }

        $threw = $false
        try {
            Assert-ClagnosFeaturePreconditions -Context @{
                VmName = 'samplevm'
                AzLocation = 'austriaeast'
                VmSize = 'Standard_D4as_v6'
                VmSecurityType = 'Standard'
                VmEnableHibernation = $true
                VmEnableNestedVirtualization = $false
            }
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Data['Summary'] -eq 'Hibernation precheck failed.') -Message 'Unsupported hibernation must fail during precheck.'
            Assert-True -Condition ([string]$_.Exception.Message -like '*Standard_D4as_v6*') -Message 'Unsupported hibernation precheck must mention the VM size.'
        }

        Assert-True -Condition $threw -Message 'Unsupported hibernation must stop the create/update precheck before Azure mutation.'
    }
    finally {
        foreach ($functionName in @('Get-ClagnosHibernationSupportInfo','Get-ClagnosNestedVirtualizationSupportInfo')) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Feature preconditions fail fast when nested virtualization requires Standard security" -Action {
    $threw = $false
    try {
        try {
            Assert-ClagnosFeaturePreconditions -Context @{
                VmName = 'samplevm'
                AzLocation = 'austriaeast'
                VmSize = 'Standard_D4as_v6'
                VmSecurityType = 'TrustedLaunch'
                VmEnableHibernation = $false
                VmEnableNestedVirtualization = $true
            }
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Data['Summary'] -eq 'Nested virtualization precheck failed.') -Message 'TrustedLaunch nested virtualization mismatch must fail during precheck.'
            Assert-True -Condition ([string]$_.Exception.Message -like '*TrustedLaunch*') -Message 'Nested virtualization precheck must mention the conflicting security type.'
        }

        Assert-True -Condition $threw -Message 'Nested virtualization must fail fast when the selected security type is incompatible.'
    }
    finally {
    }
}

Invoke-Test -Name "Bsv2 nested virtualization is rejected before create when Azure omits the SKU capability" -Action {
    try {
        $script:NestedFamilyFixtures = @{
            'Standard_B1s' = 'Bv1 Series'
            'Standard_B2s_v2' = 'BSv2 Series'
            'Standard_B2as_v2' = 'Basv2 Series'
            'Standard_B2ps_v2' = 'Bpsv2 Series'
            'Standard_D4as_v6' = 'DAsv6 Series'
        }
        function Get-ClagnosVmSkuCapabilitySnapshot {
            param([string]$Location,[string]$VmSize)
            return [pscustomobject]@{
                Known = $true
                Message = ''
                Evidence = @()
                CapabilityRows = @()
                Family = [string]$script:NestedFamilyFixtures[[string]$VmSize]
            }
        }

        foreach ($unsupportedSku in @('Standard_B1s','Standard_B2s_v2','Standard_B2as_v2','Standard_B2ps_v2')) {
            $familySupport = Get-ClagnosNestedVirtualizationSupportInfo -Location 'fixture-region' -VmSize $unsupportedSku
            Assert-True -Condition ([bool]$familySupport.Known -and -not [bool]$familySupport.Supported -and [string]$familySupport.Message -eq 'nested-series-not-supported') -Message ("A documented unsupported B family '{0}' must be a known negative when Compute SKU metadata omits the capability row." -f $unsupportedSku)
        }
        $unknownFamily = Get-ClagnosNestedVirtualizationSupportInfo -Location 'fixture-region' -VmSize 'Standard_D4as_v6'
        Assert-True -Condition (-not [bool]$unknownFamily.Known -and [string]$unknownFamily.Message -eq 'nested-capability-inconclusive') -Message 'An undocumented family with no nested capability row must remain inconclusive instead of being falsely marked unsupported.'

        $support = Get-ClagnosNestedVirtualizationSupportInfo -Location 'fixture-region' -VmSize 'Standard_B2s_v2'
        Assert-True -Condition ([bool]$support.Known -and -not [bool]$support.Supported -and [string]$support.Message -eq 'nested-series-not-supported') -Message 'A documented unsupported Bsv2 family must be a known negative when Compute SKU metadata omits the capability row.'
        Assert-True -Condition ((@($support.Evidence) -join '; ') -match 'VMSize=Standard_B2s_v2.*Family=BSv2 Series.*NestedVirtualization=NotSupported') -Message 'Bsv2 rejection must retain the SKU, family, and documentation evidence.'

        $threw = $false
        try {
            Assert-ClagnosFeaturePreconditions -Context @{
                VmName = 'vc-fixture'
                AzLocation = 'fixture-region'
                VmSize = 'Standard_B2s_v2'
                VmSecurityType = 'Standard'
                VmEnableHibernation = $false
                VmEnableNestedVirtualization = $true
            }
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Data['Summary'] -eq 'Nested virtualization precheck failed.') -Message 'Unsupported Bsv2 nested virtualization must stop in the feature precheck.'
            Assert-True -Condition ([string]$_.Exception.Message -like '*Bsv2 Series*NotSupported*') -Message 'The precheck error must explain the documented family limitation.'
            Assert-True -Condition ([string]$_.Exception.Data['Hint'] -like '*VM_ENABLE_NESTED_VIRTUALIZATION=false*') -Message 'The precheck must explain how to proceed when nested virtualization is optional.'
        }
        Assert-True -Condition $threw -Message 'Bsv2 creation with nested virtualization enabled must fail before resource-group or VM deployment.'
    }
    finally {
        Remove-Item Function:\Get-ClagnosVmSkuCapabilitySnapshot -ErrorAction SilentlyContinue
        Remove-Variable -Name NestedFamilyFixtures -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Precheck step validates feature compatibility before deployment" -Action {
    $script:PrecheckCallOrder = @()
    try {
        function Show-ClagnosStepFirstUseValues { param([string]$StepLabel, [hashtable]$Context, [string[]]$Keys) }
        function Assert-LocationExists { param([string]$Location) $script:PrecheckCallOrder += 'location' }
        function Assert-VmImageAvailable { param([string]$Location, [string]$ImageUrn) $script:PrecheckCallOrder += 'image' }
        function Assert-VmSkuAvailableViaRest { param([string]$Location, [string]$VmSize) $script:PrecheckCallOrder += 'sku' }
        function Assert-VmOsDiskSizeCompatible { param([string]$Location, [string]$ImageUrn, [string]$VmDiskSizeGb) $script:PrecheckCallOrder += 'disk' }
        function Assert-ClagnosSecurityTypePreconditions { param([hashtable]$Context) $script:PrecheckCallOrder += 'security' }
        function Assert-ClagnosFeaturePreconditions { param([hashtable]$Context) $script:PrecheckCallOrder += 'feature' }

        Invoke-ClagnosPrecheckStep -Context @{
            AzLocation = 'austriaeast'
            VmImage = 'publisher:offer:sku:latest'
            VmSize = 'Standard_D4as_v6'
            VmDiskSize = '256'
            VmSecurityType = 'Standard'
            VmEnableHibernation = $true
            VmEnableNestedVirtualization = $true
        }

        Assert-True -Condition ((@($script:PrecheckCallOrder) -join ',') -eq 'location,image,sku,disk,security,feature') -Message 'Precheck step must validate feature compatibility after the base availability checks.'
    }
    finally {
        foreach ($functionName in @(
            'Show-ClagnosStepFirstUseValues',
            'Assert-LocationExists',
            'Assert-VmImageAvailable',
            'Assert-VmSkuAvailableViaRest',
            'Assert-VmOsDiskSizeCompatible',
            'Assert-ClagnosSecurityTypePreconditions',
            'Assert-ClagnosFeaturePreconditions'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name PrecheckCallOrder -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Subscription resolver uses CLI then env then active precedence and persists CLI overrides" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-subscription-test-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $envFilePath = Join-Path $tempRoot '.env'
    Write-TextFileNormalized -Path $envFilePath -Content "SELECTED_AZURE_SUBSCRIPTION_ID=33333333-3333-3333-3333-333333333333" -Encoding 'utf8NoBom' -LineEnding 'crlf' -EnsureTrailingNewline

    try {
        function Get-ClagnosRepoRoot { return $tempRoot }
        function az {
            $line = @($args) -join ' '
            $global:LASTEXITCODE = 0
            if ($line -like 'account list*') {
                return @'
[
  {"id":"11111111-1111-1111-1111-111111111111","name":"cli-sub","tenantId":"tenant-a","isDefault":false},
  {"id":"33333333-3333-3333-3333-333333333333","name":"env-sub","tenantId":"tenant-b","isDefault":false},
  {"id":"44444444-4444-4444-4444-444444444444","name":"active-sub","tenantId":"tenant-c","isDefault":true}
]
'@
            }
            if ($line -like 'account show*') {
                return '{"id":"44444444-4444-4444-4444-444444444444","name":"active-sub","tenantId":"tenant-c"}'
            }
            return ''
        }

        $cliContext = Initialize-ClagnosCommandSubscriptionState -CommandName 'show' -Options @{ 'subscription-id' = '11111111-1111-1111-1111-111111111111' }
        Assert-True -Condition ([string]$cliContext.SubscriptionId -eq '11111111-1111-1111-1111-111111111111') -Message 'CLI subscription must win.'
        Assert-True -Condition ([string]$cliContext.ResolutionSource -eq 'cli') -Message 'CLI resolution source must be recorded.'
        $envAfterCli = Read-DotEnvFile -Path $envFilePath
        Assert-True -Condition ([string]$envAfterCli['SELECTED_AZURE_SUBSCRIPTION_ID'] -eq '11111111-1111-1111-1111-111111111111') -Message 'CLI subscription must persist into .env.'

        Set-DotEnvValue -Path $envFilePath -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Value '33333333-3333-3333-3333-333333333333'
        $envContext = Initialize-ClagnosCommandSubscriptionState -CommandName 'show' -Options @{}
        Assert-True -Condition ([string]$envContext.SubscriptionId -eq '33333333-3333-3333-3333-333333333333') -Message '.env subscription must win when CLI is absent.'
        Assert-True -Condition ([string]$envContext.ResolutionSource -eq 'env') -Message '.env resolution source must be recorded.'

        Set-DotEnvValue -Path $envFilePath -Key 'SELECTED_AZURE_SUBSCRIPTION_ID' -Value ''
        $activeContext = Initialize-ClagnosCommandSubscriptionState -CommandName 'show' -Options @{}
        Assert-True -Condition ([string]$activeContext.SubscriptionId -eq '44444444-4444-4444-4444-444444444444') -Message 'Active Azure CLI subscription must be the final fallback.'
        Assert-True -Condition ([string]$activeContext.ResolutionSource -eq 'active') -Message 'Active resolution source must be recorded.'
    }
    finally {
        foreach ($functionName in @('Get-ClagnosRepoRoot','az')) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Clear-ClagnosResolvedSubscriptionContext
    }
}

Invoke-Test -Name "Azure location queries bypass forced subscription injection" -Action {
    try {
        $script:ClagnosActiveSubscriptionId = '11111111-1111-1111-1111-111111111111'
        $script:BypassAzCliSubscription = 0
        $script:ObservedLocationBypassDepths = @()
        function az {
            $line = @($args) -join ' '
            if ($line -like 'account list-locations*') {
                $script:ObservedLocationBypassDepths += [int]$script:BypassAzCliSubscription
                $global:LASTEXITCODE = 0
                if ($line -like "*availabilityZoneMappings*") {
                    return '["1","2","3"]'
                }
                if ($line -like "*metadata.regionType=='Physical'*") {
                    return '[{"Name":"austriaeast","DisplayName":"Austria East","RegionType":"Physical"}]'
                }
                if ($line -like "*[?name==''austriaeast''].name | [0]*") {
                    return 'austriaeast'
                }
                return '[{"Name":"austriaeast","DisplayName":"Austria East","RegionType":"Physical"}]'
            }

            $global:LASTEXITCODE = 0
            return ''
        }

        Assert-LocationExists -Location 'austriaeast'
        $locationCatalog = @(Get-AzLocationCatalog)
        $zoneArgs = @(Get-ClagnosPublicIpZoneArgs -Location 'austriaeast')

        Assert-True -Condition (@($script:ObservedLocationBypassDepths).Count -ge 3) -Message 'Location-related Azure account queries must all be observed.'
        Assert-True -Condition ((@($script:ObservedLocationBypassDepths) | Where-Object { $_ -lt 1 }).Count -eq 0) -Message 'Location-related Azure account queries must run with forced-subscription bypass enabled.'
        Assert-True -Condition (@($locationCatalog).Count -eq 1) -Message 'Location catalog should still resolve a physical region entry.'
        Assert-True -Condition ((@($zoneArgs) -join ',') -eq '--zone,1,2,3') -Message 'Public IP zone discovery should still return zone arguments.'
    }
    finally {
        Remove-Item Function:\az -ErrorAction SilentlyContinue
        Remove-Variable -Name ObservedLocationBypassDepths -Scope Script -ErrorAction SilentlyContinue
        $script:ClagnosActiveSubscriptionId = ''
        $script:BypassAzCliSubscription = 0
    }
}

Invoke-Test -Name "Interactive create and update subscription picker stores selected subscription" -Action {
    $subscriptionRows = @(
        [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; name = 'default-sub'; tenantId = 'tenant-a'; isDefault = $true },
        [pscustomobject]@{ id = '22222222-2222-2222-2222-222222222222'; name = 'other-sub'; tenantId = 'tenant-b'; isDefault = $false }
    )

    try {
        function Get-ClagnosRepoRoot { return $RepoRoot }
        function Read-DotEnvFile { param([string]$Path) return @{} }
        function Resolve-ClagnosActionPlan { param([string]$CommandName, [hashtable]$Options) return [pscustomobject]@{ Mode='full'; Target='vm-summary'; Actions=@('configure','group','network','vm-deploy','vm-init','vm-update','vm-summary') } }
        function Get-ClagnosAccessibleSubscriptionRows { return @($subscriptionRows) }
        function Read-Host { param([string]$Prompt) return '2' }
        function Get-ClagnosCliOptionText { param([hashtable]$Options, [string]$Name) if ($Options.ContainsKey($Name)) { return [string]$Options[$Name] } return '' }
        function Get-ClagnosCliOptionBool { param([hashtable]$Options, [string]$Name, [bool]$DefaultValue = $false) return $DefaultValue }
        function Assert-ClagnosCreateAutoOptions { param([hashtable]$Options, [switch]$WindowsFlag, [switch]$LinuxFlag) }
        function Assert-ClagnosUpdateAutoOptions { param([hashtable]$Options, [switch]$WindowsFlag, [switch]$LinuxFlag) }
        function Resolve-ClagnosTargetResourceGroup { param([hashtable]$Options, [switch]$AutoMode, [string]$DefaultResourceGroup, [string]$VmName, [string]$OperationName) return 'rg-samplevm-ate1-g1' }
        function Resolve-ClagnosTargetVmName { param([string]$ResourceGroup, [string]$DefaultVmName, [switch]$AutoMode, [string]$OperationName) return 'samplevm' }
        function Test-ClagnosAzResourceExists { param([string[]]$AzArgs) return $true }
        function Get-ClagnosResourceGroupLocation { param([string]$ResourceGroup) return 'austriaeast' }
        function Get-ClagnosManagedTargetOsType { param([string]$ResourceGroup, [string]$VmName) return 'windows' }
        function Get-ClagnosVmNetworkDescriptor {
            param([string]$ResourceGroup, [string]$VmName)
            return [pscustomobject]@{
                VnetName = 'net-samplevm-ate1-n1'
                SubnetName = 'subnet-samplevm-ate1-n1'
                NsgName = 'nsg-samplevm-ate1-n1'
                PublicIpName = 'ip-samplevm-ate1-n1'
                NicName = 'nic-samplevm-ate1-n1'
                OsDiskName = 'disk-samplevm-ate1-n1'
            }
        }

        Set-ClagnosResolvedSubscriptionContext -SubscriptionId '11111111-1111-1111-1111-111111111111' -SubscriptionName 'default-sub' -TenantId 'tenant-a' -ResolutionSource 'active'
        $createRuntime = New-ClagnosCreateCommandRuntime -Options @{} -WindowsFlag:$false -LinuxFlag:$false -AutoMode:$false
        Assert-True -Condition ([string]$createRuntime.InitialConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] -eq '22222222-2222-2222-2222-222222222222') -Message 'Interactive create must persist the selected subscription id.'
        Assert-True -Condition ([string](Get-ClagnosResolvedSubscriptionContext).SubscriptionId -eq '22222222-2222-2222-2222-222222222222') -Message 'Interactive create must update the active subscription context.'

        Set-ClagnosResolvedSubscriptionContext -SubscriptionId '11111111-1111-1111-1111-111111111111' -SubscriptionName 'default-sub' -TenantId 'tenant-a' -ResolutionSource 'active'
        $updateRuntime = New-ClagnosUpdateCommandRuntime -Options @{} -WindowsFlag:$false -LinuxFlag:$false -AutoMode:$false
        Assert-True -Condition ([string]$updateRuntime.InitialConfigOverrides['SELECTED_AZURE_SUBSCRIPTION_ID'] -eq '22222222-2222-2222-2222-222222222222') -Message 'Interactive update must persist the selected subscription id.'
        Assert-True -Condition ([string](Get-ClagnosResolvedSubscriptionContext).SubscriptionId -eq '22222222-2222-2222-2222-222222222222') -Message 'Interactive update must update the active subscription context.'
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot','Read-DotEnvFile','Resolve-ClagnosActionPlan','Get-ClagnosAccessibleSubscriptionRows','Read-Host','Get-ClagnosCliOptionText','Get-ClagnosCliOptionBool',
            'Assert-ClagnosCreateAutoOptions','Assert-ClagnosUpdateAutoOptions','Resolve-ClagnosTargetResourceGroup','Resolve-ClagnosTargetVmName','Test-ClagnosAzResourceExists',
            'Get-ClagnosResourceGroupLocation','Get-ClagnosManagedTargetOsType','Get-ClagnosVmNetworkDescriptor'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Clear-ClagnosResolvedSubscriptionContext
    }
}

Invoke-Test -Name "List rejects invalid type filter" -Action {
    foreach ($invalidValue in @('group;vm', 'group,unknown')) {
        $threw = $false
        try {
            Assert-ClagnosCommandOptions -CommandName 'list' -Options @{ type = $invalidValue }
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message ("List must reject invalid type filter '{0}'." -f [string]$invalidValue)
    }
}

Invoke-Test -Name "List group inventory includes active marker, location, and provisioning state" -Action {
    $rows = @(Get-ClagnosListSectionRows `
        -TypeName 'group' `
        -ResourceGroups @('rg-active-ate1-g1','rg-other-cin1-g2') `
        -ConfigMap @{ SELECTED_RESOURCE_GROUP = 'rg-active-ate1-g1' } `
        -ManagedGroupRows @(
            [pscustomobject]@{ name = 'rg-active-ate1-g1'; location = 'austriaeast'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' } },
            [pscustomobject]@{ name = 'rg-other-cin1-g2'; location = 'centralindia'; properties = [pscustomobject]@{ provisioningState = 'Accepted' } }
        ))

    Assert-True -Condition (@($rows).Count -eq 2) -Message 'Managed group inventory must keep one metadata row per group.'
    Assert-True -Condition ([string]$rows[0] -match 'rg-active-ate1-g1 \[active\].*location=austriaeast.*provisioning=Succeeded') -Message 'Active resource group row must show its location and provisioning state.'
    Assert-True -Condition ([string]$rows[1] -match 'rg-other-cin1-g2.*location=centralindia.*provisioning=Accepted') -Message 'Other resource group row must show its location and provisioning state.'
}

Invoke-Test -Name "Interactive create platform prompt ignores persisted SELECTED_VM_OS when flags are missing" -Action {
    function Read-Host {
        param([string]$Prompt)
        return ''
    }

    try {
        $configOverrides = @{}
        $promptedPlatform = Resolve-ClagnosPlatformSelection `
            -ConfigMap @{ SELECTED_VM_OS = 'linux' } `
            -EnvFilePath 'ignored.env' `
            -AutoMode:$false `
            -WindowsFlag:$false `
            -LinuxFlag:$false `
            -ConfigOverrides $configOverrides `
            -DeferEnvWrite `
            -PromptWhenFlagsMissing
        Assert-True -Condition ([string]$promptedPlatform -eq 'windows') -Message 'Interactive create platform prompt must default blank input to windows.'
        Assert-True -Condition ([string]$configOverrides['VM_OS_TYPE'] -eq 'windows') -Message 'Interactive create platform prompt must persist the prompted platform into config overrides.'

        $envDrivenPlatform = Resolve-ClagnosPlatformSelection `
            -ConfigMap @{ SELECTED_VM_OS = 'linux' } `
            -EnvFilePath 'ignored.env' `
            -AutoMode:$false `
            -WindowsFlag:$false `
            -LinuxFlag:$false `
            -ConfigOverrides @{} `
            -DeferEnvWrite
        Assert-True -Condition ([string]$envDrivenPlatform -eq 'linux') -Message 'Platform selection without PromptWhenFlagsMissing must still honor .env SELECTED_VM_OS.'
    }
    finally {
        Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Read-Host -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Configure VM selection helper auto-selects one VM and rejects ambiguous explicit groups" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @('Get-ClagnosVmNamesForResourceGroup')) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosVmNamesForResourceGroup {
        param([string]$ResourceGroup)
        if ([string]::Equals([string]$ResourceGroup, 'rg-single', [System.StringComparison]::OrdinalIgnoreCase)) {
            return @('vm-single')
        }
        return @('vm-a', 'vm-b')
    }

    try {
        $resolvedVm = Resolve-ClagnosVmSelectionForResourceGroup `
            -ResourceGroup 'rg-single' `
            -RequestedVmName '' `
            -DefaultVmName '' `
            -AutoSelectSingleVm `
            -FailIfMultipleWithoutExplicitVm `
            -OperationName 'configure'
        Assert-True -Condition ([string]$resolvedVm -eq 'vm-single') -Message 'Configure VM helper must auto-select the single VM in the selected resource group.'

        $threw = $false
        try {
            Resolve-ClagnosVmSelectionForResourceGroup `
                -ResourceGroup 'rg-multi' `
                -RequestedVmName '' `
                -DefaultVmName '' `
                -AutoSelectSingleVm `
                -FailIfMultipleWithoutExplicitVm `
                -OperationName 'configure' | Out-Null
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*contains multiple VMs*') -Message 'Configure VM helper failure must explain the ambiguous resource group.'
        }

        Assert-True -Condition $threw -Message 'Configure VM helper must reject explicit managed groups that contain multiple VMs when vm-name is omitted.'
    }
    finally {
        foreach ($functionName in @('Get-ClagnosVmNamesForResourceGroup')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "List type resolver keeps supported output order" -Action {
    $resolvedTypes = @(Resolve-ClagnosListRequestedTypes -Options @{ type = 'nsg-rule,group,vm' })
    Assert-True -Condition ((@($resolvedTypes) -join ',') -eq 'group,vm,nsg-rule') -Message 'List type resolver must normalize requested values into the supported output order.'
}

Invoke-Test -Name "Create and update accept renamed step selectors" -Action {
    Assert-ClagnosCommandOptions -CommandName 'create' -Options @{ step = 'network'; linux = $true }
    Assert-ClagnosCommandOptions -CommandName 'create' -Options @{ 'step-from' = 'vm-deploy'; 'step-to' = 'vm-summary'; auto = $true; windows = $true; 'vm-name' = 'samplevm'; 'vm-region' = 'swedencentral'; 'vm-size' = 'Standard_D4as_v5' }
    Assert-ClagnosCommandOptions -CommandName 'update' -Options @{ step = 'vm-update'; auto = $true; windows = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
    Assert-ClagnosCommandOptions -CommandName 'update' -Options @{ 'step-from' = 'vm-update'; 'step-to' = 'vm-summary'; auto = $true; windows = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
}

Invoke-Test -Name "Create and update reject retired step selectors" -Action {
    $retiredOptionCases = @(
        @{ Command = 'create'; Options = @{ 'single-step' = 'network' } },
        @{ Command = 'create'; Options = @{ 'from-step' = 'group'; 'step-to' = 'vm-init' } },
        @{ Command = 'create'; Options = @{ 'step-from' = 'group'; 'to-step' = 'vm-init' } },
        @{ Command = 'update'; Options = @{ 'single-step' = 'vm-update'; auto = $true } },
        @{ Command = 'update'; Options = @{ 'from-step' = 'vm-deploy'; 'to-step' = 'vm-summary'; auto = $true } }
    )

    foreach ($case in @($retiredOptionCases)) {
        $threw = $false
        try {
            Assert-ClagnosCommandOptions -CommandName ([string]$case.Command) -Options $case.Options
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message ("Retired step selector must be rejected for command '{0}'." -f [string]$case.Command)
    }
}

Invoke-Test -Name "Action plan resolves renamed step selectors" -Action {
    $singlePlan = Resolve-ClagnosActionPlan -CommandName 'create' -Options @{ step = 'network' }
    Assert-True -Condition ([string]$singlePlan.Mode -eq 'single') -Message "Single-step action plan mode mismatch."
    Assert-True -Condition (@($singlePlan.Actions).Count -eq 1 -and [string]$singlePlan.Actions[0] -eq 'network') -Message "Single-step action plan must contain only the requested step."

    $rangePlan = Resolve-ClagnosActionPlan -CommandName 'update' -Options @{ 'step-from' = 'vm-update'; 'step-to' = 'vm-summary' }
    Assert-True -Condition ([string]$rangePlan.Mode -eq 'range') -Message "Range action plan mode mismatch."
    Assert-True -Condition ((@($rangePlan.Actions) -join ',') -eq 'vm-update,vm-summary') -Message "Update range must stay within its maintenance contract."

    $createDefaultPlan = Resolve-ClagnosActionPlan -CommandName 'create' -Options @{}
    $updateDefaultPlan = Resolve-ClagnosActionPlan -CommandName 'update' -Options @{}
    Assert-True -Condition ((@($createDefaultPlan.Actions) -join ',') -eq 'configure,group,network,vm-deploy,vm-summary') -Message 'Default create must stop after VM deployment and summary.'
    Assert-True -Condition ((@($updateDefaultPlan.Actions) -join ',') -eq 'configure,vm-update,vm-summary') -Message 'Default update must not include infrastructure or vm-init steps.'

    $unsupportedRangeFailed = $false
    try {
        Resolve-ClagnosActionPlan -CommandName 'update' -Options @{ 'step-from' = 'vm-deploy'; 'step-to' = 'vm-summary' } | Out-Null
    }
    catch { $unsupportedRangeFailed = $true }
    Assert-True -Condition $unsupportedRangeFailed -Message 'Update must reject infrastructure or vm-init step ranges.'

    $threw = $false
    try {
        Resolve-ClagnosActionPlan -CommandName 'create' -Options @{ step = 'network'; 'step-to' = 'vm-summary' } | Out-Null
    }
    catch {
        $threw = $true
    }

    Assert-True -Condition $threw -Message "Conflicting renamed step selectors must be rejected."
}

Invoke-Test -Name "Move and set commands accept vm-name" -Action {
    Assert-ClagnosCommandOptions -CommandName 'move' -Options @{ 'vm-name' = 'samplevm'; 'vm-region' = 'swedencentral'; group = 'rg-samplevm-ate1-g1' }
    Assert-ClagnosCommandOptions -CommandName 'set' -Options @{ 'vm-name' = 'samplevm'; group = 'rg-samplevm-ate1-g1'; hibernation = 'on' }
}

Invoke-Test -Name "Task command accepts list filters" -Action {
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ list = $true }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ list = $true; 'vm-init' = $true; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ list = $true; 'vm-update' = $true; disabled = $true; linux = $true }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ history = $true }
}

Invoke-Test -Name "Task run history persists local outcome metadata and omits guest output" -Action {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $historyRoot = Join-Path $tempBase ('clagnos-task-history-test-' + [guid]::NewGuid().ToString('N'))
    $previousHistoryPathOverride = [string]$script:ClagnosTaskHistoryPathOverride
    $script:ClagnosTaskHistoryPathOverride = Join-Path $historyRoot 'task-runs.jsonl'
    try {
        Write-ClagnosTaskRunHistoryRecord -Record ([ordered]@{
            SchemaVersion = 1
            CompletedAtUtc = '2026-10-13T00:00:00.0000000Z'
            Operation = 'task'
            Stage = 'update'
            Platform = 'windows'
            ResourceGroup = 'rg-sample'
            VmName = 'samplevm'
            TaskNumber = 101
            TaskName = '101-test-task'
            Requested = '101'
            Outcome = 'completed-with-warnings'
            SuccessCount = 1
            FailedCount = 0
            WarningCount = 1
            ErrorCount = 0
            RebootCount = 0
            DeferredAppStateCount = 0
            DurationSeconds = 12.5
            FailureCategory = ''
            FailureSummary = ''
        })

        $records = @(Get-ClagnosTaskRunHistoryRecords -Limit 25)
        Assert-True -Condition ($records.Count -eq 1) -Message 'Task history reader must return the appended JSONL record.'
        Assert-True -Condition ([string]$records[0].Outcome -eq 'completed-with-warnings') -Message 'Task history must preserve the run outcome.'
        Assert-True -Condition ([int]$records[0].WarningCount -eq 1) -Message 'Task history must preserve warning counts.'
        Assert-True -Condition ([string]$records[0].PSObject.Properties['VmPass'] -eq '') -Message 'Task history must not contain guest credentials.'
        Assert-True -Condition ([string](Get-Content -LiteralPath $script:ClagnosTaskHistoryPathOverride -Raw) -notmatch 'password|guest output') -Message 'Task history JSONL must not include secrets or guest command output.'
    }
    finally {
        $resolvedHistoryRoot = [System.IO.Path]::GetFullPath($historyRoot)
        $resolvedTempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedHistoryRoot.StartsWith(($resolvedTempBase + 'clagnos-task-history-test-'), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Refusing to remove unexpected task history test path: {0}" -f $resolvedHistoryRoot)
        }
        if (Test-Path -LiteralPath $resolvedHistoryRoot) { Remove-Item -LiteralPath $resolvedHistoryRoot -Recurse -Force }
        $script:ClagnosTaskHistoryPathOverride = $previousHistoryPathOverride
    }
}

Invoke-Test -Name "Task execution wrapper records outcome and deferred app-state metadata" -Action {
    $originalDisabled = [bool]$script:ClagnosTaskHistoryDisabled
    $script:ClagnosTaskHistoryDisabled = $false
    $script:CapturedTaskRunHistoryRecord = $null
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @('Invoke-ClagnosTaskExecutionWithTargetCore','Write-ClagnosTaskRunHistoryRecord')) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) { $originalFunctionDefinitions[$functionName] = [string]$command.Definition }
    }

    function Invoke-ClagnosTaskExecutionWithTargetCore {
        param([pscustomobject]$Runtime,[hashtable]$Options,[string]$OperationName,[string]$Stage,[string]$Requested,[psobject]$PackageTaskBlock,[switch]$AutoMode,[string]$TaskOutcomeModeOverride)
        return [pscustomobject]@{
            Stage = 'update'
            Task = [pscustomobject]@{ TaskNumber = 101; Name = '101-fixture-update' }
            Result = [pscustomobject]@{ SuccessCount = 1; FailedCount = 0; WarningCount = 1; ErrorCount = 0; RebootCount = 0; DeferredAppStateCount = 2; DeferredAppStateTasks = @('101-state-alpha','101-state-beta') }
        }
    }
    function Write-ClagnosTaskRunHistoryRecord { param([psobject]$Record) $script:CapturedTaskRunHistoryRecord = $Record }
    foreach ($functionName in @('Invoke-ClagnosTaskExecutionWithTargetCore','Write-ClagnosTaskRunHistoryRecord')) {
        $localFunction = Get-Command $functionName -CommandType Function -ErrorAction Stop
        $mockDefinition = [scriptblock]::Create([string]$localFunction.Definition)
        Set-Item -Path ("Function:\script:{0}" -f $functionName) -Value $mockDefinition
        Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value $mockDefinition
    }

    try {
        $runResult = Invoke-ClagnosTaskExecutionWithTarget `
            -Runtime ([pscustomobject]@{ Platform = 'windows'; Context = [pscustomobject]@{ ResourceGroup = 'rg-sample'; VmName = 'samplevm' } }) `
            -Options @{ group = 'rg-sample'; 'vm-name' = 'samplevm' } `
            -OperationName 'task' `
            -Stage 'update' `
            -Requested '101-fixture-update'

        Assert-True -Condition ([string]$runResult.Task.Name -eq '101-fixture-update') -Message 'Task history wrapper must preserve the task execution result.'
        Assert-True -Condition ([string]$script:CapturedTaskRunHistoryRecord.Outcome -eq 'completed-with-warnings') -Message 'Task history must classify warning outcomes.'
        Assert-True -Condition ([int]$script:CapturedTaskRunHistoryRecord.DeferredAppStateCount -eq 2) -Message 'Task history must retain deferred app-state counts.'
        Assert-True -Condition (@($script:CapturedTaskRunHistoryRecord.DeferredAppStateTasks).Count -eq 2) -Message 'Task history must identify deferred app-state tasks.'
        Assert-True -Condition (-not $script:CapturedTaskRunHistoryRecord.Contains('VmPass')) -Message 'Task history must not include VM credentials.'
    }
    finally {
        $script:ClagnosTaskHistoryDisabled = $originalDisabled
        Remove-Item Function:\global:Invoke-ClagnosTaskExecutionWithTargetCore -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-ClagnosTaskRunHistoryRecord -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-ClagnosTaskExecutionWithTargetCore -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ClagnosTaskRunHistoryRecord -ErrorAction SilentlyContinue
        Remove-Item Function:\script:Invoke-ClagnosTaskExecutionWithTargetCore -ErrorAction SilentlyContinue
        Remove-Item Function:\script:Write-ClagnosTaskRunHistoryRecord -ErrorAction SilentlyContinue
        foreach ($functionName in @('Invoke-ClagnosTaskExecutionWithTargetCore','Write-ClagnosTaskRunHistoryRecord')) {
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\script:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
        Remove-Variable -Name CapturedTaskRunHistoryRecord -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Workflow task history records stage tasks and unresolved deferred work" -Action {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $historyRoot = Join-Path $tempBase ('clagnos-task-stage-history-test-' + [guid]::NewGuid().ToString('N'))
    $previousHistoryPathOverride = [string]$script:ClagnosTaskHistoryPathOverride
    $previousHistoryDisabled = [bool]$script:ClagnosTaskHistoryDisabled
    $script:ClagnosTaskHistoryPathOverride = Join-Path $historyRoot 'task-runs.jsonl'
    $script:ClagnosTaskHistoryDisabled = $false
    try {
        Write-ClagnosTaskStageHistoryRecord `
            -Stage 'init' `
            -Platform 'windows' `
            -ResourceGroup 'rg-sample' `
            -VmName 'samplevm' `
            -TaskNames @('01-first-task','02-second-task') `
            -FailedTasks @('02-second-task') `
            -WarningTasks @('02-second-task => app-state-deferred') `
            -DeferredAppStateTasks @('02-second-task') `
            -SuccessCount 1 `
            -ErrorCount 0 `
            -RebootCount 1 `
            -DurationSeconds 34.5

        $visibleRecords = @(Show-ClagnosTaskRunHistory -Limit 25)
        Assert-True -Condition ($visibleRecords.Count -eq 1) -Message 'Task history screen must read the saved stage record without Azure setup.'
        Assert-True -Condition ([string]$visibleRecords[0].Outcome -eq 'completed-with-failures') -Message 'Stage history must summarize a failed task outcome.'
        Assert-True -Condition ([int]$visibleRecords[0].DeferredAppStateCount -eq 1) -Message 'Stage history must preserve deferred app-state counts.'
        Assert-True -Condition ((@($visibleRecords[0].TaskNames) -join ',') -eq '01-first-task,02-second-task') -Message 'Stage history must preserve task names for support diagnosis.'
    }
    finally {
        $resolvedHistoryRoot = [System.IO.Path]::GetFullPath($historyRoot)
        $resolvedTempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedHistoryRoot.StartsWith(($resolvedTempBase + 'clagnos-task-stage-history-test-'), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Refusing to remove unexpected task stage history test path: {0}" -f $resolvedHistoryRoot)
        }
        if (Test-Path -LiteralPath $resolvedHistoryRoot) { Remove-Item -LiteralPath $resolvedHistoryRoot -Recurse -Force }
        $script:ClagnosTaskHistoryPathOverride = $previousHistoryPathOverride
        $script:ClagnosTaskHistoryDisabled = $previousHistoryDisabled
    }
}

Invoke-Test -Name "Task command lists discovered tasks in runtime order" -Action {
    try {
        function Initialize-ClagnosTaskCommandRuntimeContext {
            param([switch]$AutoMode, [switch]$WindowsFlag, [switch]$LinuxFlag)
            return [pscustomobject]@{
                Platform = 'windows'
                VmInitTaskDir = 'windows/init'
                VmUpdateTaskDir = 'windows/update'
            }
        }
        function Get-ClagnosTaskBlocksFromDirectory {
            param([string]$DirectoryPath, [string]$Platform, [string]$Stage, [switch]$SuppressSkipMessages)
            if ($Stage -eq 'init') {
                return [ordered]@{
                    InventoryTasks = @(
                        [pscustomobject]@{
                            Name = '01-ensure-local-user-accounts'
                            RelativePath = '01-ensure-local-user-accounts.ps1'
                            TimeoutSeconds = 180
                            Priority = 1
                            TaskType = 'initial'
                            Source = 'tracked'
                            TaskNumber = 1
                            Enabled = $true
                            DisabledReason = ''
                        },
                        [pscustomobject]@{
                            Name = '1004-disabled-local-task'
                            RelativePath = 'local/disabled/1004-disabled-local-task.ps1'
                            TimeoutSeconds = 180
                            Priority = 1004
                            TaskType = 'local'
                            Source = 'local'
                            TaskNumber = 1004
                            Enabled = $false
                            DisabledReason = 'disabled-by-location'
                        }
                    )
                }
            }

            return [ordered]@{
                InventoryTasks = @(
                    [pscustomobject]@{
                        Name = '102-configure-autologon-settings'
                        RelativePath = '102-configure-autologon-settings/102-configure-autologon-settings.ps1'
                        TimeoutSeconds = 45
                        Priority = 10006
                        TaskType = 'final'
                        Source = 'tracked'
                        TaskNumber = 10006
                        Enabled = $true
                        DisabledReason = ''
                    }
                )
            }
        }

        $updateResult = Invoke-ClagnosTaskCommand -Options @{ list = $true; 'vm-update' = $true } -AutoMode:$false -WindowsFlag -LinuxFlag:$false
        Assert-True -Condition ($null -ne $updateResult) -Message 'Task command must return a result object.'
        Assert-True -Condition ($updateResult.Rows.Count -eq 1) -Message 'Task command vm-update filter must return only update-stage rows.'
        Assert-True -Condition ([string]$updateResult.Rows[0].Name -eq '102-configure-autologon-settings') -Message 'Task command must preserve discovered update task names.'
        Assert-True -Condition ([string]$updateResult.Rows[0].Stage -eq 'vm-update') -Message 'Task command must label update-stage rows.'

        $disabledResult = Invoke-ClagnosTaskCommand -Options @{ list = $true; disabled = $true } -AutoMode:$false -WindowsFlag -LinuxFlag:$false
        Assert-True -Condition ($disabledResult.Rows.Count -eq 1) -Message 'Task command disabled filter must return only disabled rows.'
        Assert-True -Condition ([string]$disabledResult.Rows[0].Status -eq 'disabled') -Message 'Task command disabled filter must label disabled tasks correctly.'
        Assert-True -Condition ([string]$disabledResult.Rows[0].Source -eq 'local') -Message 'Task command must preserve local/builtin source labels.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosTaskCommandRuntimeContext',
            'Get-ClagnosTaskBlocksFromDirectory'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Set command applies both toggles and persists them to .env" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-set-test-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $envFilePath = Join-Path $tempRoot '.env'
    Write-TextFileNormalized -Path $envFilePath -Content @"
SELECTED_RESOURCE_GROUP=rg-old
SELECTED_VM_NAME=oldvm
VM_ENABLE_HIBERNATION=false
VM_ENABLE_NESTED_VIRTUALIZATION=true
"@ -Encoding 'utf8NoBom' -LineEnding 'crlf' -EnsureTrailingNewline

    try {
        $script:SetCommandAzCalls = @()

        function Get-ClagnosRepoRoot { return $tempRoot }
        function Initialize-ClagnosCommandRuntimeContext { throw 'Set command must not initialize the full command runtime context.' }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-target'
                VmName = 'targetvm'
            }
        }
        function Invoke-TrackedAction {
            param([string]$Label, [scriptblock]$Action)
            & $Action
            return [pscustomobject]@{ Label = $Label }
        }
        function az {
            $script:SetCommandAzCalls += ,(@($args) -join ' ')
            $global:LASTEXITCODE = 0
            return ''
        }

        Invoke-ClagnosSetCommand -Options @{
            group = 'rg-target'
            'vm-name' = 'targetvm'
            hibernation = 'on'
            'nested-virtualization' = 'off'
        } -AutoMode:$false -WindowsFlag:$false -LinuxFlag:$false

        $envMap = Read-DotEnvFile -Path $envFilePath
        Assert-True -Condition ([string]$envMap['SELECTED_RESOURCE_GROUP'] -eq 'rg-target') -Message 'Set command must persist the resolved selected resource group.'
        Assert-True -Condition ([string]$envMap['SELECTED_VM_NAME'] -eq 'targetvm') -Message 'Set command must persist the resolved selected VM name.'
        Assert-True -Condition ([string]$envMap['VM_ENABLE_HIBERNATION'] -eq 'true') -Message 'Set command must persist VM_ENABLE_HIBERNATION=true when hibernation is turned on.'
        Assert-True -Condition ([string]$envMap['VM_ENABLE_NESTED_VIRTUALIZATION'] -eq 'false') -Message 'Set command must persist VM_ENABLE_NESTED_VIRTUALIZATION=false when nested virtualization is turned off.'
        Assert-True -Condition (@($script:SetCommandAzCalls).Count -eq 1) -Message 'Set command must issue the Azure hibernation update without calling a nested virtualization API toggle.'
        Assert-True -Condition ((@($script:SetCommandAzCalls) -join "`n") -match [regex]::Escape('--enable-hibernation true')) -Message 'Set command must call Azure hibernation update.'
        Assert-True -Condition (-not ((@($script:SetCommandAzCalls) -join "`n") -match [regex]::Escape('additionalCapabilities.nestedVirtualization'))) -Message 'Set command must not call the removed Azure nested virtualization property path.'
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Initialize-ClagnosCommandRuntimeContext',
            'Resolve-ClagnosManagedVmTarget',
            'Invoke-TrackedAction',
            'az'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name SetCommandAzCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Set command persists successful updates before a later toggle failure" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-set-failover-test-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    $envFilePath = Join-Path $tempRoot '.env'
    Write-TextFileNormalized -Path $envFilePath -Content @"
SELECTED_RESOURCE_GROUP=rg-old
SELECTED_VM_NAME=oldvm
VM_ENABLE_HIBERNATION=false
VM_ENABLE_NESTED_VIRTUALIZATION=true
"@ -Encoding 'utf8NoBom' -LineEnding 'crlf' -EnsureTrailingNewline

    try {
        $script:SetCommandFailureAzCalls = @()
        $script:SetCommandNestedValidationCalled = $false

        function Get-ClagnosRepoRoot { return $tempRoot }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-target'
                VmName = 'targetvm'
            }
        }
        function Invoke-TrackedAction {
            param([string]$Label, [scriptblock]$Action)
            & $Action
            return [pscustomobject]@{ Label = $Label }
        }
        function Get-ClagnosVmLifecycleSnapshot {
            param([string]$ResourceGroup, [string]$VmName)
            return [pscustomobject]@{
                NormalizedState = 'started'
                VmName = $VmName
                ResourceGroup = $ResourceGroup
                PowerStateDisplay = 'VM running'
                ProvisioningStateDisplay = 'Provisioning succeeded'
                HibernationStateDisplay = ''
                HibernationStateCode = ''
                HibernationEnabled = $true
            }
        }
        function Get-ClagnosNestedVirtualizationGuestValidation {
            param([string]$ResourceGroup, [string]$VmName, [string]$OsType)
            $script:SetCommandNestedValidationCalled = $true
            return [pscustomobject]@{
                Known = $true
                Enabled = $false
                Evidence = @('VirtualizationFirmwareEnabled=False')
                Data = $null
                ErrorMessage = ''
            }
        }
        function az {
            $line = @($args) -join ' '
            $script:SetCommandFailureAzCalls += ,$line
            $global:LASTEXITCODE = 0
            return ''
        }

        $threw = $false
        try {
            Invoke-ClagnosSetCommand -Options @{
                group = 'rg-target'
                'vm-name' = 'targetvm'
                hibernation = 'on'
                'nested-virtualization' = 'on'
            } -AutoMode:$false -WindowsFlag:$false -LinuxFlag:$false
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message 'Set command must fail when nested virtualization guest validation fails.'
        Assert-True -Condition ([bool]$script:SetCommandNestedValidationCalled) -Message 'Set command must validate nested virtualization through guest checks when turning it on.'
        $envMap = Read-DotEnvFile -Path $envFilePath
        Assert-True -Condition ([string]$envMap['SELECTED_RESOURCE_GROUP'] -eq 'rg-target') -Message 'Set command must still persist the resolved selected resource group after a partial update.'
        Assert-True -Condition ([string]$envMap['SELECTED_VM_NAME'] -eq 'targetvm') -Message 'Set command must still persist the resolved selected VM name after a partial update.'
        Assert-True -Condition ([string]$envMap['VM_ENABLE_HIBERNATION'] -eq 'true') -Message 'Set command must persist the successful hibernation update even if a later toggle fails.'
        Assert-True -Condition ([string]$envMap['VM_ENABLE_NESTED_VIRTUALIZATION'] -eq 'true') -Message 'Set command must not overwrite nested virtualization in .env when the Azure update failed.'
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Resolve-ClagnosManagedVmTarget',
            'Invoke-TrackedAction',
            'Get-ClagnosVmLifecycleSnapshot',
            'Get-ClagnosNestedVirtualizationGuestValidation',
            'az'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name SetCommandFailureAzCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name SetCommandNestedValidationCalled -Scope Script -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Post-deploy feature enablement verifies desired flags even on existing VMs" -Action {
    $script:FeatureEnablementAzCalls = @()
    $script:FeatureEnablementGuestValidationCalled = $false
    $script:FeatureEnablementState = @{
        HibernationEnabled = $false
    }
    try {
        function Invoke-TrackedAction {
            param([string]$Label, [scriptblock]$Action)
            & $Action
            return [pscustomobject]@{ Label = $Label }
        }
        function Wait-ClagnosProvisioningSucceeded {
            param([string]$ResourceGroup, [string]$VmName, [int]$MaxAttempts, [int]$DelaySeconds)
            return [pscustomobject]@{
                Ready = $true
                Snapshot = [pscustomobject]@{
                    ProvisioningStateCode = 'ProvisioningState/succeeded'
                    ProvisioningStateDisplay = 'Provisioning succeeded'
                    PowerStateCode = 'PowerState/running'
                    PowerStateDisplay = 'VM running'
                }
            }
        }
        function Get-ClagnosHibernationSupportInfo {
            param([string]$Location, [string]$VmSize)
            return [pscustomobject]@{
                Known = $true
                Supported = $true
                Evidence = @('HibernationSupported=true')
                Message = 'hibernation-supported'
            }
        }
        function Get-ClagnosNestedVirtualizationSupportInfo {
            param([string]$Location, [string]$VmSize)
            return [pscustomobject]@{
                Known = $false
                Supported = $false
                Evidence = @()
                Message = 'nested-capability-inconclusive'
            }
        }
        function Get-ClagnosNestedVirtualizationGuestValidation {
            param([string]$ResourceGroup, [string]$VmName, [string]$OsType, [int]$MaxAttempts, [int]$RetryDelaySeconds)
            $script:FeatureEnablementGuestValidationCalled = $true
            return [pscustomobject]@{
                Known = $true
                Enabled = $true
                Evidence = @('VMMonitorModeExtensions=True','VirtualizationFirmwareEnabled=True','SecondLevelAddressTranslationExtensions=True')
                Data = $null
                ErrorMessage = ''
            }
        }
        function az {
            $line = @($args) -join ' '
            $script:FeatureEnablementAzCalls += ,$line

            if ($line -match [regex]::Escape('securityProfile.securityType')) {
                $global:LASTEXITCODE = 0
                return '{"securityType":"Standard","secureBoot":true,"vTpm":true}'
            }
            if ($line -match [regex]::Escape('additionalCapabilities.hibernationEnabled')) {
                $global:LASTEXITCODE = 0
                if ([bool]$script:FeatureEnablementState.HibernationEnabled) { return 'true' }
                return ''
            }
            if ($line -match [regex]::Escape('disk update') -or $line -match [regex]::Escape('--set supportsHibernation=true')) {
                $global:LASTEXITCODE = 0
                return ''
            }
            if ($line -match [regex]::Escape('--enable-hibernation true')) {
                $script:FeatureEnablementState.HibernationEnabled = $true
                $global:LASTEXITCODE = 0
                return ''
            }

            $global:LASTEXITCODE = 0
            return ''
        }

        $result = Invoke-ClagnosPostDeployFeatureEnablement -Context @{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            VmDiskName = 'disk-samplevm'
            AzLocation = 'austriaeast'
            VmSize = 'Standard_D4as_v5'
            VmSecurityType = 'Standard'
            VmEnableHibernation = $true
            VmEnableNestedVirtualization = $true
        } -VmCreatedThisRun:$false

        Assert-True -Condition ([bool]$result.HibernationAttempted) -Message 'Feature enablement must still evaluate hibernation on existing VMs.'
        Assert-True -Condition ([bool]$result.HibernationEnabled) -Message 'Feature enablement must verify hibernation.'
        Assert-True -Condition ([bool]$result.NestedAttempted) -Message 'Feature enablement must still evaluate nested virtualization on existing VMs.'
        Assert-True -Condition ([bool]$result.NestedEnabled) -Message 'Feature enablement must verify nested virtualization.'
        Assert-True -Condition ([bool]$script:FeatureEnablementGuestValidationCalled) -Message 'Feature enablement must validate nested virtualization through guest checks.'
        Assert-True -Condition ((@($script:FeatureEnablementAzCalls) -join "`n") -match [regex]::Escape('--enable-hibernation true')) -Message 'Feature enablement must call the Azure hibernation update.'
        Assert-True -Condition (-not ((@($script:FeatureEnablementAzCalls) -join "`n") -match [regex]::Escape('additionalCapabilities.nestedVirtualization'))) -Message 'Feature enablement must not call the removed Azure nested virtualization property path.'
        Assert-True -Condition ((@($script:FeatureEnablementAzCalls) | Where-Object { $_ -like '*vm deallocate*' }).Count -eq 1) -Message 'Feature enablement should deallocate the VM once before applying feature updates.'
        Assert-True -Condition ((@($script:FeatureEnablementAzCalls) | Where-Object { $_ -like '*vm start*' }).Count -eq 1) -Message 'Feature enablement should start the VM again after feature updates.'
    }
    finally {
        foreach ($functionName in @(
            'Invoke-TrackedAction',
            'Wait-ClagnosProvisioningSucceeded',
            'Get-ClagnosHibernationSupportInfo',
            'Get-ClagnosNestedVirtualizationSupportInfo',
            'Get-ClagnosNestedVirtualizationGuestValidation',
            'az'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name FeatureEnablementAzCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name FeatureEnablementGuestValidationCalled -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name FeatureEnablementState -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Windows nested virtualization guest validation requires exposed CPU virtualization extensions" -Action {
    try {
        $script:NestedGuestValidationFixture = $null
        function Invoke-ClagnosVmRunCommandJson {
            param(
                [string]$ResourceGroup,
                [string]$VmName,
                [string]$CommandId,
                [string[]]$Scripts,
                [string]$ContextLabel,
                [int]$MaxAttempts,
                [int]$RetryDelaySeconds
            )

            return [pscustomobject]@{
                Success = $true
                ErrorMessage = ''
                OutputObject = $script:NestedGuestValidationFixture
            }
        }

        $script:NestedGuestValidationFixture = [pscustomobject]@{
            ProcessorName = 'Intel Xeon fixture processor'
            VMMonitorModeExtensions = $true
            VirtualizationFirmwareEnabled = $true
            SecondLevelAddressTranslationExtensions = $true
            HyperVisorPresent = $true
            VirtualMachinePlatformState = 'Enabled'
            HypervisorPlatformState = 'Disabled'
            MicrosoftHyperVState = 'Disabled'
            MicrosoftHyperVAllState = 'Disabled'
            BcdHypervisorLaunchType = 'Auto'
        }
        $result = Get-ClagnosNestedVirtualizationGuestValidation -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'samplevm' -OsType 'windows'
        Assert-True -Condition ([bool]$result.Known) -Message 'Nested virtualization guest validation must return a known result when run-command succeeds.'
        Assert-True -Condition ([bool]$result.Enabled) -Message 'Nested virtualization must be available when VMX, firmware virtualization, and SLAT are exposed to the guest.'
        Assert-True -Condition ((@($result.Evidence) -join "`n") -match [regex]::Escape('CpuVirtualizationExtensionsExposed=True')) -Message 'Guest evidence must explicitly report exposed CPU virtualization extensions.'
        Assert-True -Condition ((@($result.Evidence) -join "`n") -match [regex]::Escape('HyperVisorPresent=True')) -Message 'Nested virtualization guest validation must record active hypervisor evidence.'
        Assert-True -Condition ((@($result.Evidence) -join "`n") -match [regex]::Escape('VirtualMachinePlatformState=Enabled')) -Message 'Nested virtualization guest validation must record virtualization platform feature state.'

        # Mirrors the live vc1 check: Azure's outer hypervisor is present and
        # VirtualMachinePlatform is enabled, but this B-series guest has no
        # nested VMX/SLAT extensions exposed to it.
        $script:NestedGuestValidationFixture.VMMonitorModeExtensions = $false
        $script:NestedGuestValidationFixture.VirtualizationFirmwareEnabled = $false
        $script:NestedGuestValidationFixture.SecondLevelAddressTranslationExtensions = $false
        $result = Get-ClagnosNestedVirtualizationGuestValidation -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'samplevm' -OsType 'windows'
        Assert-True -Condition ([bool]$result.Known -and -not [bool]$result.Enabled) -Message 'HyperVisorPresent plus an enabled VirtualMachinePlatform feature must not override missing nested CPU extensions.'
        Assert-True -Condition ((@($result.Evidence) -join "`n") -match [regex]::Escape('CpuVirtualizationExtensionsExposed=False')) -Message 'A negative guest validation must preserve the absent CPU extension evidence.'
    }
    finally {
        Remove-Item Function:\Invoke-ClagnosVmRunCommandJson -ErrorAction SilentlyContinue
        Remove-Variable -Name NestedGuestValidationFixture -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Post-deploy feature enablement fails when nested virtualization cannot be verified" -Action {
    try {
        $script:FeatureEnablementFailureAzCalls = @()
        function Invoke-TrackedAction {
            param([string]$Label, [scriptblock]$Action)
            & $Action
            return [pscustomobject]@{ Label = $Label }
        }
        function Wait-ClagnosProvisioningSucceeded {
            param([string]$ResourceGroup, [string]$VmName, [int]$MaxAttempts, [int]$DelaySeconds)
            return [pscustomobject]@{
                Ready = $true
                Snapshot = [pscustomobject]@{
                    ProvisioningStateCode = 'ProvisioningState/succeeded'
                    ProvisioningStateDisplay = 'Provisioning succeeded'
                    PowerStateCode = 'PowerState/running'
                    PowerStateDisplay = 'VM running'
                }
            }
        }
        function Get-ClagnosHibernationSupportInfo {
            param([string]$Location, [string]$VmSize)
            return [pscustomobject]@{
                Known = $true
                Supported = $true
                Evidence = @('HibernationSupported=true')
                Message = 'hibernation-supported'
            }
        }
        function Get-ClagnosNestedVirtualizationSupportInfo {
            param([string]$Location, [string]$VmSize)
            return [pscustomobject]@{
                Known = $false
                Supported = $false
                Evidence = @()
                Message = 'nested-capability-inconclusive'
            }
        }
        function Get-ClagnosNestedVirtualizationGuestValidation {
            param([string]$ResourceGroup, [string]$VmName, [string]$OsType, [int]$MaxAttempts, [int]$RetryDelaySeconds)
            return [pscustomobject]@{
                Known = $true
                Enabled = $false
                Evidence = @('VirtualizationFirmwareEnabled=False')
                Data = $null
                ErrorMessage = ''
            }
        }
        function az {
            $line = @($args) -join ' '
            $script:FeatureEnablementFailureAzCalls += ,$line
            if ($line -match [regex]::Escape('securityProfile.securityType')) {
                $global:LASTEXITCODE = 0
                return '{"securityType":"Standard","secureBoot":true,"vTpm":true}'
            }
            if ($line -match [regex]::Escape('additionalCapabilities.hibernationEnabled')) {
                $global:LASTEXITCODE = 0
                return 'true'
            }
            if ($line -match [regex]::Escape('additionalCapabilities.nestedVirtualization')) {
                $global:LASTEXITCODE = 0
                return ''
            }

            $global:LASTEXITCODE = 0
            return ''
        }

        $threw = $false
        try {
            Invoke-ClagnosPostDeployFeatureEnablement -Context @{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
                VmDiskName = 'disk-samplevm'
                AzLocation = 'austriaeast'
                VmSize = 'Standard_D4as_v5'
                VmSecurityType = 'Standard'
                VmEnableHibernation = $true
                VmEnableNestedVirtualization = $true
            } -VmCreatedThisRun:$true | Out-Null
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*nested virtualization*') -Message 'Nested verification failure should mention nested virtualization.'
        }

        Assert-True -Condition $threw -Message 'Feature enablement must fail when nested virtualization stays unverified.'
    }
    finally {
        foreach ($functionName in @(
            'Invoke-TrackedAction',
            'Wait-ClagnosProvisioningSucceeded',
            'Get-ClagnosHibernationSupportInfo',
            'Get-ClagnosNestedVirtualizationSupportInfo',
            'Get-ClagnosNestedVirtualizationGuestValidation',
            'az'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name FeatureEnablementFailureAzCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "VM create security args are omitted for existing VMs" -Action {
    try {
        function Test-ClagnosAzResourceExists {
            param([string[]]$AzArgs)
            return ([string]$AzArgs[-1] -eq 'existingvm')
        }

        $context = @{
            VmSecurityType = 'Standard'
            VmEnableSecureBoot = $false
            VmEnableVtpm = $false
        }

        $existingVmArgs = @(Get-ClagnosCreateSecurityArgumentsForCurrentVmState -Context $context -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'existingvm' -SuppressNotice)
        $newVmArgs = @(Get-ClagnosCreateSecurityArgumentsForCurrentVmState -Context $context -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'newvm' -SuppressNotice)

        Assert-True -Condition ($existingVmArgs.Count -eq 0) -Message 'Existing VMs must omit security-type create arguments.'
        Assert-True -Condition ($newVmArgs.Count -ge 2) -Message 'New VMs must keep security-type create arguments.'
        Assert-True -Condition ($newVmArgs -contains '--security-type') -Message 'New VMs must keep the security-type argument.'
    }
    finally {
        Remove-Item Function:\Test-ClagnosAzResourceExists -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "VM create step tolerates a transient non-zero create when the new VM appears after probing" -Action {
    $script:VmCreateProbeCount = 0
    $script:VmCreateDetailedShowCalled = $false
    $script:VmCreateActionCalled = $false

    try {
        function Show-ClagnosStepFirstUseValues { param([string]$StepLabel, [hashtable]$Context, [string[]]$Keys, [hashtable]$ExtraValues) }
        function Invoke-TrackedAction {
            param([string]$Label, [scriptblock]$Action)
            & $Action
        }
        function Invoke-ClagnosPostDeployFeatureEnablement {
            param([hashtable]$Context, [switch]$VmCreatedThisRun)
            return [pscustomobject]@{
                HibernationAttempted = $false
                HibernationEnabled = $false
                HibernationMessage = ''
                NestedAttempted = $false
                NestedEnabled = $false
                NestedMessage = ''
            }
        }
        function Test-ClagnosAzResourceExists {
            param([string[]]$AzArgs)
            $script:VmCreateProbeCount++
            return $true
        }
        function az {
            $line = @($args) -join ' '
            if ($line -match [regex]::Escape('vm list')) {
                $global:LASTEXITCODE = 0
                return ''
            }
            if ($line -match [regex]::Escape('--query id')) {
                $global:LASTEXITCODE = 0
                return '/subscriptions/test/resourceGroups/rg-samplevm-ate1-g1/providers/Microsoft.Compute/virtualMachines/samplevm'
            }
            if ($line -match [regex]::Escape('vm show -g rg-samplevm-ate1-g1 -n samplevm -d')) {
                $script:VmCreateDetailedShowCalled = $true
                $global:LASTEXITCODE = 0
                return '{"id":"/subscriptions/test/resourceGroups/rg-samplevm-ate1-g1/providers/Microsoft.Compute/virtualMachines/samplevm"}'
            }

            $global:LASTEXITCODE = 0
            return ''
        }

        $result = Invoke-ClagnosVmCreateStep -Context @{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        } -ExecutionMode 'default' -CreateVmAction {
            $script:VmCreateActionCalled = $true
            $global:LASTEXITCODE = 1
            return ''
        }

        Assert-True -Condition $script:VmCreateActionCalled -Message 'VM create step must run the create action.'
        Assert-True -Condition ($script:VmCreateProbeCount -ge 1) -Message 'VM create step must probe for a VM that may have landed after a non-zero create result.'
        Assert-True -Condition $script:VmCreateDetailedShowCalled -Message 'VM create step must recover through az vm show -d after the VM appears.'
        Assert-True -Condition ([string]$result.VmId -eq '/subscriptions/test/resourceGroups/rg-samplevm-ate1-g1/providers/Microsoft.Compute/virtualMachines/samplevm') -Message 'VM create step must keep the recovered VM id.'
        Assert-True -Condition ([bool]$result.VmCreateInvoked) -Message 'VM create step must still report the create action as invoked.'
        Assert-True -Condition ([bool]$result.VmCreatedThisRun) -Message 'VM create step must classify the recovered VM as newly created.'
    }
    finally {
        foreach ($functionName in @(
            'Show-ClagnosStepFirstUseValues',
            'Invoke-TrackedAction',
            'Invoke-ClagnosPostDeployFeatureEnablement',
            'Test-ClagnosAzResourceExists',
            'az'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name VmCreateProbeCount -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name VmCreateDetailedShowCalled -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name VmCreateActionCalled -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Create runtime keeps fresh-target overrides for a fresh target" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @(
        'Get-ClagnosRepoRoot',
        'Read-DotEnvFile'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile {
        param([string]$Path)
        return @{
            RESOURCE_GROUP = 'rg-stalevm-ate1-g4'
            VM_NAME = 'seedvm'
        }
    }

    try {
        $runtime = New-ClagnosCreateCommandRuntime -Options @{
            auto = $true
            'vm-name' = 'samplevm'
            'vm-region' = 'swedencentral'
            'vm-size' = 'Standard_D4as_v5'
        } -WindowsFlag -LinuxFlag:$false -AutoMode

        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.SELECTED_VM_NAME -eq 'samplevm') -Message "Create runtime must keep the requested selected VM name override."
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.SELECTED_AZURE_REGION -eq 'swedencentral') -Message "Create runtime must keep the requested selected Azure region override."
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.VM_SIZE -eq 'Standard_D4as_v5') -Message "Create runtime must keep the requested VM size override."
        Assert-True -Condition (-not $runtime.InitialConfigOverrides.ContainsKey('SELECTED_RESOURCE_GROUP')) -Message "Create runtime must not reuse an existing managed resource group override."
        Assert-True -Condition ([string]$runtime.ActionPlan.Target -eq 'vm-summary') -Message "Create runtime without step selectors must default to the full action plan."
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Read-DotEnvFile'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Create runtime reuses the existing managed target for vm-init resume windows" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @(
        'Get-ClagnosRepoRoot',
        'Read-DotEnvFile',
        'Get-ConfigValue',
        'Get-ClagnosCliOptionText',
        'Get-ClagnosCliOptionBool',
        'Resolve-ClagnosActionPlan',
        'Test-ClagnosResourceGroupManaged',
        'Get-ClagnosVmNamesForResourceGroup',
        'Test-ClagnosAzResourceExists',
        'Get-ClagnosResourceGroupLocation',
        'Get-ClagnosManagedTargetOsType',
        'Get-ClagnosVmNetworkDescriptor',
        'Get-ClagnosResolvedSubscriptionContext',
        'Set-ClagnosConfigValueSource',
        'Get-ClagnosManagedVmMatchRows'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile {
        param([string]$Path)
        return @{
            SELECTED_VM_NAME = 'samplevm'
            SELECTED_RESOURCE_GROUP = ''
            SELECTED_AZURE_REGION = 'swedencentral'
            SELECTED_VM_OS = 'windows'
            WIN_VM_SIZE = 'Standard_D4as_v5'
        }
    }
    function Get-ConfigValue {
        param([hashtable]$Config,[string]$Key,[string]$DefaultValue)
        if ($Config.ContainsKey($Key)) { return [string]$Config[$Key] }
        return [string]$DefaultValue
    }
    function Get-ClagnosCliOptionText {
        param([hashtable]$Options,[string]$Name)
        if ($Options.ContainsKey($Name)) { return [string]$Options[$Name] }
        return ''
    }
    function Get-ClagnosCliOptionBool {
        param([hashtable]$Options,[string]$Name,[bool]$DefaultValue)
        if ($Options.ContainsKey($Name)) { return [bool]$Options[$Name] }
        return [bool]$DefaultValue
    }
    function Resolve-ClagnosActionPlan {
        param([string]$CommandName,[hashtable]$Options)
        return [pscustomobject]@{
            Mode = 'range'
            Target = 'vm-summary'
            Actions = @('vm-init','vm-update','vm-summary')
        }
    }
    function Test-ClagnosResourceGroupManaged { param([string]$ResourceGroup) return $false }
    function Get-ClagnosVmNamesForResourceGroup { param([string]$ResourceGroup) return @('samplevm') }
    function Test-ClagnosAzResourceExists { param([string[]]$AzArgs) return $true }
    function Get-ClagnosResourceGroupLocation { param([string]$ResourceGroup) return 'austriaeast' }
    function Get-ClagnosManagedTargetOsType { param([string]$ResourceGroup,[string]$VmName) return 'windows' }
    function Get-ClagnosVmNetworkDescriptor {
        param([string]$ResourceGroup,[string]$VmName)
        return [pscustomobject]@{
            OsDiskName = 'disk-samplevm-ate1-n7'
            NicName = 'nic-samplevm-ate1-n6'
            PublicIpName = 'ip-samplevm-ate1-n5'
            NsgName = 'nsg-samplevm-ate1-n3'
            VnetName = 'net-samplevm-ate1-n1'
            SubnetName = 'subnet-samplevm-ate1-n2'
        }
    }
    function Get-ClagnosResolvedSubscriptionContext {
        return [pscustomobject]@{
            SubscriptionId = '11111111-1111-1111-1111-111111111111'
            SubscriptionName = 'Example Sub'
        }
    }
    function Set-ClagnosConfigValueSource { param([string]$Key,[string]$Source) }
    function Get-ClagnosManagedVmMatchRows {
        param([string]$VmName)
        return @([pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        })
    }

    try {
        $runtime = New-ClagnosCreateCommandRuntime -Options @{ auto = $true; 'step-from' = 'vm-init' } -WindowsFlag -LinuxFlag:$false -AutoMode

        Assert-True -Condition ([string]$runtime.Step1OperationName -eq 'update') -Message 'Create vm-init resume windows must switch step-1 context resolution to existing-target mode.'
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.SELECTED_RESOURCE_GROUP -eq 'rg-samplevm-ate1-g1') -Message 'Create vm-init resume windows must reuse the existing managed resource group.'
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.SELECTED_AZURE_REGION -eq 'austriaeast') -Message 'Create vm-init resume windows must reuse the actual managed resource group location.'
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.PUBLIC_IP_NAME -eq 'ip-samplevm-ate1-n5') -Message 'Create vm-init resume windows must lock the existing managed network resource names.'
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides.VM_DISK_NAME -eq 'disk-samplevm-ate1-n7') -Message 'Create vm-init resume windows must reuse the existing managed OS disk name.'
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Read-DotEnvFile',
            'Get-ConfigValue',
            'Get-ClagnosCliOptionText',
            'Get-ClagnosCliOptionBool',
            'Resolve-ClagnosActionPlan',
            'Test-ClagnosResourceGroupManaged',
            'Get-ClagnosVmNamesForResourceGroup',
            'Test-ClagnosAzResourceExists',
            'Get-ClagnosResourceGroupLocation',
            'Get-ClagnosManagedTargetOsType',
            'Get-ClagnosVmNetworkDescriptor',
            'Get-ClagnosResolvedSubscriptionContext',
            'Set-ClagnosConfigValueSource',
            'Get-ClagnosManagedVmMatchRows'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Create auto mode resolves from selected env values" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile')) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile {
        param([string]$Path)
        return @{
            SELECTED_VM_OS = 'windows'
            SELECTED_VM_NAME = 'samplevm'
            SELECTED_AZURE_REGION = 'swedencentral'
            WIN_VM_SIZE = 'Standard_D4as_v5'
        }
    }

    try {
        $runtime = New-ClagnosCreateCommandRuntime -Options @{ auto = $true } -WindowsFlag:$false -LinuxFlag:$false -AutoMode
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides['SELECTED_VM_NAME'] -eq 'samplevm') -Message 'Create auto mode must resolve VM name from SELECTED_VM_NAME.'
        Assert-True -Condition ([string]$runtime.InitialConfigOverrides['SELECTED_AZURE_REGION'] -eq 'swedencentral') -Message 'Create auto mode must resolve Azure region from SELECTED_AZURE_REGION.'
    }
    finally {
        foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Create auto mode fails when selected values are incomplete" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile')) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile {
        param([string]$Path)
        return @{
            SELECTED_VM_OS = 'windows'
            SELECTED_VM_NAME = 'samplevm'
            SELECTED_AZURE_REGION = 'swedencentral'
            WIN_VM_SIZE = ''
        }
    }

    try {
        $threw = $false
        try {
            New-ClagnosCreateCommandRuntime -Options @{ auto = $true } -WindowsFlag:$false -LinuxFlag:$false -AutoMode | Out-Null
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*SELECTED_VM_NAME or --vm-name*' -or [string]$_.Exception.Message -like '*WIN_VM_SIZE*') -Message 'Create auto mode failure must explain the missing resolved selection values.'
        }
        Assert-True -Condition $threw -Message 'Create auto mode must fail when the selected env values are incomplete.'
    }
    finally {
        foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Update runtime requires an existing managed VM before orchestration starts" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @(
        'Get-ClagnosRepoRoot',
        'Read-DotEnvFile',
        'Resolve-ClagnosTargetResourceGroup',
        'Resolve-ClagnosTargetVmName',
        'Test-ClagnosAzResourceExists'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile {
        param([string]$Path)
        return @{
            RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
            VM_NAME = 'samplevm'
        }
    }
    function Resolve-ClagnosTargetResourceGroup {
        param([hashtable]$Options, [switch]$AutoMode, [string]$DefaultResourceGroup, [string]$VmName, [string]$OperationName)
        return 'rg-samplevm-ate1-g1'
    }
    function Resolve-ClagnosTargetVmName {
        param([string]$ResourceGroup, [string]$DefaultVmName, [switch]$AutoMode, [string]$OperationName)
        return 'samplevm'
    }
    function Test-ClagnosAzResourceExists {
        param([string[]]$AzArgs)
        return $false
    }

    try {
        $threw = $false
        try {
            New-ClagnosUpdateCommandRuntime -Options @{ auto = $true; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' } -WindowsFlag -LinuxFlag:$false -AutoMode | Out-Null
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*was not found in managed resource group*') -Message "Update runtime failure must explain that the target VM does not exist."
        }

        Assert-True -Condition $threw -Message "Update runtime must fail early when the target VM does not exist."
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Read-DotEnvFile',
            'Resolve-ClagnosTargetResourceGroup',
            'Resolve-ClagnosTargetVmName',
            'Test-ClagnosAzResourceExists'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Update auto mode requires a resolvable selected resource group" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile')) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile {
        param([string]$Path)
        return @{
            SELECTED_RESOURCE_GROUP = ''
            SELECTED_VM_NAME = ''
        }
    }

    try {
        $threw = $false
        try {
            New-ClagnosUpdateCommandRuntime -Options @{ auto = $true } -WindowsFlag:$false -LinuxFlag:$false -AutoMode | Out-Null
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*SELECTED_RESOURCE_GROUP*') -Message "Update auto mode failure must explain the missing selected resource group."
        }

        Assert-True -Condition $threw -Message "Update auto mode must fail when the selected resource group is missing."
    }
    finally {
        foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Managed naming uses global gX and sequential global nX allocation" -Action {
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @(
        'Get-ClagnosManagedResourceGroupRows',
        'az'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosManagedResourceGroupRows {
        return @(
            [pscustomobject]@{ name = 'rg-examplevm-ate1-g1' },
            [pscustomobject]@{ name = 'rg-examplevm-sec1-g4' }
        )
    }
    function az {
        $global:LASTEXITCODE = 0
        $argText = (@($args) | ForEach-Object { [string]$_ }) -join ' '
        if ($argText -like 'resource list -g rg-examplevm-ate1-g1*') {
            return @(
                'net-examplevm-ate1-n7'
                'nic-examplevm-ate1-n8'
            )
        }
        if ($argText -like 'resource list -g rg-examplevm-sec1-g4*') {
            return @(
                'ip-examplevm-sec1-n9'
                'disk-examplevm-sec1-n10'
            )
        }
        return @()
    }

    try {
        $nextGroupIndex = Get-ClagnosNextManagedResourceGroupIndex -NamePrefix ''
        Assert-True -Condition ($nextGroupIndex -eq 5) -Message "Managed resource group index must be global across all managed resource groups."
        $nextGroupName = Resolve-ClagnosResourceGroupNameFromTemplate -Template 'rg-{SELECTED_VM_NAME}-{REGION_CODE}-g{N}' -VmName 'examplevm' -RegionCode 'sec1' -UseNextIndex
        Assert-True -Condition ([string]$nextGroupName -eq 'rg-examplevm-sec1-g5') -Message "Managed resource group name generation must use the next global gX value."

        $allocator = New-ClagnosManagedResourceIndexAllocator
        $vnetName = Resolve-ClagnosNameFromTemplate -Template 'net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}' -ResourceType 'net' -VmName 'examplevm' -RegionCode 'sec1' -ResourceGroup 'rg-examplevm-sec1-g5' -UseNextIndex -IndexAllocator $allocator -LogicalName 'VNET_NAME'
        $subnetName = Resolve-ClagnosNameFromTemplate -Template 'subnet-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}' -ResourceType 'subnet' -VmName 'examplevm' -RegionCode 'sec1' -ResourceGroup 'rg-examplevm-sec1-g5' -UseNextIndex -IndexAllocator $allocator -LogicalName 'SUBNET_NAME'

        Assert-True -Condition ([string]$vnetName -eq 'net-examplevm-sec1-n11') -Message "First generated managed resource id must continue after the global max nX value."
        Assert-True -Condition ([string]$subnetName -eq 'subnet-examplevm-sec1-n12') -Message "Managed resource ids must stay sequential and unique within the same provisioning plan."

        $legacyTemplateFailed = $false
        try {
            $null = Resolve-ClagnosResourceGroupNameFromTemplate -Template 'rg-{VM_NAME}-{REGION_CODE}-g{N}' -VmName 'examplevm' -RegionCode 'sec1' -UseNextIndex
        }
        catch {
            $legacyTemplateFailed = $true
            Assert-True -Condition ($_.Exception.Message -like '*unresolved placeholder token*') -Message "Legacy resource-group placeholders must fail with a precise unresolved-token error."
        }
        Assert-True -Condition $legacyTemplateFailed -Message "Legacy resource-group templates must be rejected."

        $legacyResourceTemplateFailed = $false
        try {
            $null = Resolve-ClagnosNameFromTemplate -Template 'net-{VM_NAME}-{REGION_CODE}-n{N}' -ResourceType 'net' -VmName 'examplevm' -RegionCode 'sec1' -ResourceGroup 'rg-examplevm-sec1-g5' -UseNextIndex -IndexAllocator $allocator -LogicalName 'VNET_NAME'
        }
        catch {
            $legacyResourceTemplateFailed = $true
            Assert-True -Condition ($_.Exception.Message -like '*unresolved placeholder token*') -Message "Legacy managed resource placeholders must fail with a precise unresolved-token error."
        }
        Assert-True -Condition $legacyResourceTemplateFailed -Message "Legacy managed resource templates must be rejected."

        $reRegisterIndex = Register-ClagnosManagedResourceNameIndex -Allocator $allocator -Name 'net-examplevm-sec1-n11' -LogicalName 'VNET_NAME'
        Assert-True -Condition ($reRegisterIndex -eq 11) -Message "Managed resource name registration must be idempotent for the same logical resource."

        $threw = $false
        try {
            Register-ClagnosManagedResourceNameIndex -Allocator $allocator -Name 'nic-examplevm-sec1-n12' -LogicalName 'NIC_NAME' | Out-Null
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message "Managed resource name registration must reject duplicate nX ids within the same provisioning plan."
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosManagedResourceGroupRows',
            'az'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Managed public DNS label uses vm_name-vm{id} and skips stale label collisions" -Action {
    $firstLabel = Resolve-ClagnosPublicDnsLabel -VmName 'test' -ManagedPublicIpRows @(
        [pscustomobject]@{
            dnsSettings = [pscustomobject]@{}
            ipConfiguration = [pscustomobject]@{ id = '' }
        }
    )
    Assert-True -Condition ([string]$firstLabel -eq 'test-vm1') -Message 'Managed public DNS label must start at vm1 when no managed public IPs are attached yet.'

    $managedPublicIpRows = @(
        [pscustomobject]@{
            dnsSettings = [pscustomobject]@{ domainNameLabel = 'test-vm1' }
            ipConfiguration = [pscustomobject]@{ id = '/subscriptions/test/resourceGroups/rg-a/providers/Microsoft.Network/networkInterfaces/nic-a/ipConfigurations/ipconfig1' }
        },
        [pscustomobject]@{
            dnsSettings = [pscustomobject]@{ domainNameLabel = 'test-vm2' }
            ipConfiguration = [pscustomobject]@{ id = '/subscriptions/test/resourceGroups/rg-b/providers/Microsoft.Network/networkInterfaces/nic-b/ipConfigurations/ipconfig1' }
        },
        [pscustomobject]@{
            dnsSettings = [pscustomobject]@{ domainNameLabel = 'test-vm3' }
            ipConfiguration = [pscustomobject]@{ id = '' }
        }
    )
    $collisionSkippedLabel = Resolve-ClagnosPublicDnsLabel -VmName 'test' -ManagedPublicIpRows $managedPublicIpRows
    Assert-True -Condition ([string]$collisionSkippedLabel -eq 'test-vm4') -Message 'Managed public DNS label must skip stale managed label collisions and advance to the next free vm id.'

    $longVmName = ('examplevmsegment' * 5)
    $truncatedLabel = Resolve-ClagnosPublicDnsLabel -VmName $longVmName -PreferredVmId 12345 -ManagedPublicIpRows @()
    Assert-True -Condition ($truncatedLabel.Length -le 63) -Message 'Managed public DNS label must stay within Azure length limits.'
    Assert-True -Condition ($truncatedLabel -match '^[a-z0-9][a-z0-9-]*[a-z0-9]$') -Message 'Managed public DNS label must stay Azure-safe after normalization.'
    Assert-True -Condition ($truncatedLabel -like '*-vm12345') -Message 'Managed public DNS label truncation must preserve the vm{id} suffix.'
}

Invoke-Test -Name "Create allows same VM name in other resource groups but rejects target-group duplicates" -Action {
    try {
        function az {
            $line = @($args) -join ' '
            if ($line -like 'resource list*') {
                $global:LASTEXITCODE = 0
                return @'
[
  {"name":"examplevm","resourceGroup":"rg-examplevm-sec1-g1","id":"/subscriptions/test/resourceGroups/rg-examplevm-sec1-g1/providers/Microsoft.Compute/virtualMachines/examplevm"},
  {"name":"examplevm","resourceGroup":"rg-examplevm-ate1-g2","id":"/subscriptions/test/resourceGroups/rg-examplevm-ate1-g2/providers/Microsoft.Compute/virtualMachines/examplevm"}
]
'@
            }

            $global:LASTEXITCODE = 0
            return '[]'
        }

        Assert-ClagnosVmNameConflictFree -VmName 'examplevm' -TargetResourceGroup 'rg-examplevm-ate1-g3'

        $threw = $false
        try {
            Assert-ClagnosVmNameConflictFree -VmName 'examplevm' -TargetResourceGroup 'rg-examplevm-ate1-g2'
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message 'Create must still reject a VM name that already exists in the target resource group.'
    }
    finally {
        Remove-Item Function:\az -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Create step1 ignores persisted managed resource names and uses templates" -Action {
    $configMap = @{
        VNET_NAME = 'net-examplevm-sec1-n1'
        VNET_NAME_TEMPLATE = 'net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
        NIC_NAME = 'nic-examplevm-sec1-n1'
        NIC_NAME_TEMPLATE = 'nic-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    }

    $createVnetSeed = Get-ClagnosManagedNameSeed -ConfigMap $configMap -ConfigOverrides @{} -OperationName 'create' -NameKey 'VNET_NAME' -TemplateKey 'VNET_NAME_TEMPLATE' -TemplateDefaultValue 'net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $createNicSeed = Get-ClagnosManagedNameSeed -ConfigMap $configMap -ConfigOverrides @{} -OperationName 'create' -NameKey 'NIC_NAME' -TemplateKey 'NIC_NAME_TEMPLATE' -TemplateDefaultValue 'nic-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'
    $updateVnetSeed = Get-ClagnosManagedNameSeed -ConfigMap $configMap -ConfigOverrides @{} -OperationName 'update' -NameKey 'VNET_NAME' -TemplateKey 'VNET_NAME_TEMPLATE' -TemplateDefaultValue 'net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}'

    Assert-True -Condition (-not [bool]$createVnetSeed.Explicit) -Message "Create step1 must not treat persisted VNET_NAME as an explicit managed resource target."
    Assert-True -Condition ([string]$createVnetSeed.Value -eq 'net-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}') -Message "Create step1 must fall back to the selected VM VNET template when a persisted managed name exists."
    Assert-True -Condition (-not [bool]$createNicSeed.Explicit) -Message "Create step1 must not treat persisted NIC_NAME as an explicit managed resource target."
    Assert-True -Condition ([string]$createNicSeed.Value -eq 'nic-{SELECTED_VM_NAME}-{REGION_CODE}-n{N}') -Message "Create step1 must fall back to the selected VM NIC template when a persisted managed name exists."
    Assert-True -Condition ([bool]$updateVnetSeed.Explicit) -Message "Update step1 must continue treating persisted VNET_NAME as the existing managed target."
    Assert-True -Condition ([string]$updateVnetSeed.Value -eq 'net-examplevm-sec1-n1') -Message "Update step1 must preserve the persisted managed resource name for the existing target."
}

Invoke-Test -Name "VM create step redeploys existing VMs in update mode" -Action {
    $script:VmUpdateRedeployInvocation = $null

    try {
        function Show-ClagnosStepFirstUseValues { param([string]$StepLabel, [hashtable]$Context, [string[]]$Keys, [hashtable]$ExtraValues) }
        function Invoke-TrackedAction {
            param([string]$Label, [scriptblock]$Action)
            & $Action
        }
        function Invoke-ClagnosPostDeployFeatureEnablement {
            param([hashtable]$Context, [switch]$VmCreatedThisRun)
            return [pscustomobject]@{
                HibernationAttempted = $false
                HibernationEnabled = $false
                HibernationMessage = ''
                NestedAttempted = $false
                NestedEnabled = $false
                NestedMessage = ''
            }
        }
        function Invoke-ClagnosUpdateVmRedeploy {
            param([string]$ResourceGroup, [string]$VmName, [switch]$AutoMode)
            $script:VmUpdateRedeployInvocation = [pscustomobject]@{
                ResourceGroup = $ResourceGroup
                VmName = $VmName
                AutoMode = [bool]$AutoMode
            }
        }
        function az {
            $line = @($args) -join ' '
            if ($line -match [regex]::Escape('vm list')) {
                $global:LASTEXITCODE = 0
                return 'samplevm'
            }

            $global:LASTEXITCODE = 0
            return ''
        }

        $result = Invoke-ClagnosVmCreateStep -Context @{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        } -AutoMode -ExecutionMode 'update' -CreateVmAction {
            $global:LASTEXITCODE = 0
            return '{"id":"/subscriptions/test/resourceGroups/rg-samplevm-ate1-g1/providers/Microsoft.Compute/virtualMachines/samplevm"}'
        }

        Assert-True -Condition ($null -ne $script:VmUpdateRedeployInvocation) -Message "Update-mode create step must trigger VM redeploy for an existing VM."
        Assert-True -Condition ([string]$script:VmUpdateRedeployInvocation.ResourceGroup -eq 'rg-samplevm-ate1-g1') -Message "Update-mode redeploy must target the existing resource group."
        Assert-True -Condition ([string]$script:VmUpdateRedeployInvocation.VmName -eq 'samplevm') -Message "Update-mode redeploy must target the existing VM."
        Assert-True -Condition (-not [bool]$result.VmCreatedThisRun) -Message "Existing update-mode VM create must not be reported as a fresh VM creation."
    }
    finally {
        foreach ($functionName in @(
            'Show-ClagnosStepFirstUseValues',
            'Invoke-TrackedAction',
            'Invoke-ClagnosPostDeployFeatureEnablement',
            'Invoke-ClagnosUpdateVmRedeploy',
            'az'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name VmUpdateRedeployInvocation -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Resize command accepts vm-name and platform flags" -Action {
    Assert-ClagnosCommandOptions -CommandName 'resize' -Options @{ 'vm-name' = 'samplevm'; 'vm-size' = 'Standard_D4as_v5'; group = 'rg-samplevm-ate1-g1' }
    Assert-ClagnosCommandOptions -CommandName 'resize' -Options @{ 'vm-name' = 'samplevm'; 'vm-size' = 'Standard_D2as_v5'; group = 'rg-samplevm-ate1-g1'; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'resize' -Options @{ 'vm-name' = 'samplevm'; 'vm-size' = 'Standard_D2as_v5'; group = 'rg-samplevm-ate1-g1'; linux = $true }
}

Invoke-Test -Name "Resize command accepts disk-size and disk intent flags" -Action {
    Assert-ClagnosCommandOptions -CommandName 'resize' -Options @{ 'vm-name' = 'samplevm'; group = 'rg-samplevm-ate1-g1'; 'disk-size' = '196gb'; expand = $true }
    Assert-ClagnosCommandOptions -CommandName 'resize' -Options @{ 'vm-name' = 'samplevm'; group = 'rg-samplevm-ate1-g1'; 'disk-size' = '98304mb'; expand = $true; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'resize' -Options @{ 'vm-name' = 'samplevm'; group = 'rg-samplevm-ate1-g1'; 'disk-size' = '64gb'; shrink = $true; linux = $true }
}

Invoke-Test -Name "Task run and exec command accept the direct target contract" -Action {
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ 'run-vm-init' = '01'; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'task' -Options @{ 'run-vm-update' = '28'; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; windows = $true }
    Assert-ClagnosCommandOptions -CommandName 'exec' -Options @{ command = 'Get-Date'; group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' }
}

Invoke-Test -Name "Do command accepts vm-name and valid vm-action" -Action {
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ 'vm-name' = 'samplevm'; 'vm-action' = 'status' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'resume' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'shutdown' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'power-off' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'reset' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'deallocate' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'hibernate-deallocate' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'hibernate-stop' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'reapply' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'redeploy' }
    Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ 'vm-action' = '' }
}

Invoke-Test -Name "Target-requiring commands reject legacy vm option" -Action {
    foreach ($commandName in @('move','set','resize','do','connect','exec','task')) {
        $threw = $false
        try {
            if ($commandName -eq 'connect') {
                Assert-ClagnosCommandOptions -CommandName $commandName -Options @{ vm = 'samplevm'; ssh = $true }
            }
            elseif ($commandName -eq 'task') {
                Assert-ClagnosCommandOptions -CommandName $commandName -Options @{ vm = 'samplevm'; 'run-vm-update' = '10002' }
            }
            elseif ($commandName -eq 'exec') {
                Assert-ClagnosCommandOptions -CommandName $commandName -Options @{ vm = 'samplevm'; command = 'Get-Date' }
            }
            else {
                Assert-ClagnosCommandOptions -CommandName $commandName -Options @{ vm = 'samplevm' }
            }
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Legacy --vm must be rejected for command '{0}'." -f $commandName)
    }
}

Invoke-Test -Name "Do command rejects retired or unknown power actions" -Action {
    foreach ($actionName in @('release','sleep','hibernate')) {
        $threw = $false
        try {
            Assert-ClagnosCommandOptions -CommandName 'do' -Options @{ 'vm-action' = $actionName }
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Do command must reject unsupported action '{0}'." -f $actionName)
    }
}

Invoke-Test -Name "Do help, README, and interactive operations document lifecycle actions" -Action {
    $helpText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\cli\clagnos-help.ps1') -Raw)
    $readmeText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw)
    $uiText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'scripts\clagnos-cli.ps1') -Raw)

    Assert-True -Condition ($helpText -match [regex]::Escape('--vm-action=<status|start|resume|restart|reset|shutdown|stop|power-off|deallocate|hibernate-deallocate|hibernate-stop|reapply|redeploy>')) -Message 'CLI help must list all supported lifecycle actions.'
    Assert-True -Condition ($helpText -match [regex]::Escape('clagnos do --vm-action=reapply --group <resource-group> --vm-name <vm-name>')) -Message 'CLI help must show a reapply example.'
    Assert-True -Condition ($helpText -match [regex]::Escape('clagnos do --vm-action=redeploy --group <resource-group> --vm-name <vm-name>')) -Message 'CLI help must show a redeploy example.'
    Assert-True -Condition ($helpText -match [regex]::Escape('clagnos do --vm-action=hibernate-stop --group <resource-group> --vm-name <vm-name>')) -Message 'CLI help must show a hibernate-stop example.'
    Assert-True -Condition ($helpText -match [regex]::Escape('clagnos do --vm-action=hibernate-deallocate --group <resource-group> --vm-name <vm-name>')) -Message 'CLI help must show a hibernate-deallocate example.'
    Assert-True -Condition ($readmeText -match [regex]::Escape('Gives operators lifecycle commands for status, start/resume, restart/reset, shutdown, immediate power-off, reapply, redeploy, stop, deallocate, hibernate-stop, hibernate-deallocate')) -Message 'README must mention lifecycle actions in the command summary.'
    Assert-True -Condition ($readmeText -match [regex]::Escape('o: operations')) -Message 'README must describe the selected-VC operations shortcut.'
    Assert-True -Condition ($uiText -match [regex]::Escape("Write-Host 'o: operations'")) -Message 'Selected VC menu must expose the operations shortcut.'
    foreach ($lifecycleActionName in @('status','start','shutdown','hibernate-stop','hibernate-deallocate','resume','restart','power-off','reset','deallocate','reapply','redeploy')) {
        Assert-True -Condition ($uiText -match [regex]::Escape("Action = '$lifecycleActionName'")) -Message ("Operations menu must expose '{0}'." -f $lifecycleActionName)
    }
    Assert-True -Condition ($readmeText -match [regex]::Escape('.\cg.cmd do --vm-action=reapply --group=<resource-group> --vm-name=<vm-name>')) -Message 'README must include a reapply usage example.'
    Assert-True -Condition ($readmeText -match [regex]::Escape('.\cg.cmd do --vm-action=redeploy --group=<resource-group> --vm-name=<vm-name>')) -Message 'README must include a redeploy usage example.'
    Assert-True -Condition ($readmeText -match [regex]::Escape('.\cg.cmd do --vm-action=hibernate-stop --group=<resource-group> --vm-name=<vm-name>')) -Message 'README must include a hibernate-stop usage example.'
    Assert-True -Condition ($readmeText -match [regex]::Escape('.\cg.cmd do --vm-action=hibernate-deallocate --group=<resource-group> --vm-name=<vm-name>')) -Message 'README must include a hibernate-deallocate usage example.'
}

Invoke-Test -Name "Create update and resize docs reflect the current operator contract" -Action {
    $helpText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\cli\clagnos-help.ps1') -Raw)
    $readmeText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'README.md') -Raw)

    foreach ($fragment in @(
        'create targets a fresh managed resource group, its initial network resources, and one fresh VM',
        'asks for VM OS type first when --windows/--linux is omitted',
        'proposes the next global gX name plus globally unique nX resource ids',
        'Auto mode runs from the fully resolved selection set',
        'Auto mode runs from the resolved managed target',
        'interactive-only. It edits supported .env keys in sections',
        'supports --type and --group for managed inventory output',
        'show --group <resource-group> [--vm-name <vm-name>] [--subscription-id <subscription-id>]',
        'vm-summary always renders, even for partial step windows',
        '--disk-size requires exactly one intent flag: --expand or --shrink'
    )) {
        Assert-True -Condition ($helpText -match [regex]::Escape([string]$fragment)) -Message ("CLI help must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        '`create` now stays dedicated to one fresh managed resource group plus one fresh managed VM; use `delete` and then `create` when a destructive rebuild is intentional.',
        'Auto `create` succeeds when CLI overrides or `.env` `SELECTED_*` values plus the platform defaults resolve platform, VM name, Azure region, and VM size.',
        'Auto `update` resolves its target from CLI overrides first, then `.env` `SELECTED_RESOURCE_GROUP` and `SELECTED_VM_NAME`',
        'Purpose: review, edit, validate, preview, and save the supported `.env` contract through one interactive frontend.',
        'uses a picker for every finite or discoverable multi-option field',
        '`configure` can open without Azure sign-in, but its Azure-backed pickers stay read-only until `az login` is available',
        'Purpose: print read-only managed inventory sections for clagnos-tagged resource groups and resources.',
        'show --group=<resource-group> --vm-name=<vm-name>',
        'if `--windows` or `--linux` is omitted, interactive mode asks for the VM OS type first and then scopes size, disk, and image defaults to that selection',
        'Interactive `create` reviews the resource group and VM deployment steps; `initialize` and `update` have their own task-stage reviews.',
        '`configure` and `vm-summary` stay visible in `create` and `update` flows, even when partial step selection skips interior stages.',
        'Managed resource group ids use a global `gX` suffix that increments across all managed groups, regardless of region.',
        'Managed resource ids use a global `nX` suffix that increments across all generated managed resources and is never reused by another managed resource of any type.',
        '`create` never reuses an existing managed resource group or existing managed resource names, and `update` never falls through to an implicit fresh-create path.',
        '`list` gives a read-only managed inventory view across groups and resource types',
        '`configure` gives a safe interactive frontend for every supported `.env` key',
        '`--disk-size=... --shrink` is a non-mutating guidance path because Azure does not support shrinking an existing managed OS disk in place; the command prints supported rebuild and migration alternatives instead of risking disk integrity'
    )) {
        Assert-True -Condition ($readmeText -match [regex]::Escape([string]$fragment)) -Message ("README must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($legacyFragment in @(
        '--single-step',
        '--from-step',
        '--to-step',
        'Create, reuse, destructive rebuild',
        '.\cg.cmd group',
        '### `group`'
    )) {
        Assert-True -Condition (-not ($helpText -match [regex]::Escape([string]$legacyFragment))) -Message ("CLI help must not include retired fragment '{0}'." -f [string]$legacyFragment)
        Assert-True -Condition (-not ($readmeText -match [regex]::Escape([string]$legacyFragment))) -Message ("README must not include retired fragment '{0}'." -f [string]$legacyFragment)
    }
}

Invoke-Test -Name "Auto option scope contract" -Action {
    $invalidAutoCommands = @('configure','list','show','do','move','resize','set','exec','connect','help')
    foreach ($commandName in $invalidAutoCommands) {
        $threw = $false
        try {
            Assert-ClagnosCommandOptions -CommandName $commandName -Options @{ auto = $true }
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("--auto must be rejected for command '{0}'." -f $commandName)
    }

    Assert-ClagnosCommandOptions -CommandName 'create' -Options @{ auto = $true }
    Assert-ClagnosCommandOptions -CommandName 'update' -Options @{ auto = $true }
    Assert-ClagnosCommandOptions -CommandName 'delete' -Options @{ auto = $true; target = 'vm' }
}

Invoke-Test -Name "Resize direct request detection" -Action {
    Assert-True -Condition (Test-ClagnosResizeDirectRequest -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-size' = 'Standard_D4as_v5' }) -Message "Fully specified resize request must be treated as direct."
    Assert-True -Condition (Test-ClagnosResizeDirectRequest -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'disk-size' = '98304mb'; expand = $true }) -Message "Disk expand request with target group, VM, and disk size must be treated as direct."
    Assert-True -Condition (Test-ClagnosResizeDirectRequest -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'disk-size' = '64gb'; shrink = $true }) -Message "Disk shrink request with target group, VM, and disk size must be treated as direct."
    Assert-True -Condition (-not (Test-ClagnosResizeDirectRequest -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm' })) -Message "Resize request without vm-size must not be treated as direct."
    Assert-True -Condition (-not (Test-ClagnosResizeDirectRequest -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'disk-size' = '64gb' })) -Message "Disk resize request without an intent flag must not be treated as direct."
    Assert-True -Condition (-not (Test-ClagnosResizeDirectRequest -Options @{ group = 'rg-samplevm-ate1-g1'; vm = 'samplevm'; 'vm-size' = 'Standard_D4as_v5' })) -Message "Legacy vm option must not satisfy direct resize request detection."
}

Invoke-Test -Name "Resize operation request validates disk intent combinations" -Action {
    $expandRequest = Resolve-ClagnosResizeOperationRequest -Options @{ 'disk-size' = '98304mb'; expand = $true }
    Assert-True -Condition ([string]$expandRequest.Kind -eq 'disk') -Message "Disk resize request must resolve to the disk kind."
    Assert-True -Condition ([string]$expandRequest.Intent -eq 'expand') -Message "Disk resize request must keep expand intent."
    Assert-True -Condition ([int]$expandRequest.TargetDiskSizeGb -eq 96) -Message "MB disk resize request must round upward to whole GiB."

    $vmSizeRequest = Resolve-ClagnosResizeOperationRequest -Options @{ 'vm-size' = 'Standard_D4as_v5' }
    Assert-True -Condition ([string]$vmSizeRequest.Kind -eq 'vm-size') -Message "VM-size resize request must resolve to the vm-size kind."

    foreach ($invalidOptions in @(
        @{ 'disk-size' = '196gb'; expand = $true; shrink = $true },
        @{ 'disk-size' = '196gb' },
        @{ expand = $true },
        @{ 'vm-size' = 'Standard_D4as_v5'; 'disk-size' = '196gb'; expand = $true }
    )) {
        $threw = $false
        try {
            Resolve-ClagnosResizeOperationRequest -Options $invalidOptions | Out-Null
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message "Invalid disk resize option combination must be rejected."
    }
}

Invoke-Test -Name "Resize target disk size parser validates units and values" -Action {
    $gbRequest = Resolve-ClagnosResizeTargetDiskSize -Options @{ 'disk-size' = '196gb' }
    Assert-True -Condition ([int]$gbRequest.TargetDiskSizeGb -eq 196) -Message "GB disk-size request must keep the same numeric size."

    $mbRequest = Resolve-ClagnosResizeTargetDiskSize -Options @{ 'disk-size' = '1537mb' }
    Assert-True -Condition ([int]$mbRequest.TargetDiskSizeGb -eq 2) -Message "MB disk-size request must round upward to the next whole GiB."

    $tbRequest = Resolve-ClagnosResizeTargetDiskSize -Options @{ 'disk-size' = '1TB' }
    Assert-True -Condition ([int]$tbRequest.TargetDiskSizeGb -eq 1024) -Message "TB disk-size request must normalize to whole GiB."

    $minimumRequest = Resolve-ClagnosResizeTargetDiskSize -Options @{ 'disk-size' = '1MB' }
    Assert-True -Condition ([int]$minimumRequest.TargetDiskSizeGb -eq 1) -Message "The minimum 1MB text size must normalize to the minimum whole GiB."

    foreach ($invalidDiskSize in @('', '0gb', 'bad', '12tb', '4096gb', '1pb', '1,5gb')) {
        $threw = $false
        try {
            Resolve-ClagnosResizeTargetDiskSize -Options @{ 'disk-size' = $invalidDiskSize } | Out-Null
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message ("Invalid disk-size value '{0}' must be rejected." -f $invalidDiskSize)
    }
}

Invoke-Test -Name "TCP port specification accepts ranges and rejects malformed or oversized input" -Action {
    $specification = Resolve-ClagnosTcpPortSpecification -Text '80,3000-3300,3300-3310' -RequiredPorts @('22')
    Assert-True -Condition ($specification.CanonicalText -eq '22,80,3000-3310') -Message "TCP port ranges must sort, merge, and include required connection ports."
    Assert-True -Condition (@($specification.PortRanges).Count -eq 3) -Message "Normalized TCP port ranges must remain compact."
    Assert-True -Condition (@($specification.Ports).Count -eq 313) -Message "Expanded guest port targets must reflect the merged range and required port."

    foreach ($invalidSpecification in @('0','65536','500-300','1-65535','80,abc','')) {
        $threw = $false
        try { Resolve-ClagnosTcpPortSpecification -Text $invalidSpecification | Out-Null } catch { $threw = $true }
        Assert-True -Condition $threw -Message ("Invalid TCP port specification '{0}' must be rejected." -f $invalidSpecification)
    }
}

Invoke-Test -Name "Resize shrink path is non-mutating and prints supported alternatives" -Action {
    $script:ResizeShrinkAzCalls = @()
    $script:ResizeShrinkAlternativesShown = $false
    $script:ConfigOverrides = @{}
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Get-ClagnosRepoRoot',
        'Read-DotEnvFile',
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosResizeOsDiskContext',
        'Show-ClagnosResizeShrinkAlternatives',
        'Set-DotEnvValue',
        'az'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile { param([string]$Path) return @{} }
    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        }
    }
    function Get-ClagnosResizeOsDiskContext {
        param([psobject]$VmObject, [string]$ResourceGroup, [string]$VmName)
        return [pscustomobject]@{
            DiskId = '/subscriptions/test/resourceGroups/rg-samplevm-ate1-g1/providers/Microsoft.Compute/disks/disk-samplevm'
            DiskName = 'disk-samplevm'
            DiskSizeGb = 128
            SkuName = 'Premium_LRS'
        }
    }
    function Show-ClagnosResizeShrinkAlternatives {
        $script:ResizeShrinkAlternativesShown = $true
    }
    function Set-DotEnvValue {
        throw 'Shrink guidance must not persist .env changes.'
    }
    function az {
        $line = @($args) -join ' '
        $script:ResizeShrinkAzCalls += $line

        if ($line -eq 'vm show -g rg-samplevm-ate1-g1 -n samplevm -o json --only-show-errors') {
            $global:LASTEXITCODE = 0
            return '{"location":"austriaeast","hardwareProfile":{"vmSize":"Standard_D4as_v5"},"storageProfile":{"osDisk":{"osType":"Windows"}}}'
        }

        throw ("Unexpected Azure call during shrink guidance test: {0}" -f $line)
    }

    try {
        $threw = $false
        try {
            Invoke-ClagnosResizeCommand -Options @{
                group = 'rg-samplevm-ate1-g1'
                'vm-name' = 'samplevm'
                'disk-size' = '64gb'
                shrink = $true
            } -AutoMode:$false -WindowsFlag -LinuxFlag:$false
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*Azure does not support shrinking the existing managed OS disk*') -Message "Shrink guidance failure must explain the Azure OS disk shrink limitation."
        }

        Assert-True -Condition $threw -Message "Shrink guidance path must exit with a friendly error."
        Assert-True -Condition $script:ResizeShrinkAlternativesShown -Message "Shrink guidance path must print supported alternatives."
        Assert-True -Condition (-not ((@($script:ResizeShrinkAzCalls) -join "`n") -match 'vm deallocate|disk update|vm start|vm resize')) -Message "Shrink guidance path must not call mutating Azure resize operations."
        Assert-True -Condition ($script:ConfigOverrides.Count -eq 0) -Message "Shrink guidance path must not update runtime config overrides."
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Read-DotEnvFile',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosResizeOsDiskContext',
            'Show-ClagnosResizeShrinkAlternatives',
            'Set-DotEnvValue',
            'az'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
        Remove-Variable -Name ResizeShrinkAzCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeShrinkAlternativesShown -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ConfigOverrides -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Resize expand path deallocates, grows disk, restarts, and persists config" -Action {
    $script:ResizeExpandAzCalls = @()
    $script:ResizeExpandWaits = @()
    $script:ResizeExpandPersist = $null
    $script:ResizeExpandSnapshots = @()
    $script:ConfigOverrides = @{}
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Get-ClagnosRepoRoot',
        'Read-DotEnvFile',
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosResizeOsDiskContext',
        'Get-ClagnosResizeLifecycleSnapshot',
        'Get-ClagnosResizeDiskSizeReadback',
        'Write-ClagnosResizeStateSnapshot',
        'Invoke-TrackedAction',
        'Wait-ClagnosVmPowerState',
        'Set-DotEnvValue',
        'az'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile { param([string]$Path) return @{} }
    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        }
    }
    function Get-ClagnosResizeOsDiskContext {
        param([psobject]$VmObject, [string]$ResourceGroup, [string]$VmName)
        return [pscustomobject]@{
            DiskId = '/subscriptions/test/resourceGroups/rg-samplevm-ate1-g1/providers/Microsoft.Compute/disks/disk-samplevm'
            DiskName = 'disk-samplevm'
            DiskSizeGb = 128
            SkuName = 'Premium_LRS'
        }
    }
    function Get-ClagnosResizeLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName, [string]$Stage)
        $powerState = if ($Stage -eq 'before resize') { 'VM running' } else { 'VM running' }
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            NormalizedState = 'started'
            PowerStateDisplay = $powerState
            PowerStateCode = 'PowerState/running'
            HibernationStateDisplay = '(none)'
            HibernationStateCode = ''
            ProvisioningStateDisplay = 'Provisioning succeeded'
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            HibernationEnabled = $false
        }
    }
    function Get-ClagnosResizeDiskSizeReadback { param([string]$DiskId, [string]$DiskName) return 196 }
    function Write-ClagnosResizeStateSnapshot {
        param([string]$Stage, [string]$VmName, [string]$ResourceGroup, [string]$Region, [string]$VmSize, [string]$DiskName, [int]$DiskSizeGb, [psobject]$LifecycleSnapshot)
        $script:ResizeExpandSnapshots += ,([pscustomobject]@{ Stage = $Stage; VmSize = $VmSize; DiskSizeGb = $DiskSizeGb; Power = $LifecycleSnapshot.PowerStateDisplay })
    }
    function Invoke-TrackedAction {
        param([string]$Label, [scriptblock]$Action)
        & $Action
    }
    function Wait-ClagnosVmPowerState {
        param([string]$ResourceGroup, [string]$VmName, [string]$DesiredPowerState, [int]$MaxAttempts, [int]$DelaySeconds)
        $script:ResizeExpandWaits += [string]$DesiredPowerState
        return $true
    }
    function Set-DotEnvValue {
        param([string]$Path, [string]$Key, [string]$Value)
        $script:ResizeExpandPersist = [pscustomobject]@{
            Path = $Path
            Key = $Key
            Value = $Value
        }
    }
    function az {
        $line = @($args) -join ' '
        $script:ResizeExpandAzCalls += $line

        switch ($line) {
            'vm show -g rg-samplevm-ate1-g1 -n samplevm -o json --only-show-errors' {
                $global:LASTEXITCODE = 0
                return '{"location":"austriaeast","hardwareProfile":{"vmSize":"Standard_D4as_v5"},"storageProfile":{"osDisk":{"osType":"Windows"}}}'
            }
            'vm deallocate -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors' {
                $global:LASTEXITCODE = 0
                return ''
            }
            'disk update -g rg-samplevm-ate1-g1 -n disk-samplevm --size-gb 196 -o none --only-show-errors' {
                $global:LASTEXITCODE = 0
                return ''
            }
            'vm start -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors' {
                $global:LASTEXITCODE = 0
                return ''
            }
            default {
                throw ("Unexpected Azure call during disk expand test: {0}" -f $line)
            }
        }
    }

    try {
        Invoke-ClagnosResizeCommand -Options @{
            group = 'rg-samplevm-ate1-g1'
            'vm-name' = 'samplevm'
            'disk-size' = '196gb'
            expand = $true
        } -AutoMode:$false -WindowsFlag -LinuxFlag:$false

        $expectedAzSequence = @(
            'vm show -g rg-samplevm-ate1-g1 -n samplevm -o json --only-show-errors',
            'vm deallocate -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors',
            'disk update -g rg-samplevm-ate1-g1 -n disk-samplevm --size-gb 196 -o none --only-show-errors',
            'vm start -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors'
        )
        Assert-True -Condition ((@($script:ResizeExpandAzCalls) -join "`n") -eq ($expectedAzSequence -join "`n")) -Message "Disk expand path must call Azure in the expected order."
        Assert-True -Condition ((@($script:ResizeExpandWaits) -join ',') -eq 'VM deallocated,VM running') -Message "Disk expand path must wait for deallocated and running VM states."
        Assert-True -Condition ($null -ne $script:ResizeExpandPersist) -Message "Disk expand path must persist the updated platform disk-size config."
        Assert-True -Condition ([string]$script:ResizeExpandPersist.Key -eq 'WIN_VM_DISK_SIZE_GB') -Message "Disk expand path must persist the Windows disk-size config key for a Windows VM."
        Assert-True -Condition ([string]$script:ResizeExpandPersist.Value -eq '196') -Message "Disk expand path must persist the expanded disk size."
        Assert-True -Condition ([string]$script:ConfigOverrides.WIN_VM_DISK_SIZE_GB -eq '196') -Message "Disk expand path must update in-memory config overrides with the expanded disk size."
        Assert-True -Condition ((@($script:ResizeExpandSnapshots | ForEach-Object { [string]$_.Stage }) -join ',') -eq 'before,after') -Message 'Disk expand must print before and after state snapshots.'
        Assert-True -Condition ([int]$script:ResizeExpandSnapshots[1].DiskSizeGb -eq 196) -Message 'Disk expand after snapshot must use the Azure readback size.'
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosRepoRoot',
            'Read-DotEnvFile',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosResizeOsDiskContext',
            'Get-ClagnosResizeLifecycleSnapshot',
            'Get-ClagnosResizeDiskSizeReadback',
            'Write-ClagnosResizeStateSnapshot',
            'Invoke-TrackedAction',
            'Wait-ClagnosVmPowerState',
            'Set-DotEnvValue',
            'az'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
        Remove-Variable -Name ResizeExpandAzCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeExpandWaits -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeExpandPersist -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeExpandSnapshots -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ConfigOverrides -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Resize post-action Azure readback helpers query VM size and disk size" -Action {
    $script:ResizeReadbackAzCalls = @()
    try {
        function az {
            $line = @($args) -join ' '
            $script:ResizeReadbackAzCalls += $line
            switch ($line) {
                'vm show -g rg-samplevm-ate1-g1 -n samplevm --query hardwareProfile.vmSize -o tsv --only-show-errors' {
                    $global:LASTEXITCODE = 0
                    return 'Standard_D8as_v5'
                }
                'disk show --ids /subscriptions/test/disks/disk-samplevm --query diskSizeGb -o tsv --only-show-errors' {
                    $global:LASTEXITCODE = 0
                    return '196'
                }
                default { throw ("Unexpected resize readback query: {0}" -f $line) }
            }
        }

        $vmSize = Get-ClagnosResizeVmSizeReadback -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'samplevm'
        $diskSize = Get-ClagnosResizeDiskSizeReadback -DiskId '/subscriptions/test/disks/disk-samplevm' -DiskName 'disk-samplevm'

        Assert-True -Condition ([string]$vmSize -eq 'Standard_D8as_v5') -Message 'VM resize readback must return the Azure-confirmed SKU.'
        Assert-True -Condition ([int]$diskSize -eq 196) -Message 'Disk resize readback must parse the Azure-confirmed size.'
        Assert-True -Condition (@($script:ResizeReadbackAzCalls).Count -eq 2) -Message 'Resize must use read-only Azure queries for both post-action properties.'
    }
    finally {
        Remove-Item Function:\az -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeReadbackAzCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Resize readback mismatch reports the actual state without claiming rollback" -Action {
    $snapshot = [pscustomobject]@{
        NormalizedState = 'started'
        PowerStateDisplay = 'VM running'
        PowerStateCode = 'PowerState/running'
        HibernationStateDisplay = '(none)'
        HibernationStateCode = ''
        ProvisioningStateDisplay = 'Provisioning succeeded'
        ProvisioningStateCode = 'ProvisioningState/succeeded'
        HibernationEnabled = $false
    }
    $failureText = ''
    $failureHint = ''
    try {
        Assert-ClagnosResizeReadback -Kind 'vm-size' -ExpectedValue 'Standard_D8as_v5' -ActualValue 'Standard_D4as_v5' -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'samplevm' -LifecycleSnapshot $snapshot
    }
    catch {
        $failureText = [string]$_.Exception.Message
        $failureHint = [string]$_.Exception.Data['Hint']
    }

    Assert-True -Condition ($failureText -match 'expected VM size=.Standard_D8as_v5., actual=.Standard_D4as_v5.') -Message 'Resize readback failure must state expected and actual values.'
    Assert-True -Condition ($failureText -match 'VM running') -Message 'Resize readback failure must include the current VM power state.'
    Assert-True -Condition ($failureHint -match 'no automatic rollback was attempted') -Message 'Resize readback failure must state the recovery boundary accurately.'
}

Invoke-Test -Name "Resize VM size path reads back the resulting SKU and lifecycle state" -Action {
    $script:ResizeVmSizeAzCalls = @()
    $script:ResizeVmSizePersist = $null
    $script:ResizeVmSizeSnapshots = @()
    $script:ConfigOverrides = @{}
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Get-ClagnosRepoRoot',
        'Read-DotEnvFile',
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosResizeLifecycleSnapshot',
        'Get-ClagnosResizeVmSizeReadback',
        'Write-ClagnosResizeStateSnapshot',
        'Assert-LocationExists',
        'Assert-VmSkuAvailableViaRest',
        'Invoke-TrackedAction',
        'Wait-ClagnosVmPowerState',
        'Set-DotEnvValue',
        'az'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) { $originalFunctionDefinitions[$functionName] = [string]$command.Definition }
    }

    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Read-DotEnvFile { param([string]$Path) return @{} }
    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{ ResourceGroup = 'rg-samplevm-ate1-g1'; VmName = 'samplevm' }
    }
    function Get-ClagnosResizeLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName, [string]$Stage)
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            NormalizedState = 'started'
            PowerStateDisplay = 'VM running'
            PowerStateCode = 'PowerState/running'
            HibernationStateDisplay = '(none)'
            HibernationStateCode = ''
            ProvisioningStateDisplay = 'Provisioning succeeded'
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            HibernationEnabled = $false
        }
    }
    function Get-ClagnosResizeVmSizeReadback { param([string]$ResourceGroup, [string]$VmName) return 'Standard_D8as_v5' }
    function Write-ClagnosResizeStateSnapshot {
        param([string]$Stage, [string]$VmName, [string]$ResourceGroup, [string]$Region, [string]$VmSize, [string]$DiskName, [int]$DiskSizeGb, [psobject]$LifecycleSnapshot)
        $script:ResizeVmSizeSnapshots += ,([pscustomobject]@{ Stage = $Stage; VmSize = $VmSize; Power = $LifecycleSnapshot.PowerStateDisplay })
    }
    function Assert-LocationExists { param([string]$Location) }
    function Assert-VmSkuAvailableViaRest { param([string]$Location, [string]$VmSize) }
    function Invoke-TrackedAction { param([string]$Label, [scriptblock]$Action) & $Action }
    function Wait-ClagnosVmPowerState { param([string]$ResourceGroup, [string]$VmName, [string]$DesiredPowerState, [int]$MaxAttempts, [int]$DelaySeconds) return $true }
    function Set-DotEnvValue {
        param([string]$Path, [string]$Key, [string]$Value)
        $script:ResizeVmSizePersist = [pscustomobject]@{ Key = $Key; Value = $Value }
    }
    function az {
        $line = @($args) -join ' '
        $script:ResizeVmSizeAzCalls += $line
        switch ($line) {
            'vm show -g rg-samplevm-ate1-g1 -n samplevm -o json --only-show-errors' {
                $global:LASTEXITCODE = 0
                return '{"location":"austriaeast","hardwareProfile":{"vmSize":"Standard_D4as_v5"},"storageProfile":{"osDisk":{"osType":"Windows"}}}'
            }
            'vm deallocate -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors' { $global:LASTEXITCODE = 0; return '' }
            'vm resize -g rg-samplevm-ate1-g1 -n samplevm --size Standard_D8as_v5 -o none --only-show-errors' { $global:LASTEXITCODE = 0; return '' }
            'vm start -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors' { $global:LASTEXITCODE = 0; return '' }
            default { throw ("Unexpected Azure call during VM resize test: {0}" -f $line) }
        }
    }

    foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile','Resolve-ClagnosManagedVmTarget','Get-ClagnosResizeLifecycleSnapshot','Get-ClagnosResizeVmSizeReadback','Write-ClagnosResizeStateSnapshot','Assert-LocationExists','Assert-VmSkuAvailableViaRest','Invoke-TrackedAction','Wait-ClagnosVmPowerState','Set-DotEnvValue','az')) {
        $localFunction = Get-Command $functionName -CommandType Function -ErrorAction Stop
        $mockDefinition = [scriptblock]::Create([string]$localFunction.Definition)
        Set-Item -Path ("Function:\script:{0}" -f $functionName) -Value $mockDefinition
        Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value $mockDefinition
    }

    try {
        Invoke-ClagnosResizeCommand -Options @{
            group = 'rg-samplevm-ate1-g1'
            'vm-name' = 'samplevm'
            'vm-size' = 'Standard_D8as_v5'
        } -AutoMode:$false -WindowsFlag -LinuxFlag:$false

        $expectedAzSequence = @(
            'vm show -g rg-samplevm-ate1-g1 -n samplevm -o json --only-show-errors',
            'vm deallocate -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors',
            'vm resize -g rg-samplevm-ate1-g1 -n samplevm --size Standard_D8as_v5 -o none --only-show-errors',
            'vm start -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors'
        )
        Assert-True -Condition ((@($script:ResizeVmSizeAzCalls) -join "`n") -eq ($expectedAzSequence -join "`n")) -Message 'VM resize must keep its Azure mutation sequence explicit.'
        Assert-True -Condition ((@($script:ResizeVmSizeSnapshots | ForEach-Object { [string]$_.Stage }) -join ',') -eq 'before,after') -Message 'VM resize must print before and after lifecycle snapshots.'
        Assert-True -Condition ([string]$script:ResizeVmSizeSnapshots[1].VmSize -eq 'Standard_D8as_v5') -Message 'VM resize after snapshot must use the Azure-confirmed SKU.'
        Assert-True -Condition ([string]$script:ResizeVmSizePersist.Key -eq 'WIN_VM_SIZE') -Message 'VM resize must persist the platform-specific VM-size key after readback.'
        Assert-True -Condition ([string]$script:ResizeVmSizePersist.Value -eq 'Standard_D8as_v5') -Message 'VM resize must persist the Azure-confirmed VM size.'
    }
    finally {
        foreach ($functionName in @('Get-ClagnosRepoRoot','Read-DotEnvFile','Resolve-ClagnosManagedVmTarget','Get-ClagnosResizeLifecycleSnapshot','Get-ClagnosResizeVmSizeReadback','Write-ClagnosResizeStateSnapshot','Assert-LocationExists','Assert-VmSkuAvailableViaRest','Invoke-TrackedAction','Wait-ClagnosVmPowerState','Set-DotEnvValue','az')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\script:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\script:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
        Remove-Variable -Name ResizeVmSizeAzCalls -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeVmSizePersist -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ResizeVmSizeSnapshots -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ConfigOverrides -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Move source group purge-safety helper accepts expected resource set" -Action {
    $resources = @(
        [pscustomobject]@{ name = 'samplevm'; type = 'Microsoft.Compute/virtualMachines' },
        [pscustomobject]@{ name = 'disk-samplevm-ate1-n1'; type = 'Microsoft.Compute/disks' },
        [pscustomobject]@{ name = 'nic-samplevm-ate1-n1'; type = 'Microsoft.Network/networkInterfaces' },
        [pscustomobject]@{ name = 'ip-samplevm-ate1-n1'; type = 'Microsoft.Network/publicIPAddresses' },
        [pscustomobject]@{ name = 'nsg-samplevm-ate1-n1'; type = 'Microsoft.Network/networkSecurityGroups' },
        [pscustomobject]@{ name = 'net-samplevm-ate1-n1'; type = 'Microsoft.Network/virtualNetworks' }
    )

    $result = Test-ClagnosMoveResourceSetIsPurgeSafe -Resources $resources -VmName 'samplevm' -OsDiskName 'disk-samplevm-ate1-n1'
    Assert-True -Condition ([bool]$result.IsSafe) -Message "Expected VM-bound resource set must be purge-safe."
}

Invoke-Test -Name "Move source group purge-safety helper rejects unexpected resources" -Action {
    $resources = @(
        [pscustomobject]@{ name = 'samplevm'; type = 'Microsoft.Compute/virtualMachines' },
        [pscustomobject]@{ name = 'disk-samplevm-ate1-n1'; type = 'Microsoft.Compute/disks' },
        [pscustomobject]@{ name = 'nic-samplevm-ate1-n1'; type = 'Microsoft.Network/networkInterfaces' },
        [pscustomobject]@{ name = 'ip-samplevm-ate1-n1'; type = 'Microsoft.Network/publicIPAddresses' },
        [pscustomobject]@{ name = 'nsg-samplevm-ate1-n1'; type = 'Microsoft.Network/networkSecurityGroups' },
        [pscustomobject]@{ name = 'net-samplevm-ate1-n1'; type = 'Microsoft.Network/virtualNetworks' },
        [pscustomobject]@{ name = 'vault-extra'; type = 'Microsoft.KeyVault/vaults' }
    )

    $result = Test-ClagnosMoveResourceSetIsPurgeSafe -Resources $resources -VmName 'samplevm' -OsDiskName 'disk-samplevm-ate1-n1'
    Assert-True -Condition (-not [bool]$result.IsSafe) -Message "Unexpected resource types must block automatic source-group purge."
    Assert-True -Condition (@($result.UnexpectedTypes) -contains 'Microsoft.KeyVault/vaults') -Message "Unexpected resource type should be surfaced to the operator."
}

Invoke-Test -Name "Help --command syntax was removed" -Action {
    $threw = $false
    try {
        Assert-ClagnosCommandOptions -CommandName "help" -Options @{ command = "create" }
    }
    catch {
        $threw = $true
    }
    Assert-True -Condition $threw -Message "help --command must be rejected."
}

Invoke-Test -Name "Detailed help topic validation" -Action {
    Show-ClagnosCommandHelp -Topic "create"
    Show-ClagnosCommandHelp -Topic "configure"
    Show-ClagnosCommandHelp -Topic "list"
    Show-ClagnosCommandHelp -Topic "do"
    Show-ClagnosCommandHelp -Topic "resize"
    Show-ClagnosCommandHelp -Topic "connect"
    Show-ClagnosCommandHelp -Topic "exec"
    Show-ClagnosCommandHelp -Topic "show"
    Show-ClagnosCommandHelp -Topic ""
    Show-ClagnosCommandHelp -Overview
}

Invoke-Test -Name "Do lifecycle snapshot normalization" -Action {
    $vmObject = [pscustomobject]@{
        location = 'austriaeast'
        osType = 'Windows'
        hibernationEnabled = $true
    }

    $stoppedSnapshot = ConvertTo-ClagnosVmLifecycleSnapshot `
        -ResourceGroup 'rg-samplevm-ate1-g1' `
        -VmName 'samplevm' `
        -VmObject $vmObject `
        -InstanceViewObject ([pscustomobject]@{
            instanceView = [pscustomobject]@{
                statuses = @(
                    [pscustomobject]@{ code = 'ProvisioningState/succeeded'; displayStatus = 'Provisioning succeeded' },
                    [pscustomobject]@{ code = 'PowerState/stopped'; displayStatus = 'VM stopped' }
                )
            }
        })
    Assert-True -Condition ([string]$stoppedSnapshot.NormalizedState -eq 'stopped') -Message "Stopped VM state normalization failed."

    $deallocatedSnapshot = ConvertTo-ClagnosVmLifecycleSnapshot `
        -ResourceGroup 'rg-samplevm-ate1-g1' `
        -VmName 'samplevm' `
        -VmObject $vmObject `
        -InstanceViewObject ([pscustomobject]@{
            instanceView = [pscustomobject]@{
                statuses = @(
                    [pscustomobject]@{ code = 'ProvisioningState/succeeded'; displayStatus = 'Provisioning succeeded' },
                    [pscustomobject]@{ code = 'PowerState/deallocated'; displayStatus = 'VM deallocated' }
                )
            }
        })
    Assert-True -Condition ([string]$deallocatedSnapshot.NormalizedState -eq 'deallocated') -Message "Deallocated VM state normalization failed."

    $hibernatedSnapshot = ConvertTo-ClagnosVmLifecycleSnapshot `
        -ResourceGroup 'rg-samplevm-ate1-g1' `
        -VmName 'samplevm' `
        -VmObject $vmObject `
        -InstanceViewObject ([pscustomobject]@{
            instanceView = [pscustomobject]@{
                statuses = @(
                    [pscustomobject]@{ code = 'ProvisioningState/succeeded'; displayStatus = 'Provisioning succeeded' },
                    [pscustomobject]@{ code = 'PowerState/deallocated'; displayStatus = 'VM deallocated' },
                    [pscustomobject]@{ code = 'HibernationState/hibernated'; displayStatus = 'Hibernated' }
                )
            }
        })
    Assert-True -Condition ([string]$hibernatedSnapshot.NormalizedState -eq 'hibernated') -Message "Hibernated VM state normalization failed."

    $otherSnapshot = ConvertTo-ClagnosVmLifecycleSnapshot `
        -ResourceGroup 'rg-samplevm-ate1-g1' `
        -VmName 'samplevm' `
        -VmObject $vmObject `
        -InstanceViewObject ([pscustomobject]@{
            instanceView = [pscustomobject]@{
                statuses = @(
                    [pscustomobject]@{ code = 'ProvisioningState/succeeded'; displayStatus = 'Provisioning succeeded' },
                    [pscustomobject]@{ code = 'PowerState/starting'; displayStatus = 'VM starting' }
                )
            }
        })
    Assert-True -Condition ([string]$otherSnapshot.NormalizedState -eq 'other') -Message "Unknown VM state should normalize to other."
}

Invoke-Test -Name "Resize target size selection stays in current region" -Action {
    $script:ResizePickerCallCount = 0

    try {
        function script:Select-AzLocationInteractive {
            throw "Resize target size selection must not call region picker."
        }

        function script:Select-VmSkuInteractive {
            param(
                [string]$Location,
                [string]$DefaultVmSize,
                [int]$PriceHours
            )

            $script:ResizePickerCallCount++
            if ($script:ResizePickerCallCount -eq 1) {
                return (Get-ClagnosSkuPickerRegionBackToken)
            }

            return 'Standard_D4as_v5'
        }

        $resolvedSize = Resolve-ClagnosResizeTargetSize -Options @{} -CurrentRegion 'austriaeast' -CurrentSize 'Standard_D2as_v5' -ConfigMap @{ PRICE_HOURS = '730' }
        Assert-True -Condition ([string]$resolvedSize -eq 'Standard_D4as_v5') -Message "Resize interactive size selection returned unexpected value."
        Assert-True -Condition ($script:ResizePickerCallCount -eq 2) -Message "Resize interactive size selection should retry after back token without invoking region picker."
    }
    finally {
        Remove-Item Function:\script:Select-AzLocationInteractive -ErrorAction SilentlyContinue
        Remove-Item Function:\script:Select-VmSkuInteractive -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Select-AzLocationInteractive -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Select-VmSkuInteractive -ErrorAction SilentlyContinue
        Remove-Variable ResizePickerCallCount -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Resize platform expectation" -Action {
    Assert-ClagnosResizePlatformExpectation -ActualPlatform 'windows' -WindowsFlag -VmName 'samplevm' -ResourceGroup 'rg-samplevm-ate1-g1'
    Assert-ClagnosResizePlatformExpectation -ActualPlatform 'linux' -LinuxFlag -VmName 'samplevm' -ResourceGroup 'rg-samplevm-ate1-g1'

    $invalidCases = @(
        @{ ActualPlatform = 'windows'; UseLinux = $true },
        @{ ActualPlatform = 'linux'; UseWindows = $true }
    )

    foreach ($case in @($invalidCases)) {
        $threw = $false
        try {
            Assert-ClagnosResizePlatformExpectation `
                -ActualPlatform ([string]$case.ActualPlatform) `
                -WindowsFlag:([bool]$case.UseWindows) `
                -LinuxFlag:([bool]$case.UseLinux) `
                -VmName 'samplevm' `
                -ResourceGroup 'rg-samplevm-ate1-g1'
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Resize platform expectation should reject mismatched platform '{0}'." -f [string]$case.ActualPlatform)
    }
}

Invoke-Test -Name "Do action eligibility contract" -Action {
    function New-TestDoSnapshot {
        param(
            [string]$NormalizedState,
            [string]$PowerStateDisplay,
            [bool]$HibernationEnabled = $true,
            [string]$ProvisioningStateCode = 'ProvisioningState/succeeded',
            [string]$ProvisioningStateDisplay = 'Provisioning succeeded',
            [string]$HibernationStateDisplay = '',
            [string]$HibernationStateCode = ''
        )

        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            NormalizedState = $NormalizedState
            PowerStateDisplay = $PowerStateDisplay
            PowerStateCode = ''
            HibernationEnabled = $HibernationEnabled
            ProvisioningStateCode = $ProvisioningStateCode
            ProvisioningStateDisplay = $ProvisioningStateDisplay
            HibernationStateDisplay = $HibernationStateDisplay
            HibernationStateCode = $HibernationStateCode
        }
    }

    Assert-ClagnosDoActionAllowed -ActionName 'status' -Snapshot (New-TestDoSnapshot -NormalizedState 'other' -PowerStateDisplay 'VM starting')
    Assert-ClagnosDoActionAllowed -ActionName 'resume' -Snapshot (New-TestDoSnapshot -NormalizedState 'hibernated' -PowerStateDisplay 'VM deallocated' -HibernationStateDisplay 'Hibernated' -HibernationStateCode 'HibernationState/hibernated')
    Assert-ClagnosDoActionAllowed -ActionName 'restart' -Snapshot (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')
    Assert-ClagnosDoActionAllowed -ActionName 'reset' -Snapshot (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')
    Assert-ClagnosDoActionAllowed -ActionName 'shutdown' -Snapshot (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')
    Assert-ClagnosDoActionAllowed -ActionName 'power-off' -Snapshot (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')
    Assert-ClagnosDoActionAllowed -ActionName 'deallocate' -Snapshot (New-TestDoSnapshot -NormalizedState 'hibernated' -PowerStateDisplay 'VM deallocated' -HibernationStateDisplay 'Hibernated' -HibernationStateCode 'HibernationState/hibernated')
    Assert-ClagnosDoActionAllowed -ActionName 'hibernate-deallocate' -Snapshot (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')
    Assert-ClagnosDoActionAllowed -ActionName 'hibernate-stop' -Snapshot (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')
    Assert-ClagnosDoActionAllowed -ActionName 'reapply' -Snapshot (New-TestDoSnapshot -NormalizedState 'other' -PowerStateDisplay 'VM starting' -ProvisioningStateCode 'ProvisioningState/updating' -ProvisioningStateDisplay 'Updating')
    Assert-ClagnosDoActionAllowed -ActionName 'redeploy' -Snapshot (New-TestDoSnapshot -NormalizedState 'other' -PowerStateDisplay 'VM starting' -ProvisioningStateCode 'ProvisioningState/updating' -ProvisioningStateDisplay 'Updating')

    $invalidCases = @(
        @{ Action = 'start'; Snapshot = (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running') },
        @{ Action = 'resume'; Snapshot = (New-TestDoSnapshot -NormalizedState 'stopped' -PowerStateDisplay 'VM stopped') },
        @{ Action = 'hibernate-deallocate'; Snapshot = (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running' -HibernationEnabled:$false) },
        @{ Action = 'hibernate-stop'; Snapshot = (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running' -HibernationEnabled:$false) },
        @{ Action = 'stop'; Snapshot = (New-TestDoSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running' -ProvisioningStateCode 'ProvisioningState/updating' -ProvisioningStateDisplay 'Updating') }
    )

    foreach ($case in @($invalidCases)) {
        $threw = $false
        try {
            Assert-ClagnosDoActionAllowed -ActionName ([string]$case.Action) -Snapshot $case.Snapshot
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Do action eligibility should reject invalid case '{0}'." -f [string]$case.Action)
    }
}

Invoke-Test -Name "Do resume, shutdown, power-off, and reset use the intended Azure actions" -Action {
    $script:DoActionDispatchCall = $null
    $script:DoActionDispatchState = 'started'
    $originalFunctionDefinitions = @{}
    foreach ($functionName in @(
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosVmLifecycleSnapshot',
        'Invoke-ClagnosDoAzureAction',
        'Wait-ClagnosDoLifecycleState',
        'Write-ClagnosDoStatusReport'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) { $originalFunctionDefinitions[$functionName] = [string]$command.Definition }
    }

    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{ ResourceGroup = 'rg-samplevm-ate1-g1'; VmName = 'samplevm' }
    }
    function Get-ClagnosVmLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName)
        $state = [string]$script:DoActionDispatchState
        $hibernationState = if ($state -eq 'hibernated') { 'Hibernated' } else { '' }
        $hibernationCode = if ($state -eq 'hibernated') { 'HibernationState/hibernated' } else { '' }
        $powerState = if ($state -eq 'started') { 'VM running' } elseif ($state -eq 'hibernated') { 'VM deallocated' } else { 'VM stopped' }
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            OsType = 'Windows'
            Location = 'austriaeast'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            ProvisioningStateDisplay = 'Provisioning succeeded'
            PowerStateCode = ''
            PowerStateDisplay = $powerState
            HibernationStateCode = $hibernationCode
            HibernationStateDisplay = $hibernationState
            NormalizedState = $state
        }
    }
    function Invoke-ClagnosDoAzureAction {
        param([string]$ActionName, [string]$ResourceGroup, [string]$VmName, [string[]]$AzArguments, [string]$AzContext)
        $script:DoActionDispatchCall = [pscustomobject]@{
            ActionName = $ActionName
            AzArguments = @($AzArguments)
            AzContext = $AzContext
        }
    }
    function Wait-ClagnosDoLifecycleState {
        param([string]$ResourceGroup, [string]$VmName, [string]$DesiredState, [int]$MaxAttempts, [int]$DelaySeconds)
        $script:DoActionDispatchState = $DesiredState
        return (Get-ClagnosVmLifecycleSnapshot -ResourceGroup $ResourceGroup -VmName $VmName)
    }
    function Write-ClagnosDoStatusReport { param([psobject]$Snapshot) }

    try {
        $cases = @(
            @{ Action = 'resume'; SourceState = 'hibernated'; Expected = 'vm start -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors'; Context = 'az vm start (resume)' },
            @{ Action = 'shutdown'; SourceState = 'started'; Expected = 'vm stop -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors'; Context = 'az vm stop (graceful shutdown)' },
            @{ Action = 'power-off'; SourceState = 'started'; Expected = 'vm stop -g rg-samplevm-ate1-g1 -n samplevm --skip-shutdown -o none --only-show-errors'; Context = 'az vm stop --skip-shutdown' },
            @{ Action = 'reset'; SourceState = 'started'; Expected = 'vm restart -g rg-samplevm-ate1-g1 -n samplevm --force -o none --only-show-errors'; Context = 'az vm restart --force' }
        )
        foreach ($case in @($cases)) {
            $script:DoActionDispatchState = [string]$case.SourceState
            $script:DoActionDispatchCall = $null
            Invoke-ClagnosDoCommand -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = [string]$case.Action }
            Assert-True -Condition ($null -ne $script:DoActionDispatchCall) -Message ("'{0}' must call the Azure lifecycle wrapper." -f [string]$case.Action)
            Assert-True -Condition ([string]$script:DoActionDispatchCall.ActionName -eq [string]$case.Action) -Message ("'{0}' must preserve its lifecycle action name." -f [string]$case.Action)
            Assert-True -Condition ((@($script:DoActionDispatchCall.AzArguments) -join ' ') -eq [string]$case.Expected) -Message ("'{0}' must use the expected Azure CLI operation." -f [string]$case.Action)
            Assert-True -Condition ([string]$script:DoActionDispatchCall.AzContext -eq [string]$case.Context) -Message ("'{0}' must use a descriptive Azure progress label." -f [string]$case.Action)
        }
    }
    finally {
        foreach ($functionName in @('Resolve-ClagnosManagedVmTarget','Get-ClagnosVmLifecycleSnapshot','Invoke-ClagnosDoAzureAction','Wait-ClagnosDoLifecycleState','Write-ClagnosDoStatusReport')) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Do interactive action selection" -Action {
    $snapshot = [pscustomobject]@{
        ResourceGroup = 'rg-samplevm-ate1-g1'
        VmName = 'samplevm'
        NormalizedState = 'stopped'
        PowerStateDisplay = 'VM stopped'
        PowerStateCode = 'PowerState/stopped'
        HibernationEnabled = $true
        ProvisioningStateCode = 'ProvisioningState/succeeded'
        ProvisioningStateDisplay = 'Provisioning succeeded'
        HibernationStateDisplay = ''
        HibernationStateCode = ''
    }

    try {
        function Read-Host { param([string]$Prompt) return '' }
        $defaultAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$defaultAction -eq 'status') -Message "Interactive do action default should be status."

        function Read-Host { param([string]$Prompt) return '5' }
        $pickedAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$pickedAction -eq 'deallocate') -Message "Interactive do action selection by number failed."

        function Read-Host { param([string]$Prompt) return '6' }
        $hibernateDeallocateAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$hibernateDeallocateAction -eq 'hibernate-deallocate') -Message "Interactive do action selection must expose hibernate-deallocate."

        function Read-Host { param([string]$Prompt) return '7' }
        $hibernateStopAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$hibernateStopAction -eq 'hibernate-stop') -Message "Interactive do action selection must expose hibernate-stop."

        function Read-Host { param([string]$Prompt) return '8' }
        $reapplyAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$reapplyAction -eq 'reapply') -Message "Interactive do action selection must expose reapply."

        function Read-Host { param([string]$Prompt) return '9' }
        $redeployAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$redeployAction -eq 'redeploy') -Message "Interactive do action selection must expose redeploy."

        function Read-Host { param([string]$Prompt) return '10' }
        $shutdownAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$shutdownAction -eq 'shutdown') -Message "Interactive do action selection must expose graceful shutdown."

        function Read-Host { param([string]$Prompt) return '11' }
        $resumeAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$resumeAction -eq 'resume') -Message "Interactive do action selection must expose resume."

        function Read-Host { param([string]$Prompt) return '12' }
        $powerOffAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$powerOffAction -eq 'power-off') -Message "Interactive do action selection must expose immediate power-off."

        function Read-Host { param([string]$Prompt) return '13' }
        $resetAction = Read-ClagnosDoActionInteractive -Snapshot $snapshot
        Assert-True -Condition ([string]$resetAction -eq 'reset') -Message "Interactive do action selection must expose forced reset."
    }
    finally {
        Remove-Item Function:\global:Read-Host -ErrorAction SilentlyContinue
        Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Do reapply action calls Azure reapply and prints refreshed status" -Action {
    $script:DoReapplyInvocation = $null
    $script:DoReapplySnapshotCalls = 0
    $script:DoReapplyWaitCalled = $false
    $script:DoReapplyReportedSnapshot = $null
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosVmLifecycleSnapshot',
        'Invoke-ClagnosDoAzureAction',
        'Wait-ClagnosDoLifecycleState',
        'Write-ClagnosDoStatusReport'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        }
    }
    function Get-ClagnosVmLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName)
        $script:DoReapplySnapshotCalls++
        $provisioningDisplay = if ($script:DoReapplySnapshotCalls -eq 1) { 'Updating' } else { 'Provisioning succeeded' }
        $provisioningCode = if ($script:DoReapplySnapshotCalls -eq 1) { 'ProvisioningState/updating' } else { 'ProvisioningState/succeeded' }
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            OsType = 'Windows'
            Location = 'austriaeast'
            HibernationEnabled = $true
            ProvisioningStateCode = $provisioningCode
            ProvisioningStateDisplay = $provisioningDisplay
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
            NormalizedState = 'started'
        }
    }
    function Invoke-ClagnosDoAzureAction {
        param(
            [string]$ActionName,
            [string]$ResourceGroup,
            [string]$VmName,
            [string[]]$AzArguments,
            [string]$AzContext
        )

        $script:DoReapplyInvocation = [pscustomobject]@{
            ActionName = $ActionName
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            AzArguments = @($AzArguments)
            AzContext = $AzContext
        }
    }
    function Wait-ClagnosDoLifecycleState {
        param([string]$ResourceGroup, [string]$VmName, [string]$DesiredState, [int]$MaxAttempts, [int]$DelaySeconds)
        $script:DoReapplyWaitCalled = $true
        return $null
    }
    function Write-ClagnosDoStatusReport {
        param([psobject]$Snapshot)
        $script:DoReapplyReportedSnapshot = $Snapshot
    }

    try {
        Invoke-ClagnosDoCommand -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'reapply' }

        Assert-True -Condition ($null -ne $script:DoReapplyInvocation) -Message 'Reapply must invoke the Azure action wrapper.'
        Assert-True -Condition ([string]$script:DoReapplyInvocation.ActionName -eq 'reapply') -Message 'Reapply must pass the reapply action name to the Azure wrapper.'
        Assert-True -Condition ([string]$script:DoReapplyInvocation.AzContext -eq 'az vm reapply') -Message 'Reapply must use the az vm reapply context label.'
        Assert-True -Condition ((@($script:DoReapplyInvocation.AzArguments) -join ' ') -eq 'vm reapply -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors') -Message 'Reapply must call az vm reapply with the resolved target.'
        Assert-True -Condition ($script:DoReapplySnapshotCalls -eq 2) -Message 'Reapply must refresh lifecycle status after the Azure action.'
        Assert-True -Condition (-not $script:DoReapplyWaitCalled) -Message 'Reapply must not wait for a synthetic lifecycle-state transition.'
        Assert-True -Condition ($null -ne $script:DoReapplyReportedSnapshot) -Message 'Reapply must print the refreshed VM status.'
        Assert-True -Condition ([string]$script:DoReapplyReportedSnapshot.ProvisioningStateCode -eq 'ProvisioningState/succeeded') -Message 'Reapply must report the post-action lifecycle snapshot.'
    }
    finally {
        foreach ($functionName in @(
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmLifecycleSnapshot',
            'Invoke-ClagnosDoAzureAction',
            'Wait-ClagnosDoLifecycleState',
            'Write-ClagnosDoStatusReport'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Do hibernate-stop guest action uses pyssh shutdown" -Action {
    $script:DoHibernateStopProcessInvocation = $null
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Initialize-ClagnosConnectionCommandContext',
        'Resolve-ClagnosConnectionPortNumber',
        'Wait-ClagnosTcpPortReachable',
        'Get-ClagnosRepoRoot',
        'Get-ConfigValue',
        'Ensure-ClagnosPySshTools',
        'Invoke-ClagnosProcessWithRetry'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Initialize-ClagnosConnectionCommandContext {
        param([hashtable]$Options, [string]$OperationName)
        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            ConnectionHost = 'samplevm.example'
            VmSshPort = '444'
            SelectedUserName = 'manager'
            SelectedPassword = 'secret'
            ConfigMap = @{ PYSSH_CLIENT_PATH = 'tools/pyssh/ssh_client.py'; SSH_CONNECT_TIMEOUT_SECONDS = '30' }
        }
    }
    function Resolve-ClagnosConnectionPortNumber { param([string]$PortText, [string]$PortLabel) return 444 }
    function Wait-ClagnosTcpPortReachable { param([string]$HostName, [int]$Port, [int]$MaxAttempts, [int]$DelaySeconds, [int]$TimeoutSeconds, [string]$Label) return $true }
    function Get-ClagnosRepoRoot { return $RepoRoot }
    function Get-ConfigValue {
        param([hashtable]$Config, [string]$Key, [string]$DefaultValue)
        if ($Config.ContainsKey($Key)) {
            return [string]$Config[$Key]
        }
        return [string]$DefaultValue
    }
    function Ensure-ClagnosPySshTools {
        param([string]$RepoRoot, [string]$ConfiguredPySshClientPath)
        return [pscustomobject]@{
            PythonPath = 'python'
            ClientPath = 'client.py'
        }
    }
    function Invoke-ClagnosProcessWithRetry {
        param(
            [string]$FilePath,
            [string[]]$Arguments,
            [string]$Label,
            [int]$MaxAttempts,
            [switch]$AllowFailure
        )

        $script:DoHibernateStopProcessInvocation = [pscustomobject]@{
            FilePath = $FilePath
            Arguments = @($Arguments)
            Label = $Label
            MaxAttempts = $MaxAttempts
            AllowFailure = [bool]$AllowFailure
        }

        return [pscustomobject]@{
            ExitCode = 0
            Output = 'ok'
        }
    }

    try {
        $result = Invoke-ClagnosDoGuestHibernateStopCommand -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'samplevm'
        Assert-True -Condition ($null -ne $result) -Message 'Hibernate-stop helper must return runtime invocation details.'
        Assert-True -Condition ($null -ne $script:DoHibernateStopProcessInvocation) -Message 'Hibernate-stop helper must invoke the pyssh process wrapper.'
        Assert-True -Condition ((@($script:DoHibernateStopProcessInvocation.Arguments) -join ' ') -match [regex]::Escape('--command shutdown /h /f')) -Message 'Hibernate-stop helper must issue shutdown /h /f through pyssh.'
        Assert-True -Condition ($script:DoHibernateStopProcessInvocation.MaxAttempts -eq 1) -Message 'Hibernate-stop helper must not retry the guest shutdown command.'
        Assert-True -Condition ($script:DoHibernateStopProcessInvocation.AllowFailure) -Message 'Hibernate-stop helper must allow a dropped SSH session while the guest powers off.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosConnectionCommandContext',
            'Resolve-ClagnosConnectionPortNumber',
            'Wait-ClagnosTcpPortReachable',
            'Get-ClagnosRepoRoot',
            'Get-ConfigValue',
            'Ensure-ClagnosPySshTools',
            'Invoke-ClagnosProcessWithRetry'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Do hibernate-stop action waits for the guest to stop after SSH-triggered hibernation" -Action {
    $script:DoHibernateStopInvocation = $null
    $script:DoHibernateStopWaitInvocation = $null
    $script:DoHibernateStopReportedSnapshot = $null
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosVmLifecycleSnapshot',
        'Invoke-ClagnosDoGuestHibernateStopCommand',
        'Wait-ClagnosDoHibernateStopCompletion',
        'Write-ClagnosDoStatusReport'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        }
    }
    function Get-ClagnosVmLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName)
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            OsType = 'Windows'
            Location = 'austriaeast'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            ProvisioningStateDisplay = 'Provisioning succeeded'
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
            NormalizedState = 'started'
        }
    }
    function Invoke-ClagnosDoGuestHibernateStopCommand {
        param([string]$ResourceGroup, [string]$VmName)
        $script:DoHibernateStopInvocation = [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
        }
        return [pscustomobject]@{
            Runtime = [pscustomobject]@{
                ConnectionHost = 'samplevm.example'
                VmSshPort = '444'
            }
            LaunchResult = [pscustomobject]@{
                ExitCode = 0
                Output = 'issued'
            }
        }
    }
    function Wait-ClagnosDoHibernateStopCompletion {
        param([psobject]$Runtime, [string]$ResourceGroup, [string]$VmName, [int]$MaxAttempts, [int]$DelaySeconds)
        $script:DoHibernateStopWaitInvocation = [pscustomobject]@{
            Runtime = $Runtime
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            MaxAttempts = $MaxAttempts
            DelaySeconds = $DelaySeconds
        }
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            OsType = 'Windows'
            Location = 'austriaeast'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            ProvisioningStateDisplay = 'Provisioning succeeded'
            PowerStateCode = 'PowerState/stopped'
            PowerStateDisplay = 'VM stopped'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
            NormalizedState = 'stopped'
        }
    }
    function Write-ClagnosDoStatusReport {
        param([psobject]$Snapshot)
        $script:DoHibernateStopReportedSnapshot = $Snapshot
    }

    try {
        Invoke-ClagnosDoCommand -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'hibernate-stop' }

        Assert-True -Condition ($null -ne $script:DoHibernateStopInvocation) -Message 'Hibernate-stop must invoke the guest shutdown helper.'
        Assert-True -Condition ($null -ne $script:DoHibernateStopWaitInvocation) -Message 'Hibernate-stop must wait for the guest to stop after issuing shutdown.'
        Assert-True -Condition ($script:DoHibernateStopWaitInvocation.MaxAttempts -eq 24) -Message 'Hibernate-stop must use the bounded wait contract.'
        Assert-True -Condition ($null -ne $script:DoHibernateStopReportedSnapshot) -Message 'Hibernate-stop must print the final VM status.'
        Assert-True -Condition ([string]$script:DoHibernateStopReportedSnapshot.NormalizedState -eq 'stopped') -Message 'Hibernate-stop must report the post-hibernate stopped state.'
    }
    finally {
        foreach ($functionName in @(
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmLifecycleSnapshot',
            'Invoke-ClagnosDoGuestHibernateStopCommand',
            'Wait-ClagnosDoHibernateStopCompletion',
            'Write-ClagnosDoStatusReport'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Connection command running-state guard" -Action {
    function New-TestConnectionSnapshot {
        param(
            [string]$NormalizedState,
            [string]$PowerStateDisplay,
            [string]$HibernationStateDisplay = '',
            [string]$HibernationStateCode = ''
        )

        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            NormalizedState = $NormalizedState
            PowerStateDisplay = $PowerStateDisplay
            PowerStateCode = ''
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            ProvisioningStateDisplay = 'Provisioning succeeded'
            HibernationStateDisplay = $HibernationStateDisplay
            HibernationStateCode = $HibernationStateCode
        }
    }

    Assert-ClagnosConnectionVmRunning -OperationName 'connect-ssh' -Snapshot (New-TestConnectionSnapshot -NormalizedState 'started' -PowerStateDisplay 'VM running')

    $invalidCases = @(
        @{ Operation = 'connect-ssh'; Snapshot = (New-TestConnectionSnapshot -NormalizedState 'stopped' -PowerStateDisplay 'VM stopped') },
        @{ Operation = 'connect-rdp'; Snapshot = (New-TestConnectionSnapshot -NormalizedState 'deallocated' -PowerStateDisplay 'VM deallocated') },
        @{ Operation = 'connect-ssh'; Snapshot = (New-TestConnectionSnapshot -NormalizedState 'hibernated' -PowerStateDisplay 'VM deallocated' -HibernationStateDisplay 'Hibernated' -HibernationStateCode 'HibernationState/hibernated') }
    )

    foreach ($case in @($invalidCases)) {
        $threw = $false
        try {
            Assert-ClagnosConnectionVmRunning -OperationName ([string]$case.Operation) -Snapshot $case.Snapshot
        }
        catch {
            $threw = $true
        }
        Assert-True -Condition $threw -Message ("Connection guard should reject non-running VM state for '{0}'." -f [string]$case.Operation)
    }
}

Invoke-Test -Name "Connection context checks VM state before credentials" -Action {
    $script:TestConnectionCredentialsCalled = $false
    try {
        function Test-ClagnosLocalWindowsHost { return $true }
        function Get-ClagnosRepoRoot { return $RepoRoot }
        function Read-DotEnvFile { param([string]$Path) return @{} }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosVmLifecycleSnapshot {
            param([string]$ResourceGroup, [string]$VmName)
            return [pscustomobject]@{
                ResourceGroup = $ResourceGroup
                VmName = $VmName
                OsType = 'Windows'
                Location = 'austriaeast'
                HibernationEnabled = $true
                ProvisioningStateCode = 'ProvisioningState/succeeded'
                ProvisioningStateDisplay = 'Provisioning succeeded'
                PowerStateCode = 'PowerState/stopped'
                PowerStateDisplay = 'VM stopped'
                HibernationStateCode = ''
                HibernationStateDisplay = ''
                NormalizedState = 'stopped'
            }
        }
        function Resolve-ClagnosConnectionPortText { param([hashtable]$ConfigMap, [string]$Key, [string]$DefaultValue, [string]$Label) return [string]$DefaultValue }
        function Resolve-ClagnosConnectionRoleName { param([hashtable]$Options) return 'manager' }
        function Resolve-ClagnosConnectionCredentials {
            param([string]$RoleName, [hashtable]$ConfigMap, [string]$EnvFilePath)
            $script:TestConnectionCredentialsCalled = $true
            return [pscustomobject]@{
                Role = 'manager'
                UserName = 'manager'
                Password = 'secret'
            }
        }
        function Get-ClagnosVmDetails { throw 'Get-ClagnosVmDetails should not run when the VM is not running.' }

        $threw = $false
        try {
            Initialize-ClagnosConnectionCommandContext -Options @{ ssh = $true } -OperationName 'connect-ssh' | Out-Null
        }
        catch {
            $threw = $true
        }

        Assert-True -Condition $threw -Message "Connection context should stop when the VM is not running."
        Assert-True -Condition (-not $script:TestConnectionCredentialsCalled) -Message "Connection context must reject non-running VMs before credential resolution."
    }
    finally {
        foreach ($functionName in @(
            'Test-ClagnosLocalWindowsHost',
            'Get-ClagnosRepoRoot',
            'Read-DotEnvFile',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmLifecycleSnapshot',
            'Resolve-ClagnosConnectionPortText',
            'Resolve-ClagnosConnectionRoleName',
            'Resolve-ClagnosConnectionCredentials',
            'Get-ClagnosVmDetails'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name TestConnectionCredentialsCalled -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Lifecycle provisioning repair redeploys when Updating persists" -Action {
    $script:LifecycleRepairSnapshots = @(
        [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            NormalizedState = 'started'
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/updating'
            ProvisioningStateDisplay = 'Updating'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
        },
        [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            NormalizedState = 'started'
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/updating'
            ProvisioningStateDisplay = 'Updating'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
        },
        [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
            NormalizedState = 'started'
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            ProvisioningStateDisplay = 'Provisioning succeeded'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
        }
    )
    $script:LifecycleRepairSnapshotIndex = 0
    $script:LifecycleRepairAzCalls = @()
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Get-ClagnosVmLifecycleSnapshot',
        'Invoke-TrackedAction',
        'Assert-LastExitCode',
        'az'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Get-ClagnosVmLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName)
        $index = [int]$script:LifecycleRepairSnapshotIndex
        if ($index -ge @($script:LifecycleRepairSnapshots).Count) {
            $index = @($script:LifecycleRepairSnapshots).Count - 1
        }

        $snapshot = $script:LifecycleRepairSnapshots[$index]
        $script:LifecycleRepairSnapshotIndex = $script:LifecycleRepairSnapshotIndex + 1
        return $snapshot
    }
    function Invoke-TrackedAction {
        param([string]$Label, [scriptblock]$Action)
        & $Action
        return [pscustomobject]@{ Label = $Label }
    }
    function Assert-LastExitCode { param([string]$Context) }
    function az {
        $script:LifecycleRepairAzCalls += ,(@($args) -join ' ')
        $global:LASTEXITCODE = 0
        return ''
    }
    function Start-Sleep { param([int]$Seconds) }

    try {
        $result = Wait-ClagnosProvisioningReadyOrRepair -ResourceGroup 'rg-samplevm-ate1-g1' -VmName 'samplevm' -MaxAttempts 3 -DelaySeconds 1 -UpdatingAttemptsBeforeRedeploy 2
        Assert-True -Condition ([bool]$result.Ready) -Message 'Lifecycle provisioning repair must return ready after successful redeploy recovery.'
        Assert-True -Condition ((@($script:LifecycleRepairAzCalls) | Where-Object { $_ -like 'vm redeploy*' }).Count -eq 1) -Message 'Lifecycle provisioning repair must trigger one Azure VM redeploy when Updating persists.'
        Assert-True -Condition ([int]$result.RedeployCount -eq 1) -Message 'Lifecycle provisioning repair must report the redeploy count.'
    }
    finally {
        foreach ($functionName in @(
            'Get-ClagnosVmLifecycleSnapshot',
            'Invoke-TrackedAction',
            'Assert-LastExitCode',
            'az'
        )) {
            Remove-Item ("Function:\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
        Remove-Item Function:\Start-Sleep -ErrorAction SilentlyContinue
        Remove-Variable -Name LifecycleRepairSnapshots -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name LifecycleRepairSnapshotIndex -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name LifecycleRepairAzCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Show report redacts password-bearing config values and prints nested state" -Action {
    $script:ShowReportCapturedHostLines = @()
    try {
        function Write-Host {
            param(
                [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
                [object[]]$Object,
                [ConsoleColor]$ForegroundColor,
                [ConsoleColor]$BackgroundColor,
                [switch]$NoNewline,
                [object]$Separator
            )

            $script:ShowReportCapturedHostLines += ,((@($Object) | ForEach-Object { [string]$_ }) -join ' ')
        }

        $dump = [ordered]@{
            GeneratedAtUtc = '2026-03-11T00:00:00Z'
            Command = 'show'
            Mode = 'auto'
            RequestedPlatform = 'windows'
            EnvFilePath = 'C:\repo\.env'
            AzureAccount = [ordered]@{
                SubscriptionName = 'sub'
                SubscriptionId = 'sub-id'
                TenantName = 'tenant'
                TenantId = 'tenant-id'
                UserName = '<email>'
            }
            Config = [ordered]@{
                DotEnvValues = [ordered]@{
                    VM_ADMIN_PASS = '<runtime-secret>'
                    VM_ASSISTANT_PASS = '<runtime-secret>'
                    VM_NAME = 'samplevm'
                }
                RuntimeOverrides = [ordered]@{
                    VM_ADMIN_PASS = '<runtime-secret>'
                    RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
                }
            }
            Selection = [ordered]@{
                TargetGroup = 'rg-samplevm-ate1-g1'
                IncludedResourceGroups = @('rg-samplevm-ate1-g1')
            }
            Summary = [ordered]@{
                ResourceGroupCount = 1
                TotalVmCount = 1
                RunningVmCount = 1
            }
            ResourceGroups = @(
                [ordered]@{
                    Name = 'rg-samplevm-ate1-g1'
                    Exists = $true
                    Location = 'austriaeast'
                    ProvisioningState = 'Succeeded'
                    ResourceCount = 6
                    VmCount = 1
                    ResourceTypeCounts = [ordered]@{
                        'Microsoft.Compute/virtualMachines' = 1
                    }
                    Resources = @()
                    Vms = @(
                        [ordered]@{
                            Name = 'samplevm'
                            PowerState = 'VM running'
                            ProvisioningState = 'Succeeded'
                            Location = 'austriaeast'
                            VmSize = 'Standard_D4as_v5'
                            SkuAvailability = 'yes'
                            OsType = 'Windows'
                            PublicIps = '1.2.3.4'
                            PrivateIps = '10.0.0.4'
                            Fqdns = 'samplevm.example'
                            OsDiskName = 'disk-samplevm'
                            DataDiskNames = @()
                            NicIds = @()
                            FeatureFlags = [ordered]@{
                                HibernationEnabled = $true
                                NestedVirtualizationEnabled = $true
                                NestedVirtualizationValidationSource = 'guest'
                                NestedVirtualizationEvidence = @(
                                    'VMMonitorModeExtensions=True',
                                    'VirtualizationFirmwareEnabled=True'
                                )
                            }
                            FocusedCapabilities = @(
                                [pscustomobject]@{ name = 'NestedVirtualization'; value = 'True' }
                            )
                        }
                    )
                }
            )
        }

        Write-ClagnosShowReport -Dump $dump

        $outputText = $script:ShowReportCapturedHostLines -join "`n"
        Assert-True -Condition ($outputText -match [regex]::Escape('VM_ADMIN_PASS: [redacted]')) -Message 'Show report must redact the admin password.'
        Assert-True -Condition ($outputText -match [regex]::Escape('VM_ASSISTANT_PASS: [redacted]')) -Message 'Show report must redact the assistant password.'
        Assert-True -Condition (-not ($outputText -match [regex]::Escape('<runtime-secret>'))) -Message 'Show report must not print the raw admin password.'
        Assert-True -Condition (-not ($outputText -match [regex]::Escape('<runtime-secret>'))) -Message 'Show report must not print the raw assistant password.'
        Assert-True -Condition ($outputText -match [regex]::Escape('Nested virtualization enabled: True')) -Message 'Show report must print the nested virtualization enabled state.'
        Assert-True -Condition ($outputText -match [regex]::Escape('Nested virtualization validation source: guest')) -Message 'Show report must print the nested virtualization validation source.'
        Assert-True -Condition ($outputText -match [regex]::Escape('VirtualizationFirmwareEnabled=True')) -Message 'Show report must print nested virtualization guest evidence.'
        Assert-True -Condition ($outputText -match [regex]::Escape('VM_NAME: samplevm')) -Message 'Show report must keep non-secret config values visible.'
    }
    finally {
        Remove-Item Function:\Write-Host -ErrorAction SilentlyContinue
        Remove-Variable -Name ShowReportCapturedHostLines -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Show JSON export redacts passwords, tokens, and refuses implicit overwrite" -Action {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $exportRoot = Join-Path $tempBase ('clagnos-show-export-test-' + [guid]::NewGuid().ToString('N'))
    $exportPath = Join-Path $exportRoot 'report.json'
    New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
    $dump = [ordered]@{
        Command = 'show'
        Config = [ordered]@{
            DotEnvValues = [ordered]@{ VM_ADMIN_PASS = '<runtime-secret>'; VM_NAME = 'samplevm' }
            RuntimeOverrides = [ordered]@{ MAP_ACCESS_TOKEN = '<runtime-secret>' }
        }
        TargetDerivedConfiguration = [ordered]@{ Summary = [ordered]@{ VM_ASSISTANT_PASS = '<runtime-secret>'; SelectedRegion = 'austriaeast' } }
    }
    try {
        Export-ClagnosShowReportJson -Dump $dump -OutputPath $exportPath | Out-Null
        $jsonText = [string](Get-Content -LiteralPath $exportPath -Raw)
        $export = ConvertFrom-JsonCompat -InputObject $jsonText
        Assert-True -Condition ([string]$export.Config.DotEnvValues.VM_ADMIN_PASS -eq '[redacted]') -Message 'Show JSON export must redact passwords in .env values.'
        Assert-True -Condition ([string]$export.Config.RuntimeOverrides.MAP_ACCESS_TOKEN -eq '[redacted]') -Message 'Show JSON export must redact tokens in runtime overrides.'
        Assert-True -Condition ([string]$export.TargetDerivedConfiguration.Summary.VM_ASSISTANT_PASS -eq '[redacted]') -Message 'Show JSON export must redact sensitive target-derived values.'
        Assert-True -Condition (-not ($jsonText -match 'runtime-secret')) -Message 'Show JSON export must not contain raw secrets.'

        $overwriteBlocked = $false
        try { Export-ClagnosShowReportJson -Dump $dump -OutputPath $exportPath | Out-Null }
        catch { $overwriteBlocked = $true }
        Assert-True -Condition $overwriteBlocked -Message 'Show JSON export must refuse to overwrite an existing file by default.'
        Export-ClagnosShowReportJson -Dump $dump -OutputPath $exportPath -Overwrite | Out-Null
    }
    finally {
        $resolvedExportRoot = [System.IO.Path]::GetFullPath($exportRoot)
        $resolvedTempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $resolvedExportRoot.StartsWith(($resolvedTempBase + 'clagnos-show-export-test-'), [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ("Refusing to remove unexpected show export test path: {0}" -f $resolvedExportRoot)
        }
        if (Test-Path -LiteralPath $resolvedExportRoot) { Remove-Item -LiteralPath $resolvedExportRoot -Recurse -Force }
    }
}

Invoke-Test -Name "Step first-use values redact sensitive fields" -Action {
    $script:StepFirstUseCapturedHostLines = @()
    try {
        Remove-Variable -Name ClagnosFirstUseTracker -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ClagnosValueStateTracker -Scope Script -ErrorAction SilentlyContinue

        function Write-Host {
            param(
                [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
                [object[]]$Object,
                [ConsoleColor]$ForegroundColor,
                [ConsoleColor]$BackgroundColor,
                [switch]$NoNewline,
                [object]$Separator
            )

            $script:StepFirstUseCapturedHostLines += ,((@($Object) | ForEach-Object { [string]$_ }) -join ' ')
        }

        Show-ClagnosStepFirstUseValues `
            -StepLabel 'Step 4/7 - VM create' `
            -Context ([ordered]@{
                VmName = 'samplevm'
                VmUser = 'manager'
                VmPass = '<runtime-secret>'
                VmAssistantUser = 'assistant'
                VmAssistantPass = '<runtime-secret-2>'
            }) `
            -Keys @('VmName', 'VmUser', 'VmPass', 'VmAssistantUser', 'VmAssistantPass') `
            -ExtraValues @{ VmExecutionMode = 'default' }

        $outputText = $script:StepFirstUseCapturedHostLines -join "`n"
        Assert-True -Condition ($outputText -match [regex]::Escape('VmPass = [redacted]')) -Message 'Step review must redact VmPass.'
        Assert-True -Condition ($outputText -match [regex]::Escape('VmAssistantPass = [redacted]')) -Message 'Step review must redact VmAssistantPass.'
        Assert-True -Condition (-not ($outputText -match [regex]::Escape('<runtime-secret>'))) -Message 'Step review must not print the raw admin password.'
        Assert-True -Condition (-not ($outputText -match [regex]::Escape('<runtime-secret-2>'))) -Message 'Step review must not print the raw assistant password.'
        Assert-True -Condition ($outputText -match [regex]::Escape('VM_ADMIN_USER = manager')) -Message 'Step review must keep VM_ADMIN_USER visible.'
        Assert-True -Condition ($outputText -match [regex]::Escape('SELECTED_VM_NAME = samplevm')) -Message 'Step review must keep SELECTED_VM_NAME visible.'
    }
    finally {
        Remove-Item Function:\Write-Host -ErrorAction SilentlyContinue
        Remove-Variable -Name StepFirstUseCapturedHostLines -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ClagnosFirstUseTracker -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ClagnosValueStateTracker -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "SSH identity output matcher accepts machine-qualified usernames" -Action {
    Assert-True -Condition (Test-ClagnosConnectionIdentityOutputMatchesUser -ExpectedUserName 'manager' -OutputText "samplevm\manager") -Message 'Identity matcher must accept machine-qualified usernames.'
    Assert-True -Condition (Test-ClagnosConnectionIdentityOutputMatchesUser -ExpectedUserName 'assistant' -OutputText "assistant") -Message 'Identity matcher must accept plain usernames.'
    Assert-True -Condition (-not (Test-ClagnosConnectionIdentityOutputMatchesUser -ExpectedUserName 'manager' -OutputText "samplevm\assistant")) -Message 'Identity matcher must reject a different user.'
}

Invoke-Test -Name "Connect --ssh test mode performs a non-interactive handshake without launching ssh.exe" -Action {
    $script:SshTestStartedProcess = $false
    $script:SshTestProcessInvocation = $null
    try {
        function Initialize-ClagnosConnectionCommandContext {
            param([hashtable]$Options, [string]$OperationName)
            return [pscustomobject]@{
                ConfigMap = @{
                    PYSSH_CLIENT_PATH = 'tools/pyssh/ssh_client.py'
                    SSH_MAX_RETRIES = '2'
                    SSH_CONNECT_TIMEOUT_SECONDS = '30'
                }
                VmName = 'samplevm'
                ResourceGroup = 'rg-samplevm-ate1-g1'
                ConnectionHost = 'samplevm.example'
                SelectedUserName = 'manager'
                SelectedPassword = 'secret'
                VmSshPort = '444'
            }
        }
        function Wait-ClagnosTcpPortReachable { param([string]$HostName, [int]$Port, [int]$MaxAttempts, [int]$DelaySeconds, [int]$TimeoutSeconds, [string]$Label) return $true }
        function Get-ClagnosRepoRoot { return $RepoRoot }
        function Ensure-ClagnosPySshTools { param([string]$RepoRoot, [string]$ConfiguredPySshClientPath) return @{ PythonPath = 'python.exe'; ClientPath = 'ssh_client.py' } }
        function Invoke-ClagnosProcessWithRetry {
            param([string]$FilePath, [string[]]$Arguments, [string]$Label, [int]$MaxAttempts, [switch]$AllowFailure)
            $script:SshTestProcessInvocation = [pscustomobject]@{
                FilePath = $FilePath
                Arguments = @($Arguments)
                Label = $Label
                MaxAttempts = $MaxAttempts
                AllowFailure = [bool]$AllowFailure
            }
            return [pscustomobject]@{
                ExitCode = 0
                Output = "samplevm\manager"
            }
        }
        function Start-Process {
            param()
            $script:SshTestStartedProcess = $true
        }
        function Resolve-ClagnosLocalExecutablePath { throw 'Local SSH executable should not resolve in --test mode.' }

        Invoke-ClagnosConnectCommand -Options @{ ssh = $true; test = $true; user = 'manager' }

        Assert-True -Condition ($null -ne $script:SshTestProcessInvocation) -Message 'SSH test mode must invoke the pyssh process.'
        Assert-True -Condition (-not $script:SshTestStartedProcess) -Message 'SSH test mode must not launch the external SSH client.'
        Assert-True -Condition ((@($script:SshTestProcessInvocation.Arguments) -join ' ') -match [regex]::Escape('--command whoami')) -Message 'SSH test mode must execute a whoami handshake.'
        Assert-True -Condition ([int]$script:SshTestProcessInvocation.MaxAttempts -eq 2) -Message 'SSH test mode must honor SSH_MAX_RETRIES.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosConnectionCommandContext',
            'Wait-ClagnosTcpPortReachable',
            'Get-ClagnosRepoRoot',
            'Ensure-ClagnosPySshTools',
            'Invoke-ClagnosProcessWithRetry',
            'Start-Process',
            'Resolve-ClagnosLocalExecutablePath'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name SshTestStartedProcess -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name SshTestProcessInvocation -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Connect --rdp test mode checks reachability without launching mstsc" -Action {
    $script:RdpTestStartedProcess = $false
    $script:RdpTestReachabilityCalls = @()
    try {
        function Initialize-ClagnosConnectionCommandContext {
            param([hashtable]$Options, [string]$OperationName)
            return [pscustomobject]@{
                VmName = 'samplevm'
                ResourceGroup = 'rg-samplevm-ate1-g1'
                ConnectionHost = 'samplevm.example'
                SelectedUserName = 'manager'
                SelectedPassword = 'secret'
                VmRdpPort = '3389'
                OsType = 'Windows'
            }
        }
        function Wait-ClagnosTcpPortReachable {
            param([string]$HostName, [int]$Port, [int]$MaxAttempts, [int]$DelaySeconds, [int]$TimeoutSeconds, [string]$Label)
            $script:RdpTestReachabilityCalls += ,([pscustomobject]@{
                HostName = $HostName
                Port = $Port
                Label = $Label
            })
            return $true
        }
        function Start-Process {
            param()
            $script:RdpTestStartedProcess = $true
        }
        function Resolve-ClagnosLocalExecutablePath { throw 'Local RDP executables should not resolve in --test mode.' }

        Invoke-ClagnosConnectCommand -Options @{ rdp = $true; test = $true; user = 'manager' }

        Assert-True -Condition (@($script:RdpTestReachabilityCalls).Count -eq 1) -Message 'RDP test mode must perform a TCP reachability check.'
        Assert-True -Condition ([int]$script:RdpTestReachabilityCalls[0].Port -eq 3389) -Message 'RDP test mode must probe the resolved RDP port.'
        Assert-True -Condition (-not $script:RdpTestStartedProcess) -Message 'RDP test mode must not launch mstsc.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosConnectionCommandContext',
            'Wait-ClagnosTcpPortReachable',
            'Start-Process',
            'Resolve-ClagnosLocalExecutablePath'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name RdpTestStartedProcess -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name RdpTestReachabilityCalls -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Connect --powershell runs a remote command through a managed PSSession" -Action {
    $script:PowerShellConnectInvocation = $null
    $script:PowerShellSessionRemoved = $false
    try {
        function Initialize-ClagnosConnectionCommandContext {
            param([hashtable]$Options, [string]$OperationName)
            return [pscustomobject]@{
                VmName = 'samplevm'
                ResourceGroup = 'rg-samplevm-ate1-g1'
                ConnectionHost = 'samplevm.example'
                SelectedUserName = 'manager'
                SelectedPassword = 'secret'
                VmPowerShellPort = '5985'
                OsType = 'Windows'
            }
        }
        function Assert-ClagnosPowerShellVm { param([psobject]$Runtime) }
        function New-ClagnosPowerShellRemotingSession { param([psobject]$Runtime) return [pscustomobject]@{ Id = 1 } }
        function Invoke-ClagnosPowerShellRemoteCommand {
            param([object]$Session, [string]$CommandText)
            $script:PowerShellConnectInvocation = [pscustomobject]@{ Session = $Session; CommandText = $CommandText }
        }
        function Remove-PSSession { param([object]$Session, [string]$ErrorAction) $script:PowerShellSessionRemoved = $true }
        function Write-ClagnosActionProgress { param([string]$Action) }

        Invoke-ClagnosConnectCommand -Options @{ powershell = $true; command = 'Get-Date'; user = 'manager' }

        Assert-True -Condition ($null -ne $script:PowerShellConnectInvocation) -Message 'PowerShell command mode must invoke the remote command helper.'
        Assert-True -Condition ([string]$script:PowerShellConnectInvocation.CommandText -eq 'Get-Date') -Message 'PowerShell command mode must preserve the selected remote command.'
        Assert-True -Condition ($script:PowerShellSessionRemoved) -Message 'PowerShell command mode must close its PSSession.'
    }
    finally {
        foreach ($functionName in @('Initialize-ClagnosConnectionCommandContext','Assert-ClagnosPowerShellVm','New-ClagnosPowerShellRemotingSession','Invoke-ClagnosPowerShellRemoteCommand','Remove-PSSession','Write-ClagnosActionProgress')) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name PowerShellConnectInvocation -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name PowerShellSessionRemoved -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "PowerShell remoting creates a Negotiate session with the selected local account" -Action {
    $script:PowerShellSessionParameters = $null
    $script:PowerShellSessionProgress = @()
    try {
        function New-PSSession {
            [CmdletBinding()]
            param(
                [string]$ComputerName,
                [int]$Port,
                [System.Management.Automation.PSCredential]$Credential,
                [string]$Authentication
            )
            $script:PowerShellSessionParameters = [pscustomobject]@{
                ComputerName = $ComputerName
                Port = $Port
                Credential = $Credential
                Authentication = $Authentication
            }
            return [pscustomobject]@{ Id = 4 }
        }
        function Write-ClagnosActionProgress { param([string]$Action) $script:PowerShellSessionProgress += $Action }

        $session = New-ClagnosPowerShellRemotingSession -Runtime ([pscustomobject]@{
            ConnectionHost = 'samplevm.example'
            VmPowerShellPort = '5985'
            SelectedUserName = 'manager'
            SelectedPassword = 'secret'
        })

        Assert-True -Condition ($null -ne $session) -Message 'PowerShell remoting must return the opened session.'
        Assert-True -Condition ([string]$script:PowerShellSessionParameters.ComputerName -eq 'samplevm.example') -Message 'PowerShell remoting must target the resolved VC host.'
        Assert-True -Condition ([int]$script:PowerShellSessionParameters.Port -eq 5985) -Message 'PowerShell remoting must use the WinRM port.'
        Assert-True -Condition ([string]$script:PowerShellSessionParameters.Authentication -eq 'Negotiate') -Message 'PowerShell remoting must use Negotiate authentication.'
        Assert-True -Condition ([string]$script:PowerShellSessionParameters.Credential.UserName -eq '.\manager') -Message 'PowerShell remoting must use the selected local VM account.'
        Assert-True -Condition ([string]$script:PowerShellSessionParameters.Credential.GetNetworkCredential().Password -eq 'secret') -Message 'PowerShell credentials must be passed through a PSCredential object.'
        Assert-True -Condition ((@($script:PowerShellSessionProgress) -join ' ') -notmatch 'secret') -Message 'PowerShell progress labels must never disclose the password.'
    }
    finally {
        Remove-Item Function:\New-PSSession -ErrorAction SilentlyContinue
        Remove-Item Function:\Write-ClagnosActionProgress -ErrorAction SilentlyContinue
        Remove-Variable -Name PowerShellSessionParameters -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name PowerShellSessionProgress -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Connect --powershell test verifies the WinRM endpoint and remote account" -Action {
    $script:PowerShellTestPorts = @()
    $script:PowerShellTestSessionRemoved = $false
    try {
        function Initialize-ClagnosConnectionCommandContext {
            param([hashtable]$Options, [string]$OperationName)
            return [pscustomobject]@{
                VmName = 'samplevm'
                ResourceGroup = 'rg-samplevm-ate1-g1'
                ConnectionHost = 'samplevm.example'
                SelectedUserName = 'manager'
                SelectedPassword = 'secret'
                VmPowerShellPort = '5985'
                OsType = 'Windows'
            }
        }
        function Wait-ClagnosTcpPortReachable {
            param([string]$HostName, [int]$Port, [int]$MaxAttempts, [int]$DelaySeconds, [int]$TimeoutSeconds, [string]$Label)
            $script:PowerShellTestPorts += ,([pscustomobject]@{ HostName = $HostName; Port = $Port; Label = $Label })
            return $true
        }
        function New-ClagnosPowerShellRemotingSession { param([psobject]$Runtime) return [pscustomobject]@{ Id = 2 } }
        function Invoke-Command {
            [CmdletBinding()]
            param([object]$Session, [scriptblock]$ScriptBlock, [object[]]$ArgumentList)
            return @('samplevm', 'samplevm\manager')
        }
        function Remove-PSSession { param([object]$Session, [string]$ErrorAction) $script:PowerShellTestSessionRemoved = $true }

        Invoke-ClagnosPowerShellConnectivityTest -Options @{ powershell = $true; test = $true; user = 'manager' }

        Assert-True -Condition (@($script:PowerShellTestPorts).Count -eq 1) -Message 'PowerShell remoting test must probe the configured TCP endpoint.'
        Assert-True -Condition ([int]$script:PowerShellTestPorts[0].Port -eq 5985) -Message 'PowerShell remoting test must use the default WinRM port.'
        Assert-True -Condition ($script:PowerShellTestSessionRemoved) -Message 'PowerShell remoting test must close its temporary PSSession.'
    }
    finally {
        foreach ($functionName in @('Initialize-ClagnosConnectionCommandContext','Wait-ClagnosTcpPortReachable','New-ClagnosPowerShellRemotingSession','Invoke-Command','Remove-PSSession')) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name PowerShellTestPorts -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name PowerShellTestSessionRemoved -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "PowerShell remoting interactive shell dispatches commands and exits cleanly" -Action {
    $script:PowerShellInteractiveCommands = @()
    $script:PowerShellInteractiveChoices = New-Object 'System.Collections.Generic.Queue[string]'
    $script:PowerShellInteractiveChoices.Enqueue('Get-Date')
    $script:PowerShellInteractiveChoices.Enqueue('exit')
    try {
        function Read-Host { param([string]$Prompt) return $script:PowerShellInteractiveChoices.Dequeue() }
        function Invoke-ClagnosPowerShellRemoteCommand { param([object]$Session, [string]$CommandText) $script:PowerShellInteractiveCommands += $CommandText }

        Invoke-ClagnosInteractivePowerShellSession -Session ([pscustomobject]@{ Id = 3 }) -ConnectionHost 'samplevm.example' -VmName 'samplevm'

        Assert-True -Condition (@($script:PowerShellInteractiveCommands).Count -eq 1) -Message 'Interactive PowerShell shell must dispatch entered commands.'
        Assert-True -Condition ([string]$script:PowerShellInteractiveCommands[0] -eq 'Get-Date') -Message 'Interactive PowerShell shell must stop before sending the exit command remotely.'
    }
    finally {
        Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
        Remove-Item Function:\Invoke-ClagnosPowerShellRemoteCommand -ErrorAction SilentlyContinue
        Remove-Variable -Name PowerShellInteractiveCommands -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name PowerShellInteractiveChoices -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Connect rejects mixed transports and SSH command execution" -Action {
    $mixedTransportThrew = $false
    try { Resolve-ClagnosConnectMode -Options @{ ssh = $true; powershell = $true } | Out-Null }
    catch { $mixedTransportThrew = $true }
    Assert-True -Condition $mixedTransportThrew -Message 'Connect must require exactly one transport selector.'

    $sshCommandThrew = $false
    try { Invoke-ClagnosConnectCommand -Options @{ ssh = $true; command = 'Get-Date' } }
    catch { $sshCommandThrew = $true }
    Assert-True -Condition $sshCommandThrew -Message 'The --command option must be rejected with SSH transport.'
}

Invoke-Test -Name "Persistent SSH protocol normalizes spinner-prefixed markers" -Action {
    $normalizedEnd = Normalize-ClagnosProtocolLine -Text '   / CLAGNOS_TASK_END:117-install-teams-application:4294967295'
    Assert-True -Condition ([string]$normalizedEnd -eq 'CLAGNOS_TASK_END:117-install-teams-application:4294967295') -Message 'Spinner-prefixed task end markers must normalize back to the protocol marker.'

    $normalizedError = Normalize-ClagnosProtocolLine -Text '  - [stderr] CLAGNOS_SESSION_TASK_ERROR:117-install-teams-application:example'
    Assert-True -Condition ([string]$normalizedError -eq '[stderr] CLAGNOS_SESSION_TASK_ERROR:117-install-teams-application:example') -Message 'Spinner-prefixed stderr session markers must normalize back to the protocol marker.'

    Assert-True -Condition ((Convert-ClagnosProtocolTaskExitCode -Text '0') -eq 0) -Message 'Task exit code parser must keep zero as zero.'
    Assert-True -Condition ((Convert-ClagnosProtocolTaskExitCode -Text '4294967295') -eq -1) -Message 'Task exit code parser must normalize unsigned 32-bit -1 markers back to -1.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text "WARNING: Ignoring checksums due to feature checksumFiles turned off or option --ignore-checksums set.") -Message 'Protocol noise filters must suppress expected Chocolatey checksum warnings.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text "[stderr] WARNING: The Windows Subsystem for Linux is not installed. You can install by running 'wsl.exe --install'.") -Message 'Protocol noise filters must suppress stderr-prefixed WSL bootstrap warnings.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text 'WARNING: wsl.exe : The Windows Subsystem for Linux is not installed. You ') -Message 'Protocol noise filters must suppress split WSL bootstrap warning headers.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text "WARNING: can install by running 'wsl.exe --install'.") -Message 'Protocol noise filters must suppress split WSL bootstrap continuation lines.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text 'WARNING: +     FullyQualifiedErrorId : NativeCommandError') -Message 'Protocol noise filters must suppress benign WSL NativeCommandError metadata.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text 'WARNING: npm notice New minor version of npm available! 11.9.0 -> 11.12.0') -Message 'Protocol noise filters must suppress benign npm notice chatter.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text 'WARNING: npm warn deprecated prebuild-install@7.1.3: No longer maintained.') -Message 'Protocol noise filters must suppress benign npm deprecation chatter.'
    Assert-True -Condition (Test-ClagnosTaskOutputNoiseLine -Text "errors pretty printing info") -Message 'Protocol noise filters must suppress transient Docker info pretty-print noise.'
}

Invoke-Test -Name "Persistent SSH task runner restores the session after transient task drops" -Action {
    $runnerPath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-ssh-task-runner.ps1'
    Assert-True -Condition (Test-Path -LiteralPath $runnerPath) -Message 'Persistent SSH task runner file was not found.'

    $runnerText = [string](Get-Content -LiteralPath $runnerPath -Raw)
    foreach ($fragment in @(
        'function Restore-ClagnosTaskSession',
        'function Invoke-ClagnosOneShotTaskTransportRecovery',
        'Wait-ClagnosTcpPortReachable',
        'Attempting persistent SSH session recovery:',
        'Attempting one-shot SSH recovery:',
        'pre-task bootstrap for',
        'post-warning recovery after task',
        'Persistent SSH session recovery is still unavailable after task',
        'One-shot SSH task preparation or execution failed for',
        'One-shot SSH recovery probe failed before retrying'
    )) {
        Assert-True -Condition ($runnerText -like ('*' + [string]$fragment + '*')) -Message ("Persistent SSH task runner must include fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Windows SSH task runner retries asset copy failures through one-shot recovery" -Action {
    $script:RetryingAssetCopyCalls = 0
    $script:RetryingTaskScriptCalls = 0
    $script:RetryingTcpReachabilityCalls = @()
    $script:RetryingBootstrapCalls = 0
    try {
        function Ensure-ClagnosPySshTools {
            param([string]$RepoRoot, [string]$ConfiguredPySshClientPath)
            return @{ PythonPath = 'python.exe'; ClientPath = 'ssh_client.py' }
        }
        function Initialize-ClagnosSshHostKey {
            param()
            $script:RetryingBootstrapCalls++
            return [pscustomobject]@{ Output = ''; HostKey = 'auto-add'; ExitCode = 0 }
        }
        function Wait-ClagnosProvisioningReadyOrRepair {
            param([string]$ResourceGroup, [string]$VmName)
            return [pscustomobject]@{ Ready = $true; Snapshot = [pscustomobject]@{} }
        }
        function Wait-ClagnosTcpPortReachable {
            param([string]$HostName, [int]$Port, [int]$MaxAttempts, [int]$DelaySeconds, [int]$TimeoutSeconds, [string]$Label)
            $script:RetryingTcpReachabilityCalls += ,([pscustomobject]@{
                HostName = $HostName
                Port = $Port
                MaxAttempts = $MaxAttempts
                DelaySeconds = $DelaySeconds
                TimeoutSeconds = $TimeoutSeconds
                Label = $Label
            })
            return $true
        }
        function Get-ClagnosTaskTimeoutSeconds {
            param([psobject]$TaskBlock, [int]$DefaultTimeoutSeconds)
            return 60
        }
        function Copy-ClagnosAssetToVm {
            param()
            $script:RetryingAssetCopyCalls++
            if ($script:RetryingAssetCopyCalls -eq 1) {
                throw 'Error reading SSH protocol banner'
            }
        }
        function Invoke-ClagnosSshTaskScript {
            param()
            $script:RetryingTaskScriptCalls++
            return [pscustomobject]@{
                ExitCode = 0
                Output = 'task-ok'
                OutputRelayedLive = $false
            }
        }
        function Invoke-ClagnosTaskAppStatePostProcess { return $null }
        function Test-ClagnosOutputIndicatesRebootRequired { return $false }

        $taskBlocks = @(
            [pscustomobject]@{
                Name = '114-install-teams-application'
                Script = 'Write-Host ok'
                TimeoutSeconds = 120
                AssetCopies = @(
                    [pscustomobject]@{
                        LocalPath = 'modules\\core\\tasks\\clagnos-store-install-state.psm1'
                        RemotePath = 'C:/Windows/Temp/clagnos-store-install-state.psm1'
                    }
                )
            }
        )

        $result = Invoke-ClagnosSshTaskBlocks `
            -Platform 'windows' `
            -RepoRoot $RepoRoot `
            -SshHost 'samplevm.example' `
            -SshUser 'manager' `
            -SshPassword 'secret' `
            -SshPort '444' `
            -ResourceGroup 'rg-samplevm-ate1-g1' `
            -VmName 'samplevm' `
            -TaskBlocks $taskBlocks `
            -TaskOutcomeMode 'continue' `
            -PerfTaskCategory 'vm-update-task' `
            -SshMaxRetries 3 `
            -SshTaskTimeoutSeconds 180 `
            -SshConnectTimeoutSeconds 30 `
            -ConfiguredPySshClientPath ''

        Assert-True -Condition ([int]$script:RetryingAssetCopyCalls -eq 2) -Message 'One-shot SSH asset copy failures must retry on the next task attempt.'
        Assert-True -Condition ([int]$script:RetryingTaskScriptCalls -eq 1) -Message 'Task execution must continue after the asset copy retry succeeds.'
        Assert-True -Condition (@($script:RetryingTcpReachabilityCalls).Count -ge 1) -Message 'One-shot SSH asset copy recovery must re-check SSH reachability before retrying.'
        Assert-True -Condition ([int]$script:RetryingBootstrapCalls -ge 2) -Message 'One-shot SSH asset copy recovery must re-bootstrap SSH before retrying.'
        Assert-True -Condition ([int]$result.SuccessCount -eq 1) -Message 'Successful retry after asset copy recovery must preserve the task success count.'
        Assert-True -Condition ([int]$result.WarningCount -eq 0) -Message 'Successful retry after asset copy recovery must avoid warning inflation.'
    }
    finally {
        foreach ($functionName in @(
            'Ensure-ClagnosPySshTools',
            'Initialize-ClagnosSshHostKey',
            'Wait-ClagnosProvisioningReadyOrRepair',
            'Wait-ClagnosTcpPortReachable',
            'Get-ClagnosTaskTimeoutSeconds',
            'Copy-ClagnosAssetToVm',
            'Invoke-ClagnosSshTaskScript',
            'Invoke-ClagnosTaskAppStatePostProcess',
            'Test-ClagnosOutputIndicatesRebootRequired'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        foreach ($variableName in @(
            'RetryingAssetCopyCalls',
            'RetryingTaskScriptCalls',
            'RetryingTcpReachabilityCalls',
            'RetryingBootstrapCalls'
        )) {
            Remove-Variable -Name $variableName -Scope Script -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Task command run-vm-init uses the isolated task execution path" -Action {
    $script:TaskRunInvocation = $null
    try {
        function Initialize-ClagnosTaskExecutionRuntimeContext {
            param([switch]$AutoMode, [switch]$WindowsFlag, [switch]$LinuxFlag)
            return [pscustomobject]@{
                EnvFilePath = (Join-Path $RepoRoot '.env')
                ConfigMap = @{ RESOURCE_GROUP = 'rg-samplevm-ate1-g1'; VM_NAME = 'samplevm' }
                EffectiveConfigMap = @{ RESOURCE_GROUP = 'rg-samplevm-ate1-g1'; VM_NAME = 'samplevm' }
                Platform = 'windows'
                PlatformDefaults = [pscustomobject]@{ RunCommandId = 'RunPowerShellScript' }
                Context = [ordered]@{
                    ResourceGroup = 'rg-samplevm-ate1-g1'
                    VmName = 'samplevm'
                    VmInitTaskDir = 'windows/init'
                    VmUpdateTaskDir = 'windows/update'
                    VmUser = 'manager'
                    VmPass = 'secret'
                    VmAssistantUser = 'assistant'
                    VmAssistantPass = 'secret2'
                    SshPort = '444'
                    RdpPort = '3389'
                    TcpPorts = @('444','3389')
                    AzLocation = 'austriaeast'
                    VmSize = 'Standard_D2as_v5'
                    VmImage = 'example:image:urn'
                    VmDiskName = 'disk-samplevm'
                    VmDiskSize = '128'
                    VmStorageSku = 'StandardSSD_LRS'
                }
                TaskOutcomeMode = 'continue'
                ConfiguredPySshClientPath = ''
                SshTaskTimeoutSeconds = 180
                SshConnectTimeoutSeconds = 30
            }
        }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosTaskBlocksFromDirectory {
            param([string]$DirectoryPath, [string]$Platform, [string]$Stage)
            return [pscustomobject]@{
                ActiveTasks = @(
                    [pscustomobject]@{
                        Name = '01-ensure-local-user-accounts'
                        TaskNumber = 1
                        Script = 'Write-Host ok'
                        TimeoutSeconds = 180
                    }
                )
            }
        }
        function Resolve-ClagnosRuntimeTaskBlocks {
            param([object[]]$TemplateTaskBlocks, [hashtable]$Context)
            return @($TemplateTaskBlocks)
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.austriaeast.cloudapp.azure.com'
                PublicIP = '1.2.3.4'
            }
        }
        function Invoke-VmRunCommandBlocks {
            param(
                [string]$ResourceGroup,
                [string]$VmName,
                [string]$CommandId,
                [object[]]$TaskBlocks,
                [string]$CombinedShell,
                [string]$TaskOutcomeMode,
                [string]$PerfTaskCategory,
                [string]$Platform,
                [string]$RepoRoot,
                [string]$ManagerUser,
                [string]$AssistantUser,
                [string]$SshHost,
                [string]$SshUser,
                [string]$SshPassword,
                [string]$SshPort,
                [int]$SshConnectTimeoutSeconds,
                [string]$ConfiguredPySshClientPath
            )

            $script:TaskRunInvocation = [pscustomobject]@{
                ResourceGroup = $ResourceGroup
                VmName = $VmName
                CommandId = $CommandId
                CombinedShell = $CombinedShell
                TaskOutcomeMode = $TaskOutcomeMode
                PerfTaskCategory = $PerfTaskCategory
                Platform = $Platform
                RepoRoot = $RepoRoot
                ManagerUser = $ManagerUser
                AssistantUser = $AssistantUser
                SshHost = $SshHost
                SshPort = $SshPort
                TaskName = [string]@($TaskBlocks)[0].Name
            }
            return [pscustomobject]@{ SuccessCount = 1; FailedCount = 0; WarningCount = 0; ErrorCount = 0 }
        }

        $result = Invoke-ClagnosTaskCommand -Options @{ 'run-vm-init' = '01' } -AutoMode:$false -WindowsFlag -LinuxFlag:$false

        Assert-True -Condition ($null -ne $script:TaskRunInvocation) -Message 'Task run-vm-init must invoke run-command blocks.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.ResourceGroup -eq 'rg-samplevm-ate1-g1') -Message 'Task run-vm-init must preserve target resource group.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.VmName -eq 'samplevm') -Message 'Task run-vm-init must preserve target VM name.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.CommandId -eq 'RunPowerShellScript') -Message 'Task run-vm-init must preserve platform run-command id.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.TaskName -eq '01-ensure-local-user-accounts') -Message 'Task run-vm-init must preserve selected task.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.PerfTaskCategory -eq 'task-run') -Message 'Task run-vm-init must use the task-run perf category.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.Platform -eq 'windows') -Message 'Task run-vm-init must pass platform through to the run-command runner.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.ManagerUser -eq 'manager') -Message 'Task run-vm-init must pass manager user through to shared init app-state replay.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.AssistantUser -eq 'assistant') -Message 'Task run-vm-init must pass assistant user through to shared init app-state replay.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.SshHost -eq 'samplevm.austriaeast.cloudapp.azure.com') -Message 'Task run-vm-init must resolve the SSH host for deferred app-state replay.'
        Assert-True -Condition ([string]$script:TaskRunInvocation.SshPort -eq '444') -Message 'Task run-vm-init must pass the SSH port for deferred app-state replay.'
        Assert-True -Condition ([string]$result.Stage -eq 'init') -Message 'Task run-vm-init must report init stage result.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosTaskExecutionRuntimeContext',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosTaskBlocksFromDirectory',
            'Resolve-ClagnosRuntimeTaskBlocks',
            'Get-ClagnosVmDetails',
            'Invoke-VmRunCommandBlocks'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name TaskRunInvocation -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Do redeploy action calls Azure redeploy and waits for recovery" -Action {
    $script:DoRedeployInvocation = $null
    $script:DoRedeployProvisioningWait = $null
    $script:DoRedeployLifecycleWait = $null
    $script:DoRedeployReportedSnapshot = $null
    $originalFunctionDefinitions = @{}

    foreach ($functionName in @(
        'Resolve-ClagnosManagedVmTarget',
        'Get-ClagnosVmLifecycleSnapshot',
        'Invoke-ClagnosDoAzureAction',
        'Wait-ClagnosProvisioningSucceeded',
        'Wait-ClagnosDoLifecycleState',
        'Write-ClagnosDoStatusReport'
    )) {
        $command = Get-Command $functionName -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            $originalFunctionDefinitions[$functionName] = [string]$command.Definition
        }
    }

    function Resolve-ClagnosManagedVmTarget {
        param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
        return [pscustomobject]@{
            ResourceGroup = 'rg-samplevm-ate1-g1'
            VmName = 'samplevm'
        }
    }
    function Get-ClagnosVmLifecycleSnapshot {
        param([string]$ResourceGroup, [string]$VmName)
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            OsType = 'Windows'
            Location = 'austriaeast'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/updating'
            ProvisioningStateDisplay = 'Updating'
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
            NormalizedState = 'started'
        }
    }
    function Invoke-ClagnosDoAzureAction {
        param(
            [string]$ActionName,
            [string]$ResourceGroup,
            [string]$VmName,
            [string[]]$AzArguments,
            [string]$AzContext
        )

        $script:DoRedeployInvocation = [pscustomobject]@{
            ActionName = $ActionName
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            AzArguments = @($AzArguments)
            AzContext = $AzContext
        }
    }
    function Wait-ClagnosProvisioningSucceeded {
        param([string]$ResourceGroup, [string]$VmName, [int]$MaxAttempts, [int]$DelaySeconds)
        $script:DoRedeployProvisioningWait = [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            MaxAttempts = $MaxAttempts
            DelaySeconds = $DelaySeconds
        }
        return [pscustomobject]@{
            Ready = $true
            Snapshot = [pscustomobject]@{
                ResourceGroup = $ResourceGroup
                VmName = $VmName
                OsType = 'Windows'
                Location = 'austriaeast'
                HibernationEnabled = $true
                ProvisioningStateCode = 'ProvisioningState/succeeded'
                ProvisioningStateDisplay = 'Provisioning succeeded'
                PowerStateCode = 'PowerState/running'
                PowerStateDisplay = 'VM running'
                HibernationStateCode = ''
                HibernationStateDisplay = ''
                NormalizedState = 'started'
            }
        }
    }
    function Wait-ClagnosDoLifecycleState {
        param([string]$ResourceGroup, [string]$VmName, [string]$DesiredState, [int]$MaxAttempts, [int]$DelaySeconds)
        $script:DoRedeployLifecycleWait = [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            DesiredState = $DesiredState
            MaxAttempts = $MaxAttempts
            DelaySeconds = $DelaySeconds
        }
        return [pscustomobject]@{
            ResourceGroup = $ResourceGroup
            VmName = $VmName
            OsType = 'Windows'
            Location = 'austriaeast'
            HibernationEnabled = $true
            ProvisioningStateCode = 'ProvisioningState/succeeded'
            ProvisioningStateDisplay = 'Provisioning succeeded'
            PowerStateCode = 'PowerState/running'
            PowerStateDisplay = 'VM running'
            HibernationStateCode = ''
            HibernationStateDisplay = ''
            NormalizedState = $DesiredState
        }
    }
    function Write-ClagnosDoStatusReport {
        param([psobject]$Snapshot)
        $script:DoRedeployReportedSnapshot = $Snapshot
    }

    try {
        Invoke-ClagnosDoCommand -Options @{ group = 'rg-samplevm-ate1-g1'; 'vm-name' = 'samplevm'; 'vm-action' = 'redeploy' }

        Assert-True -Condition ($null -ne $script:DoRedeployInvocation) -Message 'Redeploy must invoke the Azure action wrapper.'
        Assert-True -Condition ([string]$script:DoRedeployInvocation.ActionName -eq 'redeploy') -Message 'Redeploy must pass the redeploy action name to the Azure wrapper.'
        Assert-True -Condition ([string]$script:DoRedeployInvocation.AzContext -eq 'az vm redeploy') -Message 'Redeploy must use the az vm redeploy context label.'
        Assert-True -Condition ((@($script:DoRedeployInvocation.AzArguments) -join ' ') -eq 'vm redeploy -g rg-samplevm-ate1-g1 -n samplevm -o none --only-show-errors') -Message 'Redeploy must call az vm redeploy with the resolved target.'
        Assert-True -Condition ($null -ne $script:DoRedeployProvisioningWait) -Message 'Redeploy must wait for provisioning recovery.'
        Assert-True -Condition ($null -ne $script:DoRedeployLifecycleWait) -Message 'Redeploy must wait for the original lifecycle state when it was deterministic before the action.'
        Assert-True -Condition ([string]$script:DoRedeployLifecycleWait.DesiredState -eq 'started') -Message 'Redeploy must restore the original started lifecycle state.'
        Assert-True -Condition ($null -ne $script:DoRedeployReportedSnapshot) -Message 'Redeploy must print the refreshed VM status.'
        Assert-True -Condition ([string]$script:DoRedeployReportedSnapshot.ProvisioningStateCode -eq 'ProvisioningState/succeeded') -Message 'Redeploy must report the post-recovery lifecycle snapshot.'
    }
    finally {
        foreach ($functionName in @(
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmLifecycleSnapshot',
            'Invoke-ClagnosDoAzureAction',
            'Wait-ClagnosProvisioningSucceeded',
            'Wait-ClagnosDoLifecycleState',
            'Write-ClagnosDoStatusReport'
        )) {
            Remove-Item ("Function:\\global:{0}" -f $functionName) -ErrorAction SilentlyContinue
            Remove-Item ("Function:\\{0}" -f $functionName) -ErrorAction SilentlyContinue

            if ($originalFunctionDefinitions.ContainsKey($functionName)) {
                Set-Item -Path ("Function:\\global:{0}" -f $functionName) -Value ([scriptblock]::Create([string]$originalFunctionDefinitions[$functionName]))
            }
        }
    }
}

Invoke-Test -Name "Task execution helper supports strict outcome override for update tasks" -Action {
    try {
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosTaskBlocksFromDirectory {
            param([string]$DirectoryPath, [string]$Platform, [string]$Stage)
            return [pscustomobject]@{
                ActiveTasks = @(
                    [pscustomobject]@{
                        Name = '102-configure-autologon-settings'
                        TaskNumber = 10006
                        Script = 'Write-Host ok'
                        TimeoutSeconds = 45
                    }
                )
            }
        }
        function Resolve-ClagnosRuntimeTaskBlocks {
            param([object[]]$TemplateTaskBlocks, [hashtable]$Context)
            return @($TemplateTaskBlocks)
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.austriaeast.cloudapp.azure.com'
                PublicIP = '1.2.3.4'
            }
        }
        function Invoke-ClagnosSshTaskBlocks {
            param(
                [string]$Platform,
                [string]$RepoRoot,
                [string]$SshHost,
                [string]$SshUser,
                [string]$SshPassword,
                [string]$SshPort,
                [string]$ResourceGroup,
                [string]$VmName,
                [object[]]$TaskBlocks,
                [string]$TaskOutcomeMode,
                [string]$PerfTaskCategory,
                [int]$SshMaxRetries,
                [int]$SshTaskTimeoutSeconds,
                [int]$SshConnectTimeoutSeconds,
                [string]$ConfiguredPySshClientPath
            )

            $script:TaskUpdateInvocation = [pscustomobject]@{
                ResourceGroup = $ResourceGroup
                VmName = $VmName
                TaskName = [string]@($TaskBlocks)[0].Name
                TaskOutcomeMode = $TaskOutcomeMode
                PerfTaskCategory = $PerfTaskCategory
                SshHost = $SshHost
            }

            return [pscustomobject]@{ SuccessCount = 1; FailedCount = 0; WarningCount = 0; ErrorCount = 0 }
        }

        $runtime = [pscustomobject]@{
            Context = [ordered]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
                VmInitTaskDir = 'windows/init'
                VmUpdateTaskDir = 'windows/update'
                VmUser = 'manager'
                VmPass = 'secret'
                VmAssistantUser = 'assistant'
                SshPort = '444'
                AzLocation = 'austriaeast'
            }
            Platform = 'windows'
            EffectiveConfigMap = @{}
            TaskOutcomeMode = 'continue'
            ConfiguredPySshClientPath = ''
            SshTaskTimeoutSeconds = 180
            SshConnectTimeoutSeconds = 30
        }

        $result = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options @{ 'vm-name' = 'samplevm' } -Stage 'update' -Requested '10006' -TaskOutcomeModeOverride 'strict'

        Assert-True -Condition ($null -ne $script:TaskUpdateInvocation) -Message 'Task update execution helper must invoke SSH task runner.'
        Assert-True -Condition ([string]$script:TaskUpdateInvocation.TaskName -eq '102-configure-autologon-settings') -Message 'Task update execution helper must preserve selected task.'
        Assert-True -Condition ([string]$script:TaskUpdateInvocation.TaskOutcomeMode -eq 'strict') -Message 'Strict override must flow into the SSH task outcome mode.'
        Assert-True -Condition ([string]$script:TaskUpdateInvocation.PerfTaskCategory -eq 'task-run') -Message 'Task update execution helper must use the task-run perf category.'
        Assert-True -Condition ([string]$result.Stage -eq 'update') -Message 'Task update execution helper must report update stage result.'
        Assert-True -Condition ([string]$result.TaskOutcomeMode -eq 'strict') -Message 'Task update execution helper result must expose the strict override.'
    }
    finally {
        foreach ($functionName in @(
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosTaskBlocksFromDirectory',
            'Resolve-ClagnosRuntimeTaskBlocks',
            'Get-ClagnosVmDetails',
            'Invoke-ClagnosSshTaskBlocks'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name TaskUpdateInvocation -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Exec command uses the minimal runtime for remote command execution" -Action {
    $script:ExecMinimalRuntimeUsed = $false
    $script:ExecPythonArgs = @()
    try {
        function Initialize-ClagnosCommandRuntimeContext { throw 'Full Step-1 runtime context must not be used by exec.' }
        function Initialize-ClagnosExecCommandRuntimeContext {
            $script:ExecMinimalRuntimeUsed = $true
            return [pscustomobject]@{
                ConfigMap = @{
                    RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
                    VM_NAME = 'samplevm'
                    VM_ADMIN_USER = 'manager'
                    VM_ADMIN_PASS = 'secret'
                    VM_SSH_PORT = '444'
                }
                ConfiguredPySshClientPath = ''
                SshConnectTimeoutSeconds = 30
                SshCommandTimeoutSeconds = 180
            }
        }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.example'
                PublicIP = ''
            }
        }
        function Ensure-ClagnosPySshTools { param([string]$RepoRoot, [string]$ConfiguredPySshClientPath) return @{ PythonPath = 'Invoke-TestPy'; ClientPath = 'ssh_client.py' } }
        function Initialize-ClagnosSshHostKey { param() return [pscustomobject]@{ Output = '' } }
        function az {
            $global:LASTEXITCODE = 0
            return '{"storageProfile":{"osDisk":{"osType":"Windows"}}}'
        }
        function Assert-LastExitCode { param([string]$Context) }
        function Invoke-TestPy {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $script:ExecPythonArgs = @($Args)
            $global:LASTEXITCODE = 0
        }

        Invoke-ClagnosExecCommand -Options @{ command = 'Get-Date' }

        Assert-True -Condition $script:ExecMinimalRuntimeUsed -Message 'Exec must use the minimal exec runtime context.'
        $pythonArgsText = @($script:ExecPythonArgs) -join ' '
        Assert-True -Condition ($pythonArgsText -match [regex]::Escape('exec --host samplevm.example --port 444 --user manager --password secret --timeout 180 --command powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ')) -Message 'Windows exec --command must wrap one-shot commands in PowerShell and use the bounded command timeout.'
        Assert-True -Condition (-not ($pythonArgsText -match [regex]::Escape('--command Get-Date'))) -Message 'Windows exec --command must not send raw PowerShell expressions to cmd.exe.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosCommandRuntimeContext',
            'Initialize-ClagnosExecCommandRuntimeContext',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmDetails',
            'Ensure-ClagnosPySshTools',
            'Initialize-ClagnosSshHostKey',
            'az',
            'Assert-LastExitCode',
            'Invoke-TestPy'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name ExecMinimalRuntimeUsed -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name ExecPythonArgs -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Exec command can load the remote command body from one local script file" -Action {
    $script:ExecFilePythonArgs = @()
    $tempScriptPath = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-exec-file-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    try {
        Set-Content -LiteralPath $tempScriptPath -Value "Get-Date`n'from-file'" -Encoding UTF8
        function Initialize-ClagnosExecCommandRuntimeContext {
            return [pscustomobject]@{
                RepoRoot = $RepoRoot
                ConfigMap = @{
                    RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
                    VM_NAME = 'samplevm'
                    VM_ADMIN_USER = 'manager'
                    VM_ADMIN_PASS = 'secret'
                    VM_SSH_PORT = '444'
                }
                ConfiguredPySshClientPath = ''
                SshConnectTimeoutSeconds = 30
                SshCommandTimeoutSeconds = 180
            }
        }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.example'
                PublicIP = ''
            }
        }
        function Ensure-ClagnosPySshTools { param([string]$RepoRoot, [string]$ConfiguredPySshClientPath) return @{ PythonPath = 'Invoke-TestPyExecFile'; ClientPath = 'ssh_client.py' } }
        function Initialize-ClagnosSshHostKey { param() return [pscustomobject]@{ Output = '' } }
        function az {
            $global:LASTEXITCODE = 0
            return '{"storageProfile":{"osDisk":{"osType":"Windows"}}}'
        }
        function Assert-LastExitCode { param([string]$Context) }
        function Invoke-TestPyExecFile {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $script:ExecFilePythonArgs = @($Args)
            $global:LASTEXITCODE = 0
        }

        Invoke-ClagnosExecCommand -Options @{ file = $tempScriptPath }

        $pythonArgsText = @($script:ExecFilePythonArgs) -join ' '
        Assert-True -Condition ($pythonArgsText -match [regex]::Escape('exec --host samplevm.example --port 444 --user manager --password secret --timeout 180 --command powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ')) -Message 'Exec --file must use the wrapped one-shot Windows command path.'
        $encodedCommandMatch = [regex]::Match($pythonArgsText, 'EncodedCommand\s+(?<encoded>[A-Za-z0-9+/=]+)')
        Assert-True -Condition ($encodedCommandMatch.Success) -Message 'Exec --file must pass one encoded PowerShell command.'
        $decodedCommandText = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String([string]$encodedCommandMatch.Groups['encoded'].Value))
        Assert-True -Condition ($decodedCommandText -like '*Get-Date*') -Message 'Exec --file must execute the script file contents.'
        Assert-True -Condition ($decodedCommandText -like '*from-file*') -Message 'Exec --file must preserve multi-line script content.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosExecCommandRuntimeContext',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmDetails',
            'Ensure-ClagnosPySshTools',
            'Initialize-ClagnosSshHostKey',
            'az',
            'Assert-LastExitCode',
            'Invoke-TestPyExecFile'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue
        Remove-Variable -Name ExecFilePythonArgs -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Exec command opens interactive shell when no command is provided" -Action {
    $script:ExecShellArgs = @()
    try {
        function Initialize-ClagnosExecCommandRuntimeContext {
            return [pscustomobject]@{
                ConfigMap = @{
                    RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
                    VM_NAME = 'samplevm'
                    VM_ADMIN_USER = 'manager'
                    VM_ADMIN_PASS = 'secret'
                    VM_SSH_PORT = '444'
                }
                ConfiguredPySshClientPath = ''
                SshConnectTimeoutSeconds = 30
            }
        }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.example'
                PublicIP = ''
            }
        }
        function Ensure-ClagnosPySshTools { param([string]$RepoRoot, [string]$ConfiguredPySshClientPath) return @{ PythonPath = 'Invoke-TestPyShell'; ClientPath = 'ssh_client.py' } }
        function Initialize-ClagnosSshHostKey { param() return [pscustomobject]@{ Output = '' } }
        function az {
            $global:LASTEXITCODE = 0
            return '{"storageProfile":{"osDisk":{"osType":"Linux"}}}'
        }
        function Assert-LastExitCode { param([string]$Context) }
        function Invoke-TestPyShell {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $script:ExecShellArgs = @($Args)
            $global:LASTEXITCODE = 0
        }

        Invoke-ClagnosExecCommand -Options @{}

        Assert-True -Condition ((@($script:ExecShellArgs) -join ' ') -match [regex]::Escape('shell --host samplevm.example --port 444 --user manager --password secret --timeout 30 --reconnect-retries 3 --keepalive-seconds 15 --shell bash')) -Message 'Exec without --command must run the pyssh shell path with the resolved Linux shell.'
    }
    finally {
        foreach ($functionName in @(
            'Initialize-ClagnosExecCommandRuntimeContext',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmDetails',
            'Ensure-ClagnosPySshTools',
            'Initialize-ClagnosSshHostKey',
            'az',
            'Assert-LastExitCode',
            'Invoke-TestPyShell'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name ExecShellArgs -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Task token replacement" -Action {
    $context = [ordered]@{
        VmUser = "manager"
        VmPass = "secret"
        VmAssistantUser = "assistant"
        VmAssistantPass = "secret2"
        SshPort = "444"
        RdpPort = "3389"
        TcpPorts = @("444","3389","5985","11434")
        ResourceGroup = "rg-samplevm"
        VmName = "samplevm"
        CompanyName = "orgprofile"
        CompanyWebAddress = "https://example.test"
        CompanyEmailAddress = "<email>"
        EmployeeEmailAddress = "<email>"
        EmployeeFullName = "<person-name>"
        ShortcutSocialBusinessLinkedInUrl = "https://www.linkedin.com/company/orgprofile"
        ShortcutSocialPersonalXUrl = "https://x.com/exampleperson"
        ShortcutWebBusinessHomeUrl = "https://www.example.test/home"
        AzLocation = "austriaeast"
        VmSize = "Standard_B2as_v2"
        VmImage = "example:image:urn"
        VmDiskName = "disk-samplevm"
        VmDiskSize = "128"
        VmStorageSku = "StandardSSD_LRS"
        HostStartupProfileJsonBase64 = "W10="
        HostAutostartDiscoveryJsonBase64 = "e30="
    }

    $templates = @(
        [pscustomobject]@{ Name = "01-test"; Script = "echo __VM_ADMIN_USER__ __SSH_PORT__ __RDP_PORT__ __SELECTED_RESOURCE_GROUP__ __SELECTED_VM_NAME__ __SELECTED_AZURE_REGION__ __SELECTED_COMPANY_NAME__ __SELECTED_COMPANY_WEB_ADDRESS__ __SELECTED_COMPANY_EMAIL_ADDRESS__ __SELECTED_EMPLOYEE_EMAIL_ADDRESS__ __SELECTED_EMPLOYEE_FULL_NAME__ __WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL__ __WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL__ __WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL__ __TCP_PORTS_BASH__ __HOST_STARTUP_PROFILE_JSON_B64__ __HOST_AUTOSTART_DISCOVERY_JSON_B64__" }
    )

    $resolved = Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks $templates -Context $context
    $scriptBody = [string]$resolved[0].Script
    Assert-True -Condition ($scriptBody -like "*manager*") -Message "VM user token was not replaced."
    Assert-True -Condition ($scriptBody -like "*444*") -Message "SSH port token was not replaced."
    Assert-True -Condition ($scriptBody -like "*3389*") -Message "RDP port token was not replaced."
    Assert-True -Condition ($scriptBody -like "*rg-samplevm*") -Message "Selected resource-group token was not replaced."
    Assert-True -Condition ($scriptBody -like "*samplevm*") -Message "VM name token was not replaced."
    Assert-True -Condition ($scriptBody -like "*austriaeast*") -Message "Selected Azure region token was not replaced."
    Assert-True -Condition ($scriptBody -like "*orgprofile*") -Message "Company name token was not replaced."
    Assert-True -Condition ($scriptBody -like "*https://example.test*") -Message "Company web-address token was not replaced."
    Assert-True -Condition ($scriptBody -like "*<email>*") -Message "Company email-address token was not replaced."
    Assert-True -Condition ($scriptBody -like "*<email>*") -Message "Employee email token was not replaced."
    Assert-True -Condition ($scriptBody -like "*<person-name>*") -Message "Employee full name token was not replaced."
    Assert-True -Condition ($scriptBody -like "*linkedin.com/company/orgprofile*") -Message "Business LinkedIn shortcut token was not replaced."
    Assert-True -Condition ($scriptBody -like "*x.com/exampleperson*") -Message "Personal X shortcut token was not replaced."
    Assert-True -Condition ($scriptBody -like "*example.test/home*") -Message "Business home shortcut token was not replaced."
    Assert-True -Condition ($scriptBody -like "*W10=*") -Message "Host startup profile token was not replaced."
    Assert-True -Condition ($scriptBody -like "*e30=*") -Message "Host autostart discovery token was not replaced."
}

Invoke-Test -Name "Startup profile task overrides the generic host startup token" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-startup-profile-override-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try {
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '10002-configure-startup-settings' -Platform windows -ScriptText 'Write-Host "__HOST_STARTUP_PROFILE_JSON_B64__"' -TaskJson @{
            priority = 10002
            enabled = $true
            timeout = 120
            extensions = @{
                startupProfile = @{
                    schemaVersion = 1
                    sourcePath = 'extensions/startup-profile.json'
                }
            }
        }

        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update
        $taskBlock = @($catalog.ActiveTasks | Where-Object { [string]$_.Name -eq '10002-configure-startup-settings' } | Select-Object -First 1)[0]
        Assert-True -Condition ($null -ne $taskBlock) -Message 'Startup profile test task must be discoverable.'
        Assert-True -Condition (Test-ClagnosTaskStartupProfileEnabled -TaskBlock $taskBlock) -Message 'Startup profile extension must be enabled for the task.'

        $genericHostProfileToken = [string](Get-ClagnosHostStartupMirrorProfileJsonBase64)
        $resolvedTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($taskBlock) -Context ([ordered]@{
            VmUser = 'manager'
            VmPass = 'secret'
            VmAssistantUser = 'assistant'
            VmAssistantPass = 'secret2'
            SshPort = '444'
            RdpPort = '3389'
            TcpPorts = @('444','3389','5985','11434')
            ResourceGroup = 'rg-samplevm'
            VmName = 'samplevm'
            CompanyName = 'orgprofile'
            AzLocation = 'austriaeast'
            VmSize = 'Standard_B2as_v2'
            VmImage = 'example:image:urn'
            VmDiskName = 'disk-samplevm'
            VmDiskSize = '128'
            VmStorageSku = 'StandardSSD_LRS'
            HostStartupProfileJsonBase64 = 'W10='
            HostAutostartDiscoveryJsonBase64 = 'e30='
        }))[0]

        $resolvedToken = [string]$resolvedTask.Script.Trim().Replace('Write-Host "', '').Replace('"', '')
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$resolvedToken)) -Message 'Resolved startup-profile token must not be blank.'
        Assert-True -Condition ($resolvedToken -ne 'W10=') -Message 'Startup-profile task must override the generic host startup token.'
        Assert-True -Condition ($resolvedToken -ne $genericHostProfileToken) -Message 'Startup-profile task must use the approved task-local profile instead of the generic host mirror token.'

        $decodedJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($resolvedToken))
        $decodedEntries = @(ConvertFrom-JsonObjectArrayCompat -InputObject $decodedJson)
        $decodedKeys = @($decodedEntries | ForEach-Object { [string]$_.Key })
        foreach ($requiredKey in @('docker-desktop','microsoft-lists','onedrive','teams','ollama','send-to-onenote','itunes-helper','jaws','security-health','anydesk','whatsapp','icloud','google-drive','m365-copilot')) {
            Assert-True -Condition ($decodedKeys -contains $requiredKey) -Message ("Approved startup profile must include '{0}'." -f [string]$requiredKey)
        }
        Assert-True -Condition (-not ($decodedKeys -contains '1password')) -Message 'Approved startup profile must exclude 1Password.'

        $pluginZipPath = Join-Path $tempRoot '10002-configure-startup-settings\app-state\app-state.zip'
        Assert-True -Condition (Test-Path -LiteralPath $pluginZipPath) -Message 'Startup profile task must materialize a task-local app-state zip.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Startup mirror profile resolution" -Action {
    $entries = @(
        [pscustomobject]@{ Name = 'Docker Desktop'; Command = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'; EntryType = 'Run'; Scope = 'CurrentUser'; Enabled = $true },
        [pscustomobject]@{ Name = 'Ollama.lnk'; Command = 'C:\Users\operator\AppData\Local\Programs\Ollama\ollama app.exe'; EntryType = 'StartupFolder'; Scope = 'CurrentUser'; Enabled = $true },
        [pscustomobject]@{ Name = 'Teams'; Command = 'C:\Windows\explorer.exe shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams'; EntryType = 'StartupFolder'; Scope = 'CurrentUser'; Enabled = $true },
        [pscustomobject]@{ Name = 'iTunesHelper'; Command = '"C:\Program Files\iTunes\iTunesHelper.exe"'; EntryType = 'Run'; Scope = 'LocalMachine'; Enabled = $true },
        [pscustomobject]@{ Name = 'OneDrive'; Command = '"C:\Program Files\Microsoft OneDrive\OneDrive.exe" /background'; EntryType = 'Run'; Scope = 'CurrentUser'; Enabled = $true },
        [pscustomobject]@{ Name = 'Microsoft Lists'; Command = '"C:\Program Files\WindowsApps\Microsoft.Lists\Lists.exe"'; EntryType = 'Run'; Scope = 'CurrentUser'; Enabled = $true },
        [pscustomobject]@{ Name = 'Edge'; Command = '"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" --minimized'; EntryType = 'Run'; Scope = 'CurrentUser'; Enabled = $false }
    )

    $profile = @(Resolve-ClagnosHostStartupMirrorProfileFromEntries -Entries $entries)
    $keys = @($profile | ForEach-Object { [string]$_.Key })

    foreach ($requiredKey in @('docker-desktop','ollama','teams','itunes-helper','onedrive')) {
        Assert-True -Condition ($keys -contains $requiredKey) -Message ("Startup mirror profile must include '{0}'." -f $requiredKey)
    }

    Assert-True -Condition (-not ($keys -contains 'codex-app')) -Message "Startup mirror profile must not infer unsupported apps from unrelated entries."
    Assert-True -Condition (-not ($keys -contains 'microsoft-edge')) -Message "Disabled startup entries must not be mirrored."
}

Invoke-Test -Name "Required config helper rejects empty and placeholder values" -Action {
    $tokens = @{ VM_NAME = 'samplevm' }

    $missingFailed = $false
    try {
        $null = Get-ClagnosRequiredResolvedConfigValue -ConfigMap @{} -Key 'VM_ADMIN_PASS' -Tokens $tokens -Summary 'VM admin password is required.' -Hint 'Set VM_ADMIN_PASS in .env to a non-placeholder password.'
    }
    catch {
        $missingFailed = $true
        Assert-True -Condition ($_.Exception.Data['Hint'] -like '*VM_ADMIN_PASS*') -Message 'Missing required config must point to the missing key.'
    }
    Assert-True -Condition $missingFailed -Message 'Missing required config must fail.'

    $placeholderFailed = $false
    try {
        $null = Get-ClagnosRequiredResolvedConfigValue -ConfigMap @{ VM_ADMIN_PASS = '<CHANGE_ME_STRONG_ADMIN_PASSWORD>' } -Key 'VM_ADMIN_PASS' -Tokens $tokens -Summary 'VM admin password is required.' -Hint 'Set VM_ADMIN_PASS in .env to a non-placeholder password.'
    }
    catch {
        $placeholderFailed = $true
        Assert-True -Condition ($_.Exception.Message -like '*placeholder*') -Message 'Placeholder config must fail with a placeholder-specific message.'
    }
    Assert-True -Condition $placeholderFailed -Message 'Placeholder config must fail.'
}

Invoke-Test -Name "Windows task and package catalogs are physically isolated" -Action {
    $updateDir = Join-Path $RepoRoot 'windows\update'
    $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $updateDir -Platform windows -Stage update -SuppressSkipMessages
    $active = @($catalog.ActiveTasks)
    $activeNames = @($active | ForEach-Object { [string]$_.Name })
    $expectedTaskTimeouts = [ordered]@{
        '102-configure-autologon-settings' = 60
        '110-configure-unlocker-settings' = 120
        '136-configure-language-settings' = 1635
        '10001-configure-advanced-settings' = 30
        '10002-configure-startup-settings' = 120
        '10003-create-public-desktop-shortcuts' = 120
        '10004-configure-windows-experience' = 180
        '10005-copy-user-settings' = 240
        '10006-ensure-managed-user-cross-access' = 120
    }

    Assert-True -Condition (@($activeNames).Count -ge $expectedTaskTimeouts.Count) -Message 'The Windows update stage must contain its maintenance tasks.'
    Assert-True -Condition (@($activeNames | Where-Object { $_ -like '*-install-*' }).Count -eq 0) -Message 'Package installers must not be discovered as vm-update tasks.'
    foreach ($entry in $expectedTaskTimeouts.GetEnumerator()) {
        $task = @($active | Where-Object { [string]$_.Name -eq [string]$entry.Key } | Select-Object -First 1)
        Assert-True -Condition ($task.Count -eq 1) -Message ("Expected maintenance task '{0}' was not discovered." -f [string]$entry.Key)
        Assert-True -Condition ([int]$task[0].TimeoutSeconds -eq [int]$entry.Value) -Message ("Maintenance task '{0}' timeout must stay {1}." -f [string]$entry.Key,[int]$entry.Value)
    }
    Assert-True -Condition ([string]$activeNames[0] -eq '102-configure-autologon-settings') -Message 'Normal maintenance tasks must precede the final task band.'
    Assert-True -Condition ([string]$activeNames[-1] -eq '10006-ensure-managed-user-cross-access') -Message 'The final maintenance task must remain the last stage task.'

    $builtinPackages = @(Get-ClagnosPackageCatalog -Platform windows -Catalog builtin)
    $customPackages = @(Get-ClagnosPackageCatalog -Platform windows -Catalog custom)
    Assert-True -Condition ($builtinPackages.Count -eq 36) -Message 'All 36 standard Windows installers must be in the builtin package catalog.'
    Assert-True -Condition (@($builtinPackages | Where-Object { $_.Catalog -ne 'builtin' -or -not (Test-Path -LiteralPath (Join-Path $_.DirectoryPath 'package.json')) -or -not (Test-Path -LiteralPath $_.PackageTask.Path) }).Count -eq 0) -Message 'Builtin package entries must resolve their own package.json and installer script.'
    Assert-True -Condition (@($customPackages | Where-Object { $_.Catalog -ne 'custom' -or -not (Test-Path -LiteralPath (Join-Path $_.DirectoryPath 'package.json')) -or -not (Test-Path -LiteralPath $_.PackageTask.Path) }).Count -eq 0) -Message 'Custom package entries must resolve only within the custom package catalog.'
    $chrome = @($builtinPackages | Where-Object { $_.Id -eq 'google-chrome' })[0]
    Assert-True -Condition (@($chrome.PackageTask.PackageSpec.DependsOn) -contains 'chocolatey') -Message 'Package dependencies must refer to package ids, not vm-update task names.'
    foreach ($storePackageId in @('microsoft-teams','be-my-eyes','whatsapp','codex-app','icloud')) {
        $storePackage = @($builtinPackages | Where-Object { $_.Id -eq $storePackageId })[0]
        Assert-True -Condition (@($storePackage.PackageTask.PackageSpec.PostInstallTasks) -contains '10003-create-public-desktop-shortcuts') -Message ("Store package '{0}' must declare its public shortcut post-install task in package.json." -f $storePackageId)
    }
}
Invoke-Test -Name "Exec quiet mode suppresses remote chatter but keeps local action progress visible" -Action {
    $script:ExecQuietPythonArgs = @()
    $script:CapturedExecQuietHost = @()
    $previousQuietOutput = [bool]$script:ClagnosQuietOutput
    try {
        function Write-Host {
            param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)

            $parts = @()
            foreach ($argument in @($Arguments)) {
                if ($argument -is [string]) {
                    $parts += [string]$argument
                }
            }

            if (@($parts).Count -gt 0) {
                $script:CapturedExecQuietHost += (@($parts) -join ' ')
            }
        }
        function Initialize-ClagnosExecCommandRuntimeContext {
            return [pscustomobject]@{
                ConfigMap = @{
                    RESOURCE_GROUP = 'rg-samplevm-ate1-g1'
                    VM_NAME = 'samplevm'
                    VM_ADMIN_USER = 'manager'
                    VM_ADMIN_PASS = 'secret'
                    VM_SSH_PORT = '444'
                }
                ConfiguredPySshClientPath = ''
                SshConnectTimeoutSeconds = 30
                SshCommandTimeoutSeconds = 180
            }
        }
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.example'
                PublicIP = ''
            }
        }
        function Ensure-ClagnosPySshTools { param([string]$RepoRoot, [string]$ConfiguredPySshClientPath) return @{ PythonPath = 'Invoke-TestPyQuiet'; ClientPath = 'ssh_client.py' } }
        function Initialize-ClagnosSshHostKey { param() return [pscustomobject]@{ Output = 'bootstrap-output' } }
        function az {
            $global:LASTEXITCODE = 0
            return '{"storageProfile":{"osDisk":{"osType":"Windows"}}}'
        }
        function Assert-LastExitCode { param([string]$Context) }
        function Invoke-TestPyQuiet {
            param([Parameter(ValueFromRemainingArguments = $true)]$Args)
            $script:ExecQuietPythonArgs = @($Args)
            $global:LASTEXITCODE = 0
        }

        Invoke-ClagnosExecCommand -Options @{ command = 'Get-Date'; quiet = $true }

        Assert-True -Condition ([bool]$script:ClagnosQuietOutput) -Message 'Exec --quiet must enable quiet output mode for the command path.'
        Assert-True -Condition (@($script:CapturedExecQuietHost | Where-Object { [string]$_ -match '(?i)^Doing:' }).Count -eq 1) -Message 'Exec --quiet must print one safe local Doing action label.'
        Assert-True -Condition (@($script:CapturedExecQuietHost | Where-Object { [string]$_ -match '(?i)bootstrap-output|completed|VM_ADMIN_PASS|secret' }).Count -eq 0) -Message 'Exec --quiet must still suppress bootstrap, completion, and secret-bearing output.'
        $pythonArgsText = (@($script:ExecQuietPythonArgs) -join ' ')
        Assert-True -Condition ($pythonArgsText -match [regex]::Escape('exec --host samplevm.example --port 444 --user manager --password secret --timeout 180 --command powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ')) -Message 'Exec --quiet must still invoke the wrapped one-shot command path.'
        $encodedCommandMatch = [regex]::Match($pythonArgsText, 'EncodedCommand\s+(?<encoded>[A-Za-z0-9+/=]+)')
        Assert-True -Condition ($encodedCommandMatch.Success) -Message 'Exec --quiet must pass one encoded PowerShell command.'
        $encodedCommandText = [string]$encodedCommandMatch.Groups['encoded'].Value
        $decodedCommandText = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encodedCommandText))
        Assert-True -Condition ($decodedCommandText -like '*$InformationPreference = ''SilentlyContinue''*') -Message 'Exec --quiet must suppress information-stream chatter inside the remote wrapper.'
        Assert-True -Condition ($decodedCommandText -like '*} 6>$null*') -Message 'Exec --quiet must suppress information-stream redirection inside the remote wrapper.'
    }
    finally {
        foreach ($functionName in @(
            'Write-Host',
            'Initialize-ClagnosExecCommandRuntimeContext',
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosVmDetails',
            'Ensure-ClagnosPySshTools',
            'Initialize-ClagnosSshHostKey',
            'az',
            'Assert-LastExitCode',
            'Invoke-TestPyQuiet'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        $script:ClagnosQuietOutput = $previousQuietOutput
        Remove-Variable -Name ExecQuietPythonArgs -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name CapturedExecQuietHost -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Task json controls local-only task discovery" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-task-meta-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try {
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '101-alpha-task' -Platform windows -ScriptText "Write-Host 'alpha'" -TaskJson @{
            priority = 101
            enabled = $true
            timeout = 90
        }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath 'local/1002-beta-task' -Platform windows -ScriptText "Write-Host 'beta'" -TaskJson @{
            priority = 1002
            enabled = $true
            timeout = 44
        }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath 'local/1001-delta-task' -Platform windows -ScriptText "Write-Host 'delta'" -TaskJson @{
            enabled = $true
        }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath 'local/disabled/1004-gamma-task' -Platform windows -ScriptText "Write-Host 'gamma'" -TaskJson @{
            priority = 1004
            enabled = $false
            timeout = 99
        }

        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update
        $active = @($catalog.ActiveTasks)
        $activeNames = @($active | ForEach-Object { [string]$_.Name })
        $disabled = @($catalog.DisabledTasks)

        Assert-True -Condition ($active.Count -eq 3) -Message 'Tracked root tasks and local-only tasks must both be discoverable.'
        Assert-True -Condition ($disabled.Count -eq 1) -Message 'Tasks under local/disabled must be discovered as disabled.'
        Assert-True -Condition ([string]$activeNames[0] -eq '101-alpha-task') -Message 'Tracked tasks must keep their task.json priority.'
        Assert-True -Condition ([string]$activeNames[1] -eq '1001-delta-task') -Message 'Local-only tasks must now sort by priority before timeout once they are ready.'
        Assert-True -Condition ([string]$activeNames[2] -eq '1002-beta-task') -Message 'Local-only tasks with higher priority numbers must follow lower-priority peers even when timeout ordering would previously place them earlier.'

        $alphaTask = $active | Where-Object { [string]$_.Name -eq '101-alpha-task' } | Select-Object -First 1
        $betaTask = $active | Where-Object { [string]$_.Name -eq '1002-beta-task' } | Select-Object -First 1
        $deltaTask = $active | Where-Object { [string]$_.Name -eq '1001-delta-task' } | Select-Object -First 1

        Assert-True -Condition ([int]$alphaTask.TimeoutSeconds -eq 90) -Message 'task.json timeout must drive tracked tasks.'
        Assert-True -Condition ([int]$betaTask.TimeoutSeconds -eq 45) -Message 'Local-only task timeouts must be normalized to the shared 30-plus-15-second contract.'
        Assert-True -Condition ([int]$deltaTask.TimeoutSeconds -eq 180) -Message 'Local-only tasks without task.json timeout must default to 180.'
        Assert-True -Condition ([int]$alphaTask.Priority -eq 101) -Message 'Tracked task priority must come from task.json.'
        Assert-True -Condition ([int]$betaTask.Priority -eq 1002) -Message 'task.json priority must drive local-only tasks.'
        Assert-True -Condition ([int]$deltaTask.Priority -eq 1001) -Message 'Local-only tasks without task.json priority must use the task number.'
        Assert-True -Condition ([string]$betaTask.RelativePath -eq 'local/1002-beta-task/1002-beta-task.ps1') -Message 'Local-only active task must preserve its folderized relative path.'
        Assert-True -Condition ([string]$disabled[0].RelativePath -eq 'local/disabled/1004-gamma-task/1004-gamma-task.ps1') -Message 'Local-only disabled task must preserve its folderized relative path.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Task discovery keeps initial then normal then local then final order" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-task-order-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try {
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '01-alpha-init' -Platform windows -ScriptText "Write-Host 'alpha'" -TaskJson @{ timeout = 30 }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '101-bravo-normal' -Platform windows -ScriptText "Write-Host 'bravo'" -TaskJson @{ timeout = 40 }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '10001-delta-final' -Platform windows -ScriptText "Write-Host 'delta'" -TaskJson @{ timeout = 50 }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath 'local/1002-charlie-local' -Platform windows -ScriptText "Write-Host 'charlie'" -TaskJson @{
            priority = 1002
            timeout = 44
            enabled = $true
        }

        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update
        $activeNames = @(@($catalog.ActiveTasks) | ForEach-Object { [string]$_.Name })

        Assert-True -Condition ($activeNames.Count -eq 4) -Message 'Expected tracked initial, tracked normal, local, and tracked final tasks to all be discovered.'
        Assert-True -Condition ([string]$activeNames[0] -eq '01-alpha-init') -Message 'Initial tracked tasks must stay first.'
        Assert-True -Condition ([string]$activeNames[1] -eq '101-bravo-normal') -Message 'Normal tracked tasks must stay after initial tasks.'
        Assert-True -Condition ([string]$activeNames[2] -eq '1002-charlie-local') -Message 'Local untracked tasks must stay after normal tracked tasks.'
        Assert-True -Condition ([string]$activeNames[3] -eq '10001-delta-final') -Message 'Tracked final tasks must stay after local untracked tasks.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Generic task metadata assets resolve into asset copies" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-task-assets-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try {
        $assetDir = Join-Path $tempRoot 'shared-assets'
        New-Item -Path $assetDir -ItemType Directory -Force | Out-Null
        $assetPath = Join-Path $assetDir 'profile.zip'
        Set-Content -Path $assetPath -Value 'payload' -Encoding UTF8

        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath 'local/1002-local-config-task' -Platform windows -ScriptText 'Write-Host "__VM_ADMIN_USER__"' -TaskJson @{
            priority = 1002
            timeout = 7
            enabled = $true
            assets = @(
                @{
                    local = '../../shared-assets/profile.zip'
                    remote = 'C:/Windows/Temp/__SELECTED_VM_NAME__-profile.zip'
                }
            )
        }

        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update
        $task = @($catalog.ActiveTasks)[0]
        $resolved = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @($task) -Context ([ordered]@{
            VmUser = 'manager'
            VmPass = 'secret'
            VmAssistantUser = 'assistant'
            VmAssistantPass = 'secret2'
            SshPort = '444'
            RdpPort = '3389'
            TcpPorts = @('444','3389','5985','11434')
            ResourceGroup = 'rg-samplevm'
            VmName = 'samplevm'
            CompanyName = 'orgprofile'
            AzLocation = 'austriaeast'
            VmSize = 'Standard_B2as_v2'
            VmImage = 'example:image:urn'
            VmDiskName = 'disk-samplevm'
            VmDiskSize = '128'
            VmStorageSku = 'StandardSSD_LRS'
        }))[0]

        $assetCopies = @($resolved.AssetCopies)
        Assert-True -Condition ($assetCopies.Count -eq 1) -Message 'Generic metadata asset resolution must publish one asset copy.'
        Assert-True -Condition ([string]$assetCopies[0].RemotePath -eq 'C:/Windows/Temp/samplevm-profile.zip') -Message 'Generic metadata asset remote path mismatch.'
        Assert-True -Condition ([string]$assetCopies[0].LocalPath -eq (Resolve-Path -LiteralPath $assetPath).Path) -Message 'Generic metadata asset local path mismatch.'
        Assert-True -Condition ([string]$resolved.Script -like '*manager*') -Message 'Generic metadata task script must still apply token replacement.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Duplicate task names across portable task trees fail fast" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-task-duplicate-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    try {
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath '101-alpha-task' -Platform windows -ScriptText 'Write-Host "tracked"' -TaskJson @{
            priority = 101
            enabled = $true
            timeout = 180
        }
        New-SmokeTaskFolder -RootPath $tempRoot -RelativeFolderPath 'disabled/101-alpha-task' -Platform windows -ScriptText 'Write-Host "disabled-duplicate"' -TaskJson @{
            priority = 101
            enabled = $true
            timeout = 180
        }

        $threw = $false
        try {
            Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update | Out-Null
        }
        catch {
            $threw = $true
            Assert-True -Condition ([string]$_.Exception.Message -like '*Task name ''101-alpha-task'' is duplicated*') -Message 'Duplicate portable task names must report a precise error.'
        }

        Assert-True -Condition $threw -Message 'Duplicate portable task names must fail fast.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Malformed nested local task folders warn and skip" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-task-nesting-test-" + [Guid]::NewGuid().ToString("N"))
    New-Item -Path (Join-Path $tempRoot 'local\subdir\1001-bad-task') -ItemType Directory -Force | Out-Null
    try {
        Set-Content -Path (Join-Path $tempRoot 'local\subdir\1001-bad-task\1001-bad-task.ps1') -Encoding UTF8 -Value 'Write-Host "bad"'
        Set-Content -Path (Join-Path $tempRoot 'local\subdir\1001-bad-task\task.json') -Encoding UTF8 -Value '{"priority":1001,"enabled":true,"timeout":180}'

        $warnings = @()
        $null = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $tempRoot -Platform windows -Stage update 3>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.WarningRecord]) {
                $warnings += [string]$_.Message
            }
        }

        Assert-True -Condition ($warnings.Count -ge 1) -Message 'Unexpected nested local task folders must emit one concise warning.'
        Assert-True -Condition (($warnings -join "`n") -like '*Task folder skipped: local/subdir*') -Message 'Malformed nested local task folders must be skipped by their top-level folder.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Windows Ollama task verifies API readiness" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '135-install-ollama-tool'
    $taskJsonPath = Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '135-install-ollama-tool'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    $taskJson = Get-Content -LiteralPath $taskJsonPath -Raw | ConvertFrom-Json
    Assert-True -Condition ($taskScript -like '*ChocoPackageId = ''ollama''*') -Message 'Ollama install task must use the ollama Chocolatey package id.'
    Assert-True -Condition ($taskScript -like '*127.0.0.1:11434*') -Message 'Ollama install task must check the default Ollama port.'
    Assert-True -Condition ($taskScript -like '*http://localhost:11434/api/version*') -Message 'Ollama install task must keep a localhost API probe fallback for slow local cold starts.'
    Assert-True -Condition ($taskScript -like '*/api/version*') -Message 'Ollama install task must validate the Ollama HTTP API endpoint.'
    Assert-True -Condition ($taskScript -like '*cmd.exe /c start*') -Message 'Ollama install task must bootstrap ollama through cmd.exe /c start.'
    Assert-True -Condition ($taskScript -like '*start ""*') -Message 'Ollama install task must use a detached start wrapper for the Ollama bootstrap.'
    Assert-True -Condition ($taskScript -like '*ollama-ls-ready: success=*') -Message 'Ollama install task must report whether ollama ls succeeded after bootstrap.'
    Assert-True -Condition ($taskScript -like '*ollama-ls-info:*') -Message 'Ollama install task must record ollama ls probe details when the runtime is otherwise healthy.'
    Assert-True -Condition ($taskScript -like '*ollama-runtime-deferred:*') -Message 'Ollama install task must defer list-only failures when process and API readiness are already satisfied.'
    Assert-True -Condition ($taskScript -like '*ollama-process-ready*') -Message 'Ollama install task must verify a running Ollama process after bootstrap.'
    Assert-True -Condition ($taskScript -like '*ollama-port-ready*') -Message 'Ollama install task must verify the local Ollama TCP port after bootstrap.'
    Assert-True -Condition (($taskScript.IndexOf('Wait-OllamaProcessReady -TimeoutSeconds ([int]$taskConfig.OllamaProcessWaitTimeoutSeconds)', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Ollama install task must verify the process before treating ollama ls as the decisive check.'
    Assert-True -Condition (($taskScript.IndexOf('Wait-OllamaApiReady -TimeoutSeconds $apiTimeoutSeconds', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Ollama install task must verify the API before treating ollama ls as the decisive check.'
    Assert-True -Condition ($taskScript -like '*Existing Ollama installation is already healthy. Skipping choco install.*') -Message 'Ollama install task must short-circuit when an existing installation is already healthy.'
    Assert-True -Condition ($taskScript -like '*RedirectStandardOutput*') -Message 'Ollama install task must bound external command output through redirected logs.'
    Assert-True -Condition ($taskScript -like '*RedirectStandardError*') -Message 'Ollama install task must bound external command error output through redirected logs.'
    Assert-True -Condition ($taskScript -like '*WaitForExit*') -Message 'Ollama install task must bound choco and ollama command waits.'
    Assert-True -Condition ($taskScript -like '*timed out after*') -Message 'Ollama install task must fail clearly when install or list probes exceed the timeout.'
    Assert-True -Condition ($taskScript -like '*choco install ollama -y --no-progress --ignore-detected-reboot*') -Message 'Ollama install task must install with choco install ollama.'
    Assert-True -Condition ($taskScript -like '*ollama-cleanup-winget-exit*') -Message 'Ollama install task must clean old winget-based installs before a clean choco reinstall.'
    Assert-True -Condition (-not ($taskScript -like '*Write-Warning*')) -Message 'Ollama install task must avoid emitting warning-channel noise during bounded retries.'
    Assert-True -Condition (-not ($taskScript -like '*winget install*')) -Message 'Ollama install task must no longer install through winget.'
    Assert-True -Condition ($taskScript -like '*Start-Process -FilePath $OllamaExe -ArgumentList ''serve''*') -Message 'Ollama install task must fall back to Start-Process ollama.exe serve when the detached ls bootstrap does not stay alive.'
    Assert-True -Condition (($taskScript.IndexOf('[string]$Host =', [System.StringComparison]::OrdinalIgnoreCase)) -lt 0) -Message 'Ollama install task must not shadow the built-in $Host variable with a parameter named Host.'
    Assert-True -Condition (($taskScript.IndexOf('[string]$HostName', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Ollama install task must use a non-reserved host-name parameter for TCP probes.'
    Assert-True -Condition ($taskScript -like '*install-ollama-tool-completed: version={0}; processCount={1}; listReady={2}*') -Message 'Ollama install task must publish whether ollama ls was ready at task completion.'
    Assert-True -Condition (@($taskJson.appState.machineDirectories).Count -eq 0) -Message 'Ollama app-state must not replay machine-wide runtime directories.'
    Assert-True -Condition (@($taskJson.appState.profileDirectories).Count -eq 0) -Message 'Ollama app-state must not replay broad profile directories.'
    $profileFilePaths = @($taskJson.appState.profileFiles | ForEach-Object { [string]$_.path })
    Assert-True -Condition (@($profileFilePaths).Count -eq 3) -Message 'Ollama app-state must be limited to the small set of managed config files.'
    Assert-True -Condition (($profileFilePaths -contains 'AppData\Local\Ollama\config.json')) -Message 'Ollama app-state must allow AppData\\Local\\Ollama\\config.json.'
    Assert-True -Condition (($profileFilePaths -contains 'AppData\Roaming\Ollama\config.json')) -Message 'Ollama app-state must allow AppData\\Roaming\\Ollama\\config.json.'
    Assert-True -Condition (($profileFilePaths -contains 'AppData\Roaming\ollama app.exe\config.json')) -Message 'Ollama app-state must allow AppData\\Roaming\\ollama app.exe\\config.json.'
}

Invoke-Test -Name "Windows VS Code task short-circuits healthy installs" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '110-install-vscode-application'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    Assert-True -Condition ($taskScript -like '*Existing Visual Studio Code installation is already healthy. Skipping winget install.*') -Message 'VS Code install task must skip winget when a healthy installation already exists.'
    Assert-True -Condition ($taskScript -like '*Resolve-CodeExecutable*') -Message 'VS Code install task must resolve the existing Code executable before reinstalling.'
}

Invoke-Test -Name "Windows Docker Desktop task clears stale installer locks" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '114-install-docker-desktop-application'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    Assert-True -Condition ($taskScript -like '*Stopping stale installer processes before Docker Desktop install*') -Message 'Docker Desktop task must clear stale installer locks before winget install.'
    Assert-True -Condition ($taskScript -like "*DockerDesktopPackageId = 'Docker.DockerDesktop'*") -Message 'Docker Desktop task must keep the Docker Desktop winget package id in its task-local config block.'
    Assert-True -Condition ($taskScript -like '*Ensure-WingetSourcesReady*') -Message 'Docker Desktop task must bound winget source repair before install.'
    Assert-True -Condition ($taskScript -like '*docker-step-repair: winget-source-list-exit=*') -Message 'Docker Desktop task must log the bounded source repair path.'
    Assert-True -Condition ($taskScript -like '*docker-step-repair: stale-registration-cleared*') -Message 'Docker Desktop task must clear stale uninstall registration when winget reports Docker Desktop as installed without install evidence.'
    Assert-True -Condition ($taskScript -like '*removed-stale-registration =>*') -Message 'Docker Desktop task must log which stale Docker Desktop uninstall registration key was removed.'
    Assert-True -Condition ($taskScript -match 'winget install \{0\}" -f \[string\]\$taskConfig\.DockerDesktopPackageId') -Message 'Docker Desktop task must label the install step as a winget Docker Desktop install.'
    Assert-True -Condition ($taskScript -match '-Arguments\s+@\(''install'',\s*''-e'',\s*''--id'',\s*\(\[string\]\$taskConfig\.DockerDesktopPackageId\)') -Message 'Docker Desktop task must install Docker Desktop through winget.'
    Assert-True -Condition ($taskScript -like '*Invoke-ProcessWithTimeout*') -Message 'Docker Desktop task must bound the winget install wait time.'
    Assert-True -Condition ($taskScript -like '*Active installer processes*') -Message 'Docker Desktop task must report active installer processes when install timing problems occur.'
    Assert-True -Condition ($taskScript -like '*docker-step-cleanup: removed-stale-run-once*') -Message 'Docker Desktop task must remove stale deferred RunOnce remnants before verifying the one-shot flow.'
    Assert-True -Condition (($taskScript.IndexOf('Register-DockerDesktopDeferredStart', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Docker Desktop task must not schedule deferred next-sign-in repair work.'
    Assert-True -Condition ($taskScript -like '*net start {0}*') -Message 'Docker Desktop task must bring Docker services up through net start.'
    Assert-True -Condition ($taskScript -like '*Start-Service -Name*') -Message 'Docker Desktop task must first try native Start-Service before falling back to net start.'
    Assert-True -Condition ($taskScript -like '*docker-step-ok: prerequisite-service-started =>*') -Message 'Docker Desktop task must confirm prerequisite service startup.'
    Assert-True -Condition ($taskScript -like '*docker-step-info: prerequisite-service-net-start-skip =>*') -Message 'Docker Desktop task must tolerate services such as vmcompute when net start is unsupported on the guest image.'
    Assert-True -Condition ($taskScript -like '*vmcompute*') -Message 'Docker Desktop task must explicitly satisfy the vmcompute prerequisite.'
    Assert-True -Condition ($taskScript -like '*wslservice*') -Message 'Docker Desktop task must explicitly satisfy the WSL service prerequisite when present.'
    Assert-True -Condition ($taskScript -like '*wsl --install --no-distribution*') -Message 'Docker Desktop task must bootstrap WSL prerequisites before daemon verification.'
    Assert-True -Condition ($taskScript -like '*Wait-ClagnosUserInteractiveDesktopReady*') -Message 'Docker Desktop task must wait for the manager interactive desktop before launching Docker Desktop.'
    Assert-True -Condition ($taskScript -like '*Invoke-ClagnosInteractiveDesktopAutomation*') -Message 'Docker Desktop task must launch Docker Desktop through interactive desktop automation.'
    Assert-True -Condition ($taskScript -like '*master-profile-state*') -Message 'Docker Desktop task must seed the master Docker profile state before launch.'
    Assert-True -Condition ($taskScript -like '*currentContext": "desktop-linux"*') -Message 'Docker Desktop task must enforce the desktop-linux Docker context in the seeded profile.'
    Assert-True -Condition ($taskScript -like '*"LicenseTermsVersion": 2*') -Message 'Docker Desktop task must seed the accepted license terms version in the managed profile state.'
    Assert-True -Condition (($taskScript.IndexOf('docker-step-warning', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Docker Desktop task must not keep soft warning-only service startup paths.'
    Assert-True -Condition ($taskScript -like '*Wait-DockerDaemonReady*') -Message 'Docker Desktop task must keep the bounded daemon readiness loop.'
    Assert-True -Condition ($taskScript -like '*docker desktop start*') -Message 'Docker Desktop task must explicitly request Docker Desktop backend startup before probing readiness.'
    Assert-True -Condition ($taskScript -like '*docker desktop status*') -Message 'Docker Desktop task must include a bounded docker desktop status probe.'
    Assert-True -Condition ($taskScript -like '*docker info*') -Message 'Docker Desktop task must include a bounded docker info probe.'
    Assert-True -Condition ($taskScript -like '*Docker Desktop did not become daemon-ready in time*') -Message 'Docker Desktop task must fail when the daemon never becomes ready.'
    Assert-True -Condition ($taskScript -like '*$global:LASTEXITCODE = 0*') -Message 'Docker Desktop task must clear non-fatal native exit codes before completing.'
}

Invoke-Test -Name "Windows AnyDesk package avoids unbounded winget list checks and verifies its executable" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '122-install-anydesk-application'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    Assert-True -Condition ($taskScript -like '*post-install verification will determine whether the package is usable*') -Message 'AnyDesk task must treat transient winget failures as verification-required, not immediate hard failure.'
    Assert-True -Condition ($taskScript -like '*install-anydesk-application-verified: executable*') -Message 'AnyDesk task must log executable-based verification after install.'
    Assert-True -Condition ($taskScript -notlike '*winget list anydesk.anydesk*') -Message 'AnyDesk install preflight must not wait on an unbounded winget source query.'
    Assert-True -Condition ($taskScript -like '*C:\Program Files (x86)\AnyDesk\AnyDesk.exe*') -Message 'AnyDesk package must verify its managed x86 executable path directly.'
    Assert-True -Condition ($taskScript -like '*WaitForExit*') -Message 'AnyDesk task must bound the winget install wait time.'
    Assert-True -Condition ($taskScript -like '*$global:LASTEXITCODE = 0*') -Message 'AnyDesk task must clear non-fatal native exit codes before completing.'
    $manifestPath = Join-Path (Split-Path $taskPath -Parent) 'package.json'
    $manifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $manifestPath -Raw) -ErrorAction Stop
    Assert-True -Condition ([string]$manifest.statusCheck.kind -eq 'command' -and [string]$manifest.statusCheck.value -eq 'C:\Program Files (x86)\AnyDesk\AnyDesk.exe') -Message 'AnyDesk status must use its direct executable check instead of winget source enumeration.'
    Assert-True -Condition ([int]$manifest.timeout -ge 180) -Message 'AnyDesk package timeout must exceed its bounded winget installation window.'
}

Invoke-Test -Name "Windows VLC task verifies the executable after bounded winget waits" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '124-install-vlc-application'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    Assert-True -Condition ($taskScript -like '*Invoke-ProcessWithTimeout*') -Message 'VLC task must bound the winget install wait time.'
    Assert-True -Condition ($taskScript -like '*Test-VlcInstalled -WingetExe $wingetExe*') -Message 'VLC task must pass the resolved winget path into install detection explicitly.'
    Assert-True -Condition ($taskScript -like '*post-install verification will determine whether the package is usable*') -Message 'VLC task must treat bounded wait overruns as verification-required, not immediate hard failure.'
    Assert-True -Condition ($taskScript -like '*install-vlc-application-verified: executable*') -Message 'VLC task must log executable-based verification after install.'
    Assert-True -Condition ($taskScript -like '*winget list --id VideoLAN.VLC*') -Message 'VLC task must keep a package-list verification fallback.'
    Assert-True -Condition ($taskScript -like '*Wait-ForVlcInstallVerification* -WingetExe $wingetExe*') -Message 'VLC task must pass the resolved winget path into post-install verification.'
    Assert-True -Condition ($taskScript -like '*$global:LASTEXITCODE = 0*') -Message 'VLC task must clear non-fatal native exit codes before completing.'
}

Invoke-Test -Name "Windows WhatsApp task keeps a one-shot Store state contract" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '121-install-whatsapp-application'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    Assert-True -Condition ($taskScript -like '*clagnos-store-install-state.psm1*') -Message 'WhatsApp task must import the shared Store install state helper.'
    Assert-True -Condition ($taskScript -like '*Invoke-ClagnosInteractiveDesktopAutomation*') -Message 'WhatsApp task must run Store installation through the interactive desktop automation helper.'
    Assert-True -Condition ($taskScript -like '*Get-ClagnosInteractivePaths*') -Message 'WhatsApp task must provision an interactive worker path.'
    Assert-True -Condition ($taskScript -like '*RunAsMode ''interactiveToken''*') -Message 'WhatsApp task must use the manager interactive desktop token.'
    Assert-True -Condition ($taskScript -like '*no next-boot follow-up was scheduled*') -Message 'WhatsApp task must classify incomplete Store installs without scheduling a later boot follow-up.'
    Assert-True -Condition ($taskScript -like '*Wait-ClagnosUserInteractiveDesktopReady*') -Message 'WhatsApp task must wait briefly for the manager desktop when autologon is already configured.'
    Assert-True -Condition ($taskScript -like '*New-ClagnosInteractiveDesktopBlockMessage*') -Message 'WhatsApp task must classify blocked desktop states with the shared helper message builder.'
    Assert-True -Condition ($taskScript -like '*Write-ClagnosInteractiveDesktopStatusLine*') -Message 'WhatsApp task must log the resolved interactive desktop status before warning.'
    Assert-True -Condition ($taskScript -like '*cannot be deferred to a later boot*') -Message 'WhatsApp task must fail explicitly instead of leaving deferred RunOnce work behind.'
    Assert-True -Condition ($taskScript -like '*Write-ClagnosStoreInstallState*') -Message 'WhatsApp task must persist explicit store install state records.'
    Assert-True -Condition ($taskScript -like '*9NKSQGP7F2NH*') -Message 'WhatsApp task must keep the Store package id in the install contract.'
    Assert-True -Condition ($taskScript -like '*install --id $packageId --source msstore --accept-source-agreements --accept-package-agreements*') -Message 'WhatsApp task must keep the Microsoft Store winget install contract.'
}

Invoke-Test -Name "Windows Teams task keeps the shared Microsoft Store state contract" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '118-install-teams-application'
    $taskScript = [string](Get-Content -LiteralPath $taskPath -Raw)
    Assert-True -Condition ($taskScript -like '*clagnos-store-install-state.psm1*') -Message 'Teams task must import the shared Store install state helper.'
    Assert-True -Condition ($taskScript -like '*Invoke-ClagnosInteractiveDesktopAutomation*') -Message 'Teams task must run Store installation through the interactive desktop automation helper.'
    Assert-True -Condition ($taskScript -like '*Wait-ClagnosUserInteractiveDesktopReady*') -Message 'Teams task must wait briefly for the manager desktop when autologon is already configured.'
    Assert-True -Condition ($taskScript -like '*New-ClagnosInteractiveDesktopBlockMessage*') -Message 'Teams task must classify blocked desktop states with the shared helper message builder.'
    Assert-True -Condition ($taskScript -like '*Write-ClagnosInteractiveDesktopStatusLine*') -Message 'Teams task must log the resolved interactive desktop status before warning.'
    Assert-True -Condition ($taskScript -like '*RunAsMode ''interactiveToken''*') -Message 'Teams task must use the manager interactive desktop token.'
    Assert-True -Condition ($taskScript -like '*Write-ClagnosStoreInstallState*') -Message 'Teams task must persist explicit Store install state records.'
    Assert-True -Condition ($taskScript -like '*cannot be deferred to a later boot*') -Message 'Teams task must fail explicitly instead of leaving deferred RunOnce work behind.'
    Assert-True -Condition ($taskScript -like '*winget install "Microsoft Teams" -s msstore --accept-source-agreements --accept-package-agreements --silent --disable-interactivity*') -Message 'Teams task must keep the unattended Microsoft Store winget install contract.'
}

Invoke-Test -Name "Interactive session helper distinguishes Store desktop readiness states" -Action {
    $helperPath = Join-Path $RepoRoot 'tools\scripts\clagnos-interactive-session-helper.ps1'
    $helperText = [string](Get-Content -LiteralPath $helperPath -Raw)
    foreach ($fragment in @(
        'function Get-ClagnosUserInteractiveDesktopStatus',
        'function Wait-ClagnosUserInteractiveDesktopReady',
        'function Write-ClagnosInteractiveDesktopStatusLine',
        'function New-ClagnosInteractiveDesktopBlockMessage',
        'function Get-ClagnosCurrentUserStartAppMatches',
        'function Invoke-ClagnosUserAppxRegistrationRepair',
        'Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop *> $null',
        'app-id-match-count=',
        'autologon-disabled',
        'autologon-pending',
        'explorer-not-ready',
        'Run 102-configure-autologon-settings and restart the VM before retrying the Microsoft Store task.'
    )) {
        Assert-True -Condition ($helperText -like ('*' + [string]$fragment + '*')) -Message ("Interactive session helper must include fragment '{0}'." -f [string]$fragment)
    }
    Assert-True -Condition (($helperText.IndexOf('PSObject.Properties.Match([string]$PropertyName).Count -lt 1', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Interactive session helper must tolerate missing Winlogon properties without strict-mode crashes.'
}

Invoke-Test -Name "Store package post-install tasks run synchronously with the installer" -Action {
    try {
        function Resolve-ClagnosManagedVmTarget {
            param([hashtable]$Options, [hashtable]$ConfigMap, [string]$OperationName)
            return [pscustomobject]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
            }
        }
        function Get-ClagnosTaskBlocksFromDirectory {
            param([string]$DirectoryPath, [string]$Platform, [string]$Stage)
            return [pscustomobject]@{
                ActiveTasks = @([pscustomobject]@{
                    Name = '10003-create-public-desktop-shortcuts'
                    TaskNumber = 10003
                    Script = 'Write-Host shortcuts'
                    TimeoutSeconds = 45
                })
            }
        }
        function Resolve-ClagnosRuntimeTaskBlocks {
            param([object[]]$TemplateTaskBlocks, [hashtable]$Context)
            return @($TemplateTaskBlocks)
        }
        function Get-ClagnosVmDetails {
            param([hashtable]$Context)
            return [pscustomobject]@{
                VmFqdn = 'samplevm.austriaeast.cloudapp.azure.com'
                PublicIP = '1.2.3.4'
            }
        }
        function Invoke-ClagnosSshTaskBlocks {
            param(
                [string]$Platform,
                [string]$RepoRoot,
                [string]$SshHost,
                [string]$SshUser,
                [string]$SshPassword,
                [string]$SshPort,
                [string]$ResourceGroup,
                [string]$VmName,
                [object[]]$TaskBlocks,
                [string]$TaskOutcomeMode,
                [string]$PerfTaskCategory,
                [int]$SshMaxRetries,
                [int]$SshTaskTimeoutSeconds,
                [int]$SshConnectTimeoutSeconds,
                [string]$ConfiguredPySshClientPath
            )

            $script:IsolatedStoreFollowUpInvocation = [pscustomobject]@{
                TaskNames = @($TaskBlocks | ForEach-Object { [string]$_.Name })
                TaskOutcomeMode = $TaskOutcomeMode
                PerfTaskCategory = $PerfTaskCategory
            }

            return [pscustomobject]@{ SuccessCount = @($TaskBlocks).Count; FailedCount = 0; WarningCount = 0; ErrorCount = 0 }
        }

        $runtime = [pscustomobject]@{
            Context = [ordered]@{
                ResourceGroup = 'rg-samplevm-ate1-g1'
                VmName = 'samplevm'
                VmInitTaskDir = 'windows/init'
                VmUpdateTaskDir = 'windows/update'
                VmUser = 'manager'
                VmPass = 'secret'
                VmAssistantUser = 'assistant'
                SshPort = '444'
                AzLocation = 'austriaeast'
            }
            Platform = 'windows'
            EffectiveConfigMap = @{}
            TaskOutcomeMode = 'continue'
            ConfiguredPySshClientPath = ''
            SshTaskTimeoutSeconds = 180
            SshConnectTimeoutSeconds = 30
        }

        $packageTask = [pscustomobject]@{
            Name = 'microsoft-teams'
            Script = 'Write-Host teams'
            TaskRootPath = $RepoRoot
            DirectoryPath = $RepoRoot
            TaskMetadataPath = (Join-Path $RepoRoot 'packages\builtin\windows\microsoft-teams\package.json')
            StageRootDirectoryPath = (Join-Path $RepoRoot 'packages\builtin\windows')
            RelativePath = 'microsoft-teams/install.ps1'
            TimeoutSeconds = 75
            AssetSpecs = @()
            PackageSpec = [pscustomobject]@{ Id = 'microsoft-teams'; PostInstallTasks = @('10003-create-public-desktop-shortcuts') }
        }
        $result = Invoke-ClagnosTaskExecutionWithTarget -Runtime $runtime -Options @{ 'vm-name' = 'samplevm' } -OperationName 'package' -Stage 'update' -Requested 'microsoft-teams' -PackageTaskBlock $packageTask -TaskOutcomeModeOverride strict

        Assert-True -Condition ($null -ne $script:IsolatedStoreFollowUpInvocation) -Message 'Store package installation must invoke the SSH task runner.'
        Assert-True -Condition ((@($script:IsolatedStoreFollowUpInvocation.TaskNames) -join ',') -eq 'microsoft-teams,10003-create-public-desktop-shortcuts') -Message 'The package manifest postInstallTasks list must append the shortcut refresh script.'
        Assert-True -Condition ((@($result.TaskBlocks).Count) -eq 2) -Message 'Package install results must include the installer and its post-install task.'
        Assert-True -Condition ([string]$result.Task.Name -eq 'microsoft-teams') -Message 'Package install results must report the package id as the primary task.'
    }
    finally {
        foreach ($functionName in @(
            'Resolve-ClagnosManagedVmTarget',
            'Get-ClagnosTaskBlocksFromDirectory',
            'Resolve-ClagnosRuntimeTaskBlocks',
            'Get-ClagnosVmDetails',
            'Invoke-ClagnosSshTaskBlocks'
        )) {
            Remove-Item ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
        }
        Remove-Variable -Name IsolatedStoreFollowUpInvocation -Scope Script -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Windows UX helper asset and validation model" -Action {
    $context = [ordered]@{
        VmUser = "manager"
        VmPass = "secret"
        VmAssistantUser = "assistant"
        VmAssistantPass = "secret2"
        SshPort = "444"
        RdpPort = "3389"
        TcpPorts = @("444","3389","5985","11434")
        ResourceGroup = "rg-samplevm"
        VmName = "samplevm"
        AzLocation = "austriaeast"
        VmSize = "Standard_B2as_v2"
        VmImage = "example:image:urn"
        VmDiskName = "disk-samplevm"
        VmDiskSize = "128"
        VmStorageSku = "StandardSSD_LRS"
    }

    $resolvedUxTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @(
        (New-RepoTaskTemplate -Platform windows -Stage update -TaskName '10003-configure-windows-experience' -TimeoutSeconds 600)
    ) -Context $context)[0]
    $uxAssetCopies = @($resolvedUxTask.AssetCopies)
    $uxScriptBody = [string]$resolvedUxTask.Script
    $uxTaskJsonText = [string](Get-Content -LiteralPath (Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '10004-configure-windows-experience') -Raw)
    Assert-True -Condition ($uxAssetCopies.Count -ge 1) -Message "UX task must publish its required helper asset set."
    Assert-True -Condition ($uxTaskJsonText -like '*C:/Windows/Temp/clagnos-interactive-session-helper.ps1*') -Message "UX task helper remote path mismatch."
    Assert-True -Condition ($uxScriptBody -like '*TaskManager\settings.json*') -Message "UX task must validate Task Manager through settings.json."
    Assert-True -Condition ($uxScriptBody -like '*SearchboxTaskbarMode*') -Message "UX task must hide the taskbar search control."
    Assert-True -Condition ($uxScriptBody -like '*AllowNewsAndInterests*') -Message "UX task must hide Widgets through machine policy."
    Assert-True -Condition ($uxScriptBody -like '*ShowTaskViewButton*') -Message "UX task must hide Task View."
    Assert-True -Condition ($uxScriptBody -like '*Disable-ComputerRestore*') -Message "UX task must disable System Restore."
    Assert-True -Condition ($uxScriptBody -like '*vssadmin.exe delete shadows*') -Message "UX task must delete existing shadow copies."
    Assert-True -Condition ($uxScriptBody -like '*DisableThumbsDBOnNetworkFolders*') -Message "UX task must suppress Thumbs.db creation on known Windows Explorer policy paths."
    Assert-True -Condition ($uxScriptBody -like '*DisableThumbnailCache*') -Message "UX task must suppress thumbnail cache generation."
    Assert-True -Condition ($uxScriptBody -like '*UserAuthentication*') -Message "UX task must disable RDP NLA."
    Assert-True -Condition ($uxScriptBody -like '*shell-icons-hidden*') -Message "UX task must hide shell-managed desktop icons."
    Assert-True -Condition ($uxScriptBody -like '*System Volume Information*') -Message "UX task must attempt best-effort System Volume Information cleanup."
    Assert-True -Condition ($uxScriptBody -like '*Convert-ClagnosShellSortBytesToPropertyExpression*') -Message "UX task must normalize Windows shell sort binary values during validation."
    Assert-True -Condition ($uxScriptBody -like '*b725f130-47ef-101a-a5f1-02608c9eebac:10*') -Message "UX task must recognize the shell property key for System.ItemNameDisplay."
    Assert-True -Condition ($uxScriptBody -like '*Invoke-RegQuiet*') -Message "UX task must keep registry hive load and unload operations quiet under strict PowerShell native error handling."
    Assert-True -Condition (-not $resolvedUxTask.PSObject.Properties.Match('InteractiveResultPath').Count) -Message "UX task must not publish reboot-resume metadata."

    $resolvedCopyUserSettingsTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @(
        (New-RepoTaskTemplate -Platform windows -Stage update -TaskName '10005-copy-user-settings' -TimeoutSeconds 1800)
    ) -Context $context)[0]
    $copyUserSettingsAssetCopies = @($resolvedCopyUserSettingsTask.AssetCopies)
    $copyUserSettingsBody = [string]$resolvedCopyUserSettingsTask.Script
    $copyUserSettingsJsonText = [string](Get-Content -LiteralPath (Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '10005-copy-user-settings') -Raw)
    Assert-True -Condition ($copyUserSettingsAssetCopies.Count -ge 1) -Message "Copy user settings task must publish its required helper asset set."
    Assert-True -Condition ($copyUserSettingsJsonText -like '*C:/Windows/Temp/clagnos-interactive-session-helper.ps1*') -Message "Copy user settings helper remote path mismatch."
    Assert-True -Condition ($copyUserSettingsBody -like '*copy-user-settings-profile-materialized*') -Message "Copy user settings task must materialize the assistant profile."
    Assert-True -Condition ($copyUserSettingsBody -like '*copy-user-settings-profile-ready*') -Message "Copy user settings task must log when the assistant profile hive is fully ready."
    Assert-True -Condition ($copyUserSettingsBody -like '*copy-user-settings-profile-partial*') -Message "Copy user settings task must log partial assistant profile paths before retrying materialization."
    Assert-True -Condition ($copyUserSettingsBody -like '*Test-PortableProfileHiveReady*') -Message "Copy user settings task must require NTUSER.DAT readiness before treating a profile as materialized."
    Assert-True -Condition ($copyUserSettingsBody -like '*User profile hive could not be materialized*') -Message "Copy user settings task must fail clearly when NTUSER.DAT never appears."
    Assert-True -Condition ($copyUserSettingsBody -like '*Invoke-PortableProfileMirror*') -Message "Copy user settings task must mirror portable profile files."
    Assert-True -Condition ($copyUserSettingsBody -like '*Invoke-PortableRegistryMirror*') -Message "Copy user settings task must mirror portable registry state."
    Assert-True -Condition ($copyUserSettingsBody -like '*Invoke-PortableAssistantRegistryMirror*') -Message "Copy user settings task must mirror portable manager state into assistant."
    Assert-True -Condition ($copyUserSettingsBody -like '*Invoke-PortableDefaultProfileRegistryMirror*') -Message "Copy user settings task must mirror portable manager state into the default profile template."
    Assert-True -Condition ($copyUserSettingsBody -like '*Invoke-PortableLogonRegistryMirror*') -Message "Copy user settings task must mirror portable manager state into the Winlogon hive."
    Assert-True -Condition ($copyUserSettingsBody -like '*HKEY_USERS\.DEFAULT*') -Message "Copy user settings task must seed the logon-screen hive."
    Assert-True -Condition ($copyUserSettingsBody -like '*Get-PortableProfileExcludedDirectories*') -Message "Copy user settings task must define portable profile-directory exclusions."
    Assert-True -Condition ($copyUserSettingsBody -like '*Get-PortableProfileExcludedFiles*') -Message "Copy user settings task must define portable file exclusions."
    Assert-True -Condition ($copyUserSettingsBody -like '*Get-PortableProfileTargetPruneExcludedFiles*') -Message "Copy user settings task must define a target-prune exclusion set that preserves target-owned profile hives."
    Assert-True -Condition ($copyUserSettingsBody -like '*-TargetPruneExcludedFiles @(Get-PortableProfileTargetPruneExcludedFiles)*') -Message "Copy user settings task must avoid pruning NTUSER.DAT and UsrClass.dat from the assistant target profile."
    Assert-True -Condition ($copyUserSettingsBody -like '*Remove-StaleExcludedTargetPaths -TargetPath $TargetPath -ExcludedDirectories $TargetPruneExcludedDirectories -ExcludedFiles $TargetPruneExcludedFiles -Label $Label*') -Message "Copy user settings target pruning must consistently use the dedicated target-prune exclusion set."
    Assert-True -Condition ($copyUserSettingsBody -like '*Get-PortableRegistryExcludedPrefixes*') -Message "Copy user settings task must define portable registry exclusions."
    Assert-True -Condition ($copyUserSettingsBody -like '*Get-PortableRegistryClassesExcludedPrefixes*') -Message "Copy user settings task must define portable registry exclusions for classes-hive-only branches."
    Assert-True -Condition ($copyUserSettingsBody -like '*Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository*') -Message "Copy user settings task must exclude non-portable AppModel repository branches from classes-hive mirroring."
    Assert-True -Condition ($copyUserSettingsBody -like '*-ExcludedPrefixes @(Get-PortableRegistryClassesExcludedPrefixes)*') -Message "Copy user settings task must apply the classes-hive exclusion set during assistant/default UsrClass mirroring."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Roaming\Microsoft\Credentials*') -Message "Copy user settings task must exclude portable-incompatible credential stores."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Local\Microsoft\WindowsApps*') -Message "Copy user settings task must exclude WindowsApps shims that are not portable across profiles."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Local\Packages*') -Message "Copy user settings task must exclude live packaged-app containers that are not portable across profiles."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Local\Microsoft\Protect*') -Message "Copy user settings task must exclude DPAPI-bound secret stores."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Local\Microsoft\Vault*') -Message "Copy user settings task must exclude vault stores."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Local\Microsoft\IdentityCRL*') -Message "Copy user settings task must exclude identity stores."
    Assert-True -Condition ($copyUserSettingsBody -like '*AppData\Local\Microsoft\Windows\WebCache*') -Message "Copy user settings task must exclude web cache state."
    Assert-True -Condition ($copyUserSettingsBody -like '*Login Data*') -Message "Copy user settings task must exclude Chromium login data."
    Assert-True -Condition ($copyUserSettingsBody -like '*Cookies*') -Message "Copy user settings task must exclude Chromium cookie stores."
    Assert-True -Condition ($copyUserSettingsBody -like '*NTUSER.DAT*') -Message "Copy user settings task must exclude raw source hive files from profile copies."
    Assert-True -Condition ($copyUserSettingsBody -like '*UsrClass.dat*') -Message "Copy user settings task must exclude raw source classes hives from profile copies."
    Assert-True -Condition ($copyUserSettingsBody -like '*Assert-RepresentativePathCopiedIfPresent*') -Message "Copy user settings task must verify representative profile paths after mirroring."
    Assert-True -Condition ($copyUserSettingsBody -like '*Assert-ExcludedPathAbsentIfPresent*') -Message "Copy user settings task must verify excluded non-portable paths stay absent."
    Assert-True -Condition ($copyUserSettingsBody -like '*Assert-RegistryBranchMirroredIfPresent*') -Message "Copy user settings task must verify representative mirrored registry branches."
    Assert-True -Condition ($copyUserSettingsBody -like '*copy-user-settings-portable-mirror-validated*') -Message "Copy user settings task must log portable mirror validation."
    Assert-True -Condition ($copyUserSettingsBody -like '*Invoke-RegQuiet*') -Message "Copy user settings task must run registry hive load and unload operations through the quiet helper."
    Assert-True -Condition ($copyUserSettingsBody -like '*with exit code*') -Message "Copy user settings task must include the unload exit code in terminal hive cleanup failures."
    Assert-True -Condition ($copyUserSettingsBody -like '*Wait-UserSessionsAndProcessesToSettle*') -Message "Copy user settings task must use a bounded settle helper instead of a fixed post-logoff sleep."
    Assert-True -Condition (($copyUserSettingsBody.IndexOf('Start-Sleep -Seconds 5', [System.StringComparison]::Ordinal)) -lt 0) -Message "Copy user settings task must not keep the old fixed five-second post-logoff sleep."
    Assert-True -Condition (($copyUserSettingsBody.IndexOf('Get-ProfileCopySpecs', [System.StringComparison]::Ordinal)) -lt 0) -Message "Copy user settings task must not keep the retired targeted copy-spec builder."
    Assert-True -Condition (-not $resolvedCopyUserSettingsTask.PSObject.Properties.Match('InteractiveResultPath').Count) -Message "Copy user settings task must not publish reboot-resume metadata."

    $resolvedAdvancedTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @(
        (New-RepoTaskTemplate -Platform windows -Stage update -TaskName '10004-configure-advanced-settings' -TimeoutSeconds 300)
    ) -Context $context)[0]
    $advancedAssetCopies = @($resolvedAdvancedTask.AssetCopies)
    $advancedScriptBody = [string]$resolvedAdvancedTask.Script
    Assert-True -Condition ($advancedAssetCopies.Count -le 1) -Message "Advanced settings task must not publish more than the shared session-environment helper asset."
    if ($advancedAssetCopies.Count -eq 1) {
        Assert-True -Condition ([string]$advancedAssetCopies[0].RemotePath -eq 'C:/Windows/Temp/clagnos-session-environment.psm1') -Message "Advanced settings task may only materialize the session-environment helper asset."
    }
Assert-True -Condition ($advancedScriptBody -notlike '*VolumeControl*') -Message "Advanced settings task must not keep legacy audio tuning."
Assert-True -Condition (-not $resolvedAdvancedTask.PSObject.Properties.Match('InteractiveResultPath').Count) -Message "Advanced settings task must not publish reboot-resume metadata."
}

Invoke-Test -Name "Vm-update app-state plugin contract resolves only task-local app-state zip paths" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("clagnos-app-state-plugin-test-" + [Guid]::NewGuid().ToString("N"))
    $updateDir = Join-Path $tempRoot 'windows\update'
    $localDir = Join-Path $updateDir 'local'
    New-Item -Path $localDir -ItemType Directory -Force | Out-Null

    function New-TestAppStateZip {
        param(
            [string]$DestinationPath,
            [string]$TaskName,
            [string]$ManifestTaskName = ''
        )

        $scratchDir = Join-Path $tempRoot ("plugin-" + [Guid]::NewGuid().ToString("N"))
        New-Item -Path $scratchDir -ItemType Directory -Force | Out-Null
        try {
            if ([string]::IsNullOrWhiteSpace([string]$ManifestTaskName)) {
                $ManifestTaskName = [string]$TaskName
            }
            $manifest = [ordered]@{
                version = 1
                taskName = [string]$ManifestTaskName
                machineFiles = @()
                machineDirectories = @()
                profileFiles = @()
                profileDirectories = @()
                registryImports = @()
            }
            Set-Content -LiteralPath (Join-Path $scratchDir 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 6) -Encoding UTF8
            if (Test-Path -LiteralPath $DestinationPath) {
                Remove-Item -LiteralPath $DestinationPath -Force -ErrorAction SilentlyContinue
            }
            Compress-Archive -LiteralPath (Join-Path $scratchDir 'app-state.manifest.json') -DestinationPath $DestinationPath -Force
        }
        finally {
            Remove-Item -LiteralPath $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        New-SmokeTaskFolder -RootPath $updateDir -RelativeFolderPath '113-install-docker-desktop-application' -Platform windows -ScriptText 'Write-Host "tracked"' -TaskJson @{
            priority = 113
            enabled = $true
            timeout = 600
        }
        New-SmokeTaskFolder -RootPath $updateDir -RelativeFolderPath 'local/1001-install-configure-screen-reader' -Platform windows -ScriptText 'Write-Host "local"' -TaskJson @{
            priority = 1001
            enabled = $true
            timeout = 780
        }

        $catalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath $updateDir -Platform windows -Stage update
        $trackedTask = @($catalog.ActiveTasks | Where-Object { [string]$_.Name -eq '113-install-docker-desktop-application' })[0]
        $localTask = @($catalog.ActiveTasks | Where-Object { [string]$_.Name -eq '1001-install-configure-screen-reader' })[0]

        $expectedTrackedPluginDir = Join-Path (Join-Path $updateDir '113-install-docker-desktop-application') 'app-state'
        $expectedLocalPluginDir = Join-Path (Join-Path $localDir '1001-install-configure-screen-reader') 'app-state'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStateRootDirectoryPath -TaskBlock $trackedTask) -eq $expectedTrackedPluginDir) -Message 'Tracked vm-update tasks must resolve their task-local app-state root.'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStateRootDirectoryPath -TaskBlock $localTask) -eq $expectedLocalPluginDir) -Message 'Local-only vm-update tasks must resolve their task-local app-state root.'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $trackedTask) -eq $expectedTrackedPluginDir) -Message 'Tracked task plugin directory mismatch.'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $localTask) -eq $expectedLocalPluginDir) -Message 'Local-only task plugin directory mismatch.'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStateZipPath -TaskBlock $trackedTask) -eq (Join-Path $expectedTrackedPluginDir 'app-state.zip')) -Message 'Tracked task plugin zip path mismatch.'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStateZipPath -TaskBlock $localTask) -eq (Join-Path $expectedLocalPluginDir 'app-state.zip')) -Message 'Local-only task plugin zip path mismatch.'

        New-Item -Path (Join-Path $localDir 'legacy-side-assets') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $localDir 'legacy-side-assets\app-state.zip') -Value 'legacy' -Encoding UTF8
        $missingPluginInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $localTask
        Assert-True -Condition ([string]$missingPluginInfo.Status -eq 'missing-plugin') -Message 'Task app-state resolution must not read zip payloads from local/ helper directories.'

        New-Item -Path $expectedTrackedPluginDir -ItemType Directory -Force | Out-Null
        $missingZipInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $trackedTask
        Assert-True -Condition ([string]$missingZipInfo.Status -eq 'missing-zip') -Message 'Existing app-state plugin folders without app-state.zip must report missing-zip.'

        New-TestAppStateZip -DestinationPath (Join-Path $expectedTrackedPluginDir 'app-state.zip') -TaskName '113-install-docker-desktop-application' -ManifestTaskName 'wrong-task-name'
        $invalidZipInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $trackedTask
        Assert-True -Condition ([string]$invalidZipInfo.Status -eq 'invalid') -Message 'Task app-state plugin zips with mismatched taskName must be rejected.'

        New-Item -Path $expectedLocalPluginDir -ItemType Directory -Force | Out-Null
        New-TestAppStateZip -DestinationPath (Join-Path $expectedLocalPluginDir 'app-state.zip') -TaskName '1001-install-configure-screen-reader'
        $readyInfo = Get-ClagnosTaskAppStatePluginInfo -TaskBlock $localTask
        Assert-True -Condition ([string]$readyInfo.Status -eq 'ready') -Message 'Valid per-task app-state zip plugins must resolve as ready.'
        Assert-True -Condition ($null -ne $readyInfo.Manifest) -Message 'Ready app-state zip plugins must publish their parsed manifest.'
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Invoke-Test -Name "Vm-update app-state plugin runtime removes legacy restore surfaces" -Action {
    $runtimeManifestPath = Join-Path $RepoRoot 'modules\clagnos-runtime-manifest.ps1'
    $runtimeManifestText = [string](Get-Content -LiteralPath $runtimeManifestPath -Raw)
    $runnerPath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-ssh-task-runner.ps1'
    $runnerText = [string](Get-Content -LiteralPath $runnerPath -Raw)
    $runCommandRunnerPath = Join-Path $RepoRoot 'modules\tasks\run-command\runner.ps1'
    $runCommandRunnerText = [string](Get-Content -LiteralPath $runCommandRunnerPath -Raw)
    $connectionRuntimePath = Join-Path $RepoRoot 'modules\ui\connection\clagnos-connection-runtime.ps1'
    $connectionRuntimeText = [string](Get-Content -LiteralPath $connectionRuntimePath -Raw)
    $sessionHelpersPath = Join-Path $RepoRoot 'modules\tasks\ssh\session.ps1'
    $sessionHelpersText = [string](Get-Content -LiteralPath $sessionHelpersPath -Raw)
    $localExportModulePath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-plugin-local-export.psm1'
    $localExportModuleText = [string](Get-Content -LiteralPath $localExportModulePath -Raw)
    $gitignoreText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot '.gitignore') -Raw)

    Assert-True -Condition ($runtimeManifestText -like '*modules/core/tasks/clagnos-app-state-plugin.ps1*') -Message 'Runtime manifest must load the shared app-state plugin helper module.'
    Assert-True -Condition ($runnerText -like '*Invoke-ClagnosTaskAppStatePostProcess*') -Message 'Windows update SSH runner must invoke the shared app-state post-process after each task.'
    Assert-True -Condition ($runCommandRunnerText -like '*Invoke-ClagnosTaskAppStatePostProcess*') -Message 'VM init run-command runner must invoke the shared app-state post-process after each task.'
    Assert-True -Condition ($runCommandRunnerText -like '*Invoke-ClagnosRunCommandDeferredAppStateFlush*') -Message 'VM init run-command runner must defer app-state replay until SSH is ready.'
    Assert-True -Condition ($runCommandRunnerText -like '*App-state deferred:*') -Message 'VM init run-command runner must log deferred app-state replay while waiting for SSH readiness.'
    Assert-True -Condition ($runCommandRunnerText -like '*SSH was not ready before vm-init completed*') -Message 'VM init run-command runner must summarize unresolved deferred app-state replay at stage end.'
    Assert-True -Condition ($runnerText -like '*Invoke-ClagnosSshTaskScript*') -Message 'Windows update SSH runner must use the shared SSH task execution wrapper.'
    Assert-True -Condition ($runnerText -like '*signal-warning=*') -Message 'Windows update SSH runner must surface task-emitted warning signals in the stage summary.'
    Assert-True -Condition ($runnerText -like '*Wait-ClagnosProvisioningReadyOrRepair*') -Message 'Windows update SSH runner must guard against persistent Updating provisioning states before task execution.'
    Assert-True -Condition ($connectionRuntimeText -like '*Wait-ClagnosProvisioningReadyOrRepair*') -Message 'Connection runtime must repair persistent Updating provisioning states before launching SSH or RDP commands.'
    Assert-True -Condition (($runnerText.IndexOf('-AssistantUser', [System.StringComparison]::Ordinal) -ge 0) -and ($runnerText.IndexOf('[string]$AssistantUser', [System.StringComparison]::Ordinal) -ge 0)) -Message 'Windows update SSH runner must pass the assistant user through to app-state replay.'
    Assert-True -Condition ($sessionHelpersText -like '*function Invoke-ClagnosOneShotSshTask*') -Message 'SSH session helpers must provide a one-shot task fallback helper.'
    Assert-True -Condition ($sessionHelpersText -like '*function Invoke-ClagnosSshTaskScript*') -Message 'SSH session helpers must provide a shared task-execution wrapper.'
    Assert-True -Condition (-not ($runCommandRunnerText -like '*-Transport ''run-command''*')) -Message 'VM init run-command runner must not keep the retired run-command app-state transport.'
    Assert-True -Condition ($localExportModuleText -like '*function Get-LocalAppStatePluginDirectoryPath*') -Message 'Local app-state export helpers must resolve task-local plugin directories.'
    Assert-True -Condition ($localExportModuleText -like '*Join-Path $candidate ''app-state''*') -Message 'Local app-state export helpers must write to each task-local app-state folder.'
    Assert-True -Condition ($localExportModuleText -like '*''jaws'' = ''133-install-jaws-application''*') -Message 'Local app-state export helpers must map JAWS to its tracked task.'
    Assert-True -Condition ($localExportModuleText -like '*HKLM\\Software\\Freedom Scientific*') -Message 'Local app-state export helpers must export the JAWS machine Freedom Scientific subtree.'
    Assert-True -Condition ($localExportModuleText -like '*HKLM\\Software\\WOW6432Node\\Freedom Scientific*') -Message 'Local app-state export helpers must export the JAWS WOW6432 Freedom Scientific subtree.'
    Assert-True -Condition ($localExportModuleText -like '*HKCU\\Software\\Freedom Scientific*') -Message 'Local app-state export helpers must export the JAWS user Freedom Scientific subtree.'
    Assert-True -Condition (-not ($localExportModuleText -like '*AppStatesRoot*')) -Message 'Local app-state export helpers must not keep the retired shared app-states root.'
    Assert-True -Condition ($gitignoreText -like '*windows/update/**/app-state/***') -Message '.gitignore must ignore Windows update task-local app-state payloads.'
    Assert-True -Condition ($gitignoreText -like '*windows/init/**/app-state/***') -Message '.gitignore must ignore Windows init task-local app-state payloads.'
    Assert-True -Condition ($gitignoreText -like '*linux/update/**/app-state/***') -Message '.gitignore must ignore Linux update task-local app-state payloads.'
    Assert-True -Condition ($gitignoreText -like '*linux/init/**/app-state/***') -Message '.gitignore must ignore Linux init task-local app-state payloads.'
    Assert-True -Condition ($gitignoreText -like '*windows/update/**/backup-app-states/***') -Message '.gitignore must ignore Windows update backup-app-states snapshots.'
    Assert-True -Condition ($gitignoreText -like '*windows/init/**/backup-app-states/***') -Message '.gitignore must ignore Windows init backup-app-states snapshots.'
    Assert-True -Condition ($gitignoreText -like '*linux/update/**/backup-app-states/***') -Message '.gitignore must ignore Linux update backup-app-states snapshots.'
    Assert-True -Condition ($gitignoreText -like '*linux/init/**/backup-app-states/***') -Message '.gitignore must ignore Linux init backup-app-states snapshots.'
    Assert-True -Condition (-not ($gitignoreText -like '*windows/update/app-states/***')) -Message '.gitignore must not keep the retired Windows update shared app-states root ignore.'
    Assert-True -Condition (-not ($gitignoreText -like '*windows/init/app-states/***')) -Message '.gitignore must not keep the retired Windows init shared app-states root ignore.'
    Assert-True -Condition (-not ($gitignoreText -like '*linux/update/app-states/***')) -Message '.gitignore must not keep the retired Linux update shared app-states root ignore.'
    Assert-True -Condition (-not ($gitignoreText -like '*linux/init/app-states/***')) -Message '.gitignore must not keep the retired Linux init shared app-states root ignore.'
    Assert-True -Condition (-not ($runnerText -like '*linux replay is not implemented yet*')) -Message 'Shared app-state runtime must not keep the old Linux replay unsupported warning.'

    foreach ($removedPath in @(
        'windows\update\133-restore-managed-app-state.ps1',
        'windows\update\app-state\managed-app-state-common.psm1',
        'windows\update\app-state\managed-app-state-manifest.json'
    )) {
        Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $removedPath))) -Message ("Legacy app-state restore surface must be removed: {0}" -f $removedPath)
    }
}

Invoke-Test -Name "Windows public desktop shortcut contract includes refreshed public shortcuts" -Action {
    $shortcutTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '10002-create-public-desktop-shortcuts'
    $shortcutTaskScript = [string](Get-Content -LiteralPath $shortcutTaskPath -Raw)
    $shortcutTaskJsonPath = Join-Path (Split-Path -Path $shortcutTaskPath -Parent) 'task.json'
    $shortcutTaskJsonText = [string](Get-Content -LiteralPath $shortcutTaskJsonPath -Raw)
    $healthTaskPath = Get-RepoSummaryReadbackScriptPath -Platform windows
    $healthTaskScript = [string](Get-Content -LiteralPath $healthTaskPath -Raw)
    $cicekSepetiLabel = ConvertFrom-UnicodeCodePoints -CodePoints @(0x00C7, 0x0069, 0x00E7, 0x0065, 0x006B, 0x0053, 0x0065, 0x0070, 0x0065, 0x0074, 0x0069)
    $eksiSozlukLabel = ConvertFrom-UnicodeCodePoints -CodePoints @(0x0045, 0x006B, 0x015F, 0x0069, 0x0053, 0x00F6, 0x007A, 0x006C, 0x00FC, 0x006B)
    $generatedShortcutNames = @(
        ('q1{0}' -f $eksiSozlukLabel),
        ('r13{0} Business' -f $cicekSepetiLabel),
        ('r14{0} Personal' -f $cicekSepetiLabel)
    )

    $expectedShortcutNames = @(
        'a1ChatGPT Web',
        'a2CodexApp',
        'a3Be My Eyes',
        'a4WhatsApp Business',
        'a5WhatsApp Personal',
        'a6AnyDesk',
        'a7Docker Desktop',
        'a8WindScribe',
        'a9VLC Player',
        'a10NVDA',
        'a11MS Edge',
        'a12Itunes',
        'b1GarantiBank Business',
        'b2GarantiBank Personal',
        'b3QnbBank Business',
        'b4QnbBank Personal',
        'b5AktifBank Business',
        'b6AktifBank Personal',
        'b7ZiraatBank Business',
        'b8ZiraatBank Personal',
        'c1Cmd',
        'd1RClone CLI',
        'd2One Drive',
        'd3Google Drive',
        'd4ICloud',
        'e1Mail {0}',
        'g1Apple Developer',
        'g2Google Developer',
        'g3Microsoft Developer',
        'g4Azure Portal',
        'i1Internet Business',
        'i2Internet Personal',
        'j0Jaws',
        'k1Codex CLI',
        'k2Gemini CLI',
        'k3Github Copilot CLI',
        'm1Digital Tax Office',
        'n1Notepad',
        'o1Outlook',
        'o2Teams',
        'o3Word',
        'o4Excel',
        'o5Power Point',
        'o6OneNote',
        ('q1{0}' -f $eksiSozlukLabel),
        'q2Spotify',
        'q3Netflix',
        'q4eGovernment',
        'q5Apple Account',
        'q6AJet Flights',
        'q7TCDD Train',
        'q8OBilet Bus',
        'r1Sahibinden Business',
        'r2Sahibinden Personal',
        'r3Letgo Business',
        'r4Letgo Personal',
        'r5Trendyol Business',
        'r6Trendyol Personal',
        'r7Amazon TR Business',
        'r8Amazon TR Personal',
        'r9HepsiBurada Business',
        'r10HepsiBurada Personal',
        'r11N11 Business',
        'r12N11 Personal',
        ('r13{0} Business' -f $cicekSepetiLabel),
        ('r14{0} Personal' -f $cicekSepetiLabel),
        'r15Pazarama Business',
        'r16Pazarama Personal',
        'r17PTTAVM Business',
        'r18PTTAVM Personal',
        'r19Ozon Business',
        'r20Ozon Personal',
        'r21Getir Business',
        'r22Getir Personal',
        's1LinkedIn Business',
        's2LinkedIn Personal',
        's3YouTube Business',
        's4YouTube Personal',
        's5GitHub Business',
        's6GitHub Personal',
        's7TikTok Business',
        's8TikTok Personal',
        's9Instagram Business',
        's10Instagram Personal',
        's11Facebook Business',
        's12Facebook Personal',
        's13X-Twitter Business',
        's14X-Twitter Personal',
        's15{0} Web',
        's16{0} Blog',
        's17SnapChat Business',
        's18NextSosyal Business',
        't1Git Bash',
        't2Python CLI',
        't3NodeJS CLI',
        't4Ollama App',
        't5Pwsh',
        't6PS',
        't7Azure CLI',
        't8WSL',
        't9Docker CLI',
        't10Azd CLI',
        't11GH CLI',
        't12FFmpeg CLI',
        't13Seven Zip CLI',
        't14Process Explorer',
        't15Io Unlocker',
        'u1User Files',
        'u2This PC',
        'u3Control Panel',
        'u7Network and Sharing',
        'v1VS2022Com',
        'v5VS Code',
        'z1Google Account Setup',
        'z2Office365 Account Setup'
    )
    $legacyShortcutNames = @(
        'i7whatsapp',
        't0-git bash',
        't1-python cli',
        't2-nodejs cli',
        't3-ollama app',
        't4-pwsh',
        't5-ps',
        't6-azure cli',
        't7-wsl',
        't9-azd cli',
        't10-gh cli',
        't11-ffmpeg cli',
        't12-7zip cli',
        't13-sysinternals',
        't14-io-unlocker',
        't15-codex cli',
        't16-gemini cli',
        'i0internet',
        'z1google account setup',
        'z2Office365 account setup',
        'c0cmd',
        'a7docker desktop',
        'o0outlook',
        'o1teams',
        'o2word',
        'o3excel',
        'o4power point',
        'o5onenote',
        'i8anydesk',
        'i9windscribe',
        'v5vscode',
        't3OllamaApp',
        't6azure-cli',
        't12SevenZip-cli',
        't15codex-cli',
        't16gemini-cli',
        'a4WhatsApp Kurumsal',
        'a5WhatsApp Bireysel',
        'b1GarantiBank Kurumsal',
        'b2GarantiBank Bireysel',
        'b3QnbBank Kurumsal',
        'b4QnbBank Bireysel',
        'b5AktifBank Kurumsal',
        'b6AktifBank Bireysel',
        'b7ZiraatBank Kurumsal',
        'b8ZiraatBank Bireysel',
        'i1Internet Kurumsal',
        'i2Internet Bireysel',
        'm1Dijital Vergi Dairesi',
        'q4EDevlet',
        'q6AJet Uçak',
        'q7TCDD Tren',
        'q8OBilet Otobüs',
        'r13Çiçek Sepeti Kurumsal',
        'r14Çiçek Sepeti Bireysel',
        'r17PTT AVM Kurumsal',
        'r18PTT AVM Bireysel',
        's18Next Sosyal'
    )
    $expectedFragments = @(
        'SELECTED_COMPANY_NAME is required for the Windows business public desktop shortcut flow',
        'SELECTED_EMPLOYEE_EMAIL_ADDRESS is required for the Windows public desktop shortcut flow',
        'SELECTED_EMPLOYEE_FULL_NAME is required for the Windows public desktop shortcut flow',
        'Get-EmployeeEmailBaseName',
        'ConvertTo-LowerInvariantText',
        'ConvertTo-TitleCaseShortcutText',
        '$companyChromeProfileDirectory = ConvertTo-LowerInvariantText -Value $companyName',
        '$employeeEmailBaseName = ConvertTo-LowerInvariantText -Value $employeeEmailBaseName',
        'Resolve-OptionalShortcutUrl',
        'Get-ChromeArgsPrefix',
        'Get-EdgeArgsPrefix',
        'Get-ChromeProfileDirectoryForShortcut -ProfileKind $ProfileKind',
        'New-StoreAppShortcutSpec',
        'New-ChromeShortcutSpec',
        'ConvertTo-ManagedShortcutLauncherSpec',
        'Get-ClagnosShortcutLauncherFilePath',
        'Get-ClagnosShortcutLauncherInvocationArguments',
        'shortcut-launcher-enabled:',
        'clagnos-shortcut-launcher.psm1',
        'Get-NormalizedShortcutNameKey',
        'Get-ShortcutUrlFromArguments',
        'Test-ShortcutDetailsMatchManagedSpec',
        'https://chatgpt.com',
        'https://www.google.com',
        'https://web.whatsapp.com',
        'chrome://settings/syncSetup',
        'https://portal.office.com',
        'https://www.linkedin.com/company/',
        'https://www.linkedin.com/',
        'https://www.youtube.com/',
        'https://www.youtube.com/',
        'https://github.com/',
        'https://github.com/',
        'https://www.tiktok.com/',
        'https://instagram.com/',
        'https://instagram.com/',
        'https://www.facebook.com/',
        'https://www.facebook.com/',
        'https://x.com/',
        'https://x.com/',
        '$defaultBusinessWebRootUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $companyWebAddress -FallbackUrl ''https://www.example.com''',
        '$companyWebRootUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutWebBusinessHomeUrl -FallbackUrl $defaultBusinessWebRootUrl',
        '$companyBlogUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutWebBusinessBlogUrl -FallbackUrl ($companyWebRootUrl + ''/blog'')',
        '__SELECTED_COMPANY_WEB_ADDRESS__',
        '__SELECTED_COMPANY_EMAIL_ADDRESS__',
        '__WIN_PUBLIC_SHORTCUT_SOCIAL_BUSINESS_LINKEDIN_URL__',
        '__WIN_PUBLIC_SHORTCUT_SOCIAL_PERSONAL_X_URL__',
        '__WIN_PUBLIC_SHORTCUT_WEB_BUSINESS_HOME_URL__',
        'https://sube.garantibbva.com.tr/isube/login/login/passwordentrycorporate-tr',
        'https://sube.garantibbva.com.tr/isube/login/login/passwordentrypersonal-tr',
        'https://internetsubesi.qnb.com.tr/Login/LoginPage.aspx?FromDK=true',
        'https://internetsubesi.qnb.com.tr/Login/LoginPage.aspx',
        'https://kurumsal.aktifbank.com.tr/default.aspx?lang=tr-TR',
        'https://online.aktifbank.com.tr/default.aspx?lang=tr-TR',
        'https://kurumsal.ziraatbank.com.tr/Transactions/Login/FirstLogin.aspx?customertype=crp',
        'https://bireysel.ziraatbank.com.tr/Transactions/Login/FirstLogin.aspx',
        '$socialBusinessSnapchatUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessSnapchatUrl -FallbackUrl ''https://www.snapchat.com/''',
        '$socialBusinessNextSosyalUrl = Resolve-OptionalShortcutUrl -ConfiguredValue $shortcutSocialBusinessNextSosyalUrl -FallbackUrl ''https://sosyal.teknofest.app/''',
        'https://dijital.gib.gov.tr/portal/login',
        'https://www.eksisozluk.com',
        'https://secure.sahibinden.com/giris',
        'https://www.sahibinden.com',
        'https://www.letgo.com',
        'https://partner.trendyol.com',
        'https://www.trendyol.com/uyelik',
        'https://sellercentral.amazon.com.tr',
        'https://www.amazon.com.tr/ap/signin',
        'https://merchant.hepsiburada.com',
        'https://giris.hepsiburada.com',
        'https://so.n11.com',
        'https://www.n11.com/giris-yap',
        'https://seller.ciceksepeti.com/giris',
        'https://www.ciceksepeti.com/uye-girisi',
        'https://isortagim.pazarama.com',
        'https://account.pazarama.com/giris',
        'https://merchant.pttavm.com/magaza-giris',
        'https://www.pttavm.com',
        'https://seller.ozon.ru/app/registration/signin?locale=en',
        'https://www-ozon-ru.translate.goog/?_x_tr_sl=ru&_x_tr_tl=en&_x_tr_hl=en&_x_tr_hist=true',
        'https://panel.getircarsi.com/login',
        'https://getir.com',
        'Resolve-AppPackageExecutablePath',
        'Resolve-StoreAppId',
        'Resolve-VsWhereExe',
        'Resolve-Vs2022CommunityExecutablePath',
        'Resolve-JawsRootFromRegistry',
        'Resolve-JawsExecutablePath',
        'Add-StoreManagedShortcutSpec',
        'Read-ClagnosStoreInstallState',
        'ms-windows-store://pdp/?ProductId=9MSW46LTDWGF',
        'Resolve-EmbeddedShortcutCommandPath',
        'public-shortcut-skip:',
        'shell:AppsFolder\',
        'OpenAI.Codex',
        'WhatsApp.Root.exe',
        '9NKSQGP7F2NH',
        'Resolve-AppPackageExecutablePath -NameFragment "whatsapp"',
        '5319275A.WhatsAppDesktop',
        'iCloudHome.exe',
        '$publicEdgeUserDataDir = "C:\Users\Public\AppData\Local\Microsoft\msedge\UserData"',
        '$edgeBusinessArgs = Get-EdgeArgsPrefix -ProfileKind ''business'' -Variant ''remote''',
        '/c start outlook.exe /select "outlook:\\{0}\\Inbox"',
        'https://developer.apple.com/account',
        'https://play.google.com/console/signin',
        'https://aka.ms/submitwindowsapp',
        'https://portal.azure.com',
        'C:\Windows\System32\notepad.exe',
        'https://accounts.spotify.com/en/login?continue=https%3A%2F%2Fopen.spotify.com',
        'https://www.netflix.com/tr-en/login',
        'https://www.turkiye.gov.tr',
        'https://account.apple.com/sign-in',
        'https://ajet.com',
        'https://ebilet.tcddtasimacilik.gov.tr',
        'https://www.obilet.com/?giris',
        'TaskKill -im "ollama app.exe"',
        '/k cd /d %UserProfile% & docker',
        '%UserProfile%\AppData\Roaming\npm\copilot.cmd --screen-reader --yolo --no-ask-user --model claude-haiku-4.5',
        'C:\ProgramData\chocolatey\bin\7z.exe',
        '-c model_reasoning_summary=detailed -c hide_agent_reasoning=false -c show_raw_agent_reasoning=true -c tui.animations=true --enable multi_agent --enable fast_mode --yolo -s danger-full-access --cd "%UserProfile%" --search',
        '--screen-reader --yolo',
        'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe',
        'Microsoft.VisualStudio.Product.Community',
        'HKLM:\Software\Freedom Scientific\JAWS\2025',
        'HKLM:\Software\WOW6432Node\Freedom Scientific\JAWS\2025',
        'Set-ShortcutRunAsAdministratorFlag',
        'Get-ShortcutRunAsAdministratorFlag',
        'WindowStyle',
        'RunAsAdmin = [bool]$RunAsAdmin',
        'ShowCmd = [int]$ShowCmd',
        'New-ChromeShortcutSpec -Name "z1Google Account Setup" -Url "chrome://settings/syncSetup"',
        'Resolve-CommandPath -CommandName "control.exe"',
        'Microsoft.NetworkAndSharingCenter',
        'function Clear-DesktopEntries',
        'user-desktop-entry-removed:',
        '("C:\Users\{0}\Desktop" -f $managerUser)',
        '("C:\Users\{0}\Desktop" -f $assistantUser)',
        '"C:\Users\Default\Desktop"',
        '%UserProfile%',
        '$publicChromeUserDataDir = "C:\Users\Public\AppData\Local\Google\Chrome\UserData"',
        '--user-data-dir="{0}"',
        '--profile-directory="{1}"',
        'return [string]$employeeEmailBaseName',
        'return [string]$companyChromeProfileDirectory',
        'public-desktop-inspect-skip:',
        'public-desktop-removed: {0} => managed-by {1}',
        'function Test-ShortcutRemovalLockedMessage',
        'function Test-ExistingPublicShortcutMatchesManagedSpec',
        'function Remove-ExistingPublicShortcut',
        'public-desktop-remove-retry: {0} => attempt {1}/{2}',
        'public-desktop-retained: {0} => locked-managed-shortcut',
        'public-shortcut-path-retained: {0} => existing-managed-shortcut',
        'CleanupAliases = @(',
        'CleanupMatchTargetOnly = [bool]$CleanupMatchTargetOnly',
        'CleanupAliasMatchByNameOnly = [bool]$CleanupAliasMatchByNameOnly',
        '__VM_ADMIN_PASS__',
        '__ASSISTANT_PASS__',
        'clagnos-interactive-session-helper.ps1',
        'Ensure-ManagedUserStoreAppRegistration',
        'Invoke-ClagnosUserAppxRegistrationRepair',
        'public-shortcut-user-appid-repair:',
        '%UserProfile%\AppData\Roaming\npm\codex.cmd',
        '%UserProfile%\AppData\Roaming\npm\gemini.cmd',
        '%LocalAppData%\Microsoft\OneDrive\OneDrive.exe'
    )

    foreach ($shortcutName in @($expectedShortcutNames | Where-Object { @($generatedShortcutNames) -notcontains [string]$_ })) {
        Assert-True -Condition (($shortcutTaskScript.IndexOf([string]$shortcutName, [System.StringComparison]::Ordinal)) -ge 0) -Message ("Shortcut task must create '{0}'." -f $shortcutName)
        Assert-True -Condition (($healthTaskScript.IndexOf([string]$shortcutName, [System.StringComparison]::Ordinal)) -ge 0) -Message ("Health snapshot must inventory '{0}'." -f $shortcutName)
    }

    Assert-True -Condition (($shortcutTaskScript.IndexOf('$q1EksiSozlukName =', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must build the Turkish EkşiSözlük label from Unicode code points.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('$r13CicekSepetiBusinessName =', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must build the Turkish ÇiçekSepeti business label from Unicode code points.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('$r14CicekSepetiPersonalName =', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must build the Turkish ÇiçekSepeti personal label from Unicode code points.'
    Assert-True -Condition (($healthTaskScript.IndexOf('$cicekSepetiLabel =', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must derive the Turkish ÇiçekSepeti label from Unicode code points.'
    Assert-True -Condition (($healthTaskScript.IndexOf('$eksiSozlukLabel =', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must derive the Turkish EkşiSözlük label from Unicode code points.'

    foreach ($legacyShortcutName in @($legacyShortcutNames)) {
        Assert-True -Condition (($shortcutTaskScript.IndexOf([string]$legacyShortcutName, [System.StringComparison]::Ordinal)) -lt 0) -Message ("Shortcut task must not keep legacy shortcut name '{0}'." -f $legacyShortcutName)
        Assert-True -Condition (($healthTaskScript.IndexOf([string]$legacyShortcutName, [System.StringComparison]::Ordinal)) -lt 0) -Message ("Health snapshot must not keep legacy shortcut name '{0}'." -f $legacyShortcutName)
    }

    Assert-True -Condition (($shortcutTaskScript.IndexOf('-Name "i1Internet"', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Shortcut task must not keep the old i1Internet shortcut label.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('t10AZD CLI', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Shortcut task must not keep the old t10AZD CLI shortcut label.'
    Assert-True -Condition (($healthTaskScript.IndexOf('t10AZD CLI', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Health snapshot must not keep the old t10AZD CLI shortcut label.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Test-PersonalChromeShortcutName', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Shortcut task must not route personal Chrome profiles by the old label-text helper.'
    foreach ($legacyBrowserArgument in @('--disable-extensions', '--disable-default-apps', '--remote-debugging-address=127.0.0.1', '--remote-debugging-port=9222', '--no-first-run', '--no-default-browser-check')) {
        Assert-True -Condition (($shortcutTaskScript.IndexOf([string]$legacyBrowserArgument, [System.StringComparison]::Ordinal)) -lt 0) -Message ("Shortcut task must not keep the retired browser launcher arg '{0}'." -f [string]$legacyBrowserArgument)
        Assert-True -Condition (($healthTaskScript.IndexOf([string]$legacyBrowserArgument, [System.StringComparison]::Ordinal)) -lt 0) -Message ("Health snapshot must not keep the retired browser launcher arg '{0}'." -f [string]$legacyBrowserArgument)
    }

    foreach ($fragment in @($expectedFragments)) {
        Assert-True -Condition (($shortcutTaskScript.IndexOf([string]$fragment, [System.StringComparison]::Ordinal)) -ge 0) -Message ("Shortcut task must include fragment '{0}'." -f $fragment)
    }
    Assert-True -Condition (-not ($shortcutTaskJsonText -match '"appState"\s*:')) -Message 'Public desktop shortcut task must stay on-the-fly and must not own a task-local app-state snapshot/replay contract.'
    Assert-True -Condition ($shortcutTaskScript -like '*RunAsAdmin*') -Message 'Shortcut task must model RunAsAdmin in the manifest.'
    Assert-True -Condition ($shortcutTaskScript -like '*ShowCmd*') -Message 'Shortcut task must model ShowCmd in the manifest.'
    Assert-True -Condition ($healthTaskScript -like '*hotkey =>*') -Message 'Health snapshot must read back shortcut hotkeys.'
    Assert-True -Condition ($healthTaskScript -like '*start-in =>*') -Message 'Health snapshot must read back shortcut working directories.'
    Assert-True -Condition ($healthTaskScript -like '*show =>*') -Message 'Health snapshot must read back shortcut show commands.'
    Assert-True -Condition ($healthTaskScript -like '*run-as-admin =>*') -Message 'Health snapshot must read back shortcut admin flags.'
    Assert-True -Condition ($healthTaskScript -like '*effective-target =>*') -Message 'Health snapshot must read back managed launcher effective targets.'
    Assert-True -Condition ($healthTaskScript -like '*effective-args =>*') -Message 'Health snapshot must read back managed launcher effective arguments.'
    foreach ($fragment in @(
        'STORE INSTALL STATE:',
        '120-install-codex-application',
        '119-install-whatsapp-application',
        '118-install-be-my-eyes-application',
        '122-install-icloud-application'
    )) {
        Assert-True -Condition ($healthTaskScript -like ('*' + [string]$fragment + '*')) -Message ("Health snapshot must include Store install state fragment '{0}'." -f [string]$fragment)
    }
    Assert-True -Condition ($healthTaskScript -like '*unmanaged-public-shortcut-count=*') -Message 'Health snapshot must inventory unmanaged Public Desktop shortcuts.'
    Assert-True -Condition (($healthTaskScript.IndexOf("Write-ShortcutReadback -Label 'unmanaged-public-shortcut'", [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must read back unmanaged Public Desktop shortcut details.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Where-Object { $managedShortcutNames -contains [System.IO.Path]::GetFileNameWithoutExtension([string]$_.Name) }', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Shortcut task must not keep the old exact-name-only Public Desktop cleanup logic.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('function Find-ManagedShortcutSpecByName', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must provide a direct-name shortcut spec matcher for Public Desktop cleanup.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('function Find-ManagedShortcutSpecByDetails', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must provide a semantic shortcut spec matcher for Public Desktop cleanup.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('function Test-PublicDesktopAlreadyNormalized', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must provide a no-op fast path when the Public Desktop is already normalized.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('public-desktop-normalized: no changes required', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must log the no-op normalized path explicitly.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Find-ManagedShortcutSpecByDetails -Specs $shortcutSpecs -Details $existingDetails -ShortcutBaseName $shortcutBaseName', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must use semantic duplicate matching for Public Desktop cleanup.'
    Assert-True -Condition (-not ($shortcutTaskScript -match 'public-desktop-inspect-skip:[\s\S]{0,120}\breturn\b')) -Message 'Shortcut task must not exit early after an unmanaged shortcut inspection warning.'
    Assert-True -Condition (-not ($shortcutTaskScript -match 'if\s*\(\$null\s*-eq\s*\$matchedSpec\)\s*\{\s*return\b')) -Message 'Shortcut task must continue past unrelated Public Desktop shortcuts instead of returning from the script.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("Google Chrome", "Chrome")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry explicit Chrome duplicate aliases.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("Microsoft Edge")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry explicit Edge duplicate aliases.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("Visual Studio 2022")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry explicit Visual Studio duplicate aliases.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("AnyDesk")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry explicit AnyDesk duplicate aliases.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("IObit Unlocker")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry an explicit IObit Unlocker duplicate alias.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("NVDA")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry an explicit NVDA duplicate alias.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('@("JAWS")', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must carry an explicit JAWS duplicate alias.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Ctrl+Shift+J', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must assign the JAWS hotkey.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('CleanupAliasMatchByNameOnly $true', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must support explicit alias-only cleanup for installer shortcuts that wrap the managed app target.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('if ([bool]$Spec.AllowMissingTargetPath -and ($validationKind -in @(''app'', ''console'')))', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must treat optional app and console shortcut misses as informational skips.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Write-Host $skipMessage', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must emit informational output for optional unresolved shortcuts.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Write-Warning $skipMessage', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must retain warnings for non-optional unresolved shortcuts.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('unexpected-public-shortcut', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Shortcut task must not keep unexpected Public Desktop cleanup logic.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('if (-not [string]::IsNullOrWhiteSpace([string]$codexAppId))', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must prefer AppsFolder launch for Codex when a Store app id is available.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('if (-not [string]::IsNullOrWhiteSpace([string]$whatsAppBusinessAppId))', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must prefer AppsFolder launch for WhatsApp when a Store app id is available.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('if (-not [string]::IsNullOrWhiteSpace([string]$iCloudAppId))', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must prefer AppsFolder launch for iCloud when a Store app id is available.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf("Add-StoreManagedShortcutSpec -List `$shortcutSpecs -ShortcutName 'o2Teams' -TaskName '114-install-teams-application'", [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must resolve Teams through the shared Store-managed shortcut helper.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Write-Host ("public-shortcut-skip: {0} => store state={1}; {2}"', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must log non-launch-ready Store state skips as informational output.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('Write-Warning ("public-shortcut-skip: {0} => store state={1}; {2}"', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Shortcut task must not duplicate Store task warnings for non-installed Store state records.'
    Assert-True -Condition (($shortcutTaskScript.IndexOf('public-shortcut-recover: {0} => store state={1}; live launch target resolved, continuing with shortcut creation.', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Shortcut task must recover from stale Store state when a live AppsFolder or executable target is now resolvable.'
    Assert-True -Condition (($healthTaskScript.IndexOf("Write-DesktopState -Label 'assistant'", [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report assistant desktop state.'
    Assert-True -Condition (($healthTaskScript.IndexOf('Write-DesktopArtifactScan', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must scan desktop.ini and Thumbs.db artifacts.'
    Assert-True -Condition (($healthTaskScript.IndexOf('MS EDGE SHORTCUT CONTRACT:', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the dedicated MS Edge shortcut contract.'
    Assert-True -Condition (($healthTaskScript.IndexOf('edge-shortcut-launcher =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the MS Edge launcher path when a managed launcher is used.'
    Assert-True -Condition (($healthTaskScript.IndexOf('edge-shortcut-args-match =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the MS Edge shortcut argument match state.'
    Assert-True -Condition (($healthTaskScript.IndexOf('edge-shortcut-user-data-root =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the MS Edge shared user-data root.'
    Assert-True -Condition (($healthTaskScript.IndexOf('CHROME SHORTCUT CONTRACT:', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the dedicated Chrome shortcut contract.'
    Assert-True -Condition (($healthTaskScript.IndexOf('chrome-shortcut-args-match =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the Chrome shortcut argument match state.'
    Assert-True -Condition (($healthTaskScript.IndexOf('chrome-shortcut-user-data-root =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the Chrome shared user-data root.'
    Assert-True -Condition (($healthTaskScript.IndexOf('CHROME SETUP SHORTCUT CONTRACT:', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the dedicated Chrome setup shortcut contract.'
    Assert-True -Condition (($healthTaskScript.IndexOf('chrome-setup-shortcut-args-match =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report the Chrome setup shortcut argument match state.'
    Assert-True -Condition (($healthTaskScript.IndexOf('BROWSER USER DATA STATUS:', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report browser user-data presence for managed users.'
    Assert-True -Condition (($healthTaskScript.IndexOf('browser-user-data => {0} => {1} =>', [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must emit the browser user-data readback format.'
    Assert-True -Condition (($healthTaskScript.IndexOf("Write-BrowserUserDataStatus -BrowserName 'chrome' -UserName $managerUser", [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report manager Chrome user-data status.'
    Assert-True -Condition (($healthTaskScript.IndexOf("Write-BrowserUserDataStatus -BrowserName 'edge' -UserName $assistantUser", [System.StringComparison]::Ordinal)) -ge 0) -Message 'Health snapshot must report assistant Edge user-data status.'
}

Invoke-Test -Name "Windows WSL and health contracts expose Docker prerequisite signals" -Action {
    $wslTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '113-install-wsl-feature'
    $healthTaskPath = Get-RepoSummaryReadbackScriptPath -Platform windows
    $wslTaskText = [string](Get-Content -LiteralPath $wslTaskPath -Raw)
    $healthTaskText = [string](Get-Content -LiteralPath $healthTaskPath -Raw)
    $wslManifest = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Join-Path (Split-Path $wslTaskPath -Parent) 'package.json') -Raw) -ErrorAction Stop
    Assert-True -Condition ([int]$wslManifest.timeout -ge 600) -Message 'WSL feature installation must allow enough time for servicing-stack DISM enablement.'
    Assert-True -Condition (@($wslManifest.assets | Where-Object { [string]$_.local -eq '../../../../tools/scripts/clagnos-interactive-session-helper.ps1' -and [string]$_.remote -eq 'C:/Windows/Temp/clagnos-interactive-session-helper.ps1' }).Count -eq 1) -Message 'WSL Store package installation must carry the interactive desktop helper asset.'
    Assert-True -Condition ($wslTaskText -like '*Install-WslAppxThroughInteractiveSession*' -and $wslTaskText -like '*RunAsMode ''interactiveToken''*') -Message 'WSL Store package installation must run in the interactive manager desktop session.'
    Assert-True -Condition ($wslTaskText -like '*wsl.exe --update --web-download*') -Message 'WSL updates must use the non-Store web download path.'

    foreach ($fragment in @(
        'Get-WindowsOptionalFeatureState',
        'function Test-WslReady',
        'Test-WslBootstrapSatisfied',
        'Test-WslBenignBootstrapLine',
        '$wslVersionOutput = @(& wsl.exe --version 2>&1)',
        'if (Test-WslBenignBootstrapLine -Text $lineText)',
        '$previousErrorActionPreference = $ErrorActionPreference',
        '$ErrorActionPreference = ''Continue''',
        '$ErrorActionPreference = $previousErrorActionPreference',
        'Write-WslFeatureState',
        '@(& $Action 2>&1)',
        'wsl-feature-state => Microsoft-Windows-Subsystem-Linux =>',
        'wsl-feature-state => VirtualMachinePlatform =>',
        'wsl --set-default-version 2',
        'wsl-step-ok: default-version-2'
    )) {
        Assert-True -Condition ($wslTaskText -like ('*' + [string]$fragment + '*')) -Message ("WSL task must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'WSL FEATURE STATE:',
        'wsl-feature => Microsoft-Windows-Subsystem-Linux => state=',
        'wsl-feature => VirtualMachinePlatform => state=',
        'OLLAMA HEALTH:',
        'ollama-ls-probe =>',
        'ollama-process-count =>',
        'Wait-OllamaApiReady',
        'docker-wsl-prereq-ready =>',
        'WSL HEALTH:'
    )) {
        Assert-True -Condition ($healthTaskText -like ('*' + [string]$fragment + '*')) -Message ("Health snapshot must include WSL readiness fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "App-state runtime keeps managed VM targeting strict and local-machine targeting explicit" -Action {
    $guestHelperText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-guest.psm1') -Raw)
    $captureHelperText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-capture.ps1') -Raw)
    $localAppStateText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-local.ps1') -Raw)
    $chromeTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\google-chrome\package.json') -Raw)
    $edgeTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\microsoft-edge\package.json') -Raw)
    $copySettingsTaskJsonText = [string](Get-Content -LiteralPath (Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '10005-copy-user-settings') -Raw)
    $dockerTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\docker-desktop\package.json') -Raw)
    $ollamaTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\ollama\package.json') -Raw)
    $azdTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\azure-developer-cli\package.json') -Raw)
    $azureCliTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\azure-cli\package.json') -Raw)
    $ghCliTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\github-cli\package.json') -Raw)
    $jawsTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\jaws\package.json') -Raw)
    $whatsAppTaskJsonText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'packages\builtin\windows\whatsapp\package.json') -Raw)
    $sshAssetsText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\ssh\assets.ps1') -Raw)
    $sshProcessText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\tasks\ssh\process.ps1') -Raw)
    $auditScriptPath = Join-Path $RepoRoot 'tools\scripts\app-state-audit.ps1'
    $normalizeScriptPath = Join-Path $RepoRoot 'tools\scripts\normalize-app-state-zips.ps1'
    $auditScriptText = [string](Get-Content -LiteralPath $auditScriptPath -Raw)

    Assert-True -Condition (-not ($guestHelperText -like '*C:\Users\Default*')) -Message 'Windows app-state guest helpers must not target the default profile.'
    Assert-True -Condition (-not ($guestHelperText -like '*Get-ChildItem -LiteralPath ''C:\Users'' -Directory*')) -Message 'Windows app-state guest helpers must not enumerate arbitrary local user profiles.'
    Assert-True -Condition (-not ($captureHelperText -like '*''/etc/skel''*')) -Message 'Linux app-state capture must not target /etc/skel as a default replay profile.'
    Assert-True -Condition (-not ($captureHelperText -like '*glob.glob(''/home/*'')*')) -Message 'Linux app-state capture must not enumerate arbitrary /home/* users for replay targeting.'
    Assert-True -Condition ($captureHelperText -like '*Get-ClagnosAllowedAppStateProfileLabels*') -Message 'Shared app-state capture must keep one explicit allowlist for replayable profile targets.'
    Assert-True -Condition ($guestHelperText -like '*$ProfileTargets = @()*') -Message 'Windows app-state guest helpers must accept explicit local profile target descriptors.'
    Assert-True -Condition ($guestHelperText -like '*Get-ClagnosTaskAppStateReplayOperations*') -Message 'Windows app-state guest helpers must materialize restore operations before replay.'
    Assert-True -Condition ($guestHelperText -like '*Test-ClagnosAppStateProfileRegistryReplayAvailable*') -Message 'Windows app-state guest helpers must probe profile hive availability before scheduling user-registry replay.'
    Assert-True -Condition ($guestHelperText -like '*app-state-user-registry-skip => {0} => no-hive-file*') -Message 'Windows app-state guest helpers must skip user-registry replay cleanly when the target profile has no hive file.'
    Assert-True -Condition ($guestHelperText -like '*Backup-ClagnosTaskAppStateOperations*') -Message 'Windows app-state guest helpers must back up touched targets before replay.'
    Assert-True -Condition ($guestHelperText -like '*Invoke-ClagnosTaskAppStateRollback*') -Message 'Windows app-state guest helpers must support rollback after restore verification failures.'
    Assert-True -Condition ($guestHelperText -like '*Get-ClagnosTaskAppStateManagedProcessNames*') -Message 'Windows app-state guest helpers must map browser replay tasks to managed process names.'
    Assert-True -Condition ($guestHelperText -like '*Invoke-ClagnosTaskAppStateCapturePreflight*') -Message 'Windows app-state guest helpers must preflight capture before saving browser payloads.'
    Assert-True -Condition ($guestHelperText -like '*Invoke-ClagnosTaskAppStateReplayPreflight*') -Message 'Windows app-state guest helpers must preflight replay before restoring browser payloads.'
    Assert-True -Condition ($guestHelperText -like '*chrome*') -Message 'Windows app-state guest helpers must include Chrome process preflight handling.'
    Assert-True -Condition ($guestHelperText -like '*msedge*') -Message 'Windows app-state guest helpers must include Edge process preflight handling.'
    Assert-True -Condition ($guestHelperText -like '*app-state-machine-registry-import-skip*') -Message 'Windows app-state guest helpers must downgrade non-fatal machine registry import failures to info skips.'
    Assert-True -Condition ($guestHelperText -like '*app-state-user-registry-import-skip*') -Message 'Windows app-state guest helpers must downgrade non-fatal user registry import failures to info skips.'
    Assert-True -Condition ($guestHelperText -like '*SkippedCount*') -Message 'Windows app-state guest helpers must report skipped replay/rollback items explicitly.'
    Assert-True -Condition ($guestHelperText -like '*app-state done => task=*') -Message 'Windows app-state guest helpers must log restore verification completion in the compact success format.'
    Assert-True -Condition ($guestHelperText -like '*app-state rollback => task=*') -Message 'Windows app-state guest helpers must log rollback completion in the compact failure format.'
    Assert-True -Condition ($captureHelperText -like '*Copy-ClagnosAssetToVm*') -Message 'Shared app-state capture must upload capture plans over SSH.'
    Assert-True -Condition (-not ($captureHelperText -like '*plan_b64*')) -Message 'Shared app-state capture must not embed capture plans as base64 blobs.'
    Assert-True -Condition (-not ($captureHelperText -like '*import base64*')) -Message 'Shared app-state capture must not keep the retired base64 decode helper path.'
    Assert-True -Condition ($sshAssetsText -like '*Get-ClagnosPscpExecutablePath*') -Message 'Windows SSH asset copy must resolve pscp.exe for the primary Windows SCP transport.'
    Assert-True -Condition ($sshAssetsText -like '*Get-ClagnosWindowsScpHostKeyArguments*') -Message 'Windows SSH asset copy must resolve trusted SCP host key fingerprints dynamically.'
    Assert-True -Condition ($sshAssetsText -like '*Try-Get-ClagnosWindowsScpHostKeyArguments*') -Message 'Windows SSH asset copy must expose a non-throwing SCP host-key resolver for pyssh fallback paths.'
    Assert-True -Condition ($sshAssetsText -like '*Resolve-ClagnosWindowsScpHostKeyArguments*') -Message 'Windows SSH asset copy must resolve SCP host-key arguments without emitting fallback transport noise.'
    Assert-True -Condition ($sshAssetsText -like '*ssh-keyscan.exe*') -Message 'Windows SCP transport must use ssh-keyscan.exe to discover the current VM host keys.'
    Assert-True -Condition ($sshAssetsText -like '*ssh-keygen.exe*') -Message 'Windows SCP transport must use ssh-keygen.exe to derive PuTTY-compatible host key fingerprints.'
    Assert-True -Condition ($sshAssetsText -like '*mode=windows-scp*') -Message 'Windows SSH asset copy logs must identify the SCP transport mode.'
    Assert-True -Condition ($sshAssetsText -like '*-pwfile*') -Message 'Windows SCP transport must pass the password through a temp pwfile instead of the process command line.'
    Assert-True -Condition ($sshAssetsText -like '*-scp*') -Message 'Windows SCP transport must force the SCP protocol on Windows targets.'
    Assert-True -Condition ($sshAssetsText -like '*pscp fetch asset <-*') -Message 'Windows SSH asset fetch must also use SCP on Windows targets.'
    Assert-True -Condition ($sshAssetsText -like '*Task asset copy fallback: pyssh windows copy ->*') -Message 'Windows SSH asset copy must log an explicit pyssh fallback when SCP host-key resolution cannot be established.'
    Assert-True -Condition ($sshAssetsText -like '*Task asset fetch fallback: pyssh windows fetch <-*') -Message 'Windows SSH asset fetch must log an explicit pyssh fallback when SCP host-key resolution cannot be established.'
    Assert-True -Condition ($sshProcessText -like '*SkipPythonBytecodeFlag*') -Message 'Shared SSH process helpers must let non-Python transports opt out of the Python-specific -B prefix.'
    Assert-True -Condition ($localAppStateText -like '*Resolve-ClagnosLocalAppStateProfileTargets*') -Message 'Local app-state helpers must resolve explicit Windows profile targets.'
    Assert-True -Condition ($localAppStateText -like '*restore-journal.json*') -Message 'Local app-state helpers must write a restore journal.'
    Assert-True -Condition ($localAppStateText -like '*verify-report.json*') -Message 'Local app-state helpers must write a verify report.'
    Assert-True -Condition ($localAppStateText -like '*Get-ClagnosTaskAppStateBackupRootDirectoryPath*') -Message 'Local app-state helpers must resolve task-adjacent backup-app-states roots.'
    Assert-True -Condition ($localAppStateText -like '*rolled-back*') -Message 'Local app-state helpers must mark rollback outcomes in the restore journal.'
    Assert-True -Condition (-not ($dockerTaskJsonText -like '*"appState"*')) -Message 'Docker Desktop must not replay source-machine daemon, context, or registry-credential state.'
    Assert-True -Condition (-not ($chromeTaskJsonText -like '*"appState"*')) -Message 'Chrome must not copy authenticated browser profiles, cookies, history, or local-state encryption keys.'
    Assert-True -Condition (-not ($edgeTaskJsonText -like '*"appState"*')) -Message 'Edge must not copy authenticated browser profiles, cookies, history, or local-state encryption keys.'
    Assert-True -Condition (-not ($copySettingsTaskJsonText -like '*"appState"*')) -Message '10005-copy-user-settings must stay out of task-local app-state snapshot and restore.'
    Assert-True -Condition (Test-Path -LiteralPath (Get-RepoSummaryReadbackScriptPath -Platform windows)) -Message 'Windows vm-summary readback script must exist after removing the health task.'
    Assert-True -Condition ($ollamaTaskJsonText -like '*AppData\\Local\\Ollama\\config.json*') -Message 'Task-local Ollama capture specs must keep the local config.json path.'
    Assert-True -Condition ($ollamaTaskJsonText -like '*AppData\\Roaming\\Ollama\\config.json*') -Message 'Task-local Ollama capture specs must keep the roaming config.json path.'
    Assert-True -Condition ($ollamaTaskJsonText -like '*AppData\\Roaming\\ollama app.exe\\config.json*') -Message 'Task-local Ollama capture specs must keep the shell-host config.json path.'
    Assert-True -Condition (-not ($ollamaTaskJsonText -like '*AppData\\Local\\Ollama\"*')) -Message 'Task-local Ollama capture specs must not keep the broad AppData\\Local\\Ollama directory.'
    Assert-True -Condition (-not ($ollamaTaskJsonText -like '*updates_v2*')) -Message 'Task-local Ollama capture specs must not mention installer update payloads after narrowing to config files.'
    Assert-True -Condition (-not ($ollamaTaskJsonText -like '*EBWebView*')) -Message 'Task-local Ollama capture specs must not mention embedded WebView runtime payloads after narrowing to config files.'
    Assert-True -Condition ($azdTaskJsonText -like '*".azd\\config.json*' -and -not ($azdTaskJsonText -like '*auth\\*')) -Message 'Azure Developer CLI state must be limited to portable configuration and exclude authentication caches.'
    Assert-True -Condition ($azureCliTaskJsonText -like '*".azure\\config*' -and -not ($azureCliTaskJsonText -like '*azureProfile.json*')) -Message 'Azure CLI state must retain only its settings file and exclude user subscription/authentication state.'
    Assert-True -Condition (-not ($ghCliTaskJsonText -like '*AppData\Local\GitHub CLI*')) -Message 'Task-local GitHub CLI capture specs must not keep the heavy local cache tree.'
    Assert-True -Condition (-not ($whatsAppTaskJsonText -like '*"appState"*')) -Message 'WhatsApp must not carry account credentials, chat history, or media state between VCs.'
    Assert-True -Condition ($jawsTaskJsonText -like '*DEFAULT.JCF*' -and $jawsTaskJsonText -like '*DEFAULT.JDF*' -and -not ($jawsTaskJsonText -like '*HKLM*') -and -not ($jawsTaskJsonText -like '*HKCU*')) -Message 'JAWS portability must retain user preferences and voice profiles without machine licensing registry state.'
    Assert-True -Condition ($ghCliTaskJsonText -like '*GitHub CLI\\config.yml*' -and -not ($ghCliTaskJsonText -like '*hosts.yml*')) -Message 'GitHub CLI app-state must retain UI defaults but not authentication hosts or tokens.'
    Assert-True -Condition ($localAppStateText -like '*Convert-ClagnosTaskAppStateZipToPortableProfilePayload*') -Message 'Local app-state save must support portable profile payload normalization for task-owned zips.'
    Assert-True -Condition ($localAppStateText -like '*Convert-ClagnosTaskCapturePlanToPortableProfileSourcePlan*') -Message 'Local app-state save must relax profile-target filtering when capturing portable payloads from the operator machine.'
    Assert-True -Condition ($localAppStateText -like '*$effectiveCapturePlan = Convert-ClagnosTaskCapturePlanToPortableProfileSourcePlan*') -Message 'Local app-state save must apply the portable capture-plan rewrite before local capture.'
    Assert-True -Condition ($localAppStateText -like '*Test-ClagnosTaskCanonicalManagerProfilePayload*') -Message 'Local app-state save must recognize profile-generic task payloads that should normalize to manager.'
    Assert-True -Condition (Test-Path -LiteralPath $auditScriptPath) -Message 'The manual app-state audit helper must exist under tools/scripts.'
    Assert-True -Condition ($auditScriptText -like '*foreign-targets*') -Message 'The manual app-state audit helper must report foreign profile targets when present.'
    Assert-True -Condition ($auditScriptText -like '*foreign-source-users*') -Message 'The manual app-state audit helper must report foreign source profile tokens when present.'
    Assert-True -Condition (Test-Path -LiteralPath $normalizeScriptPath) -Message 'The repo must ship a dedicated app-state normalization helper under tools/scripts.'
    Assert-True -Condition ((Get-Content -LiteralPath $normalizeScriptPath -Raw) -like '*foreign-users:*') -Message 'The app-state normalization helper must summarize normalized foreign profile tokens.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'tools\trim-browser-app-state-zips.ps1'))) -Message 'The repo must not keep the retired browser app-state trim helper.'
}

Invoke-Test -Name "Portable app-state normalization rewrites local user markers to manager" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-portable-payload-smoke-' + [Guid]::NewGuid().ToString('N'))
    $sourceSettingsRoot = Join-Path $tempRoot 'payload\profile-directories\sourceuser\AppData_Roaming_Freedom_Scientific_JAWS_2025_Settings'
    $sourceRegistryRoot = Join-Path $tempRoot 'payload\registry\user\sourceuser'
    $manifestPath = Join-Path $tempRoot 'app-state.manifest.json'
    $zipPath = Join-Path $tempRoot 'portable-test.zip'
    $expandedRoot = Join-Path $tempRoot 'expanded'

    try {
        New-Item -Path $sourceSettingsRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $sourceRegistryRoot -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $sourceSettingsRoot 'DEFAULT.JCF') -Value 'sample-settings' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $sourceRegistryRoot 'HKCU_Software_Freedom_Scientific.reg') -Value @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\Freedom Scientific\JAWS\2025\Settings\Scripts]
"File1"="C:\\Users\\sourceuser\\AppData\\Roaming\\Freedom Scientific\\JAWS\\2025\\Settings\\enu\\default.JKM"
"@ -Encoding Unicode

        $manifest = [ordered]@{
            version = 3
            taskName = 'portable-test'
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @(
                [ordered]@{
                    sourcePath = 'payload\profile-directories\sourceuser\AppData_Roaming_Freedom_Scientific_JAWS_2025_Settings'
                    relativeDestinationPath = 'AppData\Roaming\Freedom Scientific\JAWS\2025\Settings'
                    targetProfiles = @('sourceuser')
                }
            )
            profileFiles = @()
            registryImports = @(
                [ordered]@{
                    sourcePath = 'payload\registry\user\sourceuser\HKCU_Software_Freedom_Scientific.reg'
                    scope = 'user'
                    registryPath = 'HKEY_CURRENT_USER\Software\Freedom Scientific'
                    targetProfiles = @('sourceuser')
                }
            )
        }
        Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 12) -Encoding UTF8

        Compress-Archive -LiteralPath @(
            (Join-Path $tempRoot 'payload'),
            $manifestPath
        ) -DestinationPath $zipPath -Force

        Convert-ClagnosTaskAppStateZipToPortableProfilePayload -ZipPath $zipPath -TaskName 'portable-test' -ProfileTargets @(
            [pscustomobject]@{
                Label = 'sourceuser'
                UserName = 'sourceuser'
                ProfilePath = 'C:\Users\sourceuser'
            }
        )

        Expand-Archive -LiteralPath $zipPath -DestinationPath $expandedRoot -Force
        $normalizedManifest = Get-Content -LiteralPath (Join-Path $expandedRoot 'app-state.manifest.json') -Raw | ConvertFrom-Json
        $profileEntry = @($normalizedManifest.profileDirectories)[0]
        $registryEntry = @($normalizedManifest.registryImports)[0]
        $normalizedRegistryText = [string](Get-Content -LiteralPath (Join-Path $expandedRoot 'payload\registry\user\manager\HKCU_Software_Freedom_Scientific.reg') -Raw)

        Assert-True -Condition ($null -ne $profileEntry) -Message 'Portable payload smoke manifest must keep one profile directory entry.'
        Assert-True -Condition ($null -ne $registryEntry) -Message 'Portable payload smoke manifest must keep one user registry entry.'
        Assert-True -Condition ([string]$profileEntry.sourcePath -eq 'payload\profile-directories\manager\AppData_Roaming_Freedom_Scientific_JAWS_2025_Settings') -Message 'Portable payload normalization must rewrite profile source paths to manager.'
        Assert-True -Condition ([string]$registryEntry.sourcePath -eq 'payload\registry\user\manager\HKCU_Software_Freedom_Scientific.reg') -Message 'Portable payload normalization must rewrite user registry source paths to manager.'
        Assert-True -Condition (@($profileEntry.targetProfiles).Count -eq 0) -Message 'Portable payload normalization must clear profile targetProfiles.'
        Assert-True -Condition (@($registryEntry.targetProfiles).Count -eq 0) -Message 'Portable payload normalization must clear user-registry targetProfiles.'
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $expandedRoot 'payload\profile-directories\manager\AppData_Roaming_Freedom_Scientific_JAWS_2025_Settings') -PathType Container) -Message 'Portable payload normalization must rename the profile payload folder to manager.'
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $expandedRoot 'payload\registry\user\manager\HKCU_Software_Freedom_Scientific.reg') -PathType Leaf) -Message 'Portable payload normalization must rename the user registry payload folder to manager.'
        Assert-True -Condition ($normalizedRegistryText -like '*C:\\Users\\manager\\AppData\\Roaming\\Freedom Scientific\\JAWS\\2025\\Settings\\enu\\default.JKM*') -Message 'Portable payload normalization must rewrite user-profile registry paths to manager.'
        Assert-True -Condition (-not ($normalizedRegistryText -like '*C:\\Users\\sourceuser\\AppData\\Roaming\\Freedom Scientific\\JAWS\\2025\\Settings\\enu\\default.JKM*')) -Message 'Portable payload normalization must remove the original local user path from registry exports.'
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "App-state normalization tool merges foreign profile payloads into manager" -Action {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-normalize-tool-' + [Guid]::NewGuid().ToString('N'))
    $taskRoot = Join-Path $tempRepo 'windows\update\117-test'
    $pluginRoot = Join-Path $taskRoot 'app-state'
    $scratchRoot = Join-Path $tempRepo 'scratch'
    $payloadRoot = Join-Path $scratchRoot 'payload'
    $zipPath = Join-Path $pluginRoot 'app-state.zip'
    $normalizeScriptPath = Join-Path $RepoRoot 'tools\scripts\normalize-app-state-zips.ps1'

    try {
        New-Item -Path $pluginRoot -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $payloadRoot 'profile-directories\sourceuser\Settings') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $payloadRoot 'profile-directories\backupuser\Settings') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $payloadRoot 'registry\user\sourceuser') -ItemType Directory -Force | Out-Null
        New-Item -Path (Join-Path $payloadRoot 'registry\user\backupuser') -ItemType Directory -Force | Out-Null

        $sourceUserSharedPath = Join-Path $payloadRoot 'profile-directories\sourceuser\Settings\shared.json'
        $backupUserSharedPath = Join-Path $payloadRoot 'profile-directories\backupuser\Settings\shared.json'
        $sourceUserSizePath = Join-Path $payloadRoot 'profile-directories\sourceuser\Settings\size-first.json'
        $backupUserSizePath = Join-Path $payloadRoot 'profile-directories\backupuser\Settings\size-first.json'
        $sourceUserOnlyPath = Join-Path $payloadRoot 'profile-directories\sourceuser\Settings\only-sourceuser.json'
        $backupUserOnlyPath = Join-Path $payloadRoot 'profile-directories\backupuser\Settings\only-backupuser.json'
        $sourceUserRegistryPath = Join-Path $payloadRoot 'registry\user\sourceuser\HKCU_Software_TestApp.reg'
        $backupUserRegistryPath = Join-Path $payloadRoot 'registry\user\backupuser\HKCU_Software_TestApp.reg'

        Set-Content -LiteralPath $sourceUserSharedPath -Value '{"winner":"newer"}' -Encoding UTF8
        Set-Content -LiteralPath $backupUserSharedPath -Value '{"winner":"older-but-bigger-than-shared"}' -Encoding UTF8
        Set-Content -LiteralPath $sourceUserSizePath -Value '{"winner":"smaller"}' -Encoding UTF8
        Set-Content -LiteralPath $backupUserSizePath -Value '{"winner":"larger-loses-on-time?no-size-wins"}' -Encoding UTF8
        Set-Content -LiteralPath $sourceUserOnlyPath -Value '{"owner":"sourceuser"}' -Encoding UTF8
        Set-Content -LiteralPath $backupUserOnlyPath -Value '{"owner":"backupuser"}' -Encoding UTF8
        Set-Content -LiteralPath $sourceUserRegistryPath -Value @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\TestApp]
"PrimaryProfile"="C:\\Users\\sourceuser\\AppData\\Roaming\\TestApp"
"@ -Encoding Unicode
        Set-Content -LiteralPath $backupUserRegistryPath -Value @"
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\Software\TestApp]
"PrimaryProfile"="C:\\Users\\backupuser\\AppData\\Roaming\\TestApp"
"@ -Encoding Unicode

        $newerTime = [datetime]::SpecifyKind([datetime]'2026-03-16T10:00:00', [System.DateTimeKind]::Utc)
        $olderTime = [datetime]::SpecifyKind([datetime]'2026-03-16T09:00:00', [System.DateTimeKind]::Utc)
        $tieTime = [datetime]::SpecifyKind([datetime]'2026-03-16T08:00:00', [System.DateTimeKind]::Utc)
        (Get-Item -LiteralPath $sourceUserSharedPath).LastWriteTimeUtc = $newerTime
        (Get-Item -LiteralPath $backupUserSharedPath).LastWriteTimeUtc = $olderTime
        (Get-Item -LiteralPath $sourceUserSizePath).LastWriteTimeUtc = $tieTime
        (Get-Item -LiteralPath $backupUserSizePath).LastWriteTimeUtc = $tieTime
        (Get-Item -LiteralPath $sourceUserRegistryPath).LastWriteTimeUtc = $newerTime
        (Get-Item -LiteralPath $backupUserRegistryPath).LastWriteTimeUtc = $olderTime

        $manifest = [ordered]@{
            version = 3
            taskName = '117-test'
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @(
                [ordered]@{
                    sourcePath = 'payload\profile-directories\sourceuser\Settings'
                    relativeDestinationPath = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\Settings'
                    targetProfiles = @('sourceuser')
                },
                [ordered]@{
                    sourcePath = 'payload\profile-directories\backupuser\Settings'
                    relativeDestinationPath = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\Settings'
                    targetProfiles = @('backupuser')
                }
            )
            profileFiles = @()
            registryImports = @(
                [ordered]@{
                    sourcePath = 'payload\registry\user\sourceuser\HKCU_Software_TestApp.reg'
                    scope = 'user'
                    registryPath = 'HKEY_CURRENT_USER\Software\TestApp'
                    targetProfiles = @('sourceuser')
                },
                [ordered]@{
                    sourcePath = 'payload\registry\user\backupuser\HKCU_Software_TestApp.reg'
                    scope = 'user'
                    registryPath = 'HKEY_CURRENT_USER\Software\TestApp'
                    targetProfiles = @('backupuser')
                }
            )
        }
        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 12) -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $taskRoot 'task.json') -Value (([ordered]@{
            appState = [ordered]@{
                machineDirectories = @()
                machineFiles = @()
                profileDirectories = @(@{ path = 'AppData\Local\Packages\MSTeams_8wekyb3d8bbwe\Settings'; targetProfiles = @() })
                profileFiles = @()
                machineRegistryKeys = @()
                userRegistryKeys = @(@{ path = 'HKCU\Software\TestApp'; targetProfiles = @() })
            }
        }) | ConvertTo-Json -Depth 12) -Encoding UTF8

        Compress-Archive -LiteralPath @(
            (Join-Path $scratchRoot 'app-state.manifest.json'),
            $payloadRoot
        ) -DestinationPath $zipPath -Force

        $reports = & $normalizeScriptPath -RepoRoot $tempRepo -PassThru
        $normalizedReport = @($reports | Where-Object { [string]$_.TaskName -eq '117-test' } | Select-Object -First 1)[0]
        Assert-True -Condition ($null -ne $normalizedReport) -Message 'The normalization tool must report the processed task.'
        Assert-True -Condition ([string]$normalizedReport.Status -eq 'normalized') -Message 'The normalization tool must mark foreign profile payloads as normalized.'
        Assert-True -Condition (((@($normalizedReport.ForeignUsers) | Sort-Object) -join ',') -eq 'backupuser,sourceuser') -Message 'The normalization tool must report the foreign profile tokens it rewrote.'

        $expandedRoot = Join-Path $tempRepo 'expanded'
        Expand-Archive -LiteralPath $zipPath -DestinationPath $expandedRoot -Force
        $normalizedManifest = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath (Join-Path $expandedRoot 'app-state.manifest.json') -Raw))
        $profileEntry = @($normalizedManifest.profileDirectories)[0]
        $registryEntry = @($normalizedManifest.registryImports)[0]
        $managerSettingsRoot = Join-Path $expandedRoot 'payload\profile-directories\manager\Settings'
        $managerRegistryPath = Join-Path $expandedRoot 'payload\registry\user\manager\HKCU_Software_TestApp.reg'
        $normalizedRegistryText = [string](Get-Content -LiteralPath $managerRegistryPath -Raw)

        Assert-True -Condition (@($normalizedManifest.profileDirectories).Count -eq 1) -Message 'The normalization tool must collapse duplicate foreign profile directories into one manager payload.'
        Assert-True -Condition (@($normalizedManifest.registryImports).Count -eq 1) -Message 'The normalization tool must collapse duplicate foreign user-registry payloads into one manager payload.'
        Assert-True -Condition ([string]$profileEntry.sourcePath -eq 'payload\profile-directories\manager\Settings') -Message 'The normalization tool must rewrite profile directory source paths to manager.'
        Assert-True -Condition (@($profileEntry.targetProfiles).Count -eq 0) -Message 'The normalization tool must clear foreign profile targetProfiles after normalization.'
        Assert-True -Condition ([string]$registryEntry.sourcePath -eq 'payload\registry\user\manager\HKCU_Software_TestApp.reg') -Message 'The normalization tool must rewrite registry source paths to manager.'
        Assert-True -Condition (@($registryEntry.targetProfiles).Count -eq 0) -Message 'The normalization tool must clear foreign registry targetProfiles after normalization.'
        Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $managerSettingsRoot 'shared.json') -Raw) -match 'newer') -Message 'The normalization tool must prefer the newer conflicting profile file.'
        Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $managerSettingsRoot 'size-first.json') -Raw) -match 'larger-loses-on-time\?no-size-wins') -Message 'The normalization tool must prefer the larger conflicting profile file when timestamps tie.'
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $managerSettingsRoot 'only-sourceuser.json') -PathType Leaf) -Message 'The normalization tool must keep non-conflicting files from the first foreign profile.'
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $managerSettingsRoot 'only-backupuser.json') -PathType Leaf) -Message 'The normalization tool must keep non-conflicting files from the second foreign profile.'
        Assert-True -Condition ($normalizedRegistryText -like '*C:\\Users\\manager\\AppData\\Roaming\\TestApp*') -Message 'The normalization tool must rewrite embedded registry profile paths to manager.'
        Assert-True -Condition (-not ($normalizedRegistryText -like '*sourceuser*')) -Message 'The normalization tool must remove the first foreign token from registry payloads.'
        Assert-True -Condition (-not ($normalizedRegistryText -like '*backupuser*')) -Message 'The normalization tool must remove the second foreign token from registry payloads.'
        Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $expandedRoot 'payload\profile-directories\sourceuser'))) -Message 'The normalization tool must remove the first superseded foreign profile directory.'
        Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $expandedRoot 'payload\profile-directories\backupuser'))) -Message 'The normalization tool must remove the second superseded foreign profile directory.'
    }
    finally {
        Remove-Item -LiteralPath $tempRepo -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Guest app-state capture resolves wildcard profile paths to concrete destinations" -Action {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-guest-capture-' + [Guid]::NewGuid().ToString('N'))
    $profilePath = Join-Path $tempRoot 'profiles\manager'
    $settingsPath = Join-Path $profilePath 'AppData\Local\Packages\OpenAI.Codex_2p2nqsd0c76g0\Settings'
    $planPath = Join-Path $tempRoot 'capture-plan.json'
    $zipPath = Join-Path $tempRoot 'app-state.zip'
    $modulePath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-guest.psm1'
    $module = $null

    try {
        New-Item -Path $settingsPath -ItemType Directory -Force | Out-Null
        $sourceSettings = [ordered]@{
            theme = 'saved'
            workspace = (Join-Path $profilePath 'Documents')
            apiToken = 'fixture-value'
        }
        Set-Content -LiteralPath (Join-Path $settingsPath 'settings.json') -Value (ConvertTo-Json -InputObject $sourceSettings -Depth 8) -Encoding UTF8

        $plan = [ordered]@{
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @(
                [ordered]@{
                    path = 'AppData\Local\Packages\OpenAI.Codex_*\Settings'
                    targetProfiles = @('manager')
                    excludeNames = @()
                    excludePathPatterns = @()
                    excludeFilePatterns = @()
                }
            )
            profileFiles = @()
            machineRegistryKeys = @()
            userRegistryKeys = @()
        }
        Set-Content -LiteralPath $planPath -Value ($plan | ConvertTo-Json -Depth 8) -Encoding UTF8

        $module = Import-Module -Name $modulePath -Force -PassThru
        $captureResult = Invoke-ClagnosTaskAppStateCapture `
            -TaskName '116-install-codex-application' `
            -PlanPath $planPath `
            -OutputZipPath $zipPath `
            -ManagerUser 'manager' `
            -AssistantUser 'assistant' `
            -ProfileTargets @([pscustomobject]@{ Label = 'manager'; UserName = 'manager'; ProfilePath = $profilePath })

        Assert-True -Condition ([bool]$captureResult.CreatedZip) -Message 'Guest app-state capture must create a zip when wildcard profile content exists.'
        Assert-True -Condition (Test-Path -LiteralPath $zipPath) -Message 'Guest app-state capture must write the output zip.'

        $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
        try {
            $manifestEntry = $archive.Entries | Where-Object { $_.FullName -eq 'app-state.manifest.json' } | Select-Object -First 1
            $reader = New-Object System.IO.StreamReader($manifestEntry.Open())
            try {
                $manifest = $reader.ReadToEnd() | ConvertFrom-Json
            }
            finally {
                $reader.Dispose()
            }
            $payloadEntry = $archive.Entries | Where-Object { ([string]$_.FullName).Replace('\','/') -match 'payload/profile-directories/manager/.+settings\.json$' } | Select-Object -First 1
            Assert-True -Condition ($null -ne $payloadEntry) -Message 'Guest app-state capture must include the selected settings payload.'
            $payloadReader = New-Object System.IO.StreamReader($payloadEntry.Open())
            try { $savedSettings = $payloadReader.ReadToEnd() | ConvertFrom-Json }
            finally { $payloadReader.Dispose() }
        }
        finally {
            $archive.Dispose()
        }

        $capturedEntry = @($manifest.profileDirectories | Where-Object { @($_.targetProfiles) -contains 'manager' } | Select-Object -First 1)
        Assert-True -Condition (@($capturedEntry).Count -eq 1) -Message 'Guest app-state capture must emit one concrete profile-directory manifest entry.'
        Assert-True -Condition ([string]$capturedEntry[0].relativeDestinationPath -eq 'AppData\Local\Packages\OpenAI.Codex_2p2nqsd0c76g0\Settings') -Message 'Guest app-state capture must record the resolved package path instead of the wildcard rule.'
        Assert-True -Condition ([string]$savedSettings.workspace -eq '%CLAGNOS_TARGET_PROFILE_PATH%\Documents') -Message 'Guest app-state capture must replace source profile paths with a target profile placeholder.'
        Assert-True -Condition ($savedSettings.PSObject.Properties.Match('apiToken').Count -eq 0) -Message 'Guest app-state capture must strip sensitive JSON fields before saving the snapshot.'
    }
    finally {
        if ($null -ne $module) {
            Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Guest app-state replay resolves wildcard manifest targets to concrete profile paths" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-guest-replay-' + [Guid]::NewGuid().ToString('N'))
    $profilePath = Join-Path $tempRoot 'profiles\manager'
    $resolvedSettingsPath = Join-Path $profilePath 'AppData\Local\Packages\OpenAI.Codex_2p2nqsd0c76g0\Settings'
    $scratchRoot = Join-Path $tempRoot 'payload-build'
    $payloadPath = Join-Path $scratchRoot 'payload\profile-directories\manager\OpenAI.Codex.Settings'
    $zipPath = Join-Path $tempRoot 'app-state.zip'
    $modulePath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-guest.psm1'
    $module = $null

    try {
        New-Item -Path $resolvedSettingsPath -ItemType Directory -Force | Out-Null
        New-Item -Path $payloadPath -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $payloadPath 'settings.json') -Value '{"theme":"saved"}' -Encoding UTF8

        $manifest = [ordered]@{
            version = 3
            taskName = '116-install-codex-application'
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @(
                [ordered]@{
                    sourcePath = 'payload/profile-directories/manager/OpenAI.Codex.Settings'
                    relativeDestinationPath = 'AppData\Local\Packages\OpenAI.Codex_*\Settings'
                    targetProfiles = @('manager')
                }
            )
            profileFiles = @()
            registryImports = @()
        }
        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 8) -Encoding UTF8
        Compress-Archive -LiteralPath @(
            (Join-Path $scratchRoot 'app-state.manifest.json'),
            (Join-Path $scratchRoot 'payload')
        ) -DestinationPath $zipPath -Force

        $module = Import-Module -Name $modulePath -Force -PassThru
        $replayResult = Invoke-ClagnosTaskAppStateReplay `
            -ZipPath $zipPath `
            -TaskName '116-install-codex-application' `
            -ManagerUser 'manager' `
            -AssistantUser 'assistant' `
            -ProfileTargets @([pscustomobject]@{ Label = 'manager'; UserName = 'manager'; ProfilePath = $profilePath })

        Assert-True -Condition ([bool]$replayResult.Verified) -Message 'Guest app-state replay must verify successfully when a wildcard manifest resolves to a concrete profile path.'
        Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $resolvedSettingsPath 'settings.json') -Raw) -match '"saved"') -Message 'Guest app-state replay must copy wildcard-manifest content into the resolved package directory.'
    }
    finally {
        if ($null -ne $module) {
            Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Task command surface supports save and restore app-state maintenance" -Action {
    $taskContractText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\task\contract.ps1') -Raw)
    $taskRuntimeText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\task\runtime.ps1') -Raw)
    $taskEntryText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\commands\task\entry.ps1') -Raw)
    $taskHelpText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\cli\clagnos-help.ps1') -Raw)

    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskSaveAppStateOptionSpecification*') -Message 'Task contract must expose the save-app-state option.'
    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskRestoreAppStateOptionSpecification*') -Message 'Task contract must expose the restore-app-state option.'
    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskSourceOptionSpecification*') -Message 'Task contract must expose the source option.'
    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskTargetOptionSpecification*') -Message 'Task contract must expose the target option.'
    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskUserOptionSpecification*') -Message 'Task contract must expose the user option.'
    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskVmInitTaskOptionSpecification*') -Message 'Task contract must expose vm-init-task.'
    Assert-True -Condition ($taskContractText -like '*Get-ClagnosTaskVmUpdateTaskOptionSpecification*') -Message 'Task contract must expose vm-update-task.'
    Assert-True -Condition ($taskRuntimeText -like '*Assert-ClagnosTaskCommandOptionScope*') -Message 'Task runtime must scope task command options by mode.'
    Assert-True -Condition ($taskRuntimeText -like '*save-app-state*') -Message 'Task runtime must recognize save-app-state mode.'
    Assert-True -Condition ($taskRuntimeText -like '*restore-app-state*') -Message 'Task runtime must recognize restore-app-state mode.'
    Assert-True -Condition ($taskRuntimeText -like '*Resolve-ClagnosTaskAppStateSurface*') -Message 'Task runtime must resolve app-state source and target surfaces.'
    Assert-True -Condition ($taskRuntimeText -like '*Resolve-ClagnosTaskVmAppStateSelectedProfiles*') -Message 'Task runtime must resolve VM app-state user filters.'
    Assert-True -Condition ($taskEntryText -like '*Save-ClagnosTaskAppStateFromVm*') -Message 'Task entry must call the VM app-state save path.'
    Assert-True -Condition ($taskEntryText -like '*Save-ClagnosTaskAppStateFromLocalMachine*') -Message 'Task entry must call the local app-state save path.'
    Assert-True -Condition ($taskEntryText -like '*Restore-ClagnosTaskAppStateToLocalMachine*') -Message 'Task entry must call the local app-state restore path.'
    Assert-True -Condition ($taskEntryText -like '*Invoke-ClagnosTaskAppStatePostProcess*') -Message 'Task entry must call the shared VM app-state restore path.'
    Assert-True -Condition ($taskEntryText -like '*New-ClagnosTaskAppStateFilteredTaskBlock*') -Message 'Task entry must filter VM restore payloads when a user subset is selected.'
    Assert-True -Condition (-not ($taskEntryText -like '*-Transport ''run-command''*')) -Message 'Task entry must not keep the retired run-command app-state restore transport.'
    Assert-True -Condition ($taskHelpText -like '*task --save-app-state --vm-update-task=115*') -Message 'Help must document task save-app-state examples.'
    Assert-True -Condition ($taskHelpText -like '*task --save-app-state --source=lm --user=.current.*') -Message 'Help must document local save-app-state examples.'
    Assert-True -Condition ($taskHelpText -like '*task --restore-app-state --target=lm --user=.current.*') -Message 'Help must document local restore-app-state examples.'
    Assert-True -Condition ($taskHelpText -like '*VM save/restore is SSH-based*') -Message 'Help must describe the SSH-based VM app-state transport.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'modules\commands\task\parameters\init-task.ps1'))) -Message 'Task command must not keep the retired init-task parameter binding.'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'modules\commands\task\parameters\update-task.ps1'))) -Message 'Task command must not keep the retired update-task parameter binding.'
}

Invoke-Test -Name "Local-machine app-state helpers resolve task users and preserve restore journals" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-local-app-state-test-' + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $stageRoot = Join-Path $tempRoot 'windows\update'
    $taskRoot = Join-Path $stageRoot '101-local-app-state'
    $localStageRoot = Join-Path $stageRoot 'local'
    $localTaskRoot = Join-Path $localStageRoot '1001-local-app-state'
    $profileRoot = Join-Path $tempRoot 'profiles'
    $currentUserAlias = [string][System.Environment]::UserName
    $operatorProfile = Join-Path $profileRoot 'operator'
    $assistantProfile = Join-Path $profileRoot 'assistant'
    $fakeCatalog = @(
        [pscustomobject]@{ Label = $currentUserAlias; UserName = $currentUserAlias; ProfilePath = $operatorProfile; NtUserDatPath = (Join-Path $operatorProfile 'NTUSER.DAT') },
        [pscustomobject]@{ Label = 'operator'; UserName = 'operator'; ProfilePath = $operatorProfile; NtUserDatPath = (Join-Path $operatorProfile 'NTUSER.DAT') },
        [pscustomobject]@{ Label = 'assistant'; UserName = 'assistant'; ProfilePath = $assistantProfile; NtUserDatPath = (Join-Path $assistantProfile 'NTUSER.DAT') }
    )
    $taskBlock = [pscustomobject]@{
        Name = '101-local-app-state'
        TaskRootPath = [string]$taskRoot
        DirectoryPath = [string]$taskRoot
        StageRootDirectoryPath = [string]$stageRoot
        RelativePath = '101-local-app-state\101-local-app-state.ps1'
        AppStateSpec = ConvertTo-ClagnosTaskFolderAppStateSpec -TaskName '101-local-app-state' -TaskLabel '101-local-app-state' -AppState ([ordered]@{
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @()
            profileFiles = @(@{ path = 'AppData\Roaming\TestApp\settings.json' })
            machineRegistryKeys = @()
            userRegistryKeys = @()
        })
    }
    $localTaskBlock = [pscustomobject]@{
        Name = '1001-local-app-state'
        TaskRootPath = [string]$localTaskRoot
        DirectoryPath = [string]$localTaskRoot
        StageRootDirectoryPath = [string]$stageRoot
        RelativePath = 'local\1001-local-app-state\1001-local-app-state.ps1'
        AppStateSpec = $taskBlock.AppStateSpec
    }

    $originalCatalogCommand = Get-Command Get-ClagnosLocalAppStateProfileCatalog -CommandType Function -ErrorAction Stop
    $originalCaptureCommand = Get-Command Invoke-ClagnosTaskAppStateCapture -CommandType Function -ErrorAction SilentlyContinue
    $originalReplayCommand = Get-Command Invoke-ClagnosTaskAppStateReplay -CommandType Function -ErrorAction SilentlyContinue
    try {
        New-Item -Path $taskRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $localTaskRoot -ItemType Directory -Force | Out-Null
        foreach ($profilePath in @($operatorProfile, $assistantProfile)) {
            New-Item -Path $profilePath -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $profilePath 'NTUSER.DAT') -Value 'stub' -Encoding UTF8
            New-Item -Path (Join-Path $profilePath 'AppData\Roaming\TestApp') -ItemType Directory -Force | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"saved"}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $assistantProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"assistant"}' -Encoding UTF8

        Set-Item -Path Function:Get-ClagnosLocalAppStateProfileCatalog -Value {
            return @(
                [pscustomobject]@{ Label = $currentUserAlias; UserName = $currentUserAlias; ProfilePath = $operatorProfile; NtUserDatPath = (Join-Path $operatorProfile 'NTUSER.DAT') },
                [pscustomobject]@{ Label = 'operator'; UserName = 'operator'; ProfilePath = $operatorProfile; NtUserDatPath = (Join-Path $operatorProfile 'NTUSER.DAT') },
                [pscustomobject]@{ Label = 'assistant'; UserName = 'assistant'; ProfilePath = $assistantProfile; NtUserDatPath = (Join-Path $assistantProfile 'NTUSER.DAT') }
            )
        }.GetNewClosure()

        $selectedCurrent = @(Resolve-ClagnosLocalAppStateProfileTargets -RequestedUsers @('.current.'))
        Assert-True -Condition (@($selectedCurrent).Count -eq 1) -Message 'Local app-state .current. must resolve to one profile target.'
        $selectedExplicit = @(Resolve-ClagnosLocalAppStateProfileTargets -RequestedUsers @('assistant,operator'))
        Assert-True -Condition (@($selectedExplicit).Count -eq 2) -Message 'Local app-state explicit user lists must resolve multiple profile targets.'
        $expectedTrackedBackupRoot = Join-Path (Join-Path $stageRoot 'backup-app-states') '101-local-app-state'
        $expectedLocalBackupRoot = Join-Path (Join-Path $localStageRoot 'backup-app-states') '1001-local-app-state'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStateLocalBackupRootPath -TaskBlock $taskBlock) -eq $expectedTrackedBackupRoot) -Message 'Tracked local restore backups must resolve under the stage backup-app-states root.'
        Assert-True -Condition ([string](Get-ClagnosTaskAppStateLocalBackupRootPath -TaskBlock $localTaskBlock) -eq $expectedLocalBackupRoot) -Message 'Local-only restore backups must resolve under the local backup-app-states root.'

        Set-Item -Path Function:Invoke-ClagnosTaskAppStateCapture -Value {
            param([string]$TaskName,[string]$PlanPath,[string]$OutputZipPath,[string]$ManagerUser,[string]$AssistantUser,[object[]]$ProfileTargets=@())
            $scratchRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-test-capture-' + [Guid]::NewGuid().ToString('N'))
            New-Item -Path (Join-Path $scratchRoot 'payload\\profile-files\\operator') -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $scratchRoot 'payload\\profile-files\\operator\\settings.json') -Value '{"theme":"saved"}' -Encoding UTF8
            $manifest = [ordered]@{
                version = 3
                taskName = $TaskName
                machineDirectories = @()
                machineFiles = @()
                profileDirectories = @()
                profileFiles = @(
                    [ordered]@{
                        sourcePath = 'payload/profile-files/operator/settings.json'
                        relativeDestinationPath = 'AppData\\Roaming\\TestApp\\settings.json'
                        targetProfiles = @('operator')
                    }
                )
                registryImports = @()
            }
            Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 8) -Encoding UTF8
            Compress-Archive -LiteralPath @(
                (Join-Path $scratchRoot 'app-state.manifest.json'),
                (Join-Path $scratchRoot 'payload')
            ) -DestinationPath $OutputZipPath -Force
            Remove-Item -LiteralPath $scratchRoot -Recurse -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ CreatedZip = $true }
        }.GetNewClosure()

        $saveResult = Save-ClagnosTaskAppStateFromLocalMachine -TaskBlock $taskBlock -RequestedUsers @('operator')
        $zipPath = Get-ClagnosTaskAppStateZipPath -TaskBlock $taskBlock
        Assert-True -Condition ([string]$saveResult.Status -eq 'saved') -Message 'Local app-state save must complete for matching temp profile targets.'
        Assert-True -Condition (Test-Path -LiteralPath $zipPath) -Message 'Local app-state save must write the task-local app-state zip.'
        $savedManifestRoot = Join-Path $tempRoot 'saved-manifest'
        Expand-Archive -LiteralPath $zipPath -DestinationPath $savedManifestRoot -Force
        $savedManifest = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath (Join-Path $savedManifestRoot 'app-state.manifest.json') -Raw))
        $savedProfileFileEntry = @($savedManifest.profileFiles)[0]
        Assert-True -Condition ([string]$savedProfileFileEntry.sourcePath -eq 'payload\profile-files\manager\settings.json') -Message 'Local app-state save must normalize profile-generic payload source paths to manager.'
        Assert-True -Condition (@($savedProfileFileEntry.targetProfiles).Count -eq 0) -Message 'Local app-state save must clear foreign targetProfiles after manager normalization.'

        Set-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"drift"}' -Encoding UTF8

        Set-Item -Path Function:Invoke-ClagnosTaskAppStateReplay -Value {
            param([string]$ZipPath,[string]$TaskName,[string]$ManagerUser,[string]$AssistantUser,[object[]]$ProfileTargets=@())
            Set-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"saved"}' -Encoding UTF8
            return [pscustomobject]@{ MachineRegistryImports = 0; UserRegistryImports = 0; MachineDirectoryCopies = 0; MachineFileCopies = 0; ProfileDirectoryCopies = 0; ProfileFileCopies = 1 }
        }.GetNewClosure()

        $restoreResult = Restore-ClagnosTaskAppStateToLocalMachine -TaskBlock $taskBlock -RequestedUsers @('operator')
        Assert-True -Condition ([string]$restoreResult.Status -eq 'restored') -Message 'Local app-state restore must complete for matching temp profile targets.'
        Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Raw) -match '"saved"') -Message 'Local app-state restore must return the selected profile file to the saved value.'
        Assert-True -Condition (Test-Path -LiteralPath ([string]$restoreResult.BackupRoot)) -Message 'Local app-state restore must publish the backup root.'
        Assert-True -Condition (Test-Path -LiteralPath ([string]$restoreResult.JournalPath)) -Message 'Local app-state restore must publish the restore journal.'
        Assert-True -Condition ([string]$restoreResult.BackupRoot -eq $expectedTrackedBackupRoot) -Message 'Local app-state restore must use the task-adjacent backup-app-states root.'
        Assert-True -Condition (Test-Path -LiteralPath ([string]$restoreResult.VerifyReportPath)) -Message 'Local app-state restore must publish the verify report.'
        $restoreJournal = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath ([string]$restoreResult.JournalPath) -Raw))
        $verifyReport = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath ([string]$restoreResult.VerifyReportPath) -Raw))
        Assert-True -Condition ([string]$restoreJournal.status -eq 'verified') -Message 'Local app-state restore journal must record verified completion.'
        Assert-True -Condition ([bool]$verifyReport.succeeded) -Message 'Local app-state verify report must record a successful restore verification.'
    }
    finally {
        Set-Item -Path Function:Get-ClagnosLocalAppStateProfileCatalog -Value $originalCatalogCommand.ScriptBlock
        if ($null -ne $originalCaptureCommand) {
            Set-Item -Path Function:Invoke-ClagnosTaskAppStateCapture -Value $originalCaptureCommand.ScriptBlock
        }
        else {
            Remove-Item -Path Function:Invoke-ClagnosTaskAppStateCapture -ErrorAction SilentlyContinue
        }
        if ($null -ne $originalReplayCommand) {
            Set-Item -Path Function:Invoke-ClagnosTaskAppStateReplay -Value $originalReplayCommand.ScriptBlock
        }
        else {
            Remove-Item -Path Function:Invoke-ClagnosTaskAppStateReplay -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath (Join-Path $tempRoot 'saved-manifest') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Task app-state save uses current task.json rules ahead of legacy zip coverage" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-app-state-plan-' + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $stageRoot = Join-Path $tempRoot 'windows\update'
    $taskRoot = Join-Path $stageRoot '109-test-application'
    $pluginRoot = Join-Path $taskRoot 'app-state'
    try {
        New-Item -Path $pluginRoot -ItemType Directory -Force | Out-Null
        $taskBlock = [pscustomobject]@{
            Name = '109-test-application'
            TaskRootPath = [string]$taskRoot
            DirectoryPath = [string]$taskRoot
            StageRootDirectoryPath = [string]$stageRoot
            RelativePath = '109-test-application\109-test-application.ps1'
            AppStateSpec = ConvertTo-ClagnosTaskFolderAppStateSpec -TaskName '109-test-application' -TaskLabel '109-test-application' -AppState ([ordered]@{
                machineDirectories = @()
                machineFiles = @()
                profileDirectories = @(
                    @{
                        path = 'AppData\Roaming\TestApp'
                        targetProfiles = @()
                        excludeNames = @('Cache')
                    }
                )
                profileFiles = @()
                machineRegistryKeys = @()
                userRegistryKeys = @(
                    @{
                        path = 'HKCU\Software\TestApp'
                        targetProfiles = @()
                    }
                )
            })
        }

        $scratchRoot = Join-Path $tempRoot 'legacy-payload'
        New-Item -Path (Join-Path $scratchRoot 'payload\profile-directories\manager\LegacyApp') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $scratchRoot 'payload\profile-directories\manager\LegacyApp\settings.json') -Value '{}' -Encoding UTF8
        New-Item -Path (Join-Path $scratchRoot 'payload\registry\user\manager') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $scratchRoot 'payload\registry\user\manager\HKCU_Software_LegacyApp.reg') -Value 'Windows Registry Editor Version 5.00' -Encoding Unicode
        $legacyManifest = [ordered]@{
            version = 3
            taskName = '109-test-application'
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @(
                [ordered]@{
                    sourcePath = 'payload/profile-directories/manager/LegacyApp'
                    relativeDestinationPath = 'AppData\Roaming\LegacyApp'
                    targetProfiles = @('manager')
                }
            )
            profileFiles = @()
            registryImports = @(
                [ordered]@{
                    sourcePath = 'payload/registry/user/manager/HKCU_Software_LegacyApp.reg'
                    scope = 'user'
                    registryPath = 'HKEY_CURRENT_USER\Software\LegacyApp'
                    targetProfiles = @('manager')
                }
            )
        }
        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value ($legacyManifest | ConvertTo-Json -Depth 10) -Encoding UTF8
        Compress-Archive -LiteralPath @(
            (Join-Path $scratchRoot 'app-state.manifest.json'),
            (Join-Path $scratchRoot 'payload')
        ) -DestinationPath (Join-Path $pluginRoot 'app-state.zip') -Force

        $capturePlan = Get-ClagnosTaskAppStateCapturePlan -TaskBlock $taskBlock
        $profilePaths = @($capturePlan.profileDirectories | ForEach-Object { [string]$_.path })
        $profileFiles = @($capturePlan.profileFiles | ForEach-Object { [string]$_.path })
        $userRegistryPaths = @($capturePlan.userRegistryKeys | ForEach-Object { [string]$_.path })

        Assert-True -Condition (@($profilePaths).Count -eq 1) -Message 'Task app-state capture must prefer the current task.json profile directories when they exist.'
        Assert-True -Condition (@($profileFiles).Count -eq 0) -Message 'Task app-state capture must not backfill legacy profile files when the current task.json does not define them.'
        Assert-True -Condition (@($userRegistryPaths).Count -eq 1) -Message 'Task app-state capture must prefer the current task.json user-registry rules when they exist.'
        Assert-True -Condition (@($profilePaths) -contains 'AppData\Roaming\TestApp') -Message 'Task app-state capture must keep the current task.json profile directory path.'
        Assert-True -Condition (-not (@($profilePaths) -contains 'AppData\Roaming\LegacyApp')) -Message 'Task app-state capture must not merge stale legacy zip profile directories back into the save plan when task.json already defines them.'
        Assert-True -Condition (@($userRegistryPaths) -contains 'HKCU\Software\TestApp') -Message 'Task app-state capture must keep the current task.json user-registry path.'
        Assert-True -Condition (-not (@($userRegistryPaths) -contains 'HKEY_CURRENT_USER\Software\LegacyApp') -and -not (@($userRegistryPaths) -contains 'HKCU\Software\LegacyApp')) -Message 'Task app-state capture must not merge stale legacy zip registry paths back into the save plan when task.json already defines them.'
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "App-state wildcard capture path matching resolves matched items instead of enumerating child content" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-app-state-match-' + [Guid]::NewGuid().ToString('N'))
    $profileRoot = Join-Path $tempRoot 'Users\manager'
    $localStatePath = Join-Path $profileRoot 'AppData\Local\Packages\TestApp_123\LocalState'
    $settingsPath = Join-Path $profileRoot 'AppData\Local\Packages\TestApp_123\Settings'
    $modulePath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-app-state-guest.psm1'
    $module = $null
    try {
        New-Item -Path $localStatePath -ItemType Directory -Force | Out-Null
        New-Item -Path $settingsPath -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $localStatePath 'settings.json') -Value '{}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $settingsPath 'other.json') -Value '{}' -Encoding UTF8

        $module = Import-Module -Name $modulePath -Force -PassThru
        $matches = @(& $module {
            param($BasePath, $RelativeOrAbsolutePath)
            Resolve-ClagnosAppStateCapturePathMatches -BasePath $BasePath -RelativeOrAbsolutePath $RelativeOrAbsolutePath
        } $profileRoot 'AppData\Local\Packages\TestApp_*\LocalState')

        Assert-True -Condition (@($matches).Count -eq 1) -Message 'Wildcard app-state capture matching must resolve the matched path itself.'
        Assert-True -Condition ([string]$matches[0] -eq (Resolve-Path -LiteralPath $localStatePath).Path) -Message 'Wildcard app-state capture matching must return the matched LocalState directory path.'
    }
    finally {
        if ($null -ne $module) {
            Remove-Module -ModuleInfo $module -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Local-machine app-state restore rolls back when verification fails" -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-local-app-state-rollback-' + [Guid]::NewGuid().ToString('N'))
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    $stageRoot = Join-Path $tempRoot 'windows\update'
    $taskRoot = Join-Path $stageRoot '101-local-app-state'
    $profileRoot = Join-Path $tempRoot 'profiles'
    $operatorProfile = Join-Path $profileRoot 'operator'
    $taskBlock = [pscustomobject]@{
        Name = '101-local-app-state'
        TaskRootPath = [string]$taskRoot
        DirectoryPath = [string]$taskRoot
        StageRootDirectoryPath = [string]$stageRoot
        RelativePath = '101-local-app-state\101-local-app-state.ps1'
        AppStateSpec = ConvertTo-ClagnosTaskFolderAppStateSpec -TaskName '101-local-app-state' -TaskLabel '101-local-app-state' -AppState ([ordered]@{
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @()
            profileFiles = @(@{ path = 'AppData\Roaming\TestApp\settings.json' })
            machineRegistryKeys = @()
            userRegistryKeys = @()
        })
    }

    $originalCatalogCommand = Get-Command Get-ClagnosLocalAppStateProfileCatalog -CommandType Function -ErrorAction Stop
    $originalReplayCommand = Get-Command Invoke-ClagnosTaskAppStateReplay -CommandType Function -ErrorAction SilentlyContinue
    try {
        New-Item -Path $taskRoot -ItemType Directory -Force | Out-Null
        New-Item -Path $operatorProfile -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $operatorProfile 'NTUSER.DAT') -Value 'stub' -Encoding UTF8
        New-Item -Path (Join-Path $operatorProfile 'AppData\Roaming\TestApp') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"saved"}' -Encoding UTF8

        Set-Item -Path Function:Get-ClagnosLocalAppStateProfileCatalog -Value {
            return @(
                [pscustomobject]@{ Label = 'operator'; UserName = 'operator'; ProfilePath = $operatorProfile; NtUserDatPath = (Join-Path $operatorProfile 'NTUSER.DAT') }
            )
        }.GetNewClosure()

        $pluginDir = Get-ClagnosTaskAppStatePluginDirectoryPath -TaskBlock $taskBlock
        New-Item -Path $pluginDir -ItemType Directory -Force | Out-Null
        $scratchRoot = Join-Path $tempRoot 'payload'
        New-Item -Path (Join-Path $scratchRoot 'payload\\profile-files\\operator') -ItemType Directory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $scratchRoot 'payload\\profile-files\\operator\\settings.json') -Value '{"theme":"saved"}' -Encoding UTF8
        $manifest = [ordered]@{
            version = 3
            taskName = '101-local-app-state'
            machineDirectories = @()
            machineFiles = @()
            profileDirectories = @()
            profileFiles = @(
                [ordered]@{
                    sourcePath = 'payload/profile-files/operator/settings.json'
                    relativeDestinationPath = 'AppData\\Roaming\\TestApp\\settings.json'
                    targetProfiles = @('operator')
                }
            )
            registryImports = @()
        }
        Set-Content -LiteralPath (Join-Path $scratchRoot 'app-state.manifest.json') -Value ($manifest | ConvertTo-Json -Depth 8) -Encoding UTF8
        Compress-Archive -LiteralPath @(
            (Join-Path $scratchRoot 'app-state.manifest.json'),
            (Join-Path $scratchRoot 'payload')
        ) -DestinationPath (Join-Path $pluginDir 'app-state.zip') -Force

        Set-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"drift"}' -Encoding UTF8

        Set-Item -Path Function:Invoke-ClagnosTaskAppStateReplay -Value {
            param([string]$ZipPath,[string]$TaskName,[string]$ManagerUser,[string]$AssistantUser,[object[]]$ProfileTargets=@())
            Set-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Value '{"theme":"broken"}' -Encoding UTF8
            return [pscustomobject]@{ MachineRegistryImports = 0; UserRegistryImports = 0; MachineDirectoryCopies = 0; MachineFileCopies = 0; ProfileDirectoryCopies = 0; ProfileFileCopies = 1 }
        }.GetNewClosure()

        $restoreFailed = $false
        try {
            [void](Restore-ClagnosTaskAppStateToLocalMachine -TaskBlock $taskBlock -RequestedUsers @('operator'))
        }
        catch {
            $restoreFailed = $true
        }

        $backupRoot = Get-ClagnosTaskAppStateLocalBackupRootPath -TaskBlock $taskBlock
        $journalPath = Join-Path $backupRoot 'restore-journal.json'
        $verifyReportPath = Join-Path $backupRoot 'verify-report.json'
        $restoreJournal = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $journalPath -Raw))
        $verifyReport = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $verifyReportPath -Raw))

        Assert-True -Condition $restoreFailed -Message 'Local app-state restore must fail when post-restore verification detects drift.'
        Assert-True -Condition ((Get-Content -LiteralPath (Join-Path $operatorProfile 'AppData\Roaming\TestApp\settings.json') -Raw) -match '"drift"') -Message 'Rollback must restore the pre-restore local file content when verification fails.'
        Assert-True -Condition ([string]$restoreJournal.status -eq 'rolled-back') -Message 'Local app-state restore journal must record rollback when verification fails.'
        Assert-True -Condition ([bool]$verifyReport.rollbackSucceeded) -Message 'Verify report must record a successful rollback after verification failure.'
    }
    finally {
        Set-Item -Path Function:Get-ClagnosLocalAppStateProfileCatalog -Value $originalCatalogCommand.ScriptBlock
        if ($null -ne $originalReplayCommand) {
            Set-Item -Path Function:Invoke-ClagnosTaskAppStateReplay -Value $originalReplayCommand.ScriptBlock
        }
        else {
            Remove-Item -Path Function:Invoke-ClagnosTaskAppStateReplay -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Invoke-Test -Name "Store install state and shortcut launcher helper modules exist" -Action {
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-store-install-state.psm1')) -Message 'Shared Store install state helper must exist.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-shortcut-launcher.psm1')) -Message 'Shared shortcut launcher helper must exist.'
}

Invoke-Test -Name "Store install state reader supports legacy task aliases" -Action {
    $storeStateModuleText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-store-install-state.psm1') -Raw)

    foreach ($fragment in @(
        'function Get-ClagnosStoreInstallStateCandidateTaskNames',
        "'118-install-teams-application'",
        "'125-install-be-my-eyes-application'",
        "'120-install-whatsapp-application'",
        "'116-install-codex-application'",
        "'129-install-icloud-application'",
        'requestedTaskName',
        'resolvedTaskName'
    )) {
        Assert-True -Condition ($storeStateModuleText -like ('*' + [string]$fragment + '*')) -Message ("Store install state helper must include legacy alias fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Shortcut launcher threshold uses combined target and arguments length" -Action {
    Import-Module (Join-Path $RepoRoot 'modules\core\tasks\clagnos-shortcut-launcher.psm1') -Force -DisableNameChecking
    $shortcutTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '10002-create-public-desktop-shortcuts'
    $shortcutTaskScript = [string](Get-Content -LiteralPath $shortcutTaskPath -Raw)
    $shortcutLauncherModuleText = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'modules\core\tasks\clagnos-shortcut-launcher.psm1') -Raw)
    $targetPath = 'C:\Program Files\Test App\launcher.exe'
    $argumentsAtLimit = 'a' * (259 - $targetPath.Length - 1)
    $argumentsAboveLimit = 'a' * (260 - $targetPath.Length - 1)
    $q1EksiSozlukName = ('q1{0}' -f (ConvertFrom-UnicodeCodePoints -CodePoints @(0x0045, 0x006B, 0x015F, 0x0069, 0x0053, 0x00F6, 0x007A, 0x006C, 0x00FC, 0x006B)))
    $cicekSepetiBusinessName = ('r13{0} Business' -f (ConvertFrom-UnicodeCodePoints -CodePoints @(0x00C7, 0x0069, 0x00E7, 0x0065, 0x006B, 0x0053, 0x0065, 0x0070, 0x0065, 0x0074, 0x0069)))
    $cicekSepetiMojibakeBusinessName = ConvertFrom-UnicodeCodePoints -CodePoints @(0x0072, 0x0031, 0x0033, 0x00C3, 0x2021, 0x0069, 0x00C3, 0x00A7, 0x0065, 0x006B, 0x0053, 0x0065, 0x0070, 0x0065, 0x0074, 0x0069, 0x0020, 0x0042, 0x0075, 0x0073, 0x0069, 0x006E, 0x0065, 0x0073, 0x0073)

    Assert-True -Condition ((Get-ClagnosShortcutManagedInvocationLength -TargetPath $targetPath -Arguments $argumentsAtLimit) -eq 259) -Message 'Shortcut launcher helper must measure combined target and arguments length at the direct-write boundary.'
    Assert-True -Condition (-not (Test-ClagnosShortcutNeedsManagedLauncher -TargetPath $targetPath -Arguments $argumentsAtLimit -Threshold 259)) -Message 'Shortcut launcher helper must keep direct shortcut targets when the combined invocation length is 259.'
    Assert-True -Condition ((Get-ClagnosShortcutManagedInvocationLength -TargetPath $targetPath -Arguments $argumentsAboveLimit) -eq 260) -Message 'Shortcut launcher helper must measure combined target and arguments length past the direct-write boundary.'
    Assert-True -Condition (Test-ClagnosShortcutNeedsManagedLauncher -TargetPath $targetPath -Arguments $argumentsAboveLimit -Threshold 259) -Message 'Shortcut launcher helper must require a managed launcher when the combined invocation length exceeds 259.'
    Assert-True -Condition ([string]::Equals((Get-ClagnosShortcutLauncherInvocationArguments -LauncherPath 'C:\ProgramData\clagnos\shortcut-launchers\public-desktop\r20ozon-personal.cmd'), '/c call "C:\ProgramData\clagnos\shortcut-launchers\public-desktop\r20ozon-personal.cmd"', [System.StringComparison]::Ordinal)) -Message 'Managed launcher shortcuts must invoke the launcher script through cmd.exe /c call "<path>".'
    Assert-True -Condition ([string]::Equals((Get-ClagnosShortcutLauncherFilePath -ShortcutName $q1EksiSozlukName -Subdirectory 'public-desktop'), 'C:\ProgramData\clagnos\shortcut-launchers\public-desktop\q1eksisozluk.cmd', [System.StringComparison]::OrdinalIgnoreCase)) -Message 'Shortcut launcher helper must transliterate Turkish shortcut names into stable ASCII-safe launcher paths.'
    Assert-True -Condition ([string]::Equals((Get-ClagnosShortcutNormalizedKey -Value $cicekSepetiMojibakeBusinessName), (Get-ClagnosShortcutNormalizedKey -Value $cicekSepetiBusinessName), [System.StringComparison]::Ordinal)) -Message 'Shortcut normalization must treat mojibake Turkish names as the same managed shortcut key.'
    Assert-True -Condition ($shortcutTaskScript -like '*$managedShortcutInvocationThreshold = 259*') -Message 'Public desktop shortcut task must keep the managed-launcher threshold as an explicit 259-character contract.'
    Assert-True -Condition ($shortcutTaskScript -like '*Test-ClagnosShortcutNeedsManagedLauncher -TargetPath $effectiveTargetPath -Arguments $effectiveArguments -Threshold $managedShortcutInvocationThreshold*') -Message 'Public desktop shortcut task must apply the 259-character rule to the combined target and arguments invocation.'
    Assert-True -Condition ($shortcutLauncherModuleText -like '*/c call "{0}"*') -Message 'Shared shortcut launcher helper must generate cmd.exe launcher invocations with call.'
}

Invoke-Test -Name "Windows app install task contracts cover new shortcut-backed packages" -Action {
    $installTaskMap = [ordered]@{
        '114-install-teams-application.ps1' = @('clagnos-store-install-state.psm1', 'Invoke-ClagnosInteractiveDesktopAutomation', 'Wait-ClagnosUserInteractiveDesktopReady', 'New-ClagnosInteractiveDesktopBlockMessage', 'Write-ClagnosInteractiveDesktopStatusLine', 'Write-ClagnosStoreInstallState', 'cannot be deferred to a later boot', 'winget install "Microsoft Teams" -s msstore')
        '103-install-edge-application.ps1' = @('Microsoft.Edge', 'msedge.exe')
        '104-install-onedrive-application.ps1' = @('Microsoft.OneDrive', 'OneDrive.exe')
        '105-install-rclone-tool.ps1' = @('Rclone.Rclone', 'rclone.exe')
        '115-install-nvda-application.ps1' = @('NVAccess.NVDA', 'nvd')
        '117-install-itunes-application.ps1' = @('Apple.iTunes', 'iTunes.exe')
        '118-install-be-my-eyes-application.ps1' = @('9MSW46LTDWGF', '--source msstore', 'Invoke-ClagnosInteractiveDesktopAutomation', 'Get-ClagnosInteractivePaths', 'RunAsMode ''interactiveToken''', 'Wait-ClagnosUserInteractiveDesktopReady', 'New-ClagnosInteractiveDesktopBlockMessage', 'Write-ClagnosInteractiveDesktopStatusLine', 'cannot be deferred to a later boot', 'Write-ClagnosStoreInstallState')
        '119-install-whatsapp-application.ps1' = @('9NKSQGP7F2NH', 'Invoke-ClagnosInteractiveDesktopAutomation', 'Get-ClagnosInteractivePaths', 'RunAsMode ''interactiveToken''', 'Wait-ClagnosUserInteractiveDesktopReady', 'New-ClagnosInteractiveDesktopBlockMessage', 'Write-ClagnosInteractiveDesktopStatusLine', 'Write-ClagnosStoreInstallState')
        '120-install-codex-application.ps1' = @('9PLM9XGG6VKS', 'OpenAI.Codex', 'Codex.exe', 'Invoke-ClagnosInteractiveDesktopAutomation', 'Get-ClagnosInteractivePaths', 'RunAsMode ''interactiveToken''', 'Wait-ClagnosUserInteractiveDesktopReady', 'New-ClagnosInteractiveDesktopBlockMessage', 'Write-ClagnosInteractiveDesktopStatusLine', 'Write-ClagnosStoreInstallState', 'cannot be deferred to a later boot')
        '122-install-icloud-application.ps1' = @('9PKTQ5699M62', "PackageSource = 'msstore'", 'iCloudHome.exe', 'Get-StartApps', 'Invoke-ClagnosInteractiveDesktopAutomation', 'RunAsMode ''interactiveToken''', 'Wait-ClagnosUserInteractiveDesktopReady', 'New-ClagnosInteractiveDesktopBlockMessage', 'Write-ClagnosInteractiveDesktopStatusLine', 'cannot be deferred to a later boot', 'Write-ClagnosStoreInstallState')
        '124-install-openai-codex-tool.ps1' = @('@openai/codex@latest', '@openai/codex', '--loglevel error', 'Test-BenignNpmInstallNoiseLine', '2>&1', 'npm install exit code:', 'codex.cmd', 'install-openai-codex-tool-completed')
        '125-install-github-copilot-tool.ps1' = @('@github/copilot@latest', '@github/copilot', '--loglevel error', 'Test-BenignNpmInstallNoiseLine', '2>&1', 'npm install exit code:', 'copilot.cmd', 'install-github-copilot-tool-completed')
        '126-install-google-gemini-tool.ps1' = @('@google/gemini-cli@latest', '@google/gemini-cli', '--loglevel error', 'Test-BenignNpmInstallNoiseLine', '2>&1', 'npm install exit code:', 'gemini.cmd', 'install-google-gemini-tool-completed')
        '129-install-google-drive-application.ps1' = @('Google.GoogleDrive', 'GoogleDriveFS.exe')
        '131-install-vlc-application.ps1' = @('VideoLAN.VLC', 'vlc.exe')
        '132-install-vs2022community-application.ps1' = @('visualstudio2022community', 'choco install', 'devenv.exe', 'Wait-DevenvReady', 'install-vs2022community-application-completed')
        '133-install-jaws-application.ps1' = @('FreedomScientific.JAWS.2025', 'jfw.exe', '--exact', '--accept-source-agreements', '--accept-package-agreements', '--silent', '--disable-interactivity', 'Resolve-JawsRootFromRegistry', 'Ensure-WingetSourcesReady', 'jaws-step-retry')
    }

    foreach ($entry in $installTaskMap.GetEnumerator()) {
        $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName ([System.IO.Path]::GetFileNameWithoutExtension([string]$entry.Key))
        Assert-True -Condition (Test-Path -LiteralPath $taskPath) -Message ("Expected install task file was not found: {0}" -f $taskPath)
        $taskText = [string](Get-Content -LiteralPath $taskPath -Raw)
        foreach ($fragment in @($entry.Value)) {
            Assert-True -Condition ($taskText -like ('*' + [string]$fragment + '*')) -Message ("Task '{0}' must include fragment '{1}'." -f [string]$entry.Key, [string]$fragment)
        }
    }
}

Invoke-Test -Name "Windows PATH refresh is centralized and refreshenv is gone" -Action {
    $helperModulePath = Join-Path $RepoRoot 'modules\core\tasks\clagnos-session-environment.psm1'
    Assert-True -Condition (Test-Path -LiteralPath $helperModulePath) -Message 'Windows session environment helper module must exist.'

    $helperText = [string](Get-Content -LiteralPath $helperModulePath -Raw)
    Assert-True -Condition ($helperText -like '*HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment*') -Message 'Session environment helper must read machine PATH from the registry.'
    Assert-True -Condition ($helperText -like '*HKCU:\Environment*') -Message 'Session environment helper must read user PATH from the registry.'
    Assert-True -Condition ($helperText -like '*Refresh-ClagnosSessionPath*') -Message 'Session environment helper must export a PATH refresh function.'

    $windowsSurfaceFiles = @(
        Get-ChildItem (Join-Path $RepoRoot 'windows\init') -Recurse -File -Include *.ps1 |
            Select-Object -ExpandProperty FullName
        Get-ChildItem (Join-Path $RepoRoot 'windows\update') -Recurse -File -Include *.ps1 |
            Select-Object -ExpandProperty FullName
        (Join-Path $RepoRoot 'tools\scripts\clagnos-summary-readback-windows.ps1')
        (Join-Path $RepoRoot 'modules\core\tasks\clagnos-store-install-state.psm1')
    ) | Select-Object -Unique

    foreach ($filePath in @($windowsSurfaceFiles)) {
        $fileText = [string](Get-Content -LiteralPath $filePath -Raw)
        Assert-True -Condition (-not ($fileText -like '*refreshenv.cmd*')) -Message ("Windows PATH refresh contract must not reference refreshenv.cmd: {0}" -f $filePath)
    }
}

Invoke-Test -Name "Windows run-command tasks extend Azure CLI timeout to the task budget" -Action {
    $runnerPath = Join-Path $RepoRoot 'modules\tasks\run-command\runner.ps1'
    $azCliHelperPath = Join-Path $RepoRoot 'modules\core\system\clagnos-az-cli.ps1'
    $runnerText = [string](Get-Content -LiteralPath $runnerPath -Raw)
    $azCliHelperText = [string](Get-Content -LiteralPath $azCliHelperPath -Raw)
    . $runnerPath

    $generatedWrapper = [string](New-ClagnosRunCommandTaskWrapperScript -TaskName 'probe-task' -TaskScript 'Write-Host "probe-output"' -TimeoutSeconds 60 -CombinedShell powershell)

    foreach ($fragment in @(
        'Invoke-ClagnosWithAzCliTimeoutSeconds',
        '$taskTimeoutSeconds + 120',
        'Invoke-ClagnosWithAzCliTimeoutSeconds -TimeoutSeconds $azTimeoutSeconds',
        'Start-Process -FilePath',
        'WaitForExit(',
        'Task timed out after {0} second(s).',
        'Stop-Process -Id $process.Id -Force',
        'CLAGNOS_NESTED_RESULT:success',
        'CLAGNOS_NESTED_RESULT:error',
        'Nested PowerShell ended without a result marker.'
    )) {
        Assert-True -Condition ($runnerText -like ('*' + [string]$fragment + '*')) -Message ("Run-command runner must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'function Invoke-ClagnosWithAzCliTimeoutSeconds',
        '$script:AzCommandTimeoutSeconds = $effectiveTimeoutSeconds',
        '$script:AzCommandTimeoutSeconds = $previousTimeoutSeconds'
    )) {
        Assert-True -Condition ($azCliHelperText -like ('*' + [string]$fragment + '*')) -Message ("Azure CLI helper must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'param([string]$TaskScriptPath)',
        '-TaskScriptPath',
        '.payload.ps1',
        '*>&1 | ForEach-Object'
    )) {
        Assert-True -Condition ($generatedWrapper.Contains([string]$fragment)) -Message ("Generated Windows run-command wrapper must include fragment '{0}'." -f [string]$fragment)
    }

    Assert-True -Condition (-not ($generatedWrapper -like '*$taskScriptBase64 = '''' + $taskScriptBase64 + ''''*')) -Message 'Generated Windows run-command wrapper must not leave the task base64 assignment uninterpolated.'
}

Invoke-Test -Name "Windows autologon manager task and health contract" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '102-configure-autologon-settings'
    $healthTaskPath = Get-RepoSummaryReadbackScriptPath -Platform windows

    Assert-True -Condition (Test-Path -LiteralPath $taskPath) -Message 'Autologon manager task file was not found.'
    $taskText = [string](Get-Content -LiteralPath $taskPath -Raw)
    $healthTaskText = [string](Get-Content -LiteralPath $healthTaskPath -Raw)

    foreach ($fragment in @(
        '__VM_ADMIN_USER__',
        '__VM_ADMIN_PASS__',
        '/accepteula',
        'LogonUser',
        'AutoAdminLogon',
        'DefaultUserName',
        'DefaultDomainName',
        'DefaultPasswordPresent',
        'autologon-state =>',
        'Autologon note: DefaultPassword is not present in Winlogon.',
        'configure-autologon-settings-completed',
        'autologon.exe was not found',
        'Install the Sysinternals package from the builtin package catalog first.'
    )) {
        Assert-True -Condition ($taskText -like ('*' + [string]$fragment + '*')) -Message ("Autologon manager task must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'AUTOLOGON STATUS:',
        'manager_autologon_configured',
        'DefaultDomainName',
        'CredentialStorageMode',
        'sysinternals-autologon-or-external-store'
    )) {
        Assert-True -Condition ($healthTaskText -like ('*' + [string]$fragment + '*')) -Message ("Health snapshot must include autologon fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Windows OpenSSH init tasks recover missing sshd registration" -Action {
    $installTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage init -TaskName '03-install-openssh-service'
    $configTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage init -TaskName '04-configure-sshd-service'

    Assert-True -Condition (Test-Path -LiteralPath $installTaskPath) -Message 'OpenSSH install task file was not found.'
    Assert-True -Condition (Test-Path -LiteralPath $configTaskPath) -Message 'OpenSSH configure task file was not found.'

    $installTaskText = [string](Get-Content -LiteralPath $installTaskPath -Raw)
    $configTaskText = [string](Get-Content -LiteralPath $configTaskPath -Raw)

    foreach ($fragment in @(
        'Wait-OpenSshServiceRegistration',
        'Get-OpenSshServiceExecutablePath',
        'Install-OpenSshServerPackage',
        'Downloading OpenSSH MSI from',
        'Invoke-WebRequest -Uri $openSshServerMsiUrl -OutFile $openSshServerMsiPath',
        "Start-Process -FilePath 'msiexec.exe'",
        'OpenSSH MSI installation exited with code',
        'Ensure-OpenSshHostKeyMaterial',
        'Registering sshd service directly from executable:',
        'Get-OpenSshInstallScriptPath',
        'openssh-service-ready:',
        'openssh-service-pending-reboot:',
        'TASK_REBOOT_REQUIRED:install-openssh-service',
        'OpenSSH setup completed but sshd service was not found.'
    )) {
        Assert-True -Condition ($installTaskText -like ('*' + [string]$fragment + '*')) -Message ("OpenSSH install task must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'Wait-SshdListener',
        'Recover-OpenSshService',
        'OpenSSH service is missing. Running service installer before sshd_config changes.',
        'OpenSSH service is missing. Attempting direct service recovery before sshd_config changes from',
        'Ensure-OpenSshHostKeyMaterial',
        'Running OpenSSH host key generation:',
        'Start-Service -Name sshd',
        'Restart-Service -Name sshd -Force',
        'listener did not bind to the configured port in time',
        'Subsystem sftp C:/Windows/System32/OpenSSH/sftp-server.exe',
        'Set-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name "DefaultShell" -Value "C:\Windows\System32\cmd.exe"'
    )) {
        Assert-True -Condition ($configTaskText -like ('*' + [string]$fragment + '*')) -Message ("OpenSSH configure task must include fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Windows configure-all-users init task contract" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage init -TaskName '07-configure-all-users'
    $taskJsonPath = Get-RepoTaskJsonPath -Platform windows -Stage init -TaskName '07-configure-all-users'

    Assert-True -Condition (Test-Path -LiteralPath $taskPath) -Message 'configure-all-users init task file was not found.'
    Assert-True -Condition (Test-Path -LiteralPath $taskJsonPath) -Message 'configure-all-users init task json was not found.'

    $taskText = [string](Get-Content -LiteralPath $taskPath -Raw)
    $taskJsonText = [string](Get-Content -LiteralPath $taskJsonPath -Raw)

    foreach ($fragment in @(
        'Init task started: configure-all-users',
        'Get-LocalUser',
        'CreateProfile',
        'NTUSER.DAT',
        'InteractiveMaterializationWaitSeconds = 20',
        'InteractiveMaterializationWaitSeconds)',
        'profile-ready:',
        'profile-materialized:',
        'configure-all-users-ready:',
        'AppData\Roaming',
        'Documents',
        'Downloads',
        'Desktop'
    )) {
        Assert-True -Condition ($taskText -like ('*' + [string]$fragment + '*')) -Message ("configure-all-users init task must include fragment '{0}'." -f [string]$fragment)
    }

    Assert-True -Condition ($taskJsonText -like '*"priority": 2*') -Message 'configure-all-users init task priority must stay 2.'
    Assert-True -Condition ($taskJsonText -like '*"timeout": 120*') -Message 'configure-all-users init task timeout must stay 120.'
    Assert-True -Condition ($taskJsonText -like '*01-ensure-local-user-accounts*') -Message 'configure-all-users init task must depend on local user creation.'
}

Invoke-Test -Name "Windows PowerShell remoting init and summary contract" -Action {
    $remotingTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage init -TaskName '06-configure-powershell-remoting'
    $remotingTaskJsonPath = Get-RepoTaskJsonPath -Platform windows -Stage init -TaskName '06-configure-powershell-remoting'
    $advancedTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '10001-configure-advanced-settings'
    $guestRuntimePath = Join-Path $RepoRoot 'modules\platform\clagnos-guest-runtime.ps1'
    $mainCommandPath = Join-Path $RepoRoot 'modules\commands\pipeline\clagnos-main-command.ps1'
    $platformDefaultsPath = Join-Path $RepoRoot 'modules\core\platform\clagnos-platform-defaults.ps1'
    $envExamplePath = Join-Path $RepoRoot '.env.example'

    Assert-True -Condition (Test-Path -LiteralPath $remotingTaskPath) -Message 'PowerShell remoting init task file was not found.'
    Assert-True -Condition (Test-Path -LiteralPath $remotingTaskJsonPath) -Message 'PowerShell remoting init task json was not found.'
    Assert-True -Condition (Test-Path -LiteralPath $advancedTaskPath) -Message 'Advanced settings task file was not found.'

    $remotingTaskText = [string](Get-Content -LiteralPath $remotingTaskPath -Raw)
    $remotingTaskJsonText = [string](Get-Content -LiteralPath $remotingTaskJsonPath -Raw)
    $advancedTaskText = [string](Get-Content -LiteralPath $advancedTaskPath -Raw)
    $guestRuntimeText = [string](Get-Content -LiteralPath $guestRuntimePath -Raw)
    $mainCommandText = [string](Get-Content -LiteralPath $mainCommandPath -Raw)
    $platformDefaultsText = [string](Get-Content -LiteralPath $platformDefaultsPath -Raw)
    $envExampleText = [string](Get-Content -LiteralPath $envExamplePath -Raw)

    foreach ($fragment in @(
        'Enable-PSRemoting -SkipNetworkProfileCheck -Force',
        '__VM_ADMIN_USER__',
        '__ASSISTANT_USER__',
        'Set-Service -Name WinRM -StartupType Automatic',
        'Start-Service -Name WinRM',
        'Remote Management Users',
        'LocalAccountTokenFilterPolicy',
        'WSMan:\localhost\Service\Auth\Basic',
        'WSMan:\localhost\Service\AllowUnencrypted',
        'Test-WSMan -ComputerName localhost',
        'powershell-remoting-group-ready:',
        'powershell-remoting-ready:'
    )) {
        Assert-True -Condition ($remotingTaskText -like ('*' + [string]$fragment + '*')) -Message ("PowerShell remoting init task must include fragment '{0}'." -f [string]$fragment)
    }

    Assert-True -Condition ($remotingTaskJsonText -like '*"priority": 7*') -Message 'PowerShell remoting init task priority must stay 7.'
    Assert-True -Condition ($remotingTaskJsonText -like '*"enabled": true*') -Message 'PowerShell remoting init task must remain enabled.'
    Assert-True -Condition ($remotingTaskJsonText -like '*05-configure-firewall-settings*') -Message 'PowerShell remoting init task must depend on firewall configuration.'
    Assert-True -Condition (($remotingTaskText -like "*Ensure-LocalGroupMember -GroupName 'Remote Management Users' -MemberName `$managerUser*") -and ($remotingTaskText -like "*Ensure-LocalGroupMember -GroupName 'Remote Management Users' -MemberName `$assistantUser*")) -Message 'PowerShell remoting init task must grant both managed users access.'
    Assert-True -Condition ($platformDefaultsText -like '*5985*') -Message 'Default TCP ports must include 5985 for WinRM.'
    Assert-True -Condition ($envExampleText -like '*5985*') -Message '.env.example TCP port defaults must include 5985 for WinRM.'

    foreach ($fragment in @(
        'PowerShell remoting commands:',
        'TrustedHostsCommand',
        'EnterPSSessionCommand',
        'InvokeCommand',
        'cg.cmd connect --powershell',
        '5985'
    )) {
        Assert-True -Condition (($guestRuntimeText + "`n" + $mainCommandText) -like ('*' + [string]$fragment + '*')) -Message ("Connection summary must include PowerShell remoting fragment '{0}'." -f [string]$fragment)
    }

    foreach ($fragment in @(
        'EnableLUA',
        'ConsentPromptBehaviorAdmin',
        'PromptOnSecureDesktop',
        'uac-silent-store-safe'
    )) {
        Assert-True -Condition ($advancedTaskText -like ('*' + [string]$fragment + '*')) -Message ("Advanced settings task must include fragment '{0}'." -f [string]$fragment)
    }
}

Invoke-Test -Name "Windows auto-start task applies the approved startup profile additively for manager and assistant" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '10002-configure-startup-settings'
    $taskJsonPath = Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '10002-configure-startup-settings'
    Assert-True -Condition (Test-Path -LiteralPath $taskPath) -Message "Expected auto-start task file was not found."
    $taskText = [string](Get-Content -LiteralPath $taskPath -Raw)
    $taskJsonText = [string](Get-Content -LiteralPath $taskJsonPath -Raw)
    $healthTaskPath = Get-RepoSummaryReadbackScriptPath -Platform windows
    $healthTaskText = [string](Get-Content -LiteralPath $healthTaskPath -Raw)
    $taskCatalog = Get-ClagnosTaskBlocksFromDirectory -DirectoryPath (Join-Path $RepoRoot 'windows\update') -Platform windows -Stage update
    $taskBlock = @($taskCatalog.ActiveTasks | Where-Object { [string]$_.Name -eq '10002-configure-startup-settings' } | Select-Object -First 1)[0]
    Assert-True -Condition ($null -ne $taskBlock) -Message 'Auto-start task must be discoverable from the Windows vm-update catalog.'
    Assert-True -Condition (Test-ClagnosTaskStartupProfileEnabled -TaskBlock $taskBlock) -Message 'Auto-start task must carry the startup-profile extension through task discovery.'
    $approvedProfileJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String((Get-ClagnosTaskStartupProfileJsonBase64 -TaskBlock $taskBlock)))
    $approvedProfileEntries = @(ConvertFrom-JsonObjectArrayCompat -InputObject $approvedProfileJson)
    $approvedProfileKeys = @($approvedProfileEntries | ForEach-Object { [string]$_.Key })

    foreach ($fragment in @(
        '__HOST_STARTUP_PROFILE_JSON_B64__',
        'host-startup-profile =>',
        'managed-startup-profile =>',
        'Get-ManagerContext',
        'Get-StartupUserContexts',
        'Get-StartupLocationDefinitions',
        'Get-MachineStartupLocationDefinitions',
        'Resolve-RequestedStartupLocation',
        'Resolve-StartupProfileEntrySpec',
        'Resolve-StartupProfileEntryTargetUsers',
        'Ensure-UserProfileMaterialized',
        'Clear-OwnedStartupArtifacts',
        'autostart-info-skip:',
        'autostart-profile-materialized:',
        'profile materialization did not complete within the bounded wait',
        'autostart-managed =>',
        'autostart-method =>',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run32',
        'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp',
        'Resolve-StartupProfileExecutablePath',
        'Resolve-StartupProfileStoreAppId',
        'shell:AppsFolder\',
        '$assistantUser = "__ASSISTANT_USER__"',
        '$assistantPassword = "__ASSISTANT_PASS__"',
        'configure-startup-settings-completed'
    )) {
        Assert-True -Condition ($taskText -like ('*' + $fragment + '*')) -Message ("Auto-start task must include fragment '{0}'." -f $fragment)
    }
    Assert-True -Condition (($taskText.IndexOf('static-startup-snapshot =>', [System.StringComparison]::Ordinal)) -lt 0) -Message "Auto-start task must not keep the static startup snapshot contract."
    Assert-True -Condition (($taskText.IndexOf('autostart-cleared: host-disabled-or-absent', [System.StringComparison]::Ordinal)) -lt 0) -Message 'Auto-start task must stay additive and must not clear managed startup entries when the host profile omits them.'
    Assert-True -Condition (($taskText.IndexOf('unsupported host app key', [System.StringComparison]::OrdinalIgnoreCase)) -lt 0) -Message 'Auto-start task must not warn about unsupported host app keys.'
    Assert-True -Condition (($taskText.IndexOf('windscribe', [System.StringComparison]::OrdinalIgnoreCase)) -lt 0) -Message 'Auto-start task must no longer manage Windscribe.'
    Assert-True -Condition (($taskText.IndexOf('codex-app', [System.StringComparison]::OrdinalIgnoreCase)) -lt 0) -Message 'Auto-start task must no longer manage the Codex app.'
    Assert-True -Condition ($taskJsonText -like '*"timeout": 120*') -Message 'Auto-start task must keep the expanded timeout 120.'
    Assert-True -Condition ($taskJsonText -like '*clagnos-interactive-session-helper.ps1*') -Message 'Auto-start task must publish the interactive helper asset for assistant profile materialization.'
    Assert-True -Condition ($taskJsonText -like '*"startupProfile"*') -Message 'Auto-start task must declare the startup-profile extension in task.json.'
    Assert-True -Condition ($taskJsonText -like '*"sourcePath": "extensions/startup-profile.json"*') -Message 'Auto-start task must point the startup-profile extension to extensions/startup-profile.json.'
    foreach ($requiredKey in @('docker-desktop','microsoft-lists','onedrive','teams','ollama','send-to-onenote','itunes-helper','jaws','security-health','anydesk','whatsapp','icloud','google-drive','m365-copilot')) {
        Assert-True -Condition ($approvedProfileKeys -contains $requiredKey) -Message ("Auto-start startup profile must include '{0}'." -f [string]$requiredKey)
    }
    Assert-True -Condition (-not ($approvedProfileKeys -contains '1password')) -Message 'Auto-start startup profile must exclude 1Password.'

    foreach ($fragment in @(
        'AUTO-START APP STATUS:',
        '__HOST_STARTUP_PROFILE_JSON_B64__',
        'host-startup-profile =>',
        'managed-startup-profile =>',
        'startup-entry =>',
        'missing-startup-entry =>',
        'unsupported-startup-key =>',
        'Docker Desktop',
        'Ollama',
        'OneDrive',
        'Teams',
        'iTunesHelper',
        'JAWS',
        'Write-JawsSettingsStatus -Label ''manager''',
        'Write-JawsSettingsStatus -Label ''assistant''',
        'Registry::HKEY_LOCAL_MACHINE\Software\Freedom Scientific',
        'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Freedom Scientific',
        'Write-JawsUserRegistryStatus -UserName $managerUser',
        'Write-JawsUserRegistryStatus -UserName $assistantUser',
        'jaws-winget-probe =>',
        'jaws-exe-present =>'
    )) {
        Assert-True -Condition ($healthTaskText -like ('*' + $fragment + '*')) -Message ("Health snapshot must include startup fragment '{0}'." -f $fragment)
    }
    Assert-True -Condition (($healthTaskText.IndexOf('Get-ManagerContext', [System.StringComparison]::Ordinal)) -ge 0) -Message "Health snapshot must read manager-scope startup locations through the manager hive."
    Assert-True -Condition (($healthTaskText.IndexOf('ollama-api-version-response => {{"version":"{0}"}}', [System.StringComparison]::Ordinal)) -ge 0) -Message "Health snapshot must escape literal JSON braces when formatting the Ollama API version response."
    Assert-True -Condition (($healthTaskText.IndexOf('$ollamaApiWaitSeconds = if ($null -ne $ollamaStartupShortcutHealth -and [bool]$ollamaStartupShortcutHealth.Healthy) { 180 } else { 20 }', [System.StringComparison]::Ordinal)) -ge 0) -Message "Health snapshot must extend the Ollama API wait when the managed startup shortcut is already healthy."
    Assert-True -Condition (($healthTaskText.IndexOf('if (-not [bool]$ollamaCliResult.Success -and -not [string]::IsNullOrWhiteSpace([string]$ollamaApiVersion) -and -not [string]::IsNullOrWhiteSpace([string]$ollamaExe)) {', [System.StringComparison]::Ordinal)) -ge 0) -Message "Health snapshot must rerun ollama ls after the API becomes reachable."
}

Invoke-Test -Name "Windows language task and health contract" -Action {
    $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '136-configure-language-settings'
    $taskJsonPath = Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '136-configure-language-settings'
    $healthTaskPath = Get-RepoSummaryReadbackScriptPath -Platform windows

    Assert-True -Condition (Test-Path -LiteralPath $taskPath) -Message 'Language settings task file was not found.'
    Assert-True -Condition (Test-Path -LiteralPath $taskJsonPath) -Message 'Language settings task json was not found.'

    $taskText = [string](Get-Content -LiteralPath $taskPath -Raw)
    $taskJsonText = [string](Get-Content -LiteralPath $taskJsonPath -Raw)
    $healthTaskText = [string](Get-Content -LiteralPath $healthTaskPath -Raw)

    foreach ($fragment in @(
        'Install-Language',
        'Get-WindowsCapability',
        'Language.Basic',
        'InstallPending',
        'Test-LanguageCapabilityDeferredVerificationAllowed',
        'QueuedInstallAccepted',
        'Set-SystemPreferredUILanguage',
        'Set-WinUILanguageOverride',
        'Set-WinUserLanguageList',
        'tr-TR',
        'en-US',
        'TASK_REBOOT_REQUIRED:configure-language-settings',
        'language-step-ok: restart-required-to-finalize',
        'Applying system preferred UI language',
        'Collecting final language verification output',
        'language-capabilities-final => {0} => {1}',
        'language-capabilities-deferred => {0} => {1}',
        'Assert-LanguageStateReadyForRestart',
        'Assert-LanguageStateReadyForRestart -ComponentResults $systemLanguageState.ComponentResults',
        'direct apply for ''{0}'' is queued and will finish after the next restart or sign-in.'
    )) {
        Assert-True -Condition ($taskText -like ('*' + [string]$fragment + '*')) -Message ("Language settings task must include fragment '{0}'." -f [string]$fragment)
    }

    foreach ($removedFragment in @(
        'Set-WinDefaultInputMethodOverride',
        'Set-WinCultureFromLanguageListOptOut',
        'Set-Culture',
        'Set-WinHomeLocation',
        'Set-WinSystemLocale',
        'Set-TimeZone',
        'Copy-UserInternationalSettingsToSystem'
    )) {
        Assert-True -Condition (-not ($taskText -like ('*' + [string]$removedFragment + '*'))) -Message ("Language settings task must no longer own '{0}'." -f [string]$removedFragment)
    }

    Assert-True -Condition ($taskJsonText -like '*"timeout": 1635*') -Message 'Language settings task must keep the normalized timeout 1635.'
    Assert-True -Condition ($taskText -like '*-WaitTimeoutSeconds 120*') -Message 'Language settings task must short-circuit the SYSTEM language worker after the reduced bounded wait.'
    Assert-True -Condition ($taskText -like '*interactive-worker-timeout-recovered=true*') -Message 'Language settings task must recover timeout cases when capability state is already satisfied.'
    Assert-True -Condition ($taskText -like '*interactive-worker-queued=true*') -Message 'Language settings task must accept the queued background install state when the SYSTEM worker is still running at timeout.'
    Assert-True -Condition ($taskText -like '*$queuedInstallAccepted = (*') -Message 'Language settings task must explicitly preserve the queued-install verification path after the interactive worker returns.'
    Assert-True -Condition (-not ($taskJsonText -like '*"appState"*')) -Message 'Language settings task must stay out of task-local app-state snapshot and restore.'

    foreach ($fragment in @(
        'LANGUAGE AND REGION STATUS:',
        'system-preferred-ui-language =>',
        'system-locale =>',
        'time-zone =>',
        'utf8-codepage-acp =>',
        'utf8-codepage-oemcp =>',
        'installed-language => {0} =>',
        'Write-InstalledLanguageStatus -LanguageTag ''en-US''',
        'Write-InstalledLanguageStatus -LanguageTag ''tr-TR''',
        'user-language-status => {0} =>',
        'default-input={7}',
        'Write-UserLanguageStatus -UserName $managerUser -UserPassword $managerPassword',
        'Write-UserLanguageStatus -UserName $assistantUser -UserPassword $assistantPassword',
        'welcome-screen-language =>',
        'new-user-language =>',
        'installed=pending; features='
    )) {
        Assert-True -Condition ($healthTaskText -like ('*' + [string]$fragment + '*')) -Message ("Health snapshot must include language fragment '{0}'." -f [string]$fragment)
    }

    $uxTaskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName '10004-configure-windows-experience'
    $uxTaskJsonPath = Get-RepoTaskJsonPath -Platform windows -Stage update -TaskName '10004-configure-windows-experience'
    $uxTaskText = [string](Get-Content -LiteralPath $uxTaskPath -Raw)
    $uxTaskJsonText = [string](Get-Content -LiteralPath $uxTaskJsonPath -Raw)

    foreach ($fragment in @(
        'Set-WinDefaultInputMethodOverride',
        'Set-WinCultureFromLanguageListOptOut',
        'Set-Culture',
        'Set-WinHomeLocation',
        'Set-WinSystemLocale',
        '$systemLocaleTarget = ''en-US''',
        'Set-TimeZone',
        'Copy-UserInternationalSettingsToSystem',
        'TASK_REBOOT_REQUIRED:configure-windows-experience',
        'regional-current-user-begin',
        'regional-assistant-start:',
        'regional-culture-effective:',
        'registry-preload-skip:',
        'registry-time-format-skip:'
    )) {
        Assert-True -Condition ($uxTaskText -like ('*' + [string]$fragment + '*')) -Message ("UX task must now own regional fragment '{0}'." -f [string]$fragment)
    }
    Assert-True -Condition (-not ($uxTaskText -like '*Set-WinSystemLocale -SystemLocale $turkishCulture*')) -Message 'UX task must no longer target tr-TR as the system locale.'
    Assert-True -Condition (-not ($uxTaskText -like '*Culture verification failed*')) -Message 'UX task must not rely on same-session Get-Culture verification that drifts during the mixed locale flow.'

    Assert-True -Condition ($uxTaskJsonText -like '*"timeout": 180*') -Message 'UX task must keep the expanded regional-input timeout 180.'
}

Invoke-Test -Name "Windows install tasks short-circuit healthy installs and avoid forceful package reinstalls" -Action {
    $expectedHealthySkipFragments = [ordered]@{
        '02-install-winget-tool.ps1' = @('Existing winget installation is already healthy. Skipping bootstrap download.', 'https://aka.ms/getwinget', 'Microsoft.DesktopAppInstaller', 'Skipping forceful source reset and attempting one bounded source update.')
        '03-install-chrome-application.ps1' = @('Google Chrome executable already exists:', 'choco install googlechrome')
        '101-install-powershell-tool.ps1' = @('Existing PowerShell 7 installation is already healthy. Skipping choco install.')
        '102-install-git-tool.ps1' = @('Existing Git installation is already healthy. Skipping choco install.', 'choco install git')
        '103-install-python-tool.ps1' = @('Existing Python installation is already healthy. Skipping choco install.', 'choco install python312')
        '104-install-node-tool.ps1' = @('Existing Node.js installation is already healthy. Skipping choco install.', 'choco install nodejs-lts')
        '105-install-azure-cli-tool.ps1' = @('Existing Azure CLI installation is already healthy:', 'choco install azure-cli')
        '107-install-gh-tool.ps1' = @('Existing GitHub CLI installation is already healthy. Skipping choco install.')
        '106-install-7zip-tool.ps1' = @('Existing 7-Zip installation is already healthy. Skipping choco install.')
        '133-install-sysinternals-tool.ps1' = @('Existing Sysinternals installation is already healthy:', 'choco install sysinternals')
        '109-install-ffmpeg-tool.ps1' = @('Existing FFmpeg installation is already healthy. Skipping choco install.')
        '135-install-ollama-tool.ps1' = @('Existing Ollama installation is already healthy. Skipping choco install.', 'choco install ollama')
        '112-install-azd-tool.ps1' = @('Existing azd installation is already healthy. Skipping winget install.')
        '118-install-teams-application.ps1' = @('Existing Microsoft Teams installation is already healthy. Skipping winget install.')
        '122-install-anydesk-application.ps1' = @('Existing AnyDesk installation is already healthy', 'function Test-AnyDeskInstalled')
        '123-install-windscribe-application.ps1' = @('Existing Windscribe installation is already healthy. Skipping winget install.', 'function Test-WindscribeInstalled')
        '131-install-jaws-application.ps1' = @('Existing JAWS installation is already healthy. Skipping winget install.', 'FreedomScientific.JAWS.2025', 'jfw.exe')
        '129-configure-unlocker-settings.ps1' = @('unlocker-settings-skip => IObit Unlocker is not installed')
    }

    foreach ($entry in $expectedHealthySkipFragments.GetEnumerator()) {
        $taskPath = Get-RepoTaskScriptPath -Platform windows -Stage update -TaskName ([System.IO.Path]::GetFileNameWithoutExtension([string]$entry.Key))
        $taskText = [string](Get-Content -LiteralPath $taskPath -Raw)
        foreach ($fragment in @($entry.Value)) {
            Assert-True -Condition ($taskText -like ('*' + [string]$fragment + '*')) -Message ("Task '{0}' must include fragment '{1}'." -f [string]$entry.Key, [string]$fragment)
        }
    }

    foreach ($taskPath in @(
        Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'windows\update') -Recurse -Filter '*.ps1' -File -ErrorAction Stop |
            Where-Object { [string]$_.BaseName -eq [string](Split-Path -Path $_.DirectoryName -Leaf) }
    )) {
        $taskText = [string](Get-Content -LiteralPath $taskPath.FullName -Raw)
        Assert-True -Condition (-not ($taskText -match 'winget\s+install[^\r\n]{0,240}--force')) -Message ("Task '{0}' must not pass --force to winget install." -f $taskPath.Name)
        Assert-True -Condition (-not ($taskText -match 'choco\s+upgrade\s+\S+')) -Message ("Task '{0}' must not use choco upgrade for package install semantics." -f $taskPath.Name)
        Assert-True -Condition (($taskText.IndexOf('--force', [System.StringComparison]::Ordinal)) -lt 0) -Message ("Task '{0}' must not pass any --force flag in vm-update." -f $taskPath.Name)
    }
}

Invoke-Test -Name "Tracked tree omits legacy local-only accessibility residue" -Action {
    $smokeTestPath = Join-Path $RepoRoot 'tests\clagnos-smoke-tests.ps1'
    $trackedRelativePaths = @()
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        $trackedRelativePaths = @(
            & $gitCommand.Source -C $RepoRoot ls-files --cached --others --exclude-standard
        )
    }

    $repoFiles = @()
    foreach ($relativePath in @($trackedRelativePaths)) {
        $relativeText = [string]$relativePath
        if ([string]::IsNullOrWhiteSpace([string]$relativeText)) {
            continue
        }
        if ($relativeText.StartsWith('.git/', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($relativeText.StartsWith('windows/update/local/', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if ($relativeText.StartsWith('windows/init/local/', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $absolutePath = Join-Path $RepoRoot $relativeText
        if ([string]::Equals([string]$absolutePath, [string]$smokeTestPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (Test-Path -LiteralPath $absolutePath -PathType Leaf) {
            $repoFiles += [string]$absolutePath
        }
    }

    $legacyNeedles = @(
        'legacy-accessibility-reader',
        'legacy-local-shortcut-hotkey',
        'legacy-accessibility-launcher.exe',
        'legacy-accessibility-files'
    )

    foreach ($needle in @($legacyNeedles)) {
        $matchingFiles = New-Object 'System.Collections.Generic.List[string]'
        foreach ($file in @($repoFiles)) {
            $fileText = ''
            try {
                $fileText = [string](Get-Content -LiteralPath $file -Raw -ErrorAction Stop)
            }
            catch {
                $fileText = ''
            }

            if (-not [string]::IsNullOrEmpty([string]$fileText) -and $fileText.IndexOf([string]$needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                [void]$matchingFiles.Add([string]$file)
            }
        }

        Assert-True -Condition ($matchingFiles.Count -eq 0) -Message ("Tracked tree must not keep legacy local-only accessibility residue for needle '{0}'. Matches: {1}" -f [string]$needle, ($matchingFiles -join ', '))
    }
}

Invoke-Test -Name "Be My Eyes task publishes interactive helper asset" -Action {
    $context = [ordered]@{
        VM_NAME = 'samplevm'
        VM_ADMIN_USER = 'manager'
        VM_ADMIN_PASS = '<runtime-secret>'
        ASSISTANT_USER = 'assistant'
        ASSISTANT_PASS = '<runtime-secret>'
        SSH_PORT = '22'
        RDP_PORT = '3389'
    }

    $resolvedTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @(
        (New-RepoTaskTemplate -Platform windows -Stage update -TaskName '126-install-be-my-eyes-application' -TimeoutSeconds 300)
    ) -Context $context)[0]
    $assetCopies = @($resolvedTask.AssetCopies)
    Assert-True -Condition ([string]$resolvedTask.Script -like '*clagnos-store-install-state.psm1*') -Message "Be My Eyes task must import the shared Store helper asset."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*Invoke-ClagnosInteractiveDesktopAutomation*') -Message "Be My Eyes task must call the interactive helper."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*Wait-ClagnosUserInteractiveDesktopReady*') -Message "Be My Eyes task must wait briefly for the manager desktop when autologon is already configured."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*New-ClagnosInteractiveDesktopBlockMessage*') -Message "Be My Eyes task must classify blocked interactive-desktop states with the shared helper."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*cannot be deferred to a later boot*') -Message "Be My Eyes task must fail explicitly instead of scheduling a deferred install."
    Assert-True -Condition ($assetCopies.Count -ge 2) -Message "Be My Eyes task must materialize helper assets."
}

Invoke-Test -Name "iCloud task publishes interactive helper asset" -Action {
    $context = [ordered]@{
        VM_NAME = 'samplevm'
        VM_ADMIN_USER = 'manager'
        VM_ADMIN_PASS = '<runtime-secret>'
        ASSISTANT_USER = 'assistant'
        ASSISTANT_PASS = '<runtime-secret>'
        SSH_PORT = '22'
        RDP_PORT = '3389'
    }

    $resolvedTask = @(Resolve-ClagnosRuntimeTaskBlocks -TemplateTaskBlocks @(
        (New-RepoTaskTemplate -Platform windows -Stage update -TaskName '131-install-icloud-application' -TimeoutSeconds 300)
    ) -Context $context)[0]
    $assetCopies = @($resolvedTask.AssetCopies)
    Assert-True -Condition ([string]$resolvedTask.Script -like '*clagnos-store-install-state.psm1*') -Message "iCloud task must import the shared Store helper asset."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*Invoke-ClagnosInteractiveDesktopAutomation*') -Message "iCloud task must call the interactive helper."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*Wait-ClagnosUserInteractiveDesktopReady*') -Message "iCloud task must wait briefly for the manager desktop when autologon is already configured."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*New-ClagnosInteractiveDesktopBlockMessage*') -Message "iCloud task must classify blocked interactive-desktop states with the shared helper."
    Assert-True -Condition ([string]$resolvedTask.Script -like '*cannot be deferred to a later boot*') -Message "iCloud task must fail explicitly instead of scheduling a deferred install."
    Assert-True -Condition ($assetCopies.Count -ge 2) -Message "iCloud task must materialize helper assets."
}

$historyTestDirectory = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath([string]$script:ClagnosTaskHistoryPathOverride))
$tempHistoryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if (-not $historyTestDirectory.StartsWith(($tempHistoryRoot + 'clagnos-smoke-history-'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw ("Refusing to remove unexpected smoke history path: {0}" -f $historyTestDirectory)
}
if (Test-Path -LiteralPath $historyTestDirectory) { Remove-Item -LiteralPath $historyTestDirectory -Recurse -Force }

Write-Host ""
Write-Host ("Compatibility smoke summary -> Passed: {0}, Failed: {1}" -f $passCount, $failCount)
if ($failCount -gt 0) {
    exit 1
}



