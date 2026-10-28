# Contract for the 'task' command.

function Get-ProdicloudTaskOptionSpecifications {
    return @(
        (Get-ProdicloudTaskPerfOptionSpecification),
        (Get-ProdicloudTaskHelpOptionSpecification),
        (Get-ProdicloudTaskListOptionSpecification),
        (Get-ProdicloudTaskHistoryOptionSpecification),
        (Get-ProdicloudTaskSaveAppStateOptionSpecification),
        (Get-ProdicloudTaskRestoreAppStateOptionSpecification),
        (Get-ProdicloudTaskSourceOptionSpecification),
        (Get-ProdicloudTaskTargetOptionSpecification),
        (Get-ProdicloudTaskUserOptionSpecification),
        (Get-ProdicloudTaskRunVmInitOptionSpecification),
        (Get-ProdicloudTaskRunVmUpdateOptionSpecification),
        (Get-ProdicloudTaskVmInitOptionSpecification),
        (Get-ProdicloudTaskVmUpdateOptionSpecification),
        (Get-ProdicloudTaskVmInitTaskOptionSpecification),
        (Get-ProdicloudTaskVmUpdateTaskOptionSpecification),
        (New-ProdicloudCommandOptionSpecification -Name 'package' -TakesValue),
        (New-ProdicloudCommandOptionSpecification -Name 'package-catalog' -TakesValue),
        (New-ProdicloudCommandOptionSpecification -Name 'enable'),
        (New-ProdicloudCommandOptionSpecification -Name 'disable'),
        (Get-ProdicloudTaskDisabledOptionSpecification),
        (Get-ProdicloudTaskGroupOptionSpecification),
        (Get-ProdicloudTaskVmNameOptionSpecification),
        (Get-ProdicloudTaskSubscriptionIdOptionSpecification),
        (Get-ProdicloudTaskWindowsOptionSpecification),
        (Get-ProdicloudTaskLinuxOptionSpecification)
    )
}
