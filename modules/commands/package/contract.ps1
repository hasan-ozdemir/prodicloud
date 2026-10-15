# Public contract for builtin and custom package catalog management.

function Get-ClagnosPackageOptionSpecifications {
    $actionValidation = {
        param($Options)
        $value = [string](Get-ClagnosCliOptionText -Options $Options -Name 'action')
        if ($value.Trim().ToLowerInvariant() -notin @('list','status','install','update','uninstall','enable','disable')) {
            Throw-FriendlyError -Detail "Package action must be list, status, install, update, uninstall, enable, or disable." -Code 2 -Summary "Package action is invalid." -Hint "Choose an action from the package menu."
        }
    }
    $catalogValidation = {
        param($Options)
        $value = [string](Get-ClagnosCliOptionText -Options $Options -Name 'catalog')
        if ($value.Trim().ToLowerInvariant() -notin @('builtin','custom')) {
            Throw-FriendlyError -Detail "Package catalog must be builtin or custom." -Code 2 -Summary "Package catalog is invalid." -Hint "Use --catalog=builtin or --catalog=custom."
        }
    }
    return @(
        (New-ClagnosCommandOptionSpecification -Name 'action' -TakesValue -ShortNames @('a') -Validate $actionValidation),
        (New-ClagnosCommandOptionSpecification -Name 'package' -TakesValue -ShortNames @('p')),
        (New-ClagnosCommandOptionSpecification -Name 'catalog' -TakesValue -Validate $catalogValidation),
        (Get-ClagnosSharedGroupOptionSpecification),
        (Get-ClagnosSharedVmNameOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosSharedWindowsOptionSpecification),
        (Get-ClagnosSharedLinuxOptionSpecification),
        (Get-ClagnosSharedYesOptionSpecification),
        (Get-ClagnosSharedPerfOptionSpecification),
        (Get-ClagnosSharedHelpOptionSpecification)
    )
}
