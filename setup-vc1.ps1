[CmdletBinding()]
param()

$runner = Join-Path $PSScriptRoot 'setup-vc.ps1'
& $runner -VmName 'vc1' @args
exit $LASTEXITCODE
