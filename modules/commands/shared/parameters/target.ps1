# Shared 'target' command option specification.

function Get-ProdicloudSharedTargetOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'target' -TakesValue)
}
