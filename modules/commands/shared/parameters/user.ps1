# Shared 'user' command option specification.

function Get-ProdicloudSharedUserOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'user' -TakesValue)
}
