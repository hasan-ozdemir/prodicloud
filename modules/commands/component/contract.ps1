# Contract for component-level CRUD operations.

function Get-ClagnosComponentOptionSpecifications {
    $actionValidation = {
        param($Options)
        $value = [string](Get-ClagnosCliOptionText -Options $Options -Name 'action')
        if ($value.Trim().ToLowerInvariant() -notin @('list','show','create','update','delete','attach','detach')) {
            Throw-FriendlyError -Detail "Component action must be list, show, create, update, delete, attach, or detach." -Code 2 -Summary "Component action is invalid." -Hint "Choose one action from the component menu."
        }
    }
    $typeValidation = {
        param($Options)
        $value = [string](Get-ClagnosCliOptionText -Options $Options -Name 'type')
        if ($value.Trim().ToLowerInvariant() -notin @(Get-ClagnosComponentTypeIds)) {
            Throw-FriendlyError -Detail "Component type is not supported by Clagnos." -Code 2 -Summary "Component type is invalid." -Hint ("Valid types: {0}." -f ((Get-ClagnosComponentTypeIds) -join ', '))
        }
    }
    return @(
        (New-ClagnosCommandOptionSpecification -Name 'action' -TakesValue -ShortNames @('a') -Validate $actionValidation),
        (New-ClagnosCommandOptionSpecification -Name 'type' -TakesValue -ShortNames @('t') -Validate $typeValidation),
        (New-ClagnosCommandOptionSpecification -Name 'name' -TakesValue -ShortNames @('n')),
        (Get-ClagnosSharedGroupOptionSpecification),
        (Get-ClagnosSharedVmNameOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosSharedYesOptionSpecification),
        (Get-ClagnosSharedPerfOptionSpecification),
        (Get-ClagnosSharedHelpOptionSpecification)
    )
}
