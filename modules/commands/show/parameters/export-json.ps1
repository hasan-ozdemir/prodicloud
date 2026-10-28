# 'export-json' option binding for 'show'.

function Get-ProdicloudShowExportJsonOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'export-json' -TakesValue)
}
