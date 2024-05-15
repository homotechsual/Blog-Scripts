<#
    .SYNOPSIS
        Monitoring - Windows - User Session Events
    .DESCRIPTION
        This script will retrieve user session events from the Windows event logs. It will retrieve the following events: Logon, Logoff, Lock, and Unlock. The script will return the events in a table format.
    .PARAMETER Days
        [System.Int32]

        The number of days to retrieve events from. Default is 10 days.
    .NOTES
        2024-05-14: V1.1 - Standardise User formatting.
        2024-05-14: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
[CmdletBinding()]
param (
    # The number of days to retrieve events from. Default is 10 days.
    [int]$Days = 10,
    # The NinjaOne custom field to use to store the table.
    [string]$NinjaField = 'UserSessionEvents'
)
if ($ENV:Days) {
    $Days = [int]::Parse($ENV:Days)
}
if ($ENV:NinjaField) {
    $NinjaField = $ENV:NinjaField
}
function ConvertTo-ObjectToHtmlTable {
    param (
        [Parameter(Mandatory=$true)]
        [System.Collections.Generic.List[Object]]$Objects
    )

    $sb = New-Object System.Text.StringBuilder

    # Start the HTML table
    [void]$sb.Append('<table><thead><tr>')

    # Add column headers based on the properties of the first object, excluding "RowColour"
    $Objects[0].PSObject.Properties.Name |
        Where-Object { $_ -ne 'RowColour' } |
        ForEach-Object { [void]$sb.Append("<th>$_</th>") }

    [void]$sb.Append('</tr></thead><tbody>')

    foreach ($obj in $Objects) {
        # Use the RowColour property from the object to set the class for the row
        $rowClass = if ($obj.RowColour) { $obj.RowColour } else { "" }

        [void]$sb.Append("<tr class=`"$rowClass`">")
        # Generate table cells, excluding "RowColour"
        foreach ($propName in $obj.PSObject.Properties.Name | Where-Object { $_ -ne 'RowColour' }) {
            [void]$sb.Append("<td>$($obj.$propName)</td>")
        }
        [void]$sb.Append('</tr>')
    }

    [void]$sb.Append('</tbody></table>')

    return $sb.ToString()
}
$Events = [System.Collections.Generic.List[Object]]::new()
$LockUnlockEvents = Get-WinEvent -FilterHashtable @{ 
    LogName = 'Security'
    Id = @(4800,4801)
    StartTime = (Get-Date).AddDays(-$Days)
} -ErrorAction SilentlyContinue
if ($LockUnlockEvents) {
    $Events.AddRange($LockUnlockEvents)
}
$LoginLogoffEvents = Get-WinEvent -FilterHashtable @{ 
    LogName = 'System'
    Id = @(7001,7002)
    StartTime = (Get-Date).AddDays(-$Days)
    ProviderName = 'Microsoft-Windows-Winlogon' 
} -ErrorAction SilentlyContinue
if ($LoginLogoffEvents) {
    $Events.AddRange($LoginLogoffEvents)
}
$EventTypeLookup = @{
    7001 = 'Logon'
    7002 = 'Logoff'
    4800 = 'Lock'
    4801 = 'Unlock'
}
$XMLNameSpace = @{'ns'='http://schemas.microsoft.com/win/2004/08/events/event'}
$XPathTargetUserSID = "//ns:Data[@Name='TargetUserSid']"
$XPathUserSID = "//ns:Data[@Name='UserSid']"
if ($Events) {
    $Results = ForEach($Event in $Events) {
        $XML = $Event.ToXML()
        Switch -Regex ($Event.Id) {
            '4...' {
                $SID = (
                    Select-XML -Content $XML -Namespace $XMLNameSpace -XPath $XPathTargetUserSID
                ).Node.'#text'
                if ($SID) {
                    $User = [System.Security.Principal.SecurityIdentifier]::new($SID).Translate([System.Security.Principal.NTAccount]).Value
                } else {
                    Write-Warning ('Failed to parse SID ({0}) for event {1}.' -f $SID,$Event.Id)
                }
                Break            
            }
            '7...' {
                $SID = (
                    Select-XML -Content $XML -Namespace $XMLNameSpace -XPath $XPathUserSID
                ).Node.'#text'
                if ($SID) {
                    $User = [System.Security.Principal.SecurityIdentifier]::new($SID).Translate([System.Security.Principal.NTAccount]).Value
                } else {
                    Write-Warning ('Failed to parse SID ({0}) for event {1}.' -f $SID,$Event.Id)
                }
                Break
            }
        }
        $RowColour = switch ($Event.Id) {
            7001 { 'success' }
            7002 { 'danger' }
            4800 { 'warning' }
            4801 { 'other' }
        }
        New-Object -TypeName PSObject -Property @{
            Time = $Event.TimeCreated
            Id = $Event.Id
            Type = $EventTypeLookup[$event.Id]
            User = $User
            RowColour = $RowColour
        }
    }
    if ($Results) {
        $Objects = $Results | Sort-Object Time
        $Table = ConvertTo-ObjectToHtmlTable -Objects $Objects
        $Table | Ninja-Property-Set-Piped $NinjaField
    } else {
        throw 'Failed to process / parse events.'
    }
} else {
    Write-Warning 'No events found.'
}