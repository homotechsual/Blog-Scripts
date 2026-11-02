<#
.SYNOPSIS
    Copies a user's OneDrive to a SharePoint document library via Microsoft Graph API.

.DESCRIPTION
    Fully server-side copy via Graph client credentials. Source files are not deleted.
    Only the latest file version is copied; source metadata and permissions are not retained.
    Tenant discovery tries the source UPN domain, then the destination tenant's
    inferred onmicrosoft.com domain, via the OIDC well-known endpoint.
    Unless DestFolderName is supplied, the destination folder uses the user's
    Microsoft Entra display name, with unsupported folder characters replaced by underscores.

.PARAMETER ClientId
    App registration Client ID. Requires Files.ReadWrite.All and Sites.ReadWrite.All
    application permissions with admin consent. Automatic display-name lookup also
    requires User.Read.All application permission with admin consent.

.PARAMETER ClientSecret
    Client secret for the app registration.

.PARAMETER KeyVaultName
    Azure Key Vault to resolve ClientId/ClientSecret from, instead of passing them directly.
    Requires an active Connect-AzAccount session and the Az.KeyVault module.

.PARAMETER ClientIdSecretName
    Name of the Key Vault secret holding the Client ID. Defaults to 'ODArchiverClientId'.

.PARAMETER ClientSecretSecretName
    Name of the Key Vault secret holding the Client Secret. Defaults to 'ODArchiverClientSecret'.

.PARAMETER SourceUPN
    UPN of the user whose OneDrive to migrate (e.g. user@contoso.com).

.PARAMETER TenantId
    Optional Microsoft Entra tenant ID (GUID) or verified domain.
    If omitted, the script attempts auto-discovery from SourceUPN domain and
    destination SharePoint hostname.

.PARAMETER DestSiteHost
    SharePoint hostname of the destination site (e.g. contoso.sharepoint.com).

.PARAMETER DestSitePath
    Server-relative path of the destination site (e.g. /sites/yoursite).

.PARAMETER DestFolderName
    Folder to create in the destination document library. Defaults to the user's
    display name from Microsoft Graph. An explicit name skips the display-name lookup.
    A failed lookup stops the migration rather than falling back to the email prefix.

.PARAMETER ShareWithUPN
    Optional UPN to grant read-only access to the destination folder (e.g. the leaver's
    manager). Sends Microsoft's standard sharing-invitation email. Omit to skip sharing.

.PARAMETER PollTimeoutMinutes
    How long to poll async copy jobs. Defaults to 30. A timeout stops local polling,
    not the server-side copy. The returned job object includes monitor URLs and statuses.

.EXAMPLE
    .\Invoke-OneDriveArchive.ps1 `
        -ClientId     'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -ClientSecret $clientSecret `
        -SourceUPN    'alex@contoso.com' `
        -DestSiteHost 'contoso.sharepoint.com' `
        -DestSitePath '/sites/OneDriveArchive'

.EXAMPLE
    .\Invoke-OneDriveArchive.ps1 `
        -KeyVaultName 'ContosoAutomation' `
        -SourceUPN    'alex@contoso.com' `
        -DestSiteHost 'contoso.sharepoint.com' `
        -DestSitePath '/sites/OneDriveArchive'
#>

[CmdletBinding(DefaultParameterSetName = 'Explicit')]
param (
    [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientId,
    [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientSecret,

    [Parameter(ParameterSetName = 'KeyVault', Mandatory)] [string]$KeyVaultName,
    [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientIdSecretName     = 'ODArchiverClientId',
    [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientSecretSecretName = 'ODArchiverClientSecret',

    [Parameter(Mandatory)] [string]$SourceUPN,
    [string]$TenantId,
    [Parameter(Mandatory)] [string]$DestSiteHost,
    [Parameter(Mandatory)] [string]$DestSitePath,
    [string]$DestFolderName,
    [string]$ShareWithUPN,
    [ValidateRange(0, 1440)] [int]$PollTimeoutMinutes = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'OneDriveArchive.psm1') -Force

$ProgressMain = 1

function Write-MainProgress {
    param([string]$Status, [int]$Step, [int]$TotalSteps = 5)
    $Pct = [int](($Step / $TotalSteps) * 100)
    Write-Progress -Id $ProgressMain -Activity 'OneDrive Migration' -Status $Status -PercentComplete $Pct
}

if ($PSCmdlet.ParameterSetName -eq 'KeyVault') {
    $Credential = Resolve-OneDriveArchiveCredential -KeyVaultName $KeyVaultName -ClientIdSecretName $ClientIdSecretName -ClientSecretSecretName $ClientSecretSecretName
} else {
    $Credential = Resolve-OneDriveArchiveCredential -ClientId $ClientId -ClientSecret $ClientSecret
}

Write-MainProgress -Status 'Resolving tenant ID...' -Step 1
$TenantId = Resolve-OneDriveArchiveTenantId -TenantId $TenantId -SourceUPN $SourceUPN -DestSiteHost $DestSiteHost

Write-MainProgress -Status 'Authenticating to Microsoft Graph...' -Step 2
Connect-OneDriveArchiveGraph -ClientId $Credential.ClientId -ClientSecret $Credential.ClientSecret -TenantId $TenantId | Out-Null

$GraphBase = 'https://graph.microsoft.com/v1.0'

Write-MainProgress -Status ('Resolving SharePoint site {0}{1}...' -f $DestSiteHost, $DestSitePath) -Step 3
$Destination = Resolve-OneDriveArchiveDestination -GraphBase $GraphBase -DestSiteHost $DestSiteHost -DestSitePath $DestSitePath

Write-MainProgress -Status ('Queuing copy for {0}...' -f $SourceUPN) -Step 4
$Job = Start-OneDriveArchiveCopy -GraphBase $GraphBase -SourceUPN $SourceUPN -DestDriveId $Destination.DriveId -DestFolderName $DestFolderName

if ($ShareWithUPN) {
    try {
        Grant-OneDriveArchiveFolderAccess -GraphBase $GraphBase -DriveId $Destination.DriveId -ItemId $Job.DestFolderId -ShareWithUPN $ShareWithUPN | Out-Null
    } catch {
        Write-OneDriveArchiveLog ('Failed to share folder with {0}: {1}' -f $ShareWithUPN, $_) 'WARN'
        $Job | Add-Member -NotePropertyName ShareError -NotePropertyValue $_.Exception.Message
    }
}

if ($Job.Items.Count -eq 0) {
    Write-OneDriveArchiveLog 'No top-level items to copy; the destination folder was created.' 'WARN'
    Write-Progress -Id $ProgressMain -Activity 'OneDrive Migration' -Completed
    return $Job
}

Write-MainProgress -Status ('Polling {0} async copy job(s)...' -f $Job.Items.Count) -Step 5
$Job.Items = @(Wait-OneDriveArchiveCopy -Items $Job.Items -TimeoutMinutes $PollTimeoutMinutes)

Write-Progress -Id $ProgressMain -Activity 'OneDrive Migration' -Completed
$Completed = @($Job.Items | Where-Object { $_.Status -eq 'completed' }).Count
$Failed = @($Job.Items | Where-Object { $_.Status -in 'failed', 'error' }).Count
$Pending = @($Job.Items | Where-Object { $_.Status -eq 'pending' }).Count
if ($Failed -gt 0 -or $Pending -gt 0) {
    Write-OneDriveArchiveLog ('Copy is not fully confirmed: {0} completed, {1} failed, {2} pending. Inspect the returned job and destination before retrying.' -f $Completed, $Failed, $Pending) 'WARN'
} else {
    Write-OneDriveArchiveLog ('All {0} copy job(s) completed. Verify the destination before continuing offboarding.' -f $Completed)
}
return $Job
