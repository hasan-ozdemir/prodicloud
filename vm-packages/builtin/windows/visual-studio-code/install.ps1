$ErrorActionPreference = "Stop"
Write-Host "Update task started: install-vscode-application"

$taskConfig = [ordered]@{
    PortableWingetPath = 'C:\ProgramData\prodicloud\tools\winget-x64\winget.exe'
    VsCodePackageId = 'Microsoft.VisualStudioCode'
    CodeExecutableCandidates = @(
        'C:\Program Files\Microsoft VS Code\Code.exe',
        'C:\Users\__VM_ADMIN_USER__\AppData\Local\Programs\Microsoft VS Code\Code.exe',
        'C:\Users\__ASSISTANT_USER__\AppData\Local\Programs\Microsoft VS Code\Code.exe'
    )
}

Import-Module 'C:\Windows\Temp\prodicloud-session-environment.psm1' -Force -DisableNameChecking

function Refresh-SessionPath {
    Refresh-ProdicloudSessionPath | Out-Null
}

function Resolve-WingetExe {
    $portableCandidate = [string]$taskConfig.PortableWingetPath
    if (Test-Path -LiteralPath $portableCandidate) {
        return [string]$portableCandidate
    }

    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd -and -not [string]::IsNullOrWhiteSpace([string]$cmd.Source)) {
        return [string]$cmd.Source
    }

    return ""
}

function Resolve-CodeExecutable {
    $command = Get-Command code -ErrorAction SilentlyContinue
    if ($command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        return [string]$command.Source
    }

    foreach ($candidate in @($taskConfig.CodeExecutableCandidates)) {
        if (Test-Path -LiteralPath $candidate) {
            return [string]$candidate
        }
    }

    return ""
}

Refresh-SessionPath
$existingCodeExe = Resolve-CodeExecutable
if (-not [string]::IsNullOrWhiteSpace([string]$existingCodeExe)) {
    Write-Host ("Visual Studio Code executable already exists: {0}" -f $existingCodeExe)
    Write-Host "Existing Visual Studio Code installation is already healthy. Skipping winget install."
    Write-Host "install-vscode-application-completed"
    Write-Host "Update task completed: install-vscode-application"
    return
}

$wingetExe = Resolve-WingetExe
if ([string]::IsNullOrWhiteSpace([string]$wingetExe)) {
    throw "winget command is not available."
}

Write-Host "Resolved winget executable: $wingetExe"
Write-Host ("Running: winget install {0} --accept-source-agreements --accept-package-agreements --silent --disable-interactivity" -f [string]$taskConfig.VsCodePackageId)
& $wingetExe install ([string]$taskConfig.VsCodePackageId) --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
$installExit = [int]$LASTEXITCODE
if ($installExit -ne 0 -and $installExit -ne -1978335189) {
    throw ("winget install {0} failed with exit code {1}." -f [string]$taskConfig.VsCodePackageId, $installExit)
}

Refresh-SessionPath
$codeExe = Resolve-CodeExecutable
if ([string]::IsNullOrWhiteSpace([string]$codeExe)) {
    Write-Host ("Running: winget list {0}" -f [string]$taskConfig.VsCodePackageId)
    $listOutput = & $wingetExe list ([string]$taskConfig.VsCodePackageId)
    $listText = [string]($listOutput | Out-String)
    if ([string]::IsNullOrWhiteSpace($listText) -or -not $listText.ToLowerInvariant().Contains(([string]$taskConfig.VsCodePackageId).ToLowerInvariant())) {
        throw "Visual Studio Code install could not be verified."
    }
}

Write-Host "install-vscode-application-completed"
Write-Host "Update task completed: install-vscode-application"

