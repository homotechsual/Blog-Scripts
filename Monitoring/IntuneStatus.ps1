<#
    .SYNOPSIS
        Monitoring - Windows - Intune Enrollment Status
    .DESCRIPTION
        This script will monitor the intune enrollment status of a Windows device and report back to NinjaOne. It will write into custom fields the enrollment status, bound tenant id, last sync attempt and sync status.
    .NOTES
        2023-09-06: Initial version
    .LINK
        Blog post: Not blogged yet.
#>
[CmdletBinding()]
param(
    # The NinjaOne custom field to log the enrollment status to.
    [String]$EnrollmentStatusCustomField = 'intuneEnrollmentStatus',
    # Log the bound tenant id to a NinjaOne custom field.
    [bool]$LogTenantId = $True,
    # The NinjaOne custom field to log the bound tenant id to.
    [String]$TenantIdCustomField = 'intuneTenantId',
    # Log the last sync attempt to a NinjaOne custom field.
    [bool]$LogLastSyncAttempt = $True,
    # The NinjaOne custom field to log the last sync attempt to.
    [String]$LastSyncAttemptCustomField = 'intuneLastSyncAttempt',
    # Log the last sync status to a NinjaOne custom field.
    [bool]$LogLastSyncStatus = $True,
    # The NinjaOne custom field to log the sync status to.
    [String]$SyncStatusCustomField = 'intuneLastSyncStatus'
)
$DSRegOutput = [PSObject]::New()
& dsregcmd.exe /status | Where-Object { $_ -match ' : ' } | ForEach-Object {
    $Item = $_.Trim() -split '\s:\s'
    $DSRegOutput | Add-Member -MemberType NoteProperty -Name $($Item[0] -replace '[:\s]', '') -Value $Item[1] -ErrorAction SilentlyContinue
}
$IntuneJoined = 0
# Test AADJ
if ($DSRegOutput.AzureADJoined -eq 'YES') {
    Write-Debug 'Device is Azure AD Joined'
    $IntuneJoined++
} else {
    Write-Error 'Device is not Azure AD Joined'
    exit 1
}
# Test MDM URL
if ($DSRegOutput.MDMUrl -like '*.microsoft.com*') {
    Write-Debug 'Device has a Microsoft MDM URL'
    $IntuneJoined++
} else {
    Write-Error 'Device does not have a Microsoft MDM URL'
    exit 1
}
# Test TenantId
if ($DSRegOutput.TenantId) {
    Write-Debug 'Device has a bound tenant id'
    $IntuneJoined++
    if ($LogTenantId) {
        Ninja-Property-Set $TenantIdCustomField $DSRegOutput.TenantId
    }
} else {
    Write-Error 'Device does not have a bound tenant id'
    exit 1
}
# Test intune certificate
$MDMCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Issuer -EQ '*CN=Microsoft Intune MDM Device CA' }
if ($MDMCert) {
    Write-Debug 'Device has an Intune MDM Device CA certificate'
    $IntuneJoined++
} else {
    Write-Error 'Device does not have an Intune MDM Device CA certificate'
    exit 1
}
# Test scheduled tasks
$MDMScheduledTask = Get-ScheduledTask | Where-Object { $_.TaskPath -like '*Microsoft*Windows*EnterpriseMgmt\*' -and $_.TaskName -eq 'PushLaunch' }
$EnrollmentGUID = $MDMScheduledTask | Select-Object -ExpandProperty TaskPath -Unique | Where-Object { $_ -like '*-*-*' } | Split-Path -Leaf
if ($EnrollmentGUID) {
    Write-Debug 'Device has an enrollment GUID'
    $IntuneJoined++
} else {
    Write-Error 'Device does not have an enrollment GUID or Intune scheduled sync task is missing'
    exit 1
}
# Test registry keys
$RegistryKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Enrollments',
    'HKLM:\SOFTWARE\Microsoft\Enrollments\Status',
    'HKLM:\SOFTWARE\Microsoft\EnterpriseResourceManager\Tracked',
    'HKLM:\SOFTWARE\Microsoft\PolicyManager\AdmxInstalled',
    'HKLM:\SOFTWARE\Microsoft\PolicyManager\Providers',
    'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Accounts',
    'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Logger',
    'HKLM:\SOFTWARE\Microsoft\Provisioning\OMADM\Sessions'
)
foreach ($Key in $RegistryKeys) {
    if (-Not(Get-ChildItem -Path $Key -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $EnrollmentGUID })) {
        Write-Error "Device is missing registry key: $Key"
        exit 1
    } else {
        Write-Debug "Device has registry key: $Key"
        $IntuneJoined++
    }
}
# Test service
$MDMService = Get-Service -Name 'IntuneManagementExtension' -ErrorAction SilentlyContinue
if ($MDMService -and $MDMService.Status -eq 'Running') {
    Write-Debug 'Device has the Intune Management Extension service'
    $IntuneJoined++
} else {
    Write-Error 'Device does not have the Intune Management Extension service or it is not running'
    exit 1
}
# Log intune enrollment status to NinjaOne
if ($IntuneJoined -eq 15) {
    Write-Host 'Device meets all Intune enrollment tests'
    Ninja-Property-Set $intuneEnrollmentStatus 1
} elseif ($IntuneJoined -gt 0) {
    Write-Warning 'Device does not meet all Intune enrollment tests but is enrolled in Intune'
    Ninja-Property-Set $intuneEnrollmentStatus 1
} else {
    Write-Error 'Device does not meet all Intune enrollment tests and is not enrolled in Intune'
    Ninja-Property-Set $intuneEnrollmentStatus 0
}
# Log last sync attempt to NinjaOne
if ($LogLastSyncAttempt) {
    $OMADMResultEvents = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'; ID = 209 } | Sort-Object -Property TimeCreated -Descending
    if ($OMADMResultEvents) {
        $LastSyncDateTime = $OMADMResultEvents | Select-Object -First 1 -ExpandProperty TimeCreated
        $UnixEpochStart = Get-Date -Date '1970-01-01'
        $LastSyncUnixTimestamp = New-TimeSpan -Start $UnixEpochStart -End $LastSyncDateTime | Select-Onbject -ExpandProperty TotalSeconds
        Ninja-Property-Set $LastSyncAttemptCustomField $LastSyncUnixTimestamp
    }
    if ($LogLastSyncStatus) {
        if (($OMADMResultEvents | Select-Object -First 1 -ExpandProperty Message) -Like '*The operation completed successfully*') {
            Ninja-Property-Set $SyncStatusCustomField 'OK'
        } else {
            Ninja-Property-Set $SyncStatusCustomField 'Error'
        }
    }
}
