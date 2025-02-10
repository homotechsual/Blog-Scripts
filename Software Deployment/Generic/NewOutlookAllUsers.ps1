<#
    .SYNOPSIS
        Software Deployment - Generic - New Outlook (All Users)
    .DESCRIPTION
        Uses the Outlook Bootstrapper executable to install New Outlook machine-wide.
    .NOTES
        2025-02-10: Initial version
    .LINK
        Not blogged yet.
#>
$BootstrapperDownloadURL = 'https://go.microsoft.com/fwlink/?linkid=2207851'
$DownloadPath = 'C:\RMM\Installers\'
# Create download folder if it doesn't exist
if (-not (Test-Path -Path $DownloadPath)) {
    New-Item -Path $DownloadPath -ItemType Directory
}
$OutlookBootstrapperFile = Join-Path -Path $DownloadPath -ChildPath 'OutlookBootstrapper.exe'
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($BootstrapperDownloadURL, $OutlookBootstrapperFile)
if (Test-Path -Path $OutlookBootstrapperFile) {
    Start-Process -FilePath $OutlookBootstrapperFile -ArgumentList @(
        '--provision',
        'true',
        '--quiet',
        '--start-'
    ) -Wait -NoNewWindow
}