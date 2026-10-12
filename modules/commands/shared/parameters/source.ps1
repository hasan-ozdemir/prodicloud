# Shared 'source' command option specification.

function Get-ClagnosSharedSourceOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'source' -TakesValue)
}
