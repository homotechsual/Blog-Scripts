<#
    .SYNOPSIS
        Device Setup - Bloatware Removal - HP.ps1
    .DESCRIPTION
        This script removes bloatware from HP devices. Intended to be run as part of a device setup process. Run without any parameters this will remove all AppX packages for HP's prefix and the programs in the $UninstallPrograms array.
    .NOTES
        2023-05-18: Initial version
    .LINK
        Blog post: https://homotechsual.dev
#>
[CmdletBinding()]
param (
    # List of AppX packages to keep
    [String[]]$KeepPackages,
    # List of programs to keep
    [String[]]$KeepPrograms,
    # Limit number of retries for uninstalling programs
    [Int]$MaxRetryCount = 3
)
# List of built-in apps to remove
$UninstallPackages = @(
    'AD2F1837.HPJumpStarts'
    'AD2F1837.HPPCHardwareDiagnosticsWindows'
    'AD2F1837.HPPowerManager'
    'AD2F1837.HPPrivacySettings'
    'AD2F1837.HPSupportAssistant'
    'AD2F1837.HPSureShieldAI'
    'AD2F1837.HPSystemInformation'
    'AD2F1837.HPQuickDrop'
    'AD2F1837.HPWorkWell'
    'AD2F1837.myHP'
    'AD2F1837.HPDesktopSupportUtilities'
    'AD2F1837.HPEasyClean'
    'AD2F1837.HPSystemInformation'
)
# List of programs to uninstall
$UninstallPrograms = @(
    'HP Connection Optimizer'
    'HP Documentation'
    'HP MAC Address Manager'
    'HP Notifications'
    'HP Security Update Service'
    'HP System Default Settings'
    'HP Sure Click'
    'HP Sure Run'
    'HP Sure Recover'
    'HP Sure Sense'
    'HP Sure Sense Installer'
    'HP Wolf Security Application Support for Sure Sense'
    'HP Wolf Security Application Support for Windows'
    'HP Client Security Manager'
    'HP Wolf Security'
    'HP Wolf Security - Console'
    'HP Sure Run Module'
    'ICS'
)
$HPidentifier = 'AD2F1837'
$UninstallRegKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'
)
$HPConnectionOptimizerISSAnswerFilePath = "$env:TEMP\HPConnectionOptimizer.iss"
$HPConnectionOptimizerUninstallProperties = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{6468C4A5-E47E-405F-B675-A70A70983EA6}' -ErrorAction SilentlyContinue
$GUID = $HPConnectionOptimizerUninstallProperties.ProductGuid
$Version = $HPConnectionOptimizerUninstallProperties.DisplayVersion
$HPConnectionOptimizerISSAnswerFile = @"
[InstallShield Silent]
Version=v7.00
File=Response File
[File Transfer]
OverwrittenReadOnly=NoToAll
[-DlgOrder]
Dlg0=$GUID-SdWelcomeMaint-0
Count=3
Dlg1=$GUID-MessageBox-0
Dlg2=$GUID-SdFinishReboot-0
[$GUID-SdWelcomeMaint-0]
Result=303
[$GUID-MessageBox-0]
Result=6
[Application]
Name=HP Connection Optimizer
Version=$Version
Company=HP Inc.
Lang=0409
[$GUID-SdFinishReboot-0]
Result=1
BootOption=0
"@
$HPConnectionOptimizerISSAnswerFile | Out-File -FilePath $HPConnectionOptimizerISSAnswerFilePath

# Convert the uninstall string to the path to the uninstall exe.
function Convert-UninstallStringToExe ([string]$UninstallString) {
    $EXEPosition = $UninstallString.IndexOf('.exe')
    $QuotePosition = $UninstallString.IndexOf('"')

    if (($EXEPosition -ne -1) -and (($QuotePosition -eq -1) -or ($QuotePosition -gt $EXEPosition))) {
        $EXEPath = '"' + $UninstallString.Substring(0, $EXEPosition + 4) + '"' + $UninstallString.Substring($EXEPosition + 4)
        $EXEPath
    } else {
        $UninstallString
    }
}

# Remove provisioned packages first
Do {
    $ProvisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { (($UninstallPackages -contains $_.DisplayName) -or ($_.DisplayName -match "^$HPidentifier")) -and ($KeepPackages -notcontains $_.DisplayName) }
    ForEach ($ProvPackage in $ProvisionedPackages) {
        Write-Output "Attempting to remove provisioned package: [$($ProvPackage.DisplayName)]..."
        Try {
            Remove-AppxProvisionedPackage -PackageName $ProvPackage.PackageName -Online -AllUsers -ErrorAction Stop | Out-Null
            Write-Output "Successfully removed provisioned package: [$($ProvPackage.DisplayName)]"
        } Catch {
            Write-Warning -Message "Failed to remove provisioned package: [$($ProvPackage.DisplayName)]"
        }
    }
} While ($ProvisionedPackages)
# Remove appx packages
Do {
    $InstalledPackages = Get-AppxPackage -AllUsers | Where-Object { (($UninstallPackages -contains $_.Name) -or ($_.Name -match "^$HPidentifier")) -and ($KeepPackages -notcontains $_.Name) }
    ForEach ($AppxPackage in $InstalledPackages) {                                           
        Write-Output "Attempting to remove Appx package: [$($AppxPackage.Name)]..."
        Try {
            Remove-AppxPackage -Package $AppxPackage.PackageFullName -AllUsers -ErrorAction Stop | Out-Null
            Write-Output "Successfully removed Appx package: [$($AppxPackage.Name)]"
        } Catch {
            Write-Warning -Message "Failed to remove Appx package: [$($AppxPackage.Name)]"
        }
    }
} While ($InstalledPackages)
# Remove installed programs
## We use a do-while loop here because we can't always wait for the uninstall to complete.
### Registry method first - usually more reliable.
Do {
    $InstalledPrograms = $UninstallRegKeys | Get-ChildItem | Get-ItemProperty | Where-Object { (($UninstallPrograms -contains $_.DisplayName) -and ($_.QuietUninstallString -or $_.UninstallString)) -and ($KeepPrograms -notcontains $_.DisplayName) }
    ForEach ($InstalledProgram in $InstalledPrograms) {
        if ($InstalledProgram -like '*HP Connection Optimizer*') {
            Write-Output 'Rewriting quiet uninstall string for HP Connection Optimizer to use ISS answer file...'
            $PathToEXE = Convert-UninstallStringToExe -UninstallString $InstalledProgram.UninstallString
            $SetupFile = $PathToEXE.Substring(0, $PathToEXE.IndexOf('.exe') + 5)
            $InstalledProgram.QuietUninstallString = ('{0} /s /f1"{1}"' -f $SetupFile, $HPConnectionOptimizerISSAnswerFilePath)
        }
        $UninstallString = if ($InstalledProgram.QuietUninstallString) {
            $InstalledProgram.QuietUninstallString
        } elseif ($InstalledProgram.UninstallString -match '^msiexec') {
            "$($InstalledProgram.UninstallString -replace '/I', '/X') /qn /norestart /quiet"
        } else {
            $InstalledProgram.UninstallString
        }
        Write-Output "Attempting to uninstall: [$($InstalledProgram.DisplayName)]..."
        try {
            Start-Process -FilePath 'cmd' -ArgumentList '/c', $UninstallString -Wait -NoNewWindow -ErrorAction Stop
        } catch {
            Write-Warning -Message "Failed to uninstall: [$($InstalledProgram.DisplayName)]"
        }
    }
} while ($InstalledPrograms)
### Package manager method second - sometimes less reliable but should catch anything the registry method missed.
$Retries = 0
Do {
    $Retries++
    $InstalledPrograms = Get-Package | Where-Object { $UninstallPrograms -contains $_.Name }
    ForEach ($InstalledProgram in $InstalledPrograms) {
        Write-Output "Attempting to uninstall: [$($InstalledProgram.Name)]..."
        Try {
            $InstalledProgram | Uninstall-Package -AllVersions -Force -ErrorAction Stop | Out-Null
            Write-Output "Successfully uninstalled: [$($InstalledProgram.Name)]"
        } Catch {
            Write-Warning -Message "Failed to uninstall: [$($InstalledProgram.Name)]"
        }
    }
} While ($InstalledPrograms -and ($Retries -lt $MaxRetryCount))
# Remove HP offers and shortcuts
$PathsToCleanup = @('C:\ProgramData\HP\TCO', 'C:\Online Services', 'C:\Users\Public\Desktop\TCO Certified.lnk', 'C:\Program Files (x86)\Online Services', 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Adobe offers.lnk')
ForEach ($Path in $PathsToCleanup) {
    if (Test-Path -Path $Path) {
        Write-Output "Attempting to remove: [$Path]..."
        Try {
            Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop | Out-Null
            Write-Output "Successfully removed: [$Path]"
        } Catch {
            Write-Warning -Message "Failed to remove: [$Path]"
        }
    }
}