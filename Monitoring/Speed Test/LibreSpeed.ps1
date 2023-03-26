<#
    .SYNOPSIS
        Monitoring - Speed Test - LibreSpeed
    .DESCRIPTION
        This script will run a speed test using LibreSpeed and report back to NinjaOne.
    .NOTES
        2022-12-31: Throw an error on null output from LibreSpeed.
        2022-12-23: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
[CmdletBinding()]
param (
    # Path to download the LibreSpeed CLI executable to.
    [Parameter()]
    [String]$LibreSpeedEXEPath = 'C:\RMM\Bin\',
    # Do not update the LibreSpeed CLI executable.
    [Parameter()]
    [String]$NoUpdate,
    # Replace the LibreSpeed CLI executable with a fresh downloaded copy.
    [Parameter()]
    [String]$ForceUpdate,
    # Switches for the LibreSpeed CLI executable. See documentation at https://github.com/librespeed/speedtest-cli#usage. Space separated single string.
    [Parameter()]
    [String]$CLISwitches
)

$LibreSpeedEXEFile = Join-Path -Path $LibreSpeedEXEPath -ChildPath 'librespeed-cli.exe'
$LibreSpeedVersionFile = Join-Path -Path $LibreSpeedEXEPath -ChildPath 'librespeed-cli.version'

if (-not (Test-Path $LibreSpeedEXEPath)) {
    New-Item -ItemType Directory -Path $LibreSpeedEXEPath -Force
}
# Workaround because the CLI doesn't currently version itself properly.
if (Test-Path $LibreSpeedVersionFile) {
    [version]$LibreSpeedInstalledVersion = Get-Content $LibreSpeedVersionFile -Raw
} else {
    [version]$LibreSpeedInstalledVersion = [version]'0.0.0'
}

if (Test-Path $LibreSpeedEXEFile) {
    $LibreSpeedCLIExists = $true
} else {
    $LibreSpeedCLIExists = $false
}
if (-not $NoUpdate) {
    Write-Verbose 'Starting LibreSpeed installation loop.'
    $LibreSpeedReleasesURI = [uri]'https://api.github.com/repos/librespeed/speedtest-cli/releases/latest'
    $Release = (Invoke-WebRequest -Uri $LibreSpeedReleasesURI -UseBasicParsing).Content | ConvertFrom-Json
    [version]$ReleaseVersion = $Release.name.TrimStart('v')
    if ((($LibreSpeedCLIExists) -and ($ReleaseVersion -gt $LibreSpeedInstalledVersion)) -or $ForceUpdate -or (-not $LibreSpeedCLIExists)) {
        $ReleaseVersion.ToString() | Out-File -FilePath $LibreSpeedVersionFile
        $Assets = $Release.assets
        switch ([Environment]::Is64BitOperatingSystem) {
            $true {
                foreach ($Asset in $Assets | Where-Object { $_.name -like '*windows_amd64.zip' }) {
                    $AssetURI = $Asset.browser_download_url
                    $ZipFileName = $Asset.name
                    $ZipFilePath = "C:\RMM\$($Asset.name)"
                }
            }
            $false {
                foreach ($Asset in $Assets | Where-Object { $_.name -like '*windows_386.zip' }) {
                    $AssetURI = $Asset.browser_download_url
                    $ZipFileName = $Asset.name
                    $ZipFilePath = "C:\RMM\$($Asset.name)"
                }
            }
        }
        Invoke-WebRequest -Uri $AssetURI -OutFile $ZipFilePath -UseBasicParsing
        if (Test-Path -Path $ZipFilePath) {
            Write-Information "Extracting $ZipFileName..."
            Expand-Archive -Path $ZipFilePath -DestinationPath $LibreSpeedEXEPath -Force
        } else {
            Write-Error 'Failed to download latest LibreSpeed CLI.'
        }
    } else {
        Write-Information 'LibreSpeed CLI executable exists and is up to date.'
    }
} else {
    if (-not $LibreSpeedCLIExists) { 
        Write-Error 'LibreSpeed CLI executable does not exist and was not installed because -NoUpdate was specified.'
    } else {
        Write-Information 'LibreSpeed CLI executable exists not updating because -NoUpdate was specified.'
    }
}
# Make sure the CLI switch string includes `--json` if it is not already present.
if (-not [String]::IsNullOrWhiteSpace($CLISwitches)) {
    $CLISwitchArray = $CLISwitches.Split(' ')
} else {
    $CLISwitchArray = @()
}
$CLISwitchArrayList = [System.Collections.ArrayList]::new()
$CLISwitchArrayList.AddRange($CLISwitchArray)
if ($CLISwitchArrayList -notcontains '--json') {
    $CLISwitchArrayList.Add('--json')
}
$SpeedTestResultJSON = & $LibreSpeedEXEFile $CLISwitchArrayList
if ([String]::IsNullOrWhiteSpace($SpeedTestResultJSON)) {
    Throw 'LibreSpeed CLI returned no data. This is likely due to a network issue or a problem with LibreSpeed''s servers.'
} else {
    $SpeedTestResult = ConvertFrom-Json $SpeedTestResultJSON
    $ServerUsed = $SpeedTestResult.server.name
    $DownloadSpeed = $SpeedTestResult.download
    $UploadSpeed = $SpeedTestResult.upload
    Ninja-Property-Set serverUsed $ServerUsed
    Ninja-Property-Set downloadSpeed $DownloadSpeed
    Ninja-Property-Set uploadSpeed $UploadSpeed
}