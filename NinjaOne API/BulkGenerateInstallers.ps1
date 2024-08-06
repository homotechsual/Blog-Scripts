[CmdletBinding()]
param(
    # Download the installers.
    [Switch]$Download,
    # Location to save the installers to.
    [System.IO.DirectoryInfo]$DownloadPath = 'C:\RMM\Installers\NinjaOne',
    # Upload the installers to an Azuyr Blob Storage container.
    [Switch]$Upload,
    # Azure Storage account to upload the installers to.
    [String]$AzureStorageAccount,
    # Azure Storage container to upload the installers to.
    [String]$AzureStorageContainer,
    # Azure Storage account key for the Azure Storage account.
    [String]$AzureStorageAccountKey = $ENV:AzureStorageAccountKey,
    # Clean up the downloaded installers after uploading them.
    [Switch]$CleanUp
)
if ($Download -or $Upload) {
    if (-not (Test-Path -Path $DownloadPath)) {
        New-Item -ItemType Directory -Path $DownloadPath | Out-Null
    }
}
$Organisations = Get-NinjaOneOrganisations
$Installers = [System.Collections.Generic.List[Hashtable]]::New()
$Locations = ForEach ($Organisation in $Organisations) {
    $OrganisationName = $Organisation.name
    $Locations = Get-NinjaOneLocations -organisationId $Organisation.id
    ForEach ($Location in $Locations) {
        $LocationName = $Location.name
        $FileName = '{0}-{1}.msi' -f $OrganisationName, $LocationName
        $InstallerURI = Get-NinjaOneInstaller -organisationId $Organisation.id -locationId $Location.id -installerType 'WINDOWS_MSI' | Select-Object -ExpandProperty 'url'
        $Installer = @{
            Organisation = $OrganisationName
            Location = $LocationName
            FileName = $FileName
            URI = $InstallerURI
        }
        $Installers.Add($Installer)
    }
}
if ($Download -or $Upload) {
    $OriginalProgressPreference = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    ForEach ($Installer in $Installers) {
        $InstallerFilePath = Join-Path -Path $DownloadPath -ChildPath $Installer.FileName
        Write-Verbose ('Downloading {0} to {1}' -f $Installer.URI, $InstallerFilePath)
        Invoke-WebRequest -Uri $Installer.URI -OutFile $InstallerFilePath
    }
    $ProgressPreference = $OriginalProgressPreference
}
if ($Upload) {
    if (-not $AzureStorageAccount) {
        throw 'AzureStorageAccount is required when uploading installers.'
    }
    if (-not $AzureStorageContainer) {
        throw 'AzureStorageContainer is required when uploading installers.'
    }
    $AzureStorageContext = New-AzStorageContext -StorageAccountName $AzureStorageAccount -StorageAccountKey $AzureStorageAccountKey
    $InstallerFiles = Get-ChildItem -Path $DownloadPath -Filter '*.msi'
    ForEach ($InstallerFile in $InstallerFiles) {
        Write-Verbose ('Uploading {0} to {1}' -f $InstallerFile, $AzureStorageContainer)
        Set-AzStorageBlobContent -File $InstallerFile -Container $AzureStorageContainer -Context $AzureStorageContext | Out-Null
        if ($CleanUp) {
            Write-Verbose ('Deleting {0}' -f $InstallerFile)
            Remove-Item -Path $InstallerFile
        }
    }
}