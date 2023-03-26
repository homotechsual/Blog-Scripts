<#
    .SYNOPSIS
        Monitoring - Speed Test - Ookla Speedtest
    .DESCRIPTION
        This script will run a speed test using the OOKLA Speedtest CLI and report back to NinjaOne.
    .NOTES
        2022-12-31: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
[CmdletBinding()]
param (
    # URI to download the Ookla Speedtest CLI executable from.
    [Parameter()]
    [String]$OoklaSpeedtestURI = 'https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-win64.zip',
    # Path to download the Ookla Speedtest CLI executable to.
    [Parameter()]
    [String]$OoklaSpeedtestEXEPath = 'C:\RMM\Bin\',
    # Do not redownload the Ookla Speedtest CLI executable.
    [Parameter()]
    [String]$NoUpdate,
    # Replace the Ookla Speedtest CLI executable with a fresh downloaded copy.
    [Parameter()]
    [String]$ForceUpdate,
    # Switches for the Ookla Speedtest CLI executable. Space separated single string.
    [Parameter()]
    [String]$CLISwitches
)

$OoklaSpeedtestZipName = Split-Path -Path $OoklaSpeedtestURI -Leaf
$OoklaSpeedtestZipPath = Join-Path -Path 'C:\RMM\' -ChildPath $OoklaSpeedtestZipName
$OoklaSpeedtestEXEFile = Join-Path -Path $OoklaSpeedtestEXEPath -ChildPath 'speedtest.exe'
$OoklaSpeedtestVersionFile = Join-Path -Path $OoklaSpeedtestEXEPath -ChildPath 'ooklaspeedtest-cli.version'

if (-not (Test-Path $OoklaSpeedtestEXEPath)) {
    New-Item -ItemType Directory -Path $OoklaSpeedtestEXEPath -Force
}

$OoklaspeedtestDownloadVersionMatches = Select-String -Pattern '(?<=-)(?<version>\d+.+?)(?=-)' -InputObject $OoklaSpeedtestURI
[version]$OoklaSpeedtestDownloadVersion = $OoklaspeedtestDownloadVersionMatches.Matches.Groups | Where-Object { $_.name -eq 'version' } | Select-Object -ExpandProperty value

# Workaround because the CLI doesn't currently version itself properly.
if (Test-Path $OoklaSpeedtestVersionFile) {
    [version]$OoklaSpeedtestInstalledVersion = Get-Content $OoklaSpeedtestVersionFile -Raw
} else {
    [version]$OoklaSpeedtestInstalledVersion = [version]'0.0.0'
    $OoklaSpeedtestDownloadVersion.ToString() | Out-File -FilePath $OoklaSpeedtestVersionFile
}

if (Test-Path $OoklaSpeedtestEXEFile) {
    $OoklaSpeedtestCLIExists = $true
} else {
    $OoklaSpeedtestCLIExists = $false
}
if (-not $NoUpdate) {
    Write-Verbose 'Starting Ookla Speedtest installation loop.'
    if ((($OoklaSpeedtestCLIExists) -and ($OoklaSpeedtestDownloadVersion -gt $OoklaSpeedtestInstalledVersion)) -or $ForceUpdate -or (-not $OoklaSpeedtestCLIExists)) {
        Invoke-WebRequest -Uri $OoklaSpeedtestURI -OutFile $OoklaSpeedtestZipPath -UseBasicParsing
        if (Test-Path -Path $OoklaSpeedtestZipPath) {
            Write-Information "Extracting $OoklaSpeedtestZipName..."
            Expand-Archive -Path $OoklaSpeedtestZipPath -DestinationPath $OoklaSpeedtestEXEPath -Force
        } else {
            Write-Error 'Failed to download latest Ookla Speedtest CLI.'
        }
    } else {
        Write-Information 'Ookla Speedtest CLI executable exists and is up to date.'
    }
} else {
    if (-not $OoklaSpeedtestCLIExists) { 
        Write-Error 'Ookla Speedtest CLI executable does not exist and was not installed because -NoUpdate was specified.'
    } else {
        Write-Information 'Ookla Speedtest CLI executable exists not updating because -NoUpdate was specified.'
    }
}
# Make sure the CLI switch string includes ` --format=json-pretty`, `--accept-license` and `--accept-gdpr` if it is not already present.
if (-not [String]::IsNullOrWhiteSpace($CLISwitches)) {
    $CLISwitchArray = $CLISwitches.Split(' ')
} else {
    $CLISwitchArray = @()
}
$CLISwitchArrayList = [System.Collections.ArrayList]::new()
$CLISwitchArrayList.AddRange($CLISwitchArray)
if ($CLISwitchArrayList -notcontains '--format=json-pretty') {
    $CLISwitchArrayList.Add('--format=json')
}
if ($CLISwitchArrayList -notcontains '--accept-license') {
    $CLISwitchArrayList.Add('--accept-license')
}
if ($CLISwitchArrayList -notcontains '--accept-gdpr') {
    $CLISwitchArrayList.Add('--accept-gdpr')
}
$SpeedTestResultJSON = & $OoklaSpeedtestEXEFile $CLISwitchArrayList
$SpeedTestResult = ConvertFrom-Json $SpeedTestResultJSON
$ServerUsed = '{0} ({1} - {2})' -f $SpeedTestResult.server.name, $SpeedTestResult.server.location, $SpeedTestResult.server.country
[double]$DownloadSpeed = [math]::round($SpeedTestResult.download.bandwidth / 125000, 2)
[double]$UploadSpeed = [math]::round($SpeedTestResult.upload.bandwidth / 125000, 2)
Ninja-Property-Set serverUsed $ServerUsed
Ninja-Property-Set downloadSpeed $DownloadSpeed
Ninja-Property-Set uploadSpeed $UploadSpeed