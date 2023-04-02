<#
    .SYNOPSIS
        Monitoring - Windows - Time Drift
    .DESCRIPTION
        This script will monitor time drift on the machine vs a provided "source of truth".
    .NOTES
        2023-03-22: Exclude empty lines in the output.
        2023-03-18: Add `-Resync` parameter to force a resync if the time drift exceeds threshold.
        2023-03-17: Initial version
    .LINK
        Original Source: https://kevinholman.com/2017/08/26/monitoring-for-time-drift-in-your-enterprise/
    .LINK
        Blog post: https://homotechsual.dev/2023/03/17/Monitoring-Time-Drift-PowerShell/
#>
# This script will monitor the time drift between the local machine and a reference server.
# The script accepts the following parameters:
## ReferenceServer: The NTP or local domain controller to use as a reference for time drift.
## NumberOfSamples: The number of samples to take.
## AllowedTimeDrift: The allowed time drift in seconds.
# The script will return the following:
## If the time drift is within the allowed time drift, the script will return a message if the -Verbose switch is used.
## If the time drift is greater than the allowed time drift, the script will throw an error.
## If the -Debug switch is used, the script will return various raw data.

# Thanks to David Szpunar from the NinjaOne Users Discord for inspiring this one.
# Thanks to Kevin Holman for the many useful bits of code in his script here: https://kevinholman.com/2017/08/26/monitoring-for-time-drift-in-your-enterprise/
# Thanks to Scott - CO from the One Mand Band MSP Discord for the idea to add a resync option.
# Thanks to Chris Taylor (https://christaylor.codes/) for the suggestion to add `| Where-Object { $_ }` to exclude empty lines from the output.

[CmdletBinding()]
param (
    # The NTP or local domain controller to use as a reference for time drift.
    [string]$ReferenceServer = 'time.windows.com',
    # The number of samples to take.
    [int]$NumberOfSamples = 1,
    # The allowed time drift in seconds.
    [int]$AllowedTimeDrift = 10,
    # Force a resync of the time if the time drift is greater than the allowed time drift.
    [switch]$ForceResync
)
$Win32TimeExe = Join-Path -Path $ENV:SystemRoot -ChildPath 'System32\w32tm.exe'
$Win32TimeArgs = '/stripchart /computer:{0} /samples:{1} /dataonly' -f $ReferenceServer, $NumberOfSamples
$ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
$ProcessInfo.FileName = $Win32TimeExe
$ProcessInfo.Arguments = $Win32TimeArgs
$ProcessInfo.RedirectStandardError = $true
$ProcessInfo.RedirectStandardOutput = $true
$ProcessInfo.UseShellExecute = $false
$ProcessInfo.CreateNoWindow = $true
$Process = New-Object System.Diagnostics.Process
$Process.StartInfo = $ProcessInfo
$Process.Start() | Out-Null
$ProcessResult = [PSCustomObject]@{
    ExitCode = $Process.ExitCode
    StdOut   = $Process.StandardOutput.ReadToEnd()
    StdErr   = $Process.StandardError.ReadToEnd()
}
$Process.WaitForExit()
if ($ProcessResult.StdErr) {
    throw "w32tm.exe returned the following error: $($ProcessResult.StdErr)"
} elseif ($ProcessResult.StdOut -contains 'Error') {
    throw "w32tm.exe returned the following error: $($ProcessResult.StdOut)"
} else {
    Write-Debug ('Raw StdOut: {0}' -f $ProcessResult.StdOut)
    $ProcessOutput = $ProcessResult.StdOut.Split("`n") | Where-Object { $_ }
    $Skew = $ProcessOutput[-1..($NumberOfSamples * -1)] | ConvertFrom-Csv -Header @('Time', 'Skew') | Select-Object -ExpandProperty Skew
    Write-Debug ('Raw Skew: {0}' -f $Skew)
    $AverageSkew = $Skew | ForEach-Object { $_ -replace 's', '' } | Measure-Object -Average | Select-Object -ExpandProperty Average
    Write-Debug ('Average Skew: {0}' -f $AverageSkew)
    if ($AverageSkew -lt 0) { $AverageSkew = $AverageSkew * -1 }
    $TimeDriftSeconds = [Math]::Round($AverageSkew, 2)
    if ($TimeDriftSeconds -gt $AllowedTimeDrift) {
        if ($ForceResync) {
            Start-Process -FilePath $Win32TimeExe -ArgumentList '/resync' -Wait
            Write-Warning "Time drift was greater than the allowed time drift of $AllowedTimeDrift seconds. Time drift was $TimeDriftSeconds seconds A resync was forced."
        } else {
            throw "Time drift is greater than the allowed time drift of $AllowedTimeDrift seconds. Time drift is $TimeDriftSeconds seconds."
        }
    } else {
        Write-Verbose "Time drift is within accepted limits. Time drift is $TimeDriftSeconds seconds."
    }
}