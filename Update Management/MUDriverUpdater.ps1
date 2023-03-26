<#
    .SYNOPSIS
        Update Management - Microsoft Update Driver Updater
    .DESCRIPTION
        Downloads and installs the latest drivers using Microsoft Update.
    .NOTES
        2023-01-10: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2023/01/10/Updating-Drivers-from-Microsoft-Update/
#>
[CmdletBinding()]
param ()
try {
    # Create a new update service manager COM object.
    $UpdateService = New-Object -ComObject Microsoft.Update.ServiceManager
    # If the Microsoft Update service is not enabled, enable it.
    $MicrosoftUpdateService = $UpdateService.Services | Where-Object { $_.ServiceId -eq '7971f918-a847-4430-9279-4a52d1efe18d' }
    if (!$MicrosoftUpdateService) {
        $UpdateService.AddService2('7971f918-a847-4430-9279-4a52d1efe18d', 7, '')
    }
    # Create a new update session COM object.
    $UpdateSession = New-Object -ComObject Microsoft.Update.Session
    # Create a new update searcher in the update session.
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
    # Configure the update searcher to search for driver updates from Microsoft Update.
    ## Set the update searcher 
    $UpdateSearcher.ServiceID = '7971f918-a847-4430-9279-4a52d1efe18d'
    ## Set the update searcher to search for per-machine updates only.
    $UpdateSearcher.SearchScope = 1
    ## Set the update searcher to search non-Microsoft sources only (no WSUS, no Windows Update) so Microsoft Update and Manufacturers only.
    $UpdateSearcher.ServerSelection = 3
    # Set our search criteria to only search for driver updates.
    $SearchCriteria = "IsInstalled=0 and Type='Driver'"
    # Search for driver updates.
    Write-Verbose 'Searching for driver updates...'
    $UpdateSearchResult = $UpdateSearcher.Search($SearchCriteria)
    $UpdatesAvailable = $UpdateSearchResult.Updates
    # If no updates are available, output a message and exit.
    if (($UpdatesAvailable.Count -eq 0) -or ([string]::IsNullOrEmpty($UpdatesAvailable))) {
        Write-Warning 'No driver updates are available.'
        Ninja-Property-Set driverUpdateRebootRequired 0 # Adjust for RMM
        Ninja-Property-Set driverUpdateLastRun (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') # Adjust for RMM
        Ninja-Property-Set driverUpdateNumberInstalledOnLastRun 0 # Adjust for RMM
        exit 0
    } else {
        Write-Verbose "Found $($UpdatesAvailable.Count) driver updates."
        # Output available updates.
        $UpdatesAvailable | Select-Object -Property Title, DriverModel, DriverVerDate, DriverClass, DriverManufacturer | Format-Table
        # Create a new update collection to hold the updates we want to download.
        $UpdatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
        $UpdatesAvailable | ForEach-Object {
            # Add the update to the update collection.
            $UpdatesToDownload.Add($_) | Out-Null
        }
        # If there are updates to download, download them.
        if (($UpdatesToDownload.count -gt 0) -or (![string]::IsNullOrEmpty($UpdatesToDownload))) {
            # Create a fresh session to download and install updates.
            $UpdaterSession = New-Object -ComObject Microsoft.Update.Session
            $UpdateDownloader = $UpdaterSession.CreateUpdateDownloader()
            # Add the updates to the downloader.
            $UpdateDownloader.Updates = $UpdatesToDownload
            # Download the updates.
            Write-Verbose 'Downloading driver updates...'
            $UpdateDownloader.Download()
        }
        # Create a new update collection to hold the updates we want to install.
        $UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
        # Add downloaded updates to the update collection.
        $UpdatesToDownload | ForEach-Object { 
            if ($_.IsDownloaded) {
                # Add the update to the update collection if it has been downloaded.
                $UpdatesToInstall.Add($_) | Out-Null
            }
        }
        # If there are updates to install, install them.
        if (($UpdatesToInstall.count -gt 0) -or (![string]::IsNullOrEmpty($UpdatesToInstall))) {
            # Create an update installer.
            $UpdateInstaller = $UpdaterSession.CreateUpdateInstaller()
            # Add the updates to the installer.
            $UpdateInstaller.Updates = $UpdatesToInstall
            # Install the updates.
            Write-Verbose 'Installing driver updates...'
            $InstallationResult = $UpdateInstaller.Install()
            # If we need to reboot flag that information.
            if ($InstallationResult.RebootRequired) {
                Write-Warning 'Reboot required to complete driver updates.'
                Ninja-Property-Set driverUpdateRebootRequired 1 # Adjust for RMM
            }
        
            # Output the results of the installation.
            ## Result codes: 0 = Not Started, 1 = In Progress, 2 = Succeeded, 3 = Succeeded with Errors, 4 = Failed, 5 = Aborted
            ## We consider 1, 2, and 3 to be successful here.
            if (($InstallationResult.ResultCode -eq 1) -or ($InstallationResult.ResultCode -eq 2) -or ($InstallationResult.ResultCode -eq 3)) {
                Write-Verbose 'Driver updates installed successfully.'
                Ninja-Property-Set driverUpdateRebootRequired 0 # Adjust for RMM
                Ninja-Property-Set driverUpdateLastRun (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss') # Adjust for RMM
                Ninja-Property-Set driverUpdateNumberInstalledOnLastRun $UpdatesToInstall.Count # Adjust for RMM
            } else {
                Write-Warning "Driver updates failed to install. Result code: $($InstallationResult.ResultCode.ToString())"
                exit 1
            }
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}