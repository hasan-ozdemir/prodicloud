# Shared 'vm-name' command option specification.

function Get-ClagnosSharedVmNameOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-name' -ShortNames @('v') -TakesValue)
}
