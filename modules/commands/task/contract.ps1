# Contract for the 'task' command.

function Get-ClagnosTaskOptionSpecifications {
    return @(
        (Get-ClagnosTaskPerfOptionSpecification),
        (Get-ClagnosTaskHelpOptionSpecification),
        (Get-ClagnosTaskListOptionSpecification),
        (Get-ClagnosTaskSaveAppStateOptionSpecification),
        (Get-ClagnosTaskRestoreAppStateOptionSpecification),
        (Get-ClagnosTaskSourceOptionSpecification),
        (Get-ClagnosTaskTargetOptionSpecification),
        (Get-ClagnosTaskUserOptionSpecification),
        (Get-ClagnosTaskRunVmInitOptionSpecification),
        (Get-ClagnosTaskRunVmUpdateOptionSpecification),
        (Get-ClagnosTaskVmInitOptionSpecification),
        (Get-ClagnosTaskVmUpdateOptionSpecification),
        (Get-ClagnosTaskVmInitTaskOptionSpecification),
        (Get-ClagnosTaskVmUpdateTaskOptionSpecification),
        (Get-ClagnosTaskDisabledOptionSpecification),
        (Get-ClagnosTaskGroupOptionSpecification),
        (Get-ClagnosTaskVmNameOptionSpecification),
        (Get-ClagnosTaskSubscriptionIdOptionSpecification),
        (Get-ClagnosTaskWindowsOptionSpecification),
        (Get-ClagnosTaskLinuxOptionSpecification)
    )
}
