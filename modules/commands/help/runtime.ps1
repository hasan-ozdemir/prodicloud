# Help command runtime helper.

function Invoke-ClagnosHelpCommand {
    param(
        [string]$HelpTopic = ''
    )

    if ([string]::Equals([string]$HelpTopic, '__overview__', [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-ClagnosCommandHelp -Overview
    }
    else {
        Show-ClagnosCommandHelp -Topic $HelpTopic
    }
}
