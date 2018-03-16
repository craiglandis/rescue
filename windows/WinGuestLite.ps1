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