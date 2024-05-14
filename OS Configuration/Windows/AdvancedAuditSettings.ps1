<#
    .SYNOPSIS
        OS Configuration - Windows - Advanced Audit Settings
    .DESCRIPTION
        This script will enable advanced audit settings on a Windows device. It will also set the advanced audit settings to log all events for success and failure. This is useful for monitoring user session events.
    .NOTES
        2024-05-14: Initial version
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
        Category = 'Account Logon'
        Settings = @(
            @{
                subcategory = '*'
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = 'Account Management'
        Settings = @(
            @{
                subcategory = '*' 
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = 'Detailed Tracking'
        Settings = @(
            @{
                subcategory = 'DPAPI Activity'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'Process Creation'
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = 'Logon/Logoff'
        Settings = @(
            @{
                subcategory = 'Account Lockout'
                success = 'enable'
                failure = $null
            },
            @{
                subcategory = 'Logoff'
                success = 'enable'
                failure = $null
            },
            @{
                subcategory = 'Logon'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'Special Logon'
                success = 'enable'
                failure = 'enable'
            }
        )
    },
    @{
        Category = 'Policy Change'
        Settings = @(
            @{
                subcategory = 'Audit Policy Change'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'Authentication Policy Change'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'MPSSVC Rule-Level Policy Change'
                success = 'enable'
                failure = $null
            }
        )
    },
    @{
        Category = 'System'
        Settings = @(
            @{
                subcategory = 'IPsec Driver'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'Security State Change'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'Security System Extension'
                success = 'enable'
                failure = 'enable'
            },
            @{
                subcategory = 'System Integrity'
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
