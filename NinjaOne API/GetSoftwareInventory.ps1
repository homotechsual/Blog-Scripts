<#
    .SYNOPSIS
        NinjaOne API - Get Software Inventory
    .DESCRIPTION
        This script uses the NinjaOne API (via the NinjaOne PowerShell wrapper module) to retrieve software inventory information for all organisations. The script will output a CSV file per organisation with the software inventory information.
    .NOTES
        2024-08-13: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
$outputPath = 'C:\RMM\NinjaOne\SoftwareInventory'
# Create the output path if it does not exist.
if (!(Test-Path -Path $outputPath)) {
    $null = New-Item -Path $outputPath -ItemType Directory
}
# Get the list of organisations.
$organisations = Get-NinjaOneOrganisations
# Get all software products from NinjaOne.
$softwareProducts = Get-NinjaOneSoftwareInventory | Group-Object -Property name, publisher, version | Select-Object @{n='name'; e={$_.values[0]}}, @{n='publisher'; e={$_.values[1]}}, @{n='version'; e={ $_.values[2]}}, @{n = 'details'; e={ $_.group | Select-Object deviceId, installDate }}
# Loop through the organisations to do what we need.
foreach ($organisation in $organisations) {
    # Get the list of devices for the organisation.
    $devices = Get-NinjaOneDevices -organisationId $organisation.id
    # Filter the list of software products to include only those installed on the devices. Add the device names to the software product line.
    $filteredSoftwareProducts = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($softwareProduct in $softwareProducts) {
        Write-Host ('Processing software product: {0} {1} {2}' -f $softwareProduct.name, $softwareProduct.publisher, $softwareProduct.version)
        $deviceInfo = [System.Collections.Generic.List[String]]::new()
        foreach ($device in $devices) {
            if ($softwareProduct.details.deviceId -contains $device.id) {
                Write-Host ('Adding device name: {0}' -f $device.systemName)
                $deviceOutput = '{0} (Installed: {1})' -f $device.systemName, ($softwareProduct.details | Where-Object { $_.deviceId -eq $device.id }).installDate
                [void]$deviceInfo.Add($deviceOutput)
            }
        }
        if ($deviceInfo.Count -gt 0) {
            $softwareProduct | Add-Member -MemberType NoteProperty -Name 'devices' -Value ($deviceInfo -join ', ') -Force
        }
        if (![String]::IsNullOrEmpty($softwareProduct.devices)) {
            Write-Host ('Adding software product: {0} {1} {2} to list' -f $softwareProduct.name, $softwareProduct.publisher, $softwareProduct.version)
            [void]$filteredSoftwareProducts.Add($softwareProduct)
        }
    }
    # Output the list of software products for the organisation to a CSV file per organisation and dated today in ISO 9601 format.
    $outputFile = '{0}\{1}-{2}.csv' -f $outputPath, $organisation.name, (Get-Date -Format 'yyyy-MM-dd')
    # Output the list of software products to the CSV file. Exclude the details property.
    Write-Host ('Outputting {0} software products to {1}' -f $filteredSoftwareProducts.Count, $outputFile)
    $filteredSoftwareProducts | Select-Object -ExcludeProperty details | ConvertTo-Csv | Set-Content -Path $outputFile -Force
}
