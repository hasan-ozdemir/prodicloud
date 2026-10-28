# Package management command entry.

function Invoke-ProdicloudPackageCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $action = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'action')
    $packageId = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'package')
    $catalog = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'catalog')
    if ([string]::IsNullOrWhiteSpace($action)) {
        Throw-FriendlyError -Detail "Package command requires an action." -Code 2 -Summary "Package operation is incomplete." -Hint "Use --action=list|status|install|update|uninstall|enable|disable --catalog=builtin|custom."
    }
    if ([string]::IsNullOrWhiteSpace($catalog)) {
        Throw-FriendlyError -Detail "Package command requires --catalog." -Code 2 -Summary "Package catalog selection is missing." -Hint "Select --catalog=builtin or --catalog=custom."
    }
    $normalizedAction = $action.Trim().ToLowerInvariant()
    $normalizedCatalog = $catalog.Trim().ToLowerInvariant()
    if ($normalizedAction -eq 'setup-all') {
        if ($normalizedCatalog -ne 'all') {
            Throw-FriendlyError -Detail "Package setup-all operates on both isolated catalogs." -Code 2 -Summary "Package catalog selection is invalid." -Hint "Use --action=setup-all --catalog=all to review builtin and custom packages together."
        }
        if (-not [string]::IsNullOrWhiteSpace($packageId)) {
            Throw-FriendlyError -Detail "Package setup-all does not take an individual package id." -Code 2 -Summary "Package selection is invalid." -Hint "Omit --package when using --action=setup-all."
        }
        Invoke-ProdicloudPackageSetupAll -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
        return
    }
    Invoke-ProdicloudPackageOperation -Action $normalizedAction -PackageId $packageId -Catalog $normalizedCatalog -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
}
