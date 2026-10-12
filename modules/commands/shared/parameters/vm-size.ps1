# Shared 'vm-size' command option specification.

function Get-ClagnosSharedVmSizeOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-size' -TakesValue)
}
