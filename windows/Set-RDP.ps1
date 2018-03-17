
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
    Start-Service -Name TermService
}

function Set-RdpPort
{

}
function Enable-Rdp
{
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections' 0 -Type Dword -ErrorAction SilentlyContinue
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name 'fDenyTSConnections' 0 -Type Dword -ErrorAction SilentlyContinue
    Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections' -ErrorAction SilentlyContinue
    Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name 'fDenyTSConnections' -ErrorAction SilentlyContinue
    Restart-Service -Name TermService -Force        
}

function Set-MachineKeys
{
    $machineKeysFolderPath = 'C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys'
    icacls $machineKeysFolderPath /t /c > c:\temp\BeforeScript_permissions.txt 
    takeown /f $machineKeysFolderPath /a /r 
    icacls $machineKeysFolderPath /t /c /grant "NT AUTHORITY\System:(F)" 
    icacls $machineKeysFolderPath /t /c /grant " NT AUTHORITY\NETWORK SERVICE:(R)" 
    icacls $machineKeysFolderPath /t /c /grant "BUILTIN\Administrators:(F)" 
    icacls $machineKeysFolderPath /t /c > c:\temp\AfterScript_permissions.txt 
    restart-service TermService –force    
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

function Set-RdpFirewallRule
{
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    Enable-NetFirewallRule -DisplayName "File and Printer Sharing (Echo Request - ICMPv4-In)"
    Enable-NetFirewallRule -DisplayName "Windows Remote Management (HTTP-In)"
    
    $firewallPolicyRegKey = 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy' 
    Set-ItemProperty -Path "$firewallPolicyRegKey\DomainProfile" -name 'EnableFirewall' 1 -Type 'DWORD'
    Set-ItemProperty -Path "$firewallPolicyRegKey\PublicProfile" -name 'EnableFirewall' 1 -Type 'DWORD'
    Set-ItemProperty -Path "$firewallPolicyRegKey\FirewallPolicy\StandardProfile" -name 'EnableFirewall' 1 -Type 'DWORD'
    Remove-ItemProperty -Path "$firewallPolicyRegKey\DomainProfile" -Name 'DoNotAllowExceptions' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$firewallPolicyRegKey\PublicProfile" -Name 'DoNotAllowExceptions' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "$firewallPolicyRegKey\StandardProfile" -Name 'DoNotAllowExceptions' -ErrorAction SilentlyContinue
}