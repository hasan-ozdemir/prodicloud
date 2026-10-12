# Shared 'vm-region' command option specification.

function Get-ClagnosSharedVmRegionOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-region' -TakesValue)
}
