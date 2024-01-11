<#
    .SYNOPSIS
        Software Deployment - Generic - New Teams
    .DESCRIPTION
        Uses the Teams Bootstrapper executable to install New Teams machine-wide. Use the `-Offline` switch to install using the MSIX File. Use `-Uninstall` to remove machine-wide provisioning of New Teams.
    .NOTES
        2024-01-11: Fix incorrect syntax for if condition (thanks Jayrod) and silence progress bar for Invoke-WebRequest.
        2024-01-10: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2023/01/10/Deploy-New-Teams/
#>
[CmdletBinding()]
param(
    [System.IO.DirectoryInfo]$TeamsFolder = 'C:\RMM\Teams',
    [System.IO.FileInfo]$MSIXPath,
    [Switch]$Offline,
    [Switch]$Uninstall
)
begin {
    $ProgressPreference = 'SilentlyContinue'
    # Make sure the folder exists to hold the downloaded files.
    if (-not (Test-Path -Path $TeamsFolder)) {
        New-Item -Path $TeamsFolder -ItemType Directory | Out-Null
    }
    # Source: https://learn.microsoft.com/en-us/microsoftteams/new-teams-bulk-install-client
    $TeamsInstallerDownloadId = 2243204
    if ($Offline) {
        $TeamsMSIXDownloadIds = @{
            'x86' = 2196060
            'x64' = 2196106
            'ARM64' = 2196207
        }
        $Is64Bit = [System.Environment]::Is64BitOperatingSystem
        $IsArm = [System.Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE') -like 'ARM*'
        if ($IsArm) {
            $TeamsMSIXDownloadId = $TeamsMSIXDownloadIds['ARM64']
        } elseif ($Is64Bit) {
            $TeamsMSIXDownloadId = $TeamsMSIXDownloadIds['x64']
        } else {
            $TeamsMSIXDownloadId = $TeamsMSIXDownloadIds['x86']
        }
        $TeamsMSIXDownloadUri = ('https://go.microsoft.com/fwlink/p/?linkid={0}' -f $TeamsMSIXDownloadId)
    }
    $TeamsInstallerDownloadUri = ('https://go.microsoft.com/fwlink/p/?linkid={0}' -f $TeamsInstallerDownloadId)
    # Define our ProcessInvoker function.
    function ProcessInvoker ([System.IO.FileInfo]$CommandPath, [String[]]$CommandArguments) {
        $PSI = New-Object System.Diagnostics.ProcessStartInfo
        $PSI.FileName = (Resolve-Path $CommandPath)
        $PSI.RedirectStandardError = $true
        $PSI.RedirectStandardOutput = $true
        $PSI.UseShellExecute = $false
        $PSI.Arguments = $CommandArguments -join ' '
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $PSI
        $Process.Start() | Out-Null
        $ProcessOutput = [PSCustomObject]@{
            STDOut = $Process.StandardOutput.ReadToEnd()
            STDErr = $Process.StandardError.ReadToEnd()
            ExitCode = $Process.ExitCode
        }
        $Process.WaitForExit()
        return $ProcessOutput
    }
}
process {
    # Download Teams installer
    $TeamsInstallerFile = Join-Path -Path $TeamsFolder -ChildPath 'TeamsBootstrapper.exe'
    Write-Verbose ('Downloading Teams installer to {0}' -f $TeamsInstallerFile)
    Invoke-WebRequest -Uri $TeamsInstallerDownloadUri -OutFile $TeamsInstallerFile
    if ($Offline -and (-not $MSIXPath)) {
        # Download Teams MSIX
        $TeamsMSIXFile = Join-Path -Path $TeamsFolder -ChildPath 'Teams.msixbundle'
        if (-not (Test-Path -Path $TeamsMSIXFile)) {
            Write-Verbose ('Downloading Teams MSIX to {0}' -f $TeamsMSIXFile)
            Invoke-WebRequest -Uri $TeamsMSIXDownloadUri -OutFile $TeamsMSIXFile
        }
    } elseif ($Offline -and $MSIXPath) {
        $TeamsMSIXFile = Resolve-Path $MSIXPath
    }
    if ($Offline) {
        # Install Teams MSIX with the bootstrapper
        Write-Verbose 'Installing Teams MSIX with the bootstrapper'
        $Output = ProcessInvoker -CommandPath $TeamsInstallerFile -CommandArguments @('-p', '-o', ('{0}' -f $TeamsMSIXFile))
    } else {
        # Install Teams with the bootstrapper
        Write-Verbose 'Installing Teams with the bootstrapper'
        $Output = ProcessInvoker -CommandPath $TeamsInstallerFile -CommandArguments @('-p') -Wait -NoNewWindow
    }
    if ($Uninstall) {
        # Uninstall Teams
        Write-Verbose 'Uninstalling Teams'
        $Output = ProcessInvoker -CommandPath $TeamsInstallerFile -CommandArguments @('-x') -Wait -NoNewWindow
    }
    $OutputObject = $Output.STDOut | ConvertFrom-Json
    Write-Verbose $Output
    if ($OutputObject.Success) {
        Write-Verbose 'Teams installed successfully'
    } else {
        Write-Error ('Teams installation failed with error code {0}' -f $OutputObject.ErrorCode)
    }
}
end {
    $ProgressPreference = 'Continue'
}