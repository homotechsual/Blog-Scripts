<#
.SYNOPSIS
    Queues OneDrive-to-SharePoint archive copies for multiple users in bulk.

.DESCRIPTION
    Queues server-side copy jobs for every user supplied via -CsvPath and/or -SourceUPN,
    without waiting for them to complete (Graph copy jobs run entirely server-side, so
    there is nothing local to keep running or background). Queued job details are written
    to a JSON state file - check on progress later with Get-OneDriveArchiveStatus.ps1.

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

.PARAMETER CsvPath
    CSV of users to migrate. Columns: SourceUPN (required), DestFolderName, DestSiteHost,
    DestSitePath, ShareWithUPN (all optional - blank cells fall back to -DestSiteHost/
    -DestSitePath/-ShareWithUPN, or the user's Microsoft Entra display name).
    Unsupported characters in display-name-derived folder names become underscores.
    An explicit DestFolderName skips lookup; a failed lookup is recorded as a per-user
    error, without creating an email-prefix folder, and the batch continues.
    Generate a template with New-OneDriveArchiveBulkTemplate.ps1.

.PARAMETER SourceUPN
    Additional UPNs to migrate, alongside or instead of -CsvPath. Destination folder names
    use each user's display name, including when supplying just one UPN manually.

.PARAMETER ShareWithUPN
    Default UPN to grant read-only access to each destination folder (e.g. a leaver's
    manager), for users that don't specify their own ShareWithUPN in the CSV. Sends
    Microsoft's standard sharing-invitation email. Omit to skip sharing.

.PARAMETER TenantId
    Optional Microsoft Entra tenant ID (GUID) or verified domain. If omitted, auto-discovery
    runs once against the first user/destination pair in the batch. Each batch must contain
    sources and destinations from one tenant; an explicit TenantId does not enable cross-tenant copying.

.PARAMETER DestSiteHost
    Default SharePoint hostname for users that don't specify their own in the CSV. Optional
    if every CSV row supplies its own DestSiteHost.

.PARAMETER DestSitePath
    Default server-relative site path for users that don't specify their own in the CSV.
    Optional if every CSV row supplies its own DestSitePath.

.PARAMETER StateFilePath
    Where to write the JSON job state file. Defaults to a timestamped file in the current
    directory. An existing file is never overwritten by this queue command.
    State is saved after each user. Use Get-OneDriveArchiveStatus.ps1 to refresh an existing file.

.EXAMPLE
    .\Invoke-OneDriveArchiveBulk.ps1 -KeyVaultName 'ContosoAutomation' -CsvPath .\leavers.csv `
        -DestSiteHost 'contoso.sharepoint.com' -DestSitePath '/sites/OneDriveArchive'

.EXAMPLE
    .\Invoke-OneDriveArchiveBulk.ps1 -KeyVaultName 'ContosoAutomation' -CsvPath .\leavers.csv
    # No shared -DestSiteHost/-DestSitePath needed if the CSV specifies them per row.

.EXAMPLE
    .\Invoke-OneDriveArchiveBulk.ps1 -KeyVaultName 'ContosoAutomation' -SourceUPN 'user@contoso.com' `
        -DestSiteHost 'contoso.sharepoint.com' -DestSitePath '/sites/OneDriveArchive'
    # Queues one user without a CSV, using their display name as the folder name.
#>

[CmdletBinding(DefaultParameterSetName = 'Explicit')]
param (
    [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientId,
    [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientSecret,

    [Parameter(ParameterSetName = 'KeyVault', Mandatory)] [string]$KeyVaultName,
    [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientIdSecretName     = 'ODArchiverClientId',
    [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientSecretSecretName = 'ODArchiverClientSecret',

    [string]  $CsvPath,
    [string[]]$SourceUPN,
    [string]  $TenantId,
    [string]  $DestSiteHost,
    [string]  $DestSitePath,
    [string]  $ShareWithUPN,
    [string]  $StateFilePath = ('.\OneDriveArchive-Jobs-{0}.json' -f (Get-Date -f 'yyyyMMdd-HHmmss'))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'OneDriveArchive.psm1') -Force

if (-not $CsvPath -and -not $SourceUPN) {
    throw 'Supply -CsvPath, -SourceUPN, or both.'
}

if (Test-Path -LiteralPath $StateFilePath) {
    throw ('State file already exists: {0}. Use Get-OneDriveArchiveStatus.ps1 to refresh it, or choose a new path for a new batch.' -f $StateFilePath)
}

# ---------------------------------------------------------------
# Build the unified list of users to queue
# ---------------------------------------------------------------

$Entries = @()

if ($CsvPath) {
    if (-not (Test-Path -LiteralPath $CsvPath)) { throw ('CSV not found: {0}' -f $CsvPath) }
    $CsvRows = @(Import-Csv -LiteralPath $CsvPath)
    foreach ($Row in $CsvRows) {
        if ($Row.PSObject.Properties.Name -notcontains 'SourceUPN') {
            throw 'CSV must include a SourceUPN column.'
        }
        if (-not $Row.SourceUPN) { Write-OneDriveArchiveLog 'Skipping CSV row with blank SourceUPN.' 'WARN'; continue }
        $RowFields = $Row.PSObject.Properties.Name
        $Entries += [PSCustomObject]@{
            SourceUPN      = $Row.SourceUPN.Trim()
            DestFolderName = if (($RowFields -contains 'DestFolderName') -and $Row.DestFolderName) { $Row.DestFolderName.Trim() } else { $null }
            DestSiteHost   = if (($RowFields -contains 'DestSiteHost')   -and $Row.DestSiteHost)   { $Row.DestSiteHost.Trim() }   else { $DestSiteHost }
            DestSitePath   = if (($RowFields -contains 'DestSitePath')   -and $Row.DestSitePath)   { $Row.DestSitePath.Trim() }   else { $DestSitePath }
            ShareWithUPN   = if (($RowFields -contains 'ShareWithUPN')   -and $Row.ShareWithUPN)   { $Row.ShareWithUPN.Trim() }   else { $ShareWithUPN }
        }
    }
}

foreach ($UPN in $SourceUPN) {
    $Entries += [PSCustomObject]@{
        SourceUPN      = $UPN.Trim()
        DestFolderName = $null
        DestSiteHost   = $DestSiteHost
        DestSitePath   = $DestSitePath
        ShareWithUPN   = $ShareWithUPN
    }
}

if ($Entries.Count -eq 0) { throw 'No users to migrate.' }

$MissingDest = $Entries | Where-Object { -not $_.DestSiteHost -or -not $_.DestSitePath }
if ($MissingDest) {
    $Names = ($MissingDest | ForEach-Object { $_.SourceUPN }) -join ', '
    throw ('No DestSiteHost/DestSitePath for: {0}. Set these per-row in the CSV, or pass -DestSiteHost/-DestSitePath as a shared default.' -f $Names)
}

Write-OneDriveArchiveLog ('Queuing archive copies for {0} user(s).' -f $Entries.Count)

# ---------------------------------------------------------------
# Authenticate (once for the whole batch)
# ---------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'KeyVault') {
    $Credential = Resolve-OneDriveArchiveCredential -KeyVaultName $KeyVaultName -ClientIdSecretName $ClientIdSecretName -ClientSecretSecretName $ClientSecretSecretName
} else {
    $Credential = Resolve-OneDriveArchiveCredential -ClientId $ClientId -ClientSecret $ClientSecret
}

$TenantId = Resolve-OneDriveArchiveTenantId -TenantId $TenantId -SourceUPN $Entries[0].SourceUPN -DestSiteHost $Entries[0].DestSiteHost
Connect-OneDriveArchiveGraph -ClientId $Credential.ClientId -ClientSecret $Credential.ClientSecret -TenantId $TenantId | Out-Null

$GraphBase = 'https://graph.microsoft.com/v1.0'

# ---------------------------------------------------------------
# Resolve each unique destination once, then queue per user
# ---------------------------------------------------------------

$StateFileDir = Split-Path -Path $StateFilePath -Parent
if ($StateFileDir -and -not (Test-Path -LiteralPath $StateFileDir)) {
    New-Item -ItemType Directory -Path $StateFileDir -Force | Out-Null
}
# Verify the state path is writable before queuing any server-side copies.
ConvertTo-Json -InputObject @() | Set-Content -LiteralPath $StateFilePath -Encoding utf8

$DestinationCache = @{}
$Results = @()
$i       = 0

foreach ($Entry in $Entries) {
    $i++
    Write-Progress -Activity 'Bulk OneDrive archive' `
        -Status ('[{0}/{1}] {2}' -f $i, $Entries.Count, $Entry.SourceUPN) `
        -PercentComplete ([int](($i / $Entries.Count) * 100))

    Write-OneDriveArchiveLog ('[{0}/{1}] Processing {2}...' -f $i, $Entries.Count, $Entry.SourceUPN)

    try {
        $DestKey = '{0}|{1}' -f $Entry.DestSiteHost, $Entry.DestSitePath
        if (-not $DestinationCache.ContainsKey($DestKey)) {
            $DestinationCache[$DestKey] = Resolve-OneDriveArchiveDestination -GraphBase $GraphBase -DestSiteHost $Entry.DestSiteHost -DestSitePath $Entry.DestSitePath
        }
        $Destination = $DestinationCache[$DestKey]

        $Job = Start-OneDriveArchiveCopy -GraphBase $GraphBase -SourceUPN $Entry.SourceUPN -DestDriveId $Destination.DriveId -DestFolderName $Entry.DestFolderName

        # Use the actual folder name returned by Graph, including any conflict suffix.
        $DisplayDestSiteHost = ($Entry.DestSiteHost -replace '^https?://', '') -replace '/$', ''
        $DisplayDestSitePath = if ($Entry.DestSitePath.StartsWith('/')) { $Entry.DestSitePath } else { ('/{0}' -f $Entry.DestSitePath) }
        Write-OneDriveArchiveLog ('  -> {0}{1}/{2}/{3}' -f $DisplayDestSiteHost, $DisplayDestSitePath, $Destination.DriveName, $Job.DestFolderName)

        $Job | Add-Member -NotePropertyName DestSiteHost -NotePropertyValue $Entry.DestSiteHost
        $Job | Add-Member -NotePropertyName DestSitePath -NotePropertyValue $Entry.DestSitePath

        if ($Entry.ShareWithUPN) {
            try {
                Grant-OneDriveArchiveFolderAccess -GraphBase $GraphBase -DriveId $Destination.DriveId -ItemId $Job.DestFolderId -ShareWithUPN $Entry.ShareWithUPN | Out-Null
            } catch {
                Write-OneDriveArchiveLog ('  -> Failed to share folder with {0}: {1}' -f $Entry.ShareWithUPN, $_) 'WARN'
                $Job | Add-Member -NotePropertyName ShareError -NotePropertyValue $_.Exception.Message
            }
        }

        $Results += $Job
    } catch {
        Write-OneDriveArchiveLog ('  -> Failed to queue {0}: {1}' -f $Entry.SourceUPN, $_) 'WARN'
        $Results += [PSCustomObject]@{
            SourceUPN      = $Entry.SourceUPN
            DestFolderName = $Entry.DestFolderName
            DestSiteHost   = $Entry.DestSiteHost
            DestSitePath   = $Entry.DestSitePath
            DestFolderId   = $null
            QueuedAt       = (Get-Date).ToString('o')
            Items          = @()
            Error          = $_.Exception.Message
        }
    }

    ConvertTo-Json -InputObject @($Results) -Depth 10 | Set-Content -LiteralPath $StateFilePath -Encoding utf8
}

Write-Progress -Activity 'Bulk OneDrive archive' -Completed

$TotalItems = (@($Results | ForEach-Object { $_.Items.Count }) | Measure-Object -Sum).Sum
$Failed     = @($Results | Where-Object { $_.PSObject.Properties.Match('Error').Count -and $_.Error }).Count
$ItemFailures = @($Results | ForEach-Object { $_.Items } | Where-Object { $_.Status -in 'error', 'failed' }).Count

Write-OneDriveArchiveLog ('Recorded {0} top-level item(s) across {1} user(s): {2} user-level queue error(s), {3} item failure(s). Copies are not yet confirmed complete.' -f $TotalItems, $Entries.Count, $Failed, $ItemFailures)
Write-OneDriveArchiveLog ('State written to {0}' -f $StateFilePath)
Write-OneDriveArchiveLog ('Check progress with Get-OneDriveArchiveStatus.ps1 using the same authentication parameters and -StateFilePath ''{0}''.' -f $StateFilePath)
