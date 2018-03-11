Write-Host "Repairing RDP listener";
Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp' -name 'PortNumber' 3389 -Type Dword;
Restart-Service -Name TermService -Force;
Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\control\Terminal Server\Winstations\RDP-Tcp' -name 'PortNumber';
Write-Host "Completed repairing RDP listener";