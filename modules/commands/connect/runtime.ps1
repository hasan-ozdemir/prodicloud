# Connect command runtime helpers.

function Resolve-ProdicloudConnectMode {
    param(
        [hashtable]$Options
    )

    $sshRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'ssh'
    $rdpRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'rdp'
    $powerShellRequested = Test-ProdicloudCliOptionPresent -Options $Options -Name 'powershell'
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
        -Hint "Use prodicloud connect with exactly one of --ssh, --rdp, or --powershell."
}
