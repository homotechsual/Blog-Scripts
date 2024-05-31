function Initialise-PSResourceGet {
    <#
    .SYNOPSIS
        Fixes common issues with PowerShellGet and PackageManagement and then installs PSResourceGet.

    .DESCRIPTION
        This script will check for common issues with PowerShellGet and PackageManagement and then install PSResourceGet.

    .NOTES
        Version:        2.1
        Author:         Mikey O'Toole
        Creation Date:  2024/05/31
        Purpose/Change: Altered removal logic for PackageManagement and PowerShellGet to remove all versions except the latest or any specifically excluded versions.
        --------------------------------------------------------------------
        Version:        2.0
        Author:         Mikey O'Toole
        Creation Date:  2024/03/26
        Purpose/Change: Updated to also install PSResourceGet aka PowerShellGet v3. Now downloads the PackageManagmenet and PowerShellGet modules from the PowerShell Gallery directly rather than a zip on GitHub.
        --------------------------------------------------------------------
        Version:        1.0
        Author:         Chris Taylor
        Creation Date:  2020/01/20
        Purpose/Change: Initial script development

    #>
    [cmdletbinding()]
    Param(
        [System.IO.DirectoryInfo]$StagingPath = 'C:\RMM\PowerShellStaging\'
    )
    $NuGetMinVersion = [System.Version]'3.0.0.1'
    $PackageManagementMinVersion = [System.Version]'1.4.8'
    $GalleryURL = 'https://www.powershellgallery.com/api/v2/'
    function Register-PSGallery {
        if ($Host.Version.Major -gt 4) {
            Register-PSRepository -Default
        } else {
            Import-Module PowerShellGet
            Register-PSRepository -Name PSGallery -SourceLocation $GalleryURL -InstallationPolicy Trusted
        }
    }
    function Redo-PowerShellGet {
        Write-Verbose 'Issue with PowerShellGet, Reinstalling.'
        $Module = 'PowerShellGet'
        foreach ($ProfilePath in $env:PSModulePath.Split(';')) {
            $FullPath = Join-Path $ProfilePath $Module
            Get-ChildItem $FullPath -Exclude '1.0.0.1' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
        }
        Register-PSGallery
        $null = Install-Module $Module -Force -AllowClobber
        Import-Module $Module -Force
    }
    function Invoke-DownloadedModuleCleaner ([String]$ModulePath) {
        if (!(Test-Path -Path $ModulePath)) {
            throw ('Module path {0} does not exist.' -f $ModulePath)
        }
        Get-ChildItem -Path $ModulePath -Filter '*.nuspec' -Recurse | Remove-Item -Force -Recurse
        Get-ChildItem -Path $ModulePath -Filter '[Content_Types].xml' -Recurse | Remove-Item -Force -Recurse
        Get-ChildItem -Path $ModulePath -Filter '_rels' -Recurse -Directory | Remove-Item -Force -Recurse
        Get-ChildItem -Path $ModulePath -Filter 'package' -Recurse -Directory | Remove-Item -Force -Recurse
    }
    function Get-LatestModuleVersion ([String]$ModuleName) {
        $Module = Invoke-RestMethod -Uri ("{0}/FindPackagesById()?id='{1}'&`$filter=IsLatestVersion and Id eq '{1}'" -f $GalleryURL, $ModuleName) -ErrorAction Stop
        $Module.Properties.NormalizedVersion
    }
    function Save-ModuleFromGallery ([String[]]$ModuleNames) {
        foreach ($ModuleName in $ModuleNames) {
            $ModuleVersion = Get-LatestModuleVersion -ModuleName $ModuleName
            $ModuleURL = ('https://www.powershellgallery.com/api/v2/package/{0}/{1}' -f $ModuleName, $ModuleVersion)
            $WebClient = [System.Net.WebClient]::new()
            $ModuleFileName = ('{0}-{1}.zip' -f $ModuleName, $ModuleVersion)
            $ModuleDownloadPath = Join-Path -Path $StagingPath -ChildPath $ModuleFileName
            $WebClient.DownloadFile($ModuleURL, $ModuleDownloadPath)
            $ModuleExtractPath = Join-Path -Path $StagingPath -ChildPath $ModuleName
            $ModuleVersionedExtractPath = Join-Path -Path $ModuleExtractPath -ChildPath $ModuleVersion
            Expand-Archive -Path $ModuleDownloadPath -Destination $ModuleVersionedExtractPath -Force
            Invoke-DownloadedModuleCleaner -ModulePath $ModuleVersionedExtractPath
        }
    }
    if (!(Test-Path -Path $StagingPath)) {
        New-Item -Path $StagingPath -ItemType Directory | Out-Null
    }
    if ($PSVersionTable.PSVersion.Major -lt 3) {
        Write-Error 'Requires PowerShell version 3 or greater.' -ErrorAction Stop
    }
    try {
        [version]$DotNetVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name Version).Version
        if ($DotNetVersion -lt [version]4.5) {
            throw
        }
    } catch {
        Write-Error '.NET version 4.5 or greater is needed.' -ErrorAction Stop
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Error 'TLS 1.2 Not supported.' -ErrorAction Stop
    }
    $WinmgmtService = Get-Service Winmgmt
    if ($WinmgmtService.StartType -eq 'Disabled') {
        Set-Service Winmgmt -StartupType Manual
    }

    if ($ENV:PSModulePath -split ';' -notcontains "$ENV:ProgramFiles\WindowsPowerShell\Modules") {
        [Environment]::SetEnvironmentVariable(
            'PSModulePath',
            ((([Environment]::GetEnvironmentVariable('PSModulePath', 'Machine') -split ';') + "$ENV:ProgramFiles\WindowsPowerShell\Modules") -join ';'),
            'Machine'
        )
    }
    # Remove Package Management Preview
    Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/X', '"{57E5A8BB-41EB-4F09-B332-B535C5954A28}"', '/qn')
    # Set Execution Policy
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Confirm:$false -Force -ErrorAction SilentlyContinue
    try {
        $null = Get-Command Install-PackageProvider -ErrorAction Stop
        $null = Get-Command Install-Module -ErrorAction Stop
        $PackageManagement = Get-Module PackageManagement -ListAvailable -ErrorAction Stop | Sort-Object Version -Descending | Select-Object -First 1
        if ($PackageManagement.Version -lt $PackageManagementMinVersion) {
            throw
        }
    } catch {
        Write-Verbose 'Missing Package Manager, installing'
        $NeededModules = @(
            [PSCustomObject]@{
                name = 'PowerShellGet'
                excludeVersions = @((Get-LatestModuleVersion -ModuleName 'PowerShellGet'))
            },
            [PSCustomObject]@{
                name = 'PackageManagement'
                excludeVersions = @(1.0.0.1, (Get-LatestModuleVersion -ModuleName 'PackageManagement'))
            }
        )
        Save-ModuleFromGallery -ModuleNames $NeededModules
        foreach ($Module in $NeededModules) {
            try {
                Write-Verbose ('Processing {0}' -f $Module.name)
                $DownloadedModulePath = Join-Path -Path $StagingPath -ChildPath $Module.name
                $ModulePath = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
                $InstalledModulePath = Join-Path -Path $ModulePath -ChildPath $Module.name
                if ($Host.Version.Major -lt 5) {
                    # These versions of PoSh want the files in the root of the drive not version sub folders
                    Write-Verbose ('Removing {0}' -f $InstalledModulePath)
                    Remove-Module -Name $Module -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path $InstalledModulePath -Recurse -Force
                    Write-Verbose ('Copying {0} to {1}' -f $DownloadedModulePath, $ModulePath)
                    Get-ChildItem -Path $DownloadedModulePath | Get-ChildItem -Recurse | ForEach-Object {
                        Copy-Item -Path $_.FullName -Destination $DownloadedModulePath -Force
                    }
                } else {
                    Write-Verbose ('Removing {0}' -f $InstalledModulePath)
                    # If the folder name matches our target version don't remove it.
                    if ((Get-ChildItem -Path $InstalledModulePath -Directory | Where-Object { $_.Name -ne $Module.excludeVersions })) {
                        Remove-Module -Name $Module -Force -ErrorAction SilentlyContinue
                        Remove-Item -Path $InstalledModulePath -Recurse -Force
                        New-Item -Path $InstalledModulePath -ItemType Directory -ErrorAction SilentlyContinue
                        Write-Verbose ('Copying {0} to {1}' -f $DownloadedModulePath, $ModulePath)
                        Copy-Item -Path $DownloadedModulePath -Destination $ModulePath -Recurse -Force
                    } else {
                        Write-Verbose ('Skipping {0} as it is the an excluded or the latest version' -f $Module.name)
                    }
                }
            } catch {
                Write-Error ('Failed to process {0}, because of the error "{1}"' -f $Module.name, $_.Exception.Message)
            }
        }
        Remove-Item $StagingPath -Force -Recurse -ErrorAction SilentlyContinue
        foreach ($Module in $NeededModules) {
            $Found = $false
            $ModulePaths = $ENV:PSModulePath -split ';'
            foreach ($ModulePath in $ModulePaths) {
                $Path = (Join-Path -Path $ModulePath -ChildPath $Module)
                if ((Test-Path $Path)) {
                    $Found = $true
                    $FoundModulePath = Get-ChildItem $Path -Recurse | Sort-Object -Descending | Where-Object { $_.Name -eq ('{0}.psd1' -f $Module) } | Select-Object -First 1
                    Import-Module $FoundModulePath.FullName
                }
            }
            if (!$Found) {
                Write-Error ('Unable to find {0}' -f $Module) -ErrorAction Stop
            }
        }
    }
    # Reset the modules in our environment.
    $null = Remove-Module -Name PackageManagement -Force -ErrorAction SilentlyContinue
    $null = Remove-Module -Name PowerShellGet -Force -ErrorAction SilentlyContinue
    $null = Import-Module PackageManagement -Force -ErrorAction SilentlyContinue
    $null = Import-Module PowerShellGet -Force -ErrorAction SilentlyContinue
    # Ensure PowerShellGet is working.
    try {
        $null = Get-Command Get-PackageProvider -ErrorAction Stop
    } catch {
        Redo-PowerShellGet
    }
    # Ensure we have the Nuget provider and test `Update-Module` and `Install-Module` are working.
    try {
        $Nuget = Get-PackageProvider NuGet -ListAvailable -ErrorAction Stop | Where-Object { $_.Version -ge $NuGetMinVersion }
        try {
            Update-Module PowerShellGet -Force -Confirm:$false -ErrorAction Stop
        } catch {
            Install-Module PowerShellGet -Force -Confirm:$false
        }
    } catch {
        $null = Install-PackageProvider NuGet -MinimumVersion $NuGetMinVersion -Force -Confirm:$false
        $null = Install-Module PowershellGet -Force -Confirm:$false
    }
    # Ensure we have NuGet.
    if (!$Nuget) {
        $null = Install-PackageProvider NuGet -MinimumVersion $NuGetMinVersion -Force -Confirm:$false
    }
    # Ensure we have PSNuGet.
    try {
        $null = Get-PackageSource -Name PSNuGet -ErrorAction Stop
    } catch {
        $null = Register-PackageSource -Name PSNuGet -Location $GalleryURL -ProviderName NuGet -Force
    }
    # Ensure we have PSGallery.
    try {
        $null = Get-PSRepository 'PSGallery' -ErrorAction Stop
    } catch {
        if ($_.exception.message -eq 'Invalid class') {
            Redo-PowerShellGet
        } else {
            Write-Verbose 'Registering PSGallery.'
            $PSRepositoriesPath = (Join-Path -Path $ENV:LocalAppData -ChildPath 'Microsoft\windows\PowerShell\PowerShellGet\PSRepositories.xml')
            Remove-Item -Path $PSRepositoriesPath -ErrorAction SilentlyContinue
            Register-PSGallery
        }
    }
    # Ensure PSGallery is trusted.
    if ((Get-PSRepository 'PSGallery').InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name 'PSGallery' -InstallationPolicy Trusted
    }
    # Ensure we have PSResourceGet.
    try {
        $null = Get-Command Install-PSResource -ErrorAction Stop
    } catch {
        Install-Module -Name 'Microsoft.PowerShell.PSResourceGet' -Force -Confirm:$false
    }
}
Initialise-PSResourceGet -ErrorAction Stop