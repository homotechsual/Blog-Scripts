<#
    .SYNOPSIS
        Monitoring - Windows - Support Status
    .DESCRIPTION
        This script will monitor the support status of the currently installed Windows OS and report back to NinjaOne.
    .NOTES
        2023-10-26: Update to new property name in EndOfLife API.
        2023-08-02: Update to new property name in EndOfLife API.
        2023-03-26: Add output to PowerShell console for easier debugging.
        2023-01-23: Update to new property name in EndOfLife API.
        2023-01-13: Update to new property name in EndOfLife API.
        2022-07-29: Add NinjaOne custom field support.
        2022-07-29: File incorrectly contained battery health script.
        2022-02-15: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/10/05/Monitoring-AV-PowerShell/
#>
$TLS12Protocol = [System.Net.SecurityProtocolType]'Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $TLS12Protocol
$EndOfLifeUriWindows = 'https://endoflife.date/api/windows.json'
$EndOfLifeUriServer = 'https://endoflife.date/api/windowsserver.json'
$EoLRequestParams = @{
    Method = 'GET'
}
$ProductName = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ProductName).ProductName
if ($ProductName -like '*Home' -or $ProductName -like '*Pro') {
    $Edition = '(W)'
} else {
    $Edition = '(E)'
}
if ($ProductName -like '*Server*') {
    $EoLRequestParams.Uri = $EndOfLifeUriServer
    $IsServerOS = $True
} else {
    $EoLRequestParams.Uri = $EndOfLifeUriWindows
}
$LifeCycles = Invoke-RestMethod @EoLRequestParams
$WindowsVersion = [System.Environment]::OSVersion.Version
$OSVersion = ($WindowsVersion.Major, $WindowsVersion.Minor, $WindowsVersion.Build -Join '.')
$LifeCycle = $LifeCycles | Where-Object { ($_.latest -eq $OSVersion -or $_.buildId -eq $OSVersion) -and (($_.releaseLabel -like "*$Edition*") -or ($IsServerOS)) }
if ($LifeCycle) {
    Write-Output 'Windows OS support information found from https://endoflife.date'
    Write-Output "Using release label: $($LifeCycle.releaseLabel)"
    Write-Output "Using cycle: $($LifeCycle.cycle)"
    Write-Output "Latest version: $($LifeCycle.latest)"
    Write-Output "Latest version release date: $($LifeCycle.releaseDate)"
    Write-Output "Latest version end of support date: $($LifeCycle.support)"
    Write-Output "Latest version end of extended support date: $($LifeCycle.eol)"
    Write-Output "Installed product: $ProductName"
    Write-Output "Installed version: $OSVersion"
    $OSActiveSupport = ($LifeCycle.support -ge (Get-Date -Format 'yyyy-MM-dd'))
    $OSSecuritySupport = ($LifeCycle.eol -ge (Get-Date -Format 'yyyy-MM-dd'))
    if ($OSActiveSupport) {
        Ninja-Property-Set windowsActiveSupport 1
    } else {
        Ninja-Property-Set windowsActiveSupport 0
    }
    if ($OSSecuritySupport) {
        Ninja-Property-Set windowsSecuritySupport 1
    } else {
        Ninja-Property-Set windowsSecuritySupport 0
    }
} else {
    Write-Error "Support information for $ProductName $OSVersion not found from https://endoflife.date are you running an insider build?"
}