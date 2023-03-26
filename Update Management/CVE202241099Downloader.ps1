<#
.SYNOPSIS
    Update Management - CVE-2022-41099 Downloader
.DESCRIPTION
    This script will download the applicable patch for CVE-2022-41099 from Microsoft Update Catalog. It will detect the OS version and bitness and download the correct patch. This uses the January 2023 Servicing Stack Update (SSU) as the ultimate target.
.NOTES
    2023-03-22: Empty the patch folder if it's not empty. Thanks to Wisecompany for the suggestion.
    2023-01-18: Use `$ProgressPreference` to speed up execution. Thanks to CodyRWhite (GitHub) for the suggestion.
    2023-01-18: Fix bug accessing hashtable of architectures using Windows build number. Thanks to Sir Loin (WinAdmins) for spotting this.
    2023-01-17: Add support for Windows 10 19044 (21H2)
    2023-01-17: Initial version
.LINK
    Blog post: https://homotechsual.dev/2023/01/17/Download-CVE-2022-41099-Patches/
.EXAMPLE
    This example will download the applicable patch for CVE-2022-41099 to the folder C:\RMM\CVEs\2022-41099\.
    
    Get-CVE202241099Patches.ps1 -PatchFolder 'C:\RMM\CVEs\2022-41099\'
.EXAMPLE
    This example will download all patches for CVE-2022-41099 to the folder C:\RMM\CVEs\2022-41099\. With subfolders for each KB and architecture.

    Get-CVE202241099Patches.ps1 -PatchFolder 'C:\RMM\CVEs\2022-41099\' -All
#>
# We're targetting the January 2023 CU as our version to patch to. The CVE page links to the November 2022 CU, but the January 2023 CU is the latest version and refers again to the vulnerability so it seems safer to patch to that version. ARM links are included but the script does not handle ARM detection yet. We also download, where applicable the latest SSU.
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
    22623 = 5022303
    22621 = 5022303
    22000 = 5022287
    19045 = 5022282
    19044 = 5022282
    19043 = 5022282
    19042 = 5021233
}
$KBtoMSUMap = @{
    # KB5022303 - January 2023
    5022303 = @{
        'x64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/01/windows11.0-kb5022303-x64_87d49704f3f7312cddfe27e45ba493048fdd1517.msu'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/01/windows11.0-kb5022303-arm64_4c207b992ed272bbdbfb35d77f0458548a7b86d1.msu'
    }
    # KB5022287 - January 2023
    5022287 = @{
        'x64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/01/windows10.0-kb5022287-x64_55641f1989bae2c2d0f540504fb07400a0f187b3.msu'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2023/01/windows10.0-kb5022287-arm64_7d26e9ef2c00ce384e19d4ca234052e378747a05.msu'
    }
    # KB5022282 - January 2023
    5022282 = @{
        'x86' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/01/windows10.0-kb5022282-x86_5fb142aca9e3f8c7ed37df9e7806b7f7f56d9599.msu'
        'x64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/01/windows10.0-kb5022282-x64_fdb2ea85e921869f0abe1750ac7cee34876a760c.msu'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2023/01/windows10.0-kb5022282-arm64_9ccaddc4356ab1db614881e08635bd8959ff97f3.msu'
    }
    # KB5021233 - December 2022
    5021233 = @{
        'x86' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/12/windows10.0-kb5021233-x86_e21531f654715af20b2aa329d6786080bd798963.msu'
        'x64' = 'https://catalog.s.download.windowsupdate.com/d/msdownload/update/software/secu/2022/12/windows10.0-kb5021233-x64_00bbf75a829a2cb4f37e4a2b876ea9503acfaf4d.msu'
        'ARM64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/12/windows10.0-kb5021233-arm64_4bac0de318c939e54fa6a9f537e892272446ae09.msu'
    }
}
$ArchtoSSUMap = @{
    'x86' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/05/ssu-19041.1704-x86_3cec66c3891a613e6656f141547e573f9d700d35.msu'
    'x64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/05/ssu-19041.1704-x64_70e350118b85fdae082ab7fde8165a947341ba1a.msu'
    'ARM64' = 'https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2022/05/ssu-19041.1704-arm64_dac34c98382f951bd654fe3affe0b3e7100b3745.msu'
}
$SSUKB = '5013942'
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
        if ($WinOSBuild -lt 22000 -and $WinOSBuild -ge 19042) {
            if ($ArchtoSSUMap.ContainsKey($WinOSArch)) {
                $DownloadUrl = $ArchtoSSUMap[$WinOSArch]
                $FileName = ([URI]$DownloadUrl).Segments[-1]
                $TargetPath = Join-Path -Path $PatchFolder -ChildPath ("1_$FileName")
                if (-not (Test-Path -Path $TargetPath)) {
                    Write-Verbose "Downloading $FileName"
                    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetPath
                }
            }
        }
        if (-not $BuildtoKBMap.ContainsKey($WinOSBuild)) {
            Write-Error "Unsupported Windows version $WinOSBuild"
            exit 1
        } else {
            $KB = $BuildtoKBMap[$WinOSBuild]
            if (-not $KBtoMSUMap.ContainsKey($KB)) {
                Write-Error "Did not find patches for KB $KB"
                exit 1
            } else {
                $DownloadUrl = $KBtoMSUMap[$KB][$WinOSArch]
                $FileName = ([URI]$DownloadUrl).Segments[-1]
                $TargetPath = Join-Path -Path $PatchFolder -ChildPath $FileName
                if (-not (Test-Path -Path $TargetPath)) {
                    Write-Verbose "Downloading $FileName"
                    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetPath
                }
            }
        }
    } catch [System.Net.WebException] {
        Write-Error "Failed to download one or more MSU files for $WinOSBuild $WinOSArch"
        Write-Error $_.Exception.Message
        exit 1
    } catch [System.IO.IOException] {
        Write-Error "Could not write to $PatchFolder"
        Write-Error $_.Exception.Message
    }
} else {
    try {
        $SSUSubFolder = Join-Path -Path $PatchFolder -ChildPath $SSUKB
        Write-Warning "Downloading SSU MSU files to: $SSUSubFolder."
        if (-not (Test-Path -Path $SSUSubFolder)) {
            New-Item -Path $SSUSubFolder -ItemType Directory | Out-Null
        }
        $ArchtoSSUMap.GetEnumerator() | ForEach-Object {
            $ArchSubFolder = Join-Path -Path $SSUSubFolder -ChildPath $_.Name
            if (-not (Test-Path -Path $ArchSubFolder)) {
                New-Item -Path $ArchSubFolder -ItemType Directory | Out-Null
            }
            $DownloadUrl = $_.Value
            $FileName = ([URI]$DownloadUrl).Segments[-1]
            $TargetPath = Join-Path -Path $ArchSubFolder -ChildPath $FileName
            if (-not (Test-Path -Path $TargetPath)) {
                Write-Verbose "Downloading $FileName"
                Invoke-WebRequest -Uri $DownloadUrl -OutFile $TargetPath
            } else {
                Write-Verbose "Skipping $FileName as it already exists"
            }
        }
        $KBtoMSUMap.GetEnumerator() | ForEach-Object {
            $PatchSubFolder = Join-Path -Path $PatchFolder -ChildPath $_.Name
            Write-Warning "Downloading Patch MSU files to: $PatchSubFolder."
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
        Write-Error "Failed to download one or more MSU files for $WinOSBuild $WinOSArch"
        Write-Error $_.Exception.Message
        exit 1
    } catch [System.IO.IOException] {
        Write-Error "Could not write to $PatchFolder"
        Write-Error $_.Exception.Message
    }
}
$ProgressPreference = $OriginalProgressPreference