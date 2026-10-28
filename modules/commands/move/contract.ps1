# Contract for the 'move' command.

function Get-ProdicloudMoveOptionSpecifications {
    return @(
        (Get-ProdicloudMovePerfOptionSpecification),
        (Get-ProdicloudMoveHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudMoveGroupOptionSpecification),
        (Get-ProdicloudMoveVmNameOptionSpecification),
        (Get-ProdicloudMoveVmRegionOptionSpecification)
    )
}
