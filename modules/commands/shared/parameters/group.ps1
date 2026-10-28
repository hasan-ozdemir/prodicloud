# Shared 'group' command option specification.

function Get-ProdicloudSharedGroupOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'group' -ShortNames @('g') -TakesValue)
}
