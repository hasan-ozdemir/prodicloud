# Configure command entry.

# Handles Invoke-ClagnosConfigureCommand.
function Invoke-ClagnosConfigureCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    Invoke-ClagnosConfigureInteractiveEditor -RepoRoot $repoRoot -EnvFilePath $envFilePath -Perf:$PerfMode
}
