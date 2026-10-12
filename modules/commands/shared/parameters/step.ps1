# Shared 'step' command option specification.

function Get-ClagnosSharedStepOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'step' -TakesValue)
}
