<#
    .SYNOPSIS
        Update Management - Check NinjaOne Agent Update
    .DESCRIPTION
        Compares a provided NinjaOne Agent version with the latest version available from NinjaOne.
    .PARAMETER Instance
        The NinjaOne instance to check for updates from. Valid values are 'eu', 'app', 'us2', 'oc', and 'ca'.

        Default value is 'eu'.
    .PARAMETER OS
        The operating system to check for updates for. Valid values are 'Windows', 'Mac', and 'Linux'.

        Default value is 'Windows'.
    .PARAMETER Version
        The version of the NinjaOne Agent you want to see if there is an update for.
    .NOTES
        2024-05-22: Initial Version
    .LINK
        Blog post: Not blogged yet.
#>
[CmdletBinding()]
param (
    # The NinjaOne instance to check for updates from.
    [ValidateSet('eu', 'app', 'us2', 'oc', 'ca')]
    [String]$Instance = 'eu',
    # The operating system to check for updates for.
    [ValidateSet('Windows', 'Mac', 'Linux')]
    [String]$OS = 'Windows',
    # The version of the NinjaOne Agent you want to see if there is an update for.
    [String]$Version
)
$NinjaVersions = Invoke-RestMethod -Uri ('https://{0}.ninjarmm.com/ws/infrastructure/version' -f $Instance)
$WindowsAgentVersion = $NinjaVersions.agentVersion
$MacAgentVersion = $NinjaVersions.macAgentVersion
$LinuxAgentVersion = $NinjaVersions.linAgentVersion
switch ($OS) {
    'Windows' {
        if ([version]$Version -eq [version]$WindowsAgentVersion) {
            Write-Output "The NinjaOne Agent is up to date."
        } else {
            Write-Output "The NinjaOne Agent is out of date. The latest version is $WindowsAgentVersion."
        }
    }
    'Mac' {
        if ([version]$Version -eq [version]$MacAgentVersion) {
            Write-Output "The NinjaOne Agent is up to date."
        } else {
            Write-Output "The NinjaOne Agent is out of date. The latest version is $MacAgentVersion."
        }
    }
    'Linux' {
        if ([version]$Version -eq [version]$LinuxAgentVersion) {
            Write-Output "The NinjaOne Agent is up to date."
        } else {
            Write-Output "The NinjaOne Agent is out of date. The latest version is $LinuxAgentVersion."
        }
    }
}