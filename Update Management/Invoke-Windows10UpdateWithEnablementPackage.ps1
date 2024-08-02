# Upgrade Windows 10 (with enablement)
# Notes:
#       - Versions/URLs will need updating whenever there is a new enablement package
# Changelog:
#   2.0 - 2024-08-02
#       - Remove update assistant usage. Tweak some notifications.
#   1.1 - 2023-08-03
#       - Changed - Syncro Alert name to 'Upgrade Windows', update any Automated Remediations accordingly
#       - Added - Improved error-handling/notification
#       - Added - Groundwork for support for Windows 11 (no Enablement packages yet and UA won't upgrade under SYSTEM user)
#       - Added - General code cleanup, improved consistency and documentation
#       - Added - Support for Windows 10 x86 and 21H2 enablement packages
#       - Fixed - Enablement minimum build (from 1247 to 1237)
#       - Fixed - Removed UBR 1237 requirement for non-enablement that was causing script to fail on 18362.1856
#   1.0 - 2022-12-08 - Initial release
 
# Target version (if you want to update to a version other than latest also set $AttemptWin1xUpdateAssistant to $false)
$Win10TargetVersion = "22H2"
 
# Reboot after upgrade (if changing this to $false also set $AttemptWin1xUpdateAssistant to $false)
$Reboot = $true

# Ignore Windows Update Target Release Version registry settings
$IgnoreTargetReleaseVersion = $false
 
# Location to download files
$TargetFolder = "$env:Temp"
 
##### END OF VARIABLES #####
 
# Get version/build info
# 19041 and older do not have DisplayVersion key, if so we grab ReleaseID instead (no longer updated in new versions)
$MajorVersion = ([System.Environment]::OSVersion.Version).Major
$CurrentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
if ($CurrentVersion.DisplayVersion) {
    $DisplayVersion = $CurrentVersion.DisplayVersion
} else {
    $DisplayVersion = $CurrentVersion.ReleaseId
}
 
# Convert versions to numerical form so comparison operators can be used
$DisplayVersionNumerical = ($DisplayVersion).replace('H1', '05').replace('H2', '10')
$Win10TargetVersionNumerical = ($Win10TargetVersion).replace('H1', '05').replace('H2', '10')
 
# Get build and UBR (kept separate as UBR can be 3 or 4 digits which confuses comparison operators in combined form)
$Build = $CurrentVersion.CurrentBuildNumber
$UBR = $CurrentVersion.UBR
 
# Correct Microsoft's version number for Windows 11
if ($Build -ge 22000) { $MajorVersion = '11' }
Write-Host "Windows $MajorVersion $DisplayVersion build $Build.$UBR detected."
 
# Exit if not eligible
if ($MajorVersion -lt '10') {
    Write-Host "Windows versions prior to 10 cannot be updated with this script."
    exit 0
}
if ($MajorVersion -eq '11') {
    Write-Host "This script is not intended for use with Windows 11."
    exit 0
}
if ($DisplayVersionNumerical -ge $Win10TargetVersionNumerical) {
    Write-Host "Already running $DisplayVersion which is the same or newer than target release $Win10TargetVersion, no update required."
    exit 0
}
if ($MajorVersion -eq '10' -and $Build -le '19041' -and $UBR -lt '1247') {
    $Notification = "Windows 10 builds older than 19041.1247 (September 14, 2021 patch for 2004/20H1) cannot be upgraded with enablement packages."
    Write-Host $Notification
    exit 1
}
if ($IgnoreTargetReleaseVersion -eq $false -and (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate") -eq $true) {
    $WindowsUpdateKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
    if ($WindowsUpdateKey.TargetReleaseVersion -eq 1 -and $WindowsUpdateKey.TargetReleaseVersionInfo) {
        $WindowsUpdateTargetReleaseNumerical = ($WindowsUpdateKey.TargetReleaseVersionInfo).replace('H1', '05').replace('H2', '10')
        if ($WindowsUpdateTargetReleaseNumerical -lt $win10TargetVersionNumerical) {
            $Notification = "Windows Update TargetReleaseVersion registry settings are in place limiting upgrade to $($WindowsUpdateKey.TargetReleaseVersionInfo). To ignore these settings, change the script variable or target version and run again."
            Write-Host $Notification
            exit 1
        }
    }
}

# Attempt upgrade
if ($MajorVersion -eq '10' -and $Build -gt '19041' -and $UBR -ge '1237' -and $Build -lt '22000') {
    # Determine correct package for install and download it
    switch ($Win10TargetVersion) {
        21H2 {
            $x64URL = "https://catalog.s.download.windowsupdate.com/c/upgr/2021/08/windows10.0-kb5003791-x64_b401cba483b03e20b2331064dd51329af5c72708.cab"
            $x86URL = "https://catalog.s.download.windowsupdate.com/c/upgr/2021/08/windows10.0-kb5003791-x86_1bf1a29db06015e9deaefba26cf1f300e8ac18b8.cab"
        }
        22H2 {
            $x64URL = "https://catalog.s.download.windowsupdate.com/c/upgr/2022/07/windows10.0-kb5015684-x64_d2721bd1ef215f013063c416233e2343b93ab8c1.cab"
            $x86URL = "https://catalog.s.download.windowsupdate.com/c/upgr/2022/07/windows10.0-kb5015684-x86_3734a3f6f4143b645788cc77154f6288c8054dd5.cab"
        }
    }
    switch ([Environment]::Is64BitOperatingSystem) {
        True { Write-Host "Attempting enablement upgrade using x64 package."; $CabURL = $x64URL }
        False { Write-Host "Attempting enablement upgrade using x86 package."; $CabURL = $x86URL }
    }
    $PackageFile = "$TargetFolder\$(([uri]$CabURL).Segments[-1])"
    Invoke-WebRequest -Uri $CabURL -OutFile $PackageFile
    # Add the enablement package to the image
    try {
        $Arguments = "/Online /Add-Package /PackagePath:$PackageFile /Quiet /NoRestart"
        $Process = Start-Process 'dism.exe' -ArgumentList $Arguments  -PassThru -Wait -NoNewWindow
        if ($Process.ExitCode -eq '3010') {
            Write-Host "Package added successfully."
        }
        if ($null -ne $Process.StdError) {
            Write-Host "Error: $($Process.StdError)"
            exit 1
        }
        Remove-Item $PackageFile
    } catch {
        Write-Host "Enablement package install failed. Error: $($_.exception.Message)"
        Write-Host "Error: $($_.exception.Message)"
        exit 1
    }
    # Reboot if desired
    if ($Reboot -and -not $Error) {
        "Reboot variable enabled, initiating reboot."
        # If Automatic Restart Sign-On is enabled, /g allows the device to automatically sign in and lock
        # based on the last interactive user. After sign in, it restarts any registered applications.
        shutdown /g /f
    }
} else {
    $Notification = "System detection logic failed, check script for issues."
    exit 1
}