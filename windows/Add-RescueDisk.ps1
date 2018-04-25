#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Copies and attaches a rescue VHD to a VM.

.DESCRIPTION
    Copies a rescue VHD into the boot diagnostics storage account.
    For managed disk VMs it creates a managed disk from the copied VHD, then attaches the managed disk to the VM
    For unmanaged disk VMs it attaches the VHD from the boot diagnostics storage account.

.EXAMPLE
    add-rescuedisk.ps1 -resourceGroupName $resourceGroupName -vmName $vmName

.PARAMETER resourceGroupName
    Resource group name of the VM where you  want to attach the rescue VHD

.PARAMETER vmName
    Name of VM to attach the rescue VHD

.PARAMETER url
    URL to zip file
#>
param(
    [string]$resourceGroupName,
    [string]$vmName,
    [string]$zipUrl = 'https://github.com/craiglandis/rescue/archive/master.zip',
    [switch]$skipShellHWDetectionServiceCheck = $true
)

set-strictmode -version Latest

function expand-zipfile($zipFile, $destination)
{
    $shell = new-object -com shell.application
    $zip = $shell.NameSpace($zipFile)
    foreach($item in $zip.items())
    {
        $shell.Namespace($destination).copyhere($item)
    }
}

function show-progress
{
    param(
        [string]$text,    
        [string]$color = 'White',
        [switch]$logOnly,
        [switch]$noTimeStamp
    )    

    $timestamp = ('[' + (get-date (get-date).ToUniversalTime() -format "yyyy-MM-dd HH:mm:ssZ") + '] ')

    if ($logOnly -eq $false)
    {
        if ($noTimeStamp)
        {
            write-host $text -foregroundColor $color
        }
        else
        {
            write-host $timestamp -NoNewline
            write-host $text -foregroundColor $color
        }
    }

    if ($noTimeStamp)
    {
        ($text | out-string).Trim() | out-file $logFile -Append
    }
    else
    {
        (($timestamp + $text) | out-string).Trim() | out-file $logFile -Append   
    }        
}

# Stop as soon as an error occurs.  Otherwise the first error can be hidden in lots of subsequent errors.
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'

$startTime = (get-date).ToUniversalTime()
$timestamp = get-date $startTime -format yyyyMMddhhmmssff
$scriptPath = split-path -path $MyInvocation.MyCommand.Path -parent
$scriptName = (split-path -path $MyInvocation.MyCommand.Path -leaf).Split('.')[0]
$logFile = "$scriptPath\$($scriptName)_$($vmName)_$($timestamp).log"
show-progress "Log file: $logFile"

$usedDriveLetters = (get-psdrive -PSProvider filesystem).Name
foreach ($letter in 'DEFGHIJKLMNOPQRSTUVWXYZ'.ToCharArray()) {
    if ($usedDriveLetters -notcontains $letter) {
        $driveLetter = "$($letter):"
        break
    }
}

if ((get-service -Name ShellHwDetection).Status -eq 'Running' -and -not $skipShellHWDetectionServiceCheck)
{
    $shellHWDetectionWasRunning = $true
    show-progress "[Running] Temporarily stopping ShellHWDetection service to avoid Explorer prompt when mounting VHD"
    stop-service -Name ShellHWDetection
    if ((get-service -Name ShellHWDetection).Status -eq 'Stopped')
    {
        show-progress "[Success] Temporarily stopped ShellHWDetection service to avoid Explorer prompt when mounting VHD" -color green
    }
    else
    {
        show-progress "[Error] Unable to stop ShellHWDetection service to avoid Explorer prompt when mounting VHD" -color red
        exit
    }
}

$vhdFile = "$scriptPath\rescue$timestamp.vhd"
$createVhdScript = "$scriptPath\createVhd$timestamp.txt"
$null = new-item $createVhdScript -itemtype File -force
add-content -path $createVhdScript "create vdisk file=$vhdFile type=fixed maximum=20"
add-content -path $createVhdScript "select vdisk file=$vhdFile"
add-content -path $createVhdScript "attach vdisk"
add-content -path $createVhdScript "create partition primary"
add-content -path $createVhdScript "select partition 1"
add-content -path $createVhdScript "format fs=FAT label=RESCUE quick"
add-content -path $createVhdScript "assign letter=$driveLetter"
add-content -path $createVhdScript "exit"
show-progress "[Running] Using diskpart to create $vhdFile"
show-progress '' -noTimeStamp
get-content $createVhdScript | foreach {show-progress $_ -noTimeStamp}
show-progress '' -noTimeStamp
$null = diskpart /s $createVhdScript
remove-item $createVhdScript
if (test-path $vhdFile)
{
    show-progress "[Success] Used diskpart to create $vhdFile" -color green
}
else
{
    show-progress "[Error] Failed to create $vhdFile using diskpart" -color red
    exit
}

$zipFile = "$scriptPath\rescue$timestamp.zip"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$webClient = new-object System.Net.WebClient
show-progress "[Running] Downloading $zipUrl to $zipFile"
$webClient.DownloadFile($zipUrl, $zipFile)
if (test-path $zipFile)
{
    show-progress "[Success] Downloaded $zipUrl to $zipFile" -color green
}
else
{
    show-progress "[Error] Download failed." -color red
}

$folderName = "$($zipUrl.Replace('.zip','').Split('/')[-3])-$($zipUrl.Replace('.zip','').Split('/')[-1])"
show-progress "[Running] Extracting $zipFile to $driveLetter\$folderName"
expand-zipfile -zipFile $zipFile -destination $driveLetter
if (test-path $driveLetter\$folderName)
{
    show-progress "[Success] Extracted $zipFile to $driveLetter\$folderName" -color green
}
else
{
    show-progress "[Error] Failed to extract $zipFile to $driveLetter\$folderName" -color red
}

# If it's a github repo zip, the extracted folder will be <repo>-<branch>
# So get that from the URL and move that folder contents to the root of the VHD.
if($zipUrl -match 'github.com' -and $zipUrl -match 'archive')
{
    $command = "robocopy $driveLetter\$folderName $driveLetter\ /R:0 /W:0 /E /NP /NC /NS /NDL /NFL /NJH /NJS /MT:128"
    invoke-expression -command $command
    remove-item "$driveLetter\$folderName" -recurse -force
}

show-progress "VHD contents:"
$command = "$env:windir\system32\tree.com $driveLetter /a /f"
show-progress " " -noTimeStamp
invoke-expression $command
show-progress " " -noTimeStamp

$detachVhdScript = "$scriptPath\detachVhd$timestamp.txt"
$null = new-item $detachVhdScript -itemtype File -force
add-content -path $detachVhdScript "select vdisk file=$vhdFile"
add-content -path $detachVhdScript "detach vdisk"
show-progress "[Running] Using diskpart to unmount $vhdFile"
$null = diskpart /s $detachVhdScript
remove-item $detachVhdScript
show-progress "[Success] Used diskpart to unmount $vhdFile" -color green

if (!$skipShellHWDetectionServiceCheck)
{
    if($shellHWDetectionWasRunning)
    {
        show-progress "[Running] Starting ShellHWDetection again"
        start-service -name ShellHWDetection
        if ((get-service -Name ShellHWDetection).Status -eq 'Running')
        {
            show-progress "[Success] Started ShellHWDetection service again" -color green
        }
        else
        {
            show-progress "[Error] Unable to start ShellHWDetection service" -color red
            exit
        }
    }    
}

show-progress "[Running] get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName"
$vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName
if ($vm)
{
    show-progress "[Success] get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName" -color green
}
else
{
    show-progress "[Error] get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName" -color red
    exit
}

$vmstatus = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName -Status
$managedDisk = $vm.StorageProfile.OsDisk.ManagedDisk
$serialLogUri = $vmstatus.BootDiagnostics.SerialConsoleLogBlobUri
$vmSize = $vm.hardwareprofile.vmsize
$vmSizes = Get-AzureRmVMSize -Location $vm.Location
$maxDataDiskCount = ($vmsizes | where name -eq $vmsize).MaxDataDiskCount
$dataDisks = $vm.storageprofile.datadisks
show-progress "[Running] Checking for an available LUN on VM $vmName"
if ($dataDisks)
{
    $luns = @(0..($MaxDataDiskCount-1))
    $availableLuns = Compare-Object $dataDisks.lun $luns | foreach {$_.InputObject}
    if($availableLuns)
    {
        $lun = $availableLuns[0]        
    }
    else 
    {
        show-progress "[Error] No LUN available. VM is size $vmSize and already has the maximum data disks attached ($maxDatadiskCount)" -color red
        exit
    }
}
else 
{
    $lun = 0
}
show-progress "[Success] LUN $lun is available" -color green

show-progress "[Running] Verifying boot diagnostics is enabled. Boot diagnostics is required for serial console to work"
if ($serialLogUri)
{
    show-progress "[Success] SerialConsoleLogBlobUri: $serialLogUri" -color green
}
else
{
    # Serial console requires boot diagnostics be enabled
    show-progress "[Error] SerialConsoleLogBlobUri not populated. Please enable boot diagnostics for this VM and run the script again" -color red
    exit
}

# The boot diagnostics storage account is present for both managed and unmanaged, so copy the rescue VHD there
# Possible corner case where the boot diagnostics storage account is in a different resource group than the VM.
# Another approach would be to just always create a new storage account for the rescue disk but simpler to use an existing one (boot diagnostics) unless we find blockers with that approach.
# Creating a managed disk for the rescue disk would require keeping a copy of the rescue VHD in every region, because you can only create a managed disk from a VHD that resides in the same region.
$destStorageAccountName = $serialLogUri.Split('/')[2].Split('.')[0]        
$destStorageContainer = $serialLogUri.Split('/')[-2]
show-progress "[Running] get-azurermstorageaccount -ResourceGroupName $resourceGroupName -Name $destStorageAccountName"
$destStorageAccount = get-azurermstorageaccount -ResourceGroupName $resourceGroupName -Name $destStorageAccountName
if ($destStorageAccount)
{
    show-progress "[Success] get-azurermstorageaccount -ResourceGroupName $resourceGroupName -Name $destStorageAccountName" -color green
}
else
{
    show-progress "[Error] get-azurermstorageaccount -ResourceGroupName $resourceGroupName -Name $destStorageAccountName" -color red
    exit
}
$destStorageAccountKey = ($destStorageAccount | Get-AzureRmStorageAccountKey)[0].Value
show-progress "[Running] Getting storage context for storage account $destStorageAccountName"
$destStorageContext = New-AzureStorageContext -StorageAccountName $destStorageAccountName -StorageAccountKey $destStorageAccountKey
if ($destStorageContext)
{
    show-progress "[Success] Got storage context for storage account $destStorageAccountName" -color green
}
else
{
    show-progress "[Error] Failed to get storage context for storage account $destStorageAccountName" -color red
}

$rescueDiskBlobName = split-path $vhdFile -leaf
$rescueDiskCopyDiskName = $rescueDiskBlobName.Split('.')[0]
$rescueDiskBlobCopyUri = "$($deststoragecontext.BlobEndPoint)$destStorageContainer/$(split-path $vhdFile -leaf)"
show-progress "[Running] add-azurermvhd -resourceGroupName $resourceGroupName -destination $rescueDiskBlobCopyUri -LocalFilePath $vhdFile"
show-progress ''
$result = add-azurermvhd -resourceGroupName $resourceGroupName -destination $rescueDiskBlobCopyUri -LocalFilePath $vhdFile
show-progress ''
if ($result.DestinationUri)
{
    show-progress "[Success] add-azurermvhd -resourceGroupName $resourceGroupName -destination $rescueDiskBlobCopyUri -LocalFilePath $vhdFile" -color green
}
else
{
    show-progress "[Error] add-azurermvhd -resourceGroupName $resourceGroupName -destination $rescueDiskBlobCopyUri -LocalFilePath $vhdFile" -color red
}

<#
show-progress "Copying rescue disk into boot diagnostics storage account $destStorageAccountName"
$rescueDiskBlobName = $rescueDiskUri.Split('/')[-1]
$rescueDiskCopyDiskName = "$($rescueDiskBlobName.Split('.')[0])$vmName"
$rescueDiskCopyBlobName = "$rescueDiskCopyDiskName.vhd"
$rescueDiskBlobCopy = Start-AzureStorageBlobCopy -AbsoluteUri $rescueDiskUri -DestContainer $destStorageContainer -DestBlob $rescueDiskCopyBlobName -DestContext $destStorageContext -Force
$rescueDiskBlobCopyUri = $rescueDiskBlobCopy.ICloudBlob.Uri

$timeout = 60
do {
    $secondsInterval = 5
    start-sleep -Seconds $secondsInterval
    $secondsElapsed += $secondsInterval
    $rescueDiskBlobCopyStatus = (Get-AzureStorageBlobCopyState -CloudBlob $rescueDiskBlobCopy.ICloudBlob -Context $destStorageContext).Status
} until (($rescueDiskBlobCopyStatus -eq 'Success') -or ($secondsElapsed -ge $timeout))

if ($rescueDiskBlobCopyStatus -eq 'Success')
{
    show-progress "Rescue disk copied to $rescueDiskBlobCopyUri"
}
else 
{
    show-progress "Copied failed or exceeded the $timeout second timeout defined in the script"    
    exit
}
#>

if($managedDisk)
{
    show-progress "[Running] Creating managed disk from VHD that was copied into boot diagnostics storage account"
    $diskConfig = New-AzureRmDiskConfig -AccountType $accountType -Location $vm.Location -CreateOption Import -StorageAccountId $destStorageAccount.Id -SourceUri $rescueDiskBlobCopyUri
    if (!$diskConfig)
    {
        show-progress "[Error] Failed to create disk config object." -color red
        exit
    }    
    $disk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $rescueDiskCopyDiskName
    if ($disk)
    {
        show-progress "[Success] Created managed disk $rescueDiskCopyDiskName" -color green
    }
    else
    {
        show-progress "[Error] Failed to create disk $rescueDiskCopyDiskName" -color red
    }
    show-progress "[Running] Attaching managed disk $rescueDiskCopyDiskName to VM $vmName"    
    $vm = Add-AzureRmVMDataDisk -VM $vm -Name $rescueDiskCopyDiskName -ManagedDiskId $disk.Id -Lun $lun -CreateOption Attach -StorageAccountType $accountType
    $vm = Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroupName
}
else 
{
    show-progress "[Running] Attaching disk $rescueDiskCopyDiskName to VM $vmName"
    $vm = Add-AzureRmVMDataDisk -VM $vm -Name $rescueDiskCopyDiskName -VhdUri $rescueDiskBlobCopyUri -Lun $lun -CreateOption Attach
    $vm = Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroupName
}

$vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName
$rescueDataDisk = $vm.storageprofile.datadisks | where LUN -eq $lun 
if ($rescueDataDisk)
{
    show-progress "[Success] Attached disk $rescueDiskCopyDiskName" -color green
}
else 
{
    show-progress "[Error] Failed to attach disk $rescueDiskCopyDiskName" -color red
}

$endTime = (get-date).ToUniversalTime()
$duration = new-timespan -Start $startTime -End $endTime
show-progress "Script duration: $('{0:hh}:{0:mm}:{0:ss}.{0:ff}' -f $duration)"
show-progress "Log file: $logFile"