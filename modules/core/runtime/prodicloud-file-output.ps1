# Shared normalized file-output helper.

# Handles Write-TextFileNormalized.
function Write-TextFileNormalized {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [AllowNull()]
        [string]$Content,
        [ValidateSet("utf8NoBom", "ascii")]
        [string]$Encoding = "utf8NoBom",
        [ValidateSet("lf", "crlf", "preserve")]
        [string]$LineEnding = "preserve",
        [switch]$EnsureTrailingNewline
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Write-TextFileNormalized requires a valid file path."
    }

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($null -eq $Content) {
        $Content = ""
    }
    $text = [string]$Content

    switch ($LineEnding) {
        "lf" {
            $text = $text -replace "`r`n", "`n"
            $text = $text -replace "`r", "`n"
        }
        "crlf" {
            $text = $text -replace "`r`n", "`n"
            $text = $text -replace "`r", "`n"
            $text = $text -replace "`n", "`r`n"
        }
    }

    if ($EnsureTrailingNewline) {
        $targetEnding = if ($LineEnding -eq "crlf") { "`r`n" } else { "`n" }
        if (-not $text.EndsWith($targetEnding)) {
            $text += $targetEnding
        }
    }

    $encodingObject = switch ($Encoding) {
        "utf8NoBom" { New-Object System.Text.UTF8Encoding($false) }
        "ascii" { [System.Text.Encoding]::ASCII }
        default { New-Object System.Text.UTF8Encoding($false) }
    }

    [System.IO.File]::WriteAllText($Path, $text, $encodingObject)
}
