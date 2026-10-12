# Shared 'vm-action' command option specification.

function Get-ClagnosSharedVmActionOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-action' -TakesValue)
}
