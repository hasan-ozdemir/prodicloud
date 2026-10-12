# Create command entry.

function Invoke-ClagnosCreateCommand {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $runtime = New-ClagnosCreateCommandRuntime -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -AutoMode:$AutoMode
    $script:UpdateMode = $false
    $script:ExecutionMode = 'default'
    Invoke-ClagnosMain -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -CommandName 'create' -Step1OperationName ([string]$runtime.Step1OperationName) -InitialConfigOverrides $runtime.InitialConfigOverrides -ActionPlan $runtime.ActionPlan
}
