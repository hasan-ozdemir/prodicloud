param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$logRoot = Join-Path $RepoRoot '.logs'
$logFiles = @(Get-ChildItem -LiteralPath $logRoot -File -Filter 'clagnos-log-*.txt' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
if (@($logFiles).Count -lt 1) {
    Write-Host 'retro-log-audit: no clagnos-log-*.txt files were found.'
    exit 0
}

$patterns = @(
    [pscustomobject]@{ Label = 'wmic-noise'; Pattern = "'wmic' is not recognized" },
    [pscustomobject]@{ Label = 'python-store-alias'; Pattern = 'Python was not found; run without arguments' },
    [pscustomobject]@{ Label = 'store-seizure-banner'; Pattern = 'Seizure Warning: https://aka.ms/microsoft-store-seizure-warning' },
    [pscustomobject]@{ Label = 'codex-deferred'; Pattern = 'Codex app install could not complete in the current noninteractive session. A RunOnce install was registered for the next interactive sign-in.' },
    [pscustomobject]@{ Label = 'whatsapp-deferred'; Pattern = 'WhatsApp install could not complete in the current noninteractive session. A RunOnce install was registered for the next interactive sign-in.' },
    [pscustomobject]@{ Label = 'be-my-eyes-deferred'; Pattern = 'Be My Eyes install requires an interactive desktop session. A RunOnce install was registered for the next interactive sign-in.' },
    [pscustomobject]@{ Label = 'icloud-deferred'; Pattern = 'iCloud install requires an interactive desktop session. A RunOnce install was registered for the next interactive sign-in.' },
    [pscustomobject]@{ Label = 'icloud-registration-only'; Pattern = 'iCloud registration already exists. Skipping install.' },
    [pscustomobject]@{ Label = 'teams-autostart-skip'; Pattern = 'autostart-skip: Teams' },
    [pscustomobject]@{ Label = 'icloud-shortcut-skip'; Pattern = 'public-shortcut-skip: d4ICloud' },
    [pscustomobject]@{ Label = 'copy-settings-empty-summary'; Pattern = 'copy-settings-user-skip-summary: none' },
    [pscustomobject]@{ Label = 'screen-reader-manager-process-missing'; Pattern = 'manager-process-not-observed' }
)

foreach ($row in @($patterns)) {
    $matches = Select-String -Path @($logFiles.FullName) -Pattern ([string]$row.Pattern) -SimpleMatch
    if (@($matches).Count -lt 1) {
        Write-Host ("retro-log-audit => {0} => count=0" -f [string]$row.Label)
        continue
    }

    $first = $matches | Select-Object -First 1
    $last = $matches | Select-Object -Last 1
    Write-Host ("retro-log-audit => {0} => count={1}; first={2}:{3}; last={4}:{5}" -f `
        [string]$row.Label, `
        @($matches).Count, `
        (Split-Path -Path ([string]$first.Path) -Leaf), `
        [int]$first.LineNumber, `
        (Split-Path -Path ([string]$last.Path) -Leaf), `
        [int]$last.LineNumber)
}
