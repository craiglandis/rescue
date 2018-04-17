
function write-log
{
    param(
        [string]$status, 
        [switch]$console
    )    

    $utcString = "[$(get-date (get-date).ToUniversalTime() -Format yyyy-MM-ddTHH:mm:ssZ)]"
    ("$utcString $status" | out-string).Trim() | out-file $logFile -append

    if ($console)
    {
        write-host ("$utcString $status" | out-string).Trim()
    }
}

function Get-InstanceMetaData
{
    invoke-restmethod -Method GET -Uri http://169.254.169.254/metadata/instance?api-version=2017-04-02 -Headers @{'Metadata'='True'} | ConvertTo-Json -Depth 99
}

function Get-RdpPort
{
    $terminalServerRegistryKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
    $rdpTcpRegistryRegistryKey = "$($terminalServerRegistryKey)\WinStations\RDP-Tcp"
    $rdpPortRegistryValue = 'PortNumber'
    $port = (Get-ItemProperty -Path $rdpTcpRegistryRegistryKey).$rdpPortRegistryValue
    if (!$port){$port = 0} 
    return $port
}

function Get-RdpFirewallRule($port)
{

    # Get-NetFirewallRule isn't on 2008R2
    # Get-NetFirewallRule -DisplayGroup "Remote Desktop"
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa364724%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa366456(v=vs.85).aspx
    $NET_FW_IP_PROTOCOL_TCP = 6
    $NET_FW_RULE_DIR_IN = 1
    $NET_FW_ACTION_BLOCK = 0
    $NET_FW_ACTION_ALLOW = 1

    # Get firewall rules where localport is the configured RDP port number and protocol is TCP
    $rules = (new-object -ComObject hnetcfg.fwpolicy2).rules | where {$_.localports -contains $port -and $_.protocol -eq $NET_FW_IP_PROTOCOL_TCP}

    # if no rules found = blocked (tim) RuleNotFoundForPort (craig)
    # if tcp rule found but enabled is false = blocked (tim) RuleDisabled (craig)
    # if tcp rule found and enabled is true, but action is blocked = blocked (tim) RuleIsBlockingPort (craig)
    # if tcp rule found and enabled is true, and action is allowed = allowed (tim) allowed (craig)
    # if we find non-default local or remote addresses or remote ports = investigate (tim) RuleHasIPAddressRestriction (craig)
    # if we find non-default remote ports = RuleHasNonDefaultOutboundPortRestriction (craig)
    # (alternate approach) dump the specific rule's properties into json that let us determine the above conditions (craig)

    foreach ($rule in $rules) {
        if ($rule.Enabled -eq $true -and $rule.Direction -eq $NET_FW_RULE_DIR_IN) 
        {
            if ($rule.Action -ne $NET_FW_ACTION_ALLOW) 
            {
                $rdpFirewallAccess = 'Blocked'
            }
            else 
            {
                if ($rule.RemoteAddresses -ne '*' -or $rule.LocalAddresses -ne '*' -or $rule.RemotePorts -ne '*') 
                {
                    $rdpFirewallAccess = 'Investigate'
                }
                else 
                {
                    $rdpFirewallAccess = 'Allowed'
                }
            }
        }
        else 
        {
            $rdpFirewallAccess = 'Blocked'
        }
    }
    return $rdpFirewallAccess
}

$rdpPort = Get-RdpPort
Get-RdpFirewallRule -port $rdpPort