# Contract for the 'help' command.

function Get-ClagnosHelpOptionSpecifications {
    return @(
        (Get-ClagnosHelpHelpOptionSpecification)
    )
}
