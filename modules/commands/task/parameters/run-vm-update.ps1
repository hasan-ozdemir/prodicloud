# 'run-vm-update' option binding for 'task'.

function Get-ClagnosTaskRunVmUpdateOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'run-vm-update' -TakesValue)
}
