<#
    .SYNOPSIS
        Ninja Scripts - Safe Mode Services
    .DESCRIPTION
        This script will allow the NinjaOne agent and NinjaOne remote services to run in Safe Mode with Networking.
    .NOTES
        2025-01-16 - Add additional certificate signers.
        2025-01-15 - Initial version
    .LINK
        Blog post: Not blogged yet
#>
$ExpectedSigners = @(
    'CN=NinjaOne LLC, O=NinjaOne LLC, L=Oldsmar, S=Florida, C=US, SERIALNUMBER=6821849, OID.2.5.4.15=Private Organization, OID.1.3.6.1.4.1.311.60.2.1.2=Delaware, OID.1.3.6.1.4.1.311.60.2.1.3=US',
    'CN="NinjaRMM, LLC", O="NinjaRMM, LLC", S=California, C=US',
    'CN=Bitdefender SRL, OU=DEVSUP EPSINTEGRATION", O=Bitdefender SRL, L=Bucharest, C=RO',
    'CN=Bitdefender SRL, OU=DEVSUP EPSINSTALLER, O=Bitdefender SRL, L=Bucharest, C=RO',
    'CN="OPSWAT, Inc.", O="OPSWAT, Inc.", L=San Francisco, S=California, C=US'
)
$ProgramFilesFolder = Get-ChildItem @('HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\') -ErrorAction SilentlyContinue | Where-Object -Property Name -Like '*NinjaRMMAgent*' | Get-ItemPropertyValue -Name 'InstallLocation'
$ProgramDataFolder = Join-Path -Path $ENV:ProgramData -ChildPath 'NinjaRMMAgent'
$NinjaPaths = @($ProgramFilesFolder, $ProgramDataFolder)
$Signatures = foreach ($Path in $NinjaPaths) {
    Write-Host ('Checking files in {0}' -f $Path)
    Get-ChildItem -Path $Path -Recurse -Filter '*.exe' | Get-AuthenticodeSignature
}
$UnsignedFiles = [System.Collections.Generic.List[PSObject]]::new()
$ImproperlySignedFiles = [System.Collections.Generic.List[PSObject]]::new()
# Loop through the files and check if they are signed and if they are signed with the expected certificate.
foreach ($Signature in $Signatures) {
    if (($Signature.Status -ne 'Valid') -or ($Signature.StatusMessage -ne 'Signature verified.')) {
        $UnsignedFiles.Add($Signature)
    } elseif ($Signature.SignerCertificate.Subject -notin $ExpectedSigners) {
        $ImproperlySignedFiles.Add($Signature)
    }
}
# If there are unsigned files, output them.
if ($UnsignedFiles) {
    Write-Error 'Unsigned files found:'
    $UnsignedFiles | ForEach-Object {
        Write-Error ('{0} ({1})' -f $_.Path, $_.Status)
    }
}
# Ensure the files are signed with NinjaOne's certificate.
if ($ImproperlySignedFiles) {
    Write-Error 'Files signed with an unexpected certificate found:'
    $ImproperlySignedFiles | ForEach-Object {
        Write-Error ('{0} ({1})' -f $_.Path, $_.SignerCertificate.Subject)
    }
}
# If there are any errors, exit with a non-zero exit code.
if ($UnsignedFiles.Count -gt 0 -or $ImproperlySignedFiles.Count -gt 0) {
    exit 1
} else {
    Write-Host 'All files are signed with a valid and expected certificate.'
    exit 0
}