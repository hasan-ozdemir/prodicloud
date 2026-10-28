# Contract for the 'help' command.

function Get-ProdicloudHelpOptionSpecifications {
    return @(
        (Get-ProdicloudHelpHelpOptionSpecification)
    )
}
