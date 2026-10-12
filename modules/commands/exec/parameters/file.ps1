# 'file' option binding for 'exec'.

function Get-ClagnosExecFileOptionSpecification {
    return (New-ClagnosCommandOptionSpecification -Name 'file' -ShortNames @('f') -TakesValue)
}
