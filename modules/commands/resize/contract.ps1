# Contract for the 'resize' command.

function Get-ProdicloudResizeOptionSpecifications {
    return @(
        (Get-ProdicloudResizePerfOptionSpecification),
        (Get-ProdicloudResizeHelpOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudResizeGroupOptionSpecification),
        (Get-ProdicloudResizeVmNameOptionSpecification),
        (Get-ProdicloudResizeVmSizeOptionSpecification),
        (Get-ProdicloudResizeDiskNameOptionSpecification),
        (Get-ProdicloudResizeDiskSizeOptionSpecification),
        (Get-ProdicloudResizeExpandOptionSpecification),
        (Get-ProdicloudResizeShrinkOptionSpecification),
        (Get-ProdicloudSharedYesOptionSpecification),
        (Get-ProdicloudResizeWindowsOptionSpecification),
        (Get-ProdicloudResizeLinuxOptionSpecification)
    )
}
