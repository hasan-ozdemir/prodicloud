$ErrorActionPreference = "Stop"
Write-Host "Init task started: configure-powershell-remoting"

$managerUser = "__VM_ADMIN_USER__"
$assistantUser = "__ASSISTANT_USER__"
$winRmPort = 5985

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

function Test-LocalGroupMemberPresent {
    param(
        [string]$GroupName,
        [string]$MemberName
    )

    $resolvedMember = ".\{0}" -f [string]$MemberName
    if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        $currentMembers = @(
            Get-LocalGroupMember -Group $GroupName -ErrorAction SilentlyContinue |
                ForEach-Object { [string]$_.Name }
        )
        if (@($currentMembers) -contains $resolvedMember -or @($currentMembers) -contains [string]$MemberName) {
            return $true
        }
    }

    $groupOutput = @(& net.exe localgroup $GroupName 2>$null)
    foreach ($line in @($groupOutput)) {
        $trimmedLine = [string]([string]$line).Trim()
        if ([string]::IsNullOrWhiteSpace([string]$trimmedLine)) {
            continue
        }

        if ([string]::Equals($trimmedLine, $resolvedMember, [System.StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($trimmedLine, [string]$MemberName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Ensure-LocalGroupMember {
    param(
        [string]$GroupName,
        [string]$MemberName
    )

    if (Test-LocalGroupMemberPresent -GroupName $GroupName -MemberName $MemberName) {
        return
    }

    if (Get-Command Add-LocalGroupMember -ErrorAction SilentlyContinue) {
        try {
            Add-LocalGroupMember -Group $GroupName -Member $MemberName -ErrorAction Stop
            return
        }
        catch {
            if (Test-LocalGroupMemberPresent -GroupName $GroupName -MemberName $MemberName) {
                return
            }
        }
    }

    $detail = ''
    $stdoutFile = Join-Path $env:TEMP ("clagnos-net-localgroup-{0}-stdout.txt" -f ([guid]::NewGuid().ToString('N')))
    $stderrFile = Join-Path $env:TEMP ("clagnos-net-localgroup-{0}-stderr.txt" -f ([guid]::NewGuid().ToString('N')))
    try {
        $process = Start-Process -FilePath 'net.exe' -ArgumentList @('localgroup', $GroupName, $MemberName, '/add') -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        $stdoutLines = if (Test-Path -LiteralPath $stdoutFile) { @(Get-Content -LiteralPath $stdoutFile -ErrorAction SilentlyContinue) } else { @() }
        $stderrLines = if (Test-Path -LiteralPath $stderrFile) { @(Get-Content -LiteralPath $stderrFile -ErrorAction SilentlyContinue) } else { @() }
        $detail = [string]((@($stdoutLines + $stderrLines) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ' | ')
        if ($process.ExitCode -ne 0 -and $detail -notmatch '(?i)1378|already a member') {
            throw ("Failed to add '{0}' to local group '{1}'. detail: {2}" -f $MemberName, $GroupName, $detail)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-LocalGroupMemberPresent -GroupName $GroupName -MemberName $MemberName)) {
        throw ("Failed to add '{0}' to local group '{1}'. detail: {2}" -f $MemberName, $GroupName, $detail)
    }
}

function Assert-LocalGroupMember {
    param(
        [string]$GroupName,
        [string]$MemberName
    )

    $resolvedMember = ".\{0}" -f [string]$MemberName
    if (Get-Command Get-LocalGroupMember -ErrorAction SilentlyContinue) {
        $currentMembers = @(
            Get-LocalGroupMember -Group $GroupName -ErrorAction Stop |
                ForEach-Object { [string]$_.Name }
        )
        if (@($currentMembers) -contains $resolvedMember -or @($currentMembers) -contains [string]$MemberName) {
            return
        }
    }

    $groupText = [string]((@(& net.exe localgroup $GroupName 2>&1) | ForEach-Object { [string]$_ }) -join "`n")
    if ($groupText -notmatch [regex]::Escape($MemberName)) {
        throw ("Local group verification failed: '{0}' is not a member of '{1}'." -f $MemberName, $GroupName)
    }
}

function Wait-WinRmListener {
    param(
        [int]$Port = 5985,
        [int]$TimeoutSeconds = 30
    )

    $deadline = [DateTime]::UtcNow.AddSeconds([Math]::Max($TimeoutSeconds, 5))
    while ([DateTime]::UtcNow -lt $deadline) {
        $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $listener) {
            return $true
        }

        Start-Sleep -Seconds 1
    }

    return $false
}

function Assert-WinRmListener {
    $listeners = @(
        & winrm.cmd enumerate winrm/config/Listener 2>$null |
            ForEach-Object { [string]$_ }
    )
    if ((@($listeners | Where-Object { $_ -match 'Transport\s*=\s*HTTP' })).Count -lt 1) {
        throw 'WinRM HTTP listener was not found.'
    }
}

Enable-PSRemoting -SkipNetworkProfileCheck -Force
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM -ErrorAction SilentlyContinue
Ensure-LocalGroupMember -GroupName 'Remote Management Users' -MemberName $managerUser
Ensure-LocalGroupMember -GroupName 'Remote Management Users' -MemberName $assistantUser

$systemPolicyPath = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-RegistryValue -Path $systemPolicyPath -Name 'LocalAccountTokenFilterPolicy' -Value 1 -Kind DWord

Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $false -Force
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $false -Force

if (-not (Wait-WinRmListener -Port $winRmPort -TimeoutSeconds 30)) {
    throw ("WinRM listener did not bind to port {0} in time." -f $winRmPort)
}

$wsmanResult = Test-WSMan -ComputerName localhost -ErrorAction Stop
if ($null -eq $wsmanResult) {
    throw 'Test-WSMan localhost returned no result.'
}

Assert-WinRmListener
Assert-RegistryValue -Path $systemPolicyPath -Name 'LocalAccountTokenFilterPolicy' -ExpectedValue 1
Assert-LocalGroupMember -GroupName 'Remote Management Users' -MemberName $managerUser
Assert-LocalGroupMember -GroupName 'Remote Management Users' -MemberName $assistantUser

$winRmService = Get-Service -Name WinRM -ErrorAction Stop
Write-Host ("powershell-remoting-group-ready: group=Remote Management Users; user=.\\{0}" -f $managerUser)
Write-Host ("powershell-remoting-group-ready: group=Remote Management Users; user=.\\{0}" -f $assistantUser)
Write-Host ("powershell-remoting-ready: service={0}; start-type={1}; port={2}; users=.\\{3},.\\{4}" -f [string]$winRmService.Status, [string]$winRmService.StartType, $winRmPort, $managerUser, $assistantUser)
Write-Host "configure-powershell-remoting-ready"
Write-Host "Init task completed: configure-powershell-remoting"
