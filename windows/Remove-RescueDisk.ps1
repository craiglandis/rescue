param(
    [Parameter(mandatory=$true)]
    [String]$ResourceGroupName,
    [Parameter(mandatory=$true)]
    [String]$vmName,
    [switch]$detachAllDataDisks
)

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

set-strictmode -version Latest

$startTime = (get-date).ToUniversalTime()
$timestamp = get-date $startTime -format yyyyMMddhhmmssff
$scriptPath = split-path -path $MyInvocation.MyCommand.Path -parent
$scriptName = (split-path -path $MyInvocation.MyCommand.Path -leaf).Split('.')[0]
$logFile = "$scriptPath\$($scriptName)_$($vmName)_$($timestamp).log"
show-progress "Log file: $logFile"

$vm = get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName
$dataDisks = $vm.StorageProfile.DataDisks

if($dataDisks)
{
    $dataDisks | where {$_.Name.StartsWith('rescue')} | foreach {
        $diskName = $_.Name
        show-progress '' -noTimeStamp
        if ($detachAllDataDisks)
        {
            get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName | Remove-AzureRmVMDataDisk -DataDiskNames $diskName | update-azurermvm
        }
        else
        {
            $answer = (read-host -Prompt "Detach data disk $($diskName)[Y/N]?").ToUpper
            if($answer = 'Y')
            {
                get-azurermvm -ResourceGroupName $resourceGroupName -Name $vmName | Remove-AzureRmVMDataDisk -DataDiskNames $diskName | update-azurermvm
            }
        }
    }
}
else
{
    show-progress "VM $vmName has no data disks"
}