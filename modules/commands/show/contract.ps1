# Contract for the 'show' command.

function Get-ClagnosShowOptionSpecifications {
    return @(
        (Get-ClagnosShowPerfOptionSpecification),
        (Get-ClagnosShowHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosShowGroupOptionSpecification),
        (Get-ClagnosShowVmNameOptionSpecification),
        (Get-ClagnosShowExportJsonOptionSpecification),
        (Get-ClagnosShowOverwriteOptionSpecification)
    )
}
