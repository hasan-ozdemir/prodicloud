# Contract for the 'do' command.

function Get-ProdicloudDoOptionSpecifications {
    return @(
        (Get-ProdicloudDoPerfOptionSpecification),
        (Get-ProdicloudDoHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudDoGroupOptionSpecification),
        (Get-ProdicloudDoVmNameOptionSpecification),
        (Get-ProdicloudDoVmActionOptionSpecification)
    )
}
