# Package management command entry.

function Invoke-ClagnosPackageCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode,
        [switch]$WindowsFlag,
        [switch]$LinuxFlag
    )

    $action = [string](Get-ClagnosCliOptionText -Options $Options -Name 'action')
    $packageId = [string](Get-ClagnosCliOptionText -Options $Options -Name 'package')
    $catalog = [string](Get-ClagnosCliOptionText -Options $Options -Name 'catalog')
    if ([string]::IsNullOrWhiteSpace($action)) {
        Throw-FriendlyError -Detail "Package command requires an action." -Code 2 -Summary "Package operation is incomplete." -Hint "Use --action=list|status|install|update|uninstall|enable|disable --catalog=builtin|custom."
    }
    if ([string]::IsNullOrWhiteSpace($catalog)) {
        Throw-FriendlyError -Detail "Package command requires --catalog." -Code 2 -Summary "Package catalog selection is missing." -Hint "Select --catalog=builtin or --catalog=custom."
    }
    Invoke-ClagnosPackageOperation -Action $action.Trim().ToLowerInvariant() -PackageId $packageId -Catalog $catalog.Trim().ToLowerInvariant() -Options $Options -AutoMode:$AutoMode -WindowsFlag:$WindowsFlag -LinuxFlag:$LinuxFlag
}
