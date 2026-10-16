# Shared command-contract resolution helpers.

function Get-ClagnosCommandOptionSpecifications {
    param(
        [string]$CommandName
    )

    switch ($CommandName) {
        'create' { return @(Get-ClagnosCreateOptionSpecifications) }
        'initialize' { return @(Get-ClagnosInitializeOptionSpecifications) }
        'update' { return @(Get-ClagnosUpdateOptionSpecifications) }
        'configure' { return @(Get-ClagnosConfigureOptionSpecifications) }
        'list' { return @(Get-ClagnosListOptionSpecifications) }
        'show' { return @(Get-ClagnosShowOptionSpecifications) }
        'do' { return @(Get-ClagnosDoOptionSpecifications) }
        'task' { return @(Get-ClagnosTaskOptionSpecifications) }
        'package' { return @(Get-ClagnosPackageOptionSpecifications) }
        'component' { return @(Get-ClagnosComponentOptionSpecifications) }
        'move' { return @(Get-ClagnosMoveOptionSpecifications) }
        'resize' { return @(Get-ClagnosResizeOptionSpecifications) }
        'set' { return @(Get-ClagnosSetOptionSpecifications) }
        'exec' { return @(Get-ClagnosExecOptionSpecifications) }
        'connect' { return @(Get-ClagnosConnectOptionSpecifications) }
        'delete' { return @(Get-ClagnosDeleteOptionSpecifications) }
        'help' { return @(Get-ClagnosHelpOptionSpecifications) }
        default {
            Throw-FriendlyError -Detail ("Unsupported command '{0}'." -f $CommandName) -Code 2 -Summary "Unknown command." -Hint "Use one command: create | initialize | update | configure | list | show | do | task | package | component | exec | connect | move | resize | set | delete | help."
        }
    }
}

function Assert-ClagnosCommandOptions {
    param(
        [string]$CommandName,
        [hashtable]$Options
    )

    $specs = @(Get-ClagnosCommandOptionSpecifications -CommandName $CommandName)
    $allowed = @($specs | ForEach-Object { [string]$_.Name })
    foreach ($key in @($Options.Keys)) {
        $optionName = [string]$key
        if ($allowed -notcontains $optionName) {
            if ([string]::Equals([string]$CommandName, 'configure', [System.StringComparison]::OrdinalIgnoreCase) -and $optionName -in @('group','vm-name','windows','linux','subscription-id','auto')) {
                Throw-FriendlyError -Detail ("Option '--{0}' is no longer supported for 'configure'." -f $optionName) -Code 2 -Summary "Configure is now the interactive global settings editor." -Hint "Run 'clagnos configure' without targeting flags to edit clagnos.env. VC-specific values are managed by VM lifecycle operations and stored in <vm-name>.env."
            }
            Throw-FriendlyError -Detail ("Option '--{0}' is not supported for command '{1}'." -f $optionName, $CommandName) -Code 2 -Summary "Unsupported command option." -Hint ("Use valid options for '{0}' only." -f $CommandName)
        }
    }

    $helpRequested = Get-ClagnosCliOptionBool -Options $Options -Name 'help' -DefaultValue $false
    if ($helpRequested -and $CommandName -ne 'help') {
        return
    }

    foreach ($spec in @($specs)) {
        if ($null -ne $spec -and $spec.PSObject.Properties.Match('Validate').Count -gt 0 -and $spec.Validate -is [scriptblock]) {
            & $spec.Validate $Options
        }
    }
}
