<#
    .SYNOPSIS
        Monitoring - Windows - Intune Enrollment Status
    .DESCRIPTION
        This script will monitor the intune enrollment status of a Windows device and report back to NinjaOne. It will write into custom fields the enrollment status, bound tenant id, last sync attempt and sync status.
    .NOTES
        2026-05-31: Updated script to support NinjaOne script variable overrides via environment variables, added additional checks for Intune enrollment status, and improved logging and error handling.
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
    [String]$SyncStatusCustomField = 'intuneLastSyncStatus',
    # Ordered list of event logs to query for Intune sync result events.
    [String[]]$SyncResultLogNames = @(
        'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Sync',
        'Microsoft-Windows-DeviceManagement-Enterprise-Diagnostics-Provider/Admin'
    ),
    # Event ID used for Intune sync result checks.
    [int]$SyncResultEventId = 209
)

function Get-EnvString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $RawValue = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($RawValue)) {
        return $null
    }
    return [string]$RawValue
}

function Get-EnvBool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $Value = Get-EnvString -Name $Name
    if ($null -eq $Value) {
        return $null
    }

    switch -Regex ($Value.Trim().ToLowerInvariant()) {
        '^(1|true|yes|y|on)$' { return $true }
        '^(0|false|no|n|off)$' { return $false }
        default {
            Write-Warning ('Invalid boolean Ninja script variable ''{0}'' value ''{1}''. Keeping existing value.' -f $Name, $Value)
            return $null
        }
    }
}

function Get-EnvInt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $Value = Get-EnvString -Name $Name
    if ($null -eq $Value) {
        return $null
    }

    $Parsed = 0
    if ([int]::TryParse($Value.Trim(), [ref]$Parsed)) {
        return $Parsed
    }

    Write-Warning ('Invalid integer Ninja script variable ''{0}'' value ''{1}''. Keeping existing value.' -f $Name, $Value)
    return $null
}

function Get-EnvStringArray {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    $Value = Get-EnvString -Name $Name
    if ($null -eq $Value) {
        return $null
    }

    $Items = @(
        $Value.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($Items.Count -eq 0) {
        Write-Warning ('Ninja script variable ''{0}'' was provided but empty after parsing. Keeping existing value.' -f $Name)
        return $null
    }

    return $Items
}

# NinjaOne script variable overrides (environment variables).
$Value = Get-EnvString -Name 'EnrollmentStatusCustomField'; if ($null -ne $Value) { $EnrollmentStatusCustomField = $Value }
$Value = Get-EnvBool -Name 'LogTenantId'; if ($null -ne $Value) { $LogTenantId = $Value }
$Value = Get-EnvString -Name 'TenantIdCustomField'; if ($null -ne $Value) { $TenantIdCustomField = $Value }
$Value = Get-EnvBool -Name 'LogLastSyncAttempt'; if ($null -ne $Value) { $LogLastSyncAttempt = $Value }
$Value = Get-EnvString -Name 'LastSyncAttemptCustomField'; if ($null -ne $Value) { $LastSyncAttemptCustomField = $Value }
$Value = Get-EnvBool -Name 'LogLastSyncStatus'; if ($null -ne $Value) { $LogLastSyncStatus = $Value }
$Value = Get-EnvString -Name 'SyncStatusCustomField'; if ($null -ne $Value) { $SyncStatusCustomField = $Value }
$Value = Get-EnvStringArray -Name 'SyncResultLogNames'; if ($null -ne $Value) { $SyncResultLogNames = $Value }
$Value = Get-EnvInt -Name 'SyncResultEventId'; if ($null -ne $Value) { $SyncResultEventId = $Value }

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
$MDMCert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Issuer -EQ 'CN=Microsoft Intune MDM Device CA' }
if ($MDMCert) {
    Write-Debug 'Device has an Intune MDM Device CA certificate'
    $IntuneJoined++
} else {
    Write-Error 'Device does not have an Intune MDM Device CA certificate'
    exit 1
}

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

# Test scheduled tasks
$MDMScheduledTask = Get-ScheduledTask | Where-Object { $_.TaskPath -like '*Microsoft*Windows*EnterpriseMgmt\*' -and $_.TaskName -eq 'PushLaunch' }
$EnrollmentGUIDs = @(
    $MDMScheduledTask |
        Select-Object -ExpandProperty TaskPath -Unique |
        ForEach-Object { Split-Path -Path $_ -Leaf } |
        Where-Object { $_ -match '^[0-9A-Fa-f-]{36}$' } |
        Select-Object -Unique
)
if ($EnrollmentGUIDs.Count -gt 0) {
    Write-Debug 'Device has an enrollment GUID'
    $IntuneJoined++
} else {
    Write-Error 'Device does not have an enrollment GUID or Intune scheduled sync task is missing'
    exit 1
}

# Pick a primary enrollment GUID when multiple enrollment task paths exist.
$EnrollmentCandidates = foreach ($GUID in $EnrollmentGUIDs) {
    $RegistryMatches = 0
    foreach ($Key in $RegistryKeys) {
        $ChildKeyNames = @(
            Get-ChildItem -Path $Key -ErrorAction SilentlyContinue |
                ForEach-Object { Split-Path -Path $_.Name -Leaf }
        )
        if ($ChildKeyNames -contains $GUID) {
            $RegistryMatches++
        }
    }

    $TenantMatch = $false
    $EnrollmentKeyPath = ('HKLM:\SOFTWARE\Microsoft\Enrollments\{0}' -f $GUID)
    $EnrollmentKeyProps = Get-ItemProperty -Path $EnrollmentKeyPath -ErrorAction SilentlyContinue
    if ($EnrollmentKeyProps) {
        $TenantProperty = $EnrollmentKeyProps.PSObject.Properties |
            Where-Object { $_.Name -match '^AADTenantId$|^AADTenantID$|^TenantId$' } |
            Select-Object -First 1
        if ($TenantProperty -and $DSRegOutput.TenantId -and $TenantProperty.Value -eq $DSRegOutput.TenantId) {
            $TenantMatch = $true
        }
    }

    $TaskInfo = $null
    try {
        $TaskInfo = Get-ScheduledTaskInfo -TaskPath ('\Microsoft\Windows\EnterpriseMgmt\{0}\' -f $GUID) -TaskName 'PushLaunch' -ErrorAction Stop
    } catch {
    }

    [PSCustomObject]@{
        Guid = $GUID
        RegistryMatches = $RegistryMatches
        TenantMatch = $TenantMatch
        LastRunTime = if ($TaskInfo) { $TaskInfo.LastRunTime } else { [datetime]::MinValue }
    }
}

$PrimaryEnrollmentGUID = $EnrollmentCandidates |
    Sort-Object @{Expression = 'TenantMatch'; Descending = $true}, @{Expression = 'RegistryMatches'; Descending = $true}, @{Expression = 'LastRunTime'; Descending = $true} |
    Select-Object -First 1 -ExpandProperty Guid

Write-Debug ('Primary enrollment GUID selected: {0}' -f $PrimaryEnrollmentGUID)

# Test registry keys against the selected primary enrollment GUID.
foreach ($Key in $RegistryKeys) {
    $ChildKeyNames = @(
        Get-ChildItem -Path $Key -ErrorAction SilentlyContinue |
            ForEach-Object { Split-Path -Path $_.Name -Leaf }
    )
    $HasMatchingEnrollmentKey = ($ChildKeyNames -contains $PrimaryEnrollmentGUID)
    if (-Not $HasMatchingEnrollmentKey) {
        Write-Error ('Device is missing registry key for primary enrollment GUID ({0}): {1}' -f $PrimaryEnrollmentGUID, $Key)
        exit 1
    } else {
        Write-Debug ('Device has registry key: {0}' -f $Key)
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
$ExpectedIntuneChecks = 6 + $RegistryKeys.Count
if ($IntuneJoined -eq $ExpectedIntuneChecks) {
    Write-Host 'Device meets all Intune enrollment tests'
    Ninja-Property-Set $EnrollmentStatusCustomField 1
} elseif ($IntuneJoined -gt 0) {
    Write-Warning 'Device does not meet all Intune enrollment tests but is enrolled in Intune'
    Ninja-Property-Set $EnrollmentStatusCustomField 1
} else {
    Write-Error 'Device does not meet all Intune enrollment tests and is not enrolled in Intune'
    Ninja-Property-Set $EnrollmentStatusCustomField 0
}
# Log last sync attempt to NinjaOne
if ($LogLastSyncAttempt) {
    $SelectedSyncResultLog = $null
    $OMADMResultEvents = @()
    foreach ($LogName in $SyncResultLogNames) {
        if (-not (Get-WinEvent -ListLog $LogName -ErrorAction SilentlyContinue)) {
            Write-Debug ('Sync result log not present: {0}' -f $LogName)
            continue
        }

        $CandidateEvents = @()
        try {
            # Primary query path.
            $CandidateEvents = @(
                Get-WinEvent -FilterHashtable @{ LogName = $LogName; ID = $SyncResultEventId } -ErrorAction Stop |
                    Sort-Object -Property TimeCreated -Descending
            )
        } catch {
            if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') {
                Write-Warning ('Unable to query Intune sync result events in log ''{0}'' with FilterHashtable: {1}' -f $LogName, $_.Exception.Message)
            }
        }

        if ($CandidateEvents.Count -eq 0) {
            try {
                # Fallback query path for channels where FilterHashtable can be inconsistent.
                $CandidateEvents = @(
                    Get-WinEvent -LogName $LogName -ErrorAction Stop |
                        Where-Object { $_.Id -eq $SyncResultEventId } |
                        Sort-Object -Property TimeCreated -Descending
                )
            } catch {
                Write-Warning ('Unable to query Intune sync result events in log ''{0}'' using fallback query: {1}' -f $LogName, $_.Exception.Message)
            }
        }

        if ($CandidateEvents.Count -gt 0) {
            $SelectedSyncResultLog = $LogName
            $OMADMResultEvents = $CandidateEvents
            break
        }
    }

    if ($SelectedSyncResultLog) {
        Write-Debug ('Selected sync result log: {0}' -f $SelectedSyncResultLog)
        Write-Debug ('Found {0} sync result events with ID {1}' -f $OMADMResultEvents.Count, $SyncResultEventId)
    } else {
        Write-Warning ('No Intune sync result events with ID {0} were found in configured logs: {1}' -f $SyncResultEventId, ($SyncResultLogNames -join ', '))
    }

    if ($OMADMResultEvents.Count -gt 0) {
        $LastSyncDateTime = $OMADMResultEvents | Select-Object -First 1 -ExpandProperty TimeCreated
        $UnixEpochStart = Get-Date -Date '1970-01-01'
        $LastSyncUnixTimestamp = [uint64][Math]::Floor((New-TimeSpan -Start $UnixEpochStart -End $LastSyncDateTime).TotalSeconds)
        Ninja-Property-Set $LastSyncAttemptCustomField $LastSyncUnixTimestamp
    }
    if ($LogLastSyncStatus) {
        if ($OMADMResultEvents.Count -eq 0) {
            Ninja-Property-Set $SyncStatusCustomField 'NoData'
        } elseif (($OMADMResultEvents | Select-Object -First 1 -ExpandProperty Message) -Like '*The operation completed successfully*') {
            Ninja-Property-Set $SyncStatusCustomField 'OK'
        } else {
            Ninja-Property-Set $SyncStatusCustomField 'Error'
        }
    }
}
