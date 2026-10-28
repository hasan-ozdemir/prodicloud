# Shared 'vm-region' command option specification.

function Get-ProdicloudSharedVmRegionOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'vm-region' -TakesValue)
}
