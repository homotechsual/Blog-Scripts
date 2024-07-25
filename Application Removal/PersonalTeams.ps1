<#
    .SYNOPSIS
        Application Removal - Windows - Personal Teams
    .DESCRIPTION
        Removes the personal Teams application from the machine and deprovisions it. This script is intended to be run as a machine-level script and requires the ability to modify token privileges and registry keys.
    .NOTES
        2024-07-25: Update the `Registry.ShouldBe` function.
        2024-06-04: Initial version
    .LINK
        Blog post: Not blogged yet
#>
# Utility Function: Registry.OpenKeyForWrite
## This function is used to open a registry key for writing.
function Registry.OpenKeyForWrite {
    [CmdletBinding()]
    param(
        # The path to the registry key to open.
        [Parameter(Mandatory)]
        [String]$Path,
        # The rights to open the key with.
        [System.Security.AccessControl.RegistryRights]$Rights
    )
    $Item = Get-Item $Path
    switch ($Item.Name.Split('\')[0]) {
        'HKEY_CLASSES_ROOT' {
            $RootKey = [Microsoft.Win32.Registry]::ClassesRoot
            break
        }
        'HKEY_CURRENT_USER' {
            $RootKey = [Microsoft.Win32.Registry]::CurrentUser
            break
        }
        'HKEY_LOCAL_MACHINE' {
            $RootKey = [Microsoft.Win32.Registry]::LocalMachine
            break
        }
        'HKEY_USERS' {
            $RootKey = [Microsoft.Win32.Registry]::Users
            break
        }
        'HKEY_CURRENT_CONFIG' {
            $RootKey = [Microsoft.Win32.Registry]::CurrentConfig
            break
        }
    }
    $Key = $Item.Name.Replace(($Item.Name.Split('\')[0] + '\'), '')
    $Item = $RootKey.OpenSubKey($Key, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, $Rights)
    return $Item
}
# Utility Function: FileSystem.SetACL
## This function is used to set the ACL on a file or directory to allow the specified user(s) the given rights.
function FileSystem.SetACL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Path,
        [Parameter(Mandatory)]
        [String]$User,
        [Parameter(Mandatory)]
        [System.Security.AccessControl.FileSystemRights]$Rights,
        [Switch]$Recurse
    )
    if ($Recurse) {
        $Items = Get-ChildItem -Path $Path -Recurse
    } else {
        $Items = Get-Item -Path $Path
    }
    foreach ($Item in $Items) {
        $ACL = $Item.GetAccessControl()
        $ObjectInherit = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $ContainerInherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
        $Propagation = [System.Security.AccessControl.PropagationFlags]::None
        $AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
        $Rule = [System.Security.AccessControl.FileSystemAccessRule]::new($User, $Rights, @($ObjectInherit, $ContainerInherit), $Propagation, $AccessControlType)
        $Acl.SetAccessRule($Rule)
        $Item.SetAccessControl($ACL)
    }
}

# Utility Function: Registry.SetACL
## This function is used to set the ACL on a registry key to allow the specified user(s) the given rights.
function Registry.SetACL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [String]$Path,
        [Parameter(Mandatory)]
        [String]$User,
        [Parameter(Mandatory)]
        [System.Security.AccessControl.RegistryRights]$Rights
    )%You 
    $Item = Registry.OpenKeyForWrite -Path $Path -Rights ([System.Security.AccessControl.RegistryRights]::TakeOwnership)
    $ACL = $Item.GetAccessControl()
    $ObjectInherit = [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $ContainerInherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit
    $Propagation = [System.Security.AccessControl.PropagationFlags]::None
    $AccessControlType = [System.Security.AccessControl.AccessControlType]::Allow
    $Rule = [System.Security.AccessControl.RegistryAccessRule]::new($User, $Rights, @($ObjectInherit, $ContainerInherit), $Propagation, $AccessControlType)
    $Acl.SetAccessRule($Rule)
    $Item.SetAccessControl($ACL)
}
# Utility Function: Utils.TakeOwnership
## This function is used to take ownership of a file or directory.
function Utils.TakeOwnership {
    [CmdletBinding()]
    param(
        # The path to the file or directory to take ownership of.
        [Parameter(Mandatory)]
        [String]$Path,
        # The owner to set on the file or directory.
        [Parameter(Mandatory)]
        [String]$User,
        [Switch]$Recurse
    )
    begin {
        # Add a C# assembly to the session so we can adjust the token privileges.
$AdjustTokenPrivileges=@"
using System;
using System.Runtime.InteropServices;

    public class TokenManipulator {
        [DllImport("kernel32.dll", ExactSpelling = true)]
            internal static extern IntPtr GetCurrentProcess();

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
            internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);
        [DllImport("advapi32.dll", SetLastError = true)]
            internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct TokPriv1Luid {
            public int Count;
            public long Luid;
            public int Attr;
        }

        internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
        internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
        internal const int TOKEN_QUERY = 0x00000008;
        internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

        public static bool AddPrivilege(string privilege) {
            bool retVal;
            TokPriv1Luid tp;
            IntPtr hproc = GetCurrentProcess();
            IntPtr htok = IntPtr.Zero;
            retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
            tp.Count = 1;
            tp.Luid = 0;
            tp.Attr = SE_PRIVILEGE_ENABLED;
            retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
            retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            return retVal;
        }

        public static bool RemovePrivilege(string privilege) {
            bool retVal;
            TokPriv1Luid tp;
            IntPtr hproc = GetCurrentProcess();
            IntPtr htok = IntPtr.Zero;
            retVal = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
            tp.Count = 1;
            tp.Luid = 0;
            tp.Attr = SE_PRIVILEGE_DISABLED;
            retVal = LookupPrivilegeValue(null, privilege, ref tp.Luid);
            retVal = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            return retVal;
        }
    }
"@
    }
    process {
        $Item = Get-Item $Path
        Write-Verbose ('Giving current process token the SeTakeOwnershipPrivilege and SeRestorePrivilege.')
        Add-Type -TypeDefinition $AdjustTokenPrivileges -PassThru > $null
        [Void][TokenManipulator]::AddPrivilege('SeTakeOwnershipPrivilege')
        [Void][TokenManipulator]::AddPrivilege('SeRestorePrivilege')
        Write-Verbose ('Taking ownership of {0}.' -f $Path)
        $Owner = [System.Security.Principal.NTAccount]($User)
        Write-Verbose ('Changing owner to {0}.' -f $Owner.Value)
        $Provider = $Item.PSProvider.Name
        if ($Item.PSIsContainer) {
            switch ($Provider) {
                'FileSystem' {
                    $ACL = [System.Security.AccessControl.DirectorySecurity]::new()
                }
                'Registry' {
                    $ACL = [System.Security.AccessControl.RegistrySecurity]::new()
                    $Item = Registry.OpenKeyForWrite -Path $Path -Rights ([System.Security.AccessControl.RegistryRights]::TakeOwnership)
                }
                default {
                    throw ('Provider {0} is not supported.' -f $Provider)
                }
            }
            $ACL.SetOwner($Owner)
            Write-Verbose ('Setting owner on {0}.' -f $Path)
            $Item.SetAccessControl($ACL)
            if ($Provider -eq 'Registry') {
                $Item.Close()
            }
            if ($Recurse.IsPresent) {
                # Cannot recurse into registry items.
                if ($Provider -eq 'Registry') {
                    $Items = Get-ChildItem -Path $Path -Recurse -Force | Where-Object -Property PSIsContainer -EQ $true
                } else {
                    $Items = Get-ChildItem -Path $Path -Recurse -Force
                }
                if ($Items -isnot [System.Array]) {
                    $Items = [System.Array]$Items
                }
                for ($i = 0; $i -lt $Items.Count; $i++) {
                    switch ($Provider) {
                        'FileSystem' {
                            $Item = Get-Item $Items[$i].FullName
                            if ($Item.PSIsContainer) {
                                $ACL = [System.Security.AccessControl.DirectorySecurity]::new()
                            } else {
                                $ACL = [System.Security.AccessControl.FileSecurity]::new()
                            }
                        }
                        'Registry' {
                            $Item = Get-Item $Items[$i].PSPath
                            $ACL = [System.Security.AccessControl.RegistrySecurity]::new()
                            $Item = Registry.OpenKeyForWrite -Path $Item -Rights ([System.Security.AccessControl.RegistryRights]::TakeOwnership)
                        }
                        default {
                            throw ('Provider {0} is not supported.' -f $Provider)
                        }
                    }
                    $ACL.SetOwner($Owner)
                    Write-Verbose ('Setting owner on {0}.' -f $Item.Name)
                    $Item.SetAccessControl($ACL)
                }
            }
        }
    }
}
# Utility Function: AppPackage.RemoveandDeprovision
## This function is used to ensure that an app package is uninstalled for all users and deprovisioned.
function AppPackage.RemoveandDeprovision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$PackageNames
    )
    $exitvalue = 0
    foreach ($PackageName in $PackageNames) {
        Write-Host ('Checking if package {0} is installed...' -f $PackageName)
        # Find the provisioned package
        $ProvisionedPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -eq $PackageName }
        $PackageRemovalLoopCount = 0
        # Try current user remove.
        do {
            Write-Host ('Attempt {0} to find and remove package {1}.' -f $PackageRemovalLoopCount, $PackageName)
            $PackageRemovalLoopCount++
            $Package = Get-AppxPackage -Name $PackageName
            if ($Package) {
                try {
                    # Uninstall the app package
                    $null = $Package | Remove-AppxPackage
                    Start-Sleep -Seconds 5
                    Write-Host ('Package {0} has been successfully uninstalled.' -f $PackageName)
                } catch {
                    Write-Error ('Failed to uninstall package {0}. Error: {1}' -f $PackageName, $_)
                    $exitvalue++
                }
            } else {
                Write-Host ('Package {0} is not installed or not found. Skipping uninstallation.' -f $PackageName)
            }
        } until (($null -eq $Package) -or $PackageRemovalLoopCount -eq 3)
        # Try all users remove.
        do {
            Write-Host ('Attempt {0} to find and remove package {1}.' -f $PackageRemovalLoopCount, $PackageName)
            $PackageRemovalLoopCount++
            $Package = Get-AppxPackage -Name $PackageName -AllUsers
            if ($Package) {
                try {
                    # Uninstall the app package
                    $null = $Package | Remove-AppxPackage -AllUsers
                    Start-Sleep -Seconds 5
                    Write-Host ('Package {0} has been successfully uninstalled.' -f $PackageName)
                } catch {
                    Write-Error ('Failed to uninstall package {0}. Error: {1}' -f $PackageName, $_)
                    $exitvalue++
                }
            } else {
                Write-Host ('Package {0} is not installed or not found. Skipping uninstallation.' -f $PackageName)
            }
        } until (($null -eq $Package) -or $PackageRemovalLoopCount -eq 3)
        $Package = Get-AppxPackage -Name $PackageName -AllUsers
        if ($Package) {
            Write-Error ('Failed to uninstall package {0} after 3 attempts. Please see the error messages above.' -f $PackageName)
            $exitvalue++
        }
        if ($ProvisionedPackage) {
            try {
                # Deprovision the app package
                $null = $ProvisionedPackage | Remove-AppxProvisionedPackage -AllUsers -Online
                Write-Host ('Package {0} has been deprovisioned.' -f $PackageName)
            } catch {
                Write-Error ('Failed to deprovision app package {0}. Error: {1}' -f $PackageName, $_)
                $exitvalue++
            }
        } else {
            Write-Host ('Package {0} is not provisoned. Skipping deprovisioning.' -f $PackageName)
        }
    }
    return $exitvalue
}

# Utility Function: Registry.ShouldBe
## This function is used to ensure that a registry value exists and is set to a specific value.
function Registry.ShouldBe {
    [CmdletBinding(DefaultParameterSetName = 'Named')]
    param(
        # The registry path to the key.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [String]$Path,
        # The name of the registry value.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [String]$Name,
        # The value to set the registry value to.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [Object]$Value,
        # The type of the registry value.
        [Parameter(Mandatory, ParameterSetName = 'Named')]
        [Parameter(Mandatory, ParameterSetName = 'Default')]
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord', 'None')]
        [Microsoft.Win32.RegistryValueKind]$Type,
        # Don't confirm that the registry value was set correctly.
        [Parameter(ParameterSetName = 'Named')]
        [Parameter(ParameterSetName = 'Default')]
        [Switch]$SkipConfirmation,
        # Use 'Default' parameter set if no name is provided.
        [Parameter(ParameterSetName = 'Default')]
        [Switch]$Default
    )
    begin {
        # Make sure the registry path exists.
        if (!(Test-Path $Path)) {
            Write-Warning ("Registry path '$Path' does not exist. Creating.")
            New-Item -Path $Path -Force | Out-Null
        }
        # Make sure it's actually a registry path.
        if (!(Get-Item $Path).PSProvider.Name -eq 'Registry' -and !(Get-Item $Path).PSIsContainer) {
            throw "Path '$Path' is not a registry path."
        }
        $LoopCount = 0
    }
    process {   
        if ($Name) {
            do {
                # Handle named registry values.
                # Make sure the registry value exists.
                if (!(Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue)) {
                    Write-Warning ("Registry value '$Name' in path '$Path' does not exist. Setting to '$Value'.")
                    New-ItemProperty -Path $Path -Name $Name -Value $Value -Force -Type $Type | Out-Null
                }
                # Make sure the registry value type is correct. Skip if it's a None type.
                if ($Type -ne [Microsoft.Win32.RegistryValueKind]::None) {
                    if ((Get-Item -Path $Path).GetValueKind($Name) -ne $Type) {
                        Write-Warning ("Registry value '$Name' in path '$Path' is not of type '$Type'. Resetting to '$Type', '$Value'.")
                        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
                    }
                }
                # Make sure the registry value is correct.
                if (!$SkipConfirmation) {
                    if ((Get-ItemProperty -Path $Path -Name $Name).$Name -ne $Value) {
                        Write-Warning ("Registry value '$Name' in path '$Path' is not correct. Setting to '$Value'.")
                        Set-ItemProperty -Path $Path -Name $Name -Value $Value
                    }
                    $LoopCount++
                } else {
                    # Short circuit the loop if we're skipping confirmation.
                    $LoopCount = 3
                }
            } while ((Get-ItemProperty -Path $Path -Name $Name).$Name -ne $Value -and $LoopCount -lt 3)
        } else {
            do {
                # Handle default registry values.
                # Make sure the registry value exists.
                $RegistryValue = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
                if (!$RegistryValue -or !$RegistryValue.'(default)') {
                    Write-Warning ("Registry value in path '$Path' does not exist. Setting to '$Value'.")
                    New-ItemProperty -Path $Path -Value $Value -Force -Type $Type | Out-Null
                }
                # Make sure the registry value type is correct. Skip if it's a None type.
                if ($Type -ne [Microsoft.Win32.RegistryValueKind]::None) {
                    if ((Get-Item -Path $Path).GetValueKind('') -ne $Type) {
                        Write-Warning ("Registry value in path '$Path' is not of type '$Type'. Resetting to '$Type', '$Value'.")
                        Set-ItemProperty -Path $Path -Value $Value -Type $Type
                    }
                }
                # Make sure the registry value is correct.
                if (!$SkipConfirmation) {
                    if ((Get-ItemProperty -Path $Path).'(default)' -ne $Value) {
                        Write-Warning ("Registry value in path '$Path' is not correct. Setting to '$Value'.")
                        Set-ItemProperty -Path $Path -Value $Value
                    }
                    $LoopCount++
                } else {
                    # Short circuit the loop if we're skipping confirmation.
                    $LoopCount = 3
                }
            } while ((Get-ItemProperty -Path $Path).'(default)' -ne $Value -and $LoopCount -lt 3)
        }        
    }
}
# Set the registry keys to prevent Teams from being reprovisioned by the OS and remove the shortcut.
$CommunicationsRegKey = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Communications'
Write-Output ('Setting ownership of {0} to SYSTEM.' -f $CommunicationsRegKey)
Utils.TakeOwnership -Path $CommunicationsRegKey -User 'NT AUTHORITY\SYSTEM'
Write-Output ('Setting FullControl ACL on {0} for SYSTEM.' -f $CommunicationsRegKey)
Registry.SetACL -Path $CommunicationsRegKey -User 'NT AUTHORITY\SYSTEM' -Rights 'FullControl'
Registry.ShouldBe -Path $CommunicationsRegKey -Name 'ConfigureChatAutoInstall' -Value 0 -Type DWord
Write-Output ('Resetting ReadKey ACL on {0} for SYSTEM.' -f $CommunicationsRegKey)
Registry.SetACL -Path $CommunicationsRegKey -User 'NT AUTHORITY\SYSTEM' -Rights 'ReadKey'
Write-Output ('Resetting ownership of {0} to TrustedInstaller.' -f $CommunicationsRegKey)
Utils.TakeOwnership -Path $CommunicationsRegKey -User 'NT SERVICE\TrustedInstaller'
Registry.ShouldBe -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' -Name 'ChatIcon' -Value 3 -Type DWord
$RemoveAndDeprovisionResult = AppPackage.RemoveandDeprovision -PackageNames 'MicrosoftTeams'
if ($RemoveAndDeprovisionResult -gt 0) {
    Write-Error ('Failed to remove and deprovision all app packages. Please see the error messages above.')
    exit $RemoveAndDeprovisionResult
}