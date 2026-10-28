# Help command entry.

function Invoke-ProdicloudHelpEntry {
    param(
        [string]$HelpTopic = ''
    )

    Invoke-ProdicloudHelpCommand -HelpTopic $HelpTopic
}
