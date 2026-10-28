# Component CRUD command entry.

function Invoke-ProdicloudComponentCommand {
    param(
        [hashtable]$Options,
        [switch]$AutoMode
    )

    $action = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'action')
    $type = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'type')
    $name = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'name')
    $group = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'group')
    if ([string]::IsNullOrWhiteSpace($action) -or [string]::IsNullOrWhiteSpace($type)) {
        Throw-FriendlyError -Detail "Component command requires an action and a resource type." -Code 2 -Summary "Component operation is incomplete." -Hint "Use component --action=list|show|create|update|delete --type=<component-type>."
    }
    Invoke-ProdicloudComponentOperation -Action $action.Trim().ToLowerInvariant() -Type $type.Trim().ToLowerInvariant() -Name $name -ResourceGroup $group -Options $Options -AutoMode:$AutoMode
}
