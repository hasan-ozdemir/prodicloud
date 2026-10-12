# 'run-vm-init' option binding for 'task'.

function Get-ClagnosTaskRunVmInitOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'run-vm-init' -TakesValue)
}
