# Shared 'quiet' command option specification.

function Get-ProdicloudSharedQuietOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'quiet' -ShortNames @('q'))
}
