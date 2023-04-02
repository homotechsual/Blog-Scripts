<#
    .SYNOPSIS
        Update Management - Update Click-to-Run Office
    .DESCRIPTION
        This script forces through an update of Click-to-Run installations of Microsoft Office or Microsoft 365 apps.
    .NOTES
        2023-03-15: Exit if the Click-to-Run executable can't be found
        2023-03-15: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2023/03/15/CVE-Monitoring-NinjaOne/
#>
[CmdletBinding()]
param ()

if ([System.Environment]::Is64BitOperatingSystem) {
    $C2RPaths = @(
        (Join-Path -Path $ENV:SystemDrive -ChildPath 'Program Files (x86)\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe'),
        (Join-Path -Path $ENV:SystemDrive -ChildPath 'Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe')
    )
} else {
    $C2RPaths = (Join-Path -Path $ENV:SystemDrive -ChildPath 'Program Files\Common Files\Microsoft Shared\ClickToRun\OfficeC2RClient.exe')
}
$C2RPaths | ForEach-Object {
    if (Test-Path -Path $_) {
        $C2RPath = $_
    }
}
if ($C2RPath) {
    Write-Verbose "C2RPath: $C2RPath"
    Start-Process -FilePath $C2RPath -ArgumentList '/update user displaylevel=false forceappshutdown=true' -Wait
} else {
    Write-Error 'No Click-to-Run Office installation detected. This script only works with Click-to-Run Office installations.'
    Exit 1
}