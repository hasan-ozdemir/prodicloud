# Shared 'subscription-id' command option specification.

function Get-ProdicloudSharedSubscriptionIdOptionSpecification {
    return (New-ProdicloudCommandOptionSpecification -Name 'subscription-id' -ShortNames @('s') -TakesValue -Validate {
        param([hashtable]$Options)

        if (-not (Test-ProdicloudCliOptionPresent -Options $Options -Name 'subscription-id')) {
            return
        }

        $rawValue = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'subscription-id')
        if ([string]::IsNullOrWhiteSpace([string]$rawValue)) {
            Throw-FriendlyError `
                -Detail "Option '--subscription-id' requires a subscription id value." `
                -Code 2 `
                -Summary "Subscription id value is missing." `
                -Hint "Use '--subscription-id <subscription-guid>', '--subscription-id=<subscription-guid>', or '-s <subscription-guid>'."
        }
    })
}
