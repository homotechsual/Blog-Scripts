<#
.SYNOPSIS
    Update Management - CVE-2022-41099 Downloader (Safe OS Dynamic Update version)
.DESCRIPTION
    This script will download the applicable patch for CVE-2022-41099 from Microsoft Update Catalog. It will detect the OS version and bitness and download the correct patch. This uses the Feb 2023, January 2023 or November 2022 Safe OS DU depending on the OS version.
.PARAMETER PatchFolder
    Accepts the path to a folder to download the patch(es) to.
.EXAMPLE
    This example will download the applicable patch for CVE-2022-41099 to the folder C:\RMM\CVEs\2022-41099\.
    
    Get-CVE202241099Patches.ps1 -PatchFolder 'C:\RMM\CVEs\2022-41099\'
.EXAMPLE
    This example will download all patches for CVE-2022-41099 to the folder C:\RMM\CVEs\2022-41099\. With subfolders for each KB and architecture.

    Get-CVE202241099Patches.ps1 -PatchFolder 'C:\RMM\CVEs\2022-41099\' -All
.NOTES
    2023-03-22: Empty the patch folder if it's not empty. Thanks to Wisecompany for the suggestion.
    2023-03-22: Fixes incorrectly switched URLs for 19042 to 19045 for the x86 and x64 downloads. Thanks to Wisecompany for helping find this.
    2023-03-21: Update to use the Safe OS Dynamic Update packages which are considerably smaller.
    2023-01-18: Use `$ProgressPreference` to speed up execution. Thanks to CodyRWhite (GitHub) for the suggestion.
    2023-01-18: Fix bug accessing hashtable of architectures using Windows build number. Thanks to Sir Loin (WinAdmins) for spotting this.
    2023-01-17: Add support for Windows 10 19044 (21H2)
    2023-01-17: Initial version
.LINK
    Blog post: https://homotechsual.dev/2023/01/17/Download-CVE-2022-41099-Patches/
#>
# We're targetting the January 2023 Safe OS Dynamic Update for Windows 11 22H2 and the November 2022 Safe OS Dynamic Update for Windows 11 21H2 and Windows 10 22H2, 22H1, 21H1 and 20H2.
[CmdletBinding()]
param (
    # The path to the folder to download the patch(es) to.
    [System.IO.DirectoryInfo]$PatchFolder = 'C:\RMM\CVEs\2022-41099\',
    # Download all patches including SSUs useful if you want to populate a staging folder. Will create a subfolder for each.
    [Switch]$All
)
$OriginalProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'
$BuildtoKBMap = @{
    22623 = 5023527
    22621 = 5023527
    22000 = 5021040
    19045 = 5021043
    19044 = 5021043
    19043 = 5021043
    19042 = 5021043
}
$KBtoCABMap = @{
    # KB5023527 - February 2023
    5023527 = @{
        'x64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/crup/2023/02/windows11.0-kb5023527-x64_076cd9782ebb8aed56ad5d99c07201035d92e66a.cab'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/crup/2023/02/windows11.0-kb5023527-arm64_bd0a8952aee4f003c26e272a9b804645146e9358.cab'
    }
    # KB5021040 - November 2022
    5021040 = @{
        'x64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/crup/2022/11/windows10.0-kb5021040-x64_2216fe185502d04d7a420a115a53613db35c0af9.cab'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/crup/2022/11/windows10.0-kb5021040-arm64_cb0622a2c0ef781826f583eccd16c289597678cc.cab'
    }
    # KB5021043 - January 2023
    5021043 = @{
        'x86' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/crup/2022/11/windows10.0-kb5021043-x86_484ed491379e442debef6fdfb6860be749145017.cab'
        'x64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/crup/2022/11/windows10.0-kb5021043-x64_efa19d2d431c5e782a59daaf2d04d026bb8c8e76.cab'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/crup/2022/11/windows10.0-kb5021043-arm64_59eed783be1d2a514c01cb325cfad83ea65f7515.cab'
    }
}
$WinOSBuild = [System.Environment]::OSVersion.Version.Build
$WinOSArch = if ([System.Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
if (-not (Test-Path -Path $PatchFolder)) {
    New-Item -Path $PatchFolder -ItemType Directory | Out-Null
} else {
    if (Get-ChildItem -Path $PatchFolder -Recurse) {
        Write-Verbose "Emptying $PatchFolder"
        Get-ChildItem -Path $PatchFolder -Recurse | Remove-Item -Force -Recurse
    }
}
if (-not $All) {
    try {
        if (-not $BuildtoKBMap.ContainsKey($WinOSBuild)) {
            Write-Error "Unsupported Windows version $WinOSBuild"
            exit 1
        } else {
            $KB = $BuildtoKBMap[$WinOSBuild]
            if (-not $KBtoCABMap.ContainsKey($KB)) {
                Write-Error "Did not find patches for KB $KB"
                exit 1
            } else {
                $DownloadUrl = $KBtoCABMap[$KB][$WinOSArch]
                $FileName = ([URI]$DownloadUrl).Segments[-1]
                $TargetPath = Join-Path -Path $PatchFolder -ChildPath $FileName
                if (-not (Test-Path -Path $TargetPath)) {
                    Write-Verbose "Downloading $FileName"
                    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetPath
                }
            }
        }
    } catch [System.Net.WebException] {
        Write-Error "Failed to download one or more CAB files for $WinOSBuild $WinOSArch"
        Write-Error $_.Exception.Message
        exit 1
    } catch [System.IO.IOException] {
        Write-Error "Could not write to $PatchFolder"
        Write-Error $_.Exception.Message
    }
} else {
    try {
        $KBtoCABMap.GetEnumerator() | ForEach-Object {
            $PatchSubFolder = Join-Path -Path $PatchFolder -ChildPath $_.Name
            Write-Warning "Downloading Patch CAB files to: $PatchSubFolder."
            if (-not (Test-Path -Path $PatchSubFolder)) {
                New-Item -Path $PatchSubFolder -ItemType Directory | Out-Null
            }
            foreach ($Arch in $_.Value.GetEnumerator()) {
                $ArchSubFolder = Join-Path -Path $PatchSubFolder -ChildPath $Arch.Name
                if (-not (Test-Path -Path $ArchSubFolder)) {
                    New-Item -Path $ArchSubFolder -ItemType Directory | Out-Null
                }
                $DownloadUrl = $Arch.Value
                $FileName = ([URI]$DownloadUrl).Segments[-1]
                $TargetPath = Join-Path -Path $ArchSubFolder -ChildPath $FileName
                if (-not (Test-Path -Path $TargetPath)) {
                    Write-Verbose "Downloading $FileName"
                    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetPath
                } else {
                    Write-Verbose "Skipping $FileName as it already exists"
                }
            }
        }
    } catch [System.Net.WebException] {
        Write-Error "Failed to download one or more CAB files for $WinOSBuild $WinOSArch"
        Write-Error $_.Exception.Message
        exit 1
    } catch [System.IO.IOException] {
        Write-Error "Could not write to $PatchFolder"
        Write-Error $_.Exception.Message
    }
}
$ProgressPreference = $OriginalProgressPreference