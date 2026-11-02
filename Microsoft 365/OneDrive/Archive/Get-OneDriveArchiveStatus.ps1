<#
.SYNOPSIS
    Reports and refreshes status for OneDrive archive jobs queued by Invoke-OneDriveArchiveBulk.ps1.

.DESCRIPTION
    Performs a single pass over every pending copy job recorded in the given state file,
    checks its current status via Microsoft Graph, prints a summary table, and writes the
    refreshed statuses back to the state file. Safe to re-run repeatedly (e.g. on a
    schedule) until everything shows completed.
    QueueError and ShareError are blank when the corresponding optional error fields
    are absent from the state file.

.PARAMETER ClientId
    App registration Client ID. Requires Files.ReadWrite.All and Sites.ReadWrite.All
    application permissions with admin consent.

.PARAMETER ClientSecret
    Client secret for the app registration.

.PARAMETER KeyVaultName
    Azure Key Vault to resolve ClientId/ClientSecret from, instead of passing them directly.
    Requires an active Connect-AzAccount session and the Az.KeyVault module.

.PARAMETER ClientIdSecretName
    Name of the Key Vault secret holding the Client ID. Defaults to 'ODArchiverClientId'.

.PARAMETER ClientSecretSecretName
    Name of the Key Vault secret holding the Client Secret. Defaults to 'ODArchiverClientSecret'.

.PARAMETER StateFilePath
    Path to the JSON state file written by Invoke-OneDriveArchiveBulk.ps1.

.PARAMETER TenantId
    Optional Microsoft Entra tenant ID (GUID) or verified domain, if auto-discovery from the
    state file's first pending entry isn't appropriate.

.EXAMPLE
    .\Get-OneDriveArchiveStatus.ps1 -KeyVaultName 'ContosoAutomation' -StateFilePath .\OneDriveArchive-Jobs.json
#>

[CmdletBinding(DefaultParameterSetName = 'Explicit')]
param (
    [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientId,
    [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientSecret,

    [Parameter(ParameterSetName = 'KeyVault', Mandatory)] [string]$KeyVaultName,
    [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientIdSecretName     = 'ODArchiverClientId',
    [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientSecretSecretName = 'ODArchiverClientSecret',

    [Parameter(Mandatory)] [string]$StateFilePath,
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'OneDriveArchive.psm1') -Force

if (-not (Test-Path -LiteralPath $StateFilePath)) { throw ('State file not found: {0}' -f $StateFilePath) }

$Results = @(Get-Content -LiteralPath $StateFilePath -Raw | ConvertFrom-Json)
$PendingUsers = @($Results | Where-Object { @($_.Items | Where-Object { $_.Status -eq 'pending' }).Count -gt 0 })

if ($PendingUsers.Count -eq 0) {
    Write-OneDriveArchiveLog 'No pending items - everything in this state file is already completed or failed.'
} else {
    if ($PSCmdlet.ParameterSetName -eq 'KeyVault') {
        $Credential = Resolve-OneDriveArchiveCredential -KeyVaultName $KeyVaultName -ClientIdSecretName $ClientIdSecretName -ClientSecretSecretName $ClientSecretSecretName
    } else {
        $Credential = Resolve-OneDriveArchiveCredential -ClientId $ClientId -ClientSecret $ClientSecret
    }

    $TenantId = Resolve-OneDriveArchiveTenantId -TenantId $TenantId -SourceUPN $PendingUsers[0].SourceUPN -DestSiteHost $PendingUsers[0].DestSiteHost
    Connect-OneDriveArchiveGraph -ClientId $Credential.ClientId -ClientSecret $Credential.ClientSecret -TenantId $TenantId | Out-Null

    foreach ($UserResult in $PendingUsers) {
        $UserResult.Items = @(Update-OneDriveArchiveCopyStatus -Items $UserResult.Items)
    }

    ConvertTo-Json -InputObject @($Results) -Depth 10 | Set-Content -LiteralPath $StateFilePath -Encoding utf8
    Write-OneDriveArchiveLog ('Refreshed status for {0} user(s) with pending items.' -f $PendingUsers.Count)
}

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------

$Report = foreach ($UserResult in $Results) {
    $Items = @($UserResult.Items)
    [PSCustomObject]@{
        SourceUPN      = $UserResult.SourceUPN
        DestFolderName = $UserResult.DestFolderName
        Total          = $Items.Count
        Completed      = @($Items | Where-Object { $_.Status -eq 'completed' }).Count
        Failed         = @($Items | Where-Object { $_.Status -in 'failed', 'error' }).Count
        Pending        = @($Items | Where-Object { $_.Status -eq 'pending' }).Count
        PollErrors     = @($Items | Where-Object { $_.PSObject.Properties.Match('PollError').Count -and $_.PollError }).Count
        QueueError     = if ($UserResult.PSObject.Properties.Match('Error').Count) { $UserResult.Error } else { $null }
        ShareError     = if ($UserResult.PSObject.Properties.Match('ShareError').Count) { $UserResult.ShareError } else { $null }
    }
}

$Report | Format-Table -AutoSize
