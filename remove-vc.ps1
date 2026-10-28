[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-z0-9][a-z0-9-]{1,62}$')]
    [string]$VmName,
    [switch]$PreflightOnly,
    [string]$SubscriptionId = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:RemoveRepoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$script:RemoveVmName = $VmName.Trim().ToLowerInvariant()
$script:RemoveVmEnvPath = Join-Path $script:RemoveRepoRoot ($script:RemoveVmName + '.env')
$script:RemoveStatePath = Join-Path $script:RemoveRepoRoot ('.remove-' + $script:RemoveVmName + '.state.json')
$script:RemoveGlobalEnvPath = Join-Path $script:RemoveRepoRoot 'prodicloud.env'
$script:RemoveCgPath = Join-Path $script:RemoveRepoRoot 'pd.cmd'
$script:RemoveSubscriptionId = ''
$script:RemoveGroups = @()
$script:RemoveResourceNames = @($script:RemoveVmName)
$script:RemoveCapturedResources = New-Object 'System.Collections.Generic.List[object]'
$script:RemoveTranscriptStarted = $false
$script:RemoveTranscriptPath = Join-Path (Join-Path $script:RemoveRepoRoot '.logs') ('prodicloud-remove-' + $script:RemoveVmName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')

function Write-RemoveDoing {
    param([Parameter(Mandatory = $true)][string]$Action)
    Write-Host ("Doing: {0}" -f $Action) -ForegroundColor Cyan
}

function Assert-RemoveElevatedSession {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run remove-vc*.cmd from an elevated PowerShell or Command Prompt. The unattended runner will not open an interactive UAC prompt.'
    }
}

function Get-RemoveEnvValue {
    param([Parameter(Mandatory = $true)][string]$Path,[Parameter(Mandatory = $true)][string]$Key)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $text = [System.IO.File]::ReadAllText($Path)
    $match = [regex]::Match($text,'(?m)^\s*' + [regex]::Escape($Key) + '\s*=(.*)$')
    if (-not $match.Success) { return '' }
    $value = [string]$match.Groups[1].Value.Trim()
    if ($value.Length -ge 2 -and (($value[0] -eq '"' -and $value[$value.Length - 1] -eq '"') -or ($value[0] -eq "'" -and $value[$value.Length - 1] -eq "'"))) {
        $value = $value.Substring(1,$value.Length - 2)
    }
    return $value
}

function Invoke-RemoveAzJson {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-RemoveDoing $Action
    $output = & az @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("Azure CLI failed while attempting to {0} (exit {1})." -f $Action,$exitCode) }
    if ([string]::IsNullOrWhiteSpace([string]$output)) { return $null }
    try { return (ConvertFrom-Json -InputObject ([string]($output -join [Environment]::NewLine)) -ErrorAction Stop) }
    catch { throw ("Azure CLI returned unreadable data while attempting to {0}." -f $Action) }
}

function Invoke-RemoveAzText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments,[Parameter(Mandatory = $true)][string]$Action)
    Write-RemoveDoing $Action
    $output = & az @Arguments 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw ("Azure CLI failed while attempting to {0} (exit {1})." -f $Action,$exitCode) }
    return [string]($output -join [Environment]::NewLine).Trim()
}

function Get-RemoveSubscriptionId {
    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) { return $SubscriptionId.Trim() }
    return (Get-RemoveEnvValue -Path $script:RemoveGlobalEnvPath -Key 'SELECTED_AZURE_SUBSCRIPTION_ID').Trim()
}

function Add-RemoveResourceName {
    param([string]$Name)
    if (-not [string]::IsNullOrWhiteSpace($Name) -and @($script:RemoveResourceNames | Where-Object { [string]::Equals([string]$_,$Name,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
        $script:RemoveResourceNames += $Name.Trim()
    }
}

function Add-RemoveCapturedResource {
    param([object]$Resource)
    if ($null -eq $Resource) { return }
    $resourceId = [string]$Resource.Id
    if ([string]::IsNullOrWhiteSpace($resourceId)) { $resourceId = [string]$Resource.id }
    if ([string]::IsNullOrWhiteSpace($resourceId)) { return }
    if (@($script:RemoveCapturedResources | Where-Object { [string]::Equals([string]$_.Id,$resourceId,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) { return }
    $resourceName = [string]$Resource.Name
    if ([string]::IsNullOrWhiteSpace($resourceName)) { $resourceName = [string]$Resource.name }
    $resourceType = [string]$Resource.Type
    if ([string]::IsNullOrWhiteSpace($resourceType)) { $resourceType = [string]$Resource.type }
    $resourceGroup = [string]$Resource.ResourceGroup
    if ([string]::IsNullOrWhiteSpace($resourceGroup)) { $resourceGroup = [string]$Resource.resourceGroup }
    [void]$script:RemoveCapturedResources.Add([pscustomobject]@{ Id = $resourceId; Name = $resourceName; Type = $resourceType; ResourceGroup = $resourceGroup })
    Add-RemoveResourceName -Name $resourceName
}

function Import-RemoveJournal {
    if (-not (Test-Path -LiteralPath $script:RemoveStatePath -PathType Leaf)) { return }
    Write-RemoveDoing ("resume prior hard-purge journal '{0}'" -f [System.IO.Path]::GetFileName($script:RemoveStatePath))
    try { $journal = Get-Content -LiteralPath $script:RemoveStatePath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw ("Purge journal '{0}' is unreadable; refusing to guess its Azure scope." -f [System.IO.Path]::GetFileName($script:RemoveStatePath)) }
    if (-not [string]::Equals([string]$journal.vmName,$script:RemoveVmName,[System.StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([string]$journal.subscriptionId,$script:RemoveSubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Purge journal target does not match the requested VM and subscription; select the original subscription to resume it.'
    }
    foreach ($groupName in @($journal.resourceGroups)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$groupName) -and @($script:RemoveGroups | Where-Object { [string]::Equals([string]$_,[string]$groupName,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { $script:RemoveGroups += [string]$groupName }
    }
    foreach ($resource in @($journal.resources)) { Add-RemoveCapturedResource -Resource $resource }
}

function Save-RemoveJournal {
    $journal = [ordered]@{
        schemaVersion = 1
        vmName = $script:RemoveVmName
        subscriptionId = $script:RemoveSubscriptionId
        resourceGroups = @($script:RemoveGroups | Sort-Object -Unique)
        resources = @($script:RemoveCapturedResources.ToArray())
    }
    $temporaryPath = $script:RemoveStatePath + '.tmp'
    $json = ConvertTo-Json -InputObject $journal -Depth 8
    [System.IO.File]::WriteAllText($temporaryPath,$json,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $script:RemoveStatePath -Force -ErrorAction Stop
}

function Get-RemoveTargetGroups {
    if (-not (Test-Path -LiteralPath $script:RemoveVmEnvPath -PathType Leaf)) {
        throw ("VC profile '{0}' was not found; refusing to infer a purge target." -f [System.IO.Path]::GetFileName($script:RemoveVmEnvPath))
    }
    $profileVmName = (Get-RemoveEnvValue -Path $script:RemoveVmEnvPath -Key 'SELECTED_VM_NAME').Trim()
    if (-not [string]::IsNullOrWhiteSpace($profileVmName) -and -not [string]::Equals($profileVmName,$script:RemoveVmName,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw ("Profile '{0}' identifies '{1}', not requested VM '{2}'." -f [System.IO.Path]::GetFileName($script:RemoveVmEnvPath),$profileVmName,$script:RemoveVmName)
    }
    Import-RemoveJournal

    foreach ($key in @('VNET_NAME','SUBNET_NAME','NSG_NAME','NSG_RULE_NAME','PUBLIC_IP_NAME','NIC_NAME','VM_DISK_NAME')) {
        Add-RemoveResourceName -Name (Get-RemoveEnvValue -Path $script:RemoveVmEnvPath -Key $key)
    }

    $configuredGroup = (Get-RemoveEnvValue -Path $script:RemoveVmEnvPath -Key 'SELECTED_RESOURCE_GROUP').Trim()
    $groups = New-Object 'System.Collections.Generic.List[string]'
    foreach ($journalGroup in @($script:RemoveGroups)) { if (@($groups | Where-Object { [string]::Equals([string]$_,[string]$journalGroup,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { [void]$groups.Add([string]$journalGroup) } }
    if (-not [string]::IsNullOrWhiteSpace($configuredGroup)) { [void]$groups.Add($configuredGroup) }

    $vms = Invoke-RemoveAzJson -Arguments @('vm','list','--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action ("find VM '{0}' across the selected subscription" -f $script:RemoveVmName)
    $matchingVms = @($vms | Where-Object { [string]::Equals([string]$_.name,$script:RemoveVmName,[System.StringComparison]::OrdinalIgnoreCase) })
    if ($matchingVms.Count -gt 1) { throw ("More than one VM named '{0}' exists in the selected subscription; refusing an ambiguous purge." -f $script:RemoveVmName) }
    if ($matchingVms.Count -eq 1) {
        $actualGroup = [string]$matchingVms[0].resourceGroup
        if ([string]::IsNullOrWhiteSpace($actualGroup)) { throw ("Azure did not report a resource group for VM '{0}'." -f $script:RemoveVmName) }
        if (@($groups | Where-Object { [string]::Equals([string]$_,$actualGroup,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { [void]$groups.Add($actualGroup) }
    }

    $allResources = Invoke-RemoveAzJson -Arguments @('resource','list','--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action 'inventory subscription resources for exact VC-profile remnants'
    $matchingNames = @($allResources | Where-Object {
        $resourceName = [string]$_.name
        @($script:RemoveResourceNames | Where-Object { [string]::Equals([string]$_,$resourceName,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    })
    foreach ($resource in @($matchingNames)) {
        $resourceGroup = [string]$resource.resourceGroup
        if ([string]::IsNullOrWhiteSpace($resourceGroup)) { continue }
        if (@($groups | Where-Object { [string]::Equals([string]$_,$resourceGroup,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) { [void]$groups.Add($resourceGroup) }
    }

    foreach ($resource in @($allResources | Where-Object {
        $resourceName = [string]$_.name
        @($script:RemoveResourceNames | Where-Object { [string]::Equals([string]$_,$resourceName,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    })) { Add-RemoveCapturedResource -Resource $resource }

    foreach ($groupName in @($groups)) {
        $exists = Invoke-RemoveAzText -Arguments @('group','exists','--name',$groupName,'--subscription',$script:RemoveSubscriptionId,'--output','tsv','--only-show-errors') -Action ("check whether target group '{0}' still exists" -f $groupName)
        if (-not [string]::Equals($exists,'true',[System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $group = Invoke-RemoveAzJson -Arguments @('group','show','--name',$groupName,'--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action ("verify ownership of target group '{0}'" -f $groupName)
        if ([string]$group.tags.'managed-by' -notin @('prodicloud','prodicloud')) {
            throw ("Target group '{0}' is not tagged as Prodicloud-managed; refusing to delete it." -f $groupName)
        }
    }
    $script:RemoveGroups = @($groups.ToArray() | Sort-Object -Unique)
    return @($script:RemoveGroups)
}

function Invoke-RemoveGroup {
    param([Parameter(Mandatory = $true)][string]$GroupName)
    $exists = Invoke-RemoveAzText -Arguments @('group','exists','--name',$GroupName,'--subscription',$script:RemoveSubscriptionId,'--output','tsv','--only-show-errors') -Action ("check target group '{0}' before purge" -f $GroupName)
    if (-not [string]::Equals($exists,'true',[System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("Already absent: resource group '{0}'." -f $GroupName) -ForegroundColor DarkGray
        return
    }
    $resources = Invoke-RemoveAzJson -Arguments @('resource','list','--resource-group',$GroupName,'--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action ("inventory every resource in '{0}' before purge" -f $GroupName)
    Write-Host ("Purge target: Prodicloud-managed resource group '{0}' ({1} resource(s))." -f $GroupName,@($resources).Count) -ForegroundColor Yellow
    foreach ($resource in @($resources)) {
        Write-Host ('  - {0}: {1}' -f [string]$resource.type,[string]$resource.name)
        Add-RemoveCapturedResource -Resource $resource
    }
    Save-RemoveJournal
    Write-RemoveDoing ("delete all resources and the complete managed resource group '{0}'" -f $GroupName)
    & $script:RemoveCgPath 'delete' '--target' 'group' '--group' $GroupName '--yes' '--auto' '--subscription-id' $script:RemoveSubscriptionId
    if ($LASTEXITCODE -ne 0) { throw ("pd.cmd failed while purging resource group '{0}' (exit {1})." -f $GroupName,$LASTEXITCODE) }

    $removed = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        $exists = Invoke-RemoveAzText -Arguments @('group','exists','--name',$GroupName,'--subscription',$script:RemoveSubscriptionId,'--output','tsv','--only-show-errors') -Action ("verify deletion of group '{0}' (check {1}/60)" -f $GroupName,$attempt)
        if (-not [string]::Equals($exists,'true',[System.StringComparison]::OrdinalIgnoreCase)) { $removed = $true; break }
        if ($attempt -lt 60) {
            Write-Host ("Resource group '{0}' is still deleting; checking again in 10 seconds." -f $GroupName) -ForegroundColor DarkGray
            Start-Sleep -Seconds 10
        }
    }
    if (-not $removed) { throw ("Resource group '{0}' still exists after the bounded 600-second deletion check." -f $GroupName) }
    Write-Host ("Purged resource group '{0}'." -f $GroupName) -ForegroundColor Green
}

function Assert-RemoveTargetAbsent {
    $remainingGroups = @()
    foreach ($groupName in @($script:RemoveGroups)) {
        $exists = Invoke-RemoveAzText -Arguments @('group','exists','--name',$groupName,'--subscription',$script:RemoveSubscriptionId,'--output','tsv','--only-show-errors') -Action ("verify resource group '{0}' is absent" -f $groupName)
        if ([string]::Equals($exists,'true',[System.StringComparison]::OrdinalIgnoreCase)) { $remainingGroups += $groupName }
    }
    if ($remainingGroups.Count -gt 0) { throw ("Resource groups remain after purge: {0}." -f ($remainingGroups -join ', ')) }

    $remainingResources = Invoke-RemoveAzJson -Arguments @('resource','list','--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action 'recheck exact VC resource names after purge'
    $leftovers = @($remainingResources | Where-Object {
        $resourceName = [string]$_.name
        @($script:RemoveResourceNames | Where-Object { [string]::Equals([string]$_,$resourceName,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    })
    if ($leftovers.Count -gt 0) {
        $details = @($leftovers | ForEach-Object { '{0} ({1}/{2})' -f [string]$_.name,[string]$_.resourceGroup,[string]$_.type })
        throw ("Exact VC-profile resources remain in Azure after group purge: {0}." -f ($details -join ', '))
    }
    foreach ($resource in @($script:RemoveCapturedResources.ToArray())) {
        $resourceId = [string]$resource.Id
        $capturedGroup = [string]$resource.ResourceGroup
        if (@($script:RemoveGroups | Where-Object { [string]::Equals([string]$_,$capturedGroup,[System.StringComparison]::OrdinalIgnoreCase) }).Count -eq 0) {
            throw ("Captured resource '{0}' belongs to group '{1}', which was not in the verified purge scope." -f $resourceId,$capturedGroup)
        }
        if (@($remainingResources | Where-Object { [string]::Equals([string]$_.id,$resourceId,[System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
            throw ("Captured Azure resource '{0}' still exists in the subscription inventory after purge." -f $resourceId)
        }
        Write-RemoveDoing ("verify captured Azure resource id is absent from subscription inventory: {0}" -f $resourceId)
    }
    if (Test-Path -LiteralPath $script:RemoveStatePath -PathType Leaf) {
        Write-RemoveDoing ("remove verified purge journal '{0}'" -f [System.IO.Path]::GetFileName($script:RemoveStatePath))
        Remove-Item -LiteralPath $script:RemoveStatePath -Force -ErrorAction Stop
    }
}

try {
    Assert-RemoveElevatedSession
    if (-not (Test-Path -LiteralPath $script:RemoveGlobalEnvPath -PathType Leaf)) { throw "Local prodicloud.env was not found; cannot resolve the selected Azure subscription." }
    if (-not (Test-Path -LiteralPath $script:RemoveCgPath -PathType Leaf)) { throw 'pd.cmd was not found at the repository root.' }
    $script:RemoveSubscriptionId = Get-RemoveSubscriptionId
    if ([string]::IsNullOrWhiteSpace($script:RemoveSubscriptionId)) { throw 'Set SELECTED_AZURE_SUBSCRIPTION_ID in prodicloud.env or pass -SubscriptionId.' }
    if (-not (Test-Path -LiteralPath (Split-Path -Path $script:RemoveTranscriptPath -Parent) -PathType Container)) { New-Item -ItemType Directory -Path (Split-Path -Path $script:RemoveTranscriptPath -Parent) -Force | Out-Null }
    Start-Transcript -LiteralPath $script:RemoveTranscriptPath -Force | Out-Null
    $script:RemoveTranscriptStarted = $true
    Write-Host ("Removal transcript: {0}" -f $script:RemoveTranscriptPath) -ForegroundColor DarkGray
    $account = Invoke-RemoveAzJson -Arguments @('account','show','--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action 'verify Azure authentication and selected subscription'
    if (-not [string]::Equals([string]$account.id,$script:RemoveSubscriptionId,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'Azure CLI returned a subscription id that does not match the requested purge subscription.' }
    Write-Host ("Target: subscription {0}; VM '{1}'." -f [string]$account.name,$script:RemoveVmName) -ForegroundColor Cyan

    $script:RemoveGroups = @(Get-RemoveTargetGroups)
    if ($PreflightOnly) {
        if ($script:RemoveGroups.Count -eq 0) { Write-Host ("Preflight passed: VM '{0}', its configured group, and exact profile resources are already absent." -f $script:RemoveVmName) -ForegroundColor Green }
        else {
            foreach ($groupName in @($script:RemoveGroups)) {
                Write-Host ("Preflight purge scope: managed group '{0}'" -f $groupName) -ForegroundColor Yellow
                $resources = Invoke-RemoveAzJson -Arguments @('resource','list','--resource-group',$groupName,'--subscription',$script:RemoveSubscriptionId,'--output','json','--only-show-errors') -Action ("inventory resources in planned purge group '{0}'" -f $groupName)
                foreach ($resource in @($resources)) { Write-Host ('  - {0}: {1}' -f [string]$resource.type,[string]$resource.name) }
            }
            Write-Host 'Preflight passed; no Azure resource was changed.' -ForegroundColor Green
        }
        return
    }

    if ($script:RemoveGroups.Count -eq 0) {
        Assert-RemoveTargetAbsent
        Write-Host ("VM '{0}' is already absent; no Azure mutation was needed." -f $script:RemoveVmName) -ForegroundColor Green
        return
    }

    Save-RemoveJournal
    foreach ($groupName in @($script:RemoveGroups)) { Invoke-RemoveGroup -GroupName $groupName }
    Assert-RemoveTargetAbsent
    Write-Host ("VM '{0}' and every captured VC-profile resource/group were hard-purged and verified absent." -f $script:RemoveVmName) -ForegroundColor Green
}
catch {
    Write-Host ''
    Write-Host ("Removal for VM '{0}' did not complete." -f $script:RemoveVmName) -ForegroundColor Red
    Write-Host ([string]$_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    if ($script:RemoveTranscriptStarted) { Stop-Transcript | Out-Null }
}
