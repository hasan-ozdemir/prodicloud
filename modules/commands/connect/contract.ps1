# Contract for the 'connect' command.

function Get-ClagnosConnectOptionSpecifications {
    return @(
        (Get-ClagnosConnectPerfOptionSpecification),
        (Get-ClagnosConnectHelpOptionSpecification),
        (Get-ClagnosConnectSubscriptionIdOptionSpecification),
        (Get-ClagnosConnectGroupOptionSpecification),
        (Get-ClagnosConnectVmNameOptionSpecification),
        (Get-ClagnosConnectUserOptionSpecification),
        (Get-ClagnosConnectTestOptionSpecification),
        (Get-ClagnosConnectSshOptionSpecification),
        (Get-ClagnosConnectRdpOptionSpecification)
    )
}
