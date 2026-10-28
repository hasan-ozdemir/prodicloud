# Precheck step orchestration.

# Handles Invoke-ProdicloudPrecheckStep.
function Invoke-ProdicloudPrecheckStep {
    param(
        [hashtable]$Context
    )

    Show-ProdicloudStepFirstUseValues `
        -StepLabel "Step 1/7 - resource availability precheck" `
        -Context $Context `
        -Keys @("AzLocation", "VmImage", "VmSize", "VmDiskSize")

    Assert-LocationExists -Location $Context.AzLocation
    Assert-VmImageAvailable -Location $Context.AzLocation -ImageUrn $Context.VmImage
    Assert-VmSkuAvailableViaRest -Location $Context.AzLocation -VmSize $Context.VmSize
    Assert-VmOsDiskSizeCompatible -Location $Context.AzLocation -ImageUrn $Context.VmImage -VmDiskSizeGb $Context.VmDiskSize
    Assert-ProdicloudSecurityTypePreconditions -Context $Context
    Assert-ProdicloudFeaturePreconditions -Context $Context
}
