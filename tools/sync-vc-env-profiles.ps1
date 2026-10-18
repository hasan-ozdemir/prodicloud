[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$templatePath = Join-Path $RepoRoot 'vc.env.example'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { throw 'vc.env.example is required to synchronize VC profiles.' }

$templateValues = [ordered]@{}
foreach ($line in @(Get-Content -LiteralPath $templatePath -ErrorAction Stop)) {
    $match = [regex]::Match([string]$line,'^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<value>.*)$')
    if ($match.Success) { $templateValues[[string]$match.Groups['key'].Value] = [string]$match.Groups['value'].Value }
}

$profiles = @(Get-ChildItem -LiteralPath $RepoRoot -File -Filter '*.env' -ErrorAction Stop | Where-Object { $_.Name -ine 'clagnos.env' -and $_.Name -match '^[A-Za-z0-9][A-Za-z0-9-]{0,63}\.env$' })
$updatedCount = 0
foreach ($profile in @($profiles)) {
    $profileName = [System.IO.Path]::GetFileNameWithoutExtension($profile.Name)
    $text = [System.IO.File]::ReadAllText($profile.FullName)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @([regex]::Split($text,"\r\n|\n|\r"))) { $lines.Add([string]$line) }
    $values = @{}
    foreach ($line in @($lines.ToArray())) {
        $match = [regex]::Match([string]$line,'^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<value>.*)$')
        if ($match.Success) { $values[[string]$match.Groups['key'].Value] = [string]$match.Groups['value'].Value.Trim().Trim('"',"'") }
    }
    if ($values.ContainsKey('SELECTED_VM_NAME') -and -not [string]::IsNullOrWhiteSpace([string]$values['SELECTED_VM_NAME']) -and
        -not [string]::Equals([string]$values['SELECTED_VM_NAME'],$profileName,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Profile identity mismatch in '{0}'; no profile files were written." -f $profile.Name)
    }

    $changed = $false
    foreach ($key in @($templateValues.Keys)) {
        if ($values.ContainsKey([string]$key)) { continue }
        $value = [string]$templateValues[$key]
        if ($key -eq 'SELECTED_VM_NAME') { $value = $profileName }
        $lines.Add(('{0}={1}' -f [string]$key,$value))
        $changed = $true
    }
    if (-not $values.ContainsKey('SELECTED_VM_NAME') -or [string]::IsNullOrWhiteSpace([string]$values['SELECTED_VM_NAME'])) {
        $identityPattern = '^\s*SELECTED_VM_NAME\s*=.*$'
        $found = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match $identityPattern) { $lines[$index] = ('SELECTED_VM_NAME={0}' -f $profileName); $found = $true; $changed = $true; break }
        }
        if (-not $found) { $lines.Add(('SELECTED_VM_NAME={0}' -f $profileName)); $changed = $true }
    }
    if (-not $values.ContainsKey('VC_PROFILE_SCHEMA_VERSION') -or [string]$values['VC_PROFILE_SCHEMA_VERSION'] -ne '2') {
        $versionPattern = '^\s*VC_PROFILE_SCHEMA_VERSION\s*=.*$'
        $found = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match $versionPattern) { $lines[$index] = 'VC_PROFILE_SCHEMA_VERSION=2'; $found = $true; break }
        }
        if (-not $found) { $lines.Add('VC_PROFILE_SCHEMA_VERSION=2') }
        $changed = $true
    }

    if (-not $changed) { continue }
    if (-not $PSCmdlet.ShouldProcess($profile.Name,'add only missing VC profile schema keys')) { continue }
    if ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$lines[$lines.Count - 1])) { $lines.RemoveAt($lines.Count - 1) }
    $temporaryPath = $profile.FullName + '.clagnos-schema.tmp'
    try {
        [System.IO.File]::WriteAllText($temporaryPath,($lines -join $newline),[System.Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $profile.FullName -Force -ErrorAction Stop
    }
    finally { if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue } }
    $updatedCount++
    Write-Host ("VC profile schema synchronized: {0}" -f $profile.Name)
}

Write-Host ("VC profile schema synchronization complete: updated={0}, found={1}." -f $updatedCount,$profiles.Count)
