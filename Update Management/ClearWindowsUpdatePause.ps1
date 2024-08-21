<#
    .SYNOPSIS
        Update Management - Clear Windows Update Pause
    .DESCRIPTION
        This script will check if Windows Update is paused and clear the pause if it is. The script will check the following registry keys for the pause: Policy Manager, Windows Update Policies, and Windows Update. If the pause is detected, the script will clear the pause and provide information on what was paused.

        WARNING: This script removes entire registry keys, if you do not have a system / script or GPO in place to reassert these settings you may want to reconsider running this script.
    .NOTES
        2024-08-21: V1.1 - Add NinjaOne script variables and parameter support to allow running in Test, Clear or Report modes with optional NinjaOne field names. Clear and Report can be used together. Clear implies Test.
        2024-08-20: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
[CmdletBinding()]
param(
    # Test for the pause state.
    [Parameter(Mandatory, ParameterSetName = 'Test')]
    [switch]$Test,
    # Clear the pause state.
    [Parameter(Mandatory, ParameterSetName = 'Clear')]
    [Parameter(ParameterSetName = 'Report')]
    [switch]$Clear,
    # Report the pause state.
    [Parameter(Mandatory, ParameterSetName = 'Report')]
    [switch]$Report,
    # NinjaOne field name for the report. Use a checkbox field type.
    [Parameter(ParameterSetName = 'Report')]
    [string]$NinjaOneField = 'windowsUpdatePaused',
    # Include detailed information in the report.
    [Parameter(ParameterSetName = 'Report')]
    [switch]$IncludeDetails,
    # NinjaOne field name for the detailed information in the report. Use a multi-line text field type.
    [Parameter(ParameterSetName = 'Report')]
    [string]$NinjaOneDetailsField = 'windowsUpdatePausedDetails'
)
# Check for environment variables.
if ($ENV:Test -and [boolean]::Parse($ENV:Test)) {
    $Test = $true
}
if ($ENV:Clear -and [boolean]::Parse($ENV:Clear)) {
    $Clear = $true
}
if ($ENV:Report -and [boolean]::Parse($ENV:Report)) {
    $Report = $true
}
if ($ENV:NinjaOneField) {
    $NinjaOneField = $ENV:NinjaOneField
}
if ($ENV:IncludeDetails -and [boolean]::Parse($ENV:IncludeDetails)) {
    $IncludeDetails = $true
}
if ($ENV:NinjaOneDetailsField) {
    $NinjaOneDetailsField = $ENV:NinjaOneDetailsField
}
$PolicyManagerRegistryKey = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Update'
$WUPoliciesRegistryKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$WURegistryKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy'
$WUSettingsRegistryKey = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UpdatePolicy\Settings'
# Test to see if we're paused.
$WUPause = @{
    Feature = $false
    Quality = $false
    PolicyManager = $false
    Policies = $false
    WindowsUpdate = $false
}
# Check the policy manager registry key.
if (Get-ItemProperty -Path $PolicyManagerRegistryKey -Name 'PauseFeatureUpdates' -ErrorAction SilentlyContinue) {
    if ((Get-ItemPropertyValue -Path $PolicyManagerRegistryKey -Name 'PauseFeatureUpdates' -ErrorAction SilentlyContinue) -eq 1) {
        $WUPause.Feature = $true
        $WUPause.PolicyManager = $true
    }
}
if (Get-ItemProperty -Path $PolicyManagerRegistryKey -Name 'PauseQualityUpdates' -ErrorAction SilentlyContinue) {
    if ((Get-ItemPropertyValue -Path $PolicyManagerRegistryKey -Name 'PauseQualityUpdates' -ErrorAction SilentlyContinue) -eq 1) {
        $WUPause.Quality = $true
        $WUPause.PolicyManager = $true
    }
}
# Check the Windows Update Policies registry key.
if (Get-ItemProperty -Path $WUPoliciesRegistryKey -Name 'PauseDeferrals' -ErrorAction SilentlyContinue) {
    if ((Get-ItemPropertyValue -Path $WUPoliciesRegistryKey -Name 'PauseDeferrals' -ErrorAction SilentlyContinue) -eq 1) {
        $WUPause.Feature = $true
        $WUPause.Quality = $true
        $WUPause.Policies = $true
    }
}
# Check the Windows Update registry key.
if (Get-ItemProperty -Path $WURegistryKey -Name 'PausedFeatureStatus' -ErrorAction SilentlyContinue) {
    if ((Get-ItemPropertyValue -Path $WUSettingsRegistryKey -Name 'PausedFeatureStatus' -ErrorAction SilentlyContinue) -eq 1) {
        $WUPause.Feature = $true
        $WUPause.WindowsUpdate = $true
    }
}
if (Get-ItemProperty -Path $WURegistryKey -Name 'PausedQualityStatus' -ErrorAction SilentlyContinue) {
    if ((Get-ItemPropertyValue -Path $WUSettingsRegistryKey -Name 'PausedQualityStatus' -ErrorAction SilentlyContinue) -eq 1) {
        $WUPause.Quality = $true
        $WUPause.WindowsUpdate = $true
    }
}
$ReportOutput = [System.Text.StringBuilder]::new()
$ErrorOutput = [System.Text.StringBuilder]::new()
if ($WUPause.Feature -or $WUPause.Quality -or $WUPause.PolicyManager -or $WUPause.Policies -or $WUPause.WindowsUpdate) {
    Write-Warning 'Windows Update is paused.'
    $null = $ReportOutput.AppendLine('Windows Update is paused.')
    # Provide information on what is paused.
    if ($WUPause.Feature) {
        Write-Host 'Feature updates are paused.'
        $null = $ReportOutput.AppendLine('Feature updates are paused.')
    }
    if ($WUPause.Quality) {
        Write-Host 'Quality updates are paused.'
        $null = $ReportOutput.AppendLine('Quality updates are paused.')
    }
    if ($WUPause.PolicyManager) {
        Write-Host 'Paused by Policy Manager registry key.'
        $null = $ReportOutput.AppendLine('Paused by Policy Manager registry key.')
        if ($Clear) {
            # Clear the policy manager registry key.
            try {
                Write-Host 'Clearing Policy Manager registry key.'
                Remove-Item -Recurse -Path $PolicyManagerRegistryKey -ErrorAction Stop
            } catch {
                $null = $ErrorOutput.AppendLine("Failed to clear Policy Manager registry key: $_")
            }
        }
    }
    if ($WUPause.Policies) {
        Write-Host 'Paused by Windows Update Policies registry key.'
        $null = $ReportOutput.AppendLine('Paused by Windows Update Policies registry key.')
        if ($Clear) {
            # Clear the Windows Update Policies registry key.
            try {
                Write-Host 'Clearing Windows Update Policies registry key.'
                Remove-Item -Recurse -Path $WUPoliciesRegistryKey -ErrorAction Stop
            } catch {
                $null = $ErrorOutput.AppendLine("Failed to clear Windows Update Policies registry key: $_")
            }
        }
    }
    if ($WUPause.WindowsUpdate) {
        Write-Host 'Paused by Windows Update registry key.'
        $null = $ReportOutput.AppendLine('Paused by Windows Update registry key.')
        if ($Clear) {
            # Clear the Windows Update registry key.
            try {
                Write-Host 'Clearing Windows Update registry key.'
                Remove-Item -Recurse -Path $WURegistryKey -ErrorAction Stop
            } catch {
                $null = $ErrorOutput.AppendLine("Failed to clear Windows Update registry key: $_")
            }
        }
    }
    if ($Report -and $NinjaOneField) {
        # Report the pause state.
        Ninja-Property-Set $NinjaOneField 1
        if ($IncludeDetails -and $NinjaOneDetailsField -and $ReportOutput.Length -gt 0) {
            $ReportOutput.ToString() | Ninja-Property-Set-Piped $NinjaOneDetailsField
        }
    }
    if ($ErrorOutput.Length -gt 0) {
        throw $ErrorOutput.ToString()
    }
} else {
    Write-Host 'Windows Update is not paused.'
}