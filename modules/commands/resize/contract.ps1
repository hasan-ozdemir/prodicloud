# Contract for the 'resize' command.

function Get-ClagnosResizeOptionSpecifications {
    return @(
        (Get-ClagnosResizePerfOptionSpecification),
        (Get-ClagnosResizeHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosResizeGroupOptionSpecification),
        (Get-ClagnosResizeVmNameOptionSpecification),
        (Get-ClagnosResizeVmSizeOptionSpecification),
        (Get-ClagnosResizeDiskSizeOptionSpecification),
        (Get-ClagnosResizeExpandOptionSpecification),
        (Get-ClagnosResizeShrinkOptionSpecification),
        (Get-ClagnosResizeWindowsOptionSpecification),
        (Get-ClagnosResizeLinuxOptionSpecification)
    )
}
