# Contract for the 'delete' command.

function Get-ClagnosDeleteOptionSpecifications {
    return @(
        (Get-ClagnosDeleteAutoOptionSpecification),
        (Get-ClagnosDeletePerfOptionSpecification),
        (Get-ClagnosDeleteHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosDeleteTargetOptionSpecification),
        (Get-ClagnosDeleteGroupOptionSpecification),
        (Get-ClagnosDeleteYesOptionSpecification)
    )
}
