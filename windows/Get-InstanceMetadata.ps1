<#
.SYNOPSIS
    Get-InstanceMetadata.ps1
.DESCRIPTION
    Get-InstanceMetadata.ps1
.EXAMPLE
    PS C:\> .\Get-InstanceMetadata.ps1
    Queries Instance Metadata Service for instance details.
.NOTES
    See also https://docs.microsoft.com/en-us/azure/virtual-machines/windows/instance-metadata-service
#>

Invoke-RestMethod -Method GET -Uri http://169.254.169.254/metadata/instance?api-version=2017-04-02 -Headers @{"Metadata"="True"} | ConvertTo-JSON -Depth 99