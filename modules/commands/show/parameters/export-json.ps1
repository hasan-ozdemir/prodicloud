# 'export-json' option binding for 'show'.

function Get-ClagnosShowExportJsonOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'export-json' -TakesValue)
}
