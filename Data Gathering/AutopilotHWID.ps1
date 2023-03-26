<#
    .SYNOPSIS
        Data Gathering - Windows - Autopilot Hardware Identifier (Hardware Hash)
    .DESCRIPTION
        This script will gather the hardware hash of a Windows device and report back to NinjaOne.
    .NOTES
        2022-02-15: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
$DeviceDetailParams = @{
    Namespace = 'root/cimv2/mdm/dmmap'
    Class = 'MDM_DevDetail_Ext01'
    Filter = "InstanceID='Ext' AND ParentID='./DevDetail'"
}  
$DeviceDetail = (Get-CimInstance @DeviceDetailParams)
if ($DeviceDetail) {
    $Hash = $DeviceDetail.DeviceHardwareData
} else {
    Throw 'Unable to retrieve device details.'
}  
Ninja-Property-Set autopilotHWID $Hash