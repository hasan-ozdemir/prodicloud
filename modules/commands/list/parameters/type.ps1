# 'type' option binding for 'list'.

function Get-ClagnosListTypeOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'type' -TakesValue -Validate {
        param([hashtable]$Options)
        [void](Resolve-ClagnosListRequestedTypes -Options $Options)
    })
}
