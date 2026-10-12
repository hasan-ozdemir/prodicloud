# Help command entry.

function Invoke-ClagnosHelpEntry {
    param(
        [string]$HelpTopic = ''
    )

    Invoke-ClagnosHelpCommand -HelpTopic $HelpTopic
}
