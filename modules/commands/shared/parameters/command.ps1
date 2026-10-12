# Shared 'command' command option specification.

function Get-ClagnosSharedCommandOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'command' -ShortNames @('c') -TakesValue)
}
