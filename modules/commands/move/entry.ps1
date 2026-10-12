# Move command entry.

# Handles Invoke-ClagnosMoveCommand.
function Invoke-ClagnosMoveCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    if (Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-size') {
        Throw-FriendlyError `
            -Detail "Option '--vm-size' is not supported with move command." `
            -Code 62 `
            -Summary "Unsupported option for move command." `
            -Hint "Use resize command for VM size updates."
    }

    $forwardOptions = Copy-ClagnosOptionsMap -Source $Options
    if (-not (Test-ClagnosCliOptionPresent -Options $forwardOptions -Name 'vm-region')) {
        $forwardOptions['vm-region'] = ''
    }

    $regionValue = [string](Get-ClagnosCliOptionText -Options $forwardOptions -Name 'vm-region')
    $effectiveAutoMode = $AutoMode -or (-not [string]::IsNullOrWhiteSpace([string]$regionValue))
    Invoke-ClagnosChangeCommand -Options $forwardOptions -AutoMode:$effectiveAutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -OperationLabel 'move'
}
