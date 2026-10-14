[CmdletBinding()]
param(
    [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:CLAGNOS_TUI_DISABLE_BACKGROUND_CACHE_WORKER = '1'
if ([string]::IsNullOrWhiteSpace([string]$RepoRoot)) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$script:TuiTestResults = New-Object 'System.Collections.Generic.List[object]'
$script:TuiRenderedLines = New-Object 'System.Collections.Generic.List[string]'
$script:TuiScreenTitles = New-Object 'System.Collections.Generic.List[string]'
$script:TuiCommandInvocations = New-Object 'System.Collections.Generic.List[object]'
$script:TuiAzureReadQueries = New-Object 'System.Collections.Generic.List[string]'
$script:TuiChoicePrompts = New-Object 'System.Collections.Generic.List[string]'
$script:TuiSubscriptionSelections = New-Object 'System.Collections.Generic.List[string]'
$script:TuiChoiceQueue = New-Object System.Collections.Queue
$script:TuiTotalNativeAzureCalls = 0
$script:TuiTotalRealDispatcherCalls = 0
$script:TuiTotalFixtureAzureReads = 0

function Assert-Tui {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-TuiOutputContains {
    param([string]$Text, [string]$Message)
    $rendered = @($script:TuiRenderedLines) -join "`n"
    Assert-Tui -Condition ($rendered.Contains($Text)) -Message $Message
}

function Set-TuiChoices {
    param([string[]]$Choices)
    $script:TuiChoiceQueue = New-Object System.Collections.Queue
    foreach ($choice in @($Choices)) { $script:TuiChoiceQueue.Enqueue([string]$choice) }
}

function Reset-TuiScenario {
    $script:TuiRenderedLines.Clear()
    $script:TuiScreenTitles.Clear()
    $script:TuiCommandInvocations.Clear()
    $script:TuiAzureReadQueries.Clear()
    $script:TuiChoicePrompts.Clear()
    $script:TuiSubscriptionSelections.Clear()
    $script:TuiChoiceQueue = New-Object System.Collections.Queue
    $script:TuiWaitCount = 0
    $script:TuiReadCount = 0
    $script:TuiNativeAzureCalls = 0
    $script:TuiRealDispatcherCalls = 0
    $script:TuiSubscriptionRefreshCount = 0
    $script:TuiVmDetailsCount = 0
    $script:TuiCreateWizardCount = 0
    $script:TuiPackageMenuCount = 0
    $script:TuiComponentMenuCount = 0
    $script:TuiOperationsMenuCount = 0
    $script:TuiTaskMenuCount = 0
    $script:TuiManagedGroupCallCount = 0
    $script:TuiLegacyMigrationCount = 0
    $script:TuiCloudRowsShouldThrow = $false
    $script:TuiPackageStatusShouldThrow = $false
    $script:TuiVmDiscoveryShouldThrow = $false
    $script:TuiDetailsShouldThrow = $false
    $script:TuiAzOverride = $null
    $script:TuiDiscoveryMode = $false
    $script:TuiDotEnvOverrides = @{}
    $script:TuiTaskCatalogByStage = @{
        init = @([pscustomobject]@{ TaskNumber = 1; Name = '01-fixture-init'; Enabled = $true; DisabledReason = '' })
        update = @([pscustomobject]@{ TaskNumber = 101; Name = '101-fixture-update'; Enabled = $false; DisabledReason = 'disabled catalog' })
    }
    $script:TuiWindowsVm = New-TuiVmFixture -Platform Windows
    $script:TuiLinuxVm = New-TuiVmFixture -Platform Linux
    $script:TuiVmDetailRecord = New-TuiVmDetailsFixture
    $script:TuiManagedGroups = @(
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1'; etag = 'fixture-group-etag'; name = 'rg-fixture-eastus-g1'; location = 'eastus'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' }; tags = [pscustomobject]@{ 'managed-by' = 'clagnos' } }
    )
    $script:TuiManagedGroupsByCall = @()
    $script:TuiVirtualComputers = @($script:TuiWindowsVm)
    $script:TuiDiscoveryVmRows = @($script:TuiWindowsVm)
    $script:TuiPackagesByCatalog = @{
        builtin = @(
            (New-TuiPackageFixture -Id 'builtin-fixture' -DisplayName 'Builtin Fixture' -Enabled $true -HasAppState $true -DependsOn @('base-tool')),
            (New-TuiPackageFixture -Id 'disabled-fixture' -DisplayName 'Disabled Fixture' -Enabled $false -HasAppState $false -DependsOn @())
        )
        custom = @(
            (New-TuiPackageFixture -Id 'custom-fixture' -DisplayName 'Custom Fixture' -Enabled $true -HasAppState $true -DependsOn @())
        )
    }
    $script:TuiPackageStatuses = @{ 'builtin-fixture' = 'installed'; 'disabled-fixture' = 'not-installed'; 'custom-fixture' = 'unknown' }
    $script:TuiCloudRows = @(
        [pscustomobject]@{ id = 'sub-fixture-enabled'; name = 'Fixture Enabled'; state = 'Enabled'; tenantId = 'tenant-fixture'; isDefault = $true },
        [pscustomobject]@{ id = 'sub-fixture-disabled'; name = 'Fixture Disabled'; state = 'Disabled'; tenantId = 'tenant-fixture'; isDefault = $false }
    )
    $script:TuiSelectedContext = [pscustomobject]@{ SubscriptionId = 'sub-fixture-enabled'; SubscriptionName = 'Fixture Enabled'; TenantId = 'tenant-fixture' }
    $script:TuiActiveSubscriptionId = 'sub-fixture-enabled'
    $script:ClagnosUiSubscription = [pscustomobject]@{ SubscriptionId = 'sub-fixture-enabled'; SubscriptionName = 'Fixture Enabled'; TenantId = 'tenant-fixture' }
    $script:ClagnosUiSubscriptionError = ''
    $script:ClagnosUiSubscriptionValidatedAtUtc = [DateTime]::UtcNow
    $script:ClagnosUiSelectedResourceGroup = 'rg-fixture-eastus-g1'
    $script:ClagnosUiSelectedVmName = 'fixture-vc'
    $script:ClagnosUiResourceCacheError = ''
    $script:ClagnosUiAzureReadCache = @{}
    $script:ClagnosUiInventoryValidationSeconds = 60
    $script:ClagnosUiReadCacheSeconds = 45
    $script:ClagnosUiInventoryCache = $null
    $fixtureResources = @(
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Compute/virtualMachines/fixture-vc'; etag = 'fixture-vm-etag'; name = 'fixture-vc'; type = 'Microsoft.Compute/virtualMachines'; resourceGroup = 'rg-fixture-eastus-g1'; location = 'eastus'; properties = [pscustomobject]@{ provisioningState = 'Succeeded' } },
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Compute/disks/disk-fixture-os'; etag = 'fixture-disk-etag'; name = 'disk-fixture-os'; type = 'Microsoft.Compute/disks'; resourceGroup = 'rg-fixture-eastus-g1'; location = 'eastus'; sku = [pscustomobject]@{ name = 'Premium_LRS' }; properties = [pscustomobject]@{ diskSizeGb = 128; encryption = [pscustomobject]@{ type = 'EncryptionAtRestWithPlatformKey' } } },
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/virtualNetworks/vnet-fixture'; etag = 'fixture-vnet-etag'; name = 'vnet-fixture'; type = 'Microsoft.Network/virtualNetworks'; resourceGroup = 'rg-fixture-eastus-g1'; location = 'eastus'; properties = [pscustomobject]@{ subnets = @([pscustomobject]@{ name = 'subnet-fixture'; id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/subnet-fixture' }) } },
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/networkInterfaces/nic-fixture'; etag = 'fixture-nic-etag'; name = 'nic-fixture'; type = 'Microsoft.Network/networkInterfaces'; resourceGroup = 'rg-fixture-eastus-g1'; location = 'eastus'; properties = [pscustomobject]@{ primary = $true; enableAcceleratedNetworking = $true; enableIPForwarding = $false; networkSecurityGroup = [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/networkSecurityGroups/nsg-fixture' }; ipConfigurations = @([pscustomobject]@{ name = 'ipconfig-primary'; privateIPAddress = '10.1.0.4'; privateIPAllocationMethod = 'Dynamic'; primary = $true; subnet = [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/subnet-fixture' }; publicIPAddress = [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/publicIPAddresses/pip-fixture' } }) } },
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/publicIPAddresses/pip-fixture'; etag = 'fixture-ip-etag'; name = 'pip-fixture'; type = 'Microsoft.Network/publicIPAddresses'; resourceGroup = 'rg-fixture-eastus-g1'; location = 'eastus'; sku = [pscustomobject]@{ name = 'Standard' }; zones = @('1'); properties = [pscustomobject]@{ ipAddress = '203.0.113.8'; publicIPAllocationMethod = 'Static'; dnsSettings = [pscustomobject]@{ fqdn = 'fixture.eastus.cloudapp.azure.com'; domainNameLabel = 'fixture' } } },
        [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/networkSecurityGroups/nsg-fixture'; etag = 'fixture-nsg-etag'; name = 'nsg-fixture'; type = 'Microsoft.Network/networkSecurityGroups'; resourceGroup = 'rg-fixture-eastus-g1'; location = 'eastus'; properties = [pscustomobject]@{ securityRules = @() } }
    )
    $script:ClagnosUiInventoryCache = @{
        SubscriptionId = 'sub-fixture-enabled'
        Groups = @($script:TuiManagedGroups)
        Resources = @($fixtureResources)
        VirtualMachines = @($script:TuiWindowsVm)
        Signature = 'tui-fixture-signature'
        LastValidatedAtUtc = [DateTime]::UtcNow
        IsDirty = $false
        DirtyReason = ''
        DirtyResourceGroup = ''
    }
    $script:TuiVmDetailRecord = New-TuiVmDetailsFixture
}

function Invoke-TuiTest {
    param([string]$Name, [scriptblock]$Action)
    Reset-TuiScenario
    try {
        . $Action
        Assert-Tui -Condition ($script:TuiChoiceQueue.Count -eq 0) -Message 'The screen did not consume the complete scripted interaction.'
        Assert-Tui -Condition ($script:TuiNativeAzureCalls -eq 0) -Message 'A TUI test attempted a native Azure CLI invocation.'
        Assert-Tui -Condition ($script:TuiRealDispatcherCalls -eq 0) -Message 'A TUI test reached the real command dispatcher.'
        $script:TuiTestResults.Add([pscustomobject]@{ Name = $Name; Passed = $true; Error = '' })
        [Console]::WriteLine(('[PASS] {0}' -f $Name))
    }
    catch {
        $errorText = [regex]::Replace([string]$_.Exception.Message, '\s+', ' ').Trim()
        $script:TuiTestResults.Add([pscustomobject]@{ Name = $Name; Passed = $false; Error = $errorText })
        [Console]::WriteLine(('[FAIL] {0}: {1}' -f $Name, $errorText))
        [Console]::WriteLine(('       reads={0}; queued={1}; screens={2}; commands={3}; output={4}' -f $script:TuiReadCount, $script:TuiChoiceQueue.Count, (@($script:TuiScreenTitles) -join '|'), (@($script:TuiCommandInvocations | ForEach-Object { [string]$_.CommandName }) -join ','), ((@($script:TuiRenderedLines | Select-Object -First 5)) -join '|')))
    }
}

function New-TuiVmFixture {
    param([ValidateSet('Windows','Linux')][string]$Platform = 'Windows')
    return [pscustomobject]@{
        id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Compute/virtualMachines/fixture-vc'
        etag = 'fixture-vm-etag'
        name = 'fixture-vc'
        location = 'eastus'
        ClagnosResourceGroup = 'rg-fixture-eastus-g1'
        ClagnosSubscriptionId = 'sub-fixture-enabled'
        storageProfile = [pscustomobject]@{
            osDisk = [pscustomobject]@{ osType = $Platform }
            dataDisks = @()
        }
        hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2as_v5' }
        publicIps = '203.0.113.8'
        privateIps = '10.1.0.4'
        fqdns = 'fixture.eastus.cloudapp.azure.com'
    }
}

function New-TuiPackageFixture {
    param(
        [string]$Id,
        [string]$DisplayName,
        [bool]$Enabled,
        [bool]$HasAppState,
        [string[]]$DependsOn = @()
    )
    $appState = if ($HasAppState) { [pscustomobject]@{ Version = 1 } } else { $null }
    return [pscustomobject]@{
        Id = $Id
        DisplayName = $DisplayName
        Enabled = $Enabled
        PackageTask = [pscustomobject]@{
            PackageSpec = [pscustomobject]@{ DependsOn = @($DependsOn) }
            AppStateSpec = $appState
        }
    }
}

function New-TuiVmDetailsFixture {
    return [pscustomobject]@{
        id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Compute/virtualMachines/fixture-vc'
        vmId = 'vm-id-fixture'
        location = 'eastus'
        provisioningState = 'Succeeded'
        osProfile = [pscustomobject]@{ computerName = 'FIXTURE-VC' }
        hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_D2as_v5' }
        storageProfile = [pscustomobject]@{
            osDisk = [pscustomobject]@{
                name = 'disk-fixture-os'
                osType = 'Windows'
                diskSizeGB = 128
                caching = 'ReadWrite'
                createOption = 'FromImage'
                deleteOption = 'Detach'
                managedDisk = [pscustomobject]@{ resourceGroup = 'rg-fixture-eastus-g1'; storageAccountType = 'Premium_LRS' }
            }
            dataDisks = @([pscustomobject]@{
                name = 'disk-fixture-data'
                diskSizeGB = 64
                caching = 'ReadOnly'
                createOption = 'Empty'
                deleteOption = 'Delete'
                lun = 0
                managedDisk = [pscustomobject]@{ resourceGroup = 'rg-fixture-eastus-g1'; storageAccountType = 'StandardSSD_LRS' }
            })
            imageReference = [pscustomobject]@{ publisher = 'FixturePublisher'; offer = 'FixtureOffer'; sku = 'FixtureSku'; version = 'latest'; exactVersion = '1.2.3'; id = '' }
        }
        additionalCapabilities = [pscustomobject]@{ hibernationEnabled = $true }
        securityProfile = [pscustomobject]@{
            securityType = 'TrustedLaunch'
            uefiSettings = [pscustomobject]@{ secureBootEnabled = $true; vTpmEnabled = $true }
        }
        diagnosticsProfile = [pscustomobject]@{ bootDiagnostics = [pscustomobject]@{ enabled = $true } }
        identity = [pscustomobject]@{ type = 'SystemAssigned' }
        zones = @('1')
        tags = [pscustomobject]@{ 'managed-by' = 'clagnos'; purpose = 'tui-fixture' }
        networkProfile = [pscustomobject]@{
            networkInterfaces = @([pscustomobject]@{
                id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/networkInterfaces/nic-fixture'
                resourceGroup = 'rg-fixture-eastus-g1'
                primary = $true
            })
        }
    }
}

function Initialize-TuiProductFunctions {
    $uiPath = Join-Path $RepoRoot 'scripts\clagnos-cli.ps1'
    $tokens = $null
    $parseErrors = $null
    $uiAst = [System.Management.Automation.Language.Parser]::ParseFile($uiPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) { throw ('Unable to read the TUI source: {0}' -f $parseErrors[0].Message) }

    $functionDefinitions = New-Object 'System.Collections.Generic.List[string]'
    foreach ($functionAst in @($uiAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))) {
        $functionText = [string]$functionAst.Extent.Text
        $functionTokens = $null
        $functionErrors = $null
        $functionAstCopy = [System.Management.Automation.Language.Parser]::ParseInput($functionText, [ref]$functionTokens, [ref]$functionErrors)
        $exitNodes = @($functionAstCopy.FindAll({ param($node) $node -is [System.Management.Automation.Language.ExitStatementAst] }, $true) | Sort-Object { $_.Extent.StartOffset } -Descending)
        foreach ($exitNode in @($exitNodes)) {
            $start = [int]$exitNode.Extent.StartOffset
            $length = [int]($exitNode.Extent.EndOffset - $start)
            $functionText = $functionText.Substring(0, $start) + 'return' + $functionText.Substring($start + $length)
        }
        $functionDefinitions.Add($functionText)
    }
    return @($functionDefinitions)
}

$null = . (Join-Path $RepoRoot 'clagnos.ps1')
$script:ClagnosUiRepoRoot = $RepoRoot
$script:ClagnosUiBackendPath = Join-Path $RepoRoot 'clagnos.ps1'
$script:ClagnosUiSubscription = $null
$script:ClagnosUiSubscriptionError = ''
$script:TuiWindowsVm = New-TuiVmFixture -Platform Windows
$script:TuiLinuxVm = New-TuiVmFixture -Platform Linux
$script:TuiVmDetailRecord = New-TuiVmDetailsFixture
foreach ($tuiFunctionDefinition in @(Initialize-TuiProductFunctions)) {
    . ([scriptblock]::Create([string]$tuiFunctionDefinition))
}
$script:TuiOriginalVmDiscovery = (Get-Command Get-ClagnosUiVirtualComputers).ScriptBlock
$script:TuiOriginalInventorySync = (Get-Command Sync-ClagnosUiResourceCache).ScriptBlock
$script:TuiOriginalCreateWizard = (Get-Command Show-ClagnosUiCreateWizard).ScriptBlock
$script:TuiOriginalVmDetails = (Get-Command Show-ClagnosUiVmDetails).ScriptBlock
$script:TuiOriginalHeader = (Get-Command Write-ClagnosUiHeader).ScriptBlock
$script:TuiOriginalPackageMenu = (Get-Command Show-ClagnosUiPackageMenu).ScriptBlock
$script:TuiOriginalPackageCatalogMenu = (Get-Command Show-ClagnosUiPackageCatalogMenu).ScriptBlock
$script:TuiOriginalPackageAppStateMenu = (Get-Command Show-ClagnosUiPackageAppStateMenu).ScriptBlock
$script:TuiOriginalComponentMenu = (Get-Command Show-ClagnosUiComponentMenu).ScriptBlock
$script:TuiOriginalTaskAvailabilityMenu = (Get-Command Show-ClagnosUiTaskAvailabilityMenu).ScriptBlock
$script:TuiOriginalTaskMenu = (Get-Command Show-ClagnosUiTaskMenu).ScriptBlock
$script:TuiOriginalOperationsMenu = (Get-Command Show-ClagnosUiOperationsMenu).ScriptBlock

# The command dispatcher and Azure CLI are deliberately blocked for every test.
function az { $script:TuiNativeAzureCalls++; $script:TuiTotalNativeAzureCalls++; throw 'Native Azure CLI is blocked in TUI tests.' }
function Invoke-ClagnosCommandDispatcher {
    param([string]$CommandName, [hashtable]$Options, [string]$HelpTopic = '', [hashtable]$FrontendContext = @{})
    $script:TuiRealDispatcherCalls++
    $script:TuiTotalRealDispatcherCalls++
    throw 'The real command dispatcher is blocked in TUI tests.'
}

function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true)][object]$Object,
        [string]$Separator = ' ',
        [switch]$NoNewline,
        [System.ConsoleColor]$ForegroundColor,
        [System.ConsoleColor]$BackgroundColor
    )
    process {
        $line = if ($null -eq $Object) { '' } else { (@($Object) | ForEach-Object { [string]$_ }) -join $Separator }
        $script:TuiRenderedLines.Add([string]$line)
    }
}

function Read-ClagnosUiChoice {
    param([string]$Prompt = 'Select an option')
    $script:TuiReadCount++
    $script:TuiChoicePrompts.Add([string]$Prompt)
    if ($script:TuiChoiceQueue.Count -eq 0) { throw ('Unexpected prompt with no scripted response: {0}' -f $Prompt) }
    return [string]$script:TuiChoiceQueue.Dequeue()
}

function Write-ClagnosUiHeader {
    param([string]$Title = 'Clagnos')
    $script:TuiScreenTitles.Add([string]$Title)
    $script:TuiRenderedLines.Add(('[SCREEN] {0}' -f $Title))
}

function Clear-Host { }

function Wait-ClagnosUiContinue { $script:TuiWaitCount++ }
function Write-ClagnosUiError { param([object]$ErrorRecord) $script:TuiRenderedLines.Add(('[ERROR] {0}' -f [string]$ErrorRecord.Exception.Message)) }
function Update-ClagnosUiSubscription { $script:TuiSubscriptionRefreshCount++ }

function Invoke-ClagnosUiCommand {
    param([string]$CommandName, [hashtable]$Options = @{}, [hashtable]$FrontendContext = @{})
    $copy = @{}
    foreach ($key in @($Options.Keys)) { $copy[[string]$key] = $Options[$key] }
    $script:TuiCommandInvocations.Add([pscustomobject]@{ CommandName = $CommandName; Options = $copy; FrontendContext = $FrontendContext })
}

function Invoke-ClagnosUiAzJson {
    param([string[]]$Arguments, [switch]$ForceRefresh, [int]$CacheTtlSeconds = 45)
    if ($null -ne $script:TuiAzOverride) { return (& $script:TuiAzOverride -Arguments $Arguments) }
    $query = @($Arguments) -join ' '
    $script:TuiAzureReadQueries.Add($query)
    if ($query -like 'vm show *') { return $script:TuiVmDetailRecord }
    if ($query -like 'vm list-ip-addresses *') {
        return @([pscustomobject]@{ virtualMachine = [pscustomobject]@{ name = 'fixture-vc'; network = [pscustomobject]@{
            privateIpAddresses = @('10.1.0.4')
            publicIpAddresses = @([pscustomobject]@{ name = 'pip-fixture'; resourceGroup = 'rg-fixture-eastus-g1'; ipAddress = '203.0.113.8'; ipAllocationMethod = 'Static' })
        } } })
    }
    if ($query -like 'network public-ip show *') {
        return [pscustomobject]@{ ipAddress = '203.0.113.8'; dnsSettings = [pscustomobject]@{ fqdn = 'fixture.eastus.cloudapp.azure.com'; domainNameLabel = 'fixture' }; publicIPAllocationMethod = 'Static'; sku = [pscustomobject]@{ name = 'Standard' }; zones = @('1') }
    }
    if ($query -like 'disk show *') {
        $diskName = [string]$Arguments[(@($Arguments).IndexOf('--name') + 1)]
        return [pscustomobject]@{ name = $diskName; diskSizeGb = 128; sku = [pscustomobject]@{ name = 'Premium_LRS' }; encryption = [pscustomobject]@{ type = 'EncryptionAtRestWithPlatformKey' } }
    }
    if ($query -like 'network nic show *') {
        return [pscustomobject]@{
            name = 'nic-fixture'; primary = $true; enableAcceleratedNetworking = $true; enableIPForwarding = $false
            networkSecurityGroup = [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/networkSecurityGroups/nsg-fixture' }
            ipConfigurations = @([pscustomobject]@{
                name = 'ipconfig-primary'; privateIPAddress = '10.1.0.4'; privateIPAllocationMethod = 'Dynamic'; primary = $true
                subnet = [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/virtualNetworks/vnet-fixture/subnets/subnet-fixture' }
                publicIPAddress = [pscustomobject]@{ id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-fixture-eastus-g1/providers/Microsoft.Network/publicIPAddresses/pip-fixture' }
            })
        }
    }
    if ($query -like 'resource list *') {
        return @(
            [pscustomobject]@{ type = 'Microsoft.Compute/virtualMachines'; name = 'fixture-vc'; location = 'eastus' },
            [pscustomobject]@{ type = 'Microsoft.Compute/disks'; name = 'disk-fixture-os'; location = 'eastus' },
            [pscustomobject]@{ type = 'Microsoft.Network/publicIPAddresses'; name = 'pip-fixture'; location = 'eastus' }
        )
    }
    if ($query -like 'vm list *') { return @($script:TuiDiscoveryVmRows) }
    throw ('Unexpected simulated Azure read query: {0}' -f $query)
}

function Read-DotEnvFile {
    param([string]$Path)
    $config = @{
        VM_ADMIN_USER = 'manager-fixture'
        VM_ADMIN_PASS = '<runtime-secret>'
        VM_ASSISTANT_USER = 'assistant-fixture'
        VM_ASSISTANT_PASS = '<runtime-secret>'
        VM_SSH_PORT = '22222'
        VM_RDP_PORT = '3390'
        VM_ENABLE_NESTED_VIRTUALIZATION = 'true'
    }
    if ($null -ne $script:TuiDotEnvOverrides) {
        foreach ($key in $script:TuiDotEnvOverrides.Keys) { $config[[string]$key] = [string]$script:TuiDotEnvOverrides[$key] }
    }
    return $config
}

function Get-ClagnosUiVmSizeFacts { param([string]$Location, [string]$Size) return [pscustomobject]@{ Cores = '2'; MemoryMb = '8192' } }
function Get-AzLocationCatalog {
    return @(
        [pscustomobject]@{ Name = 'eastus'; DisplayName = 'East US' }
        [pscustomobject]@{ Name = 'westus'; DisplayName = 'West US' }
    )
}
function Get-LocationSkusForSelection {
    param([string]$Location, [string]$SkuLike = '')
    $rows = @(
        [pscustomobject]@{ name = 'Standard_B2s_v2'; numberOfCores = 2; memoryInMb = 8192 }
        [pscustomobject]@{ name = 'Standard_B2as_v2'; numberOfCores = 2; memoryInMb = 8192 }
        [pscustomobject]@{ name = 'Standard_B4as_v2'; numberOfCores = 4; memoryInMb = 16384 }
        [pscustomobject]@{ name = 'Standard_D2as_v5'; numberOfCores = 2; memoryInMb = 8192 }
        [pscustomobject]@{ name = 'Standard_D4as_v5'; numberOfCores = 4; memoryInMb = 16384 }
        [pscustomobject]@{ name = 'Standard_E2as_v5'; numberOfCores = 2; memoryInMb = 16384 }
        [pscustomobject]@{ name = 'Standard_E4as_v5'; numberOfCores = 4; memoryInMb = 32768 }
        [pscustomobject]@{ name = 'Standard_F2s_v2'; numberOfCores = 2; memoryInMb = 4096 }
        [pscustomobject]@{ name = 'Standard_F4s_v2'; numberOfCores = 4; memoryInMb = 8192 }
        [pscustomobject]@{ name = 'Standard_A2_v2'; numberOfCores = 2; memoryInMb = 4096 }
        [pscustomobject]@{ name = 'Standard_A4_v2'; numberOfCores = 4; memoryInMb = 8192 }
        [pscustomobject]@{ name = 'Standard_D2s_v5'; numberOfCores = 2; memoryInMb = 8192 }
        [pscustomobject]@{ name = 'Standard_D4s_v5'; numberOfCores = 4; memoryInMb = 16384 }
    )
    if ([string]::IsNullOrWhiteSpace([string]$SkuLike)) { return $rows }
    return @($rows | Where-Object { [string]$_.name -like (Convert-ToSkuSearchPattern -FilterText $SkuLike) })
}
function Get-SkuAvailabilityMap {
    param([string]$Location, [string[]]$SkuNames)
    $result = @{}
    foreach ($sku in @($SkuNames)) { $result[[string]$sku] = 'yes' }
    return $result
}
function Get-ClagnosUiPowerState { param([string]$ResourceGroup, [string]$VmName) return 'VM running' }
function Show-ClagnosUiVmDetails {
    param([psobject]$Vm)
    $script:TuiVmDetailsCount++
    if ($script:TuiDetailsShouldThrow) { throw 'fixture VC detail read error' }
}
function Show-ClagnosUiCreateWizard { $script:TuiCreateWizardCount++ }
function Show-ClagnosUiPackageMenu { param([psobject]$Vm) $script:TuiPackageMenuCount++ }
function Show-ClagnosUiComponentMenu { param([psobject]$Vm) $script:TuiComponentMenuCount++ }
function Show-ClagnosUiOperationsMenu { param([psobject]$Vm) $script:TuiOperationsMenuCount++ }
function Show-ClagnosUiTaskMenu { param([psobject]$Vm) $script:TuiTaskMenuCount++ }
function Get-ClagnosUiVirtualComputers {
    if ($script:TuiVmDiscoveryShouldThrow) { throw 'fixture VM inventory error' }
    if ($script:TuiDiscoveryMode) { return @(& $script:TuiOriginalVmDiscovery) }
    return @($script:TuiVirtualComputers)
}
function Get-ClagnosUiManagedGroups {
    param([switch]$IncludeLegacy)
    $script:TuiManagedGroupCallCount++
    $sequenceIndex = $script:TuiManagedGroupCallCount - 1
    if ($sequenceIndex -lt $script:TuiManagedGroupsByCall.Count) { return @($script:TuiManagedGroupsByCall[$sequenceIndex]) }
    return @($script:TuiManagedGroups)
}
function Invoke-ClagnosUiLegacyTagMigration { param([object[]]$LegacyGroups) $script:TuiLegacyMigrationCount++ }
function Get-ClagnosUiCloudSubscriptionRows { if ($script:TuiCloudRowsShouldThrow) { throw 'fixture subscription inventory error' }; return @($script:TuiCloudRows) }
function Get-ClagnosUiAzureCliActiveSubscriptionId { return [string]$script:TuiActiveSubscriptionId }
function Get-ClagnosResolvedSubscriptionContext { return $script:TuiSelectedContext }
function Set-ClagnosUiActiveSubscription {
    param([psobject]$Subscription)
    $script:TuiSubscriptionSelections.Add([string]$Subscription.id)
    $script:TuiSelectedContext = [pscustomobject]@{ SubscriptionId = [string]$Subscription.id; SubscriptionName = [string]$Subscription.name; TenantId = [string]$Subscription.tenantId }
    $script:ClagnosUiSubscription = [pscustomobject]@{ SubscriptionId = [string]$Subscription.id; SubscriptionName = [string]$Subscription.name; TenantId = [string]$Subscription.tenantId }
}
function Get-ClagnosPackageCatalog { param([string]$Platform, [ValidateSet('builtin','custom')][string]$Catalog) return @($script:TuiPackagesByCatalog[$Catalog]) }
function Get-ClagnosPackageStatusSnapshot { param([object[]]$Packages, [hashtable]$Options, [string]$Platform) if ($script:TuiPackageStatusShouldThrow) { throw 'fixture package status unavailable' }; return $script:TuiPackageStatuses }
function Initialize-ClagnosTaskCommandRuntimeContext { param([switch]$AutoMode, [switch]$WindowsFlag, [switch]$LinuxFlag) return [pscustomobject]@{ VmInitTaskDir = 'fixture\init'; VmUpdateTaskDir = 'fixture\update' } }
function Get-ClagnosTaskBlocksFromDirectory {
    param([string]$DirectoryPath, [ValidateSet('windows','linux')][string]$Platform, [ValidateSet('init','update')][string]$Stage, [switch]$SuppressSkipMessages)
    return [pscustomobject]@{ InventoryTasks = @($script:TuiTaskCatalogByStage[$Stage]) }
}
function Select-AzLocationInteractive { param([string]$DefaultLocation) return 'westus2' }

function Assert-TuiCommand {
    param([string]$CommandName, [int]$Count = 1)
    $calls = @($script:TuiCommandInvocations | Where-Object { [string]::Equals([string]$_.CommandName, $CommandName, [System.StringComparison]::OrdinalIgnoreCase) })
    Assert-Tui -Condition ($calls.Count -eq $Count) -Message ("Expected {0} '{1}' UI dispatch(es), found {2}." -f $Count, $CommandName, $calls.Count)
    if ($Count -eq 1) { return $calls[0] }
    return $calls
}

function Assert-TuiOption {
    param([psobject]$Call, [string]$Name, [object]$Expected)
    Assert-Tui -Condition ($Call.Options.ContainsKey($Name)) -Message ("Expected option '{0}' on '{1}'." -f $Name, [string]$Call.CommandName)
    Assert-Tui -Condition ([string]$Call.Options[$Name] -eq [string]$Expected) -Message ("Option '{0}' expected '{1}', found '{2}'." -f $Name, $Expected, $Call.Options[$Name])
}

function Assert-TuiNoRealCloudCalls {
    Assert-Tui -Condition ($script:TuiNativeAzureCalls -eq 0) -Message 'No test may invoke the native Azure CLI.'
    Assert-Tui -Condition ($script:TuiRealDispatcherCalls -eq 0) -Message 'No test may invoke the real command dispatcher.'
}

Reset-TuiScenario

Invoke-TuiTest -Name 'Launcher points cg.cmd to the interactive Clagnos CLI' -Action {
    $launcher = [string](Get-Content -LiteralPath (Join-Path $RepoRoot 'cg.cmd') -Raw)
    Assert-Tui -Condition ($launcher -match '(?i)scripts[\\/]clagnos-cli\.ps1') -Message 'cg.cmd must launch scripts/clagnos-cli.ps1.'
    Assert-Tui -Condition ($launcher -match '(?i)%\*|\$args|CliTokens') -Message 'cg.cmd must forward command-line arguments to the launcher target.'
}

Invoke-TuiTest -Name 'TUI header shows the Clagnos tagline and selected subscription details' -Action {
    & $script:TuiOriginalHeader -Title 'Header fixture screen'
    Assert-TuiOutputContains -Text 'one tool for all common cloud operations' -Message 'The shared TUI header must render the product tagline.'
    Assert-TuiOutputContains -Text 'Azure subscription: Fixture Enabled (sub-fixture-enabled)' -Message 'The header must identify the selected subscription.'
    Assert-TuiOutputContains -Text 'Header fixture screen' -Message 'The header must show the requested screen title.'
}

Invoke-TuiTest -Name 'TUI header shows sign-in guidance when no subscription is available' -Action {
    $script:ClagnosUiSubscription = $null
    & $script:TuiOriginalHeader -Title 'Offline fixture screen'
    Assert-TuiOutputContains -Text 'Azure subscription: not signed in' -Message 'An offline TUI must identify the missing subscription context.'
}

Invoke-TuiTest -Name 'Main menu routes every visible item and exits on q' -Action {
    Set-TuiChoices -Choices @('1','b','2','b','3','b','c','h','q')
    Show-ClagnosUiHome
    Assert-TuiOutputContains -Text 'Main menu' -Message 'Main menu heading must render.'
    Assert-TuiOutputContains -Text '1. Virtual computers' -Message 'Main menu must show virtual computers.'
    Assert-TuiOutputContains -Text '2. Managed resource inventory' -Message 'Main menu must show resource inventory.'
    Assert-TuiOutputContains -Text '3. Cloud subscriptions' -Message 'Main menu must show cloud subscriptions.'
    Assert-TuiCommand -CommandName 'configure' | Out-Null
    Assert-TuiCommand -CommandName 'help' | Out-Null
    Assert-Tui -Condition ($script:TuiSubscriptionRefreshCount -ge 1) -Message 'Home navigation must refresh subscription context before rendering.'
}

Invoke-TuiTest -Name 'Paged numbered picker supports every page key and keeps selection on the visible page' -Action {
    $options = @(1..25 | ForEach-Object { [pscustomobject]@{ Value = [string]$_; Label = ('option-{0}' -f $_) } })
    Set-TuiChoices -Choices @('p','n','g','3','f','t','p','13')
    $selection = Select-ClagnosNumberedOptionPage -Options $options -Prompt 'Fixture choices' -DefaultValue '13' -PageSize 12
    Assert-Tui -Condition ([string]$selection.Value -eq '13') -Message 'The picker must return the selected option after navigating with p/n/g/f/t.'
    Assert-TuiOutputContains -Text 'Page 2/3' -Message 'The default option must open on its page and show the current page.'
    Assert-TuiOutputContains -Text 'p: previous page | n: next page | g: go to page | f: first page | t: last page' -Message 'Multi-page pickers must show all page controls.'

    Reset-TuiScenario
    $options = @(1..25 | ForEach-Object { [pscustomobject]@{ Value = [string]$_; Label = ('option-{0}' -f $_) } })
    Set-TuiChoices -Choices @('p','','n','')
    $selection = Select-ClagnosNumberedOptionPage -Options $options -Prompt 'Visible default choices' -DefaultValue '13' -PageSize 12
    Assert-Tui -Condition ([string]$selection.Value -eq '13') -Message 'A default must only be selected when its marked row is visible on the current page.'
    Assert-TuiOutputContains -Text 'The default is on page 2' -Message 'A blank input away from the default page must guide the operator to it.'

    Reset-TuiScenario
    $options = @(1..14 | ForEach-Object { [pscustomobject]@{ Value = [string]$_; Label = ('option-{0}' -f $_) } })
    Set-TuiChoices -Choices @('13','n','13')
    $selection = Select-ClagnosNumberedOptionPage -Options $options -Prompt 'Visible page choices' -PageSize 12
    Assert-Tui -Condition ([string]$selection.Value -eq '13') -Message 'An option on another page must become selectable after navigating to its page.'
    Assert-TuiOutputContains -Text 'Choose a number shown on the current page' -Message 'The picker must reject numbers that are not visible on the current page.'
}

Invoke-TuiTest -Name 'Managed inventory cache syncs once, reuses unchanged state, and detects resource changes' -Action {
    $script:TuiCacheFixtureCalls = 0
    $script:TuiCacheGroup = [pscustomobject]@{
        id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-cache-fixture'
        name = 'rg-cache-fixture'; etag = 'group-etag-1'; location = 'eastus'
        properties = [pscustomobject]@{ provisioningState = 'Succeeded' }
        tags = [pscustomobject]@{ 'managed-by' = 'clagnos' }
    }
    $script:TuiCacheResource = [pscustomobject]@{
        id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-cache-fixture/providers/Microsoft.Compute/disks/disk-cache'
        etag = 'disk-etag-1'; name = 'disk-cache'; type = 'Microsoft.Compute/disks'; resourceGroup = 'rg-cache-fixture'
        location = 'eastus'; properties = [pscustomobject]@{ diskSizeGb = 64 }
    }
    $script:TuiCacheVm = [pscustomobject]@{
        id = '/subscriptions/sub-fixture-enabled/resourceGroups/rg-cache-fixture/providers/Microsoft.Compute/virtualMachines/cache-vm'
        etag = 'vm-etag-1'; name = 'cache-vm'; resourceGroup = 'rg-cache-fixture'; powerState = 'VM running'; provisioningState = 'Succeeded'
        hardwareProfile = [pscustomobject]@{ vmSize = 'Standard_B2s_v2' }; privateIps = '10.0.0.4'; publicIps = '203.0.113.4'; fqdns = 'cache.example.invalid'
        storageProfile = [pscustomobject]@{ osDisk = [pscustomobject]@{ osType = 'Linux' } }
    }
    $script:TuiAzOverride = {
        param([string[]]$Arguments)
        $script:TuiCacheFixtureCalls++
        $query = @($Arguments) -join ' '
        if ($query -eq 'group list') { return @($script:TuiCacheGroup) }
        if ($query -like 'resource list --resource-group *') { return @($script:TuiCacheResource) }
        if ($query -eq 'vm list --show-details') { return @($script:TuiCacheVm) }
        throw ('Unexpected cache fixture query: {0}' -f $query)
    }
    $script:ClagnosUiInventoryCache = $null
    $first = & $script:TuiOriginalInventorySync -Force
    Assert-Tui -Condition ($script:TuiCacheFixtureCalls -eq 3) -Message 'Initial sync must query groups, resources for the managed group, and VM detail rows once each.'
    Assert-Tui -Condition (@($first.Groups).Count -eq 1 -and @($first.Resources).Count -eq 1 -and @($first.VirtualMachines).Count -eq 1) -Message 'The initial snapshot must retain every managed inventory layer.'

    $before = $script:TuiCacheFixtureCalls
    Ensure-ClagnosUiResourceCache | Out-Null
    Assert-Tui -Condition ($script:TuiCacheFixtureCalls -eq $before) -Message 'A fresh cache must serve screens without repeat Azure reads.'
    $same = & $script:TuiOriginalInventorySync -Force
    Assert-Tui -Condition ([object]::ReferenceEquals($first, $same)) -Message 'An unchanged forced validation must preserve the existing snapshot object.'
    Assert-Tui -Condition (-not [bool]$same.Changed) -Message 'An unchanged validation must clear its change marker.'

    $script:TuiCacheResource.etag = 'disk-etag-2'
    $changed = & $script:TuiOriginalInventorySync -Force
    Assert-Tui -Condition ([bool]$changed.Changed -and $changed.Signature -ne $first.Signature) -Message 'An Azure resource ETag change must invalidate the snapshot signature.'
    $before = $script:TuiCacheFixtureCalls
    Invalidate-ClagnosUiResourceCache -Reason 'fixture mutation' -ResourceGroup 'rg-cache-fixture'
    Ensure-ClagnosUiResourceCache | Out-Null
    Assert-Tui -Condition ($script:TuiCacheFixtureCalls -eq ($before + 3)) -Message 'A mutation must trigger exactly one full reconciliation before the next cache read.'
    Assert-Tui -Condition (-not [bool]$script:ClagnosUiInventoryCache.IsDirty) -Message 'A successful reconciliation must clear the dirty marker.'
}

Invoke-TuiTest -Name 'Persisted inventory refresh requests remain dirty until a newer cache snapshot is published' -Action {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('clagnos-persisted-inventory-' + [guid]::NewGuid().ToString('N'))
    $previousCacheRoot = [string]$env:CLAGNOS_TUI_CACHE_ROOT
    $previousSnapshot = $script:ClagnosUiInventoryCache
    $previousCachePath = [string]$script:ClagnosUiInventoryCacheFilePath
    $previousCacheWriteUtc = if ($null -ne $script:ClagnosUiInventoryCacheFileLastWriteUtc) { [DateTime]$script:ClagnosUiInventoryCacheFileLastWriteUtc } else { [DateTime]::MinValue }
    $previousMaximumStaleSeconds = if ($null -ne $script:ClagnosUiInventoryMaximumStaleSeconds) { [int]$script:ClagnosUiInventoryMaximumStaleSeconds } else { 300 }
    $previousSubscription = $script:ClagnosUiSubscription
    try {
        $env:CLAGNOS_TUI_CACHE_ROOT = $tempRoot
        $script:ClagnosUiInventoryMaximumStaleSeconds = 300
        $script:ClagnosUiSubscription = [pscustomobject]@{ SubscriptionId = 'sub-fixture-enabled'; SubscriptionName = 'Fixture Enabled' }
        $script:ClagnosUiInventoryCache = $null
        $script:ClagnosUiInventoryCacheFilePath = ''
        $paths = Get-ClagnosUiInventoryCachePaths -SubscriptionId 'sub-fixture-enabled'
        New-Item -ItemType Directory -Path $paths.Root -Force | Out-Null
        $validatedAt = [DateTime]::UtcNow.AddSeconds(-5)
        $snapshot = [ordered]@{ SubscriptionId = 'sub-fixture-enabled'; Groups = @(); Resources = @(); VirtualMachines = @(); Signature = 'fixture-signature'; LastValidatedAtUtc = $validatedAt.ToString('o'); IsDirty = $false; DirtyReason = ''; DirtyResourceGroup = ''; Changed = $false }
        Set-Content -LiteralPath $paths.Cache -Value (ConvertTo-Json -InputObject $snapshot -Depth 8 -Compress) -Encoding UTF8
        Set-Content -LiteralPath $paths.Request -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ASCII

        $pending = Import-ClagnosUiInventoryCacheFromDisk -Force
        $diagnosticSnapshot = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $paths.Cache -Raw))
        Assert-Tui -Condition ($null -ne $pending -and [bool]$pending.IsDirty -and [string]$pending.DirtyReason -eq 'a persisted inventory refresh is pending') -Message ('A cache written before a persisted refresh request must not be trusted as current after a CLI restart. Null={0}; ImportedSubscription={1}; ConfiguredSubscription={2}; Validated={3}; Request={4}; FileExists={5}; Error={6}' -f ($null -eq $pending),[string]$diagnosticSnapshot.SubscriptionId,[string]$script:ClagnosUiSubscription.SubscriptionId,[string]$diagnosticSnapshot.LastValidatedAtUtc,[string](Get-Content -LiteralPath $paths.Request -Raw),(Test-Path -LiteralPath $paths.Cache),[string]$script:ClagnosUiResourceCacheError)

        $snapshot.LastValidatedAtUtc = [DateTime]::UtcNow.AddSeconds(2).ToString('o')
        Set-Content -LiteralPath $paths.Cache -Value (ConvertTo-Json -InputObject $snapshot -Depth 8 -Compress) -Encoding UTF8
        $revalidated = Import-ClagnosUiInventoryCacheFromDisk -Force
        Assert-Tui -Condition ($null -ne $revalidated -and -not [bool]$revalidated.IsDirty) -Message 'A worker snapshot newer than the persisted refresh request must clear the dirty marker.'
    }
    finally {
        $script:ClagnosUiInventoryCache = $previousSnapshot
        $script:ClagnosUiInventoryCacheFilePath = $previousCachePath
        $script:ClagnosUiInventoryCacheFileLastWriteUtc = $previousCacheWriteUtc
        $script:ClagnosUiInventoryMaximumStaleSeconds = $previousMaximumStaleSeconds
        $script:ClagnosUiSubscription = $previousSubscription
        if ([string]::IsNullOrWhiteSpace($previousCacheRoot)) { Remove-Item Env:\CLAGNOS_TUI_CACHE_ROOT -ErrorAction SilentlyContinue }
        else { $env:CLAGNOS_TUI_CACHE_ROOT = $previousCacheRoot }
        $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
        $tempPrefix = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('\','/')) + [System.IO.Path]::DirectorySeparatorChar
        if ($resolvedTemp.StartsWith($tempPrefix,[System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedTemp)) { Remove-Item -LiteralPath $resolvedTemp -Recurse -Force }
    }
}

Invoke-TuiTest -Name 'Create wizard applies validated defaults through the real TUI create route' -Action {
    $script:TuiDotEnvOverrides = @{
        SELECTED_VM_OS = 'windows'; SELECTED_VM_NAME = 'fixture-new-vc'; SELECTED_AZURE_REGION = 'eastus'
        WIN_VM_SIZE = 'Standard_B2s_v2'; WIN_VM_IMAGE = 'MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest'; WIN_VM_DISK_SIZE_GB = '128GB'
        VM_STORAGE_SKU = 'StandardSSD_LRS'; VM_SECURITY_TYPE = 'Standard'; VM_ENABLE_HIBERNATION = 'true'; VM_ENABLE_NESTED_VIRTUALIZATION = 'true'
        VM_SSH_PORT = '22222'; VM_RDP_PORT = '3390'; TCP_PORTS = '80,3000-3300'
    }
    Set-TuiChoices -Choices @('a','a','a','a','a','a','a','a','a','a','a','a','a','a')
    & $script:TuiOriginalCreateWizard
    $call = Assert-TuiCommand -CommandName 'create'
    Assert-TuiOption -Call $call -Name 'windows' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-new-vc'
    Assert-TuiOption -Call $call -Name 'vm-region' -Expected 'eastus'
    Assert-TuiOption -Call $call -Name 'vm-size' -Expected 'Standard_B2s_v2'
    Assert-Tui -Condition ([bool]$call.FrontendContext.CreateWizardMode) -Message 'The create route must carry wizard mode to the shared runtime.'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.DiskSizeGb -eq '128') -Message 'The wizard must normalize disk text to whole GiB before dispatch.'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.SshPort -eq '22222' -and [string]$call.FrontendContext.CreateWizardValues.RdpPort -eq '3390') -Message 'The wizard must dispatch validated connection ports.'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.TcpPorts -match '3000-3300') -Message 'The wizard must preserve a validated TCP range in the dispatch context.'
    Assert-TuiOutputContains -Text '>1. Windows' -Message 'The OS step must show the configured default with a greater-than marker.'
    Assert-TuiOutputContains -Text 'p: previous page | n: next page | g: go to page | f: first page | t: last page' -Message 'The SKU step must expose paging when the region has more than one page.'
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Create wizard skip-all and apply-all controls use validated defaults' -Action {
    $script:TuiDotEnvOverrides = @{
        SELECTED_VM_OS = 'windows'; SELECTED_VM_NAME = 'fixture-default-vc'; SELECTED_AZURE_REGION = 'eastus'
        WIN_VM_SIZE = 'Standard_B2s_v2'; WIN_VM_IMAGE = 'MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest'; WIN_VM_DISK_SIZE_GB = '128GB'
        VM_STORAGE_SKU = 'StandardSSD_LRS'; VM_SECURITY_TYPE = 'Standard'; VM_ENABLE_HIBERNATION = 'true'; VM_ENABLE_NESTED_VIRTUALIZATION = 'true'
        VM_SSH_PORT = '22222'; VM_RDP_PORT = '3390'; TCP_PORTS = '80,3000-3300'
    }
    Set-TuiChoices -Choices @('k','l')
    & $script:TuiOriginalCreateWizard
    $call = Assert-TuiCommand -CommandName 'create'
    Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-default-vc'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.DiskSizeGb -eq '128') -Message 'Skipping remaining steps must retain and validate the configured disk default.'
    Assert-TuiOutputContains -Text 'Create wizard — review' -Message 'Apply-all must lead to a complete review before create dispatch.'
}

Invoke-TuiTest -Name 'Create wizard s and c controls keep a default then close without dispatch' -Action {
    $script:TuiDotEnvOverrides = @{ SELECTED_VM_OS = 'windows' }
    Set-TuiChoices -Choices @('s','c')
    & $script:TuiOriginalCreateWizard
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Closing the create wizard must never dispatch create.'
    Assert-TuiOutputContains -Text 's: skip | k: skip all remaining | a: apply default | l: apply all defaults | c: close wizard' -Message 'Each option step must show the wizard controls.'
}

Invoke-TuiTest -Name 'Create wizard recovers from invalid configured security and boolean defaults' -Action {
    $script:TuiDotEnvOverrides = @{
        SELECTED_VM_OS = 'windows'; SELECTED_VM_NAME = 'recover-vc'; SELECTED_AZURE_REGION = 'eastus'
        WIN_VM_SIZE = 'Standard_B2s_v2'; WIN_VM_IMAGE = 'MicrosoftWindowsDesktop:windows-11:win11-24h2-pro:latest'; WIN_VM_DISK_SIZE_GB = '128GB'
        VM_STORAGE_SKU = 'StandardSSD_LRS'; VM_SECURITY_TYPE = 'not-a-security-type'; VM_ENABLE_HIBERNATION = 'maybe'
        VM_ENABLE_NESTED_VIRTUALIZATION = 'maybe'; VM_SSH_PORT = '22222'; VM_RDP_PORT = '3390'; TCP_PORTS = '80,3000-3300'
    }
    Set-TuiChoices -Choices @('a','a','a','a','a','a','1','2','1','a','a','a','a','a')
    & $script:TuiOriginalCreateWizard
    $call = Assert-TuiCommand -CommandName 'create'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.SecurityType -eq 'Standard') -Message 'The invalid security default must be replaced by a numbered choice.'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.Hibernation -eq 'false') -Message 'The invalid hibernation default must be replaced by a numbered choice.'
    Assert-Tui -Condition ([string]$call.FrontendContext.CreateWizardValues.NestedVirtualization -eq 'true') -Message 'The invalid nested virtualization default must be replaced by a numbered choice.'
    Assert-TuiOutputContains -Text 'Configured VM_SECURITY_TYPE is invalid' -Message 'Invalid security defaults must be explained without aborting the wizard.'
    Assert-TuiOutputContains -Text 'Configured default for VM_ENABLE_HIBERNATION is invalid' -Message 'Invalid feature defaults must be explained without aborting the wizard.'
}

Invoke-TuiTest -Name 'Wizard text fields warn and reprompt after invalid numeric input' -Action {
    Set-TuiChoices -Choices @('70000','22222')
    $value = Read-ClagnosUiWizardTextStep -Title 'Fixture SSH port' -DefaultValue '22' -Required -Validator {
        param($candidate)
        return (Resolve-ClagnosTcpPortNumber -Value ([string]$candidate) -Label 'SSH port')
    }
    Assert-Tui -Condition ([string]$value.Value -eq '22222') -Message 'The text step must return only a valid normalized value.'
    Assert-TuiOutputContains -Text 'must be a whole number from 1 through 65535' -Message 'The text step must explain a rejected value before prompting again.'
}

Invoke-TuiTest -Name 'Disk and TCP text validators accept documented units and ranges and reject unsafe bounds' -Action {
    Assert-Tui -Condition ((ConvertTo-ClagnosOsDiskSizeGb -Value '1MB') -eq '1') -Message 'A 1MB disk request must round up to the minimum whole GiB.'
    Assert-Tui -Condition ((ConvertTo-ClagnosOsDiskSizeGb -Value '1GB') -eq '1') -Message 'A 1GB disk request must normalize to one GiB.'
    Assert-Tui -Condition ((ConvertTo-ClagnosOsDiskSizeGb -Value '1TB') -eq '1024') -Message 'A 1TB disk request must normalize to GiB.'
    Assert-Tui -Condition ((ConvertTo-ClagnosOsDiskSizeGb -Value '4095GB') -eq '4095') -Message 'The maximum OS disk size must be accepted.'
    foreach ($badSize in @('0MB','4096GB','1PB','1,5GB')) {
        $threw = $false
        try { ConvertTo-ClagnosOsDiskSizeGb -Value $badSize | Out-Null } catch { $threw = $true }
        Assert-Tui -Condition $threw -Message ("Invalid OS disk input '{0}' must be rejected." -f $badSize)
    }
    $ports = Resolve-ClagnosTcpPortSpecification -Text '80,3000-3300,3300-3310' -RequiredPorts @('22')
    Assert-Tui -Condition ($ports.CanonicalText -eq '22,80,3000-3310') -Message 'TCP ranges must merge, sort, and include required connection ports.'
    foreach ($badPorts in @('0','65536','500-300','1-65535','80,abc')) {
        $threw = $false
        try { Resolve-ClagnosTcpPortSpecification -Text $badPorts | Out-Null } catch { $threw = $true }
        Assert-Tui -Condition $threw -Message ("Invalid TCP port input '{0}' must be rejected." -f $badPorts)
    }
}

Invoke-TuiTest -Name 'Cloud subscriptions show selected and active state and select an enabled row' -Action {
    Set-TuiChoices -Choices @('1','b')
    Show-ClagnosUiCloudSubscriptions
    Assert-TuiOutputContains -Text 'Cloud subscriptions' -Message 'Cloud subscriptions screen heading must render.'
    Assert-TuiOutputContains -Text 'Clagnos selected: Fixture Enabled' -Message 'Screen must show the configured Clagnos selection.'
    Assert-TuiOutputContains -Text 'Azure CLI active: Fixture Enabled' -Message 'Screen must show the Azure CLI active selection.'
    Assert-TuiOutputContains -Text 'Fixture Disabled' -Message 'Screen must list disabled subscriptions.'
    Assert-Tui -Condition ($script:TuiSubscriptionSelections.Count -eq 1 -and $script:TuiSubscriptionSelections[0] -eq 'sub-fixture-enabled') -Message 'Selecting an enabled subscription must update the selected subscription through the UI adapter.'
}

Invoke-TuiTest -Name 'Cloud subscriptions reject disabled rows without activating them' -Action {
    Set-TuiChoices -Choices @('2','b')
    Show-ClagnosUiCloudSubscriptions
    Assert-TuiOutputContains -Text '[unavailable]' -Message 'Disabled subscriptions must be visible as unavailable options.'
    Assert-TuiOutputContains -Text 'not available for the active subscription' -Message 'Selecting a disabled subscription must explain why it cannot be activated.'
    Assert-Tui -Condition ($script:TuiSubscriptionSelections.Count -eq 0) -Message 'A disabled subscription must not be selected.'
    Assert-Tui -Condition ($script:TuiWaitCount -eq 0) -Message 'Disabled-selection guidance stays in the numbered picker.'
}

Invoke-TuiTest -Name 'Cloud subscriptions ignore invalid numeric selections' -Action {
    Set-TuiChoices -Choices @('99','b')
    Show-ClagnosUiCloudSubscriptions
    Assert-Tui -Condition ($script:TuiSubscriptionSelections.Count -eq 0) -Message 'An out-of-range subscription number must not activate a row.'
}

Invoke-TuiTest -Name 'Cloud subscriptions recover from an unavailable inventory' -Action {
    $script:TuiCloudRowsShouldThrow = $true
    Set-TuiChoices -Choices @()
    Show-ClagnosUiCloudSubscriptions
    Assert-TuiOutputContains -Text '[ERROR] fixture subscription inventory error' -Message 'Cloud inventory errors must render through the UI error surface.'
    Assert-Tui -Condition ($script:TuiWaitCount -eq 1) -Message 'Cloud inventory errors must pause before returning.'
}

Invoke-TuiTest -Name 'Cloud subscriptions return on q' -Action {
    Set-TuiChoices -Choices @('q')
    Show-ClagnosUiCloudSubscriptions
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Managed inventory routes all ten numbered resource filters' -Action {
    $types = @('', 'group','vm','disk','vnet','subnet','nic','ip','nsg','nsg-rule')
    for ($number = 1; $number -le 10; $number++) {
        Reset-TuiScenario
        $script:TuiCommandInvocations.Clear()
        $selection = [string]$number
        Set-TuiChoices -Choices @($selection, '2', 'b')
        Show-ClagnosUiInventoryMenu
        Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Cached inventory navigation must not dispatch another Azure inventory command.'
        if ($number -eq 1) { Assert-TuiOutputContains -Text 'DISK:' -Message 'All-types inventory must render cached resource categories.' }
        else { Assert-TuiOutputContains -Text ($types[$number - 1].ToUpperInvariant() + ':') -Message 'The selected inventory type must be rendered from the cache.' }
        Assert-TuiNoRealCloudCalls
    }
}

Invoke-TuiTest -Name 'Managed inventory renders its type menu and returns on b' -Action {
    Set-TuiChoices -Choices @('b')
    Show-ClagnosUiInventoryMenu
    Assert-TuiOutputContains -Text 'Managed resource inventory' -Message 'Inventory screen heading must render.'
    Assert-TuiOutputContains -Text '10. Network security rules' -Message 'Inventory screen must include the final numbered resource type.'
}

Invoke-TuiTest -Name 'Managed inventory returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    Show-ClagnosUiInventoryMenu
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Managed inventory ignores invalid input and supports an unfiltered inventory' -Action {
    Set-TuiChoices -Choices @('invalid','1','1','b')
    Show-ClagnosUiInventoryMenu
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Invalid menu input and the all-groups filter must remain read-only cache operations.'
    Assert-TuiOutputContains -Text 'All managed resource groups' -Message 'The group filter must offer an explicit all-groups choice.'
    Assert-TuiOutputContains -Text '>1. All managed resource groups' -Message 'The inventory filter must mark all groups as the default selection.'
}

Invoke-TuiTest -Name 'Virtual computer discovery enriches rows with managed group and subscription' -Action {
    $script:TuiDiscoveryMode = $true
    $script:TuiManagedGroups = @([pscustomobject]@{ name = 'rg-fixture-eastus-g1'; tags = [pscustomobject]@{ 'managed-by' = 'clagnos' } })
    $script:TuiDiscoveryVmRows = @($script:TuiWindowsVm)
    $rows = @(& $script:TuiOriginalVmDiscovery)
    Assert-Tui -Condition ($rows.Count -eq 1) -Message 'Discovery must return the fixture VM.'
    Assert-Tui -Condition ([string]$rows[0].ClagnosResourceGroup -eq 'rg-fixture-eastus-g1') -Message 'Discovery must attach its managed resource group.'
    Assert-Tui -Condition ([string]$rows[0].ClagnosSubscriptionId -eq 'sub-fixture-enabled') -Message 'Discovery must attach the selected subscription id.'
    Assert-Tui -Condition ($script:TuiAzureReadQueries.Count -eq 0) -Message 'VM discovery must read the startup inventory snapshot without issuing screen-specific Azure reads.'
}

Invoke-TuiTest -Name 'Legacy managed-group discovery routes tag migration only through its mock' -Action {
    $script:TuiDiscoveryMode = $true
    $legacyGroup = [pscustomobject]@{ name = 'rg-legacy-fixture'; tags = [pscustomobject]@{ 'managed-by' = 'az-vm' } }
    $currentGroup = [pscustomobject]@{ name = 'rg-legacy-fixture'; tags = [pscustomobject]@{ 'managed-by' = 'clagnos' } }
    $script:TuiManagedGroupsByCall = @($legacyGroup, $currentGroup)
    $script:TuiDiscoveryVmRows = @($script:TuiWindowsVm)
    $rows = @(& $script:TuiOriginalVmDiscovery)
    Assert-Tui -Condition ($script:TuiLegacyMigrationCount -eq 1) -Message 'Legacy group discovery must route tag migration to the test adapter.'
    Assert-Tui -Condition ($script:TuiManagedGroupCallCount -eq 2) -Message 'Discovery must refresh the managed-group inventory after migration.'
    Assert-Tui -Condition ($rows.Count -eq 1) -Message 'VM discovery must continue after mocked legacy migration.'
}

Invoke-TuiTest -Name 'Virtual computers render the empty state and all list actions' -Action {
    $script:TuiVirtualComputers = @()
    Set-TuiChoices -Choices @('b')
    Show-ClagnosUiVirtualComputers
    Assert-TuiOutputContains -Text 'No managed virtual computers were found.' -Message 'Empty VC inventory must be explicit.'
    Assert-TuiOutputContains -Text 'c: create virtual computer' -Message 'VC list must show create.'
    Assert-TuiOutputContains -Text 'r: check or refresh managed resource cache' -Message 'VC list must show an explicit cache refresh action.'
}

Invoke-TuiTest -Name 'Virtual computers show a readable error if inventory cannot load' -Action {
    $script:TuiVmDiscoveryShouldThrow = $true
    Set-TuiChoices -Choices @('b')
    Show-ClagnosUiVirtualComputers
    Assert-TuiOutputContains -Text '[ERROR] fixture VM inventory error' -Message 'VC inventory failures must render through the error surface.'
    Assert-TuiOutputContains -Text 'No managed virtual computers were found.' -Message 'VC inventory must recover to its empty state after an error.'
}

Invoke-TuiTest -Name 'Virtual computers create, refresh, and return to the previous menu' -Action {
    $script:TuiAzOverride = {
        param([string[]]$Arguments)
        $query = @($Arguments) -join ' '
        if ($query -eq 'group list') { return @($script:TuiManagedGroups) }
        if ($query -like 'resource list --resource-group *') { return @($script:ClagnosUiInventoryCache.Resources) }
        if ($query -eq 'vm list --show-details') { return @($script:TuiVirtualComputers) }
        throw ('Unexpected refresh fixture query: {0}' -f $query)
    }
    Set-TuiChoices -Choices @('c','r','b')
    Show-ClagnosUiVirtualComputers
    Assert-Tui -Condition ($script:TuiCreateWizardCount -eq 1) -Message 'Create must open the interactive create wizard.'
    Assert-Tui -Condition ($script:TuiSubscriptionRefreshCount -eq 1) -Message 'Manual cache refresh must revalidate the subscription context.'
}

Invoke-TuiTest -Name 'Virtual computer numeric selection opens that VC' -Action {
    $script:TuiVirtualComputers = @($script:TuiWindowsVm, (New-TuiVmFixture -Platform Linux))
    $script:TuiVirtualComputers[1].name = 'fixture-linux'
    Set-TuiChoices -Choices @('2','b','b')
    Show-ClagnosUiVirtualComputers
    Assert-Tui -Condition ($script:TuiVmDetailsCount -eq 1) -Message 'Selecting a VM number must enter its detail screen.'
    Assert-TuiOutputContains -Text '2. fixture-linux | Linux' -Message 'VC rows must identify the selected item and its platform.'
}

Invoke-TuiTest -Name 'Virtual computer list exits on q without invoking cloud actions' -Action {
    Set-TuiChoices -Choices @('q')
    Show-ClagnosUiVirtualComputers
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Virtual computer list ignores invalid selection input' -Action {
    Set-TuiChoices -Choices @('99','b')
    Show-ClagnosUiVirtualComputers
    Assert-Tui -Condition ($script:TuiVmDetailsCount -eq 0) -Message 'An invalid VC number must not enter a detail screen.'
}

Invoke-TuiTest -Name 'Selected VC detail screen renders addresses, DNS, disks, VM features, and both login roles' -Action {
    & $script:TuiOriginalVmDetails -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'Public IP: 203.0.113.8' -Message 'VC details must show the public IP.'
    Assert-TuiOutputContains -Text 'Public DNS: fixture.eastus.cloudapp.azure.com' -Message 'VC details must show the public DNS name.'
    Assert-TuiOutputContains -Text 'Private IP address(es): 10.1.0.4' -Message 'VC details must show private addresses.'
    Assert-TuiOutputContains -Text 'VNet vnet-fixture | subnet subnet-fixture' -Message 'VC details must show VNet and subnet.'
    Assert-TuiOutputContains -Text 'Network security group: nsg-fixture' -Message 'VC details must show the NSG.'
    Assert-TuiOutputContains -Text 'disk-fixture-os' -Message 'VC details must show the OS disk.'
    Assert-TuiOutputContains -Text 'disk-fixture-data' -Message 'VC details must show data disks.'
    Assert-TuiOutputContains -Text 'Hibernation enabled: True' -Message 'VC details must show actual Azure hibernation state.'
    Assert-TuiOutputContains -Text 'Nested virtualization setting (.env): true' -Message 'VC details must show configured nested virtualization intent.'
    Assert-TuiOutputContains -Text 'SSH endpoint: fixture.eastus.cloudapp.azure.com:22222' -Message 'SSH endpoint must use configured port and the public DNS name.'
    Assert-TuiOutputContains -Text 'PowerShell remoting endpoint: fixture.eastus.cloudapp.azure.com:5985' -Message 'Windows VC details must show the WinRM endpoint.'
    Assert-TuiOutputContains -Text 'manager-fixture | password: <runtime-secret>' -Message 'Manager credentials must be shown.'
    Assert-TuiOutputContains -Text 'assistant-fixture | password: <runtime-secret>' -Message 'Assistant credentials must be shown.'
    Assert-TuiOutputContains -Text 'RDP endpoint: fixture.eastus.cloudapp.azure.com:3390' -Message 'RDP endpoint must use configured port and the public DNS name.'
    Assert-TuiOutputContains -Text 'NIC: nic-fixture' -Message 'VC details must show the NIC.'
    Assert-TuiOutputContains -Text 'Microsoft.Compute/virtualMachines | fixture-vc' -Message 'VC details must enumerate attached Azure resources.'
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Linux VC detail screen omits RDP and reports missing public endpoints' -Action {
    $script:TuiVmDetailRecord.storageProfile.osDisk.osType = 'Linux'
    $script:TuiVmDetailRecord.networkProfile.networkInterfaces = @()
    $script:TuiVmDetailRecord.additionalCapabilities.hibernationEnabled = $false
    $script:TuiLinuxVm.publicIps = ''
    $script:TuiLinuxVm.fqdns = ''
    $script:TuiAzOverride = {
        param([string[]]$Arguments)
        $query = @($Arguments) -join ' '
        $script:TuiAzureReadQueries.Add($query)
        if ($query -like 'vm show *') { return $script:TuiVmDetailRecord }
        if ($query -like 'vm list-ip-addresses *') { return @([pscustomobject]@{ virtualMachine = [pscustomobject]@{ name = 'fixture-vc'; network = [pscustomobject]@{ privateIpAddresses = @(); publicIpAddresses = @() } } }) }
        if ($query -like 'resource list *') { return @() }
        throw ('Unexpected simulated Azure read query: {0}' -f $query)
    }
    & $script:TuiOriginalVmDetails -Vm $script:TuiLinuxVm
    Assert-TuiOutputContains -Text 'RDP: not applicable to this Linux VC.' -Message 'Linux VC details must not present RDP as available.'
    Assert-TuiOutputContains -Text 'Public IP/DNS: (no public endpoint reported)' -Message 'VC details must clearly show when no public endpoint is reported.'
    Assert-TuiOutputContains -Text 'Hibernation enabled: False' -Message 'VC details must show disabled hibernation.'
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Selected VC screen routes all visible shortcuts and confirms complete group deletion' -Action {
    Set-TuiChoices -Choices @('p','i','u','m','o','r','d','no','d','DELETE ALL')
    Show-ClagnosUiVmMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiPackageMenuCount -eq 1) -Message 'p must open Manage Programs.'
    Assert-Tui -Condition ($script:TuiComponentMenuCount -eq 1) -Message 'm must open VC components.'
    Assert-Tui -Condition ($script:TuiOperationsMenuCount -eq 1) -Message 'o must open VC operations.'
    Assert-Tui -Condition ($script:TuiVmDetailsCount -ge 8) -Message 'The selected VC must refresh its details on entry and after the refresh shortcut.'
    $initialize = Assert-TuiCommand -CommandName 'initialize'
    Assert-TuiOption -Call $initialize -Name 'vm-name' -Expected 'fixture-vc'
    $update = Assert-TuiCommand -CommandName 'update'
    Assert-TuiOption -Call $update -Name 'vm-name' -Expected 'fixture-vc'
    $delete = Assert-TuiCommand -CommandName 'delete'
    Assert-TuiOption -Call $delete -Name 'target' -Expected 'group'
    Assert-TuiOption -Call $delete -Name 'yes' -Expected 'True'
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Selected VC screen returns on q after rendering details' -Action {
    Set-TuiChoices -Choices @('q')
    Show-ClagnosUiVmMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiVmDetailsCount -eq 1) -Message 'VC details must render before the screen accepts q.'
}

Invoke-TuiTest -Name 'Selected VC screen keeps rendering after a detail-read error' -Action {
    $script:TuiDetailsShouldThrow = $true
    Set-TuiChoices -Choices @('b')
    Show-ClagnosUiVmMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '[ERROR] fixture VC detail read error' -Message 'VC detail errors must be caught and rendered.'
    Assert-TuiOutputContains -Text 'p: manage programs' -Message 'A detail-read error must not remove the VC actions.'
}

Invoke-TuiTest -Name 'Selected VC deletion cancellation never dispatches delete' -Action {
    Set-TuiChoices -Choices @('d','CANCEL','b')
    Show-ClagnosUiVmMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition (@($script:TuiCommandInvocations | Where-Object { $_.CommandName -eq 'delete' }).Count -eq 0) -Message 'Deletion must require the exact DELETE ALL confirmation.'
    Assert-TuiNoRealCloudCalls
}

Invoke-TuiTest -Name 'Manage Programs routes to builtin and custom catalogs' -Action {
    Set-TuiChoices -Choices @('1','1','b','b','2','1','b','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '[builtin]' -Message 'Builtin catalog rows must carry their source label.'
    Assert-TuiOutputContains -Text '[custom]' -Message 'Custom catalog rows must carry their source label.'
    Assert-TuiOutputContains -Text '(disabled)' -Message 'Disabled packages must be marked in the catalog.'
    Assert-TuiOutputContains -Text '[not-installed]' -Message 'Package status must be displayed beside the catalog row.'
}

foreach ($packageActionCase in @(
    @{ Key = 'e'; Action = 'enable' },
    @{ Key = 'd'; Action = 'disable' },
    @{ Key = 'i'; Action = 'install' },
    @{ Key = 's'; Action = 'status' }
)) {
    Invoke-TuiTest -Name ("Builtin package action '{0}' routes to the matching package operation" -f $packageActionCase.Action) -Action {
        $inputChoices = @('1','1', [string]$packageActionCase.Key)
        if ($packageActionCase.Key -eq 'u') { $inputChoices += 'UNINSTALL' }
        $inputChoices += @('b','b')
        Set-TuiChoices -Choices $inputChoices
        & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
        $call = Assert-TuiCommand -CommandName 'package'
        Assert-TuiOption -Call $call -Name 'action' -Expected ([string]$packageActionCase.Action)
        Assert-TuiOption -Call $call -Name 'package' -Expected 'builtin-fixture'
        Assert-TuiOption -Call $call -Name 'catalog' -Expected 'builtin'
        Assert-TuiOption -Call $call -Name 'windows' -Expected 'True'
        if ($packageActionCase.Action -notin @('enable','disable')) {
            Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
        }
    }
}

Invoke-TuiTest -Name 'Builtin package uninstall requires the exact typed confirmation' -Action {
    Set-TuiChoices -Choices @('1','1','u','uninstall','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition (@($script:TuiCommandInvocations | Where-Object { $_.CommandName -eq 'package' }).Count -eq 0) -Message 'An incorrect uninstall confirmation must not dispatch the operation.'
}

Invoke-TuiTest -Name 'Builtin package uninstall passes confirmation to its command' -Action {
    Set-TuiChoices -Choices @('1','1','u','UNINSTALL','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'package'
    Assert-TuiOption -Call $call -Name 'action' -Expected 'uninstall'
    Assert-TuiOption -Call $call -Name 'yes' -Expected 'True'
}

Invoke-TuiTest -Name 'Package status failures render unavailable rows without leaving the catalog' -Action {
    $script:TuiPackageStatusShouldThrow = $true
    Set-TuiChoices -Choices @('1','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'Package status could not be read: fixture package status unavailable' -Message 'Package status errors must be visible.'
    Assert-TuiOutputContains -Text '[unavailable]' -Message 'Missing status values must render as unavailable.'
}

Invoke-TuiTest -Name 'Package catalog reports an empty catalog and accepts back' -Action {
    $script:TuiPackagesByCatalog['builtin'] = @()
    Set-TuiChoices -Choices @('1','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'No packages are registered in the builtin catalog for windows.' -Message 'Empty catalog state must be visible.'
}

Invoke-TuiTest -Name 'Custom package install uses the custom catalog identity' -Action {
    Set-TuiChoices -Choices @('2','1','i','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'package'
    Assert-TuiOption -Call $call -Name 'catalog' -Expected 'custom'
    Assert-TuiOption -Call $call -Name 'package' -Expected 'custom-fixture'
    Assert-TuiOption -Call $call -Name 'action' -Expected 'install'
}

Invoke-TuiTest -Name 'Package app-state save maps the VC source and selected user' -Action {
    $package = $script:TuiPackagesByCatalog['builtin'][0]
    Set-TuiChoices -Choices @('1','v','.all.')
    Show-ClagnosUiPackageAppStateMenu -Vm $script:TuiWindowsVm -Package $package -Catalog builtin -Platform windows
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'save-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'source' -Expected 'vm'
    Assert-TuiOption -Call $call -Name 'user' -Expected '.all.'
    Assert-TuiOption -Call $call -Name 'package-catalog' -Expected 'builtin'
}

Invoke-TuiTest -Name 'Package app-state restore maps a local Windows target' -Action {
    $package = $script:TuiPackagesByCatalog['custom'][0]
    Set-TuiChoices -Choices @('2','l','assistant')
    Show-ClagnosUiPackageAppStateMenu -Vm $script:TuiWindowsVm -Package $package -Catalog custom -Platform windows
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'restore-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'target' -Expected 'lm'
    Assert-TuiOption -Call $call -Name 'user' -Expected 'assistant'
    Assert-TuiOption -Call $call -Name 'package-catalog' -Expected 'custom'
}

Invoke-TuiTest -Name 'Package app-state save maps a local Windows source' -Action {
    $package = $script:TuiPackagesByCatalog['builtin'][0]
    Set-TuiChoices -Choices @('1','l','assistant')
    Show-ClagnosUiPackageAppStateMenu -Vm $script:TuiWindowsVm -Package $package -Catalog builtin -Platform windows
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'save-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'source' -Expected 'lm'
    Assert-TuiOption -Call $call -Name 'user' -Expected 'assistant'
}

Invoke-TuiTest -Name 'Package app-state restore maps a VC target' -Action {
    $package = $script:TuiPackagesByCatalog['custom'][0]
    Set-TuiChoices -Choices @('2','v','.current.')
    Show-ClagnosUiPackageAppStateMenu -Vm $script:TuiWindowsVm -Package $package -Catalog custom -Platform windows
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'restore-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'target' -Expected 'vm'
    Assert-TuiOption -Call $call -Name 'user' -Expected '.current.'
}

Invoke-TuiTest -Name 'Linux package app-state refuses local-machine actions' -Action {
    $package = $script:TuiPackagesByCatalog['builtin'][0]
    Set-TuiChoices -Choices @('2','l')
    Show-ClagnosUiPackageAppStateMenu -Vm $script:TuiLinuxVm -Package $package -Catalog builtin -Platform linux
    Assert-TuiOutputContains -Text 'Local-machine package app-state is available only on a Windows host.' -Message 'Linux local package app-state restriction must be shown.'
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Linux local app-state actions must not dispatch.'
}

Invoke-TuiTest -Name 'Package catalog routes the app-state submenu from the package detail screen' -Action {
    Set-TuiChoices -Choices @('1','1','a','1','v','.current.','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'save-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'user' -Expected '.current.'
}

Invoke-TuiTest -Name 'Manage Programs screen returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '2. Custom package catalog' -Message 'Manage Programs must render before q is accepted.'
}

Invoke-TuiTest -Name 'Manage Programs ignores invalid catalog selection' -Action {
    Set-TuiChoices -Choices @('invalid','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'An invalid package catalog choice must not dispatch an action.'
}

Invoke-TuiTest -Name 'Package detail ignores invalid action and returns to the package list' -Action {
    Set-TuiChoices -Choices @('1','1','invalid','b','b')
    & $script:TuiOriginalPackageMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'An invalid package action must not dispatch an operation.'
}

Invoke-TuiTest -Name 'Package app-state screen returns on b' -Action {
    $package = $script:TuiPackagesByCatalog['builtin'][0]
    Set-TuiChoices -Choices @('b')
    Show-ClagnosUiPackageAppStateMenu -Vm $script:TuiWindowsVm -Package $package -Catalog builtin -Platform windows
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'The package app-state back option must not dispatch an operation.'
}

Invoke-TuiTest -Name 'Package catalog returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    & $script:TuiOriginalPackageCatalogMenu -Vm $script:TuiWindowsVm -Catalog builtin
    Assert-TuiNoRealCloudCalls
}

$componentTypes = @(
    @{ Number = '1'; Id = 'group' }, @{ Number = '2'; Id = 'vm' }, @{ Number = '3'; Id = 'disk' },
    @{ Number = '4'; Id = 'vnet' }, @{ Number = '5'; Id = 'subnet' }, @{ Number = '6'; Id = 'nic' },
    @{ Number = '7'; Id = 'ip' }, @{ Number = '8'; Id = 'nsg' }, @{ Number = '9'; Id = 'nsg-rule' }
)
$componentActions = @(
    @{ Key = 'l'; Name = 'list' }, @{ Key = 's'; Name = 'show' }, @{ Key = 'c'; Name = 'create' },
    @{ Key = 'u'; Name = 'update' }, @{ Key = 'd'; Name = 'delete' }
)
foreach ($componentTypeCase in $componentTypes) {
    foreach ($componentActionCase in $componentActions) {
        Invoke-TuiTest -Name ("Component '{0}' action '{1}' maps to the component command" -f $componentTypeCase.Id, $componentActionCase.Name) -Action {
            $choices = @([string]$componentTypeCase.Number, [string]$componentActionCase.Key)
            if ($componentActionCase.Name -eq 'show' -and $componentTypeCase.Id -ne 'nsg-rule') { $choices += '' }
            $choices += 'b'
            Set-TuiChoices -Choices $choices
            & $script:TuiOriginalComponentMenu -Vm $script:TuiWindowsVm
            if ($componentActionCase.Name -in @('list','show')) {
                Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Component list and show must use the managed inventory cache.'
                if ($componentTypeCase.Id -eq 'nsg-rule') { Assert-TuiOutputContains -Text 'No cached nsg-rule components' -Message 'An empty cached component type must be stated explicitly.' }
                else { Assert-TuiOutputContains -Text 'Snapshot validated:' -Message 'Cached component output must identify its validation timestamp.' }
            }
            else {
                $call = Assert-TuiCommand -CommandName 'component'
                Assert-TuiOption -Call $call -Name 'type' -Expected ([string]$componentTypeCase.Id)
                Assert-TuiOption -Call $call -Name 'action' -Expected ([string]$componentActionCase.Name)
                Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
            }
        }
    }
}

foreach ($componentAttachmentCase in @(
    @{ Number = '3'; Type = 'disk'; Key = 'a'; Action = 'attach' },
    @{ Number = '3'; Type = 'disk'; Key = 't'; Action = 'detach' },
    @{ Number = '6'; Type = 'nic'; Key = 'a'; Action = 'attach' },
    @{ Number = '6'; Type = 'nic'; Key = 't'; Action = 'detach' }
)) {
    Invoke-TuiTest -Name ("Component '{0}' supports {1}" -f $componentAttachmentCase.Type, $componentAttachmentCase.Action) -Action {
        Set-TuiChoices -Choices @([string]$componentAttachmentCase.Number, [string]$componentAttachmentCase.Key, 'b')
        & $script:TuiOriginalComponentMenu -Vm $script:TuiWindowsVm
        $call = Assert-TuiCommand -CommandName 'component'
        Assert-TuiOption -Call $call -Name 'type' -Expected ([string]$componentAttachmentCase.Type)
        Assert-TuiOption -Call $call -Name 'action' -Expected ([string]$componentAttachmentCase.Action)
    }
}

Invoke-TuiTest -Name 'Component selector renders all nine resource types and returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    & $script:TuiOriginalComponentMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '9. Network security rule' -Message 'Component screen must show the final resource type.'
}

Invoke-TuiTest -Name 'Component selector ignores invalid types and supports back from the action screen' -Action {
    Set-TuiChoices -Choices @('0','3','b','b')
    & $script:TuiOriginalComponentMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Invalid component selections and a component-action back must not dispatch operations.'
}

Invoke-TuiTest -Name 'Component action screen offers non-attach operations and accepts q' -Action {
    Set-TuiChoices -Choices @('3','q')
    & $script:TuiOriginalComponentMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'u: update properties' -Message 'Component action screen must include update.'
    Assert-TuiOutputContains -Text 't: detach' -Message 'Disk component screen must include detach.'
}

Invoke-TuiTest -Name 'Task menu lists active and disabled tasks' -Action {
    Set-TuiChoices -Choices @('1','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'list' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'vm-init' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'vm-update' -Expected 'True'
}

Invoke-TuiTest -Name 'Task menu opens local task run history without target selectors' -Action {
    Set-TuiChoices -Choices @('8','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'history' -Expected 'True'
    Assert-Tui -Condition (-not $call.Options.ContainsKey('group') -and -not $call.Options.ContainsKey('vm-name')) -Message 'Local task history must not inherit Azure target selectors.'
}

Invoke-TuiTest -Name 'Task menu runs a selected init task' -Action {
    Set-TuiChoices -Choices @('2','1','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'run-vm-init' -Expected '01-fixture-init'
    Assert-TuiOption -Call $call -Name 'windows' -Expected 'True'
}

Invoke-TuiTest -Name 'Task menu runs a selected update task' -Action {
    $script:TuiTaskCatalogByStage.update[0].Enabled = $true
    Set-TuiChoices -Choices @('3','1','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'run-vm-update' -Expected '101-fixture-update'
}

Invoke-TuiTest -Name 'Task menu prevents running a disabled task' -Action {
    Set-TuiChoices -Choices @('3','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Disabled tasks must not be dispatchable through the isolated run menu.'
    Assert-TuiOutputContains -Text 'No selectable tasks are registered for this stage.' -Message 'An all-disabled stage must explain why it cannot run.'
}

Invoke-TuiTest -Name 'Task menu lists disabled tasks' -Action {
    Set-TuiChoices -Choices @('6','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'disabled' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'vm-init' -Expected 'True'
}

Invoke-TuiTest -Name 'Task menu saves VM app-state for an init task' -Action {
    Set-TuiChoices -Choices @('4','i','1','v','.all.','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'save-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'source' -Expected 'vm'
    Assert-TuiOption -Call $call -Name 'user' -Expected '.all.'
    Assert-TuiOption -Call $call -Name 'vm-init-task' -Expected '01-fixture-init'
}

Invoke-TuiTest -Name 'Task menu restores local app-state for an update task' -Action {
    Set-TuiChoices -Choices @('5','u','1','l','manager','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'restore-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'target' -Expected 'lm'
    Assert-TuiOption -Call $call -Name 'user' -Expected 'manager'
    Assert-TuiOption -Call $call -Name 'vm-update-task' -Expected '101-fixture-update'
}

Invoke-TuiTest -Name 'Task menu saves local app-state for an update task' -Action {
    Set-TuiChoices -Choices @('4','u','1','l','.current.','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'save-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'source' -Expected 'lm'
    Assert-TuiOption -Call $call -Name 'user' -Expected '.current.'
}

Invoke-TuiTest -Name 'Task menu restores VM app-state for an init task' -Action {
    Set-TuiChoices -Choices @('5','i','1','v','assistant','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'restore-app-state' -Expected 'True'
    Assert-TuiOption -Call $call -Name 'target' -Expected 'vm'
    Assert-TuiOption -Call $call -Name 'user' -Expected 'assistant'
}

Invoke-TuiTest -Name 'Task app-state validates and normalizes a comma-separated user selection' -Action {
    Set-TuiChoices -Choices @('4','i','1','v','manager,assistant','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'user' -Expected 'manager,assistant'
}

Invoke-TuiTest -Name 'Task app-state rejects malformed usernames and prompts again' -Action {
    Set-TuiChoices -Choices @('4','i','1','v','manager;invalid','assistant','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'user' -Expected 'assistant'
    Assert-TuiOutputContains -Text 'User selector value' -Message 'Malformed usernames must be rejected before command dispatch.'
}

Invoke-TuiTest -Name 'Task availability screen enables a selected init task' -Action {
    Set-TuiChoices -Choices @('1','1','e','b')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'vm-init-task' -Expected '01-fixture-init'
    Assert-TuiOption -Call $call -Name 'enable' -Expected 'True'
}

Invoke-TuiTest -Name 'Task availability screen disables a selected update task' -Action {
    Set-TuiChoices -Choices @('2','1','d','b')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'vm-update-task' -Expected '101-fixture-update'
    Assert-TuiOption -Call $call -Name 'disable' -Expected 'True'
}

Invoke-TuiTest -Name 'Task availability screen disables a selected init task' -Action {
    Set-TuiChoices -Choices @('1','1','d','b')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'vm-init-task' -Expected '01-fixture-init'
    Assert-TuiOption -Call $call -Name 'disable' -Expected 'True'
}

Invoke-TuiTest -Name 'Task availability screen enables a selected update task' -Action {
    Set-TuiChoices -Choices @('2','1','e','b')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'task'
    Assert-TuiOption -Call $call -Name 'vm-update-task' -Expected '101-fixture-update'
    Assert-TuiOption -Call $call -Name 'enable' -Expected 'True'
}

Invoke-TuiTest -Name 'Task availability screen displays disabled task state' -Action {
    Set-TuiChoices -Choices @('2','1','b','b')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'disabled: disabled catalog' -Message 'Task inventory must display disabled status and reason.'
}

Invoke-TuiTest -Name 'Task availability handles an empty task catalog' -Action {
    $script:TuiTaskCatalogByStage.init = @()
    Set-TuiChoices -Choices @('1','b')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'No tasks are registered for this stage.' -Message 'An empty stage must be explained.'
    Assert-Tui -Condition ($script:TuiWaitCount -eq 1) -Message 'Empty stage guidance must pause.'
}

Invoke-TuiTest -Name 'Task availability screen returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    & $script:TuiOriginalTaskAvailabilityMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '1. Initialization tasks' -Message 'Task availability screen must render before q is accepted.'
}

Invoke-TuiTest -Name 'Task availability submenu is reachable from Tasks and app-state' -Action {
    Set-TuiChoices -Choices @('7','b','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text 'Task availability is shared by this repository' -Message 'Task submenu must reach the task availability screen.'
}

Invoke-TuiTest -Name 'Task menu returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '8. View recent task run history' -Message 'Task screen must render the local history option before q is accepted.'
}

Invoke-TuiTest -Name 'Task menu ignores an invalid item and returns on b' -Action {
    Set-TuiChoices -Choices @('invalid','b')
    & $script:TuiOriginalTaskMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Invalid task menu choices must not dispatch.'
}

$powerActionCases = @(
    @{ Number = '1'; Action = 'status' }, @{ Number = '2'; Action = 'start' },
    @{ Number = '3'; Action = 'shutdown' }, @{ Number = '4'; Action = 'hibernate-stop' },
    @{ Number = '5'; Action = 'hibernate-deallocate' }, @{ Number = '6'; Action = 'resume' },
    @{ Number = '7'; Action = 'restart' }, @{ Number = '8'; Action = 'power-off'; Confirmation = 'POWER OFF' },
    @{ Number = '9'; Action = 'reset'; Confirmation = 'RESET' }, @{ Number = '10'; Action = 'deallocate' },
    @{ Number = '11'; Action = 'reapply' }, @{ Number = '12'; Action = 'redeploy' }
)
foreach ($powerActionCase in $powerActionCases) {
    Invoke-TuiTest -Name ("Operations power choice {0} dispatches '{1}'" -f $powerActionCase.Number, $powerActionCase.Action) -Action {
        $choices = @('1', [string]$powerActionCase.Number)
        if ($powerActionCase.ContainsKey('Confirmation')) { $choices += [string]$powerActionCase.Confirmation }
        $choices += 'b'
        Set-TuiChoices -Choices $choices
        & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
        $call = Assert-TuiCommand -CommandName 'do'
        Assert-TuiOption -Call $call -Name 'vm-action' -Expected ([string]$powerActionCase.Action)
        Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
        Assert-Tui -Condition (-not $call.Options.ContainsKey('windows') -and -not $call.Options.ContainsKey('linux')) -Message 'Power actions must not receive platform flags rejected by the do command contract.'
    }
}

Invoke-TuiTest -Name 'Power-off cancellation returns without dispatching an operation' -Action {
    Set-TuiChoices -Choices @('1','8','no','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Power-off must require the exact typed confirmation.'
}

Invoke-TuiTest -Name 'Reset cancellation returns without dispatching an operation' -Action {
    Set-TuiChoices -Choices @('1','9','no','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Reset must require the exact typed confirmation.'
}

Invoke-TuiTest -Name 'Operations resize menu routes compute resize' -Action {
    Set-TuiChoices -Choices @('2','1','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'resize'
    Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
    Assert-Tui -Condition (-not $call.Options.ContainsKey('disk-size')) -Message 'Compute resize must open the VM SKU path without disk arguments.'
}

Invoke-TuiTest -Name 'Operations resize menu routes OS disk expansion' -Action {
    Set-TuiChoices -Choices @('2','2','196gb','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'resize'
    Assert-TuiOption -Call $call -Name 'disk-size' -Expected '196gb'
    Assert-TuiOption -Call $call -Name 'expand' -Expected 'True'
}

Invoke-TuiTest -Name 'Operations resize menu routes safe shrink guidance' -Action {
    Set-TuiChoices -Choices @('2','3','64gb','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'resize'
    Assert-TuiOption -Call $call -Name 'disk-size' -Expected '64gb'
    Assert-TuiOption -Call $call -Name 'shrink' -Expected 'True'
}

Invoke-TuiTest -Name 'Operations menu maps region move to the move command' -Action {
    Set-TuiChoices -Choices @('3','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'move'
    Assert-TuiOption -Call $call -Name 'vm-region' -Expected 'westus2'
    Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
}

foreach ($featureCase in @(
    @{ Key = 'h'; Value = '1'; Name = 'hibernation'; Expected = 'true' },
    @{ Key = 'h'; Value = '2'; Name = 'hibernation'; Expected = 'false' },
    @{ Key = 'n'; Value = '1'; Name = 'nested-virtualization'; Expected = 'true' },
    @{ Key = 'n'; Value = '2'; Name = 'nested-virtualization'; Expected = 'false' }
)) {
    Invoke-TuiTest -Name ("Operations feature menu sets {0} to {1}" -f $featureCase.Name, $featureCase.Expected) -Action {
        Set-TuiChoices -Choices @('4', [string]$featureCase.Key, [string]$featureCase.Value, 'b')
        & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
        $call = Assert-TuiCommand -CommandName 'set'
        Assert-TuiOption -Call $call -Name ([string]$featureCase.Name) -Expected ([string]$featureCase.Expected)
    }
}

foreach ($connectionCase in @(
    @{ Key = 's'; Name = 'SSH'; Transport = 'ssh'; Windows = $true; Test = $false },
    @{ Key = 'r'; Name = 'RDP'; Transport = 'rdp'; Windows = $true; Test = $false },
    @{ Key = 't'; Name = 'SSH test'; Transport = 'ssh'; Windows = $true; Test = $true },
    @{ Key = 'd'; Name = 'RDP test'; Transport = 'rdp'; Windows = $true; Test = $true },
    @{ Key = 'p'; Name = 'PowerShell remoting'; Transport = 'powershell'; Windows = $true; Test = $false },
    @{ Key = 'c'; Name = 'PowerShell command'; Transport = 'powershell'; Windows = $true; Test = $false; Command = 'Get-Date' },
    @{ Key = 'w'; Name = 'PowerShell test'; Transport = 'powershell'; Windows = $true; Test = $true }
)) {
    Invoke-TuiTest -Name ("Operations connection menu supports {0}" -f $connectionCase.Name) -Action {
        $choices = @('5', [string]$connectionCase.Key)
        if ($connectionCase.ContainsKey('Command')) { $choices += [string]$connectionCase.Command }
        $choices += 'b'
        Set-TuiChoices -Choices $choices
        & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
        $call = Assert-TuiCommand -CommandName 'connect'
        Assert-TuiOption -Call $call -Name ([string]$connectionCase.Transport) -Expected 'True'
        if ($connectionCase.Test) { Assert-TuiOption -Call $call -Name 'test' -Expected 'True' }
        if ($connectionCase.ContainsKey('Command')) { Assert-TuiOption -Call $call -Name 'command' -Expected ([string]$connectionCase.Command) }
    }
}

Invoke-TuiTest -Name 'Operations connection menu rejects RDP for a Linux VC' -Action {
    Set-TuiChoices -Choices @('5','r','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiLinuxVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'RDP must not dispatch for a Linux target.'
}

Invoke-TuiTest -Name 'Operations connection menu rejects PowerShell remoting for a Linux VC' -Action {
    Set-TuiChoices -Choices @('5','p','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiLinuxVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'PowerShell remoting must not dispatch for a Linux target.'
}

Invoke-TuiTest -Name 'Operations command menu opens an interactive shell when command input is blank' -Action {
    Set-TuiChoices -Choices @('6','','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'exec'
    Assert-Tui -Condition (-not $call.Options.ContainsKey('command')) -Message 'A blank remote command must select the interactive shell path.'
}

Invoke-TuiTest -Name 'Operations command menu sends a one-shot remote command' -Action {
    Set-TuiChoices -Choices @('6','Get-Date','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'exec'
    Assert-TuiOption -Call $call -Name 'command' -Expected 'Get-Date'
}

Invoke-TuiTest -Name 'Operations menu routes Tasks and app-state, Components, and full report' -Action {
    Set-TuiChoices -Choices @('7','8','9','t','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiTaskMenuCount -eq 1) -Message 'Operations option 7 must open Tasks and app-state.'
    Assert-Tui -Condition ($script:TuiComponentMenuCount -eq 1) -Message 'Operations option 8 must open Components.'
    $call = Assert-TuiCommand -CommandName 'show'
    Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
}

Invoke-TuiTest -Name 'Operations report submenu maps a redacted JSON export path' -Action {
    Set-TuiChoices -Choices @('9','j','reports\fixture-vc.json','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    $call = Assert-TuiCommand -CommandName 'show'
    Assert-TuiOption -Call $call -Name 'export-json' -Expected 'reports\fixture-vc.json'
    Assert-TuiOption -Call $call -Name 'vm-name' -Expected 'fixture-vc'
}

Invoke-TuiTest -Name 'Operations report path accepts blank as a cancel action' -Action {
    Set-TuiChoices -Choices @('9','j','','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'A blank JSON path must return to the operations menu without dispatching.'
}

Invoke-TuiTest -Name 'Operations menu displays its complete action hierarchy and returns on q' -Action {
    Set-TuiChoices -Choices @('q')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-TuiOutputContains -Text '9. Full read-only report' -Message 'Operations screen must render every top-level category.'
    Assert-TuiOutputContains -Text '5. Connect by SSH, RDP, or PowerShell' -Message 'Operations screen must make PowerShell remoting discoverable.'
}

Invoke-TuiTest -Name 'Operations menu ignores invalid top-level selections without dispatching' -Action {
    Set-TuiChoices -Choices @('invalid','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Invalid operations-menu choices must not dispatch commands.'
}

Invoke-TuiTest -Name 'Operations resize menu ignores invalid actions' -Action {
    Set-TuiChoices -Choices @('2','invalid','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Invalid resize choices must not dispatch.'
}

Invoke-TuiTest -Name 'Operations feature menu ignores unknown features and invalid states' -Action {
    Set-TuiChoices -Choices @('4','x','1','4','h','invalid','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'Invalid feature names or values must not dispatch.'
}

Invoke-TuiTest -Name 'Operations connection menu ignores invalid transport choices' -Action {
    Set-TuiChoices -Choices @('5','x','b')
    & $script:TuiOriginalOperationsMenu -Vm $script:TuiWindowsVm
    Assert-Tui -Condition ($script:TuiCommandInvocations.Count -eq 0) -Message 'An unknown SSH/RDP transport letter must not dispatch.'
}

Invoke-TuiTest -Name 'Real cg.cmd renders real console screens with fixture Azure reads only' -Action {
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $sandboxRoot = Join-Path $tempBase ('clagnos-tui-e2e-' + [guid]::NewGuid().ToString('N'))
    $fixtureBin = Join-Path $sandboxRoot 'fixture-bin'
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $fixtureBin -Force | Out-Null
    $process = $null
    $helpProcess = $null

    try {
        foreach ($relativePath in @('cg.cmd','clagnos.ps1','release-notes.md')) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot $relativePath) -Destination (Join-Path $sandboxRoot $relativePath) -Force
        }
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'modules') -Destination (Join-Path $sandboxRoot 'modules') -Recurse -Force
        New-Item -ItemType Directory -Path (Join-Path $sandboxRoot 'scripts') -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\clagnos-cli.ps1') -Destination (Join-Path $sandboxRoot 'scripts\clagnos-cli.ps1') -Force
        Copy-Item -LiteralPath (Join-Path $RepoRoot 'scripts\clagnos-cache-worker.ps1') -Destination (Join-Path $sandboxRoot 'scripts\clagnos-cache-worker.ps1') -Force
        foreach ($catalogRoot in @('packages\builtin\windows','packages\custom\windows','packages\builtin\linux','packages\custom\linux')) {
            New-Item -ItemType Directory -Path (Join-Path $sandboxRoot $catalogRoot) -Force | Out-Null
        }
        foreach ($fixtureName in @('az.cmd','az-fixture.ps1')) {
            Copy-Item -LiteralPath (Join-Path $RepoRoot (Join-Path 'tests\tui\fixtures' $fixtureName)) -Destination (Join-Path $fixtureBin $fixtureName) -Force
        }
        $netSourcePath = Join-Path $RepoRoot 'tests\tui\fixtures\net-fixture.cs'
        $netExePath = Join-Path $fixtureBin 'net.exe'
        if ([string]$PSVersionTable.PSEdition -eq 'Desktop') {
            $netSource = [string](Get-Content -LiteralPath $netSourcePath -Raw)
            Add-Type -TypeDefinition $netSource -Language CSharp -OutputType ConsoleApplication -OutputAssembly $netExePath -ErrorAction Stop | Out-Null
        }
        else {
            $windowsPowerShell = Get-Command powershell.exe -ErrorAction Stop
            $sourceLiteral = "'" + ([string]$netSourcePath).Replace("'", "''") + "'"
            $outputLiteral = "'" + ([string]$netExePath).Replace("'", "''") + "'"
            $compileCode = '$ErrorActionPreference = ''Stop''; $sourceText = Get-Content -LiteralPath ' + $sourceLiteral + ' -Raw; Add-Type -TypeDefinition $sourceText -Language CSharp -OutputType ConsoleApplication -OutputAssembly ' + $outputLiteral + ' | Out-Null'
            $encodedCompileCode = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($compileCode))
            $compileOutput = & $windowsPowerShell.Source -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCompileCode 2>&1
            if ($LASTEXITCODE -ne 0) { throw ('Could not build the temporary net.exe fixture: {0}' -f ((@($compileOutput) | ForEach-Object { [string]$_ }) -join ' ')) }
        }
        New-Item -ItemType Directory -Path (Join-Path $sandboxRoot '.azure-fixture') -Force | Out-Null
        $envLines = @(
            'SELECTED_AZURE_SUBSCRIPTION_ID=00000000-0000-4000-8000-000000000000',
            'SELECTED_VM_OS=windows',
            'SELECTED_AZURE_REGION=eastus',
            'SELECTED_VM_NAME=tui-fixture-vc',
            'VM_ADMIN_USER=fixture-manager',
            'VM_ADMIN_PASS=<runtime-secret>',
            'VM_ASSISTANT_USER=fixture-assistant',
            'VM_ASSISTANT_PASS=<runtime-secret>',
            'VM_SSH_PORT=22222',
            'VM_RDP_PORT=3390',
            'VM_ENABLE_HIBERNATION=true',
            'VM_ENABLE_NESTED_VIRTUALIZATION=true'
        )
        Set-Content -LiteralPath (Join-Path $sandboxRoot '.env') -Value $envLines -Encoding ASCII
        $azLogPath = Join-Path $sandboxRoot 'az-fixture.log'
        $netLogPath = Join-Path $sandboxRoot 'net-fixture.log'

        $systemRoot = [string]$env:SystemRoot
        $powershellRoot = Join-Path $systemRoot 'System32\WindowsPowerShell\v1.0'
        $pathParts = @($fixtureBin, (Join-Path $systemRoot 'System32'), $powershellRoot, $systemRoot)
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = Join-Path $systemRoot 'System32\cmd.exe'
        $processInfo.Arguments = ('/d /s /c ""{0}""' -f (Join-Path $sandboxRoot 'cg.cmd'))
        $processInfo.WorkingDirectory = $sandboxRoot
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.RedirectStandardInput = $true
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.EnvironmentVariables['PATH'] = $pathParts -join ';'
        $processInfo.EnvironmentVariables['AZURE_CONFIG_DIR'] = Join-Path $sandboxRoot '.azure-fixture'
        $processInfo.EnvironmentVariables['CLAGNOS_TUI_CACHE_ROOT'] = Join-Path $sandboxRoot '.clagnos-cache'
        $processInfo.EnvironmentVariables['CLAGNOS_TUI_DISABLE_BACKGROUND_CACHE_WORKER'] = '0'
        $processInfo.EnvironmentVariables['CLAGNOS_TUI_AZ_LOG'] = $azLogPath
        $processInfo.EnvironmentVariables['CLAGNOS_TUI_NET_LOG'] = $netLogPath
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        $workerCacheDirectory = Join-Path (Join-Path $sandboxRoot '.clagnos-cache') 'Clagnos\cache'
        $cacheDeadline = [DateTime]::UtcNow.AddSeconds(30)
        $workerCacheFiles = @()
        while ([DateTime]::UtcNow -lt $cacheDeadline -and $workerCacheFiles.Count -eq 0 -and -not $process.HasExited) {
            if (Test-Path -LiteralPath $workerCacheDirectory -PathType Container) {
                $workerCacheFiles = @(Get-ChildItem -LiteralPath $workerCacheDirectory -Filter 'azure-inventory-*.json' -File -ErrorAction SilentlyContinue | Where-Object { [string]$_.Name -match '^azure-inventory-[a-f0-9]+\.json$' })
            }
            if ($workerCacheFiles.Count -eq 0) { Start-Sleep -Milliseconds 100 }
        }
        $workerStatusFileForStartup = @(Get-ChildItem -LiteralPath $workerCacheDirectory -Filter 'azure-inventory-*.status.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
        $workerStartupStatus = if ($workerStatusFileForStartup.Count -gt 0) { [string](Get-Content -LiteralPath $workerStatusFileForStartup[0].FullName -Raw) } else { '(no worker status file)' }
        $workerStartupLog = if (Test-Path -LiteralPath $azLogPath) { (@(Get-Content -LiteralPath $azLogPath) -join '; ') } else { '(no Azure fixture calls)' }
        if ($workerCacheFiles.Count -ne 1) {
            $process.StandardInput.WriteLine('q')
            $process.StandardInput.Close()
            [void]$process.WaitForExit(10000)
            $stdoutTask.Wait()
            $stderrTask.Wait()
            throw ("The interactive cg.cmd background worker must publish a subscription-scoped inventory cache without blocking the welcome screen. Status={0}; az={1}; stdout={2}; stderr={3}" -f $workerStartupStatus,$workerStartupLog,[string]$stdoutTask.Result,[string]$stderrTask.Result)
        }
        $uiWorkerSnapshot = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $workerCacheFiles[0].FullName -Raw -ErrorAction Stop))
        Assert-Tui -Condition ([string]$uiWorkerSnapshot.VirtualMachines[0].name -eq 'tui-fixture-vc' -and [string]$uiWorkerSnapshot.VirtualMachines[0].ClagnosResourceGroup -eq 'rg-tui-fixture-eastus-g1') -Message ("The live TUI must import complete worker VM identity data. Snapshot={0}" -f (ConvertTo-Json -InputObject $uiWorkerSnapshot.VirtualMachines[0] -Depth 6 -Compress))

        foreach ($choice in @('1','1','p','1','b','b','m','3','b','b','o','1','b','5','q','b','b','2','b','3','b','q')) {
            $process.StandardInput.WriteLine([string]$choice)
        }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(90000)) {
            $process.Kill()
            throw 'The real cg.cmd console session exceeded its 90-second timeout.'
        }
        $process.WaitForExit()
        $stdoutTask.Wait()
        $stderrTask.Wait()
        $stdout = [string]$stdoutTask.Result
        $stderr = [string]$stderrTask.Result
        $plainOutput = [regex]::Replace($stdout, '\x1B\[[0-9;?]*[ -/]*[@-~]', '')
        $netTrace = if (Test-Path -LiteralPath $netLogPath) { @(Get-Content -LiteralPath $netLogPath) -join '; ' } else { '(net shim was not called)' }
        $azTrace = if (Test-Path -LiteralPath $azLogPath) { @(Get-Content -LiteralPath $azLogPath) -join '; ' } else { '(az fixture was not called)' }
        Assert-Tui -Condition ($process.ExitCode -eq 0) -Message ("cg.cmd returned {0}. Output: {1}; stderr: {2}; net: {3}; az: {4}" -f $process.ExitCode, $plainOutput, $stderr, $netTrace, $azTrace)

        foreach ($expectedText in @(
            'one tool for all common cloud operations',
            'Main menu',
            'Virtual computers',
            'Virtual computer: tui-fixture-vc',
            'Public IP: 203.0.113.8',
            'Public DNS: tui-fixture.eastus.cloudapp.azure.com',
            'SSH endpoint: tui-fixture.eastus.cloudapp.azure.com:22222',
            'PowerShell remoting endpoint: tui-fixture.eastus.cloudapp.azure.com:5985',
            'fixture-manager | password: <runtime-secret>',
            'fixture-assistant | password: <runtime-secret>',
            'Manage programs on tui-fixture-vc',
            'No packages are registered in the builtin catalog for windows.',
            'Components of tui-fixture-vc',
            'Operations for tui-fixture-vc',
            '1. Power, status, and repair',
            'p: PowerShell session',
            'Managed resource inventory',
            'Cloud subscriptions',
            'TUI Fixture Subscription'
        )) {
            Assert-Tui -Condition ($plainOutput.Contains($expectedText)) -Message ("Real cg.cmd output did not contain expected screen text: {0}. Process exit={1}; stdout={2}; stderr={3}; net={4}; az={5}" -f $expectedText,$process.ExitCode,$plainOutput,$stderr,$netTrace,$azTrace)
        }

        $azLines = @(Get-Content -LiteralPath $azLogPath -ErrorAction Stop)
        Assert-Tui -Condition ($azLines.Count -gt 0) -Message 'The process TUI scenario must exercise the isolated Azure CLI fixture.'
        $groupInventoryReads = @($azLines | Where-Object { $_ -match '(?i)(^|\s)group\s+list(\s|$)' })
        $resourceInventoryReads = @($azLines | Where-Object { $_ -match '(?i)(^|\s)resource\s+list\s+--resource-group(\s|$)' })
        $vmInventoryReads = @($azLines | Where-Object { $_ -match '(?i)(^|\s)vm\s+list\s+--show-details(\s|$)' })
        Assert-Tui -Condition ($groupInventoryReads.Count -eq 1) -Message 'The real cg.cmd process must load the resource-group cache once at startup.'
        Assert-Tui -Condition ($resourceInventoryReads.Count -eq 1) -Message 'The real cg.cmd process must load each managed resource group once at startup.'
        Assert-Tui -Condition ($vmInventoryReads.Count -eq 1) -Message 'The real cg.cmd process must cache VM detail and power state once for repeated screens.'
        $script:TuiTotalFixtureAzureReads += $azLines.Count
        $mutationPattern = '(?i)(^|\s)(create|update|delete|set|start|stop|restart|deallocate|resize|reapply|redeploy|attach|detach|power-off|run-command)(\s|$)'
        $mutatingFixtureCalls = @($azLines | Where-Object { $_ -match $mutationPattern })
        Assert-Tui -Condition ($mutatingFixtureCalls.Count -eq 0) -Message ('The actual cg.cmd scenario attempted a blocked Azure mutation: {0}' -f ($mutatingFixtureCalls -join '; '))
        Assert-Tui -Condition ($stderr -notmatch 'Blocked Azure mutation attempted') -Message 'The Azure fixture must not report any attempted mutating command.'

        $workerCacheRoot = Join-Path $sandboxRoot 'worker-cache'
        New-Item -ItemType Directory -Path $workerCacheRoot -Force | Out-Null
        $workerCachePath = Join-Path $workerCacheRoot 'inventory.json'
        $workerStatusPath = Join-Path $workerCacheRoot 'status.json'
        $workerRequestPath = Join-Path $workerCacheRoot 'refresh.request'
        $workerPackageRequestPath = Join-Path $workerCacheRoot 'package-refresh.json'
        $workerStopPath = Join-Path $workerCacheRoot 'stop.request'
        $workerAzLogPath = Join-Path $workerCacheRoot 'az-worker.log'
        $workerInfo = New-Object System.Diagnostics.ProcessStartInfo
        $workerInfo.FileName = (Get-Command powershell.exe -ErrorAction Stop).Source
        $workerInfo.UseShellExecute = $false
        $workerInfo.CreateNoWindow = $true
        $workerInfo.RedirectStandardInput = $true
        $workerInfo.RedirectStandardOutput = $true
        $workerInfo.RedirectStandardError = $true
        $workerInfo.EnvironmentVariables['PATH'] = $pathParts -join ';'
        $workerInfo.EnvironmentVariables['AZURE_CONFIG_DIR'] = Join-Path $sandboxRoot '.azure-fixture'
        $workerInfo.EnvironmentVariables['CLAGNOS_TUI_AZ_LOG'] = $workerAzLogPath
        $workerArguments = @(
            '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $RepoRoot 'scripts\clagnos-cache-worker.ps1'),
            '-SubscriptionId','00000000-0000-4000-8000-000000000000','-CachePath',$workerCachePath,'-StatusPath',$workerStatusPath,
            '-RequestPath',$workerRequestPath,'-PackageRequestPath',$workerPackageRequestPath,'-StopPath',$workerStopPath,
            '-OwnerProcessId',[string]$PID,'-RepositoryRoot',$RepoRoot,'-Once'
        )
        $workerInfo.Arguments = (@($workerArguments | ForEach-Object { Convert-ClagnosProcessArgument -Value ([string]$_) }) -join ' ')
        $workerProcess = New-Object System.Diagnostics.Process
        $workerProcess.StartInfo = $workerInfo
        [void]$workerProcess.Start()
        $workerStdoutTask = $workerProcess.StandardOutput.ReadToEndAsync()
        $workerStderrTask = $workerProcess.StandardError.ReadToEndAsync()
        $workerProcess.StandardInput.Close()
        if (-not $workerProcess.WaitForExit(30000)) {
            $workerProcess.Kill()
            throw 'The fixture background inventory worker exceeded its 30-second timeout.'
        }
        $workerProcess.WaitForExit()
        $workerStdoutTask.Wait()
        $workerStderrTask.Wait()
        Assert-Tui -Condition ($workerProcess.ExitCode -eq 0) -Message ("The background cache worker returned {0}. stdout={1}; stderr={2}" -f $workerProcess.ExitCode,[string]$workerStdoutTask.Result,[string]$workerStderrTask.Result)
        $workerSnapshot = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $workerCachePath -Raw -ErrorAction Stop))
        Assert-Tui -Condition (@($workerSnapshot.Groups).Count -eq 1 -and @($workerSnapshot.VirtualMachines).Count -eq 1 -and @($workerSnapshot.Resources).Count -ge 5) -Message ("The background worker must atomically publish the managed inventory snapshot. Groups={0}; VMs={1}; Resources={2}; Snapshot={3}" -f @($workerSnapshot.Groups).Count,@($workerSnapshot.VirtualMachines).Count,@($workerSnapshot.Resources).Count,(ConvertTo-Json -InputObject $workerSnapshot -Depth 4 -Compress))
        Assert-Tui -Condition ([string]$workerSnapshot.VirtualMachines[0].name -eq 'tui-fixture-vc' -and [string]$workerSnapshot.VirtualMachines[0].ClagnosResourceGroup -eq 'rg-tui-fixture-eastus-g1') -Message 'The background worker snapshot must preserve usable VM identity fields.'
        $workerStatus = ConvertFrom-JsonCompat -InputObject ([string](Get-Content -LiteralPath $workerStatusPath -Raw -ErrorAction Stop))
        Assert-Tui -Condition ([string]$workerStatus.State -eq 'ready') -Message 'The background worker must publish its completion state.'
        $workerAzLines = @(Get-Content -LiteralPath $workerAzLogPath -ErrorAction Stop)
        Assert-Tui -Condition (@($workerAzLines | Where-Object { $_ -match '(?i)(^|\s)group\s+list(\s|$)' }).Count -eq 1) -Message 'The worker must scan resource groups once per refresh.'
        Assert-Tui -Condition (@($workerAzLines | Where-Object { $_ -match '(?i)(^|\s)resource\s+list\s+--resource-group(\s|$)' }).Count -eq 1) -Message 'The worker must scan the managed group resource list once.'
        Assert-Tui -Condition (@($workerAzLines | Where-Object { $_ -match '(?i)(^|\s)vm\s+list\s+--show-details(\s|$)' }).Count -eq 1) -Message 'The worker must scan detailed VM status once.'
        $workerMutations = @($workerAzLines | Where-Object { $_ -match $mutationPattern })
        Assert-Tui -Condition ($workerMutations.Count -eq 0) -Message ('The background worker attempted an Azure mutation: {0}' -f ($workerMutations -join '; '))
        $script:TuiTotalFixtureAzureReads += $workerAzLines.Count
        $workerProcess.Dispose()

        $helpProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $helpProcessInfo.FileName = Join-Path $systemRoot 'System32\cmd.exe'
        $helpProcessInfo.Arguments = ('/d /s /c ""{0}" help resize"' -f (Join-Path $sandboxRoot 'cg.cmd'))
        $helpProcessInfo.WorkingDirectory = $sandboxRoot
        $helpProcessInfo.UseShellExecute = $false
        $helpProcessInfo.CreateNoWindow = $true
        $helpProcessInfo.RedirectStandardInput = $true
        $helpProcessInfo.RedirectStandardOutput = $true
        $helpProcessInfo.RedirectStandardError = $true
        $helpProcessInfo.EnvironmentVariables['PATH'] = $pathParts -join ';'
        $helpProcessInfo.EnvironmentVariables['AZURE_CONFIG_DIR'] = Join-Path $sandboxRoot '.azure-fixture'
        $helpProcessInfo.EnvironmentVariables['CLAGNOS_TUI_DISABLE_BACKGROUND_CACHE_WORKER'] = '1'
        $helpProcessInfo.EnvironmentVariables['CLAGNOS_TUI_AZ_LOG'] = $azLogPath
        $helpProcessInfo.EnvironmentVariables['CLAGNOS_TUI_NET_LOG'] = $netLogPath
        $helpProcess = New-Object System.Diagnostics.Process
        $helpProcess.StartInfo = $helpProcessInfo
        [void]$helpProcess.Start()
        $helpStdoutTask = $helpProcess.StandardOutput.ReadToEndAsync()
        $helpStderrTask = $helpProcess.StandardError.ReadToEndAsync()
        $helpProcess.StandardInput.Close()
        if (-not $helpProcess.WaitForExit(30000)) {
            $helpProcess.Kill()
            throw 'The cg.cmd resize-help argument passthrough exceeded its 30-second timeout.'
        }
        $helpProcess.WaitForExit()
        $helpStdoutTask.Wait()
        $helpStderrTask.Wait()
        $helpOutput = [string]$helpStdoutTask.Result
        $helpErrorOutput = [string]$helpStderrTask.Result
        Assert-Tui -Condition ($helpProcess.ExitCode -eq 0 -and $helpOutput.Contains('Command: resize') -and $helpOutput.Contains('Usage:')) -Message ("cg.cmd did not preserve command-line help arguments. Exit={0}; output={1}; stderr={2}" -f $helpProcess.ExitCode,$helpOutput,$helpErrorOutput)
        Assert-Tui -Condition ($helpErrorOutput -notmatch 'null-valued expression') -Message 'cg.cmd command mode must not fall through to the interactive TUI when arguments are supplied.'
    }
    finally {
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(5000) }
            }
            catch { }
            $process.Dispose()
        }
        if ($null -ne $helpProcess) { $helpProcess.Dispose() }
        $resolvedSandbox = [System.IO.Path]::GetFullPath($sandboxRoot)
        $resolvedTempBase = [System.IO.Path]::GetFullPath($tempBase).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        $expectedPrefix = $resolvedTempBase + 'clagnos-tui-e2e-'
        if (-not $resolvedSandbox.StartsWith($expectedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw ('Refusing to remove an unexpected TUI fixture path: {0}' -f $resolvedSandbox)
        }
        for ($cleanupAttempt = 0; $cleanupAttempt -lt 20 -and (Test-Path -LiteralPath $resolvedSandbox); $cleanupAttempt++) {
            try {
                Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force -ErrorAction Stop
            }
            catch {
                if ($cleanupAttempt -ge 19) { throw }
                Start-Sleep -Milliseconds 250
            }
        }
    }
}

$passedCount = @($script:TuiTestResults | Where-Object { $_.Passed }).Count
$failedResults = @($script:TuiTestResults | Where-Object { -not $_.Passed })
[Console]::WriteLine('')
[Console]::WriteLine(('TUI coverage summary -> Passed: {0}, Failed: {1}, native Azure CLI calls: {2}, fixture Azure reads: {3}, real dispatcher calls: {4}' -f $passedCount, $failedResults.Count, $script:TuiTotalNativeAzureCalls, $script:TuiTotalFixtureAzureReads, $script:TuiTotalRealDispatcherCalls))
if ($failedResults.Count -gt 0) { exit 1 }
