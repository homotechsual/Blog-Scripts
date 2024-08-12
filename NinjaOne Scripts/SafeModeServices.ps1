<#
    .SYNOPSIS
        Ninja Scripts - Safe Mode Services
    .DESCRIPTION
        This script will allow the NinjaOne agent and NinjaOne remote services to run in Safe Mode with Networking.
    .NOTES
        2024-08-12 - Fix incorrect handling of default parameter set.
        2024-07-25 - Fix bug where the registry function wasn't correctly handling setting the default value.
        2024-07-23 - Fix bug where the incorrect keys were being set in the registry. Thanks to @MisterC on NinjaOne Discord for pointing this out and sharing their code to fix it.
        2024-07-19 - Initial version
    .LINK
        Blog post: Not blogged yet
#>
# Utility Function: Registry.ShouldBe
## This function is used to ensure that a registry value exists and is set to a specific value.
function Registry.ShouldBe {
    [CmdletBinding(DefaultParameterSetName = 'Named')]
    param(
        # The registry path to the key.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [String]$Path,
        # The name of the registry value.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [String]$Name,
        # The value to set the registry value to.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Object]$Value,
        # The type of the registry value.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord', 'None')]
        [Microsoft.Win32.RegistryValueKind]$Type,
        # Don't confirm that the registry value was set correctly.
        [Parameter(ParameterSetName = 'Named')]
        [Parameter(ParameterSetName = 'Default')]
        [Switch]$SkipConfirmation,
        # Use 'Default' parameter set if no name is provided.
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Switch]$Default
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
        if ($Name) {
            do {
                # Handle named registry values.
                # Make sure the registry value exists.
                if (!(Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
                    Write-Warning ("Registry value '$Name' in path '$Path' does not exist. Setting to '$Value'.")
                    New-ItemProperty -Path $Path -Name $Name -Value $Value -Force -Type $Type | Out-Null
                }
                # Make sure the registry value type is correct. Skip if it's a None type.
                if ($Type -ne [Microsoft.Win32.RegistryValueKind]::None) {
                    if ((Get-Item -Path $Path).GetValueKind($Name) -ne $Type) {
                        Write-Warning ("Registry value '$Name' in path '$Path' is not of type '$Type'. Resetting to '$Type', '$Value'.")
                        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
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
        } else {
            do {
                # Handle default registry values.
                # Make sure the registry value exists.
                $RegistryValue = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
                if (!$RegistryValue -or !$RegistryValue.'(default)') {
                    Write-Warning ("Registry value in path '$Path' does not exist. Setting to '$Value'.")
                    New-ItemProperty -Path $Path -Value $Value -Force -Name '(default)' -Type $Type | Out-Null
                }
                # Make sure the registry value type is correct. Skip if it's a None type.
                if ($Type -ne [Microsoft.Win32.RegistryValueKind]::None) {
                    if ((Get-Item -Path $Path).GetValueKind('') -ne $Type) {
                        Write-Warning ("Registry value in path '$Path' is not of type '$Type'. Resetting to '$Type', '$Value'.")
                        Set-ItemProperty -Path $Path -Value $Value -Type $Type
                    }
                }
                # Make sure the registry value is correct.
                if (!$SkipConfirmation) {
                    if ((Get-ItemProperty -Path $Path).'(default)' -ne $Value) {
                        Write-Warning ("Registry value in path '$Path' is not correct. Setting to '$Value'.")
                        Set-ItemProperty -Path $Path -Value $Value
                    }
                    $LoopCount++
                } else {
                    # Short circuit the loop if we're skipping confirmation.
                    $LoopCount = 3
                }
            } while ((Get-ItemProperty -Path $Path).'(default)' -ne $Value -and $LoopCount -lt 3)
        }        
    }
}
$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\SafeBoot\Network'
Registry.ShouldBe -Path (Join-Path $RegPath 'NinjaRMMAgent') -Type 'String' -Value 'Service' -Default
Registry.ShouldBe -Path (Join-Path $RegPath 'ncstreamer') -Type 'String' -Value 'Service' -Default