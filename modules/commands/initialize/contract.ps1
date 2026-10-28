# Contract for the initialize command.

function Get-ProdicloudInitializeOptionSpecifications {
    $updateSpecifications = @(Get-ProdicloudUpdateOptionSpecifications)
    $specifications = @(
        $updateSpecifications | Where-Object { [string]$_.Name -notin @('step','step-from','step-to') }
    )
    $specifications += New-ProdicloudCommandOptionSpecification -Name 'reset-managed-user-passwords'
    return @($specifications)
}
