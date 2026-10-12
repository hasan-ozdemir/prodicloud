# Contract for task-backed program management.

function Get-ClagnosProgramOptionSpecifications {
    $actionValidation = {
        param($Options)
        $value = [string](Get-ClagnosCliOptionText -Options $Options -Name 'action')
        if ($value.Trim().ToLowerInvariant() -notin @('list','status','install','uninstall')) {
            Throw-FriendlyError -Detail "Program action must be list, status, install, or uninstall." -Code 2 -Summary "Program action is invalid." -Hint "Choose an action from the program menu."
        }
    }
    return @(
        (New-ClagnosCommandOptionSpecification -Name 'action' -TakesValue -ShortNames @('a') -Validate $actionValidation),
        (New-ClagnosCommandOptionSpecification -Name 'program' -TakesValue -ShortNames @('p')),
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
