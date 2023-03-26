<#
    .SYNOPSIS
        Software Deployment - Intune - Adobe Reader DC
    .DESCRIPTION
        Downloads the latest version of Adobe Acrobat Reader DC, in the language specified, supporting the architecture specified and creates an IntuneWin package.
    .NOTES
        2023-03-25: Remove unused parameter.
        2021-09-30: Initial version
    .LINK
        Inspired by code from https://cyberdrain.com, https://gavsto.com and https://mspp.io.
    .LINK
        Blog post: https://homotechsual.dev/2021/09/30/Packaging-latest-Adobe-Reader-DC-IntuneWin-file/
#>
[CmdletBinding()]
param (
    # The language of the Adobe Acrobat Reader DC installer to download.
    [ValidateSet(
        'Basque',
        'Chinese (Simplified)',
        'Chinese (Traditional)',
        'Catalan',
        'Croatian',
        'Czech',
        'Danish',
        'Dutch',
        'English',
        'English (UK)',
        'Finnish',
        'French',
        'German',
        'Hungarian',
        'Italian',
        'Japanese',
        'Korean',
        'Norwegian',
        'Polish',
        'Portuguese',
        'Romanian',
        'Russian',
        'Slovakian',
        'Slovenian',
        'Spanish',
        'Swedish',
        'Turkish',
        'Ukrainian'
    )]
    [String]$Language = 'English (UK)',
    # The architecture of the Adobe Acrobat Reader DC installer to download.
    [ValidateSet(
        'x64',
        'x86'
    )]
    [String]$Architechture = 'x64',
    # The path to save the Adobe Acrobat Reader DC installer to.
    [String]$InstallerSavePath,
    # The path to the Win32ContentPrepTool.exe file.
    [String]$Win32ContentPrepToolPath,
    # The path to save the IntuneWin package to.
    [String]$PackageOutputPath
)
if (-not ('System.Web.HTTPUtility' -as [Type])) {
    Add-Type -AssemblyName System.Web
}
$OriginalProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
$AdobeReleaseFeedURI = [System.URIBuilder]'https://get.adobe.com/reader/webservices/json/standalone/'

$AdobeReleaseFeedQSCollection = [System.Web.HTTPUtility]::ParseQueryString([string]::Empty)

$AdobeReleaseFeedQSCollection.Add('platform_type', 'Windows')
$AdobeReleaseFeedQSCollection.Add('platform_dist', 'Windows 10')
$AdobeReleaseFeedQSCollection.Add('platform_arch', $Architechture)
$AdobeReleaseFeedQSCollection.Add('language', $Language)

$AdobeReleaseFeedURI.Query = $AdobeReleaseFeedQSCollection.ToString()

$AdobeReleaseFeedParams = @{
    URI = $AdobeReleaseFeedURI.ToString()
    ContentType = 'application/json'
    Headers = @{
        'x-requested-with' = 'xmlhttprequest'
    }
}

$CurrentAdobeRelease = Invoke-WebRequest @AdobeReleaseFeedParams

$AdobeReleaseInfo = $CurrentAdobeRelease.Content | ConvertFrom-Json

if ($Architechture -eq 'x64') {
    $AdobeRelease = $AdobeReleaseInfo | Where-Object {
        $_.name -like '*64bit*'
    }
} else {
    $AdobeRelease = $AdobeReleaseInfo | Where-Object {
        $_.name -notlike '*64bit*'
    }
}

if ($AdobeRelease) {
    $AdobeDownloadURL = $AdobeRelease.download_url
    $AdobeReaderInstallParameters = $AdobeRelease.aih_cmd_arguments
} else {
    Throw 'Failed to retrieve Adobe Reader release information.'
}

if (Test-Path $InstallerSavePath) {
    $InstallerSavePathExists = $True
} else {
    try {
        New-Item -ItemType Directory -Path $InstallerSavePath | Out-Null
        $InstallerSavePathExists
    } catch {
        Throw 'Save path does not exist and could not be created.'
    }
}

if ($InstallerSavePathExists) {
    $AdobeReaderDownloadURL = [System.UriBuilder]$AdobeDownloadURL
    $AdobeReaderFileName = [System.IO.Path]::GetFileName($AdobeReaderDownloadURL.ToString())
    $AdobeReaderFileNameNoExt = [System.IO.Path]::GetFileNameWithoutExtension($AdobeReaderDownloadURL.ToString())
    $InstallerOutputPath = Join-Path -Path $InstallerSavePath -ChildPath $AdobeReaderFileName
    Invoke-WebRequest -Uri $AdobeReaderDownloadURL.ToString() -OutFile $InstallerOutputPath
}
if (Test-Path $Win32ContentPrepToolPath) {
    if (Test-Path $PackageOutputPath) {
        $PackageOutputPathExists = $True
    } else {
        try {
            New-Item -ItemType Directory -Path $PackageOutputPath | Out-Null
            $PackageOutputPathExists = $True
        } catch {
            Throw 'Package output path does not exist and could not be created.'
        }
    }
} else {
    Throw 'Win 32 Content Prep Tool not found. Make sure you provided the full path including the filename "IntuneWinAppUtil.exe".'
}
$PackageOutputFile = Join-Path -Path $PackageOutputPath -ChildPath "$AdobeReaderFileNameNoExt.intunewin"
if ($PackageOutputPathExists -and (-not(Test-Path $PackageOutputFile))) {
    $OriginalWorkingDirectory = $PWD
    Set-Location $InstallerSavePath
    Start-Process -FilePath $Win32ContentPrepToolPath -ArgumentList "-c $InstallerSavePath -s $AdobeReaderFileName -o $PackageOutputPath -q" -Wait -NoNewWindow
    Set-Location $OriginalWorkingDirectory
} elseif (Test-Path $PackageOutputFile) {
    Write-Host '-------------------------------------------------------------------------------'
    Write-Host 'IntuneWin package already exists for the latest release of Adobe Reader DC.'
    Write-Host "Package is located in $PackageOutputFile"
    Write-Host "To install silently with auto updates enabled use $AdobeReaderInstallParameters"
    Write-Host '-------------------------------------------------------------------------------'
} else {
  Throw 'IntuneWin package not created.'
}
$ProgressPreference = $OriginalProgressPreference
