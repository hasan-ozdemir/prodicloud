$ErrorActionPreference = "Stop"
Write-Host "Update task started: configure-autologon-settings"

$vmAdminUser = "__VM_ADMIN_USER__"
$vmAdminPass = "__VM_ADMIN_PASS__"
$taskConfig = [ordered]@{
    WinlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    WinlogonNativePath = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    AutologonCandidates = @(
        'C:\ProgramData\chocolatey\lib\sysinternals\tools\Autologon.exe',
        'C:\ProgramData\chocolatey\lib\sysinternals\tools\Autologon64.exe',
        'C:\ProgramData\chocolatey\bin\Autologon.exe',
        'C:\ProgramData\chocolatey\bin\autologon.exe'
    )
}

Import-Module 'C:\Windows\Temp\clagnos-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ClagnosSessionPath | Out-Null
}

function Test-PlaceholderValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return $true
    }

    $normalized = $Value.Trim().ToLowerInvariant()
    return (
        $normalized.Contains('change_me') -or
        $normalized.Contains('changeme') -or
        $normalized.Contains('replace_me') -or
        $normalized.Contains('set_me') -or
        $normalized.Contains('todo') -or
        $normalized.StartsWith('<') -or
        $normalized.EndsWith('>')
    )
}

function Resolve-AutologonExe {
    foreach ($candidate in @($taskConfig.AutologonCandidates)) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    $chocoToolsDir = 'C:\ProgramData\chocolatey\lib\sysinternals\tools'
    if (Test-Path -LiteralPath $chocoToolsDir) {
        $match = Get-ChildItem -LiteralPath $chocoToolsDir -Filter 'Autologon*.exe' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
        if ($match -and (Test-Path -LiteralPath $match.FullName)) {
            return [string]$match.FullName
        }
    }

    $cmd = Get-Command autologon -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ''
}

if (-not ([System.Management.Automation.PSTypeName]'ClagnosWin32LogonNative').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ClagnosWin32LogonNative {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool LogonUser(
        string lpszUsername,
        string lpszDomain,
        string lpszPassword,
        int dwLogonType,
        int dwLogonProvider,
        out IntPtr phToken
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr hObject);
}
'@
}

function Assert-LocalCredentialValid {
    param(
        [string]$UserName,
        [string]$Password
    )

    $tokenHandle = [IntPtr]::Zero
    $logonOk = [ClagnosWin32LogonNative]::LogonUser([string]$UserName, '.', [string]$Password, 2, 0, [ref]$tokenHandle)
    if ($tokenHandle -ne [IntPtr]::Zero) {
        [void][ClagnosWin32LogonNative]::CloseHandle($tokenHandle)
    }

    if (-not $logonOk) {
        $win32Error = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw ("Local credential validation for user '{0}' failed with Win32 error {1}." -f [string]$UserName, $win32Error)
    }
}

function Get-AutologonState {
    $baseKey = $null
    $winlogonKey = $null
    try {
        $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
        $winlogonKey = $baseKey.OpenSubKey('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon')
        if ($null -eq $winlogonKey) {
            throw "Winlogon registry key was not found in the 64-bit registry view."
        }

        $autoAdminLogon = [string]$winlogonKey.GetValue('AutoAdminLogon', '')
        $defaultUserName = [string]$winlogonKey.GetValue('DefaultUserName', '')
        $defaultDomainName = [string]$winlogonKey.GetValue('DefaultDomainName', '')
        $defaultPassword = [string]$winlogonKey.GetValue('DefaultPassword', '')

        return [pscustomobject]@{
            AutoAdminLogon = [string]$autoAdminLogon
            DefaultUserName = [string]$defaultUserName
            DefaultDomainName = [string]$defaultDomainName
            DefaultPasswordPresent = (-not [string]::IsNullOrWhiteSpace([string]$defaultPassword))
        }
    }
    finally {
        if ($null -ne $winlogonKey) {
            $winlogonKey.Close()
        }

        if ($null -ne $baseKey) {
            $baseKey.Close()
        }
    }
}

function Set-WinlogonStringValue {
    param(
        [string]$Name,
        [string]$Value
    )

    $regOutput = & reg.exe add ([string]$taskConfig.WinlogonNativePath) /v ([string]$Name) /t REG_SZ /d ([string]$Value) /f /reg:64 2>&1
    $regExitCode = [int]$LASTEXITCODE
    if ($regExitCode -ne 0) {
        throw ("Failed to set Winlogon value '{0}'. reg.exe exit code={1}. Output: {2}" -f [string]$Name, $regExitCode, ((@($regOutput) | ForEach-Object { [string]$_ }) -join ' '))
    }
}

function Sync-WinlogonAutologonState {
    param(
        [string]$UserName,
        [string]$Password
    )

    Set-WinlogonStringValue -Name 'AutoAdminLogon' -Value '1'
    Set-WinlogonStringValue -Name 'DefaultUserName' -Value ([string]$UserName)
    Set-WinlogonStringValue -Name 'DefaultDomainName' -Value '.'
    Set-WinlogonStringValue -Name 'DefaultPassword' -Value ([string]$Password)
    Write-Host "winlogon-sync => AutoAdminLogon, DefaultUserName, DefaultDomainName, DefaultPassword"
}

function Assert-AutologonConfigured {
    param([string]$ExpectedUserName)

    $state = Get-AutologonState
    if (-not [string]::Equals([string]$state.AutoAdminLogon, '1', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Autologon verification failed: AutoAdminLogon is not enabled."
    }

    if (-not [string]::Equals([string]$state.DefaultUserName, [string]$ExpectedUserName, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Autologon verification failed: DefaultUserName '{0}' does not match '{1}'." -f [string]$state.DefaultUserName, [string]$ExpectedUserName)
    }

    if ([string]::IsNullOrWhiteSpace([string]$state.DefaultDomainName)) {
        throw "Autologon verification failed: DefaultDomainName is empty."
    }

    $expectedDomains = @('.', $env:COMPUTERNAME)
    $domainMatch = $false
    foreach ($expectedDomain in @($expectedDomains)) {
        if ([string]::Equals([string]$state.DefaultDomainName, [string]$expectedDomain, [System.StringComparison]::OrdinalIgnoreCase)) {
            $domainMatch = $true
            break
        }
    }

    if (-not $domainMatch) {
        throw ("Autologon verification failed: DefaultDomainName '{0}' does not match '.' or '{1}'." -f [string]$state.DefaultDomainName, [string]$env:COMPUTERNAME)
    }

    Write-Host ("autologon-state => AutoAdminLogon={0}; DefaultUserName={1}; DefaultDomainName={2}; DefaultPasswordPresent={3}" -f [string]$state.AutoAdminLogon, [string]$state.DefaultUserName, [string]$state.DefaultDomainName, [bool]$state.DefaultPasswordPresent)
    if (-not [bool]$state.DefaultPasswordPresent) {
        Write-Host "Autologon note: DefaultPassword is not present in Winlogon. Sysinternals Autologon can store the credential outside the visible Winlogon value while keeping autologon enabled."
    }
}

function Get-InteractiveLogonReadiness {
    param([string]$ExpectedUserName)

    $activeUser = ''
    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        $activeUser = [string]$computerSystem.UserName
    }
    catch {
        $activeUser = ''
    }

    $candidateUsers = @(
        [string]$ExpectedUserName,
        ('.\' + [string]$ExpectedUserName),
        ($env:COMPUTERNAME + '\' + [string]$ExpectedUserName)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }

    $userMatch = $false
    foreach ($candidateUser in @($candidateUsers)) {
        if ([string]::Equals([string]$activeUser, [string]$candidateUser, [System.StringComparison]::OrdinalIgnoreCase)) {
            $userMatch = $true
            break
        }
    }

    $explorerReady = $false
    try {
        $explorerOwners = @(
            Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $owner = Invoke-CimMethod -InputObject $_ -MethodName GetOwner -ErrorAction SilentlyContinue
                    if ($null -eq $owner -or [string]::IsNullOrWhiteSpace([string]$owner.User)) {
                        return
                    }

                    if ([string]::IsNullOrWhiteSpace([string]$owner.Domain)) {
                        return [string]$owner.User
                    }

                    return ("{0}\{1}" -f [string]$owner.Domain, [string]$owner.User)
                } |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        )
        foreach ($explorerOwner in @($explorerOwners)) {
            foreach ($candidateUser in @($candidateUsers)) {
                if ([string]::Equals([string]$explorerOwner, [string]$candidateUser, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $explorerReady = $true
                    break
                }
            }
            if ($explorerReady) {
                break
            }
        }
    }
    catch {
        $explorerReady = $false
    }

    return [pscustomobject]@{
        Ready = ([bool]$userMatch -and [bool]$explorerReady)
        ActiveUser = [string]$activeUser
        UserMatch = [bool]$userMatch
        ExplorerReady = [bool]$explorerReady
    }
}

if (Test-PlaceholderValue -Value $vmAdminUser) {
    throw "VM_ADMIN_USER is required and must not be empty or a placeholder."
}
if (Test-PlaceholderValue -Value $vmAdminPass) {
    throw "VM_ADMIN_PASS is required and must not be empty or a placeholder."
}

Refresh-SessionPath
$autologonExe = Resolve-AutologonExe
if ([string]::IsNullOrWhiteSpace([string]$autologonExe)) {
    throw "autologon.exe was not found. Install the Sysinternals package from the builtin package catalog first."
}

Assert-LocalCredentialValid -UserName $vmAdminUser -Password $vmAdminPass

Write-Host ("Resolved autologon executable: {0}" -f [string]$autologonExe)
Write-Host ("Running: {0} /accepteula {1} . <redacted>" -f [string]$autologonExe, [string]$vmAdminUser)
$autologonOutput = & $autologonExe /accepteula $vmAdminUser '.' $vmAdminPass 2>&1
$autologonExit = [int]$LASTEXITCODE
$filteredAutologonOutput = @(
    @($autologonOutput) |
        Where-Object {
            $line = [string]$_
            (-not [string]::Equals($line, "'wmic' is not recognized as an internal or external command,", [System.StringComparison]::OrdinalIgnoreCase)) -and
            (-not [string]::Equals($line, 'operable program or batch file.', [System.StringComparison]::OrdinalIgnoreCase))
        }
)
if (@($filteredAutologonOutput).Count -ne @($autologonOutput).Count) {
    Write-Host "Autologon emitted legacy WMIC lookup output; continuing because the tool completed and registry state will be validated."
}
if (@($filteredAutologonOutput).Count -gt 0) {
    $filteredAutologonOutput | ForEach-Object { Write-Host ([string]$_) }
}

if ($autologonExit -ne 0) {
    throw ("autologon exited with code {0}." -f $autologonExit)
}

Sync-WinlogonAutologonState -UserName $vmAdminUser -Password $vmAdminPass
Start-Sleep -Seconds 1
Assert-AutologonConfigured -ExpectedUserName $vmAdminUser
$interactiveLogonReadiness = Get-InteractiveLogonReadiness -ExpectedUserName $vmAdminUser
Write-Host ("interactive-logon-readiness => ready={0}; active-user={1}; user-match={2}; explorer-ready={3}; note={4}" -f [bool]$interactiveLogonReadiness.Ready, $(if ([string]::IsNullOrWhiteSpace([string]$interactiveLogonReadiness.ActiveUser)) { '(none)' } else { [string]$interactiveLogonReadiness.ActiveUser }), [bool]$interactiveLogonReadiness.UserMatch, [bool]$interactiveLogonReadiness.ExplorerReady, 'autologon is configured and an immediate reboot is required to validate the next desktop session')
Write-Host 'TASK_REBOOT_REQUIRED:configure-autologon-settings'

Write-Host "configure-autologon-settings-completed"
Write-Host "Update task completed: configure-autologon-settings"


