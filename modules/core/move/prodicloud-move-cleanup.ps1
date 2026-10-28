# Shared move cleanup helpers.

# Handles Remove-ProdicloudMoveCollectionArtifacts.
function Remove-ProdicloudMoveCollectionArtifacts {
    param(
        [string]$ResourceGroup,
        [string]$CollectionName,
        [string]$Reason = 'cleanup requested'
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup) -or [string]::IsNullOrWhiteSpace([string]$CollectionName)) {
        return
    }

    Write-Host ("Cleanup started for move collection '{0}'. Reason: {1}" -f $CollectionName, $Reason) -ForegroundColor Yellow

    $moveResourceIdsText = az resource-mover move-resource list -g $ResourceGroup --move-collection-name $CollectionName --query "[].id" -o tsv --only-show-errors 2>$null
    $moveResourceIds = @()
    if ($LASTEXITCODE -eq 0) {
        $moveResourceIds = @((Convert-ProdicloudCliTextToTokens -Text $moveResourceIdsText) | Select-Object -Unique)
    }

    if ($moveResourceIds.Count -gt 0) {
        Invoke-TrackedAction -Label ("az resource-mover move-collection discard --name {0}" -f $CollectionName) -Action {
            $discardArgs = @("resource-mover", "move-collection", "discard", "-g", $ResourceGroup, "-n", $CollectionName, "--validate-only", "false", "--input-type", "MoveResourceId", "--move-resources")
            $discardArgs += $moveResourceIds
            $discardArgs += @("-o", "none", "--only-show-errors")
            az @discardArgs 2>$null
        } | Out-Null
        Write-ProdicloudActionProgress -Action 'wait 3 seconds for Azure Resource Mover discard to settle'
        Start-Sleep -Seconds 3

        Invoke-TrackedAction -Label ("az resource-mover move-collection bulk-remove --name {0}" -f $CollectionName) -Action {
            $bulkRemoveArgs = @("resource-mover", "move-collection", "bulk-remove", "-g", $ResourceGroup, "-n", $CollectionName, "--validate-only", "false", "--input-type", "MoveResourceId", "--move-resources")
            $bulkRemoveArgs += $moveResourceIds
            $bulkRemoveArgs += @("-o", "none", "--only-show-errors")
            az @bulkRemoveArgs 2>$null
        } | Out-Null
        Write-ProdicloudActionProgress -Action 'wait 3 seconds for Azure Resource Mover bulk removal to settle'
        Start-Sleep -Seconds 3
    }

    $moveResourceNamesText = az resource-mover move-resource list -g $ResourceGroup --move-collection-name $CollectionName --query "[].name" -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0) {
        $moveResourceNames = @((Convert-ProdicloudCliTextToTokens -Text $moveResourceNamesText) | Select-Object -Unique)
        foreach ($moveResourceName in @($moveResourceNames)) {
            if ([string]::IsNullOrWhiteSpace([string]$moveResourceName)) { continue }
            Invoke-TrackedAction -Label ("az resource-mover move-resource delete --name {0}" -f $moveResourceName) -Action {
                az resource-mover move-resource delete -g $ResourceGroup --move-collection-name $CollectionName -n $moveResourceName --yes -o none --only-show-errors 2>$null
            } | Out-Null
        }
    }

    $subscriptionId = az account show --query id -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        $deleteUri = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Migrate/moveCollections/$CollectionName"
        Invoke-TrackedAction -Label ("az rest delete move-collection --name {0}" -f $CollectionName) -Action {
            az rest --method delete --uri $deleteUri --url-parameters api-version=2024-08-01 -o none --only-show-errors 2>$null
        } | Out-Null
    }
    else {
        Invoke-TrackedAction -Label ("az resource-mover move-collection delete --name {0}" -f $CollectionName) -Action {
            az resource-mover move-collection delete -g $ResourceGroup -n $CollectionName --yes -o none --only-show-errors 2>$null
        } | Out-Null
    }

    az resource-mover move-collection show -g $ResourceGroup -n $CollectionName -o none --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host ("Cleanup could not fully delete move collection '{0}'. Please remove it manually." -f $CollectionName) -ForegroundColor Yellow
    }
    else {
        Write-Host ("Cleanup completed for move collection '{0}'." -f $CollectionName) -ForegroundColor Green
    }
}

# Handles Get-ProdicloudManagedMoveCollections.
function Get-ProdicloudManagedMoveCollections {
    param(
        [string]$ResourceGroup,
        [string]$SourceRegion,
        [string]$TargetRegion,
        [string]$CollectionPrefix
    )

    if ([string]::IsNullOrWhiteSpace([string]$ResourceGroup)) {
        return @()
    }

    $collectionsJson = az resource-mover move-collection list -g $ResourceGroup -o json --only-show-errors 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace([string]$collectionsJson)) {
        return @()
    }

    $collections = @((ConvertFrom-JsonCompat -InputObject $collectionsJson))
    return @(
        $collections |
            Where-Object {
                [string]::Equals(([string]$_.properties.sourceRegion), $SourceRegion, [System.StringComparison]::OrdinalIgnoreCase) -and
                [string]::Equals(([string]$_.properties.targetRegion), $TargetRegion, [System.StringComparison]::OrdinalIgnoreCase) -and
                ([string]$_.name).ToLowerInvariant().StartsWith(([string]$CollectionPrefix).ToLowerInvariant())
            } |
            Select-Object -ExpandProperty name -Unique
    )
}
