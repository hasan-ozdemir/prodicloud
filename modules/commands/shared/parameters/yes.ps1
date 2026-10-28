# Shared 'yes' command option specification.

function Get-ProdicloudSharedYesOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'yes' -ShortNames @('y'))
}
