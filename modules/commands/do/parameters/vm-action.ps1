# 'vm-action' option binding for 'do'.

function Get-ClagnosDoVmActionOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-action' -Validate {
        param([hashtable]$Options)
        if (Test-ClagnosCliOptionPresent -Options $Options -Name 'vm-action') {
            [void](Resolve-ClagnosDoActionName -RawValue ([string](Get-ClagnosCliOptionText -Options $Options -Name 'vm-action')) -AllowEmpty)
        }
    })
}
