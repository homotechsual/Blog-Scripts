<#
    .SYNOPSIS
        Microsoft 365 - OneDrive - Remove folder recursively
    .DESCRIPTION
        This script will recursively remove a folder from OneDrive for Business. It uses the `PNP.PowerShell` module to connect to the site and then recursively remove files and folders based on the provided parameters. You can install the `PNP.PowerShell` module from the PowerShell Gallery using the following command: `Install-Module -Name PnP.PowerShell`.
    .NOTES
        2022-04-10: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/04/10/Recursively-Remove-Folder-OneDrive/
#>
[CmdletBinding()]
param (
    # OneDrive host name e.g. 'https://microsoft-my.sharepoint.com'
    [Parameter(Mandatory)]
    [String]$OneDriveHost,
    # Site path e.g. '/personal/satya_nadella_microsoft_com' must start with '/'.
    [Parameter(Mandatory)]
    [String]$SitePath,
    # Folder path e.g. '/Documents/Documents/PowerShell/Modules' must start with '/'.
    [String]$FolderPath
)

# Setup some configuration variables.
$SiteURL = $OneDriveHost + $SitePath
$FolderSiteRelativeURL = $SitePath + $FolderPath 
    
# Connect to the site with the PnP.PowerShell module.
Connect-PnPOnline -Url $SiteURL -Interactive
$Web = Get-PnPWeb
$Folder = Get-PnPFolder -Url $FolderSiteRelativeURL
     
# Function to recursively remove files and folders from the path given.
Function Clear-PnPFolder([Microsoft.SharePoint.Client.Folder]$Folder) {
    $InformationPreference = 'Continue'
    If ($Web.ServerRelativeURL -eq '/') {
        $FolderSiteRelativeURL = $Folder.ServerRelativeUrl
    } Else {       
        $FolderSiteRelativeURL = $Folder.ServerRelativeUrl.Replace($Web.ServerRelativeURL, [string]::Empty)
    }
    # First remove all files in the folder.
    $Files = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType File
    ForEach ($File in $Files) {
        # Delete the file.
        Remove-PnPFile -ServerRelativeUrl $File.ServerRelativeURL -Force -Recycle
        Write-Information ("Deleted File: '{0}' at '{1}'" -f $File.Name, $File.ServerRelativeURL)
    }
    # Second loop through sub folders and remove them - unless they are "special" or "hidden" folders.
    $SubFolders = Get-PnPFolderItem -FolderSiteRelativeUrl $FolderSiteRelativeURL -ItemType Folder
    Foreach ($SubFolder in $SubFolders) {
        If (($SubFolder.Name -ne 'Forms') -and (-Not($SubFolder.Name.StartsWith('_')))) {
            # Recurse into children.
            Clear-PnPFolder -Folder $SubFolder
            # Finally delete the now empty folder.
            Remove-PnPFolder -Name $SubFolder.Name -Folder $Site + $FolderSiteRelativeURL -Force -Recycle
            Write-Information ("Deleted Folder: '{0}' at '{1}'" -f $SubFolder.Name, $SubFolder.ServerRelativeURL)
        }
    }
    $InformationPreference = 'SilentlyContinue'
}     
# Call the function to empty folder if it exists.
if ($null -ne $Folder) {
    Clear-PnPFolder -Folder $Folder
} Else {
    Write-Error ("Folder '{0}' not found" -f $FolderSiteRelativeURL)
}