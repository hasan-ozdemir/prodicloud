# Contract for the 'exec' command.

function Get-ClagnosExecOptionSpecifications {
    return @(
        (Get-ClagnosExecPerfOptionSpecification),
        (Get-ClagnosExecHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosExecGroupOptionSpecification),
        (Get-ClagnosExecVmNameOptionSpecification),
        (Get-ClagnosExecFileOptionSpecification),
        (Get-ClagnosExecCommandContentOptionSpecification),
        (Get-ClagnosExecQuietOptionSpecification)
    )
}
