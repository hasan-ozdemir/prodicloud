# Contract for the 'exec' command.

function Get-ProdicloudExecOptionSpecifications {
    return @(
        (Get-ProdicloudExecPerfOptionSpecification),
        (Get-ProdicloudExecHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudExecGroupOptionSpecification),
        (Get-ProdicloudExecVmNameOptionSpecification),
        (Get-ProdicloudExecFileOptionSpecification),
        (Get-ProdicloudExecCommandContentOptionSpecification),
        (Get-ProdicloudExecQuietOptionSpecification)
    )
}
