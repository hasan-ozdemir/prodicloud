# Shared 'vm-name' command option specification.

function Get-ProdicloudSharedVmNameOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'vm-name' -ShortNames @('v') -TakesValue)
}
