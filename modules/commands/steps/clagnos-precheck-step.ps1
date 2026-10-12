# Precheck step orchestration.

# Handles Invoke-ClagnosPrecheckStep.
function Invoke-ClagnosPrecheckStep {
    param(
        [hashtable]$Context
    )

    Show-ClagnosStepFirstUseValues `
        -StepLabel "Step 1/7 - resource availability precheck" `
        -Context $Context `
        -Keys @("AzLocation", "VmImage", "VmSize", "VmDiskSize")

    Assert-LocationExists -Location $Context.AzLocation
    Assert-VmImageAvailable -Location $Context.AzLocation -ImageUrn $Context.VmImage
    Assert-VmSkuAvailableViaRest -Location $Context.AzLocation -VmSize $Context.VmSize
    Assert-VmOsDiskSizeCompatible -Location $Context.AzLocation -ImageUrn $Context.VmImage -VmDiskSizeGb $Context.VmDiskSize
    Assert-ClagnosSecurityTypePreconditions -Context $Context
    Assert-ClagnosFeaturePreconditions -Context $Context
}
