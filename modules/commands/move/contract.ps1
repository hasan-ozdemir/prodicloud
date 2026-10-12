# Contract for the 'move' command.

function Get-ClagnosMoveOptionSpecifications {
    return @(
        (Get-ClagnosMovePerfOptionSpecification),
        (Get-ClagnosMoveHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosMoveGroupOptionSpecification),
        (Get-ClagnosMoveVmNameOptionSpecification),
        (Get-ClagnosMoveVmRegionOptionSpecification)
    )
}
