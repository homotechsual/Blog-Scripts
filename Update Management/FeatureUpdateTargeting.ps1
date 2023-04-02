<#
    .SYNOPSIS
        Update Management - Windows - Set Feature Update Target Version
    .DESCRIPTION
        Sets the various registry keys to set the target version for Windows Update. This can be used to keep machines on Windows 10, instead of upgrading to Windows 11 or to target a specific "maximum" feature update version.
    .NOTES
        2023-02-16: Parameterise the script to allow more control over the target versions
        2022-01-25: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2023/02/16/Targeting-Windows-Versions-for-Feature-Updates/
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'RMM script - not useful to implement ShouldProcess')]
param (
    [Switch]$Test,
    [Switch]$Unset,
    [String]$TargetProductVersion = '22H2',
    [String]$TargetProduct = 'Windows 11'
)
function Test-UpdateSettings {
    $UpdateSettings = Get-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\'
    $Message = [System.Collections.Generic.List[String]]::New()
    if ($UpdateSettings.TargetReleaseVersion -and $UpdateSettings.TargetReleaseVersion -ne 0) {
        $Message.Add('Windows Update is currently set to target a specific release version.')
        if ($UpdateSettings.TargetReleaseVersionInfo) {
            $Message.Add("Target release version: $($UpdateSettings.TargetReleaseVersionInfo.ToString())")
        } else {
            $Message.Add('Target release version is not set.')
        }
        if ($UpdateSettings.ProductVersion) {
            $Message.Add("Product version: $($UpdateSettings.ProductVersion.ToString())")
        } else {
            $Message.Add('Product version is not set.')
        }
    } else {
        $Message.Add('Windows Update is currently set to target all versions.')
    }
    if ($String -is [array] -or $String.Count -gt 0) {
        return $Message.Join(' ')
    } else {
        return $Message
    }
    
}

function Set-UpdateSettings ([switch]$Unset) {
    if ($Unset) {
        try {
            Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\' -Name 'TargetReleaseVersion' -Value 0 -Type DWord
            if (Test-Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\TargetReleaseVersionInfo') {
                Remove-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\' -Name 'TargetReleaseVersionInfo'
            }
            if (Test-Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\ProductVersion') {
                Remove-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\' -Name 'ProductVersion'
            }
        } catch {
            Throw $_
        }
        $Message = 'Windows Update is now set to target all versions.'
    } else {
        try {
            Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\' -Name 'TargetReleaseVersion' -Value 1 -Type DWord
            Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\' -Name 'TargetReleaseVersionInfo' -Value $TargetProductVersion
            Set-ItemProperty -Path 'HKLM:\Software\Policies\Microsoft\Windows\WindowsUpdate\' -Name 'ProductVersion' -Value $TargetProduct
            $Message = 'Windows Update is now set to target Windows 10, 21H2.'
        } catch {
            Throw $_
        }
    }
    return $Message
}

if ($Test) {
    $Message = Test-UpdateSettings
    Write-Output $Message
} elseif ($Unset) {
    $Message = Set-UpdateSettings -Unset
    Write-Output $Message
} else {
    $Message = Set-UpdateSettings
    Write-Output $Message
}