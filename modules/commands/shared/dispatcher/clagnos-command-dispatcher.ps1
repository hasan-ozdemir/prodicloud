# Shared command dispatcher.

function Invoke-ClagnosCommandDispatcher {
    param(
        [string]$CommandName,
        [hashtable]$Options,
        [string]$HelpTopic = '',
        [hashtable]$FrontendContext = @{}
    )

    Assert-ClagnosCommandOptions -CommandName $CommandName -Options $Options

    $autoRequested = Get-ClagnosCliOptionBool -Options $Options -Name 'auto' -DefaultValue $false
    $script:AutoMode = ($CommandName -in @('create','initialize','update','delete')) -and $autoRequested
    $script:PerfMode = Get-ClagnosCliOptionBool -Options $Options -Name 'perf' -DefaultValue $false
    $windowsFlag = Get-ClagnosCliOptionBool -Options $Options -Name 'windows' -DefaultValue $false
    $linuxFlag = Get-ClagnosCliOptionBool -Options $Options -Name 'linux' -DefaultValue $false
    if ($windowsFlag -and $linuxFlag) {
        Throw-FriendlyError -Detail 'Both --windows and --linux were provided.' -Code 2 -Summary 'Conflicting OS selection flags were provided.' -Hint 'Use only one of --windows or --linux.'
    }

    $script:ConfigOverrides = @{}
    $script:ClagnosConfigValueSources = @{}
    $script:ActiveCommand = [string]$CommandName
    $helpRequested = Get-ClagnosCliOptionBool -Options $Options -Name 'help' -DefaultValue $false

    $commandPerfWatch = $null
    if ($script:PerfMode) {
        $commandPerfWatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    try {
        if ($helpRequested -and $CommandName -ne 'help') {
            Show-ClagnosCommandHelp -Topic $CommandName
            return
        }

        if ($CommandName -notin @('help','exec')) {
            Write-ClagnosActionProgress -Action ("run {0} command" -f [string]$CommandName)
        }

        Initialize-ClagnosCommandSubscriptionState -CommandName $CommandName -Options $Options | Out-Null

        switch ($CommandName) {
            'help' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosHelpEntry -HelpTopic $HelpTopic
                return
            }
            'configure' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosConfigureCommand -Options $Options -AutoMode:$false -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'list' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosListCommand -Options $Options
                return
            }
            'show' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosShowCommand -Options $Options -AutoMode:$false -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'do' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosDoCommand -Options $Options
                return
            }
            'task' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosTaskCommand -Options $Options -AutoMode:$false -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag | Out-Null
                return
            }
            'create' {
                $wizardValues = if ($FrontendContext.ContainsKey('CreateWizardValues')) { [hashtable]$FrontendContext['CreateWizardValues'] } else { @{} }
                $wizardMode = [bool]($FrontendContext.ContainsKey('CreateWizardMode') -and $FrontendContext['CreateWizardMode'])
                Invoke-ClagnosCreateCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag -WizardValues $wizardValues -WizardMode:$wizardMode
                return
            }
            'initialize' {
                Invoke-ClagnosInitializeCommand -Options $Options -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag -AutoMode:$script:AutoMode
                return
            }
            'update' {
                Invoke-ClagnosUpdateCommand -Options $Options -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag -AutoMode:$script:AutoMode
                return
            }
            'package' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosPackageCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag | Out-Null
                return
            }
            'component' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosComponentCommand -Options $Options -AutoMode:$script:AutoMode | Out-Null
                return
            }
            'move' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosMoveCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'resize' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosResizeCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'set' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosSetCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'exec' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosExecCommand -Options $Options
                return
            }
            'connect' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosConnectCommand -Options $Options
                return
            }
            'delete' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ClagnosDeleteCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            default {
                Throw-FriendlyError -Detail ("Unknown command '{0}'." -f $CommandName) -Code 2 -Summary "Unknown command." -Hint "Use one command: create | initialize | update | configure | list | show | do | task | package | component | exec | connect | move | resize | set | delete | help."
            }
        }
    }
    finally {
        if ($script:PerfMode -and $null -ne $commandPerfWatch) {
            if ($commandPerfWatch.IsRunning) {
                $commandPerfWatch.Stop()
            }

            Write-ClagnosPerfTiming -Category 'command' -Label ([string]$CommandName) -Seconds $commandPerfWatch.Elapsed.TotalSeconds
        }
    }
}
