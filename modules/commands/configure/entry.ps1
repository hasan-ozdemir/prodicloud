# Configure command entry.

# Handles Invoke-ProdicloudConfigureCommand.
function Invoke-ProdicloudConfigureCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $repoRoot = Get-ProdicloudRepoRoot
    $envFilePath = Join-Path $repoRoot 'prodicloud.env'
    Invoke-ProdicloudConfigureInteractiveEditor -RepoRoot $repoRoot -EnvFilePath $envFilePath -Perf:$PerfMode
}
