[CmdletBinding()]
param()

$runner = Join-Path $PSScriptRoot 'setup-vc.ps1'
& $runner -VmName 'vc2' @args
exit $LASTEXITCODE
