# Contract for the 'configure' command.

function Get-ClagnosConfigureOptionSpecifications {
    return @(
        (Get-ClagnosConfigurePerfOptionSpecification),
        (Get-ClagnosConfigureHelpOptionSpecification)
    )
}
