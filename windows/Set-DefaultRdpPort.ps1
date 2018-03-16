<#
.SYNOPSIS
    Sets RDP to use the default port 3389 and restarts TermService
.DESCRIPTION
    Sets PortNumber DWORD registry value to 3389 under HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp
.PARAMETER parameter1
    parameter1 description
.EXAMPLE
    PS C:\> <example usage>
    Explanation of what the example does
.NOTES
    General notes
#>

$message = "Set RDP to use 3389 and restart TermService [Y/N]?"
$answer = read-host $message
if ($answer.ToUpper() -eq 'Y') 
{
    $path = '"HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp"'
    $name = 'PortNumber'
    $value = 3389
    $type = 'DWORD'
    $command = "set-itemproperty -path $path -name $name -value $value"
    $result = invoke-expression $command
    $command = "restart-service -name TermService -force"
    $result = invoke-expression $command
    $command = "get-itemproperty -path $path -name $name"
    $result = invoke-expression -command $command
}