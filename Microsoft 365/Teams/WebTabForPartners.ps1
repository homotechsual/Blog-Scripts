<#
    .SYNOPSIS
        Microsoft 365 - Teams - Web Tab for Partners
    .DESCRIPTION
        This script will allow you to push a web tab to all your client's partner-managed tenants - it relies on having the same Team name in each tenant or can use the "default" team for each tenant. It needs a SAM application to be created in Azure AD and the application ID and secret to be passed to the script. The application requires Teams.ReadWrite.All permission.
    .NOTES
        2023-03-25: Changed the script to use parameter input instead of statically assigning variables.
        2021-11-25: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2021/11/25/Pushing-web-tab-Customers-Teams-environment/
#>
[CmdletBinding()]
param(
  # An array of customer domain names to exclude.
  [string[]]$CustomerExclude,
  # An array of customer domain names to include.
  [string[]]$CustomerInclude,
  # The Team name to add the tab for - uses wild card matching - leave blank to attempt to add to the default "whole company" Team.
  [string]$TeamName = [string]::Empty,
  # The channel name to add the tab for - leave blank for 'General'.
  $ChannelName = [string]::Empty,
  # This is the Azure AD application ID for your chosen SAM application.
  [Parameter(Mandatory)]
  [string]$ClientID,
  # This is the application secret for the chosen SAM application.
  [Parameter(Mandatory)]
  [string]$ClientSecret,
  # This is the tenant GUID for your Microsoft 365 tenant.
  [Parameter(Mandatory)]
  [string]$TenantID
  # The name of the tab to add.
  [Parameter(Mandatory)]
  [string]$TabName,
  # The URL the tab should call.
  [Parameter(Mandatory)]
  [System.Uri]$TabURL
)
# Build the request to get an access token.
$AuthRequestBody = @{
    client_id = $ClientID
    client_secret = $ClientSecret
    scope = 'https://graph.microsoft.com/.default'
    grant_type = 'client_credentials'
}
# Get an access token.
$AccessToken = (Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($TenantID)/oauth2/v2.0/token" -Method 'POST' -Body $AuthRequestBody -ErrorAction Stop)
$AuthHeader = @{ Authorization = "Bearer $($AccessToken.access_token)" }
# Get all partner contracts (Customer tenants) from Graph.
$GraphContractsURI = 'https://graph.microsoft.com/v1.0/contracts?$top=999'
$Customers = do {
    try {
        $GraphContracts = Invoke-RestMethod -Uri $GraphContractsURI -Method 'GET' -Headers $AuthHeader -ErrorAction Stop
        $GraphContractsURI = $GraphContracts.'@odata.nextLink'
        if ($GraphContracts.value) {
            $GraphContracts.value
        }
    } catch {
        if ($_.ErrorDetails.Message) {
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message
        }
        if ($Null -eq $Message) {
            $Message = $($_.Exception.Message)
        }
        throw $Message
    }
} until ([String]::IsNullOrEmpty($GraphContractsURI))
# Temporarily override the information preference to output our `Write-Information` calls.
$OriginalInformationPreference = $InformationPreference
$InformationPreference = 'Continue'
# Function to retrieve Teams from Microsoft Graph.
function Get-TeamFromGraph ([hashtable]$CustomerAuthHeader, [string]$TeamName) {
    $GraphTeamsURI = "https://graph.microsoft.com/v1.0/groups?`$filter=resourceProvisioningOptions/Any(x:x eq 'Team')"
    $Teams = do {
        try {
            $GraphTeams = Invoke-RestMethod -Uri $GraphTeamsURI -Method 'GET' -Headers $CustomerAuthHeader -ErrorAction Stop
            $GraphTeamsURI = $GraphTeams.'@odata.nextLink'
            if ($GraphTeams.value) {
                $GraphTeams.value
            }
        } catch {
            if ($_.ErrorDetails.Message) {
                $Message = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message
            }
            if ($Null -eq $Message) {
                $Message = $($_.Exception.Message)
            }
            throw $Message
        }
    } until ([String]::IsNullOrEmpty($GraphTeamsURI))
    $Team = $Teams | Where-Object { $_.displayName -eq "$($TeamName)" }
    if ($Team) {
        return $Team
    } else {
        throw "Team $($TeamName) not found."
    }
}
# Function to retrieve channels from Microsoft Graph.
function Get-TeamChannelFromGraph ([object]$Team, [hashtable]$CustomerAuthHeader, [string]$ChannelName = 'General') { 
    $Channels = do {
        try {
            $GraphTeamChannelsURI = "https://graph.microsoft.com/v1.0/teams/$($Team.id)/channels"
            $GraphChannels = Invoke-RestMethod -Uri $GraphTeamChannelsURI -Method 'GET' -Headers $CustomerAuthHeader -ErrorAction Stop
            $GraphTeamChannelsURI = $GraphChannels.'@odata.nextLink'
            if ($GraphChannels.value) {
                $GraphChannels.value
            }
        } catch {
            if ($_.ErrorDetails.Message) {
                $Message = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message
            }
            if ($Null -eq $Message) {
                $Message = $($_.Exception.Message)
            }
            throw $Message
        }
    } until ([String]::IsNullOrEmpty($GraphTeamChannelsURI))
    if (-not [String]::IsNullOrEmpty($ChannelName)) {
        $Channel = $Channels | Where-Object { $_.displayName -eq "$($ChannelName)" }
    } else {
        $Channel = $Channels
    }
    if ($Channel) {
        return $Channel
    } else {
        throw "Channel $($ChannelName) not found."
    }
}
# Function to add the tab to  the teams Channel.
function Add-TabToTeamsChannel ([hashtable]$CustomerAuthHeader, [object]$Team, [object]$Channel, [object]$Customer, [object]$Tab) {
    Write-Information "Adding Teams tab to channel $($Channel.displayName) in team $($Team.displayName) in $($Customer.displayName)."
    try {
        # Make sure we don't already have a tab with the same name.
        $Tab = (Invoke-RestMethod -Method Get -Uri ("https://graph.microsoft.com/v1.0/teams/$($team.ID)/channels/$($channel.ID)/tabs?`$filter=DisplayName eq " + "'" + $tabName + "'") -Headers $CustomerAuthHeader).value
        if (-Not $Tab) {
            # Build the tab.
            $TeamsTab = [ordered]@{
                displayName = $TabName
                "teamsApp@odata.bind" = "https://graph.microsoft.com/v1.0/appCatalogs/teamsApps/com.microsoft.teamspace.tab.web"
                configuration = @{
                    contentUrl = $TabURL
                    websiteUrl = $TabURL
                }
            } | ConvertTo-Json
            # Add the tab to the channel.
            Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/teams/$($Team.id)/channels/$($Channel.id)/tabs" -Method 'POST' -Body $TeamsTab -Headers $CustomerAuthHeader -ContentType 'application/json' -ErrorAction Stop
        } else {
            Write-Information "Tab $($Tab.displayName) already exists in channel $($Channel.displayName) in team $($Team.displayName) in $($Customer.displayName)."
        }
    } catch {
        if ($_.ErrorDetails.Message) {
            $Message = ($_.ErrorDetails.Message | ConvertFrom-Json).error.message
        }
        if ($Null -eq $Message) {
            $Message = $($_.Exception.Message)
        }
        throw $Message
    }
}

if ($CustomerExclude.Count -ge 1) {
    Write-Information "Running in exclusion mode."
} elseif ($CustomerInclude.Count -ge 1) {
    Write-Information "Running in inclusion mode."
} else {
    Write-Information "Running in all customers mode."
}

ForEach ($Customer in $Customers) {
    if ($CustomerExclude.Count -ge 1) {
        if (-Not($CustomerExclude -contains $Customer.DefaultDomainName)) {
            Write-Information "Connecting to $($Customer.DisplayName) and retrieving all Teams."
            $CustomerAccessToken = (Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($Customer.CustomerID)/oauth2/v2.0/token" -Method 'POST' -Body $AuthRequestBody -ErrorAction Stop)
            $CustomerAuthHeader = @{ Authorization = "Bearer $($CustomerAccessToken.access_token)" }
            if (-not [String]::IsNullOrEmpty($TeamName)) {
                $Team = Get-TeamFromGraph -CustomerAuthHeader $CustomerAuthHeader -TeamName $TeamName
            } else {
                $Team = Get-TeamFromGraph -CustomerAuthHeader $CustomerAuthHeader -TeamName $($Customer.DisplayName)
            }
            if (-not [String]::IsNullOrEmpty($ChannelName)) {
                $Channel = Get-TeamChannelFromGraph -Team $Team -CustomerAuthHeader $CustomerAuthHeader -ChannelName $ChannelName
            } else {
                $Channel = Get-TeamChannelFromGraph -Team $Team -CustomerAuthHeader $CustomerAuthHeader
            }
            Add-TabToTeamsChannel -CustomerAuthHeader $CustomerAuthHeader -Team $Team -Channel $Channel -Customer $Customer
        } else {
            Write-Information "Skipping $($Customer.DisplayName) as it is in the exclude list."
        }
    } elseif ($CustomerInclude.Count -ge 1) {
        if ($CustomerInclude -contains $Customer.DefaultDomainName) {
            Write-Information "Connecting to $($Customer.DisplayName) and retrieving all Teams."
            $CustomerAccessToken = (Invoke-RestMethod -Uri "https://login.microsoftonline.com/$($Customer.CustomerID)/oauth2/v2.0/token" -Method 'POST' -Body $AuthRequestBody -ErrorAction Stop)
            $CustomerAuthHeader = @{ Authorization = "Bearer $($CustomerAccessToken.access_token)" }
            if (-not [String]::IsNullOrEmpty($TeamName)) {
                $Team = Get-TeamFromGraph -CustomerAuthHeader $CustomerAuthHeader -TeamName $TeamName
            } else{
                $Team = Get-TeamFromGraph -CustomerAuthHeader $CustomerAuthHeader -TeamName $($Customer.DisplayName)
            }

            if (-not [String]::IsNullOrEmpty($ChannelName)) {
                $Channel = Get-TeamChannelFromGraph -Team $Team -CustomerAuthHeader $CustomerAuthHeader -ChannelName $ChannelName
            } else {
                $Channel = Get-TeamChannelFromGraph -Team $Team -CustomerAuthHeader $CustomerAuthHeader
            }
            Add-TabToTeamsChannel -CustomerAuthHeader $CustomerAuthHeader -Team $Team -Channel $Channel -Customer $Customer
        } else {
            Write-Information "Skipping $($Customer.DisplayName) as it is not in the include list."
        }
    }
}
$InformationPreference = $OriginalInformationPreference