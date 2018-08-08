## WARNING: This preliminary release of the Azure VM recovery scripts should only be used with the assistance of a Microsoft support engineer when working on a support incident.

# Overview

The Azure VM rescue scripts automate detection and mitigation of common guest OS issues that prevent RDP from working.

# Supported scenarios

The rescue scripts are intended for the following scenario:

1. You cannot connect to your Azure VM using RDP or SSH.
2. You can connect to your Azure VM using the Azure serial console feature. 
  If serial console also does not work, use the VM recovery scripts instead. The VM recovery scripts automate swapping the OS disk of a problem VM to a rescue VM as a data disk, where you can investigate and mitigate the problem VM's OS disk.
3. The guest OS of the VM is Windows Server 2008 R2 or later.

## Usage
### Cloud Shell PowerShell
1. Launch PowerShell in Azure Cloud Shell 

   <a href="https://shell.azure.com/powershell" target="_blank"><img border="0" alt="Launch Cloud Shell" src="https://shell.azure.com/images/launchcloudshell@2x.png"></a>

2. If it is your first time connecting to Azure Cloud Shell, select **`PowerShell (Windows)`** when you see **`Welcome to Azure Cloud Shell`**. 

3. If you then see **`You have no storage mounted`**, select the subscription where the VM you are troubleshooting resides, then select **`Create storage`**.

4. From the **`PS Azure:\>`** prompt type **`cd C:\`** then **`<ENTER>`**.

5. Run the following command to download the scripts. Git is preinstalled in Cloud Shell. You do not need to install it separately.
   ```PowerShell
   git clone https://github.com/craiglandis/rescue c:\rescue
   ```
6. Switch into the folder by running:
   ```PowerShell
   cd C:\rescue\windows
   ```
7. Run the following command to connect a rescue VHD to the problem VM as a data disk.

   Important: If the problem VM is currently using the maximum data disks for its VM size, you will not be able to connect the rescue disk unless you temporarily detach one of the existing data disks.   If you need to confirm the resource group name or VM name, you can run **`Get-AzureRmVM`**.
   ```PowerShell
   .\Add-RescueDisk.ps1 -resourceGroupName <resouceGroupName> -vmName <vmName>
   ```


8. After the rescue disk is attached, connect to the problem VM using the Azure serial console feature.

9. Run **`cmd`** to launch a CMD session in SAC.

10. In CMD, switch to the drive where the rescue disk is attached. This will be drive letter E or higher, depending on the configuration of the VM. Run **`dir`** and look for the file **`README.md`** on the root to confirm the drive letter of the rescue disk.
11. Run PowerShell.
   ```PowerShell
   powershell
   ```
12. Remove the **psreadline** module to avoid a known issue where extra characters may be introduced when pasting text into PowerShell running in Azure serial console.
   ```PowerShell
   remove-module psreadline
   ```
13. Switch into the Windows folder and run Get-FirewallDiagnostic.ps1.
   ```PowerShell
   CD windows
   .\Get-FirewallDiagnostic.ps1
   ```
