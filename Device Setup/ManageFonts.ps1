<#
    .SYNOPSIS
        Device Setup - Manage Fonts
    .DESCRIPTION
        This script is used to download, install, and uninstall fonts on a Windows device. The script can be run in three modes: Download, Install, and Uninstall. The Download mode is used to download a font file or archive from a specified URI. The Install mode is used to install all font files in the specified directory. The Uninstall mode is used to uninstall all font files in the specified directory. You can combine download with install or uninstall.

        You can use NinjaOne Script Variables to pass parameters to the script. The following variables are supported:
        - Download - Type: Checkbox - Purpose: Download the font file or archive from the specified URI.
        - Install - Type: Checkbox - Purpose: Install the font files in the specified directory.
        - Uninstall - Type: Checkbox - Purpose: Uninstall the font files in the specified directory.
        - FontURI - Type: URL - Purpose: The URI to download the font file or archive from.
        - RMMFontsDirectory - Type: Text - Purpose: The directory to save the downloaded font files or archives to.
    .LINK
        Blog: Not blogged yet.
#>
[CmdletBinding()]
param(
    # Download the font file or archive from the specified URI.
    [Parameter(ParameterSetName = 'Download')]
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [Switch]$Download,
    # Install the font files in the specified directory.
    [Parameter(ParameterSetName = 'Install')]
    [Switch]$Install,
    # Uninstall the font files in the specified directory.
    [Parameter(ParameterSetName = 'Uninstall')]
    [Switch]$Uninstall,
    # The URI to download the font file or archive from.
    [Parameter(ParameterSetName = 'Download')]
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [String]$FontURI,
    # The directory to save the downloaded font files or archives to.
    [Parameter(ParameterSetName = 'Download')]
    [Parameter(ParameterSetName = 'Install')]
    [Parameter(ParameterSetName = 'Uninstall')]
    [String]$RMMFontsDirectory = 'C:\RMM\Fonts'
)
begin {
    if ([Boolean]::Parse($ENV:Download)) {
        $Download = $True
    }
    if ([Boolean]::Parse($ENV:Install)) {
        $Install = $True
    }
    if ([Boolean]::Parse($ENV:Uninstall)) {
        $Uninstall = $True
    }
    if (![String]::IsNullOrEmpty($ENV:FontURI)) {
        $FontURI = $ENV:FontURI
    }
    if (![String]::IsNullOrEmpty($ENV:RMMFontsDirectory)) {
        $RMMFontsDirectory = $ENV:RMMFontsDirectory
    }
    function Get-FontDownload {
        [CmdletBinding()]
        param (
            [String]$FontURI
        )
        try {
            $CleanedFontURI = $FontURI.Trim().Trim("'").Trim('"')
            Write-Verbose "Font URI: $CleanedFontURI"
            $FontDownload = Invoke-WebRequest $CleanedFontURI -UseBasicParsing
            $FontFileName = ([System.Net.Mime.ContentDisposition]::new($FontDownload.Headers['Content-Disposition'])).FileName
            $FontContentType = ([System.Net.Mime.ContentType]::new($FontDownload.Headers['Content-Type']))
            $FontSavePath = Join-Path -Path $RMMFontsDirectory -ChildPath $FontFileName
            $FontFile = [System.IO.FileStream]::new($FontSavePath, [System.IO.FileMode]::Create)
            $FontFile.Write($FontDownload.Content, 0, $FontDownload.RawContentLength)
            $FontFile.Close()
            if ($FontContentType.MediaType -eq 'application/zip') {
                Write-Verbose 'Got archive download, extracting contents.'
                Expand-Archive -Path $FontSavePath -DestinationPath $RMMFontsDirectory -Force
                Remove-Item $FontFile.Name -Force
            } elseif ($FontContentType.MediaType -eq 'font/otf') {
                Write-Verbose 'Got OTF download.'
            }
        } catch {
            Write-Error "Error downloading or saving font from: $FontURI.`r`n$($_.exception.message)"
        }
    }
    
    function Install-Font {
        [CmdletBinding()]
        param (  
            [System.IO.FileInfo]$FontFile  
        )
        try { 
            $GlyphTypeface = [Windows.Media.GlyphTypeface]::new($FontFile.FullName)
            $FontFamily = $GlyphTypeface.Win32FamilyNames['en-us']
            if ($Null -eq $FontFamily) { $FontFamily = $GlyphTypeface.Win32FamilyNames.Values.Item(0) }
            $FontFace = $GlyphTypeface.Win32FaceNames['en-us']
            if ($Null -eq $FontFace) { $FontFace = $GlyphTypeface.Win32FaceNames.Values.Item(0) }
            $FontName = ("$FontFamily $FontFace").Trim()  
            switch ($FontFile.Extension) {  
                '.ttf' { $FontName = "$FontName (TrueType)" }  
                '.otf' { $FontName = "$FontName (OpenType)" }  
            }  
            Write-Verbose "Installing font: $FontFile with font name '$FontName'"
            If (!(Test-Path ("$($Env:WinDir)\Fonts\" + $FontFile.Name))) {  
                Write-Verbose "Copying font: $FontFile"
                Copy-Item -Path $FontFile.FullName -Destination ("$($Env:Windir)\Fonts\" + $FontFile.Name) -Force 
            } else { Write-Verbose "Font already exists: $FontFile" }
            If (!(Get-ItemProperty -Name $FontName -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue)) {  
                Write-Verbose "Registering font: $FontFile"
                New-ItemProperty -Name $FontName -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -PropertyType string -Value $FontFile.Name -Force -ErrorAction SilentlyContinue | Out-Null  
            } else { Write-Verbose "Font already registered: $FontFile" }
        } catch {            
            Write-Verbose "Error installing font: $FontFile.`r`n$($_.exception.message)"
        }
    }

    function Uninstall-Font {  
        [CmdletBinding()]
        param (  
            [System.IO.FileInfo]$FontFile  
        )
        try {
            $GlyphTypeface = [Windows.Media.GlyphTypeface]::new($FontFile.FullName)
            $FontFamily = $GlyphTypeface.Win32FamilyNames['en-us']
            if ($Null -eq $FontFamily) { $FontFamily = $GlyphTypeface.Win32FamilyNames.Values.Item(0) }
            $FontFace = $GlyphTypeface.Win32FaceNames['en-us']
            if ($Null -eq $FontFace) { $FontFace = $GlyphTypeface.Win32FaceNames.Values.Item(0) }
            $FontName = ("$FontFamily $FontFace").Trim()
            switch ($FontFile.Extension) {  
                '.ttf' { $FontName = "$FontName (TrueType)" }  
                '.otf' { $FontName = "$FontName (OpenType)" }  
            }
            Write-Verbose "Uninstalling font: $FontFile with font name '$FontName'"
            If (Test-Path ("$($Env:WinDir)\Fonts\" + $FontFile.Name)) {  
                Write-Verbose "Removing font: $FontFile"
                Remove-Item -Path "$($Env:WinDir)\Fonts\$($FontFile.Name)" -Force 
            } else { Write-Verbose "Font does not exist: $FontFile" }
            If (Get-ItemProperty -Name $FontName -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -ErrorAction SilentlyContinue) {  
                Write-Verbose "Unregistering font: $FontFile"
                Remove-ItemProperty -Name $FontName -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -Force                      
            } else { Write-Verbose "Font not registered: $FontFile" }
        } catch {
            Write-Verbose "Error uninstalling font: $FontFile.`r`n$($_.exception.message)"
        }
    }
    
    Add-Type -AssemblyName 'PresentationCore'
    if (-not (Test-Path $RMMFontsDirectory)) {     
        New-Item -Path $RMMFontsDirectory -ItemType Directory | Out-Null
    }
}
process {
    if ($Download -and $FontURI) {
        Get-FontDownload -FontURI $FontURI
    }
    if ($Install) {
        foreach ($FontItem in (Get-ChildItem -Path $RMMFontsDirectory | Where-Object { ($_.Name -like '*.ttf') -or ($_.Name -like '*.otf') })) {  
            Install-Font -FontFile $FontItem.FullName  
        }
    } elseif ($Uninstall) {
        foreach ($FontItem in (Get-ChildItem -Path $RMMFontsDirectory | Where-Object { ($_.Name -like '*.ttf') -or ($_.Name -like '*.otf') })) {  
            Uninstall-Font -FontFile $FontItem.FullName  
        }
    }
}