# Contract for the 'connect' command.

function Get-ProdicloudConnectOptionSpecifications {
    return @(
        (Get-ProdicloudConnectPerfOptionSpecification),
        (Get-ProdicloudConnectHelpOptionSpecification),
        (Get-ProdicloudConnectSubscriptionIdOptionSpecification),
        (Get-ProdicloudConnectGroupOptionSpecification),
        (Get-ProdicloudConnectVmNameOptionSpecification),
        (Get-ProdicloudConnectUserOptionSpecification),
        (Get-ProdicloudConnectCommandOptionSpecification),
        (Get-ProdicloudConnectTestOptionSpecification),
        (Get-ProdicloudConnectSshOptionSpecification),
        (Get-ProdicloudConnectRdpOptionSpecification),
        (Get-ProdicloudConnectPowerShellOptionSpecification)
    )
}
