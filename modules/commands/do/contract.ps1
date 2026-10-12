# Contract for the 'do' command.

function Get-ClagnosDoOptionSpecifications {
    return @(
        (Get-ClagnosDoPerfOptionSpecification),
        (Get-ClagnosDoHelpOptionSpecification),
        (Get-ClagnosSharedSubscriptionIdOptionSpecification),
        (Get-ClagnosDoGroupOptionSpecification),
        (Get-ClagnosDoVmNameOptionSpecification),
        (Get-ClagnosDoVmActionOptionSpecification)
    )
}
