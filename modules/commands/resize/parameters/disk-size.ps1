# 'disk-size' option binding for 'resize'.

function Get-ProdicloudResizeDiskSizeOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'disk-size' -TakesValue)
}
