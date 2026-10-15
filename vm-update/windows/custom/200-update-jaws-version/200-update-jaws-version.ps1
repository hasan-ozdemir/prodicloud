$ErrorActionPreference = 'Stop'
Write-Host 'Update task started: update-jaws-version'

function Resolve-ExecutableUnderDirectory {
    param(
        [string]$RootPath,
        [string]$ExecutableName
    )

    if ([string]::IsNullOrWhiteSpace([string]$RootPath) -or [string]::IsNullOrWhiteSpace([string]$ExecutableName)) {
        return ''
    }

    if (-not (Test-Path -LiteralPath $RootPath)) {
        return ''
    }

    $directCandidate = Join-Path $RootPath $ExecutableName
    if (Test-Path -LiteralPath $directCandidate) {
        return [string]$directCandidate
    }

    $match = Get-ChildItem -LiteralPath $RootPath -Filter $ExecutableName -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName | Select-Object -First 1
    if ($match -and (Test-Path -LiteralPath $match.FullName)) {
        return [string]$match.FullName
    }

    return ''
}

function Resolve-JawsInstallRoot {
    foreach ($registryPath in @(
        'HKLM:\Software\Freedom Scientific\JAWS\2025',
        'HKLM:\Software\WOW6432Node\Freedom Scientific\JAWS\2025'
    )) {
        if (-not (Test-Path -LiteralPath $registryPath)) {
            continue
        }

        $targetPath = [string](Get-ItemProperty -LiteralPath $registryPath -Name 'Target' -ErrorAction SilentlyContinue).Target
        if ([string]::IsNullOrWhiteSpace([string]$targetPath)) {
            continue
        }

        $normalizedPath = $targetPath.Trim().TrimEnd('\')
        if (Test-Path -LiteralPath $normalizedPath) {
            return [string]$normalizedPath
        }
    }

    foreach ($candidate in @(
        'C:\Program Files\Freedom Scientific\JAWS\2025',
        'C:\Program Files (x86)\Freedom Scientific\JAWS\2025'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ''
}

$jawsRoot = Resolve-JawsInstallRoot
$jawsExePath = Resolve-ExecutableUnderDirectory -RootPath $jawsRoot -ExecutableName 'jfw.exe'
$targetVersionDllPath = if ([string]::IsNullOrWhiteSpace([string]$jawsRoot)) { '' } else { Join-Path $jawsRoot 'version.dll' }

if ([string]::IsNullOrWhiteSpace([string]$jawsRoot) -or -not (Test-Path -LiteralPath $jawsRoot -PathType Container)) {
    throw 'JAWS 2025 root directory was not found.'
}

if ([string]::IsNullOrWhiteSpace([string]$jawsExePath) -or -not (Test-Path -LiteralPath $jawsExePath -PathType Leaf)) {
    throw ("JAWS 2025 executable was not found under install root: {0}" -f [string]$jawsRoot)
}

Write-Host ("JAWS 2025 install root is ready for app-state overlay: root={0}; exe={1}; target-file={2}" -f [string]$jawsRoot, [string]$jawsExePath, [string]$targetVersionDllPath)
Write-Host 'update-jaws-version-completed'
Write-Host 'Update task completed: update-jaws-version'
