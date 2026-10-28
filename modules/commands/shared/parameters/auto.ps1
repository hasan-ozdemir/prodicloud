# Shared 'auto' command option specification.

function Get-ProdicloudSharedAutoOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'auto' -ShortNames @('a'))
}
