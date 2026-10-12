# Contract for the initialize command.

function Get-ClagnosInitializeOptionSpecifications {
    $updateSpecifications = @(Get-ClagnosUpdateOptionSpecifications)
    return @(
        $updateSpecifications | Where-Object { [string]$_.Name -notin @('step','step-from','step-to') }
    )
}
