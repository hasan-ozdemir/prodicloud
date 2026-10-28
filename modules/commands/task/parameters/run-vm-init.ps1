# 'run-vm-init' option binding for 'task'.

function Get-ProdicloudTaskRunVmInitOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'run-vm-init' -TakesValue)
}
