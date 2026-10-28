# Move command entry.

# Handles Invoke-ProdicloudMoveCommand.
function Invoke-ProdicloudMoveCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    if (Test-ProdicloudCliOptionPresent -Options $Options -Name 'vm-size') {
        Throw-FriendlyError `
            -Detail "Option '--vm-size' is not supported with move command." `
            -Code 62 `
            -Summary "Unsupported option for move command." `
            -Hint "Use resize command for VM size updates."
    }

    $forwardOptions = Copy-ProdicloudOptionsMap -Source $Options
    if (-not (Test-ProdicloudCliOptionPresent -Options $forwardOptions -Name 'vm-region')) {
        $forwardOptions['vm-region'] = ''
    }

    $regionValue = [string](Get-ProdicloudCliOptionText -Options $forwardOptions -Name 'vm-region')
    $effectiveAutoMode = $AutoMode -or (-not [string]::IsNullOrWhiteSpace([string]$regionValue))
    Invoke-ProdicloudChangeCommand -Options $forwardOptions -AutoMode:$effectiveAutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -OperationLabel 'move'
}
