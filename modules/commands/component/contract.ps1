# Contract for component-level CRUD operations.

function Get-ProdicloudComponentOptionSpecifications {
    $actionValidation = {
        param($Options)
        $value = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'action')
        if ($value.Trim().ToLowerInvariant() -notin @('list','show','create','update','delete','attach','detach')) {
            Throw-FriendlyError -Detail "Component action must be list, show, create, update, delete, attach, or detach." -Code 2 -Summary "Component action is invalid." -Hint "Choose one action from the component menu."
        }
    }
    $typeValidation = {
        param($Options)
        $value = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'type')
        if ($value.Trim().ToLowerInvariant() -notin @(Get-ProdicloudComponentTypeIds)) {
            Throw-FriendlyError -Detail "Component type is not supported by Prodicloud." -Code 2 -Summary "Component type is invalid." -Hint ("Valid types: {0}." -f ((Get-ProdicloudComponentTypeIds) -join ', '))
        }
    }
    return @(
        (New-ProdicloudCommandOptionSpecification -Name 'action' -TakesValue -ShortNames @('a') -Validate $actionValidation),
        (New-ProdicloudCommandOptionSpecification -Name 'type' -TakesValue -ShortNames @('t') -Validate $typeValidation),
        (New-ProdicloudCommandOptionSpecification -Name 'name' -TakesValue -ShortNames @('n')),
        (Get-ProdicloudSharedGroupOptionSpecification),
        (Get-ProdicloudSharedVmNameOptionSpecification),
        (Get-ProdicloudSharedSubscriptionIdOptionSpecification),
        (Get-ProdicloudSharedYesOptionSpecification),
        (Get-ProdicloudSharedPerfOptionSpecification),
        (Get-ProdicloudSharedHelpOptionSpecification)
    )
}
