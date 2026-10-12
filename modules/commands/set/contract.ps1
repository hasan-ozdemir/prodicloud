# Contract for the 'set' command.

function Get-ClagnosSetOptionSpecifications {
    return @(
        (Get-ClagnosSetPerfOptionSpecification),
        (Get-ClagnosSetHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosSetGroupOptionSpecification),
        (Get-ClagnosSetVmNameOptionSpecification),
        (Get-ClagnosSetHibernationOptionSpecification),
        (Get-ClagnosSetNestedVirtualizationOptionSpecification)
    )
}
