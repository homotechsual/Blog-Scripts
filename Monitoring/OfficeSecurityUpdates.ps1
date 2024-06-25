<#
    .SYNOPSIS
        Monitoring - Windows - Office / Microsoft 365 Apps Security Updates
    .DESCRIPTION
        This script will monitor the installed version of Office "Click-to-Run" installations to ascertain whether the installed version is vulnerable to known security vulnerabilities. It will report back to NinjaOne with the installed version, the channel, and the status of the installed version.

        Consult the blog post for the fields requires in NinjaOne including the field types and default names.
    .NOTES
        2024-06-25: Exit if a retail version of Office is detected or if an unknown edition is detected.
        2024-06-16: Initial version
    .LINK
        Blog post: Not blogged yet.
#>
### Edit the field names here if you use different field names in NinjaOne.
$InstalledVersionCustomField = 'officeInstalledVersion' # Text field showing the installed version of Office.
$ChannelCustomField = 'officeChannel' # Text field showing the update channel of the installed version.
$StatusCustomField = 'officeStatus' # Text field showing information on the status of the installed version.
$SecureCustomField = 'officeSecure' # Checkbox field showing whether the installed version is the latest security update.
$OutputDetail = $true # Set to $true to output a card of the data to the field name specified in $OutputDetailField.
$OutputDetailField = 'officeDetail' # WYSIWYG field showing the details of the installed version.
### End of field names.

$IsC2R = Test-Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun'

if ($IsC2R) {
    # Get the installed Office Version
    $OfficeVersion = [version]( Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' | Select-Object -ExpandProperty VersionToReport )
    # Get the installed Office Product IDs
    $OfficeProductIds = ( Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' | Select-Object -ExpandProperty ProductReleaseIds )
} else {
    Write-Error 'No Click-to-Run Office installation detected. This script only works with Click-to-Run Office installations.'
    Exit 1
}

$IsM365 = ($OfficeProductIds -like '*O365*') -or ($OfficeProductIds -like '*M365*')

$Channels = @(
    @{
        GUID = '492350f6-3a01-4f97-b9c0-c7c6ddf67d60'
        PathPart = 'Monthly'
        GPO = 'Current'
        ID = 'Current'
        Name = 'Monthly'
    },
    @{
        GUID = '64256afe-f5d9-4f86-8936-8840a6a4f5be'
        PathPart = 'MonthlyPreview'
        GPO = 'FirstReleaseCurrent'
        ID = 'CurrentPreview'
        Name = 'Monthly (Preview)'
        AlternateNames = @('InsiderSlow', 'FirstReleaseCurrent', 'Insiders')
    },
    @{
        GUID = '55336b82-a18d-4dd6-b5f6-9e5095c314a6'
        PathPart = 'MonthlyEnterpriseChannel'
        GPO = 'MonthlyEnterprise'
        ID = 'MonthlyEnterprise'
        Name = 'MEC'
    },
    @{
        GUID = '7ffbc6bf-bc32-4f92-8982-f9dd17fd3114'
        PathPart = 'SAC'
        GPO = 'Deferred'
        ID = 'SemiAnnual'
        Name = 'SAC'
        AlternateNames = @('Deferred', 'Broad')
    },
    @{
        GUID = 'b8f9b850-328d-4355-9145-c59439a0c4cf'
        PathPart = 'SACT'
        GPO = 'FirstReleaseDeferred'
        ID = 'SemiAnnualPreview'
        Name = 'SACT'
        AlternateNames = @('FirstReleaseDeferred', 'Targeted')
    },
    @{
        GUID = '5030841d-c919-4594-8d2d-84ae4f96e58e'
        PathPart = 'LTSB2021'
        ID = 'PerpetualVL2021'
        Name = 'LTSB2021'
        AlternateNames = @('Perpetual2021')
    },
    @{
        GUID = 'f2e724c1-748f-4b47-8fb8-8e0d210e9208'
        PathPart = 'LTSB'
        ID = 'PerpetualVL2019'
        Name = 'LTSB'
        AlternateNames = @('Perpetual2019')
    },
    @{
        GUID = '5440fd1f-7ecb-4221-8110-145efaa6372f'
        PathPart = 'Beta'
        GPO = 'InsiderFast'
        ID = 'BetaChannel'
        Name = 'Beta'
    }
)
# For M365 apps detect the update channel by first checking the GPO setting, then the UpdateURL registry key, the UnmanagedUpdateURL registry key, and finally the CDNBaseUrl registry key.
if ($IsM365) {
    # Check the Office GPO settings for the update channel.
    $OfficeUpdateChannelGPO = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Office\16.0\Common\OfficeUpdate' -ErrorAction 'SilentlyContinue' | Select-Object -ExpandProperty UpdateBranch -ErrorAction 'SilentlyContinue')
    if ($OfficeUpdateChannelGPO) {
        Write-Output 'Office is configured to use a GPO update channel.'
        foreach ($Channel in $Channels) {
            if ($OfficeUpdateChannelGPO -eq $Channel.GPO) {
                $OfficeChannel = $Channel
            }
        }
    } else {
        $C2RConfigurationPath = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
        Write-Output 'Office is not configured to use a GPO update channel.'
        # Get the UpdateUrl if set
        $OfficeUpdateURL = [System.Uri](Get-ItemProperty -Path $C2RConfigurationPath -ErrorAction 'SilentlyContinue' | Select-Object -ExpandProperty UpdateURL -ErrorAction 'SilentlyContinue')
        # Get the UnmanagedUpdateUrl if set
        $OfficeUnmanagedUpdateURL = [System.Uri](Get-ItemProperty -Path $C2RConfigurationPath -ErrorAction 'SilentlyContinue' | Select-Object -ExpandProperty UnmanagedUpdateURL -ErrorAction 'SilentlyContinue')
        # Get the Office Update CDN URL
        $OfficeUpdateChannelCDNURL = [System.Uri](Get-ItemProperty -Path $C2RConfigurationPath -ErrorAction 'SilentlyContinue' | Select-Object -ExpandProperty CDNBaseUrl -ErrorAction 'SilentlyContinue')
        # Get just the channel GUID
        if ($OfficeUpdateURL.IsAbsoluteUri) {
            $OfficeUpdateGUID = $OfficeUpdateURL.Segments[2]
        } elseif ($OfficeUnmanagedUpdateURL.IsAbsoluteUri) {
            $OfficeUpdateGUID = $OfficeUnmanagedUpdateURL.Segments[2]
        } elseif ($OfficeUpdateChannelCDNURL.IsAbsoluteUri) {
            $OfficeUpdateGUID = $OfficeUpdateChannelCDNURL.Segments[2]
        } else {
            Write-Error 'Unable to determine Office update channel URL.'
            Exit 1
        }
        foreach ($Channel in $Channels) {
            if ($OfficeUpdateGUID -eq $Channel.GUID) {
                $OfficeChannel = $Channel
            }
        }
    }
    if (-not $OfficeChannel) {
        Write-Error 'Unable to determine Office update channel.'
        Exit 1
    } else {
        Write-Output ("{0} found using the {1} update channel. `r`nChannel ID: {2}. `r`nDetected Version: {3}" -f 'Microsoft 365 Apps', $OfficeChannel.Name, $OfficeChannel.ID, $OfficeVersion)
    }
}
# Use the `clients.config.office.com` API to get the latest security update for the Office Channel or version (for Office 2019 and Office 2021).
if ($OfficeVersion.Major -eq '16') {
    if ($IsM365) {
        # Handle Microsoft 365 Apps
        $ChannelURLPathPart = $OfficeChannel.PathPart
        try {
            $UpdateAPIURL = ('https://clients.config.office.net/releases/v1.0/LatestRelease/{0}?releaseType=security' -f $ChannelURLPathPart)
            $ReleaseInfo = Invoke-RestMethod -Uri $UpdateAPIURL -Method 'GET' -ErrorAction 'Stop'
            if (($null -eq $ReleaseInfo) -or ([string]::IsNullOrEmpty($ReleaseInfo))) {
                $UpdateAPIURL = ('https://clients.config.office.net/releases/v1.0/LatestRelease/{0}?releaseType=' -f $ChannelURLPathPart)
                $ReleaseInfo = Invoke-RestMethod -Uri $UpdateAPIURL -Method 'GET' -ErrorAction 'Stop'
            }
        } catch {
            Write-Error 'Unable to get the latest update information.'
            Exit 1
        }
    } elseif ($OfficeProductIds -like '*2019Volume*') {
        # Handle VL Office LTSC 2019
        try {
            $UpdateAPIURL = 'https://clients.config.office.net/releases/v1.0/LatestRelease/LTSB?releaseType=security'
            $ReleaseInfo = Invoke-RestMethod -Uri $UpdateAPIURL -Method 'GET' -ErrorAction 'Stop'
            if (($null -eq $ReleaseInfo) -or ([string]::IsNullOrEmpty($ReleaseInfo))) {
                $UpdateAPIURL = 'https://clients.config.office.net/releases/v1.0/LatestRelease/LTSB?releaseType='
                $ReleaseInfo = Invoke-RestMethod -Uri $UpdateAPIURL -Method 'GET' -ErrorAction 'Stop'
            }
        } catch {
            Write-Error 'Unable to get the latest update information.'
            Exit 1
        }
    } elseif ($OfficeProductIds -like '*2021Volume*') {
        # Handle VL Office LTSC 2021
        try {
            $UpdateAPIURL = 'https://clients.config.office.net/releases/v1.0/LatestRelease/LTSB2021?releaseType=security'
            $ReleaseInfo = Invoke-RestMethod -Uri $UpdateAPIURL -Method 'GET' -ErrorAction 'Stop'
            if (($null -eq $ReleaseInfo) -or ([string]::IsNullOrEmpty($ReleaseInfo))) {
                $UpdateAPIURL = 'https://clients.config.office.net/releases/v1.0/LatestRelease/LTSB2021?releaseType='
                $ReleaseInfo = Invoke-RestMethod -Uri $UpdateAPIURL -Method 'GET' -ErrorAction 'Stop'
            }
        } catch {
            Write-Error 'Unable to get the latest update information.'
            Exit 1
        }
    } elseif ($OfficeProductIds -like '*Retail*') {
        Write-Error 'Retail version of Office detected. This script only works with Microsoft 365 Apps or Volume License versions of Office.'
        Exit 1
    } else {
        Write-Error 'Unknown edition of Office detected. This script only works with Microsoft 365 Apps or Volume License versions of Office.'
        Exit 1
    }
}
# Create a hashtable of the release types.
$ReleaseTypes = @{
    1 = 'Feature Update'
    2 = 'Quality Update'
    3 = 'Security Update'
}
# Get today's date so we can compare the end of support date.
$Today = Get-Date
# Get the human-readable release type.
$ReleaseType = $ReleaseTypes[[int32]$ReleaseInfo.releaseType]
# Rejoin the version parts to create a full version number.
$TargetVersion = [Version]$releaseInfo.buildVersion.buildVersionString
# Determine if the installed version is supported / latest.
if ($OfficeVersion -lt $TargetVersion) {
    $Status = 'Outdated'
    $Secure = $false
} elseif ($OfficeVersion -eq $TargetVersion) {
    $Status = 'Up-to-date'
    $Secure = $true
} elseif ($OfficeVersion -gt $TargetVersion) {
    $Status = 'Preview'
    $Secure = $true
} elseif ($Today -gt $ReleaseInfo.endOfSupportDate) {
    $Status = 'End of Support'
    $Secure = $false
} else {
    $Status = 'Unknown'
    $Secure = $null
}
# Preprocess the end of support date.
$EOSDate = $ReleaseInfo.endOfSupportDate.toString()
if ($EOSDate -eq '0001-01-01T00:00:00Z') {
    $ReleaseInfo.endOfSupportDate = 'No date set'
}
# Create a hashtable of the data available to return to NinjaOne.
$OfficeVersionData = @{
    'Installed Version' = $OfficeVersion.toString()
    'Update Channel' = $OfficeChannel.Name
    'Latest Release Type' = $ReleaseType.toString()
    'Latest Release Version' = $TargetVersion.toString()
    'End Of Support Date' = $ReleaseInfo.endOfSupportDate.toString()
    'Release Date' = $ReleaseInfo.availabilityDate.toString()
    'Display Version' = $ReleaseInfo.releaseVersion.toString()
    'Status' = $Status
    'Secure' = $Secure
}
$StatusIcon = @{
    'Outdated' = @{
        class = 'fas fa-exclamation-triangle'
        color = '#FAC905'
    }
    'Up-to-date' = @{
        class = 'fas fa-check-circle'
        color = '#007644'
    }
    'Preview' = @{
        class = 'fas fa-eye'
        color = '#337ab7'
    }
    'End of Support' = @{
        class= 'fas fa-times-circle'
        color = '#D53948'
    }
    'Unknown' = @{
        class = 'fas fa-question-circle'
        color = '#CCCCCC'
    }
}
$SecureIcon = if ($Secure -eq $true) {
    @{ 
        class = 'fas fa-check-circle'
        color = '#007644'
    }
} elseif ($Secure -eq $false) {
    @{ 
        class = 'fas fa-times-circle'
        color = '#D53948'
    }
} else {
    @{ 
        class = 'fas fa-question-circle'
        color = '#CCCCCC'
    }
}
$StatusIcon = ('<i class="{0}" style="color: {1};"></i>' -f $StatusIcon[$Status].class, $StatusIcon[$Status].color)
$SecureIcon = ('<i class="{0}" style="color: {1};"></i>' -f $SecureIcon.class, $SecureIcon.color)
### NinjaOne convert object to card.
[System.Collections.Generic.List[String]]$CardHTML = @()
$CardHTML.Add('<div class="col-sm-12 d-flex">')
$CardHTML.Add('<div class="card flex-grow-1">')
$CardHTML.Add('<div class="card-title-box">')
$CardHTML.Add('<div class="card-title">Office Details</div>')
$CardHTML.Add('<div class="card-link-box"><a href="{0}" target="_blank" class="card-link"><i class="fas fa-arrow-up-right-from-square" style="color: #337ab7;"></i></a></div>' -f $ReleaseInfo.kbLink)
$CardHTML.Add('</div>')
$CardHTML.Add('<div class="card-body">')
foreach ($Field in $OfficeVersionData.Keys) {
    $CardHTML.Add('<p>')
    $CardHTML.Add(('<b>{0}</b>' -f $Field))
    $CardHTML.Add('<br />')
    if (($Field -ne 'Secure') -and ($Field -ne 'Status')) { 
        $CardHTML.Add('{0}' -f $OfficeVersionData[$Field])
    } elseif ($Field -eq 'Secure') {
        $CardHTML.Add(('{0}&nbsp;&nbsp;{1}' -f $SecureIcon, $OfficeVersionData[$Field]))
    } elseif ($Field -eq 'Status') {
        $CardHTML.Add(('{0}&nbsp;&nbsp;{1}' -f $StatusIcon, $OfficeVersionData[$Field]))
    }
    $CardHTML.Add('</p>')
}
$CardHTML.Add('</div>')
$CardHTML.Add('</div>')
$CardHTML.Add('</div>')
### End of NinjaOne convert object to card.
# Set the custom fields in NinjaOne.
Ninja-Property-Set $InstalledVersionCustomField $OfficeVersion
Ninja-Property-Set $ChannelCustomField $OfficeChannel.Name
Ninja-Property-Set $StatusCustomField $Status
Ninja-Property-Set $SecureCustomField $Secure
if ($OutputDetail) {
    $Detail = $CardHTML -join ''
    $Detail | Ninja-Property-Set-Piped $OutputDetailField
}