# Program management command entry.

function Invoke-ClagnosProgramCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $action = [string](Get-ClagnosCliOptionText -Options $Options -Name 'action')
    $programId = [string](Get-ClagnosCliOptionText -Options $Options -Name 'program')
    if ([string]::IsNullOrWhiteSpace($action)) {
        Throw-FriendlyError -Detail "Program command requires an action." -Code 2 -Summary "Program operation is incomplete." -Hint "Use --action=list|status|install|uninstall."
    }
    Invoke-ClagnosProgramOperation -Action $action.Trim().ToLowerInvariant() -ProgramId $programId -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
}
