# Shared 'command' command option specification.

function Get-ProdicloudSharedCommandOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'command' -ShortNames @('c') -TakesValue)
}
