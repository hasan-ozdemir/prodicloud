# List command entry.

function Invoke-ClagnosListCommand {
    param(
        [hashtable]$Options
    )

    $repoRoot = Get-ClagnosRepoRoot
    $envFilePath = Join-Path $repoRoot '.env'
    $configMap = Read-DotEnvFile -Path $envFilePath
    $requestedTypes = @(Resolve-ClagnosListRequestedTypes -Options $Options)
    $managedGroupRows = @()
    $groupRowsReference = if ($requestedTypes -contains 'group') { [ref]$managedGroupRows } else { $null }
    $resourceGroups = @(Get-ClagnosListTargetResourceGroups -Options $Options -ConfigMap $configMap -ManagedGroupRows $groupRowsReference)
    $subscriptionContext = Get-ClagnosResolvedSubscriptionContext

    Write-Host "Managed clagnos inventory:" -ForegroundColor Cyan
    if ($null -ne $subscriptionContext -and -not [string]::IsNullOrWhiteSpace([string]$subscriptionContext.SubscriptionId)) {
        $subscriptionDisplay = if ([string]::IsNullOrWhiteSpace([string]$subscriptionContext.SubscriptionName)) {
            [string]$subscriptionContext.SubscriptionId
        }
        else {
            ("{0} ({1})" -f [string]$subscriptionContext.SubscriptionName, [string]$subscriptionContext.SubscriptionId)
        }
        Write-Host ("- subscription: {0}" -f $subscriptionDisplay)
    }
    if (@($resourceGroups).Count -eq 0) {
        Write-Host "- No managed resource groups were found."
        return
    }

    foreach ($typeName in @($requestedTypes)) {
        $rows = @(Get-ClagnosListSectionRows -TypeName ([string]$typeName) -ResourceGroups @($resourceGroups) -ConfigMap $configMap -ManagedGroupRows @($managedGroupRows))
        Write-Host ""
        Write-Host ("{0}:" -f ([string]$typeName).ToUpperInvariant()) -ForegroundColor Cyan
        if (@($rows).Count -eq 0) {
            Write-Host "- (none)"
            continue
        }

        foreach ($row in @($rows)) {
            Write-Host ("- {0}" -f [string]$row)
        }
    }
}
