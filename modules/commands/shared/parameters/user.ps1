# Shared 'user' command option specification.

function Get-ClagnosSharedUserOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'user' -TakesValue)
}
