# Help command runtime helper.

function Invoke-ProdicloudHelpCommand {
    param(
        [string]$HelpTopic = ''
    )

    if ([string]::Equals([string]$HelpTopic, '__overview__', [System.StringComparison]::OrdinalIgnoreCase)) {
        Show-ProdicloudCommandHelp -Overview
    }
    else {
        Show-ProdicloudCommandHelp -Topic $HelpTopic
    }
}
