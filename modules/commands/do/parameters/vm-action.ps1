# 'vm-action' option binding for 'do'.

function Get-ProdicloudDoVmActionOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'vm-action' -Validate {
        param([hashtable]$Options)
        if (Test-ProdicloudCliOptionPresent -Options $Options -Name 'vm-action') {
            [void](Resolve-ProdicloudDoActionName -RawValue ([string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-action')) -AllowEmpty)
        }
    })
}
