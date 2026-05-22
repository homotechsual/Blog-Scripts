#Requires -Version 7.0
<#
.SYNOPSIS
    Reports external sharing and sharing links across SharePoint sites for a tenant.

.DESCRIPTION
    Fully self-contained — no external module dependencies. The target tenant ID is
    resolved automatically from the SharePoint hostname via the OpenID Connect
    well-known endpoint. Authenticates to Microsoft Graph using a multi-tenant Entra
    app registration deployed to the target tenant via CIPP.

    Enumerates:
      - All SharePoint sites in the tenant (or a specific site via -SiteUrl)
      - All drive items with sharing permissions
      - External shares (shared outside the organisation)
      - Anonymous / Anyone links
      - Per-item detail: link type, scope, role, expiry, shared with, email

    Output is exported to CSV with a summary printed to the console.

.PARAMETER SharePointHostname
    The SharePoint hostname for the target tenant, e.g. 'contoso.sharepoint.com'.
    Used to resolve the tenant ID via the well-known OIDC endpoint.
    Not required if -SiteUrl is provided (hostname is extracted automatically).

.PARAMETER SiteUrl
    Optional. Limit the scan to a specific SharePoint site URL, e.g.
    'https://contoso.sharepoint.com/sites/Finance'.
    If omitted, all sites in the tenant are scanned.

.PARAMETER OutputPath
    Directory to write the CSV report to. Defaults to the current directory.

.PARAMETER IncludeInternalLinks
    Switch. When set, also reports internal organisation-wide sharing links
    in addition to external and anonymous ones.

.PARAMETER MaxItemsPerSite
    Maximum number of drive items to retrieve per site. Default 500.

.PARAMETER ClientId
    Application (client) ID of your multi-tenant Entra app registration.

.PARAMETER ClientSecret
    Client secret of your Entra app registration.

.EXAMPLE
    # Scan a specific site
    .\Get-SharePointSharingReport.ps1 `
        -SiteUrl 'https://contoso.sharepoint.com/sites/Finance' `
        -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -ClientSecret 'your-secret'

.EXAMPLE
    # Scan all sites in a tenant
    .\Get-SharePointSharingReport.ps1 `
        -SharePointHostname 'contoso.sharepoint.com' `
        -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -ClientSecret 'your-secret'

.EXAMPLE
    # Scan all sites, include org-wide links, export to C:\Reports
    .\Get-SharePointSharingReport.ps1 `
        -SharePointHostname 'contoso.sharepoint.com' `
        -OutputPath 'C:\Reports' `
        -IncludeInternalLinks `
        -ClientId 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' `
        -ClientSecret 'your-secret'

.NOTES
    Prerequisites:
      1. An Entra app registration in your MSP tenant with:
            - Account type: Accounts in any organisational directory (multi-tenant)
            - Application permission: Sites.Read.All
            - Admin consent granted in your MSP tenant

      2. Admin consent granted in the target tenant via CIPP:
            CIPP → Tenant Administration → Applications → Deploy App Registration
         Or manually:
            https://login.microsoftonline.com/{tenantId}/adminconsent?client_id={clientId}
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$SharePointHostname,

    [Parameter()]
    [string]$SiteUrl,

    [Parameter()]
    [string]$OutputPath = (Get-Location).Path,

    [Parameter()]
    [switch]$IncludeInternalLinks,

    [Parameter()]
    [int]$MaxItemsPerSite = 500,

    [Parameter()]
    [ValidateRange(1, 5000)]
    [int]$PermissionRequestsPerMinute = 250,

    [Parameter()]
    [string]$CsvPath,

    [Parameter()]
    [switch]$Resume,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$ClientSecret
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $SharePointHostname -and -not $SiteUrl) {
    Write-Error "Provide either -SharePointHostname or -SiteUrl."
    exit 1
}
if (-not $SharePointHostname) {
    $SharePointHostname = ([uri]$SiteUrl).Host
}

#region ── Helper functions ────────────────────────────────────────────────────

function Resolve-TenantId {
    <#
    .SYNOPSIS Resolves the tenant ID from a SharePoint hostname via the OIDC well-known endpoint.
    SharePoint hostnames follow the pattern {tenant}.sharepoint.com, so the corresponding
    Entra domain is {tenant}.onmicrosoft.com.
    #>
    param([string]$Hostname)

    $prefix  = $Hostname -replace '\.sharepoint\.com$', ''
    $oidcUrl = "https://login.microsoftonline.com/$prefix.onmicrosoft.com/v2.0/.well-known/openid-configuration"

    try {
        $doc = Invoke-RestMethod -Uri $oidcUrl -Method GET
        if ($doc.issuer -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
            return $Matches[1]
        }
        throw "Tenant ID GUID not found in issuer: $($doc.issuer)"
    }
    catch {
        throw "Failed to resolve tenant ID from '$Hostname': $_"
    }
}

function Get-GraphToken {
    <#
    .SYNOPSIS Acquires an app-only access token for a tenant via client credentials.
    #>
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    $body = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
    }

    try {
        $response = Invoke-RestMethod `
            -Uri         "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method      POST `
            -Body        $body `
            -ContentType 'application/x-www-form-urlencoded'
        return $response.access_token
    }
    catch {
        throw "Failed to acquire Graph token for tenant '$TenantId': $_"
    }
}

function Invoke-GraphRequest {
    <#
    .SYNOPSIS Makes a Graph API GET request with automatic paging.
    Returns all results across all pages as a flat list.
    Handles both collection responses ({ value: [...] }) and single object responses.
    #>
    param(
        [string]$Uri,
        [string]$Token
    )

    $headers = @{ Authorization = "Bearer $Token" }
    $results = [System.Collections.Generic.List[object]]::new()

    do {
        try {
            $response = Invoke-RestMethod -Uri $Uri -Headers $headers -Method GET
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Warning "  [Graph] GET $Uri → HTTP $statusCode | $_"
            return $results
        }

        if ($response.PSObject.Properties.Name -contains 'value') {
            if ($response.value) { $results.AddRange([object[]]$response.value) }
        }
        elseif ($response.PSObject.Properties.Name -contains 'id') {
            $results.Add($response)
        }

        $Uri = if ($response.PSObject.Properties.Name -contains '@odata.nextLink') { $response.'@odata.nextLink' } else { $null }
    } while ($Uri)

    return $results
}

function Get-SharingLinkType {
    param([object]$Permission)

    $props = $Permission.PSObject.Properties.Name

    if ($props -contains 'link' -and $Permission.link) {
        $scope = if ($Permission.link.PSObject.Properties.Name -contains 'scope') { $Permission.link.scope } else { 'unknown' }
        $type  = if ($Permission.link.PSObject.Properties.Name -contains 'type')  { $Permission.link.type  } else { 'unknown' }
        $exp   = if ($props -contains 'expirationDateTime' -and $Permission.expirationDateTime) { $Permission.expirationDateTime } else { 'No expiry' }
        return [PSCustomObject]@{
            LinkType       = "$scope-$type"
            Scope          = $scope
            Role           = $type
            ExpiryDateTime = $exp
            SharedWith     = 'Link (no specific recipient)'
            Email          = ''
        }
    }

    $grantee = $null
    if ($props -contains 'grantedToV2' -and $Permission.grantedToV2)   { $grantee = $Permission.grantedToV2 }
    elseif ($props -contains 'grantedTo' -and $Permission.grantedTo)   { $grantee = $Permission.grantedTo }

    if ($grantee) {
        $granteeProps = $grantee.PSObject.Properties.Name
        $user = if ($granteeProps -contains 'user'     -and $grantee.user)     { $grantee.user }
               elseif ($granteeProps -contains 'siteUser' -and $grantee.siteUser) { $grantee.siteUser }
               elseif ($granteeProps -contains 'group'    -and $grantee.group)    { $grantee.group }
               else { $null }

        $exp   = if ($props -contains 'expirationDateTime' -and $Permission.expirationDateTime) { $Permission.expirationDateTime } else { 'No expiry' }
        $roles = if ($props -contains 'roles' -and $Permission.roles) { $Permission.roles -join ',' } else { '' }

        $displayName = if ($user -and $user.PSObject.Properties.Name -contains 'displayName') { $user.displayName } else { 'Unknown' }
        $email = if ($user) {
            if     ($user.PSObject.Properties.Name -contains 'email'     -and $user.email)     { $user.email }
            elseif ($user.PSObject.Properties.Name -contains 'loginName' -and $user.loginName) { $user.loginName }
            else   { '' }
        } else { '' }

        return [PSCustomObject]@{
            LinkType       = 'DirectShare'
            Scope          = 'specific'
            Role           = $roles
            ExpiryDateTime = $exp
            SharedWith     = $displayName
            Email          = $email
        }
    }

    return $null
}

function Test-IsExternalShare {
    param(
        [object]$Permission,
        [string]$TenantDomain
    )

    $props = $Permission.PSObject.Properties.Name

    if ($props -contains 'link' -and $Permission.link -and
        $Permission.link.PSObject.Properties.Name -contains 'scope' -and
        $Permission.link.scope -eq 'anonymous') {
        return $true
    }

    $grantee = $null
    if ($props -contains 'grantedToV2' -and $Permission.grantedToV2) { $grantee = $Permission.grantedToV2 }
    elseif ($props -contains 'grantedTo' -and $Permission.grantedTo) { $grantee = $Permission.grantedTo }

    if ($grantee) {
        $granteeProps = $grantee.PSObject.Properties.Name
        $email = ''
        if ($granteeProps -contains 'user' -and $grantee.user -and
            $grantee.user.PSObject.Properties.Name -contains 'email') {
            $email = $grantee.user.email
        }
        elseif ($granteeProps -contains 'siteUser' -and $grantee.siteUser -and
                $grantee.siteUser.PSObject.Properties.Name -contains 'loginName') {
            $email = $grantee.siteUser.loginName
        }
        if ($email -and $email -notmatch [regex]::Escape($TenantDomain)) {
            return $true
        }
    }

    return $false
}

function Wait-ForPermissionRateLimit {
    <#
    .SYNOPSIS Enforces a maximum number of permission requests per rolling 60-second window.
    #>
    param([int]$MaxRequestsPerMinute)

    $now = Get-Date

    while ($script:PermissionRequestTimestamps.Count -gt 0 -and
           ($now - $script:PermissionRequestTimestamps.Peek()).TotalSeconds -ge 60) {
        [void]$script:PermissionRequestTimestamps.Dequeue()
    }

    if ($script:PermissionRequestTimestamps.Count -ge $MaxRequestsPerMinute) {
        $oldest = $script:PermissionRequestTimestamps.Peek()
        $waitForSeconds = [math]::Ceiling(60 - ($now - $oldest).TotalSeconds)
        if ($waitForSeconds -lt 1) { $waitForSeconds = 1 }

        $script:ThrottlePauseCount++
        Write-Host (
            "    ↳ Throttle guard: reached {0} permission requests/min. Pausing {1}s..." -f
            $MaxRequestsPerMinute,
            $waitForSeconds
        ) -ForegroundColor Yellow

        Start-Sleep -Seconds $waitForSeconds
        $now = Get-Date

        while ($script:PermissionRequestTimestamps.Count -gt 0 -and
               ($now - $script:PermissionRequestTimestamps.Peek()).TotalSeconds -ge 60) {
            [void]$script:PermissionRequestTimestamps.Dequeue()
        }
    }

    $script:PermissionRequestTimestamps.Enqueue((Get-Date))
}

function Write-ReportRow {
    <#
    .SYNOPSIS Writes a single report row to CSV immediately so progress is preserved.
    #>
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Row,

        [Parameter(Mandatory)]
        [string]$CsvPath
    )

    if (Test-Path -LiteralPath $CsvPath) {
        $Row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -Append
    }
    else {
        $Row | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
    }
}

#endregion

#region ── Startup ─────────────────────────────────────────────────────────────

Write-Host "SharePoint External Sharing Report" -ForegroundColor Green
Write-Host ("Run started: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray

Write-Host "  → Resolving tenant ID from '$SharePointHostname'..." -NoNewline
try {
    $tenantId = Resolve-TenantId -Hostname $SharePointHostname
    Write-Host (" $tenantId") -ForegroundColor Green
}
catch {
    Write-Error $_
    exit 1
}

$tenantDomain = $SharePointHostname -replace '\.sharepoint\.com$', ''

Write-Host "  → Authenticating to Graph..." -NoNewline
try {
    $token = Get-GraphToken -TenantId $tenantId -ClientId $ClientId -ClientSecret $ClientSecret
    Write-Host " ✔" -ForegroundColor Green
}
catch {
    Write-Error $_
    exit 1
}

#endregion

#region ── Main scan ───────────────────────────────────────────────────────────

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$graphBase = 'https://graph.microsoft.com/v1.0'

if ($CsvPath) {
    if ([System.IO.Path]::IsPathRooted($CsvPath)) {
        $csvFile = $CsvPath
    }
    else {
        $csvFile = Join-Path $OutputPath $CsvPath
    }
}
else {
    $csvFile = Join-Path $OutputPath ("SharePointSharing_{0}_{1}.csv" -f $tenantDomain, $timestamp)
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$script:PermissionRequestTimestamps = [System.Collections.Generic.Queue[datetime]]::new()
$script:ThrottlePauseCount = 0

$processedPermissionKeys = [System.Collections.Generic.HashSet[string]]::new()
$processedSiteIds        = [System.Collections.Generic.HashSet[string]]::new()

$rowsWritten      = 0
$sharedRowsCount  = 0
$externalCount    = 0
$anonymousCount   = 0

if ($Resume -and (Test-Path -LiteralPath $csvFile)) {
    Write-Host ("  → Resume mode: loading existing rows from '{0}'" -f $csvFile) -ForegroundColor Yellow
    $existingRows = Import-Csv -Path $csvFile

    foreach ($existingRow in $existingRows) {
        $rowsWritten++

        if ($existingRow.ReportType -eq 'SiteSettings' -and $existingRow.SiteId) {
            [void]$processedSiteIds.Add([string]$existingRow.SiteId)
            continue
        }

        if ($existingRow.ReportType -eq 'SharedItem') {
            $sharedRowsCount++
            if ($existingRow.IsExternal -eq 'True') { $externalCount++ }
            if ($existingRow.Scope -eq 'anonymous') { $anonymousCount++ }

            $existingPermId = if ($existingRow.PSObject.Properties.Name -contains 'PermissionId') {
                [string]$existingRow.PermissionId
            }
            else {
                ''
            }
            $existingKey = "{0}|{1}|{2}" -f [string]$existingRow.SiteId, [string]$existingRow.ItemId, $existingPermId
            [void]$processedPermissionKeys.Add($existingKey)
        }
    }

    Write-Host ("  → Resume loaded: {0} existing row(s), {1} shared row(s)." -f $rowsWritten, $sharedRowsCount) -ForegroundColor Yellow
}
elseif (-not $Resume -and (Test-Path -LiteralPath $csvFile)) {
    Remove-Item -LiteralPath $csvFile -Force
}
elseif ($Resume -and -not (Test-Path -LiteralPath $csvFile)) {
    Write-Host ("  → Resume requested but file not found. Starting new CSV: '{0}'" -f $csvFile) -ForegroundColor Yellow
}

Write-Host ("  → CSV streaming enabled: writing rows as they are found to '{0}'" -f $csvFile) -ForegroundColor Gray
Write-Host ("  → Throttle guard enabled: max {0} permission requests per minute" -f $PermissionRequestsPerMinute) -ForegroundColor Gray

#── 1. Enumerate sites ────────────────────────────────────────────────────────
Write-Host "  → Retrieving SharePoint sites..." -NoNewline

if ($SiteUrl) {
    $spUri    = [uri]$SiteUrl
    $spHost   = $spUri.Host
    $spPath   = $spUri.AbsolutePath.TrimStart('/')
    $sitesUri = "$graphBase/sites/${spHost}:/${spPath}?`$select=id,name,displayName,webUrl"
    $sites    = @(Invoke-GraphRequest -Uri $sitesUri -Token $token)
}
else {
    $sitesUri = "$graphBase/sites/getAllSites?`$select=id,name,displayName,webUrl&`$top=200"
    $sites    = @(Invoke-GraphRequest -Uri $sitesUri -Token $token)
}

Write-Host (" {0} site(s) found." -f $sites.Count) -ForegroundColor Cyan

if (-not $sites) {
    Write-Error "No sites returned. Verify admin consent has been granted for ClientId '$ClientId' in tenant '$tenantId'."
    exit 1
}

$siteTotal = $sites.Count

foreach ($site in $sites) {

    $siteIndex  = [array]::IndexOf($sites, $site) + 1
    $siteName   = if ($site.PSObject.Properties.Name -contains 'displayName' -and $site.displayName) { $site.displayName } else { $site.name }
    $siteWebUrl = $site.webUrl
    $siteId     = $site.id

    Write-Host ("`n  [{0}/{1}] Site: {2}" -f $siteIndex, $siteTotal, $siteName) -ForegroundColor White

    #── 2. Site-level settings row ────────────────────────────────────────────
    $siteSettingsRow = [PSCustomObject]@{
        TenantDomain      = $tenantDomain
        TenantId          = $tenantId
        SiteName          = $siteName
        SiteUrl           = $siteWebUrl
        ReportType        = 'SiteSettings'
        ItemName          = ''
        ItemPath          = ''
        ItemType          = ''
        ItemSize_KB       = ''
        LastModified      = ''
        LinkType          = ''
        Scope             = ''
        Role              = ''
        ExpiryDateTime    = ''
        SharedWith        = ''
        SharedWithEmail   = ''
        IsExternal        = ''
        SiteId            = $siteId
        ItemId            = ''
    }

    if (-not $processedSiteIds.Contains([string]$siteId)) {
        Write-ReportRow -Row $siteSettingsRow -CsvPath $csvFile
        $rowsWritten++
        [void]$processedSiteIds.Add([string]$siteId)
    }

    #── 3. Enumerate drive items ──────────────────────────────────────────────
    Write-Progress -Id 1 -Activity ("Site {0}/{1}: {2}" -f $siteIndex, $siteTotal, $siteName) `
        -Status "Retrieving drive items..." `
        -PercentComplete 0

    $driveUri = "$graphBase/sites/$siteId/drive/root/search(q='')" +
                "?`$select=id,name,webUrl,size,lastModifiedDateTime,file,folder" +
                "&`$top=$MaxItemsPerSite"

    $items = Invoke-GraphRequest -Uri $driveUri -Token $token

    if (-not $items) {
        Write-Host "    → No drive items found." -ForegroundColor DarkGray
        Write-Progress -Id 1 -Activity ("Site {0}/{1}: {2}" -f $siteIndex, $siteTotal, $siteName) -Completed
        continue
    }

    $sharedCount = 0
    $itemIndex   = 0
    $itemTotal   = $items.Count

    Write-Host ("    → {0} item(s) found. Checking permissions..." -f $itemTotal) -ForegroundColor Gray

    foreach ($item in $items) {

        $itemIndex++
        $itemPct = [math]::Round(($itemIndex / $itemTotal) * 100)

        Write-Progress -Id 1 -Activity ("Site {0}/{1}: {2}" -f $siteIndex, $siteTotal, $siteName) `
            -Status ("Item {0}/{1} — {2}" -f $itemIndex, $itemTotal, $item.name) `
            -PercentComplete $itemPct

        #── 4. Get permissions per item ───────────────────────────────────────
        Wait-ForPermissionRateLimit -MaxRequestsPerMinute $PermissionRequestsPerMinute
        $permUri     = "$graphBase/sites/$siteId/drive/items/$($item.id)/permissions"
        $permissions = Invoke-GraphRequest -Uri $permUri -Token $token

        foreach ($perm in $permissions) {

            $permProps    = $perm.PSObject.Properties.Name
            $hasLink      = $permProps -contains 'link'        -and $perm.link
            $hasGrantedTo = $permProps -contains 'grantedToV2' -and $perm.grantedToV2
            $hasRoles     = $permProps -contains 'roles'       -and $perm.roles

            # Skip owner entry — not a share
            if ($hasRoles -and $perm.roles -contains 'owner' -and -not $hasLink -and -not $hasGrantedTo) {
                continue
            }

            $shareDetail = Get-SharingLinkType -Permission $perm
            if (-not $shareDetail) { continue }

            $isExternal = Test-IsExternalShare -Permission $perm -TenantDomain $tenantDomain

            if (-not $IncludeInternalLinks -and -not $isExternal) { continue }

            $permissionId = if ($permProps -contains 'id' -and $perm.id) {
                [string]$perm.id
            }
            else {
                "fallback:{0}|{1}|{2}|{3}|{4}" -f
                    [string]$shareDetail.LinkType,
                    [string]$shareDetail.Scope,
                    [string]$shareDetail.Role,
                    [string]$shareDetail.Email,
                    [string]$shareDetail.ExpiryDateTime
            }
            $permissionKey = "{0}|{1}|{2}" -f [string]$siteId, [string]$item.id, $permissionId
            if ($processedPermissionKeys.Contains($permissionKey)) { continue }

            $sharedCount++
            $row = [PSCustomObject]@{
                TenantDomain      = $tenantDomain
                TenantId          = $tenantId
                SiteName          = $siteName
                SiteUrl           = $siteWebUrl
                ReportType        = 'SharedItem'
                ItemName          = $item.name
                ItemPath          = $item.webUrl
                ItemType          = if     ($item.PSObject.Properties.Name -contains 'file'   -and $item.file)   { 'File' }
                                    elseif ($item.PSObject.Properties.Name -contains 'folder' -and $item.folder) { 'Folder' }
                                    else   { 'Unknown' }
                ItemSize_KB       = if ($item.PSObject.Properties.Name -contains 'size' -and $item.size) { [math]::Round($item.size / 1KB, 1) } else { '' }
                LastModified      = $item.lastModifiedDateTime
                LinkType          = $shareDetail.LinkType
                Scope             = $shareDetail.Scope
                Role              = $shareDetail.Role
                ExpiryDateTime    = $shareDetail.ExpiryDateTime
                SharedWith        = $shareDetail.SharedWith
                SharedWithEmail   = $shareDetail.Email
                IsExternal        = $isExternal
                SiteId            = $siteId
                ItemId            = $item.id
                PermissionId      = $permissionId
            }

            Write-ReportRow -Row $row -CsvPath $csvFile
            $rowsWritten++
            $sharedRowsCount++
            if ($isExternal) { $externalCount++ }
            if ($shareDetail.Scope -eq 'anonymous') { $anonymousCount++ }
            [void]$processedPermissionKeys.Add($permissionKey)
        }
    }

    Write-Progress -Id 1 -Activity ("Site {0}/{1}: {2}" -f $siteIndex, $siteTotal, $siteName) -Completed

    if ($sharedCount -gt 0) {
        Write-Host ("    → {0} external/anonymous share(s) recorded." -f $sharedCount) -ForegroundColor Magenta
    }
    else {
        Write-Host "    → No external/anonymous shares found." -ForegroundColor DarkGray
    }
}

#endregion

#region ── Export & summary ────────────────────────────────────────────────────

Write-Host ("`n✔ Wrote {0} row(s) incrementally → {1}" -f $rowsWritten, $csvFile) -ForegroundColor Green
Write-Host ("  Throttle pauses applied: {0}" -f $script:ThrottlePauseCount) -ForegroundColor Gray

Write-Host "`n── Summary ──────────────────────────────────────────────" -ForegroundColor Cyan

if ($sharedRowsCount -gt 0) {
    Write-Host ("  Tenant:          {0}  ({1})" -f $tenantDomain, $tenantId)
    Write-Host ("  Shared items:    {0}" -f $sharedRowsCount)
    Write-Host ("  External shares: {0}" -f $externalCount)
    Write-Host ("  Anonymous links: {0}" -f $anonymousCount)
}
else {
    Write-Host "  No external or anonymous sharing found." -ForegroundColor Green
}

Write-Host ("Run completed: {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor Gray

#endregion
