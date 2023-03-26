<#
    .SYNOPSIS
        Monitoring - Windows - Domain Join Status
    .DESCRIPTION
        This script will monitor the domain join status of a Windows device and report back to NinjaOne. It can detect Azure AD, Azure AD Hybrid, and on-premises Active Directory as well as Active Directory DFS joined using the DRS (Device Registration Service).
    .NOTES
        2022-05-25: Fix incorrect property for `domainName` output.
        2022-02-15: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
$DSRegOutput = [PSObject]::New()
& dsregcmd.exe /status | Where-Object { $_ -match ' : ' } | ForEach-Object {
    $Item = $_.Trim() -split '\s:\s'
    $DSRegOutput | Add-Member -MemberType NoteProperty -Name $($Item[0] -replace '[:\s]', '') -Value $Item[1] -ErrorAction SilentlyContinue
}
if ($DSRegOutput.DomainName) {
    $domainName = $DSRegOutput.DomainName
}
if ($DSRegOutput.AzureTenantName -or $DSRegOutput.TenantName) {
    $tenantName = $DSRegOutput.TenantName
}
if ($DSRegOutput.AzureADJoined -eq 'YES') {
    if ($DSRegOutput.DomainJoined -eq 'YES') {
        Ninja-Property-Set domainJoinStatus '<GUID FOR HYBRID>' | Out-Null
        Ninja-Property-Set domainName $domainName
        Ninja-Property-Set tenantName $tenantName
    } else {
        Ninja-Property-Set domainJoinStatus '<GUID FOR AZURE AD>' | Out-Null
        Ninja-Property-Set tenantName $tenantName
    }
} elseif ($DSRegOutput.DomainJoined -eq 'YES') {
    Ninja-Property-Set domainJoinStatus '<GUID FOR AD>' | Out-Null
    Ninja-Property-Set domainName $domainName
} elseif ($DSRegOutput.EnterpriseJoined -eq 'YES') {
    Ninja-Property-Set domainJoinStatus '<GUID FOR DRS>' | Out-Null
    Ninja-Property-Set domainName $domainName
} else {
    Ninja-Property-Set domainJoinStatus '<GUID FOR NO DOMAIN>' | Out-Null
}