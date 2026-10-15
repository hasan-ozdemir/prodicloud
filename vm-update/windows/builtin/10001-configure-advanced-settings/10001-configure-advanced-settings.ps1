$ErrorActionPreference = "Stop"
Write-Host "Update task started: configure-advanced-settings"

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [Microsoft.Win32.RegistryValueKind]$Kind
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Kind -Force | Out-Null
}

function Assert-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$ExpectedValue
    )

    $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
    $actualValue = $item.$Name
    if ([string]$actualValue -ne [string]$ExpectedValue) {
        throw ("Registry validation failed: {0}\{1} expected '{2}' but got '{3}'." -f $Path, $Name, $ExpectedValue, $actualValue)
    }
}

function Invoke-BcdEdit {
    param(
        [string[]]$Arguments,
        [string]$FailureContext
    )

    $output = @(& bcdedit.exe @Arguments 2>&1)
    $exitCode = [int]$LASTEXITCODE
    if ($exitCode -ne 0) {
        $detail = [string]((@($output) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' | ')
        if ([string]::IsNullOrWhiteSpace([string]$detail)) {
            throw ("bcdedit failed for {0} with exit code {1}." -f $FailureContext, $exitCode)
        }

        throw ("bcdedit failed for {0} with exit code {1}. detail: {2}" -f $FailureContext, $exitCode, $detail)
    }

    return @($output | ForEach-Object { [string]$_ })
}

function Get-BcdEditText {
    param(
        [string[]]$Arguments,
        [string]$FailureContext
    )

    return [string]((Invoke-BcdEdit -Arguments $Arguments -FailureContext $FailureContext) -join "`n")
}

function Ensure-BcdTimeoutZero {
    $bootManagerText = Get-BcdEditText -Arguments @('/enum', '{bootmgr}') -FailureContext 'boot manager readback'
    if ($bootManagerText -notmatch '(?im)^\s*timeout\s+0\b') {
        $null = Invoke-BcdEdit -Arguments @('/timeout', '0') -FailureContext 'boot timeout update'
    }

    $verifiedText = Get-BcdEditText -Arguments @('/enum', '{bootmgr}') -FailureContext 'boot manager verification'
    if ($verifiedText -notmatch '(?im)^\s*timeout\s+0\b') {
        throw 'bcdedit verification failed: boot timeout is not 0.'
    }

    Write-Host 'advanced-step-ok: boot-timeout-zero'
}

function Ensure-BcdDepAlwaysOff {
    $currentLoaderText = Get-BcdEditText -Arguments @('/enum', '{current}') -FailureContext 'current boot entry readback'
    if ($currentLoaderText -notmatch '(?im)^\s*nx\s+AlwaysOff\b') {
        $null = Invoke-BcdEdit -Arguments @('/set', '{current}', 'nx', 'AlwaysOff') -FailureContext 'DEP update'
    }

    $verifiedText = Get-BcdEditText -Arguments @('/enum', '{current}') -FailureContext 'DEP verification'
    if ($verifiedText -notmatch '(?im)^\s*nx\s+AlwaysOff\b') {
        throw 'bcdedit verification failed: DEP is not AlwaysOff.'
    }

    Write-Host 'advanced-step-ok: dep-always-off'
}

function Ensure-StoreSafeSilentUac {
    $uacPolicyPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Set-RegistryValue -Path $uacPolicyPath -Name 'EnableLUA' -Value 1 -Kind DWord
    Set-RegistryValue -Path $uacPolicyPath -Name 'ConsentPromptBehaviorAdmin' -Value 0 -Kind DWord
    Set-RegistryValue -Path $uacPolicyPath -Name 'PromptOnSecureDesktop' -Value 0 -Kind DWord

    Assert-RegistryValue -Path $uacPolicyPath -Name 'EnableLUA' -ExpectedValue 1
    Assert-RegistryValue -Path $uacPolicyPath -Name 'ConsentPromptBehaviorAdmin' -ExpectedValue 0
    Assert-RegistryValue -Path $uacPolicyPath -Name 'PromptOnSecureDesktop' -ExpectedValue 0
    Write-Host 'advanced-step-ok: uac-silent-store-safe'
}

$visualEffectsPath = "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
Set-RegistryValue -Path $visualEffectsPath -Name "VisualFXSetting" -Value 2 -Kind DWord
Write-Host "advanced-step-ok: visual-effects-best-performance"

$priorityControlPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\PriorityControl"
Set-RegistryValue -Path $priorityControlPath -Name "Win32PrioritySeparation" -Value 24 -Kind DWord
Write-Host "advanced-step-ok: processor-background-services"

$memoryManagementPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
Set-RegistryValue -Path $memoryManagementPath -Name "PagingFiles" -Value "C:\pagefile.sys 800 8192" -Kind MultiString
Set-RegistryValue -Path $memoryManagementPath -Name "ExistingPageFiles" -Value "\??\C:\pagefile.sys" -Kind MultiString
Set-RegistryValue -Path $memoryManagementPath -Name "TempPageFile" -Value 0 -Kind DWord
Write-Host "advanced-step-ok: custom-pagefile-800-8192"

$crashControlPath = "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CrashControl"
Set-RegistryValue -Path $crashControlPath -Name "CrashDumpEnabled" -Value 0 -Kind DWord
Set-RegistryValue -Path $crashControlPath -Name "AlwaysKeepMemoryDump" -Value 0 -Kind DWord
Set-RegistryValue -Path $crashControlPath -Name "LogEvent" -Value 0 -Kind DWord
Set-RegistryValue -Path $crashControlPath -Name "SendAlert" -Value 0 -Kind DWord
Write-Host "advanced-step-ok: crash-dumps-disabled"

Ensure-BcdTimeoutZero
Ensure-BcdDepAlwaysOff
Ensure-StoreSafeSilentUac

Assert-RegistryValue -Path $visualEffectsPath -Name "VisualFXSetting" -ExpectedValue 2
Assert-RegistryValue -Path $priorityControlPath -Name "Win32PrioritySeparation" -ExpectedValue 24
Assert-RegistryValue -Path $memoryManagementPath -Name "TempPageFile" -ExpectedValue 0
Assert-RegistryValue -Path $crashControlPath -Name "CrashDumpEnabled" -ExpectedValue 0

Write-Host "configure-advanced-settings-completed"
Write-Host "Update task completed: configure-advanced-settings"
