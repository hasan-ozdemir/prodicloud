# Initialize command entry.

function Invoke-ProdicloudInitializeCommand {
    param(
        [hashtable]$Options,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag,
        [switch]$AutoMode
    )

    $resetManagedUserPasswords = Get-ProdicloudCliOptionBool -Options $Options -Name 'reset-managed-user-passwords' -DefaultValue $false
    if ($resetManagedUserPasswords -and $AutoMode) {
        throw '--reset-managed-user-passwords is available only in interactive initialize mode so the operator can confirm the credential change.'
    }
    $runtime = New-ProdicloudUpdateCommandRuntime -Options $Options -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag -AutoMode:$AutoMode
    if ($resetManagedUserPasswords) {
        $profileName = [string]$runtime.InitialConfigOverrides['SELECTED_VM_NAME']
        if ([string]::IsNullOrWhiteSpace([string]$profileName)) { $profileName = 'the selected VC' }
        $confirmation = Read-Host ("This will reset the manager and assistant passwords to the values in {0}.env. Type RESET MANAGED USER PASSWORDS to continue" -f $profileName)
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
    $script:ProdicloudResetManagedUserPasswords = [bool]$resetManagedUserPasswords
    try {
        Invoke-ProdicloudMain `
            -WindowsFlag:$WindowsFlag `
            -LinuxFlag:$LinuxFlag `
            -CommandName 'initialize' `
            -Step1OperationName 'update' `
            -InitialConfigOverrides $runtime.InitialConfigOverrides `
            -ActionPlan $initActionPlan
    }
    finally { $script:ProdicloudResetManagedUserPasswords = $false }
}
