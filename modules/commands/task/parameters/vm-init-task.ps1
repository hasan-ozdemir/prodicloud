# 'vm-init-task' option binding for 'task'.

function Get-ProdicloudTaskVmInitTaskOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'vm-init-task' -TakesValue)
}
