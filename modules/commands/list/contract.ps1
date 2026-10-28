# Contract for the 'list' command.

function Get-ProdicloudListOptionSpecifications {
    return @(
        (Get-ProdicloudListPerfOptionSpecification),
        (Get-ProdicloudListHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudListGroupOptionSpecification),
        (Get-ProdicloudListTypeOptionSpecification)
    )
}
