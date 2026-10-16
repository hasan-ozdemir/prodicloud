param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
    [string]$CommitMessagePath = "",
    [switch]$SkipRepoAudit,
    [switch]$SkipHistoryAudit
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Get-SensitiveContentPatterns {
    param(
        [switch]$IncludeCommitOnlyPatterns
    )

    $tokenSpecs = @(
        @{ Name = 'banned-repo-needle-1'; Chars = @(98,105,122,121,117,109) },
        @{ Name = 'banned-repo-needle-2'; Chars = @(104,97,115,97,110) },
        @{ Name = 'banned-repo-needle-3'; Chars = @(104,97,115,97,110,111,122,100,101,109,105,114) }
    )

    $patterns = @(
        [pscustomobject]@{
            Name = 'email-address'
            Regex = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
        },
        [pscustomobject]@{
            Name = 'mailto-or-tel-link'
            Regex = ('(?i)\b(?:mail' + 'to:|te' + 'l:)\S+')
        }
    )

    foreach ($tokenSpec in @($tokenSpecs)) {
        $tokenText = -join @($tokenSpec.Chars | ForEach-Object { [char][int]$_ })
        $escapedToken = [regex]::Escape([string]$tokenText)
        $requiresWordBoundary = ($tokenText -notmatch '\s')
        $patterns += [pscustomobject]@{
            Name = [string]$tokenSpec.Name
            Regex = if ($requiresWordBoundary) { ('(?i)\b{0}\b' -f $escapedToken) } else { ('(?i){0}' -f $escapedToken) }
        }
    }

    if ($IncludeCommitOnlyPatterns) {
        $patterns += [pscustomobject]@{
            Name = 'concrete-windows-user-home'
            Regex = '(?i)C:\\Users\\(?!<user-home>\\|operator\\|Public\\|Default\\|Default User\\|%USERNAME%\\|\{0\}\\)[^\\/\r\n]+\\'
        }
    }

    return $patterns
}

function Get-TrackedAuditPaths {
    param(
        [string]$RepositoryRoot
    )

    $allowedExtensions = @(
        '.ps1', '.psm1', '.psd1', '.cmd', '.sh', '.py', '.md', '.yml', '.yaml', '.json', '.toml', '.txt'
    )
    $explicitFileNames = @(
        'clagnos.env.example', 'vc.env.example', '.gitignore', '.gitattributes'
    )

    $trackedPaths = @(& git -C $RepositoryRoot ls-files)
    foreach ($trackedPath in @($trackedPaths)) {
        $normalized = ([string]$trackedPath).Replace('\', '/')
        if ([string]::IsNullOrWhiteSpace($normalized)) {
            continue
        }

        if ($normalized.StartsWith('tools/pyssh/.venv/', [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $leafName = [System.IO.Path]::GetFileName($normalized)
        $extension = [System.IO.Path]::GetExtension($normalized).ToLowerInvariant()
        if ($allowedExtensions -contains $extension -or
            $explicitFileNames -contains $leafName -or
            $normalized.StartsWith('.githooks/', [System.StringComparison]::OrdinalIgnoreCase)) {
            Join-Path $RepositoryRoot $normalized
        }
    }
}

function Test-LineMatches {
    param(
        [string]$Text,
        [string]$Regex
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    return [regex]::IsMatch($Text, $Regex)
}

function Get-TextFindings {
    param(
        [string]$Label,
        [string[]]$Lines,
        [object[]]$Patterns
    )

    $findings = @()
    $lineNumber = 0
    foreach ($line in @($Lines)) {
        $lineNumber++
        foreach ($pattern in @($Patterns)) {
            if (Test-LineMatches -Text ([string]$line) -Regex ([string]$pattern.Regex)) {
                $findings += ("{0}:{1}: matched {2}" -f $Label, $lineNumber, [string]$pattern.Name)
            }
        }
    }

    return @($findings)
}

function Assert-NoSensitiveMatchesInRepoFiles {
    param(
        [string]$RepositoryRoot
    )

    $patterns = @(Get-SensitiveContentPatterns)
    $findings = @()
    foreach ($path in @(Get-TrackedAuditPaths -RepositoryRoot $RepositoryRoot)) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }
        $lines = @(Get-Content -LiteralPath $path -ErrorAction Stop)
        $findings += @(Get-TextFindings -Label $path -Lines $lines -Patterns $patterns)
    }

    if (@($findings).Count -gt 0) {
        throw ("Sensitive-content audit found tracked text matches: {0}" -f ((@($findings) | Select-Object -First 10) -join '; '))
    }
}

function Assert-EnvExampleSensitivePlaceholders {
    param(
        [string]$RepositoryRoot
    )

    $envExamplePath = Join-Path $RepositoryRoot 'clagnos.env.example'
    if (-not (Test-Path -LiteralPath $envExamplePath)) {
        throw "clagnos.env.example was not found."
    }

    $vmEnvExamplePath = Join-Path $RepositoryRoot 'vc.env.example'
    if (-not (Test-Path -LiteralPath $vmEnvExamplePath)) { throw 'vc.env.example was not found.' }

    $globalEnvMap = @{}
    foreach ($line in @(Get-Content -LiteralPath $envExamplePath -ErrorAction Stop)) {
        if ($line -match '^\s*#' -or -not ($line -match '=')) {
            continue
        }

        $parts = $line -split '=', 2
        $key = ([string]$parts[0]).Trim()
        $value = if ($parts.Count -gt 1) { [string]$parts[1] } else { '' }
        $globalEnvMap[$key] = $value.Trim()
    }

    $vmEnvMap = @{}
    foreach ($line in @(Get-Content -LiteralPath $vmEnvExamplePath -ErrorAction Stop)) {
        if ($line -match '^\s*#' -or -not ($line -match '=')) { continue }
        $parts = $line -split '=', 2
        $vmEnvMap[([string]$parts[0]).Trim()] = ([string]$parts[1]).Trim()
    }

    if ([string]$vmEnvMap['VM_ADMIN_PASS'] -ne '<CHANGE_ME_STRONG_ADMIN_PASSWORD>') {
        throw "vc.env.example must keep VM_ADMIN_PASS as the committed placeholder."
    }
    if ([string]$vmEnvMap['VM_ASSISTANT_PASS'] -ne '<CHANGE_ME_STRONG_ASSISTANT_PASSWORD>') {
        throw "vc.env.example must keep VM_ASSISTANT_PASS as the committed placeholder."
    }
    if ([string]$globalEnvMap['SELECTED_COMPANY_WEB_ADDRESS'] -ne '<https-url>') {
        throw "clagnos.env.example must keep SELECTED_COMPANY_WEB_ADDRESS as the committed placeholder."
    }
    if ([string]$globalEnvMap['SELECTED_COMPANY_EMAIL_ADDRESS'] -ne '<email>') {
        throw "clagnos.env.example must keep SELECTED_COMPANY_EMAIL_ADDRESS as the committed placeholder."
    }
    if ([string]$globalEnvMap['SELECTED_EMPLOYEE_EMAIL_ADDRESS'] -ne '<email>') {
        throw "clagnos.env.example must keep SELECTED_EMPLOYEE_EMAIL_ADDRESS as the committed placeholder."
    }
    if ([string]$globalEnvMap['SELECTED_EMPLOYEE_FULL_NAME'] -ne '<person-name>') {
        throw "clagnos.env.example must keep SELECTED_EMPLOYEE_FULL_NAME as the committed placeholder."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$globalEnvMap['SELECTED_AZURE_SUBSCRIPTION_ID'])) {
        throw "clagnos.env.example must not commit a concrete SELECTED_AZURE_SUBSCRIPTION_ID value."
    }
}

function Assert-NoSensitiveMatchesInReachableCommitMessages {
    param(
        [string]$RepositoryRoot
    )

    $patterns = @(Get-SensitiveContentPatterns -IncludeCommitOnlyPatterns)
    $messageText = [string](& git -C $RepositoryRoot log --all --format=%B)
    $findings = @()
    foreach ($pattern in @($patterns)) {
        if (Test-LineMatches -Text $messageText -Regex ([string]$pattern.Regex)) {
            $findings += [string]$pattern.Name
        }
    }

    if (@($findings).Count -gt 0) {
        throw ("Sensitive-content audit found reachable commit-message matches: {0}" -f ((@($findings) | Sort-Object -Unique) -join ', '))
    }
}

function Assert-NoSensitiveMatchesInCommitMessageFile {
    param(
        [string]$MessagePath
    )

    if ([string]::IsNullOrWhiteSpace($MessagePath)) {
        return
    }
    if (-not (Test-Path -LiteralPath $MessagePath)) {
        throw ("Commit message file was not found: {0}" -f $MessagePath)
    }

    $patterns = @(Get-SensitiveContentPatterns -IncludeCommitOnlyPatterns)
    $lines = @(Get-Content -LiteralPath $MessagePath -ErrorAction Stop | Where-Object { -not ([string]$_).StartsWith('#') })
    $findings = @(Get-TextFindings -Label $MessagePath -Lines $lines -Patterns $patterns)
    if (@($findings).Count -gt 0) {
        throw ("Sensitive-content audit found commit-message matches: {0}" -f ((@($findings) | Select-Object -First 10) -join '; '))
    }
}

if (-not $SkipRepoAudit) {
    Assert-NoSensitiveMatchesInRepoFiles -RepositoryRoot $RepoRoot
    Assert-EnvExampleSensitivePlaceholders -RepositoryRoot $RepoRoot
}

if (-not $SkipHistoryAudit) {
    Assert-NoSensitiveMatchesInReachableCommitMessages -RepositoryRoot $RepoRoot
}

if (-not [string]::IsNullOrWhiteSpace($CommitMessagePath)) {
    Assert-NoSensitiveMatchesInCommitMessageFile -MessagePath $CommitMessagePath
}

Write-Host 'Sensitive-content checks passed.' -ForegroundColor Green
