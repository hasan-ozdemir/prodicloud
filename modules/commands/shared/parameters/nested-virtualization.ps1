# Shared 'nested-virtualization' command option specification.

function Get-ProdicloudSharedNestedVirtualizationOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'nested-virtualization' -TakesValue)
}
