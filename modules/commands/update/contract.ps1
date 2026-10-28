# Contract for the 'update' command.

function Get-ProdicloudUpdateOptionSpecifications {
    return @(
        (Get-ProdicloudUpdateAutoOptionSpecification),
        (Get-ProdicloudUpdatePerfOptionSpecification),
        (Get-ProdicloudUpdateWindowsOptionSpecification),
        (Get-ProdicloudUpdateLinuxOptionSpecification),
        (Get-ProdicloudUpdateHelpOptionSpecification),
        (Get-ProdicloudUpdateStepToOptionSpecification),
        (Get-ProdicloudUpdateStepFromOptionSpecification),
        (Get-ProdicloudUpdateStepOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudUpdateGroupOptionSpecification),
        (Get-ProdicloudUpdateVmNameOptionSpecification)
    )
}
