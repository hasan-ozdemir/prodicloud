$ErrorActionPreference = "Stop"
Write-Host "Init task started: ensure-managed-user-cross-access"

$managerUser = "__VM_ADMIN_USER__"
$assistantUser = "__ASSISTANT_USER__"
$publicRoot = "C:\Users\Public"
$modifyRights = [System.Security.AccessControl.FileSystemRights]::Modify
$taskDetails = New-Object 'System.Collections.Generic.List[string]'

function Write-CrossAccessDetail {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace([string]$Text)) {
        return
    }

    $taskDetails.Add([string]$Text) | Out-Null
    Write-Host ([string]$Text)
}

function Get-ValidatedProfilePath {
    param([string]$UserName)

    if ([string]::IsNullOrWhiteSpace([string]$UserName)) {
        throw "User name is empty."
    }

    $profilePath = Join-Path 'C:\Users' ([string]$UserName)
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw ("Profile path was not found: {0}" -f [string]$UserName)
    }

    return [string]$profilePath
}

function Resolve-Sid {
    param([string]$Identity)

    if ([string]::IsNullOrWhiteSpace([string]$Identity)) {
        throw "Identity is empty."
    }

    try {
        return [System.Security.Principal.NTAccount]::new([string]$Identity).Translate([System.Security.Principal.SecurityIdentifier])
    }
    catch {
        throw ("Failed to resolve identity: {0}" -f [string]$Identity)
    }
}

function Test-HasModifyAccess {
    param(
        [System.Security.AccessControl.DirectorySecurity]$Acl,
        [System.Security.Principal.SecurityIdentifier]$IdentitySid
    )

    if ($null -eq $Acl -or $null -eq $IdentitySid) {
        return $false
    }

    $requiredValue = [int]$modifyRights
    foreach ($rule in @($Acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
        if ($null -eq $rule -or $null -eq $rule.IdentityReference) {
            continue
        }

        if ([string]$rule.IdentityReference -ne [string]$IdentitySid.Value) {
            continue
        }

        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            continue
        }

        if (([int]$rule.FileSystemRights -band $requiredValue) -ne $requiredValue) {
            continue
        }

        return $true
    }

    return $false
}

function Grant-PathModifyAccess {
    param(
        [string]$Path,
        [string]$Identity
    )

    if ([string]::IsNullOrWhiteSpace([string]$Path) -or -not (Test-Path -LiteralPath $Path)) {
        throw ("Path was not found: {0}" -f [string]$Path)
    }

    $identitySid = Resolve-Sid -Identity $Identity
    $acl = Get-Acl -LiteralPath $Path
    if (Test-HasModifyAccess -Acl $acl -IdentitySid $identitySid) {
        Write-CrossAccessDetail ("cross-access-ok: {0} => {1}" -f [string]$Path, [string]$Identity)
        return
    }

    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags](
        ([int][System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
        [int][System.Security.AccessControl.InheritanceFlags]::ObjectInherit)
    )
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $identitySid,
        $modifyRights,
        $inheritanceFlags,
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    [void]$acl.AddAccessRule($accessRule)
    Set-Acl -LiteralPath $Path -AclObject $acl | Out-Null
    Write-CrossAccessDetail ("cross-access-updated: {0} => {1}" -f [string]$Path, [string]$Identity)
}

$managerProfilePath = Get-ValidatedProfilePath -UserName $managerUser
$assistantProfilePath = Get-ValidatedProfilePath -UserName $assistantUser
if (-not (Test-Path -LiteralPath $publicRoot)) {
    throw ("Public root was not found: {0}" -f $publicRoot)
}

$targetMap = @(
    @{ Path = $managerProfilePath; Identity = $assistantUser },
    @{ Path = $assistantProfilePath; Identity = $managerUser },
    @{ Path = $publicRoot; Identity = $managerUser },
    @{ Path = $publicRoot; Identity = $assistantUser }
)

foreach ($entry in @($targetMap)) {
    Grant-PathModifyAccess -Path ([string]$entry.Path) -Identity ([string]$entry.Identity)
}

Write-Host ("cross-access-summary: profile={0},{1}; public={2}; rules={3}" -f
    [string]$managerUser, [string]$assistantUser, $publicRoot, [int]$taskDetails.Count)

Write-Host "Init task completed: ensure-managed-user-cross-access"
