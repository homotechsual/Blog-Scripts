<#
    .SYNOPSIS
        Device Setup - Bloatware Removal - Lenovo.ps1
    .DESCRIPTION
        This script removes bloatware from Lenovo devices. Intended to be run as part of a device setup process. Run without any parameters this will remove all AppX packages for Lenovo's prefix and the programs in the $UninstallPrograms array.
    .NOTES
        2026-06-02: Initial version
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
    'LenovoCorporation.LenovoID',
    'LenovoCorporation.LenovoSettings',
    'LenovoCorporation.LenovoUtility',
    'LenovoCorporation.LenovoCompanion',
    'LenovoCorporation.LenovoVantage',
    'LenovoCorporation.LenovoSystemUpdate',
    'LenovoCorporation.LenovoDiagnostics',
    'LenovoCorporation.LenovoSupport',
    'LenovoCorporation.LenovoQuickSettings',
    'E046963F.AIMeetingManager',
    'E0469640.LenovoSmartCommunication',
    'E0469640.SmartAppearance',
    'E046963F.cameraSettings',
    'E046963F.LenovoCompanion'
)
$UninstallPackagePrefixes = @(
    '^LenovoCorporation\.',
    '^E046963F\.',
    '^E0469640\.'
)
# List of programs to uninstall
$UninstallPrograms = @(
    '*McAfee*',
    '*Dolby Audio*',
    '*Lenovo App Explorer*',
    '*Lenovo Smart Meeting*',
    '*Lenovo Smart Meeting Components*',
    '*Lenovo Smart Noise Cancellation*',
    '*Elevoc Smart Noise Cancellation Settings*',
    '*Lenovo Now*',
    '*Lenovo Speech*',
    '*Lenovo Vantage Service*',
    '*Lenovo Smart Appearance Components*',
    '*Lenovo Smart Appearance*',
    '*Lenovo Smart Performance*',
    '*Lenovo Smart Performance Components*',
    '*Lenovo Smart Storage*',
    '*Lenovo Smart Storage Components*'
)
$WingetUninstallPrograms = @(
    'Lenovo Vantage Service',
    'Lenovo Smart Meeting Components',
    'Lenovo Smart Meeting',
    'Lenovo Smart Noise Cancellation',
    'Elevoc Smart Noise Cancellation Settings',
    'WebAdvisor by McAfee'
)
$LenovoSmartMeetingOverrideUninstaller = 'C:\Program Files\Lenovo\Smart Meeting\unins000.exe'
$LenovoSmartMeetingComponentsOverrideUninstaller = 'C:\Program Files\Lenovo\Lenovo Smart Meeting Components\unins000.exe'
$UninstallRegKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'
)

function Test-ShouldRemoveLenovoPackage {
    param (
        [string]$Name
    )

    if ($KeepPackages -contains $Name) {
        return $false
    }

    if ($UninstallPackages -contains $Name) {
        return $true
    }

    foreach ($Prefix in $UninstallPackagePrefixes) {
        if ($Name -match $Prefix) {
            return $true
        }
    }

    return $false
}

function Test-ShouldRemoveLenovoProgram {
    param (
        [string]$Name
    )

    if ($KeepPrograms -contains $Name) {
        return $false
    }

    foreach ($Pattern in $UninstallPrograms) {
        if ($Name -like $Pattern) {
            return $true
        }
    }

    return $false
}

function Get-MatchingLenovoRegistryPrograms {
    $Programs = $UninstallRegKeys | Get-ChildItem | Get-ItemProperty | Where-Object { (Test-ShouldRemoveLenovoProgram $_.DisplayName) -and ($_.QuietUninstallString -or $_.UninstallString) }
    @($Programs | Sort-Object -Property PSPath -Unique)
}

function Get-WinGetPath {
    $WinGetPathToResolve = Join-Path -Path $ENV:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe'
    $ResolveWinGetPath = Resolve-Path -Path $WinGetPathToResolve -ErrorAction SilentlyContinue | Sort-Object {
        [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1')
    }
    if ($ResolveWinGetPath) {
        $WinGetPath = $ResolveWinGetPath[-1].Path
    }

    $WinGetExePath = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($WinGetExePath) {
        return $WinGetExePath.Path
    }

    if ($WinGetPath -and (Test-Path -Path (Join-Path $WinGetPath 'winget.exe'))) {
        return (Join-Path $WinGetPath 'winget.exe')
    }

    return $null
}

function Get-LenovoSmartMeetingOverrideUninstaller {
    param (
        [string]$DisplayName
    )

    if ($DisplayName -like '*Components*') {
        if (Test-Path -Path $LenovoSmartMeetingComponentsOverrideUninstaller) {
            return $LenovoSmartMeetingComponentsOverrideUninstaller
        }
        return $null
    }

    if (Test-Path -Path $LenovoSmartMeetingOverrideUninstaller) {
        return $LenovoSmartMeetingOverrideUninstaller
    }

    if (Test-Path -Path $LenovoSmartMeetingComponentsOverrideUninstaller) {
        return $LenovoSmartMeetingComponentsOverrideUninstaller
    }

    return $null
}

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
    $ProvisionedPackages = Get-AppxProvisionedPackage -Online | Where-Object { Test-ShouldRemoveLenovoPackage $_.DisplayName }
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
    $InstalledPackages = Get-AppxPackage -AllUsers | Where-Object { Test-ShouldRemoveLenovoPackage $_.Name }
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
### Winget method first for packages that publish a reliable winget manifest.
$WinGet = Get-WinGetPath
if ($WinGet) {
    try {
        $null = & $WinGet list --accept-source-agreements -s winget
    } catch {
        Write-Warning -Message 'Failed to pre-accept winget source agreements. Continuing with uninstall attempts.'
    }

    foreach ($WingetProgram in $WingetUninstallPrograms) {
        if ($KeepPrograms -contains $WingetProgram) {
            continue
        }

        Write-Output "Attempting winget uninstall: [$WingetProgram]..."
        try {
            $null = & $WinGet uninstall --name $WingetProgram --exact --silent --accept-source-agreements --disable-interactivity --force
            if ($LASTEXITCODE -eq 0) {
                Write-Output "Winget uninstall completed for: [$WingetProgram]"
            } else {
                Write-Warning -Message "Winget uninstall did not report success for: [$WingetProgram] (exit code: $LASTEXITCODE)"
            }
        } catch {
            Write-Warning -Message "Winget uninstall failed for: [$WingetProgram]"
        }
    }
} else {
    Write-Warning -Message 'winget.exe not found. Skipping winget uninstall phase.'
}

### Custom override path for Lenovo Smart Meeting components.
foreach ($SmartMeetingOverride in @($LenovoSmartMeetingOverrideUninstaller, $LenovoSmartMeetingComponentsOverrideUninstaller)) {
    if (($KeepPrograms -notcontains 'Lenovo Smart Meeting') -and (Test-Path -Path $SmartMeetingOverride)) {
        Write-Output "Attempting custom override uninstall: [$SmartMeetingOverride]..."
        try {
            Start-Process -FilePath $SmartMeetingOverride -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait -NoNewWindow -ErrorAction Stop
        } catch {
            Write-Warning -Message "Failed to run custom Lenovo Smart Meeting override uninstaller: [$SmartMeetingOverride]"
        }
    }
}

### Registry method first - usually more reliable.
$RegistryRetries = 0
Do {
    $RegistryRetries++
    $InstalledPrograms = Get-MatchingLenovoRegistryPrograms

    if ($InstalledPrograms.Count -gt 0) {
        Write-Output "Registry uninstall pass [$RegistryRetries/$MaxRetryCount] found [$($InstalledPrograms.Count)] matching entries."
    }

    ForEach ($InstalledProgram in $InstalledPrograms) {
        $SmartMeetingOverride = if ($InstalledProgram.DisplayName -like 'Lenovo Smart Meeting*') {
            Get-LenovoSmartMeetingOverrideUninstaller -DisplayName $InstalledProgram.DisplayName
        } else {
            $null
        }

        $UninstallString = if ($SmartMeetingOverride) {
            ('"{0}" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' -f $SmartMeetingOverride)
        } elseif ($InstalledProgram.QuietUninstallString) {
            $InstalledProgram.QuietUninstallString
        } elseif ($InstalledProgram.UninstallString -match '^msiexec') {
            "$($InstalledProgram.UninstallString -replace '/I', '/X') /qn /norestart /quiet"
        } elseif ($InstalledProgram.PSChildName -like '*_is1') {
            "$(Convert-UninstallStringToExe -UninstallString $InstalledProgram.UninstallString) /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-"
        } else {
            $InstalledProgram.UninstallString
        }
        Write-Output "Attempting to uninstall: [$($InstalledProgram.DisplayName)] using key [$($InstalledProgram.PSChildName)]..."
        try {
            Start-Process -FilePath 'cmd' -ArgumentList '/c', $UninstallString -Wait -NoNewWindow -ErrorAction Stop
            $StillInstalled = Get-MatchingLenovoRegistryPrograms | Where-Object { $_.PSPath -eq $InstalledProgram.PSPath }
            if ($StillInstalled) {
                Write-Warning -Message "Uninstall command completed but entry still exists: [$($InstalledProgram.DisplayName)] key [$($InstalledProgram.PSChildName)]."
            } else {
                Write-Output "Successfully uninstalled: [$($InstalledProgram.DisplayName)]"
            }
        } catch {
            Write-Warning -Message "Failed to uninstall: [$($InstalledProgram.DisplayName)]"
        }
    }
} while (($InstalledPrograms.Count -gt 0) -and ($RegistryRetries -lt $MaxRetryCount))

if ($InstalledPrograms.Count -gt 0) {
    Write-Warning -Message "Registry uninstall retries exhausted. Remaining matched entries: [$($InstalledPrograms.Count)]."
}
### Package manager method second - sometimes less reliable but should catch anything the registry method missed.
$Retries = 0
Do {
    $Retries++
    $InstalledPrograms = @(Get-Package | Where-Object { Test-ShouldRemoveLenovoProgram $_.Name } | Sort-Object -Property Name, ProviderName -Unique)
    ForEach ($InstalledProgram in $InstalledPrograms) {
        Write-Output "Attempting to uninstall: [$($InstalledProgram.Name)]..."
        Try {
            $InstalledProgram | Uninstall-Package -AllVersions -Force -ErrorAction Stop | Out-Null
            $StillInstalled = Get-Package -Name $InstalledProgram.Name -ErrorAction SilentlyContinue
            if ($StillInstalled) {
                Write-Warning -Message "Uninstall command completed but package still exists: [$($InstalledProgram.Name)]"
            } else {
                Write-Output "Successfully uninstalled: [$($InstalledProgram.Name)]"
            }
        } Catch {
            Write-Warning -Message "Failed to uninstall: [$($InstalledProgram.Name)]"
        }
    }
} While (($InstalledPrograms.Count -gt 0) -and ($Retries -lt $MaxRetryCount))
# Remove Lenovo offers and shortcuts
$PathsToCleanup = @('$Env:PUBLIC\Desktop\Lenovo Vantage.lnk', '$Env:PUBLIC\Desktop\Lenovo Smart Performance.lnk', '$Env:PUBLIC\Desktop\Lenovo Smart Storage.lnk', '$Env:PUBLIC\Desktop\Lenovo Smart Appearance.lnk', '$Env:PUBLIC\Desktop\Lenovo Smart Meeting.lnk', '$Env:PUBLIC\Desktop\Lenovo Now.lnk', '$Env:PUBLIC\Desktop\Lenovo Support.lnk')
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