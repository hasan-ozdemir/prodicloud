# Shared 'hibernation' command option specification.

function Get-ProdicloudSharedHibernationOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'hibernation' -TakesValue)
}
