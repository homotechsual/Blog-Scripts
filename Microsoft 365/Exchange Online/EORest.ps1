using namespace System.Management.Automation
using namespace System.Runtime.InteropServices
<#
    .SYNOPSIS
        Microsoft 365 - Exchange Online - Exchange Online REST
    .DESCRIPTION
        This script will execute a scriptblock for each customer tenant for your partner tenant. The scriptblock will be executed in the context of the customer tenant. This script is designed to be used with the Secure Application Model (SAM) and the `Invoke-EORESTDelegated.ps1` script. The `Invoke-EORESTDelegated.ps1` script will authenticate to the partner tenant and then execute this script for each customer tenant. This script will then execute the scriptblock provided in the context of the customer tenant.
    .NOTES
        2022-09-07: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/09/07/Connecting-Exchange-Online-Delegated-REST/
    .EXAMPLE
        ./Invoke-EORESTDelegated.ps1 -PartnerTenantId '37abf3aa-32f5-479e-aa3c-66822ac3d258' -ApplicationId 'af8917e9-c4d7-477f-854b-b9a31a30e335' -ApplicationSecret 'sshhh its a secret' -ScriptBlock { Get-MailBoxPlan | Set-MailboxPlan  }
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Reason for suppressing')]
param (
    # The partner (CSP) tenant id.
    [Parameter(Mandatory)]
    [GUID]$PartnerTenantId,
    # The Secure Application Model application (client) id from Microsoft Azure AD.
    [Parameter(Mandatory)]
    [GUID]$ApplicationId,
    # The Secure Application Model application (client) secret from Microsoft Azure AD.
    [Parameter(Mandatory)]
    [String]$ApplicationSecret,
    # The Graph refresh token from your Secure Application Model application.
    [Parameter(Mandatory)]
    [String]$GraphRefreshToken,
    # The Exchange refresh token from your Secure Application Model application.
    [Parameter(Mandatory)]
    [String]$ExchangeRefreshToken,
    # The User Principal Name you will authenticate as. Needs sufficient permissions to access Exchange in customer tenants.
    [Parameter(Mandatory)]
    [String]$UPN,
    # Array of tenants to exclude. Use the `defaultDomainName` for the customer (https://developer.microsoft.com/en-us/graph/graph-explorer?request=contracts&method=GET&version=v1.0&GraphUrl=https://graph.microsoft.com).
    [Parameter()]
    [String[]]$ExcludedTenants,
    # The script block to execute for each customer retrieved for your partner tenant. There is a particular set of requirements for this scriptblock. Each Exchange Online command you want to execute needs to be in the format `Invoke-EORequest -Commandlet 'Get-MailboxPlan' -Params @{ AllMailboxPlanReleases = $True }`. You can use any other PowerShell in the scriptblock but your Exchange Online commands need to follow the format above.
    [Parameter(Mandatory)]
    [scriptblock]$ScriptBlock
)
# Check whether the tenant is in the included tenants array.
function _CheckIncluded ([String[]]$IncludeTenants = $IncludeTenants, [String]$Tenant) {
    if ($IncludeTenants -contains $Tenant) {
        Write-Debug ('Tenant: {0} matches entry in IncludeTenants parameter.' -f $Tenant)
        Return $true
    } else {
        Write-Debug ('Tenant: {0} does not match any entry in IncludeTenants parameter.' -f $Tenant)
        Return $false
    }
}
# Check whether the tenant is in the excluded tenants array.
function _CheckExcluded ([String[]]$ExcludeTenants = $ExcludeTenants, [String]$Tenant) {
    if ($ExcludeTenants -contains $Tenant) {
        Write-Debug ('Tenant: {0} matches entry in ExcludeTenants parameter.' -f $Tenant)
        Return $true
    } else {
        Write-Debug ('Tenant: {0} does not match any entry in ExcludeTenants parameter.' -f $Tenant)
        Return $false
    }
}
# Copy of Luke Whitelock's PartnerCenterLW function.
function _NewPartnerAccessToken (
    [GUID]$ApplicationId,
    [PSCredential]$Credential,
    [String]$RefreshToken,
    [String]$Scope,
    [String]$TenantId
) {
    Write-Verbose 'Getting access token for Tenant "{0}"' -f $TenantId
    if ($Credential) {
        $BinaryString = [Marshal]::SecureStringToBSTR($Credential.Password)
        $AppPassword = [Marshal]::PtrToStringAuto($BinaryString)
        $AuthenticationBody = @{
            client_id = $ApplicationId
            scope = $Scope
            refresh_token = $RefreshToken
            grant_type = 'refresh_token'
            client_secret = $AppPassword
        }
    } else {
        $AuthenticationBody = @{
            client_id = $ApplicationId
            scope = $Scope
            refresh_token = $RefreshToken
            grant_type = 'refresh_token'
        }
    }
    if ($TenantId) {
        $Path = '{0}/oauth2/v2.0/token' -f $TenantId
    } else {
        $Path = 'organizations/oauth2/v2.0/token'
    }
    $URI = [System.UriBuilder]'https://login.microsoftonline.com'
    $URI.Path = $Path
    try {
        $TokenResponse = (Invoke-WebRequest -Uri $URI.ToString() -ContentType 'application/x-www-form-urlencoded' -Method Post -Body $AuthenticationBody -ErrorAction Stop).content | ConvertFrom-Json
    } catch {
        Throw "Authentication Error: $_"
    }
    Return $TokenResponse.Access_Token
}
# Get partner contracts/customers from Microsoft Graph.
function _GetPartnerCustomers([String]$GraphToken) {
    Write-Verbose 'Getting Partner customers from Graph.'
    $RequestHeaders = @{ 'Authorization' = 'Bearer {0}' -f $GraphToken }
    $CustomersRequestResponse = Invoke-WebRequest -Uri 'https://graph.microsoft.com/v1.0/contracts?$top=999' -Method Get -Headers $RequestHeaders
    Write-Debug ('Raw graph contracts response: {0}' -f $CustomersRequestResponse)
    $CustomersPSObject = $CustomersRequestResponse | ConvertFrom-Json -Depth 5
    $Customers = $CustomersPSObject.value
    Return $Customers
}
# Encapsulates an Exchange PowerShell command in a REST POST request to Microsoft's Exchange Online AdminAPI.
function Invoke-EORequest ([String]$Commandlet, [Hashtable]$Parameters) {
    Write-Verbose 'Making request to Exchange Online to run cmdlet: "{0}" with parameters "{1}"' -f $Commandlet, ($Parameters | Out-String)
    $Headers = @{
        Authorization = ('Bearer {0}' -f $ExchangeCustomerToken)
    }
    if (-not($Parameters)) {
        $Parameters = @{}
    }
    $EOBody = @{
        CmdletInput = @{
            CmdletName = $Commandlet
            Parameters = $Parameters
        }
    }
    $EOBodyJson = $EOBody | ConvertTo-Json -Depth 3
    $EOUri = [uri]('https://outlook.office365.com/adminapi/beta/{0}/InvokeCommand' -f $CustomerTenantId)
    $EORequestResponse = Invoke-WebRequest -Uri $EOUri -Method Post -Body $EOBodyJson -Headers $Headers -ContentType 'application/json; charset=utf-8'
    $EOResultPSObject = $EORequestResponse | ConvertFrom-Json -Depth 10
    $EOResult = $EOResultPSObject.value
    if ($EOResult) {
        $EOResult | Add-Member -MemberType NoteProperty -Name 'EORCustomerId' -Value $CustomerTenantId
    } else {
        $EOResult = @{}
    }
    Return $EOResult 
}
# Get a Graph token so we can get customers from Microsoft Graph.
$PartnerGraphCredentials = [PSCredential]::New($ApplicationId, (ConvertTo-SecureString $ApplicationSecret -AsPlainText))
$PartnerGraphParams = @{
    ApplicationId = $ApplicationId
    Credential = $PartnerGraphCredentials
    RefreshToken = $GraphRefreshToken
    Scope = 'https://graph.microsoft.com/.default'
    TenantId = $PartnerTenantId
}
$GraphPartnerToken = _NewPartnerAccessToken @PartnerGraphParams
Write-Debug ('Graph partner access token: {0}' -f $GraphPartnerToken)
# Get customers from Microsoft Graph.
$Customers = _GetPartnerCustomers -GraphToken $GraphPartnerToken
# Iterate over customers, check if excluded and run provided scriptblock.
$CommandResults = foreach ($Customer in $Customers) {
    Write-Verbose ('Processing customer {0} [{1}].' -f $Customer.displayName, $Customer.customerId)
    if (_CheckExcluded -Tenant $Customer.defaultDomainName) {
        Write-Verbose ('Skipping customer {0} as their domain {1} is in the -ExcludedTenants parameter.' -f $Customer.displayName, $Customer.defaultDomainName)
        Continue
    }
    $ExchangeCustomerParams = @{
        ApplicationId = 'a0c73c16-a7e3-4564-9a95-2bdf47383716'
        RefreshToken = $ExchangeRefreshToken
        Scope = 'https://outlook.office365.com/.default'
        TenantId = $Customer.customerId
    }
    $CustomerTenantId = $Customer.customerId
    # Get a customer scoped token for ExchangeOnline.
    $ExchangeCustomerToken = _NewPartnerAccessToken @ExchangeCustomerParams
    &$ScriptBlock
}

Return $CommandResults