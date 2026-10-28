# Contract for the 'set' command.

function Get-ProdicloudSetOptionSpecifications {
    return @(
        (Get-ProdicloudSetPerfOptionSpecification),
        (Get-ProdicloudSetHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudSetGroupOptionSpecification),
        (Get-ProdicloudSetVmNameOptionSpecification),
        (Get-ProdicloudSetHibernationOptionSpecification),
        (Get-ProdicloudSetNestedVirtualizationOptionSpecification)
    )
}
