function ConvertTo-ProdicloudShortcutLauncherBase64 {
    param([string]$Value)

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    return [Convert]::ToBase64String($bytes)
}

function ConvertFrom-ProdicloudShortcutCodePoints {
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

function ConvertFrom-ProdicloudShortcutLauncherBase64 {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return ''
    }

    try {
        $bytes = [Convert]::FromBase64String([string]$Value)
        return [string][System.Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        return ''
    }
}

function Get-ProdicloudShortcutLauncherRoot {
    param([string]$Subdirectory = 'public-desktop')

    $root = 'C:\ProgramData\prodicloud\shortcut-launchers'
    if ([string]::IsNullOrWhiteSpace([string]$Subdirectory)) {
        return $root
    }

    return (Join-Path $root $Subdirectory)
}

function Repair-ProdicloudShortcutTextEncoding {
    param([string]$Value)

    $text = if ($null -eq $Value) { '' } else { [string]$Value }
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return ''
    }

    $mojibakeMarkers = @(
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3)),
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C4)),
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C5))
    )
    if ((@($mojibakeMarkers | Where-Object { $text.IndexOf([string]$_) -ge 0 }).Count) -eq 0) {
        return $text
    }

    $replacementMap = [ordered]@{
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3, 0x2021)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C7))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3, 0x00A7)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00E7))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C4, 0x00B0)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x0130))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C4, 0x00B1)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x0131))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C5, 0x017E)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x015E))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C5, 0x00B8)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x015F))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C4, 0x017E)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x011E))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C4, 0x00B8)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x011F))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3, 0x2013)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00D6))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3, 0x00B6)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00F6))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3, 0x0153)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00DC))
        (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00C3, 0x00BC)) = (ConvertFrom-ProdicloudShortcutCodePoints -CodePoints @(0x00FC))
    }

    $repairedText = [string]$text
    foreach ($entry in $replacementMap.GetEnumerator()) {
        $repairedText = $repairedText.Replace([string]$entry.Key, [string]$entry.Value)
    }
    if (-not [string]::Equals($repairedText, $text, [System.StringComparison]::Ordinal)) {
        return $repairedText
    }

    try {
        $windows1252 = [System.Text.Encoding]::GetEncoding(1252)
        $decoded = [System.Text.Encoding]::UTF8.GetString($windows1252.GetBytes($text))
        if (-not [string]::IsNullOrWhiteSpace([string]$decoded) -and ($decoded.IndexOf([char]0xFFFD) -lt 0)) {
            return [string]$decoded
        }
    }
    catch {
    }

    return $text
}

function ConvertTo-ProdicloudShortcutSafeSlug {
    param(
        [string]$Value,
        [string]$Fallback = 'shortcut'
    )

    $text = Repair-ProdicloudShortcutTextEncoding -Value $Value
    if ([string]::IsNullOrWhiteSpace([string]$text)) {
        return [string]$Fallback
    }

    $normalized = $text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder
        $pendingSeparator = $false
    foreach ($character in $normalized.ToCharArray()) {
        $mapped = switch ([int][char]$character) {
            0x0131 { 'i'; break }
            0x0130 { 'i'; break }
            default { [string]$character; break }
        }

        foreach ($mappedCharacter in $mapped.ToCharArray()) {
            $unicodeCategory = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($mappedCharacter)
            if ($unicodeCategory -eq [Globalization.UnicodeCategory]::NonSpacingMark) {
                continue
            }

            if ([char]::IsLetterOrDigit($mappedCharacter)) {
                if ($pendingSeparator -and $builder.Length -gt 0 -and $builder[$builder.Length - 1] -ne '-') {
                    [void]$builder.Append('-')
                }

                [void]$builder.Append(([string]$mappedCharacter).ToLowerInvariant())
                $pendingSeparator = $false
                continue
            }

            $pendingSeparator = $true
        }
    }

    $safeName = [regex]::Replace($builder.ToString().Trim('-'), '-{2,}', '-')
    if ([string]::IsNullOrWhiteSpace([string]$safeName)) {
        return [string]$Fallback
    }

    return [string]$safeName
}

function Get-ProdicloudShortcutNormalizedKey {
    param([string]$Value)

    $safeSlug = ConvertTo-ProdicloudShortcutSafeSlug -Value $Value -Fallback ''
    if ([string]::IsNullOrWhiteSpace([string]$safeSlug)) {
        return ''
    }

    return ([string]$safeSlug).Replace('-', '')
}

function Get-ProdicloudShortcutLauncherFilePath {
    param(
        [string]$ShortcutName,
        [string]$Subdirectory = 'public-desktop'
    )

    $safeName = ConvertTo-ProdicloudShortcutSafeSlug -Value $ShortcutName -Fallback 'shortcut'

    return (Join-Path (Get-ProdicloudShortcutLauncherRoot -Subdirectory $Subdirectory) ($safeName + '.cmd'))
}

function Get-ProdicloudShortcutEffectiveCommandText {
    param(
        [string]$TargetPath,
        [string]$Arguments = ''
    )

    $targetText = [string]$TargetPath
    $argumentsText = [string]$Arguments
    if ([string]::IsNullOrWhiteSpace([string]$targetText)) {
        return ''
    }

    if ([string]::IsNullOrWhiteSpace([string]$argumentsText)) {
        return [string]$targetText
    }

    return ('{0} {1}' -f [string]$targetText, [string]$argumentsText).Trim()
}

function Get-ProdicloudShortcutManagedInvocationLength {
    param(
        [string]$TargetPath,
        [string]$Arguments = ''
    )

    $effectiveCommandText = Get-ProdicloudShortcutEffectiveCommandText -TargetPath $TargetPath -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace([string]$effectiveCommandText)) {
        return 0
    }

    return [int]$effectiveCommandText.Length
}

function Test-ProdicloudShortcutNeedsManagedLauncher {
    param(
        [string]$TargetPath,
        [string]$Arguments = '',
        [int]$Threshold = 259
    )

    if ($Threshold -lt 1) {
        $Threshold = 1
    }

    return ((Get-ProdicloudShortcutManagedInvocationLength -TargetPath $TargetPath -Arguments $Arguments) -gt $Threshold)
}

function Get-ProdicloudShortcutLauncherInvocationArguments {
    param([string]$LauncherPath)

    if ([string]::IsNullOrWhiteSpace([string]$LauncherPath)) {
        return ''
    }

    return ('/c call "{0}"' -f [string]$LauncherPath)
}

function Write-ProdicloudShortcutLauncherFile {
    param(
        [string]$LauncherPath,
        [string]$TargetPath,
        [string]$Arguments = '',
        [string]$WorkingDirectory = ''
    )

    if ([string]::IsNullOrWhiteSpace([string]$LauncherPath)) {
        throw 'LauncherPath is required.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$TargetPath)) {
        throw 'TargetPath is required for shortcut launcher generation.'
    }

    $launcherDirectory = Split-Path -Path $LauncherPath -Parent
    if (-not (Test-Path -LiteralPath $launcherDirectory)) {
        New-Item -Path $launcherDirectory -ItemType Directory -Force | Out-Null
    }

    $effectiveTargetPath = [string]$TargetPath
    $effectiveArguments = [string]$Arguments
    $effectiveWorkingDirectory = [string]$WorkingDirectory
    if ([string]::IsNullOrWhiteSpace([string]$effectiveWorkingDirectory)) {
        $effectiveWorkingDirectory = [string](Split-Path -Path $effectiveTargetPath -Parent)
    }

    $quotedTarget = '"{0}"' -f $effectiveTargetPath
    $commandLine = if ([string]::IsNullOrWhiteSpace([string]$effectiveArguments)) {
        $quotedTarget
    }
    else {
        ('{0} {1}' -f $quotedTarget, [string]$effectiveArguments).Trim()
    }

    $launcherLines = New-Object 'System.Collections.Generic.List[string]'
    [void]$launcherLines.Add('@echo off')
    [void]$launcherLines.Add('setlocal')
    [void]$launcherLines.Add(':: prodicloud-shortcut-launcher=1')
    [void]$launcherLines.Add((':: prodicloud-target-b64={0}' -f (ConvertTo-ProdicloudShortcutLauncherBase64 -Value $effectiveTargetPath)))
    [void]$launcherLines.Add((':: prodicloud-arguments-b64={0}' -f (ConvertTo-ProdicloudShortcutLauncherBase64 -Value $effectiveArguments)))
    [void]$launcherLines.Add((':: prodicloud-working-directory-b64={0}' -f (ConvertTo-ProdicloudShortcutLauncherBase64 -Value $effectiveWorkingDirectory)))
    if (-not [string]::IsNullOrWhiteSpace([string]$effectiveWorkingDirectory)) {
        [void]$launcherLines.Add(('cd /d "{0}"' -f $effectiveWorkingDirectory))
    }
    [void]$launcherLines.Add(('start "" {0}' -f $commandLine))
    [void]$launcherLines.Add('exit /b 0')
    [void]$launcherLines.Add('endlocal')

    Set-Content -LiteralPath $LauncherPath -Value $launcherLines -Encoding ASCII
    return [string]$LauncherPath
}

function Test-ProdicloudShortcutLauncherFile {
    param([string]$LauncherPath)

    if ([string]::IsNullOrWhiteSpace([string]$LauncherPath) -or -not (Test-Path -LiteralPath $LauncherPath)) {
        return $false
    }

    try {
        $firstLine = [string](Get-Content -LiteralPath $LauncherPath -TotalCount 3 -ErrorAction Stop | Select-Object -Skip 2 -First 1)
        return [string]::Equals($firstLine.Trim(), ':: prodicloud-shortcut-launcher=1', [System.StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Get-ProdicloudShortcutLauncherMetadata {
    param([string]$LauncherPath)

    if (-not (Test-ProdicloudShortcutLauncherFile -LauncherPath $LauncherPath)) {
        return $null
    }

    try {
        $lines = @(Get-Content -LiteralPath $LauncherPath -ErrorAction Stop)
    }
    catch {
        return $null
    }

    $targetText = ''
    $argumentsText = ''
    $workingDirectoryText = ''
    foreach ($line in @($lines)) {
        if ([string]$line -like ':: prodicloud-target-b64=*') {
            $targetText = ConvertFrom-ProdicloudShortcutLauncherBase64 -Value ([string]$line.Substring(':: prodicloud-target-b64='.Length))
            continue
        }
        if ([string]$line -like ':: prodicloud-arguments-b64=*') {
            $argumentsText = ConvertFrom-ProdicloudShortcutLauncherBase64 -Value ([string]$line.Substring(':: prodicloud-arguments-b64='.Length))
            continue
        }
        if ([string]$line -like ':: prodicloud-working-directory-b64=*') {
            $workingDirectoryText = ConvertFrom-ProdicloudShortcutLauncherBase64 -Value ([string]$line.Substring(':: prodicloud-working-directory-b64='.Length))
        }
    }

    return [pscustomobject]@{
        LauncherPath = [string]$LauncherPath
        TargetPath = [string]$targetText
        Arguments = [string]$argumentsText
        WorkingDirectory = [string]$workingDirectoryText
    }
}

function Get-ProdicloudShortcutLauncherPathFromInvocation {
    param(
        [string]$TargetPath,
        [string]$Arguments
    )

    $targetText = [string]$TargetPath
    if ([string]::IsNullOrWhiteSpace([string]$targetText)) {
        return ''
    }

    $targetLeaf = [System.IO.Path]::GetFileName([string]$targetText)
    if (-not [string]::Equals($targetLeaf, 'cmd.exe', [System.StringComparison]::OrdinalIgnoreCase)) {
        return ''
    }

    $argumentsText = [string][Environment]::ExpandEnvironmentVariables([string]$Arguments)
    if ([string]::IsNullOrWhiteSpace([string]$argumentsText)) {
        return ''
    }

    foreach ($pattern in @(
        '^(?i)/(?:c|k)\s+"([^"]+\.cmd)"$',
        '^(?i)/(?:c|k)\s+call\s+"([^"]+\.cmd)"$',
        '^(?i)/(?:c|k)\s+("?[^"\s]+\.cmd"?)$'
    )) {
        $match = [regex]::Match($argumentsText.Trim(), $pattern)
        if (-not $match.Success) {
            continue
        }

        $candidate = [string]$match.Groups[1].Value.Trim('"', ' ')
        if ([string]::IsNullOrWhiteSpace([string]$candidate)) {
            continue
        }

        $expandedCandidate = [Environment]::ExpandEnvironmentVariables($candidate)
        if (Test-ProdicloudShortcutLauncherFile -LauncherPath $expandedCandidate) {
            return [string]$expandedCandidate
        }

        $launcherRoot = Get-ProdicloudShortcutLauncherRoot
        if (-not [string]::IsNullOrWhiteSpace([string]$launcherRoot) -and
            $expandedCandidate.StartsWith($launcherRoot, [System.StringComparison]::OrdinalIgnoreCase) -and
            [string]::Equals([System.IO.Path]::GetExtension([string]$expandedCandidate), '.cmd', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [string]$expandedCandidate
        }
    }

    return ''
}

function Get-ProdicloudShortcutResolvedInvocation {
    param(
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory = ''
    )

    $launcherPath = Get-ProdicloudShortcutLauncherPathFromInvocation -TargetPath $TargetPath -Arguments $Arguments
    if ([string]::IsNullOrWhiteSpace([string]$launcherPath)) {
        return [pscustomobject]@{
            UsesManagedLauncher = $false
            LauncherPath = ''
            TargetPath = [string]$TargetPath
            Arguments = [string]$Arguments
            WorkingDirectory = [string]$WorkingDirectory
        }
    }

    $metadata = Get-ProdicloudShortcutLauncherMetadata -LauncherPath $launcherPath
    if ($null -eq $metadata) {
        return [pscustomobject]@{
            UsesManagedLauncher = $true
            LauncherPath = [string]$launcherPath
            TargetPath = ''
            Arguments = ''
            WorkingDirectory = ''
        }
    }

    return [pscustomobject]@{
        UsesManagedLauncher = $true
        LauncherPath = [string]$launcherPath
        TargetPath = [string]$metadata.TargetPath
        Arguments = [string]$metadata.Arguments
        WorkingDirectory = [string]$metadata.WorkingDirectory
    }
}

Export-ModuleMember -Function ConvertTo-ProdicloudShortcutLauncherBase64, ConvertFrom-ProdicloudShortcutLauncherBase64, Repair-ProdicloudShortcutTextEncoding, ConvertTo-ProdicloudShortcutSafeSlug, Get-ProdicloudShortcutNormalizedKey, Get-ProdicloudShortcutLauncherRoot, Get-ProdicloudShortcutLauncherFilePath, Get-ProdicloudShortcutEffectiveCommandText, Get-ProdicloudShortcutManagedInvocationLength, Test-ProdicloudShortcutNeedsManagedLauncher, Get-ProdicloudShortcutLauncherInvocationArguments, Write-ProdicloudShortcutLauncherFile, Test-ProdicloudShortcutLauncherFile, Get-ProdicloudShortcutLauncherMetadata, Get-ProdicloudShortcutLauncherPathFromInvocation, Get-ProdicloudShortcutResolvedInvocation
