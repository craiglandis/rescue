#================================================================================
# Disable-NetFirewallRule -DisplayName 'Remote Desktop - User Mode (TCP-In)';Disable-NetFirewallRule -DisplayName 'Remote Desktop - User Mode (UDP-In)'
# netsh advfirewall firewall set rule name="Remote Desktop - User Mode (TCP-In)" new enable=no
function write-log
{
    param(
        [string]$status, 
        [switch]$logOnly,
        [switch]$noTimestamp,
        [string]$color = 'white'
    )    

    $utcString = "$(get-date (get-date).ToUniversalTime() -Format "yyyy-MM-dd HH:mm:ssZ")"

    if ($logOnly)
    {
        ("$utcString $status" | out-string).Trim() | out-file $logFile -append
    }
    else 
    {
        if ($noTimestamp)
        {
            write-host $status.Trim() -ForegroundColor $color
        }
        else 
        {
            write-host $($utcString.Split(' ')[1]) -nonewline 
            write-host " $(($status | out-string).Trim())" -ForegroundColor $color
        }
        ("$utcString $status" | out-string).Trim() | out-file $logFile -append
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
    write-log "Checking $($terminalServerRegistryKey)\WinStations\RDP-Tcp\$($rdpPortRegistryValue)"
    $port = (Get-ItemProperty -Path $rdpTcpRegistryRegistryKey).$rdpPortRegistryValue
    write-log "$($rdpPortRegistryValue): $port"
    if (!$port){$port = 0}
    return $port
}

function Add-FirewallRule {
    param( 
       $name,
       $tcpPorts,
       $appName = $null,
       $serviceName = $null
    )
     $fw = New-Object -ComObject hnetcfg.fwpolicy2 
     $rule = New-Object -ComObject HNetCfg.FWRule
         
     $rule.Name = $name
     if ($appName -ne $null) { $rule.ApplicationName = $appName }
     if ($serviceName -ne $null) { $rule.serviceName = $serviceName }
     $rule.Protocol = 6 #NET_FW_IP_PROTOCOL_TCP
     $rule.LocalPorts = $tcpPorts
     $rule.Enabled = $true
     $rule.Grouping = "@firewallapi.dll,-23255"
     $rule.Profiles = 7 # all
     $rule.Action = 1 # NET_FW_ACTION_ALLOW
     $rule.EdgeTraversal = $false
     
     $fw.Rules.Add($rule)
 }

function Get-RdpFirewallRule($port)
{
    # Get-NetFirewallRule isn't on 2008 R2
    # Get-NetFirewallRule -DisplayGroup "Remote Desktop"
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa364724%28v=vs.85%29.aspx?f=255&MSPPError=-2147217396
    # https://msdn.microsoft.com/en-us/library/windows/desktop/aa366456(v=vs.85).aspx
    $NET_FW_IP_PROTOCOL_TCP = 6
    $NET_FW_IP_PROTOCOL_UDP = 17
    $NET_FW_RULE_DIR_IN = 1
    $NET_FW_RULE_DIR_OUT = 2
    $NET_FW_ACTION_BLOCK = 0
    $NET_FW_ACTION_ALLOW = 1

    # Get firewall rules where localport is the configured RDP port number and protocol is TCP
    write-log "Checking for Windows Firewall rules allowing inbound port $port"
    $firewall = new-object -ComObject hnetcfg.fwpolicy2
    $firewallRules = $firewall.rules
    $rdpFirewallRules = $firewallRules | where {$_.localports -contains $port -and $_.protocol -eq $NET_FW_IP_PROTOCOL_TCP}
    #$rdpFirewallRules = $firewallRules | where {$_.localports -contains $port -and ($_.protocol -eq $NET_FW_IP_PROTOCOL_TCP -or $_.protocol -eq $NET_FW_IP_PROTOCOL_UDP)} 
    
    # if no rules found = blocked (tim) RuleNotFoundForPort (craig)
    # if tcp rule found but enabled is false = blocked (tim) RuleDisabled (craig)
    # if tcp rule found and enabled is true, but action is blocked = blocked (tim) RuleIsBlockingPort (craig)
    # if tcp rule found and enabled is true, and action is allowed = allowed (tim) allowed (craig)
    # if we find non-default local or remote addresses or remote ports = investigate (tim) RuleHasIPAddressRestriction (craig)
    # if we find non-default remote ports = RuleHasNonDefaultOutboundPortRestriction (craig)
    # (alternate approach) dump the specific rule's properties into json that let us determine the above conditions (craig)
    
    if ($rdpFirewallRules)
    {
        if(!($rdpFirewallRules | where {$_.Enabled}))
        {
            write-log "RDP firewall rule is disabled:" -color red
            write-log "" -noTimestamp
            write-log $($rdpFirewallRules | format-table -autosize Name,Enabled,LocalPorts,@{Name='Direction';Expression={if($_.Direction -eq $NET_FW_RULE_DIR_IN){'Inbound'}elseif($_.Direction -eq $NET_FW_RULE_DIR_OUT){'Outbound'}else{$_.Direction}}} | out-string) -noTimestamp -color red
            write-log "" -noTimestamp
            $result = read-host -Prompt "Do you want to enable them to allow inbound RDP connectivity [Y/N]?"
            if ($result.ToUpper() -eq 'Y')
            {
                foreach ($rule in $rdpFirewallRules) {
                    $rule.Enabled = $true
                }
                Get-RdpFirewallRule -port $port
            }
        }
        else 
        {
            foreach ($rule in $rdpFirewallRules) {
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
        }
    }
    else 
    {
        write-log "No Windows Firewall rules found for port $port"
        $rdpFirewallAccess = 'Blocked'
    }

    if ($rdpFirewallAccess -eq 'Allowed')
    {
        write-log "Windows Firewall rule(s) allowing inbound port $port connectivity:" -color green
        write-log "" -noTimestamp
        write-log $($rdpFirewallRules | format-table -autosize Name,Enabled,LocalPorts,@{Name='Direction';Expression={if($_.Direction -eq $NET_FW_RULE_DIR_IN){'Inbound'}elseif($_.Direction -eq $NET_FW_RULE_DIR_OUT){'Outbound'}else{$_.Direction}}} | out-string) -noTimestamp -color green
    }
    return $rdpFirewallAccess
}

$startTime = get-date
$scriptPath = split-path -path $MyInvocation.MyCommand.Path
$scriptName = split-path -path $MyInvocation.MyCommand.Path -leaf
$logFile = "$scriptPath\$($scriptName.Split('.')[0]).log"
if (test-path $logFile)
{
    $renamedLogFile = "$((split-path $logFile -leaf).Split('.')[0]).$(get-date (get-date).ToUniversalTime() -f yyyyMMddhhmmss).log"
    rename-item $logFile $renamedLogFile
    write-log "Renamed existing log file to $renamedLogFile" -console
}
new-item -path $logFile -ItemType File -force | out-null
write-log "Created log file: $logFile" -console

$rdpPort = Get-RdpPort
$rdpFirewallAccess = Get-RdpFirewallRule -port $rdpPort