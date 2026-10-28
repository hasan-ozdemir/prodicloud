# Update command entry.

function Invoke-ProdicloudUpdateCommand {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $runtime = New-ProdicloudUpdateCommandRuntime -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -AutoMode:$AutoMode
    $script:UpdateMode = $true
    $script:ExecutionMode = 'update'
    Invoke-ProdicloudMain -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -CommandName 'update' -InitialConfigOverrides $runtime.InitialConfigOverrides -ActionPlan $runtime.ActionPlan
}
