<#
    .SYNOPSIS
        Software Deployment - Generic - Adobe Creative Cloud
    .DESCRIPTION
        This script will download and install the latest version of the Adobe Creative Cloud installer from the Adobe website. The script will download the latest release from the Adobe website and install it on the device. The script will also create a staging directory if it does not exist.
    .NOTES
        2024-06-20: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
# Utility Function: DownloadFile
## This function is used to download a file, using the content-disposition header to get the filename if possible or falling back to a specified filename. The file is saved to the specified path. The function returns the path to the downloaded file. The function will exit the script if it fails to download the file.
function Utils.DownloadFile ([System.Uri]$URI, [System.IO.DirectoryInfo]$Path, [String]$FallbackFileName = '') {
    # Save the original progress preference.
    $OriginalProgressPreference = $ProgressPreference
    # Set the progress preference to silently continue.
    $ProgressPreference = 'SilentlyContinue'
    # Download the file.
    $Download = Invoke-WebRequest -Uri $URI
    # Get the filename from the URI.
    if (-not($Download.Headers.ContainsKey('Content-Disposition'))) {
        Write-Warning 'Unable to get Content-Disposition header from response. Attempting to use fallback filename.'
        if (![String]::IsNullOrWhiteSpace($FallbackFileName)) {
            $FileName = $FallbackFileName
        } else {
            Write-Error 'Unable to get filename from Content-Disposition header or fallback filename.'
            exit 1
        }
    } else {
        $ContentDisposition = [System.Net.Mime.ContentDisposition]::New($Download.Headers["Content-Disposition"])
        $FileName = $ContentDisposition.FileName
    }
    if (!$FileName) {
        Write-Error 'Unable to get filename from Content-Disposition header or fallback filename.'
    }
    # Test the path exists.
    if (-not (Test-Path -Path $Path -PathType Container)) {
        # Create the path.
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
        } catch {
            Write-Error ('Unable to create path: {0}' -f $_.Exception.Message)
            exit 1
        }
    }
    # Save the file.
    try {
        $FilePath = Join-Path -Path $Path -ChildPath $FileName
        $File = [System.IO.FileStream]::New($FilePath, [System.IO.FileMode]::Create)
        $File.Write($Download.Content, 0, $Download.RawContentLength)
        $File.Close()
        # Reset the progress preference.
        $ProgressPreference = $OriginalProgressPreference
        # Return the file path.
        return $FilePath
    } catch {
        Write-Error ('Unable to save file: {0}' -f $_.Exception.Message)
        # exit 1
    }
}
# Download the Adobe Creative Cloud installer.
$InstallerFile = Utils.DownloadFile -URI 'https://prod-rel-ffc-ccm.oobesaas.adobe.com/adobe-ffc-external/core/v1/wam/download?sapCode=KCCC&wamFeature=nuj-live' -Path 'C:\RMM\Installers\AdobeCreativeCloud\' -FallbackFileName 'ACCC_Set-Up.exe'
if (Test-Path $InstallerFile) {
    Write-Output 'Downloaded Adobe Creative Cloud installer to: {0}' -f $InstallerFile
    $InstallSwitches = '--mode=stub'
    Start-Process -FilePath $InstallerFile -ArgumentList $InstallSwitches -NoNewWindow
} else {
    Write-Error 'Failed to download Adobe Creative Cloud installer.'
    Exit 1
}