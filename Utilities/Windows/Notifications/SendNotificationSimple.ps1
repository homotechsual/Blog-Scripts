#requires -version 5.1
<#
    .SYNOPSIS
        Utilities - Windows - Notifications - Send Notification (Simple)
    .DESCRIPTION
        Sends a simple toast notification to the Windows notification center.
    .NOTES
        2023-01-17: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2023/01/10/Updating-Drivers-from-Microsoft-Update/
#>
[CmdletBinding()]
Param(
    [string]$AppID = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe',
    [string]$NotificationImage,
    [Parameter(Mandatory)]
    [string]$NotificationTitle,
    [Parameter(Mandatory)]
    [string]$NotificationMessage,
    [ValidateSet('alarm', 'reminder', 'incomingcall', 'default')]
    [string]$NotificationType = 'default'
)
$null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
$null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
$NotificationTemplate = [xml]@"
<toast scenario="$NotificationType">
    <visual>
        <binding template="ToastGeneric">
            <text>$NotificationTitle</text>
            <text>$NotificationMessage</text>
            <image placement="appLogoOverride" src="$NotificationImage"/>
        </binding>
    </visual>
</toast>
"@
$NotificationXML = [Windows.Data.XML.DOM.XMLDocument]::New()
$NotificationXML.LoadXml($NotificationTemplate.OuterXml)
$Toast = [Windows.UI.Notifications.ToastNotification]::new($NotificationXML)
$ToastNotifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppID)
$ToastNotifier.Show($Toast)