# Upgrade Windows 11 (with enablement)
# Notes:
#       - Versions/URLs will need updating whenever there is a new enablement package
# Changelog:
#   1.1 - 2025-08-02 - Added - Improved error-handling/notification (by homotechsual)
#   1.0 - 2024-06-10 - Initial release (by @Morte on NinjaOne Discord)
$Win11TargetVersion = "23H2"
$WorkingDirectory = $ENV:Temp
$DownloadURL = 'https://catalog.sf.dl.delivery.mp.microsoft.com/filestreamingservice/files/caa3ff4a-6420-4341-aeae-33b2d7f463be/public/windows11.0-kb5027397-x64_3a9c368e239bb928c32a790cf1663338d2cad472.msu'
$FilePath = Join-Path -Path $WorkingDirectory -ChildPath 'windows11.0-kb5027397-x64_3a9c368e239bb928c32a790cf1663338d2cad472.msu'

$MajorVersion = ([System.Environment]::OSVersion.Version).Major
$CurrentVersion = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
if ($CurrentVersion.DisplayVersion) {
    $DisplayVersion = $CurrentVersion.DisplayVersion
} else {
    $DisplayVersion = $CurrentVersion.ReleaseId
}
# Convert versions to numerical form so comparison operators can be used
$DisplayVersionNumerical = ($DisplayVersion).replace('H1', '05').replace('H2', '10')
$Win11TargetVersionNumerical = ($Win11TargetVersion).replace('H1', '05').replace('H2', '10')
# Get build and UBR (kept separate as UBR can be 3 or 4 digits which confuses comparison operators in combined form)
$Build = $CurrentVersion.CurrentBuildNumber
$UBR = $CurrentVersion.UBR
# Correct Microsoft's version number for Windows 11
if ($Build -ge 22000) { $MajorVersion = '11' }
Write-Host "Windows $MajorVersion $DisplayVersion build $Build.$UBR detected."
# Exit if not eligible
if ($MajorVersion -lt '11') {
    Write-Host "Windows versions prior to 11 cannot be updated with this script."
    exit 0
}
if ($Build -lt '22621') {
	Write-Host "Windows 11 builds older than 22621 (22H2) cannot be upgraded with enablement packages."
	exit 1
}
if ($DisplayVersionNumerical -ge $Win11TargetVersionNumerical) {
    Write-Host "Already running $DisplayVersion which is the same or newer than target release $Win11TargetVersion, no update required."
    exit 0
}
if ((Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate") -eq $true) {
    $WindowsUpdateKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
    if ($WindowsUpdateKey.TargetReleaseVersion -eq 1 -and $WindowsUpdateKey.TargetReleaseVersionInfo) {
        $WindowsUpdateTargetReleaseNumerical = ($WindowsUpdateKey.TargetReleaseVersionInfo).replace('H1', '05').replace('H2', '10')
        if ($WindowsUpdateTargetReleaseNumerical -lt $Win11TargetVersionNumerical) {
            $Notification = "Windows Update TargetReleaseVersion registry settings are in place limiting upgrade to $($WindowsUpdateKey.TargetReleaseVersionInfo). To ignore these settings, change or remove the target version and run again."
            Write-Host $Notification
            exit 1
        }
    }
}
# Test if the working directory exists
if (!(Test-Path $WorkingDirectory)) {
	New-Item -ItemType Directory -Force -Path $WorkingDirectory
}
# Download
Invoke-WebRequest -Uri $DownloadURL -OutFile $FilePath
# Install
Start-Process -FilePath 'wusa.exe' -ArgumentList $FilePath, '/quiet' -Wait -PassThru -NoNewWindow