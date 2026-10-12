# Shared CLI parsing and action-plan helpers.

# Handles Convert-ClagnosCliTextToTokens.
function Convert-ClagnosCliTextToTokens {
    param(
        [object]$Text
    )

    $parts = @()
    if ($Text -is [System.Array]) {
        foreach ($entry in @($Text)) {
            $parts += [string]$entry
        }
    }
    elseif ($null -ne $Text) {
        $parts += [string]$Text
    }

    $joined = ($parts -join "`n")
    return @(
        [regex]::Split([string]$joined, '\s+') |
            ForEach-Object { [string]$_ } |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
    )
}

function Get-ClagnosCliOptionSpecificationLookup {
    param(
        [string]$CommandName,
        [switch]$IncludeHelpFallback
    )

    $nameMap = @{}
    $shortMap = @{}
    $specs = @()
    $resolvedCommand = [string]$CommandName
    if (-not [string]::IsNullOrWhiteSpace([string]$resolvedCommand)) {
        $specs = @(Get-ClagnosCommandOptionSpecifications -CommandName $resolvedCommand)
    }
    elseif ($IncludeHelpFallback) {
        $specs = @(Get-ClagnosHelpOptionSpecifications)
    }

    foreach ($spec in @($specs)) {
        if ($null -eq $spec) {
            continue
        }

        $name = [string]$spec.Name
        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $nameMap[$name.Trim().ToLowerInvariant()] = $spec
        }

        if ($spec.PSObject.Properties.Match('ShortNames').Count -gt 0) {
            foreach ($shortName in @($spec.ShortNames)) {
                $shortText = [string]$shortName
                if ([string]::IsNullOrWhiteSpace([string]$shortText)) {
                    continue
                }
                $shortMap[$shortText.Trim().ToLowerInvariant()] = $spec
            }
        }
    }

    return [pscustomobject]@{
        NameMap = $nameMap
        ShortMap = $shortMap
        Specifications = @($specs)
    }
}

function Test-ClagnosCliOptionSpecificationTakesValue {
    param(
        [object]$Specification
    )

    if ($null -eq $Specification) {
        return $false
    }

    if ($Specification.PSObject.Properties.Match('TakesValue').Count -gt 0) {
        return [bool]$Specification.TakesValue
    }

    return $false
}

function Get-ClagnosCliSupportedShortOptionSummary {
    param(
        [hashtable]$ShortMap
    )

    $shortNames = @($ShortMap.Keys | Sort-Object -Unique)
    if (@($shortNames).Count -eq 0) {
        return '(none)'
    }

    return (@($shortNames) | ForEach-Object { "-{0}" -f [string]$_ }) -join ', '
}

# Handles Parse-ClagnosCliArguments.
function Parse-ClagnosCliArguments {
    param(
        [string]$CommandToken,
        [string[]]$RawArgs
    )

    $rawCommand = if ($null -eq $CommandToken) { '' } else { [string]$CommandToken }
    $remaining = @()
    if (-not [string]::IsNullOrWhiteSpace($rawCommand) -and $rawCommand.StartsWith('-')) {
        $remaining += $rawCommand
        $rawCommand = ''
    }
    $remaining += @($RawArgs)

    $validCommands = Get-ClagnosValidCommandList
    $candidateCommand = ''
    if (-not [string]::IsNullOrWhiteSpace($rawCommand) -and -not $rawCommand.StartsWith('-')) {
        $candidateCommand = $rawCommand.Trim().ToLowerInvariant()
        if ($validCommands -notcontains $candidateCommand) {
            Throw-FriendlyError `
                -Detail ("Unknown command '{0}'." -f $rawCommand) `
                -Code 2 `
                -Summary "Unknown command." `
                -Hint "Use one command: create | initialize | update | configure | list | show | do | task | program | component | move | resize | set | exec | connect | delete | help."
        }
    }

    $optionSpecLookup = Get-ClagnosCliOptionSpecificationLookup -CommandName $candidateCommand -IncludeHelpFallback:([string]::IsNullOrWhiteSpace([string]$candidateCommand))

    $normalizedArgs = @()
    for ($i = 0; $i -lt @($remaining).Count; $i++) {
        $rawArgText = if ($null -eq $remaining[$i]) { '' } else { [string]$remaining[$i] }
        if ([string]::IsNullOrWhiteSpace($rawArgText)) {
            continue
        }

        if (-not $rawArgText.StartsWith('-') -or $rawArgText.StartsWith('--')) {
            $normalizedArgs += $rawArgText
            continue
        }

        $shortMatch = [regex]::Match($rawArgText, '^-(?<name>[^=\s]+)(?:=(?<value>.*))?$')
        if (-not $shortMatch.Success) {
            Throw-FriendlyError `
                -Detail ("Unsupported short option format '{0}'." -f $rawArgText) `
                -Code 2 `
                -Summary "Invalid option format." `
                -Hint ("Supported short options: {0}. Use long options for others." -f (Get-ClagnosCliSupportedShortOptionSummary -ShortMap $optionSpecLookup.ShortMap))
        }

        $shortName = [string]$shortMatch.Groups['name'].Value
        if ([string]::IsNullOrWhiteSpace([string]$shortName) -or $shortName.Length -ne 1) {
            Throw-FriendlyError `
                -Detail ("Unsupported short option format '{0}'." -f $rawArgText) `
                -Code 2 `
                -Summary "Invalid option format." `
                -Hint ("Supported short options: {0}. Use long options for others." -f (Get-ClagnosCliSupportedShortOptionSummary -ShortMap $optionSpecLookup.ShortMap))
        }

        $shortKey = $shortName.Trim().ToLowerInvariant()
        if (-not $optionSpecLookup.ShortMap.ContainsKey($shortKey)) {
            Throw-FriendlyError `
                -Detail ("Unsupported short option format '{0}'." -f $rawArgText) `
                -Code 2 `
                -Summary "Invalid option format." `
                -Hint ("Supported short options: {0}. Use long options for others." -f (Get-ClagnosCliSupportedShortOptionSummary -ShortMap $optionSpecLookup.ShortMap))
        }

        $spec = $optionSpecLookup.ShortMap[$shortKey]
        $optionName = [string]$spec.Name
        $explicitValue = ''
        if ($shortMatch.Groups['value'].Success) {
            $explicitValue = [string]$shortMatch.Groups['value'].Value
        }

        if (Test-ClagnosCliOptionSpecificationTakesValue -Specification $spec) {
            $resolvedValue = $explicitValue
            if ([string]::IsNullOrWhiteSpace([string]$resolvedValue)) {
                if (($i + 1) -ge @($remaining).Count) {
                    Throw-FriendlyError `
                        -Detail ("Option '-{0}' requires a value." -f $shortKey) `
                        -Code 2 `
                        -Summary "Invalid option format." `
                        -Hint ("Use '-{0} <value>' or '--{1}=<value>'." -f $shortKey, $optionName)
                }

                $nextArgText = if ($null -eq $remaining[$i + 1]) { '' } else { [string]$remaining[$i + 1] }
                if ([string]::IsNullOrWhiteSpace([string]$nextArgText) -or $nextArgText.StartsWith('-')) {
                    Throw-FriendlyError `
                        -Detail ("Option '-{0}' requires a value." -f $shortKey) `
                        -Code 2 `
                        -Summary "Invalid option format." `
                        -Hint ("Use '-{0} <value>' or '--{1}=<value>'." -f $shortKey, $optionName)
                }

                $resolvedValue = $nextArgText
                $i++
            }

            $normalizedArgs += ("--{0}={1}" -f $optionName, $resolvedValue)
            continue
        }

        if ($shortMatch.Groups['value'].Success) {
            $normalizedArgs += ("--{0}={1}" -f $optionName, $explicitValue)
            continue
        }

        $normalizedArgs += ("--{0}=true" -f $optionName)
    }

    $options = @{}
    $positionals = @()
    for ($i = 0; $i -lt @($normalizedArgs).Count; $i++) {
        $arg = $normalizedArgs[$i]
        $text = if ($null -eq $arg) { '' } else { [string]$arg }
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        if ($text.StartsWith('--')) {
            $body = $text.Substring(2)
            if ([string]::IsNullOrWhiteSpace($body)) {
                continue
            }

            $name = $body
            $value = $true
            $eqIndex = $body.IndexOf('=')
            if ($eqIndex -ge 0) {
                $name = $body.Substring(0, $eqIndex)
                $value = $body.Substring($eqIndex + 1)
            }
            else {
                $nameKeyCandidate = $name.Trim().ToLowerInvariant()
                if ($optionSpecLookup.NameMap.ContainsKey($nameKeyCandidate)) {
                    $nameSpec = $optionSpecLookup.NameMap[$nameKeyCandidate]
                    if ((Test-ClagnosCliOptionSpecificationTakesValue -Specification $nameSpec) -and (($i + 1) -lt @($normalizedArgs).Count)) {
                        $nextArgText = if ($null -eq $normalizedArgs[$i + 1]) { '' } else { [string]$normalizedArgs[$i + 1] }
                        if (-not [string]::IsNullOrWhiteSpace([string]$nextArgText) -and -not $nextArgText.StartsWith('-')) {
                            $value = $nextArgText
                            $i++
                        }
                    }
                }
            }

            $nameKey = [string]$name
            $nameKey = $nameKey.Trim().ToLowerInvariant()
            if ([string]::IsNullOrWhiteSpace($nameKey)) {
                continue
            }

            $options[$nameKey] = $value
            continue
        }

        $positionals += $text
    }

    $command = ''
    $helpTopic = ''
    if (-not [string]::IsNullOrWhiteSpace($rawCommand)) {
        $command = $rawCommand.Trim().ToLowerInvariant()
        if ($validCommands -notcontains $command) {
            Throw-FriendlyError `
                -Detail ("Unknown command '{0}'." -f $rawCommand) `
                -Code 2 `
                -Summary "Unknown command." `
                -Hint "Use one command: create | initialize | update | configure | list | show | do | task | program | component | move | resize | set | exec | connect | delete | help."
        }
    }
    elseif ($options.ContainsKey('help')) {
        $command = 'help'
        if ($positionals.Count -eq 0) {
            $helpTopic = '__overview__'
        }
    }
    else {
        Throw-FriendlyError `
            -Detail "No command was provided." `
            -Code 2 `
            -Summary "Command is required." `
            -Hint "Use one command: create | initialize | update | configure | list | show | do | task | program | component | move | resize | set | exec | connect | delete | help. Example: clagnos create --auto"
    }

    if ($command -eq 'help') {
        if ($positionals.Count -gt 1) {
            Throw-FriendlyError `
                -Detail ("Too many help topics were provided: {0}" -f ($positionals -join ', ')) `
                -Code 2 `
                -Summary "Too many help topic arguments were provided." `
                -Hint "Use only one help topic. Example: clagnos help create"
        }

        $positionalTopic = ''
        if ($positionals.Count -eq 1) {
            $positionalTopic = [string]$positionals[0]
            $positionalTopic = $positionalTopic.Trim().ToLowerInvariant()
        }

        if (-not [string]::IsNullOrWhiteSpace($positionalTopic)) {
            $helpTopic = $positionalTopic
        }
        elseif ($helpTopic -ne '__overview__') {
            $helpTopic = ''
        }
    }
    else {
        if ($positionals.Count -gt 0) {
            Throw-FriendlyError `
                -Detail ("Unexpected positional argument(s): {0}" -f ($positionals -join ', ')) `
                -Code 2 `
                -Summary "Unexpected arguments were provided." `
                -Hint "Use only supported options after the command."
        }
    }

    return [pscustomobject]@{
        Command = $command
        Options = $options
        HelpTopic = $helpTopic
    }
}

# Handles Get-ClagnosCliOptionRaw.
function Get-ClagnosCliOptionRaw {
    param(
        [hashtable]$Options,
        [string]$Name
    )

    if ($null -eq $Options) {
        return $null
    }

    $key = [string]$Name
    if ([string]::IsNullOrWhiteSpace($key)) {
        return $null
    }

    $key = $key.Trim().ToLowerInvariant()
    if ($Options.ContainsKey($key)) {
        return $Options[$key]
    }

    return $null
}

# Handles Test-ClagnosCliOptionPresent.
function Test-ClagnosCliOptionPresent {
    param(
        [hashtable]$Options,
        [string]$Name
    )

    if ($null -eq $Options) {
        return $false
    }

    $key = [string]$Name
    if ([string]::IsNullOrWhiteSpace($key)) {
        return $false
    }

    return $Options.ContainsKey($key.Trim().ToLowerInvariant())
}

# Handles Convert-ClagnosCliValueToBool.
function Convert-ClagnosCliValueToBool {
    param(
        [string]$OptionName,
        [object]$RawValue
    )

    if ($RawValue -is [bool]) {
        return [bool]$RawValue
    }

    $text = [string]$RawValue
    $trimmed = $text.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $true
    }
    if ($trimmed -in @('1','true','yes','y','on')) {
        return $true
    }
    if ($trimmed -in @('0','false','no','n','off')) {
        return $false
    }

    Throw-FriendlyError `
        -Detail ("Option '--{0}' received invalid boolean value '{1}'." -f $OptionName, $text) `
        -Code 2 `
        -Summary "Invalid boolean option value." `
        -Hint ("Use '--{0}' or '--{0}=true|false'." -f $OptionName)
}

# Handles Get-ClagnosCliOptionBool.
function Get-ClagnosCliOptionBool {
    param(
        [hashtable]$Options,
        [string]$Name,
        [bool]$DefaultValue = $false
    )

    if (-not (Test-ClagnosCliOptionPresent -Options $Options -Name $Name)) {
        return [bool]$DefaultValue
    }

    $raw = Get-ClagnosCliOptionRaw -Options $Options -Name $Name
    return (Convert-ClagnosCliValueToBool -OptionName $Name -RawValue $raw)
}

# Handles Get-ClagnosCliOptionText.
function Get-ClagnosCliOptionText {
    param(
        [hashtable]$Options,
        [string]$Name
    )

    if (-not (Test-ClagnosCliOptionPresent -Options $Options -Name $Name)) {
        return $null
    }

    $raw = Get-ClagnosCliOptionRaw -Options $Options -Name $Name
    if ($raw -is [bool]) {
        if ([bool]$raw) {
            return ''
        }

        return $null
    }

    return [string]$raw
}

# Handles Get-ClagnosActionOrder.
function Get-ClagnosActionOrder {
    return @('configure', 'group', 'network', 'vm-deploy', 'vm-init', 'vm-update', 'vm-summary')
}

# Handles Resolve-ClagnosActionValue.
function Resolve-ClagnosActionValue {
    param(
        [string]$OptionName,
        [string]$RawValue
    )

    $text = if ($null -eq $RawValue) { '' } else { [string]$RawValue }
    $normalized = $text.Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        Throw-FriendlyError `
            -Detail ("Option '--{0}' requires a value." -f $OptionName) `
            -Code 2 `
            -Summary "Step option value is missing." `
            -Hint ("Use '--{0}=configure|group|network|vm-deploy|vm-init|vm-update|vm-summary'." -f $OptionName)
    }

    $allowed = Get-ClagnosActionOrder
    if ($allowed -notcontains $normalized) {
        Throw-FriendlyError `
            -Detail ("Option '--{0}' received invalid value '{1}'." -f $OptionName, $RawValue) `
            -Code 2 `
            -Summary "Invalid step option value." `
            -Hint ("Valid values: {0}" -f ($allowed -join ', '))
    }

    return $normalized
}

# Handles Resolve-ClagnosActionPlan.
function Resolve-ClagnosActionPlan {
    param(
        [string]$CommandName,
        [hashtable]$Options
    )

    $order = Get-ClagnosActionOrder
    $supportsActionOptions = ($CommandName -in @('create', 'update'))
    $hasFrom = Test-ClagnosCliOptionPresent -Options $Options -Name 'step-from'
    $hasTo = Test-ClagnosCliOptionPresent -Options $Options -Name 'step-to'
    $hasSingle = Test-ClagnosCliOptionPresent -Options $Options -Name 'step'

    if (-not $supportsActionOptions -and ($hasFrom -or $hasTo -or $hasSingle)) {
        Throw-FriendlyError `
            -Detail ("Step options are not supported for command '{0}'." -f $CommandName) `
            -Code 2 `
            -Summary "Unsupported command option." `
            -Hint "Use --step-from/--step-to/--step only with create or update."
    }

    if ($hasSingle -and ($hasFrom -or $hasTo)) {
        Throw-FriendlyError `
            -Detail "Option '--step' cannot be combined with '--step-from' or '--step-to'." `
            -Code 2 `
            -Summary "Conflicting step options were provided." `
            -Hint "Use --step alone, or use --step-from/--step-to as a range."
    }

    if (-not $hasFrom -and -not $hasTo -and -not $hasSingle) {
        if ([string]::Equals([string]$CommandName, 'create', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Mode = 'full'
                Target = 'vm-summary'
                Actions = @('configure', 'group', 'network', 'vm-deploy', 'vm-summary')
            }
        }
        if ([string]::Equals([string]$CommandName, 'update', [System.StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                Mode = 'full'
                Target = 'vm-summary'
                Actions = @('configure', 'vm-update', 'vm-summary')
            }
        }
        return [pscustomobject]@{
            Mode = 'full'
            Target = 'vm-summary'
            Actions = @($order)
        }
    }

    if ($hasSingle) {
        $singleTarget = Resolve-ClagnosActionValue -OptionName 'step' -RawValue ([string](Get-ClagnosCliOptionText -Options $Options -Name 'step'))
        $allowedActions = if ($CommandName -eq 'create') { @('configure','group','network','vm-deploy','vm-summary') } else { @('configure','vm-update','vm-summary') }
        if ($allowedActions -notcontains $singleTarget) {
            $hint = if ($CommandName -eq 'create') { "Use 'initialize' for vm-init and 'update' or 'program' for guest maintenance and software." } else { "Use 'initialize' for vm-init or the component and lifecycle commands for Azure resource changes." }
            Throw-FriendlyError -Detail ("Step '{0}' is outside the {1} command contract." -f $singleTarget,$CommandName) -Code 2 -Summary "Unsupported lifecycle step." -Hint $hint
        }
        return [pscustomobject]@{
            Mode = 'single'
            Target = $singleTarget
            Actions = @($singleTarget)
        }
    }

    $fromStep = if ($hasFrom) {
        Resolve-ClagnosActionValue -OptionName 'step-from' -RawValue ([string](Get-ClagnosCliOptionText -Options $Options -Name 'step-from'))
    }
    else {
        [string]$order[0]
    }
    $toStep = if ($hasTo) {
        Resolve-ClagnosActionValue -OptionName 'step-to' -RawValue ([string](Get-ClagnosCliOptionText -Options $Options -Name 'step-to'))
    }
    else {
        [string]$order[$order.Count - 1]
    }

    $fromIndex = [array]::IndexOf($order, $fromStep)
    $toIndex = [array]::IndexOf($order, $toStep)
    if ($fromIndex -lt 0 -or $toIndex -lt 0) {
        throw ("Step range '{0}' -> '{1}' could not be mapped." -f $fromStep, $toStep)
    }
    if ($fromIndex -gt $toIndex) {
        Throw-FriendlyError `
            -Detail ("Option '--step-from={0}' is after '--step-to={1}'." -f $fromStep, $toStep) `
            -Code 2 `
            -Summary "Invalid step range." `
            -Hint "Provide a forward step range where step-from is before or equal to step-to."
    }

    $actions = @()
    for ($i = $fromIndex; $i -le $toIndex; $i++) {
        $actions += [string]$order[$i]
    }

    $allowedActions = if ($CommandName -eq 'create') { @('configure','group','network','vm-deploy','vm-summary') } else { @('configure','vm-update','vm-summary') }
    $unsupportedActions = @($actions | Where-Object { $allowedActions -notcontains [string]$_ })
    if ($unsupportedActions.Count -gt 0) {
        $hint = if ($CommandName -eq 'create') { "Use 'initialize' for vm-init and 'update' or 'program' for guest maintenance and software." } else { "Use 'initialize' for vm-init or the component and lifecycle commands for Azure resource changes." }
        Throw-FriendlyError -Detail ("Step range includes unsupported {0} step(s): {1}." -f $CommandName,($unsupportedActions -join ', ')) -Code 2 -Summary "Unsupported lifecycle step window." -Hint $hint
    }

    return [pscustomobject]@{
        Mode = 'range'
        Target = $toStep
        Start = $fromStep
        Actions = @($actions)
    }
}

# Handles Test-ClagnosActionIncluded.
function Test-ClagnosActionIncluded {
    param(
        [psobject]$ActionPlan,
        [string]$ActionName
    )

    if ($null -eq $ActionPlan) {
        return $false
    }

    $name = if ($null -eq $ActionName) { '' } else { [string]$ActionName.Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($name)) {
        return $false
    }

    return (@($ActionPlan.Actions) -contains $name)
}
