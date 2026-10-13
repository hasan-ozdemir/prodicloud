# Imported runtime region: test-azure.

# Handles Assert-LocationExists.
function Assert-LocationExists {
    param(
        [string]$Location
    )

    $locationExists = Invoke-ClagnosWithBypassedAzCliSubscription -Action {
        az account list-locations --query "[?name=='$Location'].name | [0]" -o tsv --only-show-errors
    }
    if ($LASTEXITCODE -ne 0) {
        Throw-FriendlyError `
            -Detail "az account list-locations failed with exit code $LASTEXITCODE." `
            -Code 22 `
            -Summary "Failed to read the region list." `
            -Hint "Check Azure login status and subscription access."
    }
    if ([string]::IsNullOrWhiteSpace($locationExists)) {
        Throw-FriendlyError `
            -Detail "Region '$Location' was not found." `
            -Code 22 `
            -Summary "Region name is invalid or unavailable." `
            -Hint "Select a valid region with az account list-locations."
    }
}

# Handles Assert-VmImageAvailable.
function Assert-VmImageAvailable {
    param(
        [string]$Location,
        [string]$ImageUrn
    )

    az vm image show -l $Location --urn $ImageUrn -o none --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        Throw-FriendlyError `
            -Detail "az vm image show failed with exit code $LASTEXITCODE." `
            -Code 23 `
            -Summary "The selected image is not available in this region." `
            -Hint "Update vmImage URN to an image available in this region."
    }
}

# Handles Assert-VmSkuAvailableViaRest.
function Assert-VmSkuAvailableViaRest {
    param(
        [string]$Location,
        [string]$VmSize
    )

    $subscriptionId = az account show --query id -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        Throw-FriendlyError `
            -Detail "az account show failed with exit code $LASTEXITCODE." `
            -Code 24 `
            -Summary "Failed to read subscription information." `
            -Hint "Check Azure login status and active subscription selection."
    }
    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        Throw-FriendlyError `
            -Detail "Subscription ID could not be read." `
            -Code 24 `
            -Summary "Failed to read subscription information." `
            -Hint "Ensure az account show returns a valid id."
    }

    $sizesUrl = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Compute/locations/$Location/vmSizes"
    $sizeMatch = az rest `
        --method get `
        --url "$sizesUrl" `
        --uri-parameters "api-version=2021-07-01" `
        --query "value[?name=='$VmSize'].name | [0]" `
        -o tsv `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        Throw-FriendlyError `
            -Detail "az rest vmSizes list failed with exit code $LASTEXITCODE." `
            -Code 24 `
            -Summary "SKU availability pre-check could not be completed." `
            -Hint "Check Azure connectivity and az rest permissions."
    }

    if ([string]::IsNullOrWhiteSpace($sizeMatch)) {
        Throw-FriendlyError `
            -Detail "VM size '$VmSize' was not found in region '$Location'." `
            -Code 20 `
            -Summary "The VM size is not available in the selected region." `
            -Hint "Update vmSize or azLocation. The script cannot continue with an unsupported combination."
    }

    Write-ClagnosActionProgress -Action ("verify VM size '{0}' is offered to the active subscription in '{1}'" -f $VmSize, $Location)
    $subscriptionSkuJson = az vm list-skus `
        --location $Location `
        --resource-type virtualMachines `
        --size $VmSize `
        --output json `
        --only-show-errors
    Assert-LastExitCode 'az vm list-skus (subscription SKU availability)'
    $subscriptionSkuRows = @(
        ConvertTo-ObjectArrayCompat -InputObject (ConvertFrom-JsonCompat -InputObject $subscriptionSkuJson) |
            Where-Object { [string]::Equals([string]$_.name, [string]$VmSize, [System.StringComparison]::OrdinalIgnoreCase) }
    )
    if ($subscriptionSkuRows.Count -eq 0) {
        Throw-FriendlyError `
            -Detail "VM size '$VmSize' exists in region '$Location' but is not offered to the active Azure subscription there; subscription SKU restrictions may apply." `
            -Code 20 `
            -Summary "The VM size is not available to the active Azure subscription." `
            -Hint ("Choose a size returned by 'az vm list-skus --location {0} --resource-type virtualMachines --size <sku>'. The target VM has not been deallocated." -f $Location)
    }
}

# Handles Assert-VmOsDiskSizeCompatible.
function Assert-VmOsDiskSizeCompatible {
    param(
        [string]$Location,
        [string]$ImageUrn,
        [string]$VmDiskSizeGb
    )

    if (-not ($VmDiskSizeGb -match '^\d+$')) {
        Throw-FriendlyError `
            -Detail "Invalid VM disk size '$VmDiskSizeGb'." `
            -Code 25 `
            -Summary "Configured OS disk size is invalid." `
            -Hint "Set WIN_VM_DISK_SIZE_GB or LIN_VM_DISK_SIZE_GB to a positive integer."
    }

    $requestedDiskSize = [int]$VmDiskSizeGb
    $imageId = az vm image show -l $Location --urn $ImageUrn --query "id" -o tsv --only-show-errors
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($imageId)) {
        Throw-FriendlyError `
            -Detail "Image metadata could not be read for '$ImageUrn' in '$Location'." `
            -Code 25 `
            -Summary "OS disk size compatibility pre-check could not be completed." `
            -Hint "Check image URN/region validity and Azure read permissions."
    }

    $minimumDiskSizeText = az rest `
        --method get `
        --url "https://management.azure.com$($imageId)" `
        --uri-parameters "api-version=2024-03-01" `
        --query "properties.osDiskImage.sizeInGb" `
        -o tsv `
        --only-show-errors

    if ($LASTEXITCODE -ne 0) {
        Throw-FriendlyError `
            -Detail "Image disk-size metadata read failed for '$ImageUrn' in '$Location'." `
            -Code 25 `
            -Summary "OS disk size compatibility pre-check could not be completed." `
            -Hint "Check Azure connectivity and az rest permissions."
    }

    if (-not ($minimumDiskSizeText -match '^\d+$')) {
        return
    }

    $minimumDiskSize = [int]$minimumDiskSizeText
    Write-Host "Image minimum OS disk size: $minimumDiskSize GB. Configured: $requestedDiskSize GB."
    if ($requestedDiskSize -lt $minimumDiskSize) {
        Throw-FriendlyError `
            -Detail "Configured OS disk size '$requestedDiskSize GB' is smaller than image minimum '$minimumDiskSize GB'." `
            -Code 25 `
            -Summary "Configured OS disk size is incompatible with the selected image." `
            -Hint "Set WIN_VM_DISK_SIZE_GB or LIN_VM_DISK_SIZE_GB to at least $minimumDiskSize for image '$ImageUrn'."
    }
}
