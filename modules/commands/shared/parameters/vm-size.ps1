# Shared 'vm-size' command option specification.

function Get-ProdicloudSharedVmSizeOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'vm-size' -TakesValue)
}
