# Shared 'help' command option specification.

function Get-ProdicloudSharedHelpOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'help' -ShortNames @('h'))
}
