# Shared 'hibernation' command option specification.

function Get-ClagnosSharedHibernationOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'hibernation' -TakesValue)
}
