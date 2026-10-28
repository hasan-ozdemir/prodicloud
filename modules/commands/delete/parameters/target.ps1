# 'target' option binding for 'delete'.

function Get-ProdicloudDeleteTargetOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'target' -TakesValue -Validate {
        param([hashtable]$Options)
        $targetText = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'target')
        $target = $targetText.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($target)) {
            Throw-FriendlyError -Detail "Option '--target' is required for delete command." -Code 2 -Summary "Delete target is missing." -Hint "Use --target=group|network|vm|disk."
        }
        if ($target -notin @('group','network','vm','disk')) {
            Throw-FriendlyError -Detail ("Invalid delete target '{0}'." -f $targetText) -Code 2 -Summary "Delete target is invalid." -Hint "Valid targets: group, network, vm, disk."
        }
    })
}
