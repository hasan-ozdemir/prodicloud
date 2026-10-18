<#
Script Filename: clagnos.ps1
Script Description:
- Unified Azure VM provisioning flow for Windows and Linux.
- OS selection: --windows or --linux (or DEFAULT_VM_OS from clagnos.env for create, or SELECTED_VM_OS from the active VC profile).
- Init tasks run once on first VM creation via Azure Run Command, one task at a time.
- Update tasks run task-by-task over the active platform SSH transport.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [Alias('c')]
    [string]$PassthroughShortCommand = '',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliTokens
)

$script:ActiveCommand = ''
$script:AutoMode = $false
$script:UpdateMode = $false
$script:PerfMode = $false

$script:TranscriptStarted = $false
$script:HadError = $false
$script:ExitCode = 0
$script:ConfigOverrides = @{}
$script:ClagnosConfigValueSources = @{}
$script:ExecutionMode = if ($script:UpdateMode) { 'update' } else { 'default' }
$script:AzCommandTimeoutSeconds = 1800
$script:SshTaskTimeoutSeconds = 180
$script:SshConnectTimeoutSeconds = 30
$script:ClagnosQuietOutput = $false
$script:AzCliExecutable = $null
$script:RetailPricingCacheByLocation = @{}
$script:RetailPricingMaxRetries = 4
$script:RetailPricingPageDelayMs = 120
$script:PerfSuppressAzTimingDepth = 0
$script:ClagnosTrackedAzureActionDepth = 0
$script:ManagedByTagKey = 'managed-by'
$script:ManagedByTagValue = 'clagnos'
$script:LegacyManagedByTagValue = 'az-vm'
$script:ClagnosPackageStatusCache = @{}
$script:ClagnosPackageStatusCacheTtlSeconds = 45
$script:ClagnosResetManagedUserPasswords = $false
$script:ClagnosSshBootstrapCache = @{}
$script:ClagnosSshBootstrapCacheTtlSeconds = 20
$script:ClagnosAccessibleSubscriptionRowsCache = $null
$script:ClagnosAccessibleSubscriptionRowsValidatedAtUtc = [DateTime]::MinValue
$script:ClagnosRepoRoot = $PSScriptRoot
$env:PYTHONDONTWRITEBYTECODE = '1'

$script:DefaultErrorSummary = 'An unexpected error occurred.'
$script:DefaultErrorHint = 'Review the error line and check script parameters and Azure connectivity.'

function Get-ClagnosCliVersionInfo {
    $releaseNotesPath = Join-Path $PSScriptRoot 'release-notes.md'
    if (Test-Path -LiteralPath $releaseNotesPath) {
        $releaseNotesText = [string](Get-Content -LiteralPath $releaseNotesPath -Raw)
        $match = [regex]::Match($releaseNotesText, '(?m)^## Release (\d{4}\.\d{1,2}\.\d{1,2}\.\d+)\s+-\s+\d{4}-\d{2}-\d{2}$')
        if ($match.Success) {
            return [string]$match.Groups[1].Value
        }
    }

    return '0.0.0'
}

function Write-ClagnosCliBanner {
    if ($script:ClagnosQuietOutput) {
        return
    }

    $versionInfo = Get-ClagnosCliVersionInfo
    Write-Host ("CLAGNOS CLI V{0}" -f [string]$versionInfo) -ForegroundColor Cyan
    Write-Host 'Provision, update, connect, and maintain managed Windows or Linux Azure VMs from one deterministic CLI.' -ForegroundColor DarkCyan
    Write-Host 'Run lifecycle actions, isolated tasks, app-state save/restore, and SSH or RDP access through one repo-driven workflow.' -ForegroundColor DarkCyan
    Write-Host ''
}

$preParsedCommandToken = ''
$preParsedRawArgs = @()
if ($null -ne $CliTokens -and @($CliTokens).Count -gt 0) {
    $preParsedCommandToken = [string]$CliTokens[0]
    if (@($CliTokens).Count -gt 1) {
        $preParsedRawArgs = @($CliTokens[1..(@($CliTokens).Count - 1)])
    }
}
if (-not [string]::IsNullOrWhiteSpace([string]$PassthroughShortCommand)) {
    $preParsedRawArgs = @('-c', [string]$PassthroughShortCommand) + @($preParsedRawArgs)
}
if ([string]::Equals([string]$preParsedCommandToken, 'exec', [System.StringComparison]::OrdinalIgnoreCase)) {
    $hasQuietFlag = $false
    $hasCommandFlag = $false
    foreach ($rawArg in @($preParsedRawArgs)) {
        $rawArgText = [string]$rawArg
        if ($rawArgText -in @('-q', '--quiet')) {
            $hasQuietFlag = $true
        }
        elseif ($rawArgText -match '^(?i)(-q|--quiet)=(true|1|yes|on)?$') {
            $hasQuietFlag = $true
        }

        if ($rawArgText -in @('-c', '--command')) {
            $hasCommandFlag = $true
        }
        elseif ($rawArgText -match '^(?i)(-c|--command)=') {
            $hasCommandFlag = $true
        }
    }

    if ($hasQuietFlag -and $hasCommandFlag) {
        $script:ClagnosQuietOutput = $true
    }
}

if ($MyInvocation.InvocationName -ne '.' -and @($preParsedRawArgs).Count -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$preParsedCommandToken)) {
    $versionToken = [string]$preParsedCommandToken
    if ($versionToken -match '^(?i)--version(?:=(?:1|true|yes|on)?)?$') {
        Write-Host ("clagnos version {0}" -f (Get-ClagnosCliVersionInfo))
        return
    }
}

# Load modular function files in deterministic order from the leaf-file manifest.
$moduleManifestPath = Join-Path $PSScriptRoot 'modules/clagnos-runtime-manifest.ps1'
if (-not (Test-Path -LiteralPath $moduleManifestPath)) {
    throw ("Required module manifest was not found: {0}" -f $moduleManifestPath)
}

$moduleFiles = @(& $moduleManifestPath)
if (@($moduleFiles).Count -eq 0) {
    throw "Module manifest returned no module files."
}

foreach ($moduleFile in @($moduleFiles)) {
    $modulePath = Join-Path $PSScriptRoot $moduleFile
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw ("Required module file was not found: {0}" -f $modulePath)
    }

    . $modulePath
}

if ($MyInvocation.InvocationName -eq '.') {
    return
}

Write-ClagnosCliBanner

try {
    $script:DirectCommandTranscriptStarted = $false
    $script:DirectCommandTranscriptPath = ''
    $commandToken = [string]$preParsedCommandToken
    $rawArgs = @($preParsedRawArgs)

    $parsedCli = Parse-ClagnosCliArguments -CommandToken $commandToken -RawArgs $rawArgs
    if ([string]$parsedCli.Command -notin @('create','initialize','update')) {
        $logsRoot = Join-Path $PSScriptRoot '.logs'
        if (-not (Test-Path -LiteralPath $logsRoot -PathType Container)) { New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null }
        $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss-fff',[System.Globalization.CultureInfo]::InvariantCulture)
        $safeCommand = ([string]$parsedCli.Command -replace '[^A-Za-z0-9_-]','-')
        $script:DirectCommandTranscriptPath = Join-Path $logsRoot ("clagnos-{0}-{1}.txt" -f $safeCommand,$timestamp)
        Start-Transcript -LiteralPath $script:DirectCommandTranscriptPath -Force | Out-Null
        $script:DirectCommandTranscriptStarted = $true
    }
    Invoke-ClagnosCommandDispatcher -CommandName ([string]$parsedCli.Command) -Options $parsedCli.Options -HelpTopic ([string]$parsedCli.HelpTopic)
}
catch {
    $resolvedError = Resolve-ClagnosFriendlyError -ErrorRecord $_ -DefaultErrorSummary $script:DefaultErrorSummary -DefaultErrorHint $script:DefaultErrorHint
    if ($script:ClagnosQuietOutput) {
        exit ([int]$resolvedError.Code)
    }
    Write-Host ''
    Write-Host 'Script exited gracefully.' -ForegroundColor Yellow
    Write-Host ("Reason: {0}" -f $resolvedError.Summary) -ForegroundColor Red
    Write-Host ("Detail: {0}" -f $resolvedError.ErrorMessage)
    Write-Host ("Suggested action: {0}" -f $resolvedError.Hint) -ForegroundColor Cyan
    exit ([int]$resolvedError.Code)
}
finally {
    if ($script:DirectCommandTranscriptStarted) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null }
        catch { Write-Host ("Command transcript stop skipped: {0}" -f [string]$_.Exception.Message) -ForegroundColor Yellow }
        finally { $script:DirectCommandTranscriptStarted = $false }
    }
}

