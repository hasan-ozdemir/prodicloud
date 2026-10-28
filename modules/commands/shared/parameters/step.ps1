# Shared 'step' command option specification.

function Get-ProdicloudSharedStepOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'step' -TakesValue)
}
