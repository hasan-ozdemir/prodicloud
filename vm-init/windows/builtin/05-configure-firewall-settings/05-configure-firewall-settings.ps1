$ErrorActionPreference = "Stop"
Write-Host "Init task started: configure-firewall-settings"

foreach ($port in @(__TCP_PORTS_PS_ARRAY__)) {
    $name = "Allow-TCP-$port"
    if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $name -Direction Inbound -Action Allow -Protocol TCP -LocalPort $port -RemoteAddress Any -Profile Any
        Write-Host "Firewall rule created: $name"
    }
    else {
        Write-Host "Firewall rule exists: $name"
    }
}

Write-Host "configure-firewall-settings-ready"
Write-Host "Init task completed: configure-firewall-settings"

