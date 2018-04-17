<#
.SYNOPSIS
    Copies and attaches a rescue VHD to a VM.

.DESCRIPTION
    Copies a rescue VHD into the boot diagnostics storage account.
    For managed disk VMs it creates a managed disk from the copied VHD, then attaches the managed disk to the VM
    For unmanaged disk VMs it attaches the VHD from the boot diagnostics storage account.

.EXAMPLE
    connect-rescuedisk.ps1 -resourceGroupName $resourceGroupName -vmName $vmName

.PARAMETER resourceGroupName
    Resource group name of the VM where you  want to attach the rescue VHD

.PARAMETER vmName
    Name of VM to attach the rescue VHD

.PARAMETER rescueDiskUri
    URI to the rescue VHD

.PARAMETER accountType
    For managed disk VMs, this is the type of storage account to use for the managed disk that will be created from the rescue VHD.
    StandardLRS and PremiumLRS or the accepted values. Script defaults to StandardLRS
#>
param(
    [string]$resourceGroupName,
    [string]$vmName,
    [string]$rescueDiskUri = 'https://rescuesa1.blob.core.windows.net/vhds/rescue.vhd',
    [string]$accountType = 'StandardLRS'
)

function show-progress()
{
    param(
        [string]$text,
        [string]$prefix = 'both'
    )

    if ($prefix -eq 'timespan' -and $startTime)
    {
        $timespan = new-timespan -Start $startTime -End (get-date)
        $timespanString = '[{0:hh}:{0:mm}:{0:ss}.{0:ff}]' -f $timespan
        write-host $timespanString -nonewline -ForegroundColor Cyan
        write-host " $text"
    }
    elseif ($prefix -eq 'both' -and $startTime)
    {
        $timestamp = get-date -format "yyyy-MM-dd hh:mm:ss"
        $timespan = new-timespan -Start $startTime -End (get-date)
        $timespanString = "$($timestamp) $('[{0:hh}:{0:mm}:{0:ss}.{0:ff}]' -f $timespan)"
        write-host $timespanString -nonewline -ForegroundColor Cyan
        write-host " $text"        
    }
    else 
    {
        $timestamp = get-date -format "yyyy-MM-dd hh:mm:ss"
        write-host $timestamp -nonewline -ForegroundColor Cyan
        write-host " $text"
    }
}

# Stop as soon as an error occurs.  Otherwise the first error can be hidden in lots of subsequent errors.
$PSDefaultParameterValues['*:ErrorAction'] = 'Stop'
$PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'

$vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName
$vmstatus = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName -Status
show-progress "resourceGroupName: $($vm.ResourceGroupName) vmName: $($vm.Name) location: $($vm.Location)"

$managedDisk = $vm.StorageProfile.OsDisk.ManagedDisk
$serialLogUri = $vmstatus.BootDiagnostics.SerialConsoleLogBlobUri
$vmSize = $vm.hardwareprofile.vmsize
$vmSizes = Get-AzureRmVMSize -Location $vm.Location
$maxDataDiskCount = ($vmsizes | where name -eq $vmsize).MaxDataDiskCount
$dataDisks = $vm.storageprofile.datadisks
show-progress "Checking for available LUN"
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
        show-progress "No LUN available. VM is size $vmSize and already has the maximum data disks attached ($maxDatadiskCount)"
        exit
    }
}
else 
{
    $lun = 0
}
show-progress "LUN $lun is available"

if (!$serialLogUri)
{
    # Serial console requires boot diagnostics be enabled
    show-progress "SerialConsoleLogBlobUri not populated. Please enable boot diagnostics for this VM and run the script again"
    exit
}

# The boot diagnostics storage account is present for both managed and unmanaged, so copy the rescue VHD there
# Possible corner case where the boot diagnostics storage account is in a different resource group than the VM.
# Another approach would be to just always create a new storage account for the rescue disk but simpler to use an existing one (boot diagnostics) unless we find blockers with that approach.
# Creating a managed disk for the rescue disk would require keeping a copy of the rescue VHD in every region, because you can only create a managed disk from a VHD that resides in the same region.
show-progress "Getting boot diagnostics storage account"
$destStorageAccountName = $serialLogUri.Split('/')[2].Split('.')[0]        
$destStorageContainer = $serialLogUri.Split('/')[-2]
$destStorageAccount = get-azurermstorageaccount -ResourceGroupName $resourceGroupName -Name $destStorageAccountName
$destStorageAccountKey = ($destStorageAccount | Get-AzureRmStorageAccountKey)[0].Value
$destStorageContext = New-AzureStorageContext -StorageAccountName $destStorageAccountName -StorageAccountKey $destStorageAccountKey

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

if($managedDisk)
{
    show-progress "Creating managed disk from VHD that was copied into boot diagnostics storage account"
    $diskConfig = New-AzureRmDiskConfig -AccountType $accountType -Location $vm.Location -CreateOption Import -StorageAccountId $destStorageAccount.Id -SourceUri $rescueDiskBlobCopyUri
    $disk = New-AzureRmDisk -Disk $diskConfig -ResourceGroupName $resourceGroupName -DiskName $rescueDiskCopyDiskName
    show-progress "Created managed disk $rescueDiskCopyDiskName"
    show-progress "Attaching managed disk $rescueDiskCopyDiskName to VM $vmName"
    $vm = Add-AzureRmVMDataDisk -VM $vm -Name $rescueDiskCopyDiskName -ManagedDiskId $disk.Id -Lun $lun -CreateOption Attach -StorageAccountType $accountType
    $vm = Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroupName
}
else 
{
    show-progress "Attaching disk $rescueDiskCopyDiskName to VM $vmName"
    $vm = Add-AzureRmVMDataDisk -VM $vm -Name $rescueDiskCopyDiskName -VhdUri $rescueDiskBlobCopyUri -Lun $lun -CreateOption Attach
    $vm = Update-AzureRmVM -VM $vm -ResourceGroupName $resourceGroupName
}

$vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName
$rescueDataDisk = $vm.storageprofile.datadisks | where LUN -eq $lun 
if ($rescueDataDisk)
{
    show-progress "Disk $rescueDiskCopyDiskName was attached successfully"
}
else 
{
    show-progress "Disk $rescueDiskCopyDiskName was not attached"
    exit    
}