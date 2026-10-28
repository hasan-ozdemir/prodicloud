# 'disk-name' option binding for 'resize'.

function Get-ProdicloudResizeDiskNameOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'disk-name' -TakesValue)
}
