#Requires -Version 5.1

<#
.SYNOPSIS
Shows a Windows toast notification when system uptime exceeds a threshold.

.DESCRIPTION
Reads the system boot time from Win32_OperatingSystem, calculates uptime,
and displays a native Windows toast if uptime is greater than or equal to
the configured threshold (default: 7 days).

.PARAMETER ThresholdDays
Number of days uptime must meet or exceed before a toast is shown.

.PARAMETER ToastTitle
Toast title text.

.PARAMETER ToastMessagePrefix
Prefix for toast body text. The script appends current uptime details.

.PARAMETER RebootDeadlineHours
Maximum hours before an enforced reboot is scheduled.

.PARAMETER EnforceRebootDeadline
When true, creates/updates a scheduled task to reboot within RebootDeadlineHours.

.PARAMETER AllowInteractiveScheduling
When true, and if running in an interactive user session, prompts the user to
schedule an earlier reboot time.

.PARAMETER RunMode
Auto: normal detection/notification flow.
CleanupOnly: only remove the reboot deadline task and exit.

.PARAMETER CleanupWhenBelowThreshold
When true, removes the reboot deadline task when uptime is below threshold.

.PARAMETER DryRun
When true, logs intended actions without creating/removing tasks, showing toasts,
or prompting users.

.NOTES
NinjaOne script variable mapping (name -> expected type):
	- thresholdDays -> Integer (default: 7)
	- toastTitle -> String (default: Restart Recommended)
	- toastMessagePrefix -> String (default: This device has been online for longer than the recommended uptime window.)
	- rebootDeadlineHours -> Integer (default: 24)
	- enforceRebootDeadline -> Checkbox (true/false, default: true)
	- allowInteractiveScheduling -> Checkbox (true/false, default: true)
	- useRunAsUserForUserExperience -> Checkbox (true/false, default: true)
	- bypassDoNotDisturb -> Checkbox (true/false, default: true)
	- interactivePromptTimeoutSeconds -> Integer (default: 120)
	- brandName -> String (default: IT Support)
	- brandSupportText -> String (default: Need help? Contact your IT Service Desk.)
	- brandSupportLabels -> String (default: Portal,Email,Phone)
	  Example: Portal,Email,Phone
	- brandSupportLinks -> String (default: ,,)
	  Example: https://portal.example.com,helpdesk@example.com,+44 20 9000 7097
	  Leave positions empty with commas when needed, for example: https://portal.example.com,,+44 20 9000 7097
	- brandAccentHex -> String (default: 0063B1)
	- rebootTaskName -> String (default: Uptime-Reboot-Deadline)
	- runMode -> Dropdown (Auto | CleanupOnly, default: Auto)
	- cleanupWhenBelowThreshold -> Checkbox (true/false, default: true)
	- logEffectiveConfiguration -> Checkbox (true/false, default: true)
	- dryRun -> Checkbox (true/false, default: false)

NinjaOne custom fields written by this script (when available):
	- lastUptimeRebootPrompt -> Date/Time
	- lastUptimePromptUserAction -> Dropdown (Rebooted | Scheduled Reboot | Ignored)
	- lastUptimeRebootDeadline -> Date/Time
	- uptimeRebootPolicyState -> Dropdown (Below Threshold | Threshold Exceeded | Prompt Shown | Deadline Scheduled | Cleanup Completed)
#>

[CmdletBinding()]
param(
	[ValidateRange(1, 365)]
	[int]$ThresholdDays = $(if ($env:thresholdDays) { [int]$env:thresholdDays } else { 7 }),

	[string]$ToastTitle = $(if ($env:toastTitle) { $env:toastTitle } else { 'Restart Recommended' }),

	[string]$ToastMessagePrefix = $(if ($env:toastMessagePrefix) { $env:toastMessagePrefix } else { 'Reboot scheduled to preserve system security and stability.' }),

	[ValidateRange(1, 168)]
	[int]$RebootDeadlineHours = $(if ($env:rebootDeadlineHours) { [int]$env:rebootDeadlineHours } else { 24 }),

	[bool]$EnforceRebootDeadline = $(if ($env:enforceRebootDeadline) { [Convert]::ToBoolean($env:enforceRebootDeadline) } else { $true }),

	[bool]$AllowInteractiveScheduling = $(if ($env:allowInteractiveScheduling) { [Convert]::ToBoolean($env:allowInteractiveScheduling) } else { $true }),

	[bool]$UseRunAsUserForUserExperience = $(if ($env:useRunAsUserForUserExperience) { [Convert]::ToBoolean($env:useRunAsUserForUserExperience) } else { $true }),

	[bool]$BypassDoNotDisturb = $(if ($env:bypassDoNotDisturb) { [Convert]::ToBoolean($env:bypassDoNotDisturb) } else { $true }),

	[ValidateRange(15, 900)]
	[int]$InteractivePromptTimeoutSeconds = $(if ($env:interactivePromptTimeoutSeconds) { [int]$env:interactivePromptTimeoutSeconds } else { 120 }),

	[string]$BrandName = $(if ($env:brandName) { $env:brandName } else { 'IT Support' }),

	[string]$BrandSupportText = $(if ($env:brandSupportText) { $env:brandSupportText } else { 'Need help? Contact your IT Service Desk.' }),

	[string]$BrandSupportLabels = $(if ($env:brandSupportLabels) { $env:brandSupportLabels } else { 'Portal,Email,Phone' }),

	[string]$BrandSupportLinks = $(if ($env:brandSupportLinks) { $env:brandSupportLinks } else { ',,' }),

	[string]$BrandAccentHex = $(if ($env:brandAccentHex) { $env:brandAccentHex } else { '0063B1' }),

	[string]$RebootTaskName = $(if ($env:rebootTaskName) { $env:rebootTaskName } else { 'Uptime-Reboot-Deadline' }),

	[ValidateSet('Auto', 'CleanupOnly')]
	[string]$RunMode = $(if ($env:runMode) { $env:runMode } else { 'Auto' }),

	[bool]$CleanupWhenBelowThreshold = $(if ($env:cleanupWhenBelowThreshold) { [Convert]::ToBoolean($env:cleanupWhenBelowThreshold) } else { $true }),

	[bool]$LogEffectiveConfiguration = $(if ($env:logEffectiveConfiguration) { [Convert]::ToBoolean($env:logEffectiveConfiguration) } else { $true }),

	[bool]$DryRun = $(if ($env:dryRun) { [Convert]::ToBoolean($env:dryRun) } else { $false })
)

function Write-Log {
	param(
		[Parameter(Mandatory)]
		[ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR', 'ALERT')]
		[string]$Level,

		[Parameter(Mandatory)]
		[string]$Message
	)

	Write-Host "[$Level] $Message"
}

function Test-IsSystemContext {
	try {
		$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
		return ($currentIdentity.IsSystem -or $currentIdentity.Name -like 'NT AUTHORITY\*')
	}
	catch {
		return $false
	}
}

function Install-RunAsUserModule {
	if (Get-Module -ListAvailable -Name RunAsUser) {
		return $true
	}

	if ($DryRun) {
		Write-Log -Level 'INFO' -Message '[DRY RUN] RunAsUser module not found. Would attempt machine-scope installation (PSResourceGet, then PackageManagement).'
		return $false
	}

	$installed = $false

	if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
		try {
			Write-Log -Level 'INFO' -Message 'RunAsUser module not found. Attempting install via PSResourceGet (AllUsers scope).'
			Install-PSResource -Name RunAsUser -Repository PSGallery -Scope AllUsers -TrustRepository -Quiet -AcceptLicense -ErrorAction Stop
			$installed = $true
			Write-Log -Level 'SUCCESS' -Message 'Installed RunAsUser via PSResourceGet.'
		}
		catch {
			Write-Log -Level 'WARNING' -Message "PSResourceGet install failed for RunAsUser: $($_.Exception.Message)"
		}
	}

	if (-not $installed -and (Get-Command Install-Module -ErrorAction SilentlyContinue)) {
		try {
			Write-Log -Level 'INFO' -Message 'Attempting RunAsUser install via PackageManagement/PowerShellGet fallback (AllUsers scope).'

			if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
				Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope AllUsers -ErrorAction SilentlyContinue | Out-Null
			}

			if (Get-Command Set-PSRepository -ErrorAction SilentlyContinue) {
				Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
			}

			Install-Module -Name RunAsUser -Repository PSGallery -Scope AllUsers -Force -AllowClobber -ErrorAction Stop
			$installed = $true
			Write-Log -Level 'SUCCESS' -Message 'Installed RunAsUser via PackageManagement fallback.'
		}
		catch {
			Write-Log -Level 'WARNING' -Message "PackageManagement fallback install failed for RunAsUser: $($_.Exception.Message)"
		}
	}

	if (-not $installed) {
		Write-Log -Level 'WARNING' -Message 'RunAsUser module installation was not successful. User-context UX features may be skipped.'
	}

	return [bool](Get-Module -ListAvailable -Name RunAsUser)
}

function Test-RunAsUserAvailable {
	if (-not $UseRunAsUserForUserExperience) {
		return $false
	}

	if ($null -ne $script:RunAsUserAvailable) {
		return [bool]$script:RunAsUserAvailable
	}

	try {
		if (-not (Get-Module -ListAvailable -Name RunAsUser)) {
			$null = Install-RunAsUserModule
		}

		$script:RunAsUserAvailable = ($null -ne (Get-Command Invoke-AsCurrentUser -ErrorAction SilentlyContinue))
		if (-not $script:RunAsUserAvailable) {
			Import-Module RunAsUser -ErrorAction Stop
			$script:RunAsUserAvailable = ($null -ne (Get-Command Invoke-AsCurrentUser -ErrorAction SilentlyContinue))
		}
	}
	catch {
		$script:RunAsUserAvailable = $false
	}

	return [bool]$script:RunAsUserAvailable
}

function Invoke-RunAsUserScript {
	param(
		[Parameter(Mandatory)]
		[string]$ScriptText,

		[switch]$CaptureOutput
	)

	if (-not (Test-RunAsUserAvailable)) {
		Write-Log -Level 'INFO' -Message 'RunAsUser is not available in this session.'
		return $null
	}

	try {
		$invokeParams = @{
			ScriptBlock = [scriptblock]::Create($ScriptText)
			CacheToDisk = $true
		}

		if ($CaptureOutput) {
			$invokeParams.CaptureOutput = $true
		}

		return (Invoke-AsCurrentUser @invokeParams)
	}
	catch {
		Write-Log -Level 'WARNING' -Message "User-context script execution failed: $($_.Exception.Message)"
		return $null
	}
}

function Get-NormalizedCsvSupportConfiguration {
	param(
		[Parameter(Mandatory)]
		[string]$LabelsCsv,

		[Parameter(Mandatory)]
		[string]$LinksCsv
	)

	$defaultLabels = @('Portal', 'Email', 'Phone')
	$labelParts = @($LabelsCsv.Split(',', [System.StringSplitOptions]::None))
	while ($labelParts.Count -lt 3) {
		$labelParts += ''
	}

	$linkParts = @($LinksCsv.Split(',', [System.StringSplitOptions]::None))
	while ($linkParts.Count -lt 3) {
		$linkParts += ''
	}

	$normalizedLabels = @()
	for ($i = 0; $i -lt 3; $i++) {
		$label = $labelParts[$i]
		if ([string]::IsNullOrWhiteSpace($label)) {
			$normalizedLabels += $defaultLabels[$i]
		}
		else {
			$normalizedLabels += $label.Trim()
		}
	}

	$normalizedLinks = @()
	for ($i = 0; $i -lt 3; $i++) {
		if ($i -lt $linkParts.Count) {
			$normalizedLinks += $linkParts[$i].Trim()
		}
		else {
			$normalizedLinks += ''
		}
	}

	$maskedLinkSummary = @(
		"PortalSet=$(-not [string]::IsNullOrWhiteSpace($normalizedLinks[0]))",
		"EmailSet=$(-not [string]::IsNullOrWhiteSpace($normalizedLinks[1]))",
		"PhoneSet=$(-not [string]::IsNullOrWhiteSpace($normalizedLinks[2]))"
	) -join '; '

	return [pscustomobject]@{
		LabelsCsv = ($normalizedLabels -join ',')
		LinksCsv = ($normalizedLinks -join ',')
		MaskedLinkSummary = $maskedLinkSummary
	}
}

function Test-InteractiveUserSession {
	try {
		$currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
		if ($currentIdentity -like 'NT AUTHORITY\*') {
			return $false
		}

		return [Environment]::UserInteractive
	}
	catch {
		return $false
	}
}

function Set-NinjaOnePropertyValue {
	param(
		[Parameter(Mandatory)]
		[string]$Name,

		[Parameter(Mandatory)]
		[string]$Value,

		[ValidateSet('Text', 'Dropdown', 'Date', 'DateTime', 'Number', 'Checkbox')]
		[string]$Type
	)

	if ($DryRun) {
		Write-Log -Level 'INFO' -Message "[DRY RUN] Would set Ninja property '$Name' to '$Value'."
		return $true
	}

	try {
		if (Get-Command Set-NinjaProperty -ErrorAction SilentlyContinue) {
			try {
				if ($Type) {
					Set-NinjaProperty -Name $Name -Value $Value -Type $Type -ErrorAction Stop
				}
				else {
					Set-NinjaProperty -Name $Name -Value $Value -ErrorAction Stop
				}
				return $true
			}
			catch {
				if ($Type) {
					Set-NinjaProperty $Name $Value $Type -ErrorAction Stop
				}
				else {
					Set-NinjaProperty $Name $Value -ErrorAction Stop
				}
				return $true
			}
		}

		if (Get-Command Ninja-Property-Set -ErrorAction SilentlyContinue) {
			& Ninja-Property-Set $Name $Value
			return $true
		}

		Write-Log -Level 'INFO' -Message "Ninja property command not available. Could not write '$Name'."
		return $false
	}
	catch {
		Write-Log -Level 'WARNING' -Message "Failed to set Ninja property '$Name': $($_.Exception.Message)"
		return $false
	}
}

function Write-NinjaPromptReport {
	param(
		[Parameter(Mandatory)]
		[ValidateSet('Rebooted', 'Scheduled Reboot', 'Ignored')]
		[string]$UserAction
	)

	$promptTimestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
	$null = Set-NinjaOnePropertyValue -Name 'lastUptimeRebootPrompt' -Value $promptTimestamp -Type 'DateTime'
	$null = Set-NinjaOnePropertyValue -Name 'lastUptimePromptUserAction' -Value $UserAction -Type 'Dropdown'
}

function Write-NinjaDeadlineReport {
	param(
		[Parameter(Mandatory)]
		[datetime]$Deadline
	)

	$deadlineText = $Deadline.ToString('yyyy-MM-dd HH:mm:ss')
	$null = Set-NinjaOnePropertyValue -Name 'lastUptimeRebootDeadline' -Value $deadlineText -Type 'DateTime'
}

function Write-NinjaPolicyState {
	param(
		[Parameter(Mandatory)]
		[ValidateSet('Below Threshold', 'Threshold Exceeded', 'Prompt Shown', 'Deadline Scheduled', 'Cleanup Completed')]
		[string]$PolicyState
	)

	$null = Set-NinjaOnePropertyValue -Name 'uptimeRebootPolicyState' -Value $PolicyState -Type 'Dropdown'
}

function Get-SystemUptime {
	try {
		$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
		$lastBootRaw = $os.LastBootUpTime
		$lastBoot = $null

		if ($lastBootRaw -is [datetime]) {
			$lastBoot = [datetime]$lastBootRaw
		}
		elseif ($lastBootRaw -is [string]) {
			# Some hosts return DMTF, others return a normal date string.
			if ($lastBootRaw -match '^\d{14}\.\d{6}[\+\-]\d{3}$') {
				$lastBoot = [Management.ManagementDateTimeConverter]::ToDateTime($lastBootRaw)
			}
			else {
				$parsedBoot = [datetime]::MinValue
				if ([datetime]::TryParse($lastBootRaw, [ref]$parsedBoot)) {
					$lastBoot = $parsedBoot
				}
			}
		}

		if ($null -eq $lastBoot) {
			$wmiOs = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
			$lastBoot = [Management.ManagementDateTimeConverter]::ToDateTime($wmiOs.LastBootUpTime)
		}

		if ($lastBoot -gt (Get-Date)) {
			throw 'Resolved last boot time is in the future.'
		}

		$uptime = (Get-Date) - $lastBoot

		return [pscustomobject]@{
			LastBootTime = $lastBoot
			Uptime = $uptime
		}
	}
	catch {
		throw "Failed to retrieve uptime information: $($_.Exception.Message)"
	}
}

function Set-RebootDeadlineTask {
	param(
		[Parameter(Mandatory)]
		[datetime]$RunAt,

		[Parameter(Mandatory)]
		[string]$TaskName
	)

	try {
		if (-not (Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
			Write-Log -Level 'WARNING' -Message 'ScheduledTasks cmdlets are unavailable. Could not schedule reboot task.'
			return $false
		}

		$action = New-ScheduledTaskAction -Execute 'shutdown.exe' -Argument '/r /f /t 60 /c "Scheduled restart: uptime threshold exceeded."'
		$trigger = New-ScheduledTaskTrigger -Once -At $RunAt
		$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest -LogonType ServiceAccount
		$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
		$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings

		Register-ScheduledTask -TaskName $TaskName -InputObject $task -Force | Out-Null
		return $true
	}
	catch {
		Write-Log -Level 'WARNING' -Message "Failed to register reboot task '$TaskName': $($_.Exception.Message)"
		return $false
	}
}

function Remove-RebootDeadlineTask {
	param(
		[Parameter(Mandatory)]
		[string]$TaskName
	)

	try {
		if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) -or -not (Get-Command Unregister-ScheduledTask -ErrorAction SilentlyContinue)) {
			Write-Log -Level 'WARNING' -Message 'ScheduledTasks cmdlets are unavailable. Could not remove reboot task.'
			return $false
		}

		$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
		if ($null -eq $existing) {
			Write-Log -Level 'INFO' -Message "No existing reboot task '$TaskName' found to remove."
			return $true
		}

		Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
		Write-Log -Level 'SUCCESS' -Message "Removed reboot task '$TaskName'."
		return $true
	}
	catch {
		Write-Log -Level 'WARNING' -Message "Failed to remove reboot task '$TaskName': $($_.Exception.Message)"
		return $false
	}
}

function Write-EffectiveConfiguration {
	$interactiveSession = Test-InteractiveUserSession
	Write-Log -Level 'INFO' -Message 'Effective configuration:'
	Write-Log -Level 'INFO' -Message "  - RunMode: $RunMode"
	Write-Log -Level 'INFO' -Message "  - ThresholdDays: $ThresholdDays"
	Write-Log -Level 'INFO' -Message "  - RebootDeadlineHours: $RebootDeadlineHours"
	Write-Log -Level 'INFO' -Message "  - EnforceRebootDeadline: $EnforceRebootDeadline"
	Write-Log -Level 'INFO' -Message "  - AllowInteractiveScheduling: $AllowInteractiveScheduling"
	Write-Log -Level 'INFO' -Message "  - UseRunAsUserForUserExperience: $UseRunAsUserForUserExperience"
	Write-Log -Level 'INFO' -Message "  - BypassDoNotDisturb: $BypassDoNotDisturb"
	Write-Log -Level 'INFO' -Message "  - InteractivePromptTimeoutSeconds: $InteractivePromptTimeoutSeconds"
	Write-Log -Level 'INFO' -Message "  - BrandName: $BrandName"
	Write-Log -Level 'INFO' -Message "  - BrandSupportText: $BrandSupportText"
	Write-Log -Level 'INFO' -Message "  - BrandSupportLabels: $script:NormalizedSupportLabels"
	Write-Log -Level 'INFO' -Message "  - BrandSupportLinks: $script:MaskedSupportLinks"
	Write-Log -Level 'INFO' -Message "  - BrandAccentHex: $BrandAccentHex"
	Write-Log -Level 'INFO' -Message "  - InteractiveSessionDetected: $interactiveSession"
	Write-Log -Level 'INFO' -Message "  - RebootTaskName: $RebootTaskName"
	Write-Log -Level 'INFO' -Message "  - CleanupWhenBelowThreshold: $CleanupWhenBelowThreshold"
	Write-Log -Level 'INFO' -Message "  - DryRun: $DryRun"
}

function Get-InteractiveRebootChoiceHours {
	param(
		[Parameter(Mandatory)]
		[int]$MaxHours,

		[Parameter(Mandatory)]
		[datetime]$CurrentScheduleAt
	)

	try {
		if (Test-IsSystemContext -and (Test-RunAsUserAvailable)) {
			$promptScriptText = @"
`$MaxHoursInner = $MaxHours
`$TimeoutSeconds = $InteractivePromptTimeoutSeconds
`$CurrentScheduleAtText = @'
$($CurrentScheduleAt.ToString('yyyy-MM-dd HH:mm'))
'@
`$BrandName = @'
$BrandName
'@
`$BrandSupportText = @'
$BrandSupportText
'@
`$BrandSupportLabels = @'
$script:NormalizedSupportLabels
'@
`$BrandSupportLinks = @'
$script:NormalizedSupportLinks
'@
`$BrandAccentHex = @'
$BrandAccentHex
'@
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

`$accentHex = (`$BrandAccentHex -replace '[^0-9A-Fa-f]', '')
if (`$accentHex.Length -ne 6) { `$accentHex = '0063B1' }
`$accentColor = [System.Drawing.Color]::FromArgb(
	[Convert]::ToInt32(`$accentHex.Substring(0, 2), 16),
	[Convert]::ToInt32(`$accentHex.Substring(2, 2), 16),
	[Convert]::ToInt32(`$accentHex.Substring(4, 2), 16)
)

function Get-LinearChannel(`$value) {
	if (`$value -le 10) { return (`$value / 3294.6) }
	return [Math]::Pow(((`$value / 255.0) + 0.055) / 1.055, 2.4)
}

function Get-RelativeLuminance([System.Drawing.Color]`$color) {
	`$r = Get-LinearChannel `$color.R
	`$g = Get-LinearChannel `$color.G
	`$b = Get-LinearChannel `$color.B
	return (0.2126 * `$r) + (0.7152 * `$g) + (0.0722 * `$b)
}

function Get-ContrastRatio([System.Drawing.Color]`$a, [System.Drawing.Color]`$b) {
	`$l1 = Get-RelativeLuminance `$a
	`$l2 = Get-RelativeLuminance `$b
	`$light = [Math]::Max(`$l1, `$l2)
	`$dark = [Math]::Min(`$l1, `$l2)
	return (`$light + 0.05) / (`$dark + 0.05)
}

`$white = [System.Drawing.Color]::White
`$darkText = [System.Drawing.Color]::FromArgb(32, 32, 32)
`$accentForegroundColor = if ((Get-ContrastRatio `$accentColor `$white) -ge (Get-ContrastRatio `$accentColor `$darkText)) { `$white } else { `$darkText }

`$form = New-Object System.Windows.Forms.Form
`$form.Text = 'Restart Required'
`$form.Width = 560
`$form.Height = 372
`$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
`$form.TopMost = `$true
`$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
`$form.MaximizeBox = `$false
`$form.MinimizeBox = `$false
`$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)
`$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

`$headerPanel = New-Object System.Windows.Forms.Panel
`$headerPanel.Left = 0
`$headerPanel.Top = 0
`$headerPanel.Width = `$form.ClientSize.Width
`$headerPanel.Height = 56
`$headerPanel.BackColor = `$accentColor
`$form.Controls.Add(`$headerPanel)

`$brandLabel = New-Object System.Windows.Forms.Label
`$brandLabel.AutoSize = `$false
`$brandLabel.Left = 16
`$brandLabel.Top = 17
`$brandLabel.Width = 525
`$brandLabel.Height = 22
`$brandLabel.ForeColor = `$accentForegroundColor
`$brandLabel.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
`$brandLabel.Text = `$BrandName
`$headerPanel.Controls.Add(`$brandLabel)

`$cardPanel = New-Object System.Windows.Forms.Panel
`$cardPanel.Left = 16
`$cardPanel.Top = 68
`$cardPanel.Width = 528
`$cardPanel.Height = 264
`$cardPanel.BackColor = [System.Drawing.Color]::White
`$cardPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::None
`$form.Controls.Add(`$cardPanel)

`$heading = New-Object System.Windows.Forms.Label
`$heading.AutoSize = `$false
`$heading.Left = 16
`$heading.Top = 14
`$heading.Width = 492
`$heading.Height = 24
`$heading.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
`$heading.Text = 'A restart is required to complete maintenance updates'
`$cardPanel.Controls.Add(`$heading)

`$label = New-Object System.Windows.Forms.Label
`$label.AutoSize = `$false
`$label.Width = 492
`$label.Height = 76
`$label.Left = 16
`$label.Top = 46
`$label.Text = "To keep your device secure and up to date, a restart is required within `$MaxHoursInner hours.`r`nCurrent scheduled restart: `$CurrentScheduleAtText.`r`nChoose when to restart below. If you do nothing, this schedule remains in place.`r`nThis prompt closes automatically after `$TimeoutSeconds seconds."
`$cardPanel.Controls.Add(`$label)

`$hoursLabel = New-Object System.Windows.Forms.Label
`$hoursLabel.Text = 'Hours from now:'
`$hoursLabel.Left = 16
`$hoursLabel.Top = 130
`$hoursLabel.Width = 100
`$cardPanel.Controls.Add(`$hoursLabel)

`$hoursBoxContainer = New-Object System.Windows.Forms.Panel
`$hoursBoxContainer.Left = 120
`$hoursBoxContainer.Top = 125
`$hoursBoxContainer.Width = 88
`$hoursBoxContainer.Height = 28
`$hoursBoxContainer.BackColor = [System.Drawing.Color]::White
`$cardPanel.Controls.Add(`$hoursBoxContainer)

`$hoursUnderline = New-Object System.Windows.Forms.Panel
`$hoursUnderline.Left = 0
`$hoursUnderline.Top = 26
`$hoursUnderline.Width = 88
`$hoursUnderline.Height = 1
`$hoursUnderline.BackColor = [System.Drawing.Color]::FromArgb(203, 210, 220)
`$hoursBoxContainer.Controls.Add(`$hoursUnderline)

`$hoursBox = New-Object System.Windows.Forms.TextBox
`$hoursBox.Left = 10
`$hoursBox.Top = 4
`$hoursBox.Width = 70
`$hoursBox.Text = '4'
`$hoursBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
`$hoursBox.BackColor = [System.Drawing.Color]::White
`$hoursBoxContainer.Controls.Add(`$hoursBox)

`$buttonNow = New-Object System.Windows.Forms.Button
`$buttonNow.Text = 'Restart in 2 mins'
`$buttonNow.Left = 16
`$buttonNow.Top = 162
`$buttonNow.Width = 130
`$buttonNow.Height = 30
`$buttonNow.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
`$buttonNow.BackColor = `$accentColor
`$buttonNow.ForeColor = `$accentForegroundColor
`$buttonNow.FlatAppearance.BorderSize = 0
`$cardPanel.Controls.Add(`$buttonNow)

`$buttonSchedule = New-Object System.Windows.Forms.Button
`$buttonSchedule.Text = 'Set Restart Time'
`$buttonSchedule.Left = 156
`$buttonSchedule.Top = 162
`$buttonSchedule.Width = 130
`$buttonSchedule.Height = 30
`$buttonSchedule.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
`$buttonSchedule.BackColor = `$accentColor
`$buttonSchedule.ForeColor = `$accentForegroundColor
`$buttonSchedule.FlatAppearance.BorderSize = 0
`$cardPanel.Controls.Add(`$buttonSchedule)

`$buttonSkip = New-Object System.Windows.Forms.Button
`$buttonSkip.Text = 'Keep Current Schedule'
`$buttonSkip.Left = 296
`$buttonSkip.Top = 162
`$buttonSkip.Width = 170
`$buttonSkip.Height = 30
`$buttonSkip.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
`$buttonSkip.BackColor = [System.Drawing.Color]::FromArgb(237, 241, 247)
`$buttonSkip.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
`$buttonSkip.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(206, 214, 224)
`$cardPanel.Controls.Add(`$buttonSkip)

`$supportLabel = New-Object System.Windows.Forms.Label
`$supportLabel.AutoSize = `$true
`$supportLabel.Left = 16
`$supportLabel.Top = 198
`$supportLabel.MaximumSize = New-Object System.Drawing.Size(492, 0)
`$supportLabel.ForeColor = [System.Drawing.Color]::FromArgb(88, 95, 105)
`$supportLabel.Text = `$BrandSupportText
`$cardPanel.Controls.Add(`$supportLabel)

`$nextSupportTop = `$supportLabel.Top + `$supportLabel.Height + 4
`$supportContentBottom = `$supportLabel.Bottom
`$labelParts = @((`$BrandSupportLabels -split ','))
`$linkParts = @((`$BrandSupportLinks -split ','))

`$portalLabel = if (`$labelParts.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace(`$labelParts[0])) { `$labelParts[0].Trim() } else { 'Portal' }
`$emailLabel = if (`$labelParts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace(`$labelParts[1])) { `$labelParts[1].Trim() } else { 'Email' }
`$phoneLabel = if (`$labelParts.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace(`$labelParts[2])) { `$labelParts[2].Trim() } else { 'Phone' }

`$cleanSupportUrl = if (`$linkParts.Count -ge 1) { `$linkParts[0].Trim() } else { '' }
`$cleanSupportEmail = if (`$linkParts.Count -ge 2) { `$linkParts[1].Trim() } else { '' }
`$cleanSupportPhone = if (`$linkParts.Count -ge 3) { `$linkParts[2].Trim() } else { '' }
`$telTarget = (`$cleanSupportPhone -replace '[^0-9\+\*\#\,\;]', '')

if (-not [string]::IsNullOrWhiteSpace(`$cleanSupportEmail) -or -not [string]::IsNullOrWhiteSpace(`$telTarget) -or -not [string]::IsNullOrWhiteSpace(`$cleanSupportUrl)) {
	`$linksIntro = New-Object System.Windows.Forms.Label
	`$linksIntro.AutoSize = `$true
	`$linksIntro.Left = 16
	`$linksIntro.Top = `$nextSupportTop
	`$linksIntro.ForeColor = [System.Drawing.Color]::FromArgb(88, 95, 105)
	`$linksIntro.Text = 'Contact method:'
	`$cardPanel.Controls.Add(`$linksIntro)

	`$contactDropdown = New-Object System.Windows.Forms.ComboBox
	`$contactDropdown.Left = 16
	`$contactDropdown.Top = `$linksIntro.Top + `$linksIntro.Height + 4
	`$contactDropdown.Width = 372
	`$contactDropdown.Height = 28
	`$contactDropdown.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
	`$contactDropdown.BackColor = [System.Drawing.Color]::White
	`$contactDropdown.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
	`$cardPanel.Controls.Add(`$contactDropdown)

	if (-not [string]::IsNullOrWhiteSpace(`$cleanSupportUrl)) {
		[void]`$contactDropdown.Items.Add([pscustomobject]@{ Label = `$portalLabel + ': ' + `$cleanSupportUrl; Target = `$cleanSupportUrl; ErrorMessage = 'Unable to open the support link from this session.' })
	}

	if (-not [string]::IsNullOrWhiteSpace(`$cleanSupportEmail)) {
		[void]`$contactDropdown.Items.Add([pscustomobject]@{ Label = `$emailLabel + ': ' + `$cleanSupportEmail; Target = 'mailto:' + `$cleanSupportEmail; ErrorMessage = 'Unable to open your email client from this session.' })
	}

	if (-not [string]::IsNullOrWhiteSpace(`$telTarget)) {
		[void]`$contactDropdown.Items.Add([pscustomobject]@{ Label = `$phoneLabel + ': ' + `$cleanSupportPhone; Target = 'tel:' + `$telTarget; ErrorMessage = 'Unable to open a calling app from this session.' })
	}

	`$contactDropdown.DisplayMember = 'Label'
	if (`$contactDropdown.Items.Count -gt 0) {
		`$contactDropdown.SelectedIndex = 0
	}

	`$openContactButton = New-Object System.Windows.Forms.Button
	`$openContactButton.Text = 'Open'
	`$openContactButton.Left = 396
	`$openContactButton.Top = `$contactDropdown.Top - 1
	`$openContactButton.Width = 112
	`$openContactButton.Height = 30
	`$openContactButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
	`$openContactButton.BackColor = [System.Drawing.Color]::FromArgb(237, 241, 247)
	`$openContactButton.ForeColor = [System.Drawing.Color]::FromArgb(32, 32, 32)
	`$openContactButton.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(206, 214, 224)
	`$openContactButton.Add_Click({
		if (`$contactDropdown.SelectedItem -eq `$null) { return }
		try {
			`$selected = [pscustomobject]`$contactDropdown.SelectedItem
			`$psi = New-Object System.Diagnostics.ProcessStartInfo
			`$psi.FileName = [string]`$selected.Target
			`$psi.UseShellExecute = `$true
			[System.Diagnostics.Process]::Start(`$psi) | Out-Null
		}
		catch {
			`$errorText = 'Unable to open the selected contact option from this session.'
			if (`$contactDropdown.SelectedItem -ne `$null -and `$contactDropdown.SelectedItem.PSObject.Properties.Match('ErrorMessage').Count -gt 0) {
				`$errorText = [string]`$contactDropdown.SelectedItem.ErrorMessage
			}
			[System.Windows.Forms.MessageBox]::Show(`$errorText, 'Device Maintenance Notice', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
		}
	})
	`$cardPanel.Controls.Add(`$openContactButton)
	`$supportContentBottom = `$openContactButton.Bottom
}

`$requiredCardHeight = `$supportContentBottom + 16
if (`$requiredCardHeight -gt `$cardPanel.Height) {
	`$heightDelta = `$requiredCardHeight - `$cardPanel.Height
	`$cardPanel.Height = `$requiredCardHeight
	`$form.Height = `$form.Height + `$heightDelta
}

`$form.AcceptButton = `$buttonSchedule
`$form.CancelButton = `$buttonSkip

`$timer = New-Object System.Windows.Forms.Timer
`$timer.Interval = `$TimeoutSeconds * 1000
`$timer.Add_Tick({
	`$timer.Stop()
	`$form.Tag = ''
	`$form.Close()
})

`$buttonNow.Add_Click({
	`$form.Tag = '0'
	`$form.Close()
})

`$buttonSchedule.Add_Click({
	`$hoursLocal = 0
	if ([int]::TryParse(`$hoursBox.Text, [ref]`$hoursLocal) -and `$hoursLocal -ge 1 -and `$hoursLocal -le `$MaxHoursInner) {
		`$form.Tag = [string]`$hoursLocal
		`$form.Close()
		return
	}
	[System.Windows.Forms.MessageBox]::Show("Please enter a whole number between 1 and `$MaxHoursInner.", 'Device Maintenance Notice', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
})

`$buttonSkip.Add_Click({
	`$form.Tag = ''
	`$form.Close()
})

`$timer.Start()
[void]`$form.ShowDialog()
`$timer.Stop()
return [string]`$form.Tag
"@
			$userChoice = Invoke-RunAsUserScript -ScriptText $promptScriptText -CaptureOutput

			$choiceText = ($userChoice | Out-String).Trim()
			if ([string]::IsNullOrWhiteSpace($choiceText)) {
				return $null
			}

			$hoursParsed = 0
			if ([int]::TryParse($choiceText, [ref]$hoursParsed) -and $hoursParsed -ge 0 -and $hoursParsed -le $MaxHours) {
				return $hoursParsed
			}

			return $null
		}

		Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
		Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction Stop

		$currentScheduleText = $CurrentScheduleAt.ToString('yyyy-MM-dd HH:mm')
		$message = "This device should reboot within $MaxHours hours due to long uptime.`nCurrent scheduled restart: $currentScheduleText`n`nYes = reboot in about 2 minutes`nNo = choose hours from now (1-$MaxHours)`nCancel = keep default schedule"
		$choice = [System.Windows.Forms.MessageBox]::Show(
			$message,
			'Restart Scheduling',
			[System.Windows.Forms.MessageBoxButtons]::YesNoCancel,
			[System.Windows.Forms.MessageBoxIcon]::Information
		)

		switch ($choice) {
			([System.Windows.Forms.DialogResult]::Yes) {
				return 0
			}
			([System.Windows.Forms.DialogResult]::No) {
				$userInput = [Microsoft.VisualBasic.Interaction]::InputBox(
					"Enter the number of hours until reboot (1-$MaxHours):",
					'Restart Scheduling',
					'4'
				)

				if ([string]::IsNullOrWhiteSpace($userInput)) {
					return $null
				}

				$hours = 0
				if ([int]::TryParse($userInput, [ref]$hours) -and $hours -ge 1 -and $hours -le $MaxHours) {
					return $hours
				}

				Write-Log -Level 'WARNING' -Message "Invalid scheduling input '$userInput'. Keeping default reboot deadline."
				return $null
			}
			default {
				return $null
			}
		}
	}
	catch {
		Write-Log -Level 'INFO' -Message 'Interactive scheduling prompt was not available in this session.'
		return $null
	}
}

function Show-UptimeToast {
	param(
		[Parameter(Mandatory)]
		[string]$Title,

		[Parameter(Mandatory)]
		[string]$Message,

		[string]$Detail = '',

		[string]$AppId = 'Microsoft.Windows.Explorer'
	)

	$script:LastToastPath = 'Unknown'
	$script:LastToastReason = ''
	$script:LastToastRawResult = ''

	try {
		if (Test-IsSystemContext -and (Test-RunAsUserAvailable)) {
			$script:LastToastPath = 'RunAsUser'
			$toastScenarioLiteral = if ($BypassDoNotDisturb) { 'alarm' } else { '' }
			$toastScriptText = @"
`$ToastTitle = @'
$Title
'@
`$ToastMessage = @'
$Message
'@
`$ToastDetail = @'
$Detail
'@
`$ToastAppId = @'
$AppId
'@
`$ToastScenario = @'
$toastScenarioLiteral
'@

try {
	Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
	[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
	[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

	function New-ToastNotifier {
		param(
			[string]`$PreferredAppId
		)

		`$attemptErrors = New-Object System.Collections.Generic.List[string]

		`$candidateAppIds = New-Object System.Collections.Generic.List[string]
		if (-not [string]::IsNullOrWhiteSpace(`$PreferredAppId)) {
			`$candidateAppIds.Add(`$PreferredAppId)
		}

		foreach (`$fallbackId in @('Microsoft.Windows.Explorer')) {
			if (-not `$candidateAppIds.Contains(`$fallbackId)) {
				`$candidateAppIds.Add(`$fallbackId)
			}
		}

		foreach (`$appIdCandidate in `$candidateAppIds) {
			try {
				`$notifierByAppId = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(`$appIdCandidate)
				return [pscustomobject]@{ Notifier = `$notifierByAppId; Source = ('AppId:' + `$appIdCandidate) }
			}
			catch {
				`$attemptErrors.Add((`$appIdCandidate + ': ' + [string]`$_.Exception.Message))
			}
		}

		try {
			`$defaultNotifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier()
			return [pscustomobject]@{ Notifier = `$defaultNotifier; Source = 'Default' }
		}
		catch {
			`$attemptErrors.Add(('Default: ' + [string]`$_.Exception.Message))
		}

		throw ('CreateToastNotifier failed. Attempts: ' + (`$attemptErrors -join ' | '))
	}

	`$escapedTitle = [System.Security.SecurityElement]::Escape(`$ToastTitle)
	`$escapedMessage = [System.Security.SecurityElement]::Escape(`$ToastMessage)
	`$escapedDetail = if ([string]::IsNullOrWhiteSpace(`$ToastDetail)) { '' } else { [System.Security.SecurityElement]::Escape(`$ToastDetail.Trim()) }
	`$detailXml = if ([string]::IsNullOrWhiteSpace(`$escapedDetail)) { '' } else { "<text hint-wrap='true' hint-maxLines='2'>`$escapedDetail</text>" }
	if ([string]::IsNullOrWhiteSpace(`$ToastScenario)) {
		`$toastXml = "<toast><visual><binding template='ToastGeneric'><text hint-maxLines='1'>{0}</text><text hint-wrap='true' hint-maxLines='1'>{1}</text>{2}</binding></visual><audio src='ms-winsoundevent:Notification.IM'/></toast>" -f `$escapedTitle, `$escapedMessage, `$detailXml
	}
	else {
		`$toastXml = "<toast scenario='{0}'><visual><binding template='ToastGeneric'><text hint-maxLines='1'>{1}</text><text hint-wrap='true' hint-maxLines='1'>{2}</text>{3}</binding></visual><audio silent='true'/><actions><action content='Dismiss' arguments='dismiss'/></actions></toast>" -f `$ToastScenario, `$escapedTitle, `$escapedMessage, `$detailXml
	}

	`$xmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
	`$xmlDoc.LoadXml(`$toastXml)
	`$toast = [Windows.UI.Notifications.ToastNotification]::new(`$xmlDoc)
	`$notifierResult = New-ToastNotifier -PreferredAppId `$ToastAppId
	`$notifierResult.Notifier.Show(`$toast)
	return ('true::shown via ' + [string]`$notifierResult.Source)
}
catch {
	`$toastError = [string]`$_.Exception.Message
	if ([string]::IsNullOrWhiteSpace(`$toastError)) { `$toastError = 'Unknown user-context toast failure.' }
	`$toastError = `$toastError -replace '[\r\n]+', ' '
	return ('false::' + `$toastError)
}
"@

			$result = Invoke-RunAsUserScript -ScriptText $toastScriptText -CaptureOutput
			$rawResult = ($result | Out-String).Trim()
			$script:LastToastRawResult = $rawResult

			if ([string]::IsNullOrWhiteSpace($rawResult)) {
				$script:LastToastReason = 'No output returned from user-context toast invocation.'
				return $false
			}

			if ($rawResult -like 'true::*' -or $rawResult -eq 'true') {
				if ($rawResult -like 'true::*') {
					$script:LastToastReason = $rawResult.Substring(6)
				}
				else {
					$script:LastToastReason = 'Toast API call completed in user context.'
				}
				return $true
			}

			if ($rawResult -like 'false::*') {
				$script:LastToastReason = $rawResult.Substring(7)
				return $false
			}

			$script:LastToastReason = "Unexpected toast result payload: $rawResult"
			return $false
		}

		$script:LastToastPath = 'CurrentSession'
		Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction SilentlyContinue
		[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
		[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

		$attemptErrors = New-Object System.Collections.Generic.List[string]
		$notifier = $null
		$notifierSource = ''

		$candidateAppIds = @()
		if (-not [string]::IsNullOrWhiteSpace($AppId)) {
			$candidateAppIds += $AppId
		}
		$candidateAppIds += @('Microsoft.Windows.Explorer')
		$candidateAppIds = $candidateAppIds | Select-Object -Unique

		foreach ($appIdCandidate in $candidateAppIds) {
			try {
				$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appIdCandidate)
				$notifierSource = "AppId:$appIdCandidate"
				break
			}
			catch {
				$attemptErrors.Add(("{0}: {1}" -f $appIdCandidate, $_.Exception.Message))
			}
		}

		if ($null -eq $notifier) {
			try {
				$notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier()
				$notifierSource = 'Default'
			}
			catch {
				$attemptErrors.Add('Default: ' + [string]$_.Exception.Message)
			}
		}

		if ($null -eq $notifier) {
			throw ('CreateToastNotifier failed. Attempts: ' + ($attemptErrors -join ' | '))
		}

		$escapedTitle = [System.Security.SecurityElement]::Escape($Title)
		$escapedMessage = [System.Security.SecurityElement]::Escape($Message)
		$escapedDetail = if ([string]::IsNullOrWhiteSpace($Detail)) { '' } else { [System.Security.SecurityElement]::Escape($Detail.Trim()) }
		$detailXmlElement = if ([string]::IsNullOrWhiteSpace($escapedDetail)) { '' } else { "`t  <text hint-wrap='true' hint-maxLines='2'>$escapedDetail</text>" }
 
		if ($BypassDoNotDisturb) {
			$toastXml = @"
<toast scenario='alarm'>
  <visual>
	<binding template='ToastGeneric'>
	  <text hint-maxLines='1'>$escapedTitle</text>
	  <text hint-wrap='true' hint-maxLines='1'>$escapedMessage</text>
$detailXmlElement
	</binding>
  </visual>
	<audio silent='true'/>
  <actions>
	<action content='Dismiss' arguments='dismiss'/>
  </actions>
</toast>
"@
		}
		else {
			$toastXml = @"
<toast>
  <visual>
	<binding template='ToastGeneric'>
	  <text hint-maxLines='1'>$escapedTitle</text>
	  <text hint-wrap='true' hint-maxLines='1'>$escapedMessage</text>
$detailXmlElement
	</binding>
  </visual>
  <audio src='ms-winsoundevent:Notification.IM'/>
</toast>
"@
		}

		$xmlDoc = New-Object Windows.Data.Xml.Dom.XmlDocument
		$xmlDoc.LoadXml($toastXml)

		$toast = [Windows.UI.Notifications.ToastNotification]::new($xmlDoc)
		$notifier.Show($toast)
		$script:LastToastReason = "Toast API call completed in current session via $notifierSource."

		return $true
	}
	catch {
		$script:LastToastReason = $_.Exception.Message
		Write-Log -Level 'WARNING' -Message "Toast display failed: $($_.Exception.Message)"
		return $false
	}
}

try {
	$normalizedSupport = Get-NormalizedCsvSupportConfiguration -LabelsCsv $BrandSupportLabels -LinksCsv $BrandSupportLinks
	$script:NormalizedSupportLabels = $normalizedSupport.LabelsCsv
	$script:NormalizedSupportLinks = $normalizedSupport.LinksCsv
	$script:MaskedSupportLinks = $normalizedSupport.MaskedLinkSummary

	if ($LogEffectiveConfiguration) {
		Write-EffectiveConfiguration
	}

	if ($RunMode -eq 'CleanupOnly') {
		if ($DryRun) {
			Write-Log -Level 'INFO' -Message "[DRY RUN] Would remove reboot task '$RebootTaskName'."
			Write-NinjaPolicyState -PolicyState 'Cleanup Completed'
			Write-Log -Level 'SUCCESS' -Message 'Cleanup-only dry run completed.'
			return
		}

		if (Remove-RebootDeadlineTask -TaskName $RebootTaskName) {
			Write-NinjaPolicyState -PolicyState 'Cleanup Completed'
			Write-Log -Level 'SUCCESS' -Message 'Cleanup-only mode completed.'
		}
		else {
			Write-Log -Level 'WARNING' -Message 'Cleanup-only mode completed with task removal warning(s).'
		}

		return
	}

	$uptimeInfo = Get-SystemUptime
	$uptime = $uptimeInfo.Uptime
	$threshold = New-TimeSpan -Days $ThresholdDays

	$uptimeSummary = '{0}d {1}h {2}m' -f [int]$uptime.TotalDays, $uptime.Hours, $uptime.Minutes
	$lastBootSummary = $uptimeInfo.LastBootTime.ToString('yyyy-MM-dd HH:mm')

	Write-Log -Level 'INFO' -Message "Last boot time: $lastBootSummary"
	Write-Log -Level 'INFO' -Message "Current uptime: $uptimeSummary"
	Write-Log -Level 'INFO' -Message "Threshold: ${ThresholdDays} day(s)"

	if ($uptime -ge $threshold) {
		Write-NinjaPolicyState -PolicyState 'Threshold Exceeded'
		$promptWasShown = $false
		$promptUserAction = $null
		$scheduledRebootAt = $null
		$defaultDeadline = (Get-Date).AddHours($RebootDeadlineHours)

		if ($EnforceRebootDeadline) {
			if ($DryRun) {
				$scheduledRebootAt = $defaultDeadline
				Write-Log -Level 'ALERT' -Message "[DRY RUN] Would schedule reboot task '$RebootTaskName' for $($defaultDeadline.ToString('yyyy-MM-dd HH:mm'))."
			}
			elseif (Set-RebootDeadlineTask -RunAt $defaultDeadline -TaskName $RebootTaskName) {
				$scheduledRebootAt = $defaultDeadline
				Write-Log -Level 'ALERT' -Message "Reboot task '$RebootTaskName' scheduled for $($defaultDeadline.ToString('yyyy-MM-dd HH:mm'))."
			}
		}

		if ($DryRun -and $AllowInteractiveScheduling) {
			Write-Log -Level 'INFO' -Message '[DRY RUN] Interactive scheduling prompt skipped.'
		}
		elseif ($AllowInteractiveScheduling -and ((Test-InteractiveUserSession) -or ((Test-IsSystemContext) -and (Test-RunAsUserAvailable)))) {
			$promptWasShown = $true
			Write-NinjaPolicyState -PolicyState 'Prompt Shown'
			Write-Log -Level 'INFO' -Message 'Attempting interactive scheduling prompt in user context.'
			$selectedHours = Get-InteractiveRebootChoiceHours -MaxHours $RebootDeadlineHours -CurrentScheduleAt $defaultDeadline

			if ($null -ne $selectedHours) {
				$promptUserAction = if ($selectedHours -eq 0) { 'Rebooted' } else { 'Scheduled Reboot' }
				$chosenTime = if ($selectedHours -eq 0) { (Get-Date).AddMinutes(2) } else { (Get-Date).AddHours($selectedHours) }

				if ($DryRun) {
					$scheduledRebootAt = $chosenTime
					Write-Log -Level 'ALERT' -Message "[DRY RUN] Would apply user-selected reboot schedule for $($chosenTime.ToString('yyyy-MM-dd HH:mm'))."
				}
				elseif (Set-RebootDeadlineTask -RunAt $chosenTime -TaskName $RebootTaskName) {
					$scheduledRebootAt = $chosenTime
					Write-Log -Level 'ALERT' -Message "User-selected reboot schedule applied for $($chosenTime.ToString('yyyy-MM-dd HH:mm'))."
				}
			}
			else {
				$promptUserAction = 'Ignored'
			}
		}
		elseif ($AllowInteractiveScheduling) {
			Write-Log -Level 'INFO' -Message 'Interactive scheduling skipped (non-interactive session).'
		}

		$deadlineText = if ($null -ne $scheduledRebootAt) { $scheduledRebootAt.ToString('yyyy-MM-dd HH:mm') } else { $defaultDeadline.ToString('yyyy-MM-dd HH:mm') }
		$uptimeCompact = '{0}d {1}h' -f [int]$uptime.TotalDays, $uptime.Hours
		$toastTitleDisplay = if ([string]::IsNullOrWhiteSpace($ToastTitle)) { 'Restart Scheduled' } else { $ToastTitle }
		if ($toastTitleDisplay.Length -gt 48) {
			$toastTitleDisplay = 'Restart Scheduled'
		}
		$toastPrefixDetail = if ([string]::IsNullOrWhiteSpace($ToastMessagePrefix)) { '' } else { $ToastMessagePrefix.Trim() }
		if ($toastPrefixDetail.Length -gt 120) {
			$toastPrefixDetail = $toastPrefixDetail.Substring(0, 117) + '...'
		}
		$toastMessage = "Reboot: $deadlineText | Uptime: $uptimeCompact"
		$toastDetail = $toastPrefixDetail

		if ($DryRun) {
			Write-Log -Level 'ALERT' -Message "[DRY RUN] Would show toast: $toastTitleDisplay | $toastMessage | $toastDetail"
		}
		else {
			$toastShown = Show-UptimeToast -Title $toastTitleDisplay -Message $toastMessage -Detail $toastDetail
			if ($toastShown) {
				Write-Log -Level 'ALERT' -Message 'Threshold exceeded. Toast notification displayed.'
				Write-Log -Level 'INFO' -Message "[TOAST-MARKER] SUCCESS | Path=$($script:LastToastPath) | Detail=$($script:LastToastReason)"
			}
			else {
				Write-Log -Level 'ALERT' -Message 'Threshold exceeded, but toast notification could not be displayed in this context.'
				$toastFailureReason = if ([string]::IsNullOrWhiteSpace($script:LastToastReason)) { 'Unknown toast failure reason.' } else { $script:LastToastReason }
				Write-Log -Level 'WARNING' -Message "[TOAST-MARKER] FAILURE | Path=$($script:LastToastPath) | Detail=$toastFailureReason"
				if (-not [string]::IsNullOrWhiteSpace($script:LastToastRawResult)) {
					Write-Log -Level 'INFO' -Message "[TOAST-MARKER] RAW_RESULT | $($script:LastToastRawResult)"
				}
			}
		}

		if ($promptWasShown -and $promptUserAction) {
			Write-NinjaPromptReport -UserAction $promptUserAction
		}

		if ($null -ne $scheduledRebootAt) {
			Write-NinjaDeadlineReport -Deadline $scheduledRebootAt
			Write-NinjaPolicyState -PolicyState 'Deadline Scheduled'
		}
	}
	else {
		Write-NinjaPolicyState -PolicyState 'Below Threshold'
		Write-Log -Level 'SUCCESS' -Message 'Threshold not exceeded. No toast shown.'

		if ($CleanupWhenBelowThreshold) {
			if ($DryRun) {
				Write-Log -Level 'INFO' -Message "[DRY RUN] Would remove reboot task '$RebootTaskName' because uptime is below threshold."
			}
			else {
				$null = Remove-RebootDeadlineTask -TaskName $RebootTaskName
				Write-NinjaPolicyState -PolicyState 'Cleanup Completed'
			}
		}
	}
}
catch {
	Write-Log -Level 'ERROR' -Message $_.Exception.Message
	exit 1
}
