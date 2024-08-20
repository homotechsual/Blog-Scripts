<#
    .SYNOPSIS
        Update Management - Clear Windows Update Pause
    .DESCRIPTION
        This script will check if Windows Update is paused and clear the pause if it is. The script will check the following registry keys for the pause: Policy Manager, Windows Update Policies, and Windows Update. If the pause is detected, the script will clear the pause and provide information on what was paused.

        WARNING: This script removes entire registry keys, if you do not have a system / script or GPO in place to reassert these settings you may want to reconsider running this script.
    .NOTES
        2024-08-20: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
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
if ($WUPause.Feature -or $WUPause.Quality -or $WUPause.PolicyManager -or $WUPause.Policies -or $WUPause.WindowsUpdate) {
    Write-Warning 'Windows Update is paused.'
    # Provide information on what is paused.
    if ($WUPause.Feature) {
        Write-Host 'Feature updates are paused.'
    }
    if ($WUPause.Quality) {
        Write-Host 'Quality updates are paused.'
    }
    if ($WUPause.PolicyManager) {
        Write-Host 'Paused by Policy Manager registry key.'
        # Clear the policy manager registry key.
        Remove-Item -Recurse -Path $PolicyManagerRegistryKey -ErrorAction SilentlyContinue
    }
    if ($WUPause.Policies) {
        Write-Host 'Paused by Windows Update Policies registry key.'
        # Clear the Windows Update Policies registry key.
        Remove-Item -Recurse -Path $WUPoliciesRegistryKey -ErrorAction SilentlyContinue
    }
    if ($WUPause.WindowsUpdate) {
        Write-Host 'Paused by Windows Update registry key.'
        # Clear the Windows Update registry key.
        Remove-Item -Recurse -Path $WURegistryKey -ErrorAction SilentlyContinue
    }
} else {
    Write-Host 'Windows Update is not paused.'
}