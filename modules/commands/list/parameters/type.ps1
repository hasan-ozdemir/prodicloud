# 'type' option binding for 'list'.

function Get-ProdicloudListTypeOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'type' -TakesValue -Validate {
        param([hashtable]$Options)
        [void](Resolve-ProdicloudListRequestedTypes -Options $Options)
    })
}
