# Shared 'vm-action' command option specification.

function Get-ProdicloudSharedVmActionOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'vm-action' -TakesValue)
}
