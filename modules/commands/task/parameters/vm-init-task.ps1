# 'vm-init-task' option binding for 'task'.

function Get-ClagnosTaskVmInitTaskOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-init-task' -TakesValue)
}
