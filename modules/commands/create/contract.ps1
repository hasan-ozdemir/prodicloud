# Contract for the 'create' command.

function Get-ClagnosCreateOptionSpecifications {
    return @(
        (Get-ClagnosCreateAutoOptionSpecification),
        (Get-ClagnosCreatePerfOptionSpecification),
        (Get-ClagnosCreateWindowsOptionSpecification),
        (Get-ClagnosCreateLinuxOptionSpecification),
        (Get-ClagnosCreateHelpOptionSpecification),
        (Get-ClagnosCreateStepToOptionSpecification),
        (Get-ClagnosCreateStepFromOptionSpecification),
        (Get-ClagnosCreateStepOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosCreateVmNameOptionSpecification),
        (Get-ClagnosCreateVmRegionOptionSpecification),
        (Get-ClagnosCreateVmSizeOptionSpecification)
    )
}
