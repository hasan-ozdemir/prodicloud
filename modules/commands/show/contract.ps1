# Contract for the 'show' command.

function Get-ProdicloudShowOptionSpecifications {
    return @(
        (Get-ProdicloudShowPerfOptionSpecification),
        (Get-ProdicloudShowHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudShowGroupOptionSpecification),
        (Get-ProdicloudShowVmNameOptionSpecification),
        (Get-ProdicloudShowExportJsonOptionSpecification),
        (Get-ProdicloudShowOverwriteOptionSpecification)
    )
}
