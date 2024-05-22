<#
    .SYNOPSIS
        Device Setup - Bloatware Removal - Generic.ps1
    .DESCRIPTION
        This script removes bloatware from Windows 10 / 11 devices. It is designed to be run as a scheduled task. It only handles generic Windows 10 / 11 bloatware, and does not handle OEM-specific bloatware.
    .NOTES
        2024-05-22: Initial version
    .LINK
        Blog post: Not blogged yet.
#>
# Utility Function: Registry.ShouldBe
## This function is used to ensure that a registry value exists and is set to a specific value.
function Registry.ShouldBe {
    [CmdletBinding()]
    param(
        # The registry path to the key.
        [Parameter(Mandatory)]
        [String]$Path,
        # The name of the registry value.
        [Parameter(Mandatory)]
        [String]$Name,
        # The value to set the registry value to.
        [Parameter(Mandatory)]
        [Object]$Value,
        # The type of the registry value.
        [Parameter(Mandatory)]
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord', 'None')]
        [Microsoft.Win32.RegistryValueKind]$Type,
        # Don't confirm that the registry value was set correctly.
        [Switch]$SkipConfirmation
    )
    begin {
        # Make sure the registry path exists.
        if (!(Test-Path $Path)) {
            Write-Warning ("Registry path '$Path' does not exist. Creating.")
            New-Item -Path $Path -Force | Out-Null
        }
        # Make sure it's actually a registry path.
        if (!(Get-Item $Path).PSProvider.Name -eq 'Registry' -and !(Get-Item $Path).PSIsContainer) {
            throw "Path '$Path' is not a registry path."
        }
        $LoopCount = 0
    }
    process {
        do {
            # Make sure the registry value exists.
            if (!(Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
                Write-Warning ("Registry value '$Name' in path '$Path' does not exist. Setting to '$Value'.")
                New-ItemProperty -Path $Path -Name $Name -Value $Value -Force -Type $Type | Out-Null
            }
            # Make sure the registry value type is correct. Skip if it's a None type.
            if ($Type -ne [Microsoft.Win32.RegistryValueKind]::None) {
                if ((Get-Item -Path $Path).GetValueKind($Name) -ne $Type) {
                    Write-Warning ("Registry value '$Name' in path '$Path' is not of type '$Type'. Resetting to '$Type', '$Value'.")
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value
                }
            }
            # Make sure the registry value is correct.
            if (!$SkipConfirmation) {
                if ((Get-ItemProperty -Path $Path -Name $Name).$Name -ne $Value) {
                    Write-Warning ("Registry value '$Name' in path '$Path' is not correct. Setting to '$Value'.")
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value
                }
                $LoopCount++
            } else {
                # Short circuit the loop if we're skipping confirmation.
                $LoopCount = 3
            }
        } while ((Get-ItemProperty -Path $Path -Name $Name).$Name -ne $Value -and $LoopCount -lt 3)
    }
}
# Disable Windows Consumer Features
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord
# Block Content Delivery for OEM Content
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'ContentDeliveryAllowed' -Value 0 -Type DWord
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'OemPreInstalledAppsEnabled' -Value 0 -Type DWord
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'PreInstalledAppsEnabled' -Value 0 -Type DWord
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'PreInstalledAppsEverEnabled' -Value 0 -Type DWord
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Value 0 -Type DWord
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SystemPaneSuggestionsEnabled' -Value 0 -Type DWord
# Determine Apps to Remove
$AppsToRemove = @(
    'Microsoft.BingNews',
    'Microsoft.Microsoft3DViewer',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.News',
    'Microsoft.OneConnect',
    'Microsoft.People',
    'Microsoft.Print3D',
    'Microsoft.SkypeApp',
    'Microsoft.WindowsCommunicationsApps',
    'Microsoft.Xbox.TCUI',
    'Microsoft.XboxApp',
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.ZuneMusic',
    'Microsoft.ZuneVideo',
    '*EclipseManager*',
    '*ActiproSoftware*',
    '*AdobeSystemsIncorporated.AdobePhotoshopExpress*',
    '*DuoLingo-LearnLanguagesforFree*',
    '*PandoraMediaInc*',
    '*CandyCrush*',
    '*BubbleWitch*',
    '*Wunderlist*',
    '*Flipboard*',
    '*Twitter*',
    '*Facebook*',
    '*TikTok*',
    '*MineCraft*',
    '*Royal Revolt*',
    '*Sway*'
)
# Remove Apps
foreach ($App in $AppsToRemove) {
    Get-AppxPackage -AllUsers | Where-Object { $_.Name -like $App } | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    Write-Output ('Removing app: {0}' -f $App)
}