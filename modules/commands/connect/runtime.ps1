# Connect command runtime helpers.

function Resolve-ClagnosConnectMode {
    param(
        [hashtable]$Options
    )

    $sshRequested = Test-ClagnosCliOptionPresent -Options $Options -Name 'ssh'
    $rdpRequested = Test-ClagnosCliOptionPresent -Options $Options -Name 'rdp'
    $powerShellRequested = Test-ClagnosCliOptionPresent -Options $Options -Name 'powershell'
    $selectedModes = @(
        if ($sshRequested) { 'ssh' }
        if ($rdpRequested) { 'rdp' }
        if ($powerShellRequested) { 'powershell' }
    )

    if (@($selectedModes).Count -gt 1) {
        Throw-FriendlyError `
            -Detail ("More than one connection transport was provided: {0}." -f (@($selectedModes) -join ', ')) `
            -Code 66 `
            -Summary "Connect mode is ambiguous." `
            -Hint "Use exactly one of --ssh, --rdp, or --powershell."
    }

    if ($sshRequested) {
        return 'ssh'
    }
    if ($rdpRequested) {
        return 'rdp'
    }
    if ($powerShellRequested) {
        return 'powershell'
    }

    Throw-FriendlyError `
        -Detail "Connect command requires one transport selector." `
        -Code 66 `
        -Summary "Connect mode is missing." `
        -Hint "Use clagnos connect with exactly one of --ssh, --rdp, or --powershell."
}
