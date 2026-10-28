# Contract for the 'delete' command.

function Get-ProdicloudDeleteOptionSpecifications {
    return @(
        (Get-ProdicloudDeleteAutoOptionSpecification),
        (Get-ProdicloudDeletePerfOptionSpecification),
        (Get-ProdicloudDeleteHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudDeleteTargetOptionSpecification),
        (Get-ProdicloudDeleteGroupOptionSpecification),
        (Get-ProdicloudDeleteYesOptionSpecification)
    )
}
