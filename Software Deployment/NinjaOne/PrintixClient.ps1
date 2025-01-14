<#
    .SYNOPSIS
        Software Deployment - NinjaOne - Printix Client
    .DESCRIPTION
        Uses documentation fields to pull client specific Printix information to download that client's installer from Printix and install it on the endpoint.
    .NOTES
        2025-01-14: Install the .NET Desktop Runtime 8 using WinGet.
        2025-01-10: Add script variables support
        2023-02-01: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2024/01/10/Deploy-Printix-NinjaOne/
#>
[Cmdletbinding()]
param ()
$TLSProtocol = [System.Net.SecurityProtocolType]'TLS12, TLS13'
[System.Net.ServicePointManager]::SecurityProtocol = $TLSProtocol
# First try to install .NET Desktop Runtime using WinGet.
$skipPrintixInstall = Ninja-Property-Get skipPrintixInstall
if ($skipPrintixInstall) {
  Write-Host "Printix install skipped due to presence of custom field on device."
  exit 0
}
try {
    # Resolve the WinGet package manager path for use by SYSTEM
    $WinGetPathToResolve = Join-Path -Path $ENV:ProgramFiles -ChildPath 'WindowsApps\Microsoft.DesktopAppInstaller_*_*__8wekyb3d8bbwe'
    $ResolveWinGetPath = Resolve-Path -Path $WinGetPathToResolve | Sort-Object {
        [version]($_.Path -replace '^[^\d]+_((\d+\.)*\d+)_.*', '$1')
    }
    if ($ResolveWinGetPath) {
        # If we have multiple versions - use the latest.
        $WinGetPath = $ResolveWinGetPath[-1].Path
    }
    # Get the WinGet exe location.
    $WinGetExePath = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($WinGetExePath) {
        # Running in user context.
        $Script:WinGet = $WinGetExePath.Path
    } elseif (Test-Path -Path (Join-Path $WinGetPath 'winget.exe')) {
        # Running in SYSTEM context.
        $Script:WinGet = Join-Path $WinGetPath 'winget.exe'
    }
    # Pre-accept the source agreements using the `list` command.
    $Null = & $Script:WinGet list --accept-source-agreements -s winget
    # Install the .NET Desktop Runtime 8
    & $Script:WinGet install --id 'Microsoft.DotNet.DesktopRuntime.8' --accept-source-agreements --source winget --accept-package-agreements --silent --exact --force
} catch {
    Write-Error ('Failed to install .NET Desktop Runtime: `r`n {0}' -f $_)
    exit 1
}
# Make sure we have .NET Desktop Runtime 8 installed.
$DotNetDesktopRuntime8 = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -Name DisplayName -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Microsoft Windows Desktop Runtime *8*' }
if (-not $DotNetDesktopRuntime8) {
    Write-Error 'Failed to install .NET Desktop Runtime 8'
    exit 1
}
# Install the Printix Client
try {
    $PrintixTenantId = Ninja-Property-Docs-Get-Single 'Integration Identifiers' printixTenantId
    $PrintixTenantDomain = Ninja-Property-Docs-Get-Single 'Integration Identifiers' printixTenantDomain
    Write-Verbose ('Found Printix Tenant: {0} ({1})' -f $PrintixTenantId, $PrintixTenantDomain)
    if (-not ([String]::IsNullOrEmpty($PrintixTenantId) -and ([String]::IsNullOrEmpty($PrintixTenantDomain)))) {
        $PrintixInstallerURL = ('https://api.printix.net/v1/software/tenants/{0}/appl/CLIENT/os/WIN/type/MSI' -f $PrintixTenantId)
        Write-Verbose ('Built Printix Installer URL: {0}' -f $PrintixInstallerURL)
        $PrintixFileName = "CLIENT_{$PrintixTenantDomain}_{$PrintixTenantId}.msi"
        $PrintixSavePath = 'C:\RMM\Installers'
        if (-not (Test-Path $PrintixSavePath)) {
            New-Item -Path $PrintixSavePath -ItemType Directory | Out-Null
        }
        $PrintixInstallerPath = ('{0}\{1}' -f $PrintixSavePath, $PrintixFileName)
        Invoke-WebRequest -Uri $PrintixInstallerURL -OutFile $PrintixInstallerPath -Headers @{ 'Accept' = 'application/octet-stream' }
        if (Test-Path $PrintixInstallerPath) {
            Start-Process -FilePath 'msiexec.exe' -ArgumentList @(
                '/i',
                ('"{0}"' -f $PrintixInstallerPath),
                '/quiet',
                ('WRAPPED_ARGUMENTS=/id:{0}' -f $PrintixTenantId)
            ) -Wait
        } else {
            Write-Error ('Printix installer not found in {0}' -f $PrintixInstallerPath)
            exit 1
        }
    }
} catch {
    Write-Error ('Failed to install Printix Client: `r`n {0}' -f $_)
    exit 1
}