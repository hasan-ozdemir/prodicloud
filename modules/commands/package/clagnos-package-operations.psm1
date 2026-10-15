Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-ClagnosChocolateyRoot {
    $configuredRoot = [string][Environment]::GetEnvironmentVariable('ChocolateyInstall','Machine')
    if ([string]::IsNullOrWhiteSpace($configuredRoot)) { $configuredRoot = [string]$env:ChocolateyInstall }
    if ([string]::IsNullOrWhiteSpace($configuredRoot)) { $configuredRoot = Join-Path $env:ProgramData 'chocolatey' }
    return [IO.Path]::GetFullPath($configuredRoot.Trim())
}

function Write-ClagnosPackageResult {
    param([hashtable]$Result)
    Write-Output ('CLAGNOS_PACKAGE_RESULT:' + (ConvertTo-Json -InputObject $Result -Depth 8 -Compress))
}

function Get-ClagnosPackageVersionFromOutput {
    param([string]$Text,[string]$PackageId)
    foreach ($line in @([string]$Text -split "`r?`n")) {
        if ($line -match ('(?i)(?:^|\s)' + [regex]::Escape($PackageId) + '(?:\s|$)')) {
            $tokens = @($line.Trim() -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $idIndex = -1
            for ($index = 0; $index -lt $tokens.Count; $index++) {
                if ([string]::Equals([string]$tokens[$index],[string]$PackageId,[System.StringComparison]::OrdinalIgnoreCase)) { $idIndex = $index; break }
            }
            if ($idIndex -ge 0 -and $idIndex + 1 -lt $tokens.Count -and $tokens[$idIndex + 1] -match '^\d') { return [string]$tokens[$idIndex + 1] }
            if ($line -match '(?i)\|\s*(?<version>[^|\s]+)\s*$') { return [string]$Matches.version }
        }
    }
    return ''
}

function Get-ClagnosPackageRecord {
    param([psobject]$Spec)

    $kind = [string]$Spec.statusCheck.kind
    $value = [string]$Spec.statusCheck.value
    $status = 'unknown'
    $version = ''
    $detail = ''
    switch ($kind) {
        'command' {
            if (Test-Path -LiteralPath $value -PathType Leaf) { $status = 'installed' }
            elseif (Get-Command $value -ErrorAction SilentlyContinue) { $status = 'installed' }
            else { $status = 'not-installed' }
        }
        'winget' {
            $command = Get-Command winget.exe -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; $detail = 'winget is unavailable for package detection'; break }
            try { $output = & $command.Source list --id $value --exact --accept-source-agreements --disable-interactivity 2>&1 | Out-String }
            catch { $status = 'unknown'; $detail = 'winget package detection failed'; break }
            $exitCode = [int]$LASTEXITCODE
            if ($exitCode -eq 0 -and $output -match ('(?im)(?:^|\s)' + [regex]::Escape($value) + '(?:\s|$)')) {
                $status = 'installed'
                $version = Get-ClagnosPackageVersionFromOutput -Text $output -PackageId $value
            }
            elseif ($exitCode -eq 0 -or $output -match '(?i)no installed package') { $status = 'not-installed' }
            else { $status = 'unknown'; $detail = ('winget list exited with {0}' -f $exitCode) }
        }
        'choco' {
            $command = Get-Command choco.exe -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; $detail = 'Chocolatey is unavailable for package detection'; break }
            try { $output = & $command.Source list --local-only --exact --limit-output $value 2>&1 | Out-String }
            catch { $status = 'unknown'; $detail = 'Chocolatey package detection failed'; break }
            $exitCode = [int]$LASTEXITCODE
            $match = [regex]::Match($output,'(?im)^' + [regex]::Escape($value) + '\|(?<version>[^\s|]+)\s*$')
            if ($exitCode -eq 0 -and $match.Success) { $status = 'installed'; $version = [string]$match.Groups['version'].Value }
            elseif ($exitCode -eq 0) { $status = 'not-installed' }
            else { $status = 'unknown'; $detail = ('Chocolatey inventory exited with {0}' -f $exitCode) }
        }
        'npm' {
            $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
            if (-not $command) { $command = Get-Command npm -ErrorAction SilentlyContinue }
            if (-not $command) { $status = 'unknown'; $detail = 'npm is unavailable for package detection'; break }
            try { $output = & $command.Source list --global --depth=0 --json 2>&1 | Out-String }
            catch { $status = 'unknown'; $detail = 'npm package detection failed'; break }
            if ([int]$LASTEXITCODE -eq 0 -or $output -match '"dependencies"') {
                try {
                    $inventory = ConvertFrom-Json -InputObject $output
                    $packageProperty = $inventory.dependencies.PSObject.Properties[[string]$value]
                    if ($null -ne $packageProperty) { $status = 'installed'; $version = [string]$packageProperty.Value.version }
                    else { $status = 'not-installed' }
                }
                catch { $status = 'unknown'; $detail = 'npm returned an unreadable global package inventory' }
            }
            else { $status = 'unknown'; $detail = ('npm inventory exited with {0}' -f [int]$LASTEXITCODE) }
        }
        'appx' {
            try { $packages = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like ('*' + $value + '*') -or $_.PackageFamilyName -like ('*' + $value + '*') -or $_.PackageFullName -like ('*' + $value + '*') }) }
            catch { $status = 'unknown'; $detail = 'AppX package inventory query failed'; break }
            if ($packages.Count -gt 0) { $status = 'installed'; $version = [string](@($packages | Sort-Object Version -Descending | Select-Object -First 1)[0].Version) }
            else { $status = 'not-installed' }
        }
        'store-state' {
            $uninstallValue = [string]$Spec.uninstall.value
            try { $matches = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -like ('*' + $uninstallValue + '*') -or $_.PackageFamilyName -like ('*' + $uninstallValue + '*') -or $_.PackageFullName -like ('*' + $uninstallValue + '*') }) }
            catch { $status = 'unknown'; $detail = 'AppX package inventory query failed'; break }
            if ($matches.Count -gt 0) { $status = 'installed'; $version = [string](@($matches | Sort-Object Version -Descending | Select-Object -First 1)[0].Version) }
            else {
                $safeName = [regex]::Replace($value,'[^A-Za-z0-9._-]','_')
                $statePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\store-installs') ($safeName + '.json')
                if (Test-Path -LiteralPath $statePath) {
                    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json; if ([string]$state.State -eq 'installed') { $status = 'unknown'; $detail = 'Store install state exists but its AppX package is absent' } else { $status = 'not-installed' } }
                    catch { $status = 'unknown'; $detail = 'Store install state could not be read' }
                }
                else { $status = 'not-installed' }
            }
        }
        'choco-self' {
            $chocoRoot = Get-ClagnosChocolateyRoot
            $exePath = Join-Path $chocoRoot 'bin\choco.exe'
            if (Test-Path -LiteralPath $exePath -PathType Leaf) {
                $status = 'installed'
                try { $version = [string](& $exePath --version 2>$null | Select-Object -First 1) } catch { $version = '' }
            }
            else { $status = 'not-installed' }
        }
        'dpkg' {
            $command = Get-Command dpkg-query -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; break }
            & $command.Source -W -f='${Status}' -- $value 2>$null | Out-Null
            if ([int]$LASTEXITCODE -eq 0) { $status = 'installed' } else { $status = 'not-installed' }
        }
        'rpm' {
            $command = Get-Command rpm -ErrorAction SilentlyContinue
            if (-not $command) { $status = 'unknown'; break }
            & $command.Source -q -- $value 2>$null | Out-Null
            if ([int]$LASTEXITCODE -eq 0) { $status = 'installed' } else { $status = 'not-installed' }
        }
        default { $status = 'unknown'; $detail = ('Unsupported status kind: {0}' -f $kind) }
    }
    if ($status -eq 'installed' -and [string]$Spec.id -eq 'jaws' -and @($Spec.targetUsers).Count -gt 0) {
        $missingStartup = @($Spec.targetUsers | Where-Object { -not (Test-ClagnosJawsPostLogonStartup -UserName ([string]$_) -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe') })
        if ($missingStartup.Count -gt 0) { $detail = ('JAWS post-logon startup is not verified for: ' + ($missingStartup -join ', ')) }
        else { $detail = 'JAWS post-logon startup is verified for the selected users; logon-screen launch remains installer-managed.' }
    }
    elseif ($status -eq 'installed' -and [string]$Spec.id -in @('ollama','docker-desktop')) {
        $detail = Test-ClagnosPackageStartupState -Spec $Spec
    }
    return [pscustomobject]@{ Id = [string]$Spec.id; Status = $status; Version = $version; Detail = $detail }
}

function Write-ClagnosPackageOperationResult {
    param([psobject]$Spec,[string]$Action,[psobject]$Record,[string]$Message)
    Write-ClagnosPackageResult -Result ([ordered]@{
        id = [string]$Spec.id
        action = [string]$Action
        status = [string]$Record.Status
        version = [string]$Record.Version
        message = [string]$Message
        detail = [string]$Record.Detail
    })
}

function Set-ClagnosJawsPostLogonStartup {
    param([string[]]$UserNames,[string]$Executable)

    if ([string]::IsNullOrWhiteSpace($Executable) -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'JAWS executable could not be resolved for post-logon startup.' }
    $machineRunKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $machineRunKey)) { New-Item -Path $machineRunKey -Force -ErrorAction Stop | Out-Null }
    $machineRunCommand = '"{0}"' -f $Executable
    New-ItemProperty -LiteralPath $machineRunKey -Name 'JAWS' -Value $machineRunCommand -PropertyType String -Force -ErrorAction Stop | Out-Null
    $machineRunVerified = [string](Get-ItemProperty -LiteralPath $machineRunKey -Name 'JAWS' -ErrorAction Stop).JAWS
    if (-not [string]::Equals($machineRunVerified,$machineRunCommand,[StringComparison]::OrdinalIgnoreCase)) { throw 'Machine-wide JAWS post-logon startup did not verify.' }
    foreach ($userName in @($UserNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        Write-Output ("Doing: enable JAWS post-logon startup for user '{0}'" -f [string]$userName)
        try {
            $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName)
            $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
            $sidRegistryRoot = 'Registry::HKEY_USERS\{0}' -f $sid
        }
        catch {
            Write-Warning ("Could not resolve the profile for '{0}'; the verified machine-wide startup entry covers future logons. {1}" -f [string]$userName,[string]$_.Exception.Message)
            continue
        }
        if (-not (Test-Path -LiteralPath $sidRegistryRoot)) { Write-Output ("User profile '{0}' is not loaded; machine-wide JAWS startup covers its next logon." -f [string]$userName); continue }
        try {
            $runKey = Join-Path $sidRegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Run'
            if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force -ErrorAction Stop | Out-Null }
            $runCommand = '"{0}"' -f $Executable
            New-ItemProperty -LiteralPath $runKey -Name 'JAWS' -Value $runCommand -PropertyType String -Force -ErrorAction Stop | Out-Null
            $verified = [string](Get-ItemProperty -LiteralPath $runKey -Name 'JAWS' -ErrorAction Stop).JAWS
            if (-not [string]::Equals($verified,$runCommand,[StringComparison]::OrdinalIgnoreCase)) { throw ("JAWS post-logon startup did not verify for user '{0}'." -f [string]$userName) }
        }
        catch {
            Write-Warning ("Per-user JAWS startup could not be verified for '{0}'; the verified machine-wide startup entry remains active. {1}" -f [string]$userName,[string]$_.Exception.Message)
        }
    }
}

function Test-ClagnosJawsPostLogonStartup {
    param([string]$UserName,[string]$Executable)

    try {
        $machineValue = [string](Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'JAWS' -ErrorAction SilentlyContinue).JAWS
        if ([string]::Equals($machineValue,('"{0}"' -f $Executable),[StringComparison]::OrdinalIgnoreCase)) { return $true }
        $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$UserName)
        $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $sidRegistryRoot = 'Registry::HKEY_USERS\{0}' -f $sid
        if (-not (Test-Path -LiteralPath $sidRegistryRoot)) { return $false }
        $runKey = Join-Path $sidRegistryRoot 'Software\Microsoft\Windows\CurrentVersion\Run'
        if (-not (Test-Path -LiteralPath $runKey)) { return $false }
        $actual = [string](Get-ItemProperty -LiteralPath $runKey -Name 'JAWS' -ErrorAction SilentlyContinue).JAWS
        return [string]::Equals($actual,('"{0}"' -f $Executable),[StringComparison]::OrdinalIgnoreCase)
    }
    catch { return $false }
}

function Remove-ClagnosPackageStartupArtifacts {
    param([psobject]$Spec)

    switch ([string]$Spec.id) {
        'jaws' {
            $machineRunKey = 'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Run'
            if (Test-Path -LiteralPath $machineRunKey) { Remove-ItemProperty -LiteralPath $machineRunKey -Name 'JAWS' -ErrorAction SilentlyContinue }
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                try {
                    $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName)
                    $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                    $userRunKey = 'Registry::HKEY_USERS\{0}\Software\Microsoft\Windows\CurrentVersion\Run' -f $sid
                    if (Test-Path -LiteralPath $userRunKey) { Remove-ItemProperty -LiteralPath $userRunKey -Name 'JAWS' -ErrorAction SilentlyContinue }
                }
                catch { Write-Warning ("Could not remove the JAWS startup entry for user '{0}': {1}" -f [string]$userName,[string]$_.Exception.Message) }
            }
        }
        'ollama' {
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                try {
                    $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$userName)
                    $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
                    $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $sid) -ErrorAction Stop
                    if ($null -eq $profile -or [string]::IsNullOrWhiteSpace([string]$profile.LocalPath)) { continue }
                    $startupShortcut = Join-Path ([string]$profile.LocalPath) 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
                    if (Test-Path -LiteralPath $startupShortcut) { Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction Stop }
                }
                catch { Write-Warning ("Could not remove the Ollama startup shortcut for user '{0}': {1}" -f [string]$userName,[string]$_.Exception.Message) }
            }
        }
        'docker-desktop' {
            $startupShortcut = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk'
            if (Test-Path -LiteralPath $startupShortcut) { Remove-Item -LiteralPath $startupShortcut -Force -ErrorAction Stop }
        }
    }
}

function Get-ClagnosPackageUserProfilePath {
    param([string]$UserName)
    try {
        $accountName = ('{0}\{1}' -f $env:COMPUTERNAME,[string]$UserName)
        $sid = ([System.Security.Principal.NTAccount]::new($accountName)).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $profile = Get-CimInstance -ClassName Win32_UserProfile -Filter ("SID='{0}'" -f $sid) -ErrorAction Stop
        if ($null -ne $profile -and -not [string]::IsNullOrWhiteSpace([string]$profile.LocalPath)) { return [string]$profile.LocalPath }
    }
    catch { }
    if ([string]::IsNullOrWhiteSpace([string]$UserName)) { return '' }
    return (Join-Path $env:SystemDrive (Join-Path 'Users' ([string]$UserName)))
}

function Set-ClagnosPackageStartupShortcut {
    param([string]$ShortcutPath,[string]$TargetPath,[string]$Arguments = '')
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) { throw ("Startup target does not exist: {0}" -f [System.IO.Path]::GetFileName($TargetPath)) }
    $startupDirectory = Split-Path -Parent $ShortcutPath
    if (-not (Test-Path -LiteralPath $startupDirectory -PathType Container)) { New-Item -ItemType Directory -Path $startupDirectory -Force -ErrorAction Stop | Out-Null }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
    $shortcut.IconLocation = "$TargetPath,0"
    $shortcut.Save()
    $verified = $shell.CreateShortcut($ShortcutPath)
    if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) -or
        -not [string]::Equals([string]$verified.TargetPath,[string]$TargetPath,[StringComparison]::OrdinalIgnoreCase) -or
        -not [string]::Equals([string]$verified.Arguments,[string]$Arguments,[StringComparison]::Ordinal)) {
        throw ("Startup shortcut did not verify: {0}" -f [System.IO.Path]::GetFileName($ShortcutPath))
    }
}

function Set-ClagnosOllamaStartupState {
    param([string[]]$UserNames)
    $appCandidates = @(
        (Join-Path $env:ProgramFiles 'Ollama\ollama app.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe')
    )
    foreach ($userName in @($UserNames)) {
        $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
        if (-not [string]::IsNullOrWhiteSpace([string]$profilePath)) { $appCandidates += (Join-Path $profilePath 'AppData\Local\Programs\Ollama\ollama app.exe') }
    }
    $appExe = @($appCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
    if ($appExe.Count -ne 1) { throw 'Ollama desktop startup executable could not be resolved after package install/update.' }
    foreach ($userName in @($UserNames | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
        $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
        $shortcutPath = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
        Write-Output ("Doing: ensure Ollama startup for managed user '{0}'" -f [string]$userName)
        Set-ClagnosPackageStartupShortcut -ShortcutPath $shortcutPath -TargetPath ([string]$appExe[0])
    }
}

function Set-ClagnosPackageStartupState {
    param([psobject]$Spec)
    switch ([string]$Spec.id) {
        'ollama' { Set-ClagnosOllamaStartupState -UserNames @($Spec.targetUsers); break }
        'docker-desktop' {
            $dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
            $startupPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk'
            Write-Output 'Doing: ensure Docker Desktop startup shortcut'
            Set-ClagnosPackageStartupShortcut -ShortcutPath $startupPath -TargetPath $dockerExe -Arguments '--minimized'
            break
        }
    }
}

function Test-ClagnosPackageStartupState {
    param([psobject]$Spec)
    switch ([string]$Spec.id) {
        'ollama' {
            $missing = @()
            foreach ($userName in @($Spec.targetUsers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)) {
                $profilePath = Get-ClagnosPackageUserProfilePath -UserName ([string]$userName)
                $shortcutPath = Join-Path $profilePath 'AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Ollama.lnk'
                if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) { $missing += [string]$userName }
            }
            if ($missing.Count -gt 0) { return ('Ollama startup shortcut is missing for: ' + ($missing -join ', ')) }
            return 'Ollama startup shortcuts are verified for managed users.'
        }
        'docker-desktop' {
            $startupPath = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp\Docker Desktop.lnk'
            if (-not (Test-Path -LiteralPath $startupPath -PathType Leaf)) { return 'Docker Desktop startup shortcut is missing.' }
            return 'Docker Desktop machine-wide startup shortcut is verified.'
        }
        default { return '' }
    }
}

function Install-ClagnosJawsAppStateUpdateFiles {
    $archivePath = 'C:\Windows\Temp\clagnos-jaws-app-state.zip'
    $targetRoot = 'C:\Program Files\Freedom Scientific\JAWS\2025'
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw ('JAWS update app-state archive is missing: ' + $archivePath) }
    if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'jfw.exe') -PathType Leaf)) { throw ('The required JAWS 2025 install directory was not found: ' + $targetRoot) }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $prefix = 'payload/update-files/'
        $entries = @($archive.Entries | Where-Object { ([string]$_.FullName).StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and -not ([string]$_.FullName).EndsWith('/') })
        if ($entries.Count -eq 0) { throw 'JAWS app-state archive has no payload/update-files entries.' }
        $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $updatesToApply = @()
        foreach ($entry in @($entries)) {
            $relative = ([string]$entry.FullName).Substring($prefix.Length)
            if ([string]::IsNullOrWhiteSpace($relative) -or $relative -match '[/\\]' -or $relative -match '(^|\.)\.($|\.)' -or [IO.Path]::IsPathRooted($relative)) { throw ('Unsafe JAWS update-file path: ' + [string]$entry.FullName) }
            $destination = [IO.Path]::GetFullPath((Join-Path $targetRoot $relative))
            if (-not $destination.StartsWith($targetRoot.TrimEnd('\') + '\',[StringComparison]::OrdinalIgnoreCase) -or -not $seen.Add($destination)) { throw ('Invalid or duplicate JAWS update-file destination: ' + $relative) }
            $input = $entry.Open()
            try {
                $sha256 = [Security.Cryptography.SHA256]::Create()
                try { $expectedHash = ([BitConverter]::ToString($sha256.ComputeHash($input))).Replace('-','') }
                finally { $sha256.Dispose() }
            }
            finally { $input.Dispose() }
            if (Test-Path -LiteralPath $destination -PathType Leaf) {
                $currentHash = [string](Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
                if ([string]::Equals($currentHash,$expectedHash,[StringComparison]::OrdinalIgnoreCase)) {
                    Write-Output ('JAWS update file already matches the app-state payload and is verified: ' + $destination)
                    continue
                }
            }
            $updatesToApply += [pscustomobject]@{ Entry = $entry; Relative = $relative; Destination = $destination; ExpectedHash = $expectedHash }
        }

        if ($updatesToApply.Count -eq 0) {
            Write-Output 'All JAWS update-files already match the app-state payload; no program file replacement was needed.'
            return
        }

        Write-Output 'Doing: close JAWS before replacing changed package update files'
        foreach ($process in @(Get-Process -Name jfw -ErrorAction SilentlyContinue)) { Stop-Process -Id $process.Id -Force -ErrorAction Stop }
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        $nextProcessHeartbeat = 10
        while (@(Get-Process -Name jfw -ErrorAction SilentlyContinue).Count -gt 0 -and [DateTime]::UtcNow -lt $deadline) {
            $elapsed = [int](30 - [Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalSeconds))
            if ($elapsed -ge $nextProcessHeartbeat) { Write-Output ("Doing: waiting for jfw.exe to close ({0}s elapsed)" -f $elapsed); $nextProcessHeartbeat += 10 }
            Start-Sleep -Seconds 1
        }
        if (@(Get-Process -Name jfw -ErrorAction SilentlyContinue).Count -gt 0) { throw 'jfw.exe is still running; JAWS update files were not copied.' }

        foreach ($update in @($updatesToApply)) {
            $entry = $update.Entry
            $relative = [string]$update.Relative
            $destination = [string]$update.Destination
            $input = $entry.Open()
            try {
                $output = $null
                $fileWait = [Diagnostics.Stopwatch]::StartNew()
                $nextFileHeartbeat = 10
                while ($null -eq $output) {
                    try { $output = [IO.File]::Open($destination,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite) }
                    catch [IO.IOException] {
                        $nativeCode = [int]$_.Exception.HResult -band 0xffff
                        if ($nativeCode -notin @(32,33)) { throw }
                        if ($fileWait.Elapsed.TotalSeconds -ge 60) { throw ("JAWS update file remains locked after 60 seconds: {0}" -f $destination) }
                        if ($fileWait.Elapsed.TotalSeconds -ge $nextFileHeartbeat) {
                            Write-Output ("Doing: waiting for JAWS update file lock to clear ({0}s elapsed)" -f [int]$fileWait.Elapsed.TotalSeconds)
                            $nextFileHeartbeat += 10
                        }
                        Start-Sleep -Seconds 1
                    }
                }
                $fileWait.Stop()
                try { $input.CopyTo($output); if ($output.Length -ne $entry.Length) { throw ('JAWS update-file verification failed: ' + $relative) } }
                finally { $output.Dispose() }
                $writtenHash = [string](Get-FileHash -LiteralPath $destination -Algorithm SHA256 -ErrorAction Stop).Hash
                if (-not [string]::Equals($writtenHash,[string]$update.ExpectedHash,[StringComparison]::OrdinalIgnoreCase)) { throw ('JAWS update-file SHA256 verification failed: ' + $relative) }
            }
            finally { $input.Dispose() }
            Write-Output ('JAWS update file copied and verified: ' + $destination)
        }
    }
    finally { $archive.Dispose() }
}

function Invoke-ClagnosPackageLifecycle {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('status','install','repair','update','uninstall')][string]$Action,
        [Parameter(Mandatory = $true)][string]$PackageSpecBase64,
        [string]$InstallScriptBase64 = ''
    )

    $specJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PackageSpecBase64))
    $spec = ConvertFrom-Json -InputObject $specJson
    $record = Get-ClagnosPackageRecord -Spec $spec
    if ($Action -eq 'status') {
        $message = if ($record.Status -eq 'installed') { 'Package is installed and detectable.' } elseif ($record.Status -eq 'not-installed') { 'Package is not installed.' } else { 'Package status could not be determined safely.' }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.Detail)) { $message += ' ' + [string]$record.Detail }
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message $message
        return
    }

    if ($Action -eq 'uninstall') {
        if ($record.Status -eq 'not-installed') {
            Remove-ClagnosPackageStartupArtifacts -Spec $spec
            Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message 'Package was already absent; no uninstall action was run.'
            return
        }
        if ($record.Status -ne 'installed') { throw ('Cannot safely uninstall {0}: current package status is {1}.' -f [string]$spec.displayName,$record.Status) }
        $uninstall = $spec.uninstall
        $value = [string]$uninstall.value
        Write-Output ('Doing: uninstall package {0} using {1}' -f [string]$spec.id,[string]$uninstall.kind)
        switch ([string]$uninstall.kind) {
            'winget' { $command = Get-Command winget.exe -ErrorAction Stop; & $command.Source uninstall --id $value --exact --silent --accept-source-agreements --disable-interactivity; if ([int]$LASTEXITCODE -ne 0) { throw ('winget uninstall exited with ' + [int]$LASTEXITCODE) } }
            'choco' { $command = Get-Command choco.exe -ErrorAction Stop; & $command.Source uninstall $value -y --no-progress; if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey uninstall exited with ' + [int]$LASTEXITCODE) } }
            'npm' { $command = Get-Command npm.cmd -ErrorAction SilentlyContinue; if (-not $command) { $command = Get-Command npm -ErrorAction Stop }; & $command.Source uninstall --global $value; if ([int]$LASTEXITCODE -ne 0) { throw ('npm uninstall exited with ' + [int]$LASTEXITCODE) } }
            'appx' { $matches = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | Where-Object { $_.Name -like ('*' + $value + '*') -or $_.PackageFamilyName -like ('*' + $value + '*') -or $_.PackageFullName -like ('*' + $value + '*') }); foreach ($app in $matches) { Remove-AppxPackage -Package $app.PackageFullName -AllUsers -ErrorAction Stop } }
            'windows-feature' { Disable-WindowsOptionalFeature -Online -FeatureName $value -NoRestart -ErrorAction Stop | Out-Null }
            'choco-self' {
                $chocolateyRoot = Get-ClagnosChocolateyRoot
                $managerFiles = @(
                    (Join-Path $chocolateyRoot 'bin\choco.exe'),
                    (Join-Path $chocolateyRoot 'bin\choco.exe.config'),
                    (Join-Path $chocolateyRoot 'lib\chocolatey')
                )
                foreach ($managerPath in $managerFiles) {
                    if (Test-Path -LiteralPath $managerPath -PathType Container) { Remove-Item -LiteralPath $managerPath -Recurse -Force -ErrorAction Stop }
                    elseif (Test-Path -LiteralPath $managerPath -PathType Leaf) { Remove-Item -LiteralPath $managerPath -Force -ErrorAction Stop }
                }
                Write-Output 'Chocolatey CLI manager files removed; other packages and the shared lib/bin directories were retained.'
            }
            default { throw ('Unsupported allow-listed uninstall kind: ' + [string]$uninstall.kind) }
        }
        if ([string]$spec.statusCheck.kind -eq 'store-state') {
            $stateName = [regex]::Replace([string]$spec.statusCheck.value,'[^A-Za-z0-9._-]','_')
            $statePath = Join-Path (Join-Path $env:ProgramData 'clagnos\state\store-installs') ($stateName + '.json')
            if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop }
        }
        Remove-ClagnosPackageStartupArtifacts -Spec $spec
        $verified = Get-ClagnosPackageRecord -Spec $spec
        if ($verified.Status -ne 'not-installed') { throw ('Uninstall did not verify; package status after removal is {0}.' -f $verified.Status) }
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message 'Package uninstall completed and absence verified.'
        return
    }

    if ($Action -eq 'install') {
        if ($record.Status -eq 'installed') {
            Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message 'Package is already installed; no install was run.'
            return
        }
        if ($record.Status -ne 'not-installed') { throw ('Cannot safely install {0}: current package status is {1}.' -f [string]$spec.displayName,$record.Status) }
        if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw ('Package {0} has no validated installer script.' -f [string]$spec.id) }
        $installSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
        Write-Output ('Doing: install package {0} using its package installer' -f [string]$spec.id)
        $installOutput = & ([scriptblock]::Create($installSource)) *>&1 | Out-String
        if (-not [string]::IsNullOrWhiteSpace($installOutput)) { Write-Output $installOutput.TrimEnd() }
        Set-ClagnosPackageStartupState -Spec $spec
        $verified = Get-ClagnosPackageRecord -Spec $spec
        if ($verified.Status -ne 'installed') { throw ('Install script finished but package status verification returned {0}.' -f $verified.Status) }
        $message = 'Package installation completed and installed state verified.'
        if (-not [string]::IsNullOrWhiteSpace([string]$verified.Detail)) { $message += ' ' + [string]$verified.Detail }
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $message
        return
    }

    if ($Action -eq 'repair') {
        if ($record.Status -ne 'installed') { throw ('Cannot repair {0}: current package status is {1}; use install for an absent package.' -f [string]$spec.displayName,$record.Status) }
        if ([string]::IsNullOrWhiteSpace([string]$record.Version)) { throw ('Cannot safely repair {0}: the installed version could not be determined, so a same-version reinstall cannot be guaranteed.' -f [string]$spec.displayName) }
        $repairStrategy = [string]$spec.repairStrategy
        if ([string]::IsNullOrWhiteSpace($repairStrategy)) { $repairStrategy = [string]$spec.updateStrategy }
        if ([string]::IsNullOrWhiteSpace($repairStrategy)) { $repairStrategy = [string]$spec.statusCheck.kind }
        $repairOutput = ''
        Write-Output ('Doing: repair package {0} at installed version {1} using {2}' -f [string]$spec.id,[string]$record.Version,$repairStrategy)
        switch ($repairStrategy) {
            'winget' {
                $command = Get-Command winget.exe -ErrorAction Stop
                $repairOutput = & $command.Source install --id ([string]$spec.statusCheck.value) --exact --version ([string]$record.Version) --force --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('winget same-version repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'choco' {
                $command = Get-Command choco.exe -ErrorAction Stop
                $repairOutput = & $command.Source install ([string]$spec.statusCheck.value) --version ([string]$record.Version) --force -y --no-progress 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey same-version repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            'npm' {
                $command = Get-Command npm.cmd -ErrorAction SilentlyContinue
                if (-not $command) { $command = Get-Command npm -ErrorAction Stop }
                $versionedPackage = '{0}@{1}' -f [string]$spec.statusCheck.value,[string]$record.Version
                $repairOutput = & $command.Source install --global $versionedPackage 2>&1 | Out-String
                if ([int]$LASTEXITCODE -ne 0) { throw ('npm same-version repair exited with ' + [int]$LASTEXITCODE + '. ' + $repairOutput.Trim()) }
            }
            default { throw ('Safe same-version repair is not defined for package strategy "{0}". No install or update was attempted.' -f $repairStrategy) }
        }
        Set-ClagnosPackageStartupState -Spec $spec
        $verified = Get-ClagnosPackageRecord -Spec $spec
        if ($verified.Status -ne 'installed' -or -not [string]::Equals([string]$verified.Version,[string]$record.Version,[StringComparison]::OrdinalIgnoreCase)) {
            throw ('Repair verification failed for {0}: expected version {1}, observed status {2} version {3}.' -f [string]$spec.displayName,[string]$record.Version,[string]$verified.Status,[string]$verified.Version)
        }
        $message = ('Repaired {0} and verified version {1}.' -f [string]$spec.displayName,[string]$verified.Version)
        if (-not [string]::IsNullOrWhiteSpace([string]$verified.Detail)) { $message += ' ' + [string]$verified.Detail }
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $message
        return
    }

    if ($record.Status -eq 'not-installed') {
        Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $record -Message 'Package is not installed; update did not run.'
        return
    }
    if ($record.Status -ne 'installed') { throw ('Cannot safely update {0}: current package status is {1}.' -f [string]$spec.displayName,$record.Status) }
    $strategy = [string]$spec.updateStrategy
    if ([string]::IsNullOrWhiteSpace($strategy)) { $strategy = [string]$spec.statusCheck.kind }
    $updateOutput = ''
    Write-Output ('Doing: check and update package {0} using {1}' -f [string]$spec.id,$strategy)
    if ([string]$spec.id -eq 'jaws' -and $strategy -eq 'winget') {
        $command = Get-Command winget.exe -ErrorAction Stop
        Write-Output 'Doing: check whether a JAWS upgrade is available before invoking its installer'
        $availabilityOutput = & $command.Source list --upgrade-available --accept-source-agreements --disable-interactivity 2>&1 | Out-String
        if ([int]$LASTEXITCODE -ne 0) { throw ('winget list --upgrade-available exited with ' + [int]$LASTEXITCODE + '. ' + $availabilityOutput.Trim()) }
        if ($availabilityOutput -match ('(?im)(?:^|\s)' + [regex]::Escape([string]$spec.statusCheck.value) + '(?:\s|$)')) {
            Write-Output 'Doing: update JAWS because winget reports an available upgrade'
            $updateOutput = & $command.Source upgrade --id ([string]$spec.statusCheck.value) --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String
            $code = [int]$LASTEXITCODE
            if ($code -notin @(0,-1978335189)) { throw ('winget upgrade exited with ' + $code + '. ' + $updateOutput.Trim()) }
        }
        else { $updateOutput = 'No applicable upgrade available; the installed JAWS version is current.' }
    }
    else { switch ($strategy) {
        'winget' { $command = Get-Command winget.exe -ErrorAction Stop; $updateOutput = & $command.Source upgrade --id ([string]$spec.statusCheck.value) --exact --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Out-String; $code = [int]$LASTEXITCODE; if ($code -notin @(0,-1978335189)) { throw ('winget upgrade exited with ' + $code + '. ' + $updateOutput.Trim()) } }
        'choco' { $command = Get-Command choco.exe -ErrorAction Stop; $updateOutput = & $command.Source upgrade ([string]$spec.statusCheck.value) -y --no-progress 2>&1 | Out-String; if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey upgrade exited with ' + [int]$LASTEXITCODE + '. ' + $updateOutput.Trim()) } }
        'npm' { $command = Get-Command npm.cmd -ErrorAction SilentlyContinue; if (-not $command) { $command = Get-Command npm -ErrorAction Stop }; $updateOutput = & $command.Source update --global ([string]$spec.statusCheck.value) 2>&1 | Out-String; if ([int]$LASTEXITCODE -ne 0) { throw ('npm update exited with ' + [int]$LASTEXITCODE + '. ' + $updateOutput.Trim()) } }
        'choco-self' { $chocoExe = Join-Path (Get-ClagnosChocolateyRoot) 'bin\choco.exe'; if (-not (Test-Path -LiteralPath $chocoExe -PathType Leaf)) { throw 'Chocolatey CLI executable could not be resolved for self-update.' }; $updateOutput = & $chocoExe upgrade chocolatey -y --no-progress 2>&1 | Out-String; if ([int]$LASTEXITCODE -ne 0) { throw ('Chocolatey self-update exited with ' + [int]$LASTEXITCODE + '. ' + $updateOutput.Trim()) } }
        'installer' {
            if ([string]::IsNullOrWhiteSpace($InstallScriptBase64)) { throw ('Package {0} update requires its validated installer script.' -f [string]$spec.id) }
            $installSource = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($InstallScriptBase64))
            $updateOutput = & ([scriptblock]::Create($installSource)) *>&1 | Out-String
        }
        default { throw ('Unsupported package update strategy: ' + $strategy) }
    } }

    if ([string]$spec.id -eq 'jaws') {
        if ($Action -eq 'update') { Install-ClagnosJawsAppStateUpdateFiles }
        $users = @($spec.targetUsers | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        if ($users.Count -gt 0) { Set-ClagnosJawsPostLogonStartup -UserNames $users -Executable 'C:\Program Files\Freedom Scientific\JAWS\2025\jfw.exe' }
    }
    else { Set-ClagnosPackageStartupState -Spec $spec }
    $verified = Get-ClagnosPackageRecord -Spec $spec
    if ($verified.Status -ne 'installed') { throw ('Package update finished but installed-state verification returned {0}.' -f $verified.Status) }
    $noUpdateSignal = ($updateOutput -match '(?i)no applicable upgrade|already (?:at the )?latest|up[ -]?to[ -]?date|no updates? available|already healthy|skipping .*install')
    $versionsEqual = (-not [string]::IsNullOrWhiteSpace([string]$record.Version) -and -not [string]::IsNullOrWhiteSpace([string]$verified.Version) -and [string]::Equals([string]$record.Version,[string]$verified.Version,[StringComparison]::OrdinalIgnoreCase))
    $alreadyCurrent = $noUpdateSignal -or $versionsEqual
    if ($alreadyCurrent -and -not [string]::IsNullOrWhiteSpace([string]$verified.Version)) {
        $message = ('The package is current at version {0}.' -f [string]$verified.Version)
    }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$record.Version) -and -not [string]::IsNullOrWhiteSpace([string]$verified.Version) -and -not $versionsEqual) {
        $message = ('Package updated from version {0} to {1}.' -f [string]$record.Version,[string]$verified.Version)
    }
    elseif ($alreadyCurrent) { $message = 'The package provider reports that no update is available.' }
    else { $message = 'The update procedure completed and installed state was verified; version currentness could not be confirmed by this package provider.' }
    if ([string]$spec.id -eq 'jaws') { $message += ' JAWS update-files payload and post-logon startup were applied or verified.' }
    Write-ClagnosPackageOperationResult -Spec $spec -Action $Action -Record $verified -Message $message
}

Export-ModuleMember -Function Invoke-ClagnosPackageLifecycle,Set-ClagnosJawsPostLogonStartup
