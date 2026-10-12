# Shared command option specification helpers.

function New-ClagnosCommandOptionSpecification {
    param(
        [string]$Name,
        [scriptblock]$Validate = $null,
        [string[]]$ShortNames = @(),
        [switch]$TakesValue
    )

    return [pscustomobject]@{
        Name = [string]$Name
        Validate = $Validate
        ShortNames = @($ShortNames | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        TakesValue = [bool]$TakesValue
    }
}
