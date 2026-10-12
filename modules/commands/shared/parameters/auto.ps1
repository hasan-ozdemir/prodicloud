# Shared 'auto' command option specification.

function Get-ClagnosSharedAutoOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'auto' -ShortNames @('a'))
}
