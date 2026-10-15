# Contract for the initialize command.

function Get-ClagnosInitializeOptionSpecifications {
    $updateSpecifications = @(Get-ClagnosUpdateOptionSpecifications)
    $specifications = @(
        $updateSpecifications | Where-Object { [string]$_.Name -notin @('step','step-from','step-to') }
    )
    $specifications += New-ClagnosCommandOptionSpecification -Name 'reset-managed-user-passwords'
    return @($specifications)
}
