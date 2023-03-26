<#
    .SYNOPSIS
        Monitoring - Windows - Battery Health
    .DESCRIPTION
        This script will monitor the health of the battery in a Windows device and report back to NinjaOne.
    .NOTES
        2023-03-26: Change static variable to use a parameter instead.
        2022-11-23; Refactor to use more reliable XML pathing and improve reliability.
        2022-02-15: Fix calculation error due to data types by casting to [int] before calculation.
        2022-02-15: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
[CmdletBinding()]
param(
    # Path to output battery report files to.
    [System.IO.DirectoryInfo]$OutputPath = 'C:\RMM\Data'
)

if (-not (Test-Path -Path $OutputPath)) {
    New-Item -Type Directory -Path $OutputPath | Out-Null
}

& powercfg /batteryreport /XML /OUTPUT "$OutputPath\batteryreport.xml" | Out-Null

[xml]$Report = Get-Content "$OutputPath\batteryreport.xml"
     
$BatteryStatus = $Report.BatteryReport.Batteries.Battery | ForEach-Object {
    [PSCustomObject]@{
        DesignCapacity = [int]$_.DesignCapacity
        FullChargeCapacity = [int]$_.FullChargeCapacity
        CycleCount = [int]$_.CycleCount
        Id = $_.id
    }
}

if (!$BatteryStatus) {
    Ninja-Property-Set hasBatteries false | Out-Null
    Write-Output 'No batteries found.'
} else {
    Ninja-Property-Set hasBatteries true | Out-Null
}

$Battery = @{}

if ($BatteryStatus.Count -gt 1) {
    Ninja-Property-Set additionalBattery true | Out-Null
    $Battery = $BatteryStatus[0]
    Write-Output 'More than 1 battery found.'
} elseif ($BatteryStatus.Count -eq 1) {
    Ninja-Property-Set additionalBattery false | Out-Null
    Write-Output 'One battery found.'
    $Battery = $BatteryStatus[0]
} elseif ($BatteryStatus.Id) {
    Ninja-Property-Set additionalBattery false | Out-Null
    $Battery = $BatteryStatus
}

if ($Battery) {
    Write-Output 'Setting NinjaOne custom fields for first battery.'
  
    Ninja-Property-Set batteryIdentifier $Battery.id | Out-Null
    Ninja-Property-Set batteryDesignCapacity $Battery.DesignCapacity | Out-Null
    Ninja-Property-Set batteryFullChargeCapacity $Battery.FullChargeCapacity | Out-Null

    [int]$HealthPercent = ([int]$Battery.FullChargeCapacity / [int]$Battery.DesignCapacity) * 100

    Ninja-Property-Set batteryHealthPercent $HealthPercent | Out-Null
    Ninja-Property-Set batteryCycleCount $Battery.CycleCount | Out-Null
} else {
    Write-Output 'Failed to parse battery status correctly.'
}