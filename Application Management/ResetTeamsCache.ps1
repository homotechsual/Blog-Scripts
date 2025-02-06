# Check if the script is running as NT/SYSTEM
if ([Security.Principal.WindowsIdentity]::GetCurrent().Name -eq "NT AUTHORITY\SYSTEM") {
    Write-Host "Script is running as NT AUTHORITY\SYSTEM. Exiting..."
    exit 1
}
# Get New Teams process(es).
$TeamsProcesses = Get-Process -Name 'ms-teams' -ErrorAction SilentlyContinue
if (!$TeamsProcesses) {
    Write-Host "No Teams processes found."
}
# Loop over any Teams processes, kill them, wait for them to end and then ensure they are killed - limit to 30 seconds to avoid hanging.
$i = 0
do {
    if ($TeamsProcesses) {
        Write-Host "Killing Teams processes."
        $TeamsProcesses | Stop-Process -Force
        Start-Sleep -Seconds 5
        $TeamsProcesses = Get-Process -Name 'ms-teams' -ErrorAction SilentlyContinue
        $i+=5
    } else {
        Write-Host "Teams processes killed."
    }
} while ($TeamsProcesses -and $i -lt 30)
# Get the Teams package directory path.
$TeamsPackagePath = Join-Path $ENV:LOCALAPPDATA -ChildPath 'Packages\MSTeams_8wekyb3d8bbwe'
# Check if the Teams package directory exists.
if (Test-Path $TeamsPackagePath) {
    Write-Host "Teams package directory found."
    # Get children of the Teams package directory.
    $TeamsPackageChildren = Get-ChildItem -Path $TeamsPackagePath
    # Check if there are any children in the Teams package directory.
    if ($TeamsPackageChildren) {
        Write-Host "Teams package directory has children."
        # Remove the Teams package directory children, leaving the directory itself.
        foreach ($Child in $TeamsPackageChildren) {
            Write-Host "Removing Teams package directory child: $($Child.FullName)"
            Remove-Item -Path $Child.FullName -Recurse -Force
        }
    } else {
        Write-Host "Teams package directory is empty."
    }
} else {
    Write-Host "Teams package directory not found."
}
# Restart Teams
Start-Process -FilePath (Join-Path -Path $ENV:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\ms-teams.exe') -NoNewWindow
