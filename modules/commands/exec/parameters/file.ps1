# 'file' option binding for 'exec'.

function Get-ProdicloudExecFileOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'file' -ShortNames @('f') -TakesValue)
}
