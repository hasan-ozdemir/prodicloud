# Update command entry.

function Invoke-ClagnosUpdateCommand {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $runtime = New-ClagnosUpdateCommandRuntime -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -AutoMode:$AutoMode
    $script:UpdateMode = $true
    $script:ExecutionMode = 'update'
    Invoke-ClagnosMain -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -CommandName 'update' -InitialConfigOverrides $runtime.InitialConfigOverrides -ActionPlan $runtime.ActionPlan
}
