
<#
.SYNOPSIS
    Sets RDP to use the default port 3389 and restarts TermService
.DESCRIPTION
    Sets PortNumber DWORD registry value to 3389 under HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp
.PARAMETER noPrompt
    Suppress user acceptance prompt
.EXAMPLE
    PS C:\> .\Set-DefaultRdpPort.ps1
#>

param(
    [switch]$noPrompt
)

function Start-TermService
{

}

function Set-RdpPort
{

}
function Enable-Rdp
{
    
}

function Set-MachineKeys
{

}


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

function Set-RdpPort
{


    $scriptStartTime = get-date
    $scriptStartTimeString = get-date $scriptStartTime -format 'yyyyMMddHHmmss'
    $scriptPath = $MyInvocation.MyCommand.Path
    $logFile = "$($scriptPath.TrimEnd('.ps1'))_$scriptStartTimeString.log"

    $path = '"HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp"'
    $name = 'PortNumber'
    $value = 3389
    $type = 'DWORD'

    write-host ""
    write-log "Log file: $logFile" -console
    write-host ""

    if ($noPrompt)
    {
        write-log "User acceptance prompt overridden with -noPrompt" -console
        write-log "Setting RDP to use port $value and restarting TermService" -console
        $answer = 'Y'
    }
    else 
    {
        $message = "Set RDP to use $value and restart TermService [Y/N]?"
        write-log $message
        $answer = read-host $message
        write-log $answer
        write-host ""
    }

    if ($answer.ToUpper() -eq 'Y')
    {
        # Get current value
        $command = "get-itemproperty -path $path -name $name"
        write-log "Running: $command" -console
        $result = invoke-expression -command $command
        write-log "Current RDP port: $($result.PortNumber)" -console

        # Set default value
        $command = "set-itemproperty -path $path -name $name -value $value -type $type"
        write-log "Running: $command" -console
        $result = invoke-expression $command

        # Restart TermService
        $command = "restart-service -name TermService -force"
        write-log "Running: $command" -console
        $result = invoke-expression $command

        # Get current value again
        $command = "get-itemproperty -path $path -name $name"
        write-log "Running: $command" -console
        $result = invoke-expression -command $command
        write-log "Current RDP port: $($result.PortNumber)" -console    

    # Get TermService status
    $command = "get-service -name TermService"
    write-log "Running: $command" -console
    $result = invoke-expression $command
    write-log "TermService status: $($result.Status)" -console
    }
}

<#

Disable-NetFirewallRule -DisplayGroup "Remote Desktop"
Get-NetFirewallRule -DisplayGroup "Remote Desktop"
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp' -name 'PortNumber' 3390 -Type Dword
Restart-Service -Name TermService -Force
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp' -name 'PortNumber'
Stop-Service -Name TermService -Force
Get-Service -Name TermService
Restart-Service -Name RdAgent
Get-Service -Name RdAgent

####################
####################


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





        # Inspecting VM Health Signals
        #

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
#
# Inspecting TransparentInstaller.log  
#

####################
####################


Start-Service -Name TermService;
Get-Service -Name TermService;

####################
####################


function GetRdpPort
{
    $port = (Get-ItemProperty -Path $rdpTcpRegistryRegistryKey).$rdpPortRegistryValue
    # This is same as "return port ?? 0;" currently used in GetRdpPort() in CollectVMHealth
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

####################
####################

Invoke-RestMethod -Method GET -Uri http://169.254.169.254/metadata/instance?api-version=2017-04-02 -Headers @{"Metadata"="True"} | ConvertTo-JSON -Depth 99

####################
####################

Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections'

####################
####################

write-Host "Enabling RDP";
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections' 0 -Type Dword -ErrorAction SilentlyContinue;
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name 'fDenyTSConnections' 0 -Type Dword -ErrorAction SilentlyContinue;
Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections' -ErrorAction SilentlyContinue;
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name 'fDenyTSConnections' -ErrorAction SilentlyContinue;
Restart-Service -Name TermService -Force;
Write-Host "Completed Enabling RDP";

####################
####################


Write-Host "Fixing Firewall rules";
Enable-NetFirewallRule -DisplayGroup "Remote Desktop";
Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)";
Enable-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)";
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile' -name 'EnableFirewall' 1 -Type Dword;
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile' -name 'EnableFirewall' 1 -Type Dword;
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile' -name 'EnableFirewall' 1 -Type Dword;
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile" -Name "DoNotAllowExceptions" -ErrorAction SilentlyContinue;
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile" -Name "DoNotAllowExceptions" -ErrorAction SilentlyContinue;
Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile" -Name "DoNotAllowExceptions" -ErrorAction SilentlyContinue;
Write-Host "Completed fixing Firewall rules";

####################
####################

Start-Service -Name TermService;
Get-Service -Name TermService;

#>