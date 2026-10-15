$ErrorActionPreference = "Stop"
Write-Host "Init task started: configure-rdp-service"

$rdpPort = [int]"__RDP_PORT__"
$requiresServiceRestart = $false
$rdpSettings = @(
    @{ Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server"; Name = 'fDenyTSConnections'; Value = 0 },
    @{ Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = 'UserAuthentication'; Value = 0 },
    @{ Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = 'SecurityLayer'; Value = 1 },
    @{ Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = 'MinEncryptionLevel'; Value = 2 },
    @{ Path = "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = 'PortNumber'; Value = $rdpPort }
)
foreach ($setting in $rdpSettings) {
    $current = Get-ItemProperty -Path $setting.Path -Name $setting.Name -ErrorAction SilentlyContinue
    if ($null -eq $current -or [int]$current.($setting.Name) -ne [int]$setting.Value) {
        Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value
        $requiresServiceRestart = $true
    }
}

$rdpRuleName = "Allow-RDP-$rdpPort"
$legacyRuleNames = @("Allow-TCP-3389")
$namedRules = @(Get-NetFirewallRule -DisplayName "Allow-RDP-*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName)
foreach ($ruleName in @($legacyRuleNames + $namedRules)) {
    if ([string]::IsNullOrWhiteSpace([string]$ruleName)) {
        continue
    }
    if ([string]::Equals([string]$ruleName, $rdpRuleName, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue | Out-Null
}

if (-not (Get-NetFirewallRule -DisplayName $rdpRuleName -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rdpRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $rdpPort -RemoteAddress Any -Profile Any | Out-Null
}
else {
    Enable-NetFirewallRule -DisplayName $rdpRuleName -ErrorAction SilentlyContinue | Out-Null
}

Set-Service -Name TermService -StartupType Automatic
$termService = Get-Service -Name TermService -ErrorAction SilentlyContinue
if ($termService -and $termService.Status -eq "Running") {
    if ($requiresServiceRestart) {
        Write-Host 'Doing: restart TermService because an RDP setting changed'
        Restart-Service -Name TermService -Force
    }
    else {
        Write-Host 'RDP settings are already current; TermService remains running without a restart.'
    }
}
else {
    Start-Service -Name TermService
}

$svcWait = [System.Diagnostics.Stopwatch]::StartNew()
do {
    Start-Sleep -Seconds 2
    $svc = Get-Service -Name TermService -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { break }
} while ($svcWait.Elapsed.TotalSeconds -lt 60)

if (-not $svc -or $svc.Status -ne "Running") {
    throw "TermService did not reach Running state."
}

Write-Host "rdp-ready"
Write-Host "Init task completed: configure-rdp-service"

