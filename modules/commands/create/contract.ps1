# Contract for the 'create' command.

function Get-ProdicloudCreateOptionSpecifications {
    return @(
        (Get-ProdicloudCreateAutoOptionSpecification),
        (Get-ProdicloudCreatePerfOptionSpecification),
        (Get-ProdicloudCreateWindowsOptionSpecification),
        (Get-ProdicloudCreateLinuxOptionSpecification),
        (Get-ProdicloudCreateHelpOptionSpecification),
        (Get-ProdicloudCreateStepToOptionSpecification),
        (Get-ProdicloudCreateStepFromOptionSpecification),
        (Get-ProdicloudCreateStepOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudCreateVmNameOptionSpecification),
        (Get-ProdicloudCreateVmRegionOptionSpecification),
        (Get-ProdicloudCreateVmSizeOptionSpecification)
    )
}
