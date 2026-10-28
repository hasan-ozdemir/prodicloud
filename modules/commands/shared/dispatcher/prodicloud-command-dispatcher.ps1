# Shared command dispatcher.

function Invoke-ProdicloudCommandDispatcher {
    param(
        [string]$CommandName,
        [hashtable]$Options,
        [string]$HelpTopic = '',
        [hashtable]$FrontendContext = @{}
    )

    Assert-ProdicloudCommandOptions -CommandName $CommandName -Options $Options

    $autoRequested = Get-ProdicloudCliOptionBool -Options $Options -Name 'auto' -DefaultValue $false
    $script:AutoMode = ($CommandName -in @('create','initialize','update','delete')) -and $autoRequested
    $script:PerfMode = Get-ProdicloudCliOptionBool -Options $Options -Name 'perf' -DefaultValue $false
    $windowsFlag = Get-ProdicloudCliOptionBool -Options $Options -Name 'windows' -DefaultValue $false
    $linuxFlag = Get-ProdicloudCliOptionBool -Options $Options -Name 'linux' -DefaultValue $false
    if ($windowsFlag -and $linuxFlag) {
        Throw-FriendlyError -Detail 'Both --windows and --linux were provided.' -Code 2 -Summary 'Conflicting OS selection flags were provided.' -Hint 'Use only one of --windows or --linux.'
    }

    $script:ConfigOverrides = @{}
    $script:ProdicloudConfigValueSources = @{}
    $script:ActiveCommand = [string]$CommandName
    $explicitVmName = [string](Get-ProdicloudCliOptionText -Options $Options -Name 'vm-name')
    if (-not [string]::IsNullOrWhiteSpace([string]$explicitVmName)) {
        $script:ConfigOverrides['SELECTED_VM_NAME'] = $explicitVmName.Trim()
        Set-ProdicloudConfigValueSource -Key 'SELECTED_VM_NAME' -Source 'cli value'
    }
    $helpRequested = Get-ProdicloudCliOptionBool -Options $Options -Name 'help' -DefaultValue $false

    $commandPerfWatch = $null
    if ($script:PerfMode) {
        $commandPerfWatch = [System.Diagnostics.Stopwatch]::StartNew()
    }

    try {
        if ($helpRequested -and $CommandName -ne 'help') {
            Show-ProdicloudCommandHelp -Topic $CommandName
            return
        }

        if ($CommandName -notin @('help','exec')) {
            Write-ProdicloudActionProgress -Action ("run {0} command" -f [string]$CommandName)
        }

        Initialize-ProdicloudCommandSubscriptionState -CommandName $CommandName -Options $Options | Out-Null

        switch ($CommandName) {
            'help' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudHelpEntry -HelpTopic $HelpTopic
                return
            }
            'configure' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudConfigureCommand -Options $Options -AutoMode:$false -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'list' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudListCommand -Options $Options
                return
            }
            'show' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudShowCommand -Options $Options -AutoMode:$false -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'do' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudDoCommand -Options $Options
                return
            }
            'task' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudTaskCommand -Options $Options -AutoMode:$false -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag | Out-Null
                return
            }
            'create' {
                $wizardValues = if ($FrontendContext.ContainsKey('CreateWizardValues')) { [hashtable]$FrontendContext['CreateWizardValues'] } else { @{} }
                $wizardMode = [bool]($FrontendContext.ContainsKey('CreateWizardMode') -and $FrontendContext['CreateWizardMode'])
                Invoke-ProdicloudCreateCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag -WizardValues $wizardValues -WizardMode:$wizardMode
                return
            }
            'initialize' {
                Invoke-ProdicloudInitializeCommand -Options $Options -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag -AutoMode:$script:AutoMode
                return
            }
            'update' {
                Invoke-ProdicloudUpdateCommand -Options $Options -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag -AutoMode:$script:AutoMode
                return
            }
            'package' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudPackageCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag | Out-Null
                return
            }
            'component' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudComponentCommand -Options $Options -AutoMode:$script:AutoMode | Out-Null
                return
            }
            'move' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudMoveCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'resize' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudResizeCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'set' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudSetCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
                return
            }
            'exec' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudExecCommand -Options $Options
                return
            }
            'connect' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudConnectCommand -Options $Options
                return
            }
            'delete' {
                $script:UpdateMode = $false
                $script:ExecutionMode = 'default'
                Invoke-ProdicloudDeleteCommand -Options $Options -AutoMode:$script:AutoMode -WindowsFlag:$windowsFlag -LinuxFlag:$linuxFlag
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

            Write-ProdicloudPerfTiming -Category 'command' -Label ([string]$CommandName) -Seconds $commandPerfWatch.Elapsed.TotalSeconds
        }
    }
}
