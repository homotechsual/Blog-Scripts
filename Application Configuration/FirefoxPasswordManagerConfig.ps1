<#
    .SYNOPSIS
        Application Configuration - Disable Firefox Password Storage
    .DESCRIPTION
        This script disables the Firefox password manager using the registry and then clears existing passwords by removing the contents of `$ENV:\SystemDrive\Users\*\AppData\Local\Microsoft\Edge\User Data\*\Login Data`. By necessity this script will force-end any running Edge processes.
    .EXAMPLE
        .\FirefoxPasswordManagerConfig.ps1 -RemoveExistingPasswords -DisablePasswordManager

        Disables the Firefox password manager and removes any existing passwords.
    .EXAMPLE
        .\FirefoxPasswordManagerConfig.ps1 -RemoveExistingPasswords

        Removes any existing passwords.
    .EXAMPLE
        .\FirefoxPasswordManagerConfig.ps1 -DisablePasswordManager

        Disables the Firefox password manager.
    .NOTES
        2023-12-18: Initial version.
    .LINK
        Blog post: https://homotechsual.dev/2023/12/18/browser-password-manager-configuration/
#>
[CmdletBinding()]
param(
    [Parameter()]
    [switch]$RemoveExistingPasswords,
    [Parameter()]
    [switch]$DisablePasswordManager
)
# Utility Function: Registry.ShouldBe
## This function is used to ensure that a registry value exists and is set to a specific value.
function Registry.ShouldBe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Value,
        [Parameter(Mandatory)]
        [ValidateSet('String','ExpandString','Binary','DWord','MultiString','QWord')]
        [string]$Type
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
    }
    process {
        do {
            # Make sure the registry value exists.
            if (!(Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
                Write-Warning ("Registry value '$Name' in path '$Path' does not exist. Setting to '$Value'.")
                New-ItemProperty -Path $Path -Name $Name -Value $Value -Force | Out-Null
            }
            # Make sure the registry value is correct.
            if ((Get-ItemProperty -Path $Path -Name $Name).$Name -ne $Value) {
                Write-Warning ("Registry value '$Name' in path '$Path' is not correct. Setting to '$Value'.")
                Set-ItemProperty -Path $Path -Name $Name -Value $Value
            }
        } while ((Get-ItemProperty -Path $Path -Name $Name).$Name -ne $Value)
    }
}
# Disable the Firefox password manager.
if ($DisablePasswordManager) {
    # Disable the Firefox password manager.
    Write-Host "Disabling the Firefox password manager."
    Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox' -Name 'PasswordManagerEnabled' -Value 0 -Type DWord
}
# Remove existing passwords.
if ($RemoveExistingPasswords) {
    # Get the Firefox process(es).
    $FirefoxProcesses = Get-Process -Name 'firefox' -ErrorAction SilentlyContinue
    # If there are any Firefox processes, kill them.
    if ($FirefoxProcesses) {
        Write-Host "Killing Firefox processes."
        $FirefoxProcesses | Stop-Process -Force
    }
    # Get the Firefox user data directories.
    $UserPath = Join-Path -Path $ENV:SystemDrive -ChildPath 'Users'
    $UserProfiles = Get-ChildItem -Path $UserPath -Directory -ErrorAction SilentlyContinue
    $FirefoxPasswordFiles = foreach ($UserProfile in $UserProfiles) {
        $FirefoxProfilePath = Join-Path -Path $UserProfile.FullName -ChildPath 'AppData\Roaming\Mozilla\Firefox\Profiles\'
        $FirefoxProfiles = Get-ChildItem -Path $FirefoxProfilePath -Directory -ErrorAction SilentlyContinue
        foreach ($FirefoxProfile in $FirefoxProfiles) {
            $FirefoxLoginsFile = Join-Path -Path $FirefoxProfile.FullName -ChildPath 'logins.json'
            if (Test-Path -Path $FirefoxLoginsFile) {
                $FirefoxLoginsFile
            } else {
                Write-Warning ('User {0} profile {1} does not have a password file.' -f $UserProfile.Name, $FirefoxProfile.Name)
            }
            $FirefoxKeyFiles = Resolve-Path -Path (Join-Path -Path $FirefoxProfile.FullName -ChildPath 'key*')
            if ($FirefoxKeyFiles) {
                foreach ($FirefoxKeyFile in $FirefoxKeyFiles) {
                    $FirefoxKeyFile
                }
            } else {
                Write-Warning ('User {0} profile {1} does not have a key file.' -f $UserProfile.Name, $FirefoxProfile.Name)
            }
        }
    }
    # If there are any Firefox password files, remove them.
    if ($FirefoxPasswordFiles) {
        Write-Host "Removing existing passwords."
        foreach ($FirefoxPasswordFile in $FirefoxPasswordFiles) {
            Remove-Item -Force -Path $FirefoxPasswordFile
        }
    }
}