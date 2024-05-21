<#
    .SYNOPSIS
        Software Deployment - Generic - Microsoft PowerToys
    .DESCRIPTION
        This script will download and install the latest version of Microsoft PowerToys from GitHub. The script will download the latest release from GitHub and install it on the device. The script will also create a staging directory if it does not exist.
    .NOTES
        2024-05-21: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
[CmdletBinding()]
param(
    [string]$StagingPath = 'C:\RMM',
    [string]$Architecture = 'x64'
)
# Get latest release function - gets the latest release from GitHub and the download URL for the MSIXBundle from GitHub.
function Get-LatestRelease ([string]$architecture = 'x64') {
    $LatestRelease = Invoke-RestMethod -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -Method Get 
    $LatestGitHubVersion = $LatestRelease.tag_name
    [version]$LatestGitHubVersion = $LatestGitHubVersion.TrimStart('v')
    $LatestVersion = @{
        Version = $LatestGitHubVersion
        DownloadURI = $LatestRelease.assets.browser_download_url | Where-Object { $_.EndsWith('{0}.exe' -f $architecture) }
    }
    return $LatestVersion
}
# Ensure the staging path exists
if (-not (Test-Path -Path $StagingPath)) {
    New-Item -Path $StagingPath -ItemType Directory | Out-Null
}
# Get the latest release
$LatestVersion = Get-LatestRelease -architecture $Architecture
# Download the latest release
$InstallerFileName = [Uri]$LatestRelease.DownloadURI | Select-Object -ExpandProperty Segments | Select-Object -Last 1
$WebClient = New-Object System.Net.WebClient
$InstallerDownloadPath = Join-Path -Path $StagingPath -ChildPath $InstallerFileName
$WebClient.DownloadFile($LatestRelease.DownloadURI, $InstallerDownloadPath)
# Install the latest release
$InstallerArguments = @('/quiet', '/norestart')
Start-Process -FilePath $InstallerDownloadPath -ArgumentList $InstallerArguments -Wait