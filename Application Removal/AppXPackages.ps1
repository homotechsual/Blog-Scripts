<#
    .SYNOPSIS
        Application Removal - Windows - AppX Packages
    .DESCRIPTION
        This script is used to remove AppX packages from a Windows machine. The script will attempt to remove the packages for the current user and all users. If the packages are provisioned, it will also deprovision the packages. Accepts input from a NinjaOne script variable named "PackageNames" which should be a comma separated list of package names.

        Use a checkbox script variable to allow wildcard / partial matches. This should be named "AllowWildcards".
    .NOTES
        2024-08-14: Fix deprovisioning logic and suppress Write-Host warning.
        2024-08-14: Initial version
    .LINK
        Blog post: Not blogged yet
#>
# Utility Function: AppPackage.RemoveandDeprovision
## This function is used to ensure that an app package is uninstalled for all users and deprovisioned.
function AppPackage.RemoveandDeprovision {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Runs as RMM script. Write-Host is acceptable.')]
    param(
        # An array of package names to remove.
        [Parameter(Mandatory)]
        [string[]]$PackageNames,
        # Allow wildcard / partial matches.
        [switch]$AllowWildcards
    )
    $exitvalue = 0
    foreach ($PackageName in $PackageNames) {
        Write-Host ('Checking if package {0} is installed...' -f $PackageName)
        $PackageRemovalLoopCount = 0
        # Try current user remove.
        do {
            Write-Host ('Attempt {0} to find and remove package {1}.' -f $PackageRemovalLoopCount, $PackageName)
            $PackageRemovalLoopCount++
            $Package = if ($AllowWildcards) {
                Get-AppxPackage | Where-Object { $_.Name -like ('*{0}*' -f $PackageName) }
            } else {
                Get-AppxPackage -Name $PackageName
            }
            if ($Package) {
                try {
                    # Uninstall the app package
                    $null = $Package | Remove-AppxPackage
                    Start-Sleep -Seconds 5
                    Write-Host ('Package {0} has been successfully uninstalled.' -f $PackageName)
                } catch {
                    Write-Error ('Failed to uninstall package {0}. Error: {1}' -f $PackageName, $_)
                    $exitvalue++
                }
            } else {
                Write-Host ('Package {0} is not installed or not found. Skipping uninstallation.' -f $PackageName)
            }
        } until (($null -eq $Package) -or $PackageRemovalLoopCount -eq 3)
        # Try all users remove.
        do {
            Write-Host ('Attempt {0} to find and remove package {1}.' -f $PackageRemovalLoopCount, $PackageName)
            $PackageRemovalLoopCount++
            $Package = if ($AllowWildcards) {
                Get-AppxPackage -AllUsers | Where-Object { $_.Name -like ('*{0}*' -f $PackageName) }
            } else {
                Get-AppxPackage -AllUsers -Name $PackageName
            }
            if ($Package) {
                try {
                    # Uninstall the app package
                    $null = $Package | Remove-AppxPackage -AllUsers
                    Start-Sleep -Seconds 5
                    Write-Host ('Package {0} has been successfully uninstalled.' -f $PackageName)
                } catch {
                    Write-Error ('Failed to uninstall package {0}. Error: {1}' -f $PackageName, $_)
                    $exitvalue++
                }
            } else {
                Write-Host ('Package {0} is not installed or not found. Skipping uninstallation.' -f $PackageName)
            }
        } until (($null -eq $Package) -or $PackageRemovalLoopCount -eq 3)
        $Package = if ($AllowWildcards) {
            Get-AppxPackage -AllUsers | Where-Object { $_.Name -like ('*{0}*' -f $PackageName) }
        } else {
            Get-AppxPackage -AllUsers -Name $PackageName
        }
        if ($Package) {
            Write-Error ('Failed to uninstall package {0} after 3 attempts. Please see the error messages above.' -f $PackageName)
            $exitvalue++
        }
        try {
            # Deprovision the app package
            if ($AllowWildcards) {
                Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like ('*{0}*' -f $PackageName) } | Remove-AppxProvisionedPackage -AllUsers -Online
            } else {
                Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $PackageName } | Remove-AppxProvisionedPackage -AllUsers -Online
            }
            Write-Host ('Package {0} has been deprovisioned.' -f $PackageName) 
        } catch {
            Write-Error ('Failed to deprovision app package {0}. Error: {1}' -f $PackageName, $_)
            $exitvalue++
        }
    }
    return $exitvalue
}
if ([string]::IsNullOrWhiteSpace($ENV:PackageNames)) {
    throw 'No package names were found. Please ensure your script variable has the machine name "PackageNames" and contains a comma separated list of package names.'
}
if ([string]::IsNullOrWhiteSpace($ENV:AllowWildcards)) {
    $AllowWildcards = $false
} else {
    $AllowWildcards = [boolean]::Parse($ENV:AllowWildcards)
}
$PackageNames = ($ENV:PackageNames.Split(',').Trim())
if ($PackageNames.Count -ge 1) {
    AppPackage.RemoveandDeprovision -PackageNames $PackageNames -AllowWildcards:$AllowWildcards
} else {
    throw 'No package names were found. Please ensure your script variable has the machine name "PackageNames" and contains a comma separated list of package names.'
}