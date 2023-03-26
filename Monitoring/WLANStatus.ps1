<#
    .SYNOPSIS
        Monitoring - Windows - WLAN
    .DESCRIPTION
        This script will monitor the WLAN (Wi-Fi) status of a Windows device and report back to NinjaOne. It can detect the number of failures, warnings, and disconnect reasons.
    .NOTES
        2022-02-15: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
try {
    & netsh wlan show wlanreport
    if ($LASTEXITCODE -ne 0) { throw 'Failed to generate WLAN report.' }
    $WriteTime = Get-Item "$($ENV:SystemDrive)\ProgramData\Microsoft\Windows\WLANReport\wlan-report-latest.xml" | Where-Object {
        $_.LastWriteTime -gt (Get-Date).AddHours(-4)
    }
    if (!$WriteTime) { throw 'No recent WLAN report found.' }
    $WLANSummary = $WriteTime | Select-Xml -XPath '//WlanEventsSummary' | Select-Object -ExpandProperty 'Node'
    $Failures = $WLANSummary.StatusSummary.Failed
    # $Successes = $WLANSummary.StatusSummary.Successful
    $Warnings = $WLANSummary.StatusSummary.Warning
    $DisconnectReasons = $WLANSummary.DisconnectReasons.Reason
    if ($DisconnectReasons) {
        $ReasonOutput = $DisconnectReasons | ForEach-Object {
            [PSCustomObject]@{
                Reason = $_.message
                Count = [int]$_.count
                Type = $_.type
            }
        }
    }
    
    Ninja-Property-Set wlanFailures $Failures | Out-Null
    Ninja-Property-Set wlanWarnings $Warnings | Out-Null
    Ninja-Property-Set wlanDisconnectReasons ($ReasonOutput | ConvertTo-Json) | Out-Null
} catch {
    Write-Error "Failed to generate, retrieve or parse WLAN report: $($_.Exception.Message)"
}