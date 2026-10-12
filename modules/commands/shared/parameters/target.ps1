# Shared 'target' command option specification.

function Get-ClagnosSharedTargetOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'target' -TakesValue)
}
