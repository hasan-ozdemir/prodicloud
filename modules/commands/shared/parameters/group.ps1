# Shared 'group' command option specification.

function Get-ClagnosSharedGroupOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'group' -ShortNames @('g') -TakesValue)
}
