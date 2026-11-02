<#
.SYNOPSIS
    Shared functions for OneDrive-to-SharePoint archival via Microsoft Graph.
    Used by Invoke-OneDriveArchive.ps1, Invoke-OneDriveArchiveBulk.ps1 and
    Get-OneDriveArchiveStatus.ps1.
#>

Set-StrictMode -Version Latest

function Write-OneDriveArchiveLog {
    param([string]$Message, [string]$Level = 'INFO')
    $Prefix = switch ($Level) { 'WARN' { 'WARN ' } 'ERROR' { 'ERROR' } default { 'INFO ' } }
    # Write-Host, not Write-Output: this is called from inside functions that
    # return real values (Resolve-OneDriveArchiveCredential, etc.) - Write-Output
    # here would merge into their return value instead of just printing.
    Write-Host ('[{0}][{1}] {2}' -f (Get-Date -f 'HH:mm:ss'), $Prefix, $Message)
}

function Resolve-OneDriveArchiveCredential {
    [CmdletBinding(DefaultParameterSetName = 'Explicit')]
    param (
        [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientId,
        [Parameter(ParameterSetName = 'Explicit', Mandatory)] [string]$ClientSecret,

        [Parameter(ParameterSetName = 'KeyVault', Mandatory)] [string]$KeyVaultName,
        [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientIdSecretName     = 'ODArchiverClientId',
        [Parameter(ParameterSetName = 'KeyVault')] [string]$ClientSecretSecretName = 'ODArchiverClientSecret'
    )

    if ($PSCmdlet.ParameterSetName -eq 'KeyVault') {
        if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
            throw 'Az.KeyVault module not found. Install it with: Install-Module Az.KeyVault -Scope CurrentUser'
        }
        if (-not (Get-AzContext)) {
            throw 'No active Azure context. Run Connect-AzAccount before using -KeyVaultName.'
        }

        Write-OneDriveArchiveLog ('Resolving credentials from Key Vault ''{0}''...' -f $KeyVaultName)
        $ClientId     = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $ClientIdSecretName     -AsPlainText
        $ClientSecret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $ClientSecretSecretName -AsPlainText

        if (-not $ClientId)     { throw ("Secret '{0}' not found in vault '{1}'." -f $ClientIdSecretName, $KeyVaultName) }
        if (-not $ClientSecret) { throw ("Secret '{0}' not found in vault '{1}'." -f $ClientSecretSecretName, $KeyVaultName) }
    }

    return [PSCustomObject]@{ ClientId = $ClientId; ClientSecret = $ClientSecret }
}

function Resolve-OneDriveArchiveTenantId {
    param (
        [string]$TenantId,
        [Parameter(Mandatory)] [string]$SourceUPN,
        [Parameter(Mandatory)] [string]$DestSiteHost
    )

    if ($TenantId) {
        Write-OneDriveArchiveLog ('Using supplied tenant identifier: {0}' -f $TenantId)
        return $TenantId
    }

    $SourceDomain      = ($SourceUPN -split '@')[-1]
    $OnMicrosoftDomain = ($DestSiteHost -replace '^https?://', '') -replace '\.sharepoint\.com$', '.onmicrosoft.com'
    $TenantCandidates  = @($SourceDomain, $OnMicrosoftDomain) | Where-Object { $_ } | Select-Object -Unique

    foreach ($Candidate in $TenantCandidates) {
        Write-OneDriveArchiveLog ('Trying tenant discovery with domain: {0}' -f $Candidate)
        try {
            $OidcConfig = Invoke-RestMethod -Uri ('https://login.microsoftonline.com/{0}/v2.0/.well-known/openid-configuration' -f $Candidate) -ErrorAction Stop
            $Discovered = $OidcConfig.issuer -replace 'https://login\.microsoftonline\.com/', '' -replace '/v2\.0', ''
            if ($Discovered -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
                Write-OneDriveArchiveLog ('Tenant ID: {0}' -f $Discovered)
                return $Discovered
            }
        } catch {
            Write-OneDriveArchiveLog ('Discovery failed for {0}: {1}' -f $Candidate, $_.Exception.Message) 'WARN'
        }
    }

    throw "Could not auto-resolve tenant ID. Re-run with -TenantId '<tenant-guid-or-domain>'."
}

function Connect-OneDriveArchiveGraph {
    param (
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$ClientSecret,
        [Parameter(Mandatory)] [string]$TenantId
    )

    Write-OneDriveArchiveLog 'Authenticating to Microsoft Graph...'

    $TokenResponse = Invoke-RestMethod `
        -Uri    ('https://login.microsoftonline.com/{0}/oauth2/v2.0/token' -f $TenantId) `
        -Method POST `
        -Body   @{
            grant_type    = 'client_credentials'
            scope         = 'https://graph.microsoft.com/.default'
            client_id     = $ClientId
            client_secret = $ClientSecret
        } -ErrorAction Stop

    $script:Headers = @{ Authorization = ('Bearer {0}' -f $TokenResponse.access_token) }
    Write-OneDriveArchiveLog 'Authenticated.'
    return $script:Headers
}

function Invoke-OneDriveArchiveGraphGet {
    param([Parameter(Mandatory)] [string]$Uri)
    $Results  = @()
    $NextLink = $Uri
    do {
        $Response = Invoke-RestMethod -Uri $NextLink -Headers $script:Headers -Method GET -ErrorAction Stop

        $HasValueProperty = $Response -and ($Response.PSObject.Properties.Name -contains 'value')
        if ($HasValueProperty -and $null -ne $Response.value) {
            $Results += $Response.value
        } else {
            $Results += $Response
        }

        if ($Response -and ($Response.PSObject.Properties.Name -contains '@odata.nextLink')) {
            $NextLink = $Response.'@odata.nextLink'
        } else {
            $NextLink = $null
        }
    } while ($NextLink)
    return $Results
}

function Invoke-OneDriveArchiveGraphPost {
    param([Parameter(Mandatory)] [string]$Uri, [Parameter(Mandatory)] [hashtable]$Body, [hashtable]$ExtraHeaders = @{})
    $PostHeaders = $script:Headers.Clone()
    $PostHeaders['Content-Type'] = 'application/json'
    foreach ($Key in $ExtraHeaders.Keys) { $PostHeaders[$Key] = $ExtraHeaders[$Key] }
    return Invoke-RestMethod -Uri $Uri -Headers $PostHeaders -Method POST -Body ($Body | ConvertTo-Json -Depth 10) -ErrorAction Stop
}

function Grant-OneDriveArchiveFolderAccess {
    param (
        [Parameter(Mandatory)] [string]$GraphBase,
        [Parameter(Mandatory)] [string]$DriveId,
        [Parameter(Mandatory)] [string]$ItemId,
        [Parameter(Mandatory)] [string]$ShareWithUPN,
        [bool]$SendInvitation = $true
    )

    Write-OneDriveArchiveLog ('Sharing folder (read-only) with {0}...' -f $ShareWithUPN)

    $Response = Invoke-OneDriveArchiveGraphPost `
        -Uri  ('{0}/drives/{1}/items/{2}/invite' -f $GraphBase, $DriveId, $ItemId) `
        -Body @{
            recipients     = @(@{ email = $ShareWithUPN })
            requireSignIn  = $true
            sendInvitation = $SendInvitation
            roles          = @('read')
        }

    Write-OneDriveArchiveLog ('  -> Shared with {0}.' -f $ShareWithUPN)
    return $Response
}

function Resolve-OneDriveArchiveDestination {
    param (
        [Parameter(Mandatory)] [string]$GraphBase,
        [Parameter(Mandatory)] [string]$DestSiteHost,
        [Parameter(Mandatory)] [string]$DestSitePath
    )

    $NormalizedDestSiteHost = ($DestSiteHost -replace '^https?://', '') -replace '/$', ''
    $NormalizedDestSitePath = if ($DestSitePath.StartsWith('/')) { $DestSitePath } else { ('/{0}' -f $DestSitePath) }

    $SiteLookupUri = ('{0}/sites/{1}:{2}' -f $GraphBase, $NormalizedDestSiteHost, $NormalizedDestSitePath)
    Write-OneDriveArchiveLog ('Looking up site {0}{1}...' -f $NormalizedDestSiteHost, $NormalizedDestSitePath)

    $DestSite   = Invoke-RestMethod -Uri $SiteLookupUri -Headers $script:Headers -Method GET -ErrorAction Stop
    $DestSiteId = $DestSite.id

    if (-not $DestSiteId) { throw ('Could not resolve site: {0}{1}' -f $DestSiteHost, $DestSitePath) }
    Write-OneDriveArchiveLog ('Site ID: {0}' -f $DestSiteId)

    # Use the singular /drive endpoint to get the site's default document library, not just any documentLibrary-type drive (Site Assets etc. are also documentLibrary type)
    $DestDrive = Invoke-RestMethod -Uri ('{0}/sites/{1}/drive' -f $GraphBase, $DestSiteId) -Headers $script:Headers -Method GET -ErrorAction Stop

    if (-not $DestDrive) { throw ('Could not find the default document library on site {0}' -f $DestSiteId) }

    Write-OneDriveArchiveLog ('Destination drive ID: {0}' -f $DestDrive.id)
    return [PSCustomObject]@{ SiteId = $DestSiteId; DriveId = $DestDrive.id; DriveName = $DestDrive.name }
}

function Start-OneDriveArchiveCopy {
    param (
        [Parameter(Mandatory)] [string]$GraphBase,
        [Parameter(Mandatory)] [string]$SourceUPN,
        [Parameter(Mandatory)] [string]$DestDriveId,
        [string]$DestFolderName
    )

    $EncodedUPN = [Uri]::EscapeDataString($SourceUPN.Trim())
    if ([string]::IsNullOrWhiteSpace($DestFolderName)) {
        Write-OneDriveArchiveLog ('Resolving display name for {0}...' -f $SourceUPN)
        try {
            $User = Invoke-OneDriveArchiveGraphGet -Uri ('{0}/users/{1}?$select=displayName' -f $GraphBase, $EncodedUPN)
        } catch {
            throw ('Could not resolve display name for {0}. Ensure the app has Microsoft Graph User.Read.All application permission with admin consent, or supply an explicit DestFolderName. Graph error: {1}' -f $SourceUPN, $_.Exception.Message)
        }
        if (-not $User -or $User.PSObject.Properties.Name -notcontains 'displayName' -or [string]::IsNullOrWhiteSpace($User.displayName)) {
            throw ('No display name returned for {0}. Supply an explicit DestFolderName.' -f $SourceUPN)
        }
        $DestFolderName = ConvertTo-OneDriveArchiveFolderName -DisplayName $User.displayName
    }

    Write-OneDriveArchiveLog ('Resolving OneDrive for {0}...' -f $SourceUPN)
    $SourceDrive = Invoke-OneDriveArchiveGraphGet -Uri ('{0}/users/{1}/drives' -f $GraphBase, $EncodedUPN) |
        Where-Object { $_.name -eq 'OneDrive' } | Select-Object -First 1

    if (-not $SourceDrive) { throw ('Could not find OneDrive for {0}' -f $SourceUPN) }
    $SourceDriveId = $SourceDrive.id
    Write-OneDriveArchiveLog ('Source drive ID: {0}' -f $SourceDriveId)

    Write-OneDriveArchiveLog ('Creating destination folder ''{0}''...' -f $DestFolderName)
    $DestFolder = Invoke-OneDriveArchiveGraphPost `
        -Uri  ('{0}/drives/{1}/root/children' -f $GraphBase, $DestDriveId) `
        -Body @{
            name                                = $DestFolderName
            folder                              = @{}
            '@microsoft.graph.conflictBehavior' = 'rename'
        }
    $DestFolderId = $DestFolder.id
    $DestFolderName = $DestFolder.name
    Write-OneDriveArchiveLog ('Destination folder ID: {0}' -f $DestFolderId)

    $SourceItems = @(Invoke-OneDriveArchiveGraphGet -Uri ('{0}/drives/{1}/root/children' -f $GraphBase, $SourceDriveId))
    Write-OneDriveArchiveLog ('Found {0} top-level item(s) to copy.' -f $SourceItems.Count)

    $Items = @()
    $i     = 0
    foreach ($Item in $SourceItems) {
        $i++
        Write-Progress -Id 2 -Activity 'Queuing copy jobs' `
            -Status ('[{0}/{1}] {2}' -f $i, $SourceItems.Count, $Item.name) `
            -PercentComplete ([int](($i / $SourceItems.Count) * 100))
        Write-OneDriveArchiveLog ('  [{0}/{1}] Queuing copy: {2}' -f $i, $SourceItems.Count, $Item.name)

        try {
            $CopyHeaders = $script:Headers.Clone()
            $CopyHeaders['Content-Type'] = 'application/json'
            $CopyHeaders['Prefer']       = 'respond-async'

            $CopyResponse = Invoke-WebRequest `
                -Uri             ('{0}/drives/{1}/items/{2}/copy?@microsoft.graph.conflictBehavior=rename' -f $GraphBase, $SourceDriveId, $Item.id) `
                -Method          POST `
                -Headers         $CopyHeaders `
                -Body            (@{
                    parentReference                     = @{ driveId = $DestDriveId; id = $DestFolderId }
                    name                                = $Item.name
                } | ConvertTo-Json -Depth 10) `
                -UseBasicParsing -ErrorAction Stop

            $MonitorUrl = @($CopyResponse.Headers['Location']) | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace($MonitorUrl)) {
                throw 'Copy response did not include a Location monitor URL. Completion cannot be confirmed; inspect the destination before retrying.'
            }
            $Items += [PSCustomObject]@{ Name = $Item.name; MonitorUrl = $MonitorUrl; Status = 'pending' }
            Write-OneDriveArchiveLog '    -> Queued.'
        } catch {
            $Items += [PSCustomObject]@{ Name = $Item.name; MonitorUrl = $null; Status = 'error'; Error = $_.Exception.Message }
            Write-OneDriveArchiveLog ('    -> Failed to queue ''{0}'': {1}' -f $Item.name, $_) 'WARN'
        }
    }
    Write-Progress -Id 2 -Activity 'Queuing copy jobs' -Completed

    return [PSCustomObject]@{
        SourceUPN      = $SourceUPN
        DestFolderName = $DestFolderName
        DestFolderId   = $DestFolderId
        QueuedAt       = (Get-Date).ToString('o')
        Items          = $Items
    }
}

function Update-OneDriveArchiveCopyStatus {
    param([Parameter(Mandatory)] [object[]]$Items)

    foreach ($Item in $Items) {
        if ($Item.Status -ne 'pending') { continue }
        try {
            $Status = Invoke-RestMethod -Uri $Item.MonitorUrl -Headers $script:Headers -ErrorAction Stop
            if (-not $Status -or $Status.PSObject.Properties.Name -notcontains 'status') {
                throw 'Copy monitor response did not include a status.'
            }
            if ($Status.status -notin 'notStarted', 'inProgress', 'updating', 'waiting', 'deletePending', 'completed', 'failed', 'deleteFailed') {
                throw ('Unrecognised copy status: {0}' -f $Status.status)
            }
            $Item.PSObject.Properties.Remove('PollError')
            if ($Status.status -eq 'completed') {
                $Item.Status = 'completed'
            } elseif ($Status.status -in 'failed', 'deleteFailed') {
                $Item.Status = 'failed'
                $Failure = if ($Status.PSObject.Properties.Name -contains 'error' -and $Status.error) {
                    $Status.error | ConvertTo-Json -Depth 10 -Compress
                } else {
                    'Microsoft reported a failed copy without additional error details.'
                }
                $Item | Add-Member -NotePropertyName Error -NotePropertyValue $Failure -Force
                Write-OneDriveArchiveLog ('Copy failed for ''{0}'': {1}' -f $Item.Name, $Failure) 'WARN'
            }
        } catch {
            $Item | Add-Member -NotePropertyName PollError -NotePropertyValue $_.Exception.Message -Force
            Write-OneDriveArchiveLog ('Could not check ''{0}'': {1}. Status remains pending.' -f $Item.Name, $_.Exception.Message) 'WARN'
        }
    }
    return $Items
}

function Wait-OneDriveArchiveCopy {
    param (
        [Parameter(Mandatory)] [object[]]$Items,
        [ValidateRange(0, 1440)] [int]$TimeoutMinutes = 30
    )

    $Total = $Items.Count
    if (@($Items | Where-Object { $_.Status -eq 'pending' }).Count -eq 0) { return $Items }

    $Timeout = [DateTime]::UtcNow.AddMinutes($TimeoutMinutes)

    while (@($Items | Where-Object { $_.Status -eq 'pending' }).Count -gt 0 -and [DateTime]::UtcNow -lt $Timeout) {
        Start-Sleep -Seconds 15
        $Items = Update-OneDriveArchiveCopyStatus -Items $Items

        $Completed    = @($Items | Where-Object { $_.Status -in 'completed', 'failed', 'error' }).Count
        $StillPending = @($Items | Where-Object { $_.Status -eq 'pending' }).Count
        $TimeLeft     = $Timeout - [DateTime]::UtcNow

        Write-Progress -Id 3 -Activity 'Waiting for copy jobs to complete' `
            -Status ('{0} of {1} finished (including failures) - {2} still pending' -f $Completed, $Total, $StillPending) `
            -PercentComplete ([int](($Completed / $Total) * 100)) `
            -SecondsRemaining ([int][Math]::Max(0, $TimeLeft.TotalSeconds))
    }

    Write-Progress -Id 3 -Activity 'Waiting for copy jobs to complete' -Completed

    $StillPending = @($Items | Where-Object { $_.Status -eq 'pending' }).Count
    if ($StillPending -gt 0) {
        Write-OneDriveArchiveLog ('{0} job(s) still pending after timeout - continuing in Microsoft''s infrastructure.' -f $StillPending) 'WARN'
    }

    return $Items
}

function ConvertTo-OneDriveArchiveFolderName {
    param([Parameter(Mandatory)] [string]$DisplayName)
    $FolderName = ($DisplayName -replace '["*:<>?/\\|\x00-\x1F]', '_').Trim() -replace '[ .]+$', ''
    if ([string]::IsNullOrWhiteSpace($FolderName)) {
        throw 'The display name does not produce a valid folder name. Supply an explicit DestFolderName.'
    }
    return $FolderName
}

Export-ModuleMember -Function *
