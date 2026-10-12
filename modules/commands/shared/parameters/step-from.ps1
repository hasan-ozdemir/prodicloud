# Shared 'step-from' command option specification.

function Get-ClagnosSharedStepFromOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'step-from' -TakesValue)
}
