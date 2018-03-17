write-Host "Enabling RDP";
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections' 0 -Type Dword -ErrorAction SilentlyContinue;
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name 'fDenyTSConnections' 0 -Type Dword -ErrorAction SilentlyContinue;
Get-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -name 'fDenyTSConnections' -ErrorAction SilentlyContinue;
Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services' -name 'fDenyTSConnections' -ErrorAction SilentlyContinue;
Restart-Service -Name TermService -Force;
Write-Host "Completed Enabling RDP";