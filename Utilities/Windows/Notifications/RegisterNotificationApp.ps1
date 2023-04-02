<#
    .SYNOPSIS
        Utilities - Windows - Notifications - Register Notification App
    .DESCRIPTION
        Registers a notification app into the Windows registry allowing toast notifications to be sent using the App's Id which provides for control over the application display name and the app icon.
    .NOTES
        2023-01-17: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2023/01/17/Toast-Notifications-Windows-10-and-11/
#>
#requires -RunAsAdministrator
[CmdletBinding()]
Param(
    # The URI of the app icon to use for the notification app registration.
    [Parameter(Mandatory)]
    [uri]$IconURI,
    # File name to use for the app icon. Optional. If not specified, the file name from the URI will be used.
    [string]$IconFileName,
    # The working directory to use for the app icon. If not specified, 'C:\RMM\NotificationApp\' will be used.
    [System.IO.DirectoryInfo]$WorkingDirectory = 'C:\RMM\NotificationApp\',
    # The app ID to use for the notification app registration. Expected format is something like: 'CompanyName.AppName'.
    [Parameter(Mandatory)]
    [string]$AppId,
    # The app display name to use for the notification app registration.
    [Parameter(Mandatory)]
    [string]$AppDisplayName,
    # The background color to use for the app icon. Optional. If not specified, the background color will be transparent. Expected format is a hex value like 'FF000000' or '0' for transparent.
    [ValidatePattern('^(0)$|^([A-F0-9]{8})$')]
    [string]$AppIconBackgroundColor = 0,
    # Whether or not to show the app in the Windows Settings app. Optional. If not specified, the app will not be shown in the Settings app. Expected values are 0 or 1 (0 = false, 1 = true).
    [int]$ShowInSettings = 0
)
# Functions
function Get-NotificationApp {
    <#
    .SYNOPSIS
        Gets the notification app registration information.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$AppId
    )
    $HKCR = Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue
    If (!($HKCR)) {
        $null = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script
    }
    $AppRegPath = 'HKCR:\AppUserModelId'
    $RegPath = "$AppRegPath\$AppID"
    If (!(Test-Path $RegPath)) {
        return $null
    } else {
        $NotificationApp = Get-Item -Path $RegPath
        return $NotificationApp
    }
}
Function Register-NotificationApp {
    <#
    .SYNOPSIS
        Registers an application to receive toast notifications.
    .NOTES
        Original Author: Trevor Jones
        Original Author Link: https://smsagent.blog/author/trevandju/
        Version: 2.0
        Version Date: 2023-01-17
        Version Description: Added AppIcon and AppIconBackground parameters.
        Version Author: Mikey O'Toole
        Version: 1.0
        Version Date: 2020-10-20
        Version Description: Initial release by Trevor Jones.
    .LINK
        https://smsagent.blog/2020/10/20/adding-your-own-caller-app-for-custom-windows-10-toast-notifications/
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [string]$AppId,
        [Parameter(Mandatory)]
        [string]$AppDisplayName,
        [System.IO.FileInfo]$AppIcon = $null,
        [ValidatePattern('^(0)$|^([A-F0-9]{8})$')]
        [string]$AppIconBackgroundColor = $null,
        [int]$ShowInSettings = 0
    )
    $HKCR = Get-PSDrive -Name HKCR -ErrorAction SilentlyContinue
    If (!($HKCR)) {
        $null = New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT -Scope Script
    }
    $AppRegPath = 'HKCR:\AppUserModelId'
    $RegPath = "$AppRegPath\$AppId"
    If (!(Test-Path $RegPath)) {
        $null = New-Item -Path $AppRegPath -Name $AppId -Force
    }
    $DisplayName = Get-ItemProperty -Path $RegPath -Name DisplayName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DisplayName -ErrorAction SilentlyContinue
    If ($DisplayName -ne $AppDisplayName) {
        $null = New-ItemProperty -Path $RegPath -Name DisplayName -Value $AppDisplayName -PropertyType String -Force
    }
    $Icon = Get-ItemProperty -Path $RegPath -Name IconUri -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IconUri -ErrorAction SilentlyContinue
    if ($Icon -ne $AppIcon) {
        $null = New-ItemProperty -Path $RegPath -Name IconUri -Value $AppIcon -PropertyType String -Force
    }
    $BackgroundColor = Get-ItemProperty -Path $RegPath -Name IconBackgroundColor -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IconBackgroundColor -ErrorAction SilentlyContinue
    if ($BackgroundColor -ne $AppIconBackgroundColor) {
        $null = New-ItemProperty -Path $RegPath -Name IconBackgroundColor -Value $AppIconBackgroundColor -PropertyType String -Force
    }
    $ShowInSettingsValue = Get-ItemProperty -Path $RegPath -Name ShowInSettings -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ShowInSettings -ErrorAction SilentlyContinue
    If ($ShowInSettingsValue -ne $ShowInSettings) {
        $null = New-ItemProperty -Path $RegPath -Name ShowInSettings -Value $ShowInSettings -PropertyType DWORD -Force
    }
    $null = Remove-PSDrive -Name HKCR -Force
}
function Get-AppIcon {
    <#
    .SYNOPSIS
        Downloads the app icon from a URI and saves it to a file.
    #>
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [uri]$IconURI,
        [string]$IconFileName = $null,
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]$WorkingDirectory
    )
    if (!($WorkingDirectory.Exists)) {
        $WorkingDirectory.Create()
    }
    if (!($IconFileName)) {
        $IconFileName = $IconURI.Segments[-1]
    }
    $IconFilePath = Join-Path -Path $WorkingDirectory.FullName -ChildPath $IconFileName
    $IconFile = New-Object System.IO.FileInfo $IconFilePath
    If ($IconFile.Exists) {
        $IconFile.Delete()
    }
    Invoke-WebRequest -Uri $IconURI -OutFile $IconFile.FullName | Out-Null
    return $IconFile.FullName
}
# Main Script
$AppId = $AppId.TrimStart('"').TrimEnd('"')
$AppIcon = Get-AppIcon -IconURI $IconURI -WorkingDirectory $WorkingDirectory
$NotificationAppParams = @{
    AppID = $AppId
    AppDisplayName = $AppDisplayName
    AppIcon = $AppIcon
    AppIconBackgroundColor = $AppIconBackgroundColor
}
if ($ShowInSettings) {
    $NotificationAppParams.Add('ShowInSettings', $ShowInSettings)
}
Register-NotificationApp @NotificationAppParams
$NotificationApp = Get-NotificationApp -AppID $AppId
if (!($NotificationApp)) {
    Write-Error 'Failed to register the notification app.'
    Exit 1
} else {
    Write-Output ('Successfully registered the notification app {0}.' -f $NotificationApp.GetValue('DisplayName'))
    Exit 0
}