# Shared command-contract resolution helpers.

function Get-ProdicloudCommandOptionSpecifications {
    param(
        [string]$CommandName
    )

    switch ($CommandName) {
        'create' { return @(Get-ProdicloudCreateOptionSpecifications) }
        'initialize' { return @(Get-ProdicloudInitializeOptionSpecifications) }
        'update' { return @(Get-ProdicloudUpdateOptionSpecifications) }
        'configure' { return @(Get-ProdicloudConfigureOptionSpecifications) }
        'list' { return @(Get-ProdicloudListOptionSpecifications) }
        'show' { return @(Get-ProdicloudShowOptionSpecifications) }
        'do' { return @(Get-ProdicloudDoOptionSpecifications) }
        'task' { return @(Get-ProdicloudTaskOptionSpecifications) }
        'package' { return @(Get-ProdicloudPackageOptionSpecifications) }
        'component' { return @(Get-ProdicloudComponentOptionSpecifications) }
        'move' { return @(Get-ProdicloudMoveOptionSpecifications) }
        'resize' { return @(Get-ProdicloudResizeOptionSpecifications) }
        'set' { return @(Get-ProdicloudSetOptionSpecifications) }
        'exec' { return @(Get-ProdicloudExecOptionSpecifications) }
        'connect' { return @(Get-ProdicloudConnectOptionSpecifications) }
        'delete' { return @(Get-ProdicloudDeleteOptionSpecifications) }
        'help' { return @(Get-ProdicloudHelpOptionSpecifications) }
        default {
            Throw-FriendlyError -Detail ("Unsupported command '{0}'." -f $CommandName) -Code 2 -Summary "Unknown command." -Hint "Use one command: create | initialize | update | configure | list | show | do | task | package | component | exec | connect | move | resize | set | delete | help."
        }
    }
}

function Assert-ProdicloudCommandOptions {
    param(
        [string]$CommandName,
        [hashtable]$Options
    )

    $specs = @(Get-ProdicloudCommandOptionSpecifications -CommandName $CommandName)
    $allowed = @($specs | ForEach-Object { [string]$_.Name })
    foreach ($key in @($Options.Keys)) {
        $optionName = [string]$key
        if ($allowed -notcontains $optionName) {
            if ([string]::Equals([string]$CommandName, 'configure', [System.StringComparison]::OrdinalIgnoreCase) -and $optionName -in @('group','vm-name','windows','linux','subscription-id','auto')) {
                Throw-FriendlyError -Detail ("Option '--{0}' is no longer supported for 'configure'." -f $optionName) -Code 2 -Summary "Configure is now the interactive global settings editor." -Hint "Run 'prodicloud configure' without targeting flags to edit prodicloud.env. VC-specific values are managed by VM lifecycle operations and stored in <vm-name>.env."
            }
            Throw-FriendlyError -Detail ("Option '--{0}' is not supported for command '{1}'." -f $optionName, $CommandName) -Code 2 -Summary "Unsupported command option." -Hint ("Use valid options for '{0}' only." -f $CommandName)
        }
    }

    $helpRequested = Get-ProdicloudCliOptionBool -Options $Options -Name 'help' -DefaultValue $false
    if ($helpRequested -and $CommandName -ne 'help') {
        return
    }

    foreach ($spec in @($specs)) {
        if ($null -ne $spec -and $spec.PSObject.Properties.Match('Validate').Count -gt 0 -and $spec.Validate -is [scriptblock]) {
            & $spec.Validate $Options
        }
    }
}
