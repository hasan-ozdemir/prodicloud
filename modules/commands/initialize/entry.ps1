# Initialize command entry.

function Invoke-ClagnosInitializeCommand {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $resetManagedUserPasswords = Get-ClagnosCliOptionBool -Options $Options -Name 'reset-managed-user-passwords' -DefaultValue $false
    if ($resetManagedUserPasswords -and $AutoMode) {
        throw '--reset-managed-user-passwords is available only in interactive initialize mode so the operator can confirm the credential change.'
    }
    $runtime = New-ClagnosUpdateCommandRuntime -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -AutoMode:$AutoMode
    if ($resetManagedUserPasswords) {
        $confirmation = Read-Host 'This will reset the manager and assistant passwords to the values in .env. Type RESET MANAGED USER PASSWORDS to continue'
        if (-not [string]::Equals([string]$confirmation,'RESET MANAGED USER PASSWORDS',[System.StringComparison]::Ordinal)) {
            Write-Host 'Managed-user password reset canceled; no guest task was run.' -ForegroundColor Yellow
            return
        }
    }
    $initActionPlan = [pscustomobject]@{
        Mode = 'single'
        Target = 'vm-init'
        Actions = @('vm-init')
    }
    $script:UpdateMode = $true
    $script:ExecutionMode = 'update'
    $script:ClagnosResetManagedUserPasswords = [bool]$resetManagedUserPasswords
    try {
        Invoke-ClagnosMain `
            -WindowsFlag:$WindowsFlag `
            -LinuxFlag:$LinuxFlag `
            -CommandName 'initialize' `
            -Step1OperationName 'update' `
            -InitialConfigOverrides $runtime.InitialConfigOverrides `
            -ActionPlan $initActionPlan
    }
    finally { $script:ClagnosResetManagedUserPasswords = $false }
}
