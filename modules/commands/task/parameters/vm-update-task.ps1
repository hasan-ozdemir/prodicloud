# 'vm-update-task' option binding for 'task'.

function Get-ClagnosTaskVmUpdateTaskOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'vm-update-task' -TakesValue)
}
