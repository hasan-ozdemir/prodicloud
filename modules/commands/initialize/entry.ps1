# Initialize command entry.

function Invoke-ClagnosInitializeCommand {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $runtime = New-ClagnosUpdateCommandRuntime -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -AutoMode:$AutoMode
    $initActionPlan = [pscustomobject]@{
        Mode = 'single'
        Target = 'vm-init'
        Actions = @('vm-init')
    }
    $script:UpdateMode = $true
    $script:ExecutionMode = 'update'
    Invoke-ClagnosMain `
        -WindowsFlag:$WindowsFlag `
        -LinuxFlag:$LinuxFlag `
        -CommandName 'initialize' `
        -Step1OperationName 'update' `
        -InitialConfigOverrides $runtime.InitialConfigOverrides `
        -ActionPlan $initActionPlan
}
