#Requires -Module NinjaOne
#Requires -Version 7
<#
    .SYNOPSIS
        NinjaOne API - Get duplicate devices
    .DESCRIPTION
        This script will return a list of duplicate devices in NinjaOne. You can use the `All` parameter to return all devices with duplicates and the `Duplicates` parameter to return only the duplicate devices themselves.
    .NOTES
        2023-11-01: Fix various bugs and tighten device filtering.
        2022-04-12: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/04/12/Finding-duplicate-devices-NinjaOne/
#>
[CmdletBinding()]
param (
    # Returns all devices with duplicates.
    [Parameter(ParameterSetName = 'All', Mandatory)]
    [Switch]$All,
    # Returns the duplicate devices only.
    [Parameter(ParameterSetName = 'Duplicates', Mandatory)]
    [Switch]$Duplicates
)

try {
    $DuplicateDevices = Get-NinjaOneDevices -detailed | Where-Object { $_.id } | Group-Object { $_.system.serialNumber } | Where-Object { ($_.count -gt 1) -and ($_.name -ne '$(DEFAULT_STRING)' -and $_.name -ne 'Default string' -and $_.name -ne $null -and $_.name -ne 'To Be Filled By O.E.M.' -and $_.name -ne 'chassis serial number' -and (![string]::IsNullOrWhiteSpace($_.name))) -and (($_.Group.id | Get-Unique).Count -gt 1)}
    if ($All) {
        $Output = $DuplicateDevices | ForEach-Object { $_ | Select-Object -ExpandProperty group | Sort-Object $_.lastContact }
    } elseif ($Duplicates) {
        $Output = $DuplicateDevices | ForEach-Object { $_ | Select-Object -ExpandProperty group | Sort-Object $_.lastContact | Select-Object -First 1 -Property id, lastContact, @{ name = 'serialNumber'; expression = { $_.system.serialNumber } } }
    }
    if ($Output) {
        return $Output
    } else {
        Write-Warning 'No duplicate devices found or an unanticipated error occurred.'
    }
} catch {
    Write-Error 'Please ensure the NinjaOne PowerShell module is correctly installed and you have run the "Connect-NinjaOne" command and connected to NinjaOne.'
    exit 1
}