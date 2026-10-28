# Contract for the 'configure' command.

function Get-ProdicloudConfigureOptionSpecifications {
    return @(
        (Get-ProdicloudConfigurePerfOptionSpecification),
        (Get-ProdicloudConfigureHelpOptionSpecification)
    )
}
