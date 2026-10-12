# 'disk-size' option binding for 'resize'.

function Get-ClagnosResizeDiskSizeOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'disk-size' -TakesValue)
}
