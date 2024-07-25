<#
    .SYNOPSIS
        Ninja Scripts - WatchDog
    .DESCRIPTION
        This script creates a watchdog script that will monitor and restart the NinjaOne agent if it stops running. It creates a scheduled task to run the watchdog script every 5 minutes.
    .NOTES
        2024-07-25 - Script fixed by @Morte from NinjaOne Discord - now it actually works. Thanks @Morte!
        2024-06-24 - Initial version
    .LINK
        Blog post: Not blogged yet
    .TODO
        - Add logging to a Ninja field - name the function "Bark" (thanks @Ogre!)
#>
# Define the PowerShell script content for the watchdog
$watchdogScript = @'
$services = 'NinjaRMMAgent', 'ncstreamer'
$maxRetries = 3

function Bark {
    $NinjaModuleLoaded = Get-Module 'NJCliPsh'
    if ($NinjaModuleLoaded -eq $null) {
        $NinjaModuleAvailable = Get-Module -ListAvailable -Name 'NJCliPsh'
        if ($NinjaModuleAvailable -eq $null) {
            Write-Host "Ninja module not available."
            return
        } else {
            Import-Module 'NJCliPsh'
        }
    }
    $WatchDogFieldValue = Ninja-Property-Get -Name 'watchDogActivity'
    if ($WatchDogFieldValue -eq $null) {
        
    }  
}

foreach ($service in $services) {
    $serviceObject = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name = '$service'"
    if ($serviceObject -eq $null) {
        continue
    }

    if ($serviceObject.StartMode -ne 'Auto') {
        # Try to change the service start mode to 'Auto'
        $serviceObject | Invoke-CimMethod -MethodName 'ChangeStartMode' -Arguments @{ StartMode = 'Automatic' }
    } else {
    }

    $retries = 0
    while ($retries -lt $maxRetries) {
        $serviceObject = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name = '$service'" # Refresh the object
        if ($serviceObject.State -ne 'Running') {
            # Try to start the service
            $serviceObject | Invoke-CimMethod -MethodName 'StartService'
            Start-Sleep -Seconds 10  # Wait for service to start
            $refreshedServiceObject = Get-CimInstance -ClassName 'Win32_Service' -Filter "Name = '$service'"
            if ($refreshedServiceObject.Status -ne 'Running') {
                # Log a custom event
                $eventMessage = ('Failed to start service {0} after {1} retries.' -f $serviceObject.Name, $retries)
                $retries++
            } else {
                break
            }
        } else {
            break
        }
    }
}
'@

# Save the watchdog script to a file
$watchdogPath = 'C:\RMM\Scripts\ServiceWatchdog.ps1'
# Make sure the directory exists
$null = New-Item -Path (Split-Path -Path $watchdogPath) -ItemType Directory -Force
# Save the watchdog script to the file using Out-File with -Encoding parameter
$watchdogScript | Out-File -FilePath $watchdogPath -Encoding UTF8

# Create the scheduled task to run the watchdog script every 5 minutes
$taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy RemoteSigned -File $watchdogPath"
$taskTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval ([TimeSpan]::FromMinutes(5)) -RepetitionDuration ([TimeSpan]::FromDays(365))
Register-ScheduledTask -TaskName 'ServiceWatchdog' -Action $taskAction -Trigger $taskTrigger -User 'NT AUTHORITY\SYSTEM' -Force

Write-Host "ServiceWatchdog.ps1 was created and scheduled task 'ServiceWatchdog' was created successfully."