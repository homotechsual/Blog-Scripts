<#
    .SYNOPSIS
        OS Configuration - Windows - Advanced Audit Settings
    .DESCRIPTION
        This script will enable advanced audit settings on a Windows device. It will also set the advanced audit settings to log all events for success and failure. This is useful for monitoring user session events.
    .NOTES
        2024-08-14: V1.3 - Less strict verficiation of the settings type to allow for handling of weird edge cases where the type result is different.
        2024-06-21: V1.2 - Test the current settings before application, and verify the settings after application. Allow the script to run in test-only mode to verify the settings without applying them and allow skipping the verification of the settings.
        2024-05-14: V1.1 - Use GUIDs for categories and subcategories to ensure compatibility with all Windows languages.
        2024-05-14: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script runs noninteractively.')]
[CmdletBinding()]
param(
    # Verify the settings only.
    [Switch]$TestOnly,
    # Skip the testing of the settings.
    [Switch]$SkipTest
)
function Get-AuditPolCommand {
    $AuditPolCommand = Get-Command -Name AuditPol
    if (!$AuditPolCommand) {
        $AuditPolExe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\auditpol.exe'
        if (!(Test-Path -Path $AuditPolExe)) {
            throw 'Cannot find auditpol.exe. Ensure that the Windows installation is not corrupt.'
        } else {
            $AuditPolCommand = $AuditPolExe
        }
    }
    return $AuditPolCommand
}
function Get-AuditPolicyCategories {
    [CmdletBinding()]
    param()
    $AuditPolCommand = Get-AuditPolCommand
    Write-Verbose ('Running command: {0} /list /subcategory:* /r' -f $AuditPolCommand)
    $Output = (& $AuditPolCommand '/list' '/subcategory:*' '/r') | Where-Object { -not [String]::IsNullOrEmpty($_) } | ConvertFrom-Csv
    return $Output
}
function Get-AuditPolicyCategory {
    [CmdletBinding()]
    param(
        [String]$Category
    )
    $AuditPolCommand = Get-AuditPolCommand
    Write-Verbose ('Running command: {0} /get /category:{1} /r' -f $AuditPolCommand, $Category)
    $Output = (& $AuditPolCommand '/get' ('/category:{0}' -f $Category) '/r') | Where-Object { -not [String]::IsNullOrEmpty($_) } | ConvertFrom-Csv
    return $Output
}
function Get-AuditPolicySettings {
    [CmdletBinding()]
    param(
        [String]$Category
    )
    Write-Verbose ('Getting audit policy settings for {0}.' -f $Category)
    $CategoryGUID = $Category
    $CategoryName = (Get-AuditPolicyCategories | Where-Object { $_.GUID -eq $CategoryGUID }).'Category/Subcategory'
    $CategorySettings = Get-AuditPolicyCategory -Category $CategoryGUID
    $AuditSettings = [PSCustomObject]@{
        Category = $CategoryName
        CategoryGUID = $CategoryGUID
        Subcategories = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
    foreach ($CategorySetting in $CategorySettings) {
        $Subcategory = $CategorySetting.Subcategory
        $SubcategoryGUID = $CategorySetting.'Subcategory GUID'
        $Success = $CategorySetting.'Inclusion Setting' -like '*Success*'
        $Failure = $CategorySetting.'Inclusion Setting' -like '*Failure*'
        $AuditSetting = [PSCustomObject]@{
            Subcategory = $Subcategory
            SubcategoryGUID = $SubcategoryGUID
            Success = $Success
            Failure = $Failure
        }
        $AuditSettings.Subcategories.Add($AuditSetting)
    }
    return $AuditSettings
}
function Test-AuditSettings {
    [CmdletBinding()]
    param(
        [Object]$AuditConfiguration,
        [Switch]$Detailed
    )
    Write-Verbose ('Testing audit settings for {0}.' -f $AuditConfiguration.Category)
    $AuditSettings = Get-AuditPolicySettings -Category $AuditConfiguration.Category
    $CategoryName = $AuditSettings.Category
    $ErrorList = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($DesiredSetting in $AuditConfiguration.Settings) {
        Write-Verbose ('Desired Settings for {0} - {1}: Success: {2}, Failure: {3}' -f $CategoryName, $DesiredSetting.Subcategory, $DesiredSetting.Success, $DesiredSetting.Failure)
        if ($DesiredSetting.Subcategory -eq '*') {
            Write-Verbose 'Using wildcard subcategory handling.'
            $SuccessState = if ($DesiredSetting.Success -eq 'enable') { $true } else { $false }
            $FailureState = if ($DesiredSetting.Failure -eq 'enable') { $true } else { $false }
            $ConfiguredSettings = $AuditSettings.Subcategories
            Write-Verbose ('Configured Settings for {0} - {1}: Success: {2}, Failure: {3}' -f $CategoryName, '*', $ConfiguredSettings[0].Success, $ConfiguredSettings[0].Failure)
            if ($Detailed) {
                $ErrorDetail = [PSCustomObject]@{
                    Category = $CategoryName
                    Subcategory = '*'
                    Error = ''
                }
            }
            $SettingsMatch = foreach ($ConfiguredSetting in $ConfiguredSettings) {
                if ($ConfiguredSetting[0].Success -ne $SuccessState) {
                    if ($Detailed) {
                        $ErrorDetail.Error = ($ErrorDetail.Error += 'Success state does not match.')
                    }
                    $Mismatch = $true
                }
                if ($ConfiguredSetting[0].Failure -ne $FailureState) {
                    if ($Detailed) {
                        $ErrorDetail.Error = ($ErrorDetail.Error += 'Failure state does not match.')
                    }
                    $Mismatch = $true
                }
                if ($Mismatch) {
                    return $false
                } else {
                    return $true
                }
            }
            if ($ErrorDetail.Error -ne [String]::Empty) {
                $ErrorList.Add($ErrorDetail)
            }
        } else {
            Write-Verbose 'Using specific subcategory handling.'
            $ConfiguredSetting = $AuditSettings.Subcategories | Where-Object { ($_.SubcategoryGUID -eq $DesiredSetting.Subcategory) }
            Write-Verbose ('Configured Settings for {0} - {1}: Success: {2}, Failure: {3}' -f $CategoryName, $ConfiguredSetting.Subcategory, $ConfiguredSetting.Success, $ConfiguredSetting.Failure)
            if ($Detailed) {
                if ($ConfiguredSetting -eq $null) {
                    $ErrorDetail = [PSCustomObject]@{
                        Category = $CategoryName
                        Subcategory = $DesiredSetting.Subcategory
                        Error = 'Subcategory not found.'
                    }
                    $ErrorList.Add($ErrorDetail)
                    continue
                }
            }
            $SuccessState = if ($DesiredSetting.Success -eq 'enable') { $true } else { $false }
            $FailureState = if ($DesiredSetting.Failure -eq 'enable') { $true } else { $false }
            $SettingsMatch = if ($ConfiguredSetting.Success -ne $SuccessState) {
                if ($Detailed) {
                    $ErrorDetail = [PSCustomObject]@{
                        Category = $CategoryName
                        Subcategory = $DesiredSetting.Subcategory
                        Error = 'Success state does not match.'
                    }
                    $ErrorList.Add($ErrorDetail)
                }
                $Mismatch = $true
            } elseif ($ConfiguredSetting.Failure -ne $FailureState) {
                if ($Detailed) {
                    $ErrorDetail = [PSCustomObject]@{
                        Category = $CategoryName
                        Subcategory = $DesiredSetting.Subcategory
                        Error = 'Failure state does not match.'
                    }
                    $ErrorList.Add($ErrorDetail)
                }
                $Mismatch = $true
            }
            if ($Mismatch) {
                return $false
            } else {
                return $true
            }            
        }
    }
    if ($Detailed) {
        if ($ErrorList.Count -gt 0) {
            Write-Verbose ('Found {0} errors in audit settings for {1}.' -f $ErrorList.Count, $CategoryName)
            return $ErrorList
        }
    }
    Write-Verbose (('Test results for {0}: {1}' -f $CategoryName, $SettingsMatch))
    return $SettingsMatch
}
function Set-AuditPolicy {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Script runs noninteractively.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Script runs noninteractively.')]
    [CmdletBinding()]
    param(
        [String]$Category,
        [System.Collections.Generic.List[Object]]$Settings
    )
    $AuditPolCommand = Get-AuditPolCommand
    Write-Host ('Trying to set advanced audit settings for {0}.' -f $Category)
    $AuditPolSetArguments = [System.Collections.Generic.List[string]]::new()
    $AuditPolSetArguments.Add('/set')
    $AuditPolSetArguments.Add(('/category:{0}' -f $Category))
    foreach ($Setting in $Settings) {
        $InstanceAuditPolSetArguments = [System.Collections.Generic.List[string]]::new()
        $InstanceAuditPolSetArguments.AddRange($AuditPolSetArguments)
        $SubCategory = $Setting.Subcategory
        Write-Verbose ('Subcategory: {0}' -f $SubCategory)
        if ($SubCategory -ne '*') {
            $InstanceAuditPolSetArguments.Add(('/subcategory:{0}' -f $SubCategory))
        }
        Write-Verbose 'Processing subcategory settings.'
        $Success = $Setting.Success
        $Failure = $Setting.Failure
        if ($Success) {
            Write-Verbose ('Setting success auditing for {0} to {1}.' -f $SubCategory, $Success)
            $InstanceAuditPolSetArguments.Add(('/success:{0}' -f $Success))
        } else {
            Write-Verbose ('Skipping success auditing for {0}.' -f $SubCategory)
        }
        if ($Failure) {
            Write-Verbose ('Setting failure auditing for {0} to {1}.' -f $SubCategory, $Failure)
            $InstanceAuditPolSetArguments.Add(('/failure:{0}' -f $Failure))
        } else {
            Write-Verbose ('Skipping failure auditing for {0}.' -f $SubCategory)
        }
        Write-Verbose ('Command: {0} {1}' -f $AuditPolCommand, ($InstanceAuditPolSetArguments -join ' '))
        try {
            $Output = & $AuditPolCommand @InstanceAuditPolSetArguments
            if ($Output.Contains('The command was successfully executed.')) {
                Write-Host ('Successfully set advanced audit settings for {1} - {0}.' -f $Category, $SubCategory)
            } else {
                Write-Error ('Failed to set advanced audit settings for {0}. Error output: {1}' -f $SubCategory, ($Output | Out-String).Trim())
            }
        } catch {
            throw ('Failed to set advanced audit settings for {0}. Error: {1}' -f $SubCategory, $_.Exception.Message)
        }
        $InstanceAuditPolSetArguments.Clear()
    }
}
$AuditConfigurations = @(
    @{
        Category = '{69979850-797A-11D9-BED3-505054503030}' # Account Logon
        Settings = @(
            @{
                subcategory = '*'
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = '{6997984E-797A-11D9-BED3-505054503030}' # Account Management
        Settings = @(
            @{
                subcategory = '*' 
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = '{6997984C-797A-11D9-BED3-505054503030}' # Detailed Tracking
        Settings = @(
            @{
                subcategory = '{0CCE922D-69AE-11D9-BED3-505054503030}' # Data Protection API Activity / DPAPI Activity
                subcategoryName = 'Data Protection API Activity'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE922B-69AE-11D9-BED3-505054503030}' # Process Creation
                subcategoryName = 'Process Creation'
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = '{69979849-797A-11D9-BED3-505054503030}' # Logon/Logoff
        Settings = @(
            @{
                subcategory = '{0CCE9217-69AE-11D9-BED3-505054503030}' # Account Lockout
                subcategoryName = 'Account Lockout'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9216-69AE-11D9-BED3-505054503030}' # Logoff
                subcategoryName = 'Logoff'
                success = 'enable'
                failure = $null
            },
            @{
                subcategory = '{0CCE9215-69AE-11D9-BED3-505054503030}' # Logon
                subcategoryName = 'Logon'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE921B-69AE-11D9-BED3-505054503030}' # Special Logon
                subcategoryName = 'Special Logon'
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = '{6997984D-797A-11D9-BED3-505054503030}' # Policy Change
        Settings = @(
            @{
                subcategory = '{0CCE922F-69AE-11D9-BED3-505054503030}' # Audit Policy Change
                subcategoryName = 'Audit Policy Change'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9230-69AE-11D9-BED3-505054503030}' # Authentication Policy Change
                subcategoryName = 'Authentication Policy Change'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9232-69AE-11D9-BED3-505054503030}' # Windows Firewall with Advanced Security Policy Change / MPSSVC Rule-Level Policy Change
                subcategoryName = 'MPSSVC Rule-Level Policy Change'
                success = 'enable'
                failure = $null
            }
        )
    },
    @{
        Category = '{69979848-797A-11D9-BED3-505054503030}' # System
        Settings = @(
            @{
                subcategory = '{0CCE9213-69AE-11D9-BED3-505054503030}' # IPsec Driver
                subcategoryName = 'IPsec Driver'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9210-69AE-11D9-BED3-505054503030}' # Security State Change
                subcategoryName = 'Security State Change'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9211-69AE-11D9-BED3-505054503030}' # Security System Extension
                subcategoryName = 'Security System Extension'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9212-69AE-11D9-BED3-505054503030}' # System Integrity
                subcategoryName = 'System Integrity'
                success = 'enable'
                failure = 'enable'
            }
        )
    }
)
foreach ($AuditConfiguration in $AuditConfigurations) {
    Write-Verbose ('Processing advanced audit settings for {0}.' -f $AuditConfiguration.Category)
    $Category = $AuditConfiguration.Category
    $Settings = $AuditConfiguration.Settings
    $TestResult = if (!$SkipTest) { Test-AuditSettings -AuditConfiguration $AuditConfiguration }
    if (!$TestResult -and !$SkipTest) {
        Write-Warning ('Advanced audit settings for {0} are not set correctly. Applying settings.' -f $Category)
        $ApplySettings = $true
    } elseif ($TestResult) {
        Write-Host ('Advanced audit settings for {0} are set correctly.' -f $Category)
        $ApplySettings = $false
    }
    if (($SkipTest -and !$TestOnly) -or $ApplySettings) {
        try {
            Set-AuditPolicy -Category $Category -Settings $Settings
        } catch {
            throw ('Failed to set advanced audit settings for {0}. Error: {1}' -f $Category, $_.Exception.Message)
        }
    }
    # Verify settings
    if ($TestOnly -or !$SkipTest) {
        $TestResults = Test-AuditSettings -AuditConfiguration $AuditConfiguration -Detailed
        if ($TestResults -is [System.Collections.Generic.List[Object]]) {
            foreach ($TestResult in $TestResults) {
                Write-Error ('{0} - {1}: {2}' -f $TestResult.Category, $TestResult.Subcategory, $TestResult.Error)
            }
        } else {
            Write-Host ('Advanced audit settings for {0} are set correctly.' -f $Category)
        }
    }
}
