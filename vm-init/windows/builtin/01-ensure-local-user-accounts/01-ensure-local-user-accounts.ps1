$ErrorActionPreference = "Stop"
Write-Host "Init task started: ensure-local-user-accounts"

$vmUser = "__VM_ADMIN_USER__"
$vmPass = "__VM_ADMIN_PASS__"
$assistantUser = "__ASSISTANT_USER__"
$assistantPass = "__ASSISTANT_PASS__"
$resetExistingManagedPasswords = "__RESET_MANAGED_USER_PASSWORDS__" -match '^(?i:true|1|yes|on)$'

function Normalize-Identity {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return $Value.Trim().ToLowerInvariant()
}

function Ensure-GroupMembership {
    param(
        [string]$GroupName,
        [string]$MemberName
    )

    $normalizedTarget = Normalize-Identity -Value $MemberName
    $members = @(Get-LocalGroupMember -Group $GroupName -ErrorAction Stop)
    foreach ($member in $members) {
        $existingMember = Normalize-Identity -Value ([string]$member.Name)
        if ($existingMember -eq $normalizedTarget) {
            Write-Host "User '$MemberName' is already in local group '$GroupName'."
            return
        }
    }

    try {
        Add-LocalGroupMember -Group $GroupName -Member $MemberName -ErrorAction Stop
        Write-Host "User '$MemberName' was added to local group '$GroupName'."
    }
    catch {
        $msg = [string]$_.Exception.Message
        if ($msg -match '(?i)(already a member|1378|already belongs)') {
            Write-Host "User '$MemberName' is already in local group '$GroupName'."
            return
        }
        throw "Adding '$MemberName' to '$GroupName' failed. $msg"
    }
}

function Ensure-LocalUserUnlocked {
    param([string]$TargetUser)

    try {
        net user $TargetUser /active:yes
    }
    catch {
        Write-Warning "Could not enforce active state for '$TargetUser': $($_.Exception.Message)"
    }

    try {
        $adsiPath = "WinNT://$env:COMPUTERNAME/$TargetUser,user"
        $adsiUser = [ADSI]$adsiPath
        $isLocked = $false
        try { $isLocked = [bool]$adsiUser.InvokeGet("IsAccountLocked") } catch { }
        if ($isLocked) {
            $adsiUser.InvokeSet("IsAccountLocked", $false)
            $adsiUser.SetInfo()
            Write-Host "User '$TargetUser' lockout state was cleared."
        }
    }
    catch {
        Write-Warning "User '$TargetUser' lockout verification failed: $($_.Exception.Message)"
    }
}

function Ensure-LocalPowerAdmin {
    param(
        [string]$UserName,
        [string]$Password
    )

    if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
        $securePass = ConvertTo-SecureString $Password -AsPlainText -Force
        New-LocalUser -Name $UserName -Password $securePass -PasswordNeverExpires -AccountNeverExpires -FullName $UserName -Description "Azure VM Power Admin user"
    }
    else {
        if ($resetExistingManagedPasswords) {
            Write-Host ("Doing: reset the explicitly requested password for managed user '{0}'" -f $UserName)
            $securePass = ConvertTo-SecureString $Password -AsPlainText -Force
            Set-LocalUser -Name $UserName -Password $securePass -ErrorAction Stop
            Write-Host ("Managed user '{0}' password was reset from the current prodicloud.env value." -f $UserName)
        }
        else {
            Write-Host "Managed user '$UserName' already exists; preserving its current password."
        }
    }

    Ensure-LocalUserUnlocked -TargetUser $UserName
    Ensure-GroupMembership -GroupName "Administrators" -MemberName $UserName
    Ensure-GroupMembership -GroupName "Remote Desktop Users" -MemberName $UserName
}

Ensure-LocalPowerAdmin -UserName $vmUser -Password $vmPass
Ensure-LocalPowerAdmin -UserName $assistantUser -Password $assistantPass

Write-Host "local-admin-users-ready"
Write-Host "Init task completed: ensure-local-user-accounts"

