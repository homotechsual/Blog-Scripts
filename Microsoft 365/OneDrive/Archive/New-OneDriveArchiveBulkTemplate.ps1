<#
.SYNOPSIS
    Creates a template CSV for Invoke-OneDriveArchiveBulk.ps1 and opens it in the default app.

.PARAMETER Path
    Where to write the template. Defaults to '.\OneDriveArchive-Users.csv'.

.PARAMETER NoOpen
    Skip opening the file in the system's default handler after creating it.

.EXAMPLE
    .\New-OneDriveArchiveBulkTemplate.ps1
#>

[CmdletBinding()]
param (
    [string]$Path = '.\OneDriveArchive-Users.csv',
    [switch]$NoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path -LiteralPath $Path) {
    throw ('Template path already exists: {0}. Choose another path to avoid overwriting your user list.' -f $Path)
}

$Rows = @(
    [PSCustomObject]@{
        SourceUPN      = 'user@contoso.com'
        DestFolderName = ''
        DestSiteHost   = ''
        DestSitePath   = ''
        ShareWithUPN   = ''
    }
)

$ParentDir = Split-Path -Path $Path -Parent
if ($ParentDir -and -not (Test-Path -LiteralPath $ParentDir)) {
    New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
}

$Rows | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding utf8

Write-Output ('Template written to {0}' -f (Resolve-Path -LiteralPath $Path))
Write-Output 'Leave DestFolderName blank to use the user''s Microsoft Entra display name (requires Graph User.Read.All application permission with admin consent). Leave DestSiteHost/DestSitePath/ShareWithUPN blank to use the values passed to Invoke-OneDriveArchiveBulk.ps1. Leave ShareWithUPN blank entirely to skip sharing.'

if (-not $NoOpen) {
    Invoke-Item -Path $Path
}
