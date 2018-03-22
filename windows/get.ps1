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

function Get-MachineKeys
{
    $machineKeysFolderPath = 'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys'
    icacls $machineKeysFolderPath /t /c > c:\temp\BeforeScript_permissions.txt 
    #Check for OS version
    if ($OSVersion.Major -eq 6)
    {
        #IIS 7 and above
        $MachineKeyPath = "$env:SystemDrive\ProgramData\Microsoft\Crypto\RSA\MachineKeys\"
    }
    else
    {
        #IIS 6
        $MachineKeyPath = "$env:SystemDrive\Documents and Settings\All Users\Application Data\Microsoft\Crypto\RSA\MachineKeys\"
    }
    $MachineGuid = (Get-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Cryptography\").MachineGuid
    "MachineGuid in Registry = {0}" -f $MachineGuid | Out-File $logFile


}
function Get-TermService
{
    Get-Service -Name TermService
}
function Confirm-RdpEnabled
{
    Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections'
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

function Get-VMHealth
{
    $WinEventsPath = "C:\WindowsAzure";
    #
    # Inspecting TransparentInstaller.log 
    #
    $TransparentInstaller = Get-ChildItem -Path $WinEventsPath -Filter * -Recurse -Include TransparentInstaller.log
    if ($TransparentInstaller)
    {
    
        if($TransparentInstaller.count -le 1)
        {
            Write-Verbose ('Found file '+ $TransparentInstaller.FullName)
            $lines = Get-Content $TransparentInstaller
    
    
            #
            # Inspecting VM Health Signals
            $fullVMHealthSignals = $lines | Select-String '{"reportTime":"'
            if ($fullVMHealthSignals)
            {
                if ($fullVMHealthSignals.count -gt 0)
                {
    
                    for($i=0; $i -le ($fullVMHealthSignals.count); $i++)
                    {
                        # checking if next entry is the same as the tool logs it 2x
                        if ($fullVMHealthSignals[$i].Line -ne $fullVMHealthSignals[$i+1].Line)
                        {
                            $jsonline = $fullVMHealthSignals[$i].Line | ConvertFrom-Json
                            $lineTimeCreated = ([datetime]$jsonline.reportTime).ToUniversalTime()
                            if ( ($lineTimeCreated -ge $StartUtcTime) -and ($lineTimeCreated -le $EndUtcTime) )
                            {
                                $VMHealthSignalsHistory += $jsonline
                            }
                        }
                    }
                    
                    # getting the last state available 
                    $VMHealthSignalsLast = $fullVMHealthSignals[-1].Line | ConvertFrom-Json
                }
            }
            
            $termServiceState = $VMHealthSignalsLast.services | where {$_.name -eq "TermService"};
    
            # Dump Data to screen
            cls;
            $findings = 0;
            
            "Report Time {0}" -f $VMHealthSignalsLast.reportTime;
            "UTC: {0}" -f $VMHealthSignalsLast.systemInfo.windows.realTimeIsUniversal;
            if ($VMHealthSignalsLast.remoteAccess.windows.rdpEnabled -eq $false) {
                Write-Host "Error: RDP is disabled, please run C:\WinGuestLite\Enable-RDP.ps1 to resolve";
                $findings = 1;
                }
            if ($termServiceState.state -ne "Running") {
                Write-Host "Error: RDP service is stopped, please run C:\WinGuestLite\Start-RDP.ps1 to resolve";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.remoteAccess.windows.rdpFirewallAccess -ne "Allowed") {
                Write-Host "Error: RDP is blocked by Windows Firewall, run C:\WinGuestLite\Fix-RDPFirewall.ps1 to resolve";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.remoteAccess.windows.rdpAllowedUsers -eq $null) {
                Write-Host "Error: There are no RDP allowed users on the Server.";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.remoteAccess.windows.rdpPort -ne 3389) {
                Write-Host "Warning: RDP Port is not set to TCP 3389, run C:\WinGuestLite\Fix-RDPPort.ps1 to resolve";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.accounts.windows.adminAccountPasswordExpired -eq $true) {
                Write-Host "Warning: There is an admin account with expired password.";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.accounts.windows.adminAccountDisabled -eq $true) {
                Write-Host "Warning: There is an admin account that is disabled.";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.systemInfo.windows.isOsEval -eq $true) {
                Write-Host "Warning: Windows is running in evaulation mode.";
                $findings = 1;
                }
            if ($VMHealthSignalsLast.remoteAccess.windows.rdpTcpListenerMaxConnections -ne $null) {
                "Info: Max RDP Listener Connections: {0}" -f $VMHealthSignalsLast.remoteAccess.windows.rdpTcpListenerMaxConnections;
                }
            if ($VMHealthSignalsLast.remoteAccess.windows.rdsLicensingStatus -eq $true) {
                Write-Host "Info: RDS Licensing Status: {0}." -f $VMHealthSignalsLast.remoteAccess.windows.rdsLicensingStatus;
                $findings = 1;
                }
            if ($VMHealthSignalsLast.systemInfo.windows.domainRole -ne "StandaloneServer") {
                Write-Host "Info: Server has ADDS role installed.";
                $findings = 1;
                }
    
    
            if ($findings -eq 0) {
                Write-Host "No RDP configuration issues discovered.";
                }
    
            #$VMHealthSignalsLast.remoteAccess.windows;
            #$VMHealthSignalsLast.accounts.windows;
            #$VMHealthSignalsLast.networkAdapters;
    
        }
        else
        {
            Write-Verbose 'More than one TransparentInstaller.log available'
        }
    
    }
    else
    {
        Write-Verbose 'Guest Agent log file TransparentInstaller.log not available'
    }
}