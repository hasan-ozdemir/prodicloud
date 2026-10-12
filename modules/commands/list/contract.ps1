# Contract for the 'list' command.

function Get-ClagnosListOptionSpecifications {
    return @(
        (Get-ClagnosListPerfOptionSpecification),
        (Get-ClagnosListHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosListGroupOptionSpecification),
        (Get-ClagnosListTypeOptionSpecification)
    )
}
