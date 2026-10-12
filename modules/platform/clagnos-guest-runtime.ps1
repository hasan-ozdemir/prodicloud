# Imported runtime region: test-guest.

















# Handles Get-ClagnosConnectionDisplayModel.
function Get-ClagnosConnectionDisplayModel {
    param(
        [hashtable]$Context,
        [string]$ManagerUser,
        [string]$AssistantUser,
        [string]$SshPort,
        [string]$RdpPort = '3389',
        [string]$PowerShellPort = '5985',
        [switch]$IncludeRdp,
        [switch]$IncludePowerShellRemoting
    )

    $vmConnectionInfo = Get-ClagnosVmDetails -Context $Context
    $publicIP = [string]$vmConnectionInfo.PublicIP
    $vmFqdn = [string]$vmConnectionInfo.VmFqdn
    $resolvedHost = if ([string]::IsNullOrWhiteSpace([string]$vmFqdn)) { $publicIP } else { $vmFqdn }

    $sshConnections = @(
        [pscustomobject]@{
            User = $ManagerUser
            Command = ("ssh -p {0} {1}@{2}" -f $SshPort, $ManagerUser, $resolvedHost)
        },
        [pscustomobject]@{
            User = $AssistantUser
            Command = ("ssh -p {0} {1}@{2}" -f $SshPort, $AssistantUser, $resolvedHost)
        }
    )

    $model = [ordered]@{
        PublicIP = $publicIP
        VmFqdn = $vmFqdn
        ConnectionHost = $resolvedHost
        SshConnections = $sshConnections
    }

    if ($IncludeRdp) {
        $rdpConnections = @(
            [pscustomobject]@{
                User = $ManagerUser
                Username = (".\{0}" -f $ManagerUser)
                Command = ("mstsc /v:{0}:{1}" -f $resolvedHost, $RdpPort)
            },
            [pscustomobject]@{
                User = $AssistantUser
                Username = (".\{0}" -f $AssistantUser)
                Command = ("mstsc /v:{0}:{1}" -f $resolvedHost, $RdpPort)
            }
        )
        $model["RdpConnections"] = $rdpConnections
    }

    if ($IncludePowerShellRemoting) {
        $trustedHostCommand = ('Set-Item WSMan:\localhost\Client\TrustedHosts -Value "{0}" -Force' -f $resolvedHost)
        $enterSessionCommand = ('$credential = Get-Credential ''.\{0}''; Enter-PSSession -ComputerName {1} -Port {2} -Credential $credential -Authentication Negotiate' -f $ManagerUser, $resolvedHost, $PowerShellPort)
        $invokeCommand = ('$credential = Get-Credential ''.\{0}''; Invoke-Command -ComputerName {1} -Port {2} -Credential $credential -Authentication Negotiate -ScriptBlock {{ hostname; whoami }}' -f $ManagerUser, $resolvedHost, $PowerShellPort)
        $model["PowerShellConnections"] = @(
            [pscustomobject]@{
                User = $ManagerUser
                Username = (".\{0}" -f $ManagerUser)
                Port = [string]$PowerShellPort
                TrustedHostsCommand = [string]$trustedHostCommand
                EnterPSSessionCommand = [string]$enterSessionCommand
                InvokeCommand = [string]$invokeCommand
            }
        )
    }

    return $model
}


