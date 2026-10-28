[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Group,
    [Parameter(Mandatory = $true)][string]$VmName,
    [string]$Package = 'chocolatey',
    [ValidateSet('builtin','custom')][string]$Catalog = 'builtin',
    [ValidateRange(1,20)][int]$Repetitions = 5
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot ($VmName + '.env')
$entryPoint = Join-Path $repoRoot 'prodicloud.ps1'
if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) { throw ("The VC profile '{0}.env' is required for package transport benchmarking." -f $VmName) }
if (-not (Test-Path -LiteralPath $entryPoint -PathType Leaf)) { throw 'The Prodicloud entrypoint was not found.' }

$lines = @([IO.File]::ReadAllLines($envPath))
$transportLine = @($lines | Where-Object { $_ -match '^\s*PACKAGE_TRANSPORT\s*=' } | Select-Object -First 1)
if ($transportLine.Count -ne 1 -or $transportLine[0] -notmatch '^\s*PACKAGE_TRANSPORT\s*=(.*)$') { throw ("The VC profile '{0}.env' must define PACKAGE_TRANSPORT before benchmarking." -f $VmName) }
$originalTransport = [string]$Matches[1]
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('prodicloud-package-benchmark-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot -Force
$powerShellExe = (Get-Command pwsh -ErrorAction Stop).Source
$samples = [Collections.Generic.List[object]]::new()

function Set-BenchmarkTransport {
    param([string]$Value)
    $currentLines = @([IO.File]::ReadAllLines($envPath))
    for ($index = 0; $index -lt $currentLines.Count; $index++) {
        if ($currentLines[$index] -match '^\s*PACKAGE_TRANSPORT\s*=') { $currentLines[$index] = 'PACKAGE_TRANSPORT=' + $Value; break }
    }
    [IO.File]::WriteAllLines($envPath,$currentLines,[Text.UTF8Encoding]::new($false))
}

try {
    foreach ($transport in @('ssh','winrm')) {
        Set-BenchmarkTransport -Value $transport
        for ($iteration = 1; $iteration -le $Repetitions; $iteration++) {
            $stdoutPath = Join-Path $tempRoot ("{0}-{1}.out" -f $transport,$iteration)
            $stderrPath = Join-Path $tempRoot ("{0}-{1}.err" -f $transport,$iteration)
            $argumentList = @(
                '-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$entryPoint,
                'package',"--action=status",("--catalog={0}" -f $Catalog),("--package={0}" -f $Package),
                ("--group={0}" -f $Group),("--vm-name={0}" -f $VmName),'--windows'
            )
            Write-Output ("Doing: benchmark {0} package status ({1}/{2})" -f $transport,$iteration,$Repetitions)
            $watch = [Diagnostics.Stopwatch]::StartNew()
            $process = Start-Process -FilePath $powerShellExe -ArgumentList $argumentList -WorkingDirectory $repoRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
            $lastHeartbeat = 0
            while (-not $process.HasExited) {
                Start-Sleep -Seconds 1
                $process.Refresh()
                if ($watch.Elapsed.TotalSeconds -ge ($lastHeartbeat + 30)) {
                    $lastHeartbeat = [int][Math]::Floor($watch.Elapsed.TotalSeconds / 30) * 30
                    Write-Output ("Doing: {0} package status benchmark is still running ({1}s elapsed)" -f $transport,$lastHeartbeat)
                }
            }
            $watch.Stop()
            $combinedOutput = [string](Get-Content -LiteralPath $stdoutPath -Raw -ErrorAction SilentlyContinue) + "`n" + [string](Get-Content -LiteralPath $stderrPath -Raw -ErrorAction SilentlyContinue)
            $resultMatch = [regex]::Match($combinedOutput,'PRODICLOUD_PACKAGE_RESULT:(?<json>\{[^\r\n]*\})')
            $status = ''
            $failure = ''
            if ($resultMatch.Success) {
                try { $status = [string]((ConvertFrom-Json -InputObject $resultMatch.Groups['json'].Value).status) }
                catch { $failure = 'Prodicloud returned an invalid structured package status.' }
            }
            else { $failure = 'Prodicloud did not return a structured package status.' }
            if ([int]$process.ExitCode -ne 0) { $failure = ('Prodicloud exited with {0}.' -f [int]$process.ExitCode) }
            $samples.Add([pscustomobject]@{ Transport = $transport; Iteration = $iteration; Milliseconds = [long]$watch.ElapsedMilliseconds; Status = $status; Failure = $failure })
            if ([string]::IsNullOrWhiteSpace($failure)) { Write-Output ("Completed: {0} status {1} in {2} ms" -f $transport,$status,[long]$watch.ElapsedMilliseconds) }
            else { Write-Output ("Completed with error: {0} status attempt in {1} ms ({2})" -f $transport,[long]$watch.ElapsedMilliseconds,$failure) }
        }
    }
}
finally {
    Set-BenchmarkTransport -Value $originalTransport
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($transport in @('ssh','winrm')) {
    $valid = @($samples | Where-Object { $_.Transport -eq $transport -and [string]::IsNullOrWhiteSpace([string]$_.Failure) -and $_.Status -eq 'installed' })
    $all = @($samples | Where-Object { $_.Transport -eq $transport })
    if ($valid.Count -eq 0) { Write-Output ("BENCHMARK {0}: no successful status samples ({1}/{2})." -f $transport,$valid.Count,$all.Count); continue }
    $sorted = @($valid | Sort-Object Milliseconds)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2 -eq 1) { [long]$sorted[$middle].Milliseconds } else { [long](($sorted[$middle - 1].Milliseconds + $sorted[$middle].Milliseconds) / 2) }
    $minimum = [long](($valid | Measure-Object -Property Milliseconds -Minimum).Minimum)
    $maximum = [long](($valid | Measure-Object -Property Milliseconds -Maximum).Maximum)
    Write-Output ("BENCHMARK {0}: {1}/{2} successful; median {3} ms; range {4}-{5} ms; status installed" -f $transport,$valid.Count,$all.Count,$median,$minimum,$maximum)
}

if (@($samples | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Failure) }).Count -gt 0) { exit 1 }
