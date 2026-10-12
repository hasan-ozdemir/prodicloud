# Connect command runtime helpers.

function Resolve-ClagnosConnectMode {
    param(
        [hashtable]$Options
    )

    $sshRequested = Test-ClagnosCliOptionPresent -Options $Options -Name 'ssh'
    $rdpRequested = Test-ClagnosCliOptionPresent -Options $Options -Name 'rdp'

    if ($sshRequested -and $rdpRequested) {
        Throw-FriendlyError `
            -Detail "Both --ssh and --rdp were provided." `
            -Code 66 `
            -Summary "Connect mode is ambiguous." `
            -Hint "Use exactly one of --ssh or --rdp."
    }

    if ($sshRequested) {
        return 'ssh'
    }
    if ($rdpRequested) {
        return 'rdp'
    }

    Throw-FriendlyError `
        -Detail "Connect command requires one transport selector." `
        -Code 66 `
        -Summary "Connect mode is missing." `
        -Hint "Use clagnos connect --ssh ... or clagnos connect --rdp ...."
}
