# Shared 'nested-virtualization' command option specification.

function Get-ClagnosSharedNestedVirtualizationOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'nested-virtualization' -TakesValue)
}
