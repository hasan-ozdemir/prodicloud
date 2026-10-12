# Contract for the 'update' command.

function Get-ClagnosUpdateOptionSpecifications {
    return @(
        (Get-ClagnosUpdateAutoOptionSpecification),
        (Get-ClagnosUpdatePerfOptionSpecification),
        (Get-ClagnosUpdateWindowsOptionSpecification),
        (Get-ClagnosUpdateLinuxOptionSpecification),
        (Get-ClagnosUpdateHelpOptionSpecification),
        (Get-ClagnosUpdateStepToOptionSpecification),
        (Get-ClagnosUpdateStepFromOptionSpecification),
        (Get-ClagnosUpdateStepOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosUpdateGroupOptionSpecification),
        (Get-ClagnosUpdateVmNameOptionSpecification)
    )
}
