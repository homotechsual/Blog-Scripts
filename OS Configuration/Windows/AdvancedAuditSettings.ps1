<#
    .SYNOPSIS
        OS Configuration - Windows - Advanced Audit Settings
    .DESCRIPTION
        This script will enable advanced audit settings on a Windows device. It will also set the advanced audit settings to log all events for success and failure. This is useful for monitoring user session events.
    .NOTES
        2024-05-14: V1.1 - Use GUIDs for categories and subcategories to ensure compatibility with all Windows languages.
        2024-05-14: V1.0 - Initial version
    .LINK
        Blog post: Not blogged yet.
#>
[CmdletBinding()]
param()
$AuditPolCommand = Get-Command -Name AuditPol
if (!$AuditPolCommand) {
    $AuditPolExe = Join-Path -Path $env:SystemRoot -ChildPath 'System32\auditpol.exe'
    if (!(Test-Path -Path $AuditPolExe)) {
        throw 'Cannot find auditpol.exe. Ensure that the Windows installation is not corrupt.'
    } else {
        $AuditPolCommand = $AuditPolExe
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
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE922B-69AE-11D9-BED3-505054503030}' # Process Creation
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
                success = 'enable'
                failure = $null
            },
            @{
                subcategory = '{0CCE9216-69AE-11D9-BED3-505054503030}' # Logoff
                success = 'enable'
                failure = $null
            },
            @{
                subcategory = '{0CCE9215-69AE-11D9-BED3-505054503030}' # Logon
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE921B-69AE-11D9-BED3-505054503030}' # Special Logon
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
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9230-69AE-11D9-BED3-505054503030}' # Authentication Policy Change
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9232-69AE-11D9-BED3-505054503030}' # Windows Firewall with Advanced Security Policy Change / MPSSVC Rule-Level Policy Change
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
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9210-69AE-11D9-BED3-505054503030}' # Security State Change
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9211-69AE-11D9-BED3-505054503030}' # Security System Extension
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = '{0CCE9212-69AE-11D9-BED3-505054503030}' # System Integrity
                success = 'enable'
                failure = 'enable'
            }
        )
    }
)
foreach ($AuditConfiguration in $AuditConfigurations) {
    $Category = $AuditConfiguration.Category
    $Settings = $AuditConfiguration.Settings
    Write-Host ('Setting advanced audit settings for {0}.' -f $Category)
    $AuditPolArguments = [System.Collections.Generic.List[string]]::new()
    $AuditPolArguments.Add('/set')
    $AuditPolArguments.Add(('/category:"{0}"' -f $Category))
    foreach ($Setting in $Settings) {
        $InstanceAuditPolArguments = [System.Collections.Generic.List[string]]::new()
        $InstanceAuditPolArguments.AddRange($AuditPolArguments)
        $SubCategory = $Setting.Subcategory
        Write-Verbose ('Subcategory: {0}' -f $SubCategory)
        if ($SubCategory -ne '*') {
            $InstanceAuditPolArguments.Add(('/subcategory:"{0}"' -f $SubCategory))
        }
        Write-Verbose 'Processing subcategory settings.'
        $Success = $Setting.Success
        $Failure = $Setting.Failure
        if ($Success) {
            Write-Verbose ('Setting success auditing for {0} to {1}.' -f $SubCategory, $Success)
            $InstanceAuditPolArguments.Add(('/success:{0}' -f $Success))
        } else {
            Write-Verbose ('Skipping success auditing for {0}.' -f $SubCategory)
        }
        if ($Failure) {
            Write-Verbose ('Setting failure auditing for {0} to {1}.' -f $SubCategory, $Failure)
            $InstanceAuditPolArguments.Add(('/failure:{0}' -f $Failure))
        } else {
            Write-Verbose ('Skipping failure auditing for {0}.' -f $SubCategory)
        }
        Write-Verbose ('Command: {0} {1}' -f $AuditPolCommand, ($InstanceAuditPolArguments -join ' '))
        try {
            $Output = & $AuditPolCommand @InstanceAuditPolArguments
            if ($Output.Contains('The command was successfully executed.')) {
                Write-Host ('Successfully set advanced audit settings for {1} - {0}.' -f $Category, $SubCategory)
            } else {
                Write-Error ('Failed to set advanced audit settings for {0}. Error output: {1}' -f $SubCategory, ($Output | Out-String).Trim())
            }
        } catch {
            Write-Error $_.Exception.Message
        }
        $InstanceAuditPolArguments.Clear()
    }
}
