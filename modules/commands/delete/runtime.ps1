# Delete command runtime helpers.

function Get-ClagnosDeleteCommandRuntime {
    param(
        [hashtable]$Options
    )

    return [pscustomobject]@{
        Options = $Options
    }
}
