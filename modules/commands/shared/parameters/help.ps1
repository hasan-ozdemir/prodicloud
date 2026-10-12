# Shared 'help' command option specification.

function Get-ClagnosSharedHelpOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'help' -ShortNames @('h'))
}
