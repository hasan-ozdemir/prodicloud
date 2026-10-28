# Delete command runtime helpers.

function Get-ProdicloudDeleteCommandRuntime {
    param(
        [hashtable]$Options
    )

    return [pscustomobject]@{
        Options = $Options
    }
}
