<#
    .SYNOPSIS
        Software Deployment - NinjaOne - Printix Client
    .DESCRIPTION
        Uses documentation fields to pull client specific Printix information to download that client's installer from Printix and install it on the endpoint.
    .NOTES
        2025-01-10: Add script variables support
        2023-02-01: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2024/01/10/Deploy-Printix-NinjaOne/
#>
[Cmdletbinding()]
param (
    [Parameter(Mandatory = $true)]
    [String]$DocumentTemplate
)
if ($ENV:DocumentTemplate) {
    $DocumentTemplate = $ENV:DocumentTemplate
}
try {
    $PrintixTenantId = Ninja-Property-Docs-Get-Single $DocumentTemplate printixTenantId
    $PrintixTenantDomain = Ninja-Property-Docs-Get-Single $DocumentTemplate printixTenantDomain
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
        }
    }
} catch {
    Write-Error ('Failed to install Printix Client: `r`n {0}' -f $_)
}