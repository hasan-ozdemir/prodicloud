# Public contract for builtin and custom package catalog management.

function Get-ProdicloudPackageOptionSpecifications {
    $actionValidation = {
        param($Options)
        $value = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'action')
        if ($value.Trim().ToLowerInvariant() -notin @('list','status','install','repair','update','uninstall','reinstall','enable','disable','setup-all')) {
            Throw-FriendlyError -Detail "Package action must be list, status, install, repair, update, uninstall, reinstall, enable, disable, or setup-all." -Code 2 -Summary "Package action is invalid." -Hint "Choose an action from the package menu."
        }
    }
    $catalogValidation = {
        param($Options)
        $value = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'catalog')
        $action = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'action')
        $isSetupAll = [string]::Equals($action.Trim(),'setup-all',[System.StringComparison]::OrdinalIgnoreCase)
        $validCatalog = if ($isSetupAll) { @('all') } else { @('builtin','custom') }
        if ($value.Trim().ToLowerInvariant() -notin $validCatalog) {
            $hint = if ($isSetupAll) { 'Use --catalog=all with --action=setup-all.' } else { 'Use --catalog=builtin or --catalog=custom.' }
            $detail = if ($isSetupAll) { 'Package setup-all must select both isolated catalogs.' } else { 'Package catalog must be builtin or custom.' }
            Throw-FriendlyError -Detail $detail -Code 2 -Summary "Package catalog is invalid." -Hint $hint
        }
    }
    return @(
        (New-ProdicloudCommandOptionSpecification -Name 'action' -TakesValue -ShortNames @('a') -Validate $actionValidation),
        (New-ProdicloudCommandOptionSpecification -Name 'package' -TakesValue -ShortNames @('p')),
        (New-ProdicloudCommandOptionSpecification -Name 'catalog' -TakesValue -Validate $catalogValidation),
        (Get-ProdicloudSharedGroupOptionSpecification),
        (Get-ProdicloudSharedVmNameOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudSharedWindowsOptionSpecification),
        (Get-ProdicloudSharedLinuxOptionSpecification),
        (Get-ProdicloudSharedYesOptionSpecification),
        (Get-ProdicloudSharedPerfOptionSpecification),
        (Get-ProdicloudSharedHelpOptionSpecification)
    )
}
