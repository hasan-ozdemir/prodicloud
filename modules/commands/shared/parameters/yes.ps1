# Shared 'yes' command option specification.

function Get-ClagnosSharedYesOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'yes' -ShortNames @('y'))
}
