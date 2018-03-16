function GetRdpPort
{
    $port = (Get-ItemProperty -Path $rdpTcpRegistryRegistryKey).$rdpPortRegistryValue
    # Same as "return port ?? 0;" currently used in GetRdpPort() in CollectVMHealth
    # Note that the PortNumber reg value exists and is set to 3389 by default, so it would be rare for the PortNumber reg value to not be present at all
    if (!$port){$port = 0} 
    return $port
}

function GetFirewallAccessForPort($port)
{
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

Set-Variable -Option Constant -Name terminalServerRegistryKey -Value 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-Variable -Option Constant -Name rdpTcpRegistryRegistryKey -Value "$($terminalServerRegistryKey)\WinStations\RDP-Tcp"
Set-Variable -Option Constant -Name rdpPortRegistryValue -Value 'PortNumber'
# https://msdn.microsoft.com/en-us/library/windows/desktop/aa364724%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
# https://msdn.microsoft.com/en-us/library/windows/desktop/aa366456(v=vs.85).aspx
Set-Variable -Option Constant -Name NET_FW_IP_PROTOCOL_TCP -Value 6
Set-Variable -Option Constant -Name NET_FW_RULE_DIR_IN -Value 1
Set-Variable -Option Constant -Name NET_FW_ACTION_BLOCK -Value 0
Set-Variable -Option Constant -Name NET_FW_ACTION_ALLOW -Value 1

GetFirewallAccessForPort(GetRdpPort)