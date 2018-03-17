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