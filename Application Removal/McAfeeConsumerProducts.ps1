<#
    .SYNOPSIS
        Application Removal - Windows - McAfee Consumer Products
    .DESCRIPTION
        This script is used to remove (usually pre/OEM installed) McAfee Consumer products from Windows machines. It includes removal of McAfee store apps. It uses an old version of MCPR - McAfee's removal tool which you'll find in this repository in the supporting files folder. You'll need to host this somewhere the script can download it and put the URL into the script where you see $MCPRURL below. This will require a reboot to fully remove McAfee!
    .NOTES
        2025-01-18: Make sure we kill new MSI based packages.
        2024-11-09: Store app removal refactor.
        2023-10-01: Force stop processes.
        2023-09-18: Update MCPR. New switces.
        2023-08-11: Update MCPR.
        2023-06-10: Initial version
    .LINK
        Blog post: Not blogged yet
#>
# Variables
$MCPRURL = '<YOURMCPRZIPURLHERE>'
$ToolsDirectory = 'C:\RMM\Tools'
$MCPRDirectory = 'C:\RMM\Tools\MCPR'
$MCPRZipFile = Join-Path -Path $ToolsDirectory -ChildPath 'MCPR.zip' 
$MCPRFile = Join-Path -Path $MCPRDirectory -ChildPath 'mccleanup.exe'

$OriginalInformationPreference = $InformationPreference
$OriginalErrorActionPreference = $ErrorActionPreference
$InformationPreference = 'SilentlyContinue'
# Functions

function _killMcAfeeProcesses() {
    # These processes seem to be a bit "sticky" sometimes so we'll force them to quit.
    $ProcessNames = @(
        'sediag',
        'mfevtps',
        'mfemms',
        'pefservice'
        'mcuicnt',
        'modulecoreservice',
        'mccleanup'
    )
    foreach ($ProcessName in $ProcessNames) {
        Add-Type -Name Kernel -Namespace PInvokes -MemberDefinition '[DllImport("kernel32")] public static extern int TerminateProcess(IntPtr hProcess, uint uExitCode);'
        try {
            $Process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
            if ($Process) {
                $ProcessHandle = $Process.Handle
                [PInvokes.Kernel]::TerminateProcess($ProcessHandle, 1)
            }
        } catch {
            Write-Warning ('Process {0} not running.' -f $ProcessName)
        }
    }
}

function _removeMcAfeeStoreApps() {
    Get-AppxPackage -AllUsers | Where-Object { $_.Name -like '*McAfee*' } | Remove-AppxPackage -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -Like '*McAfee*' } | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
}

try {
    _killMcAfeeProcesses
} catch {
    Write-Warning 'Failed to kill processes.'
}

try {
    _removeMcAfeeStoreApps
} catch {
    Write-Warning 'Failed to remove Store Apps.'
}

if ( -not ( Test-Path -Path $ToolsDirectory ) ) {
    New-Item -ItemType Directory -Path $ToolsDirectory -Force
}
if ( -not ( Test-Path -Path $MCPRZipFile ) ) {
    Write-Information '[Download] Fetching MCPR...'
    try {
        # We don't download this from McAfee any more since they changed the most recent version to encode the parameters for `mccleanup.exe` and whilst we've been able to decode them, it's not strictly needed and we can just use the version we have.
        Invoke-WebRequest -Uri $MCPRURL -OutFile $MCPRZipFile
    } catch {
        throw 'Failed to download MCPR'
    }
}

if ( Test-Path -Path $MCPRZipFile) {
    Write-Information '[Extract] Extracting MCPR...'
    try {
        Expand-Archive -LiteralPath $MCPRZipFile -DestinationPath $ToolsDirectory
    } catch {
        throw 'Failed to extract MCPR'
    }
}

if ( Test-Path -Path $MCPRFile ) {
    $UninstallPath = $MCPRFile
    $UninstallArguments = '-p StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE -v -s'
    Write-Output 'MCPR may take quite a while to run. Please wait...' | Out-Default
} else {
    Write-Warning 'MCPR mccleanup.exe file not found!' | Out-Default
    Exit 1
}

Write-Information "[Job] Running:`n$($UninstallPath) $($UninstallArguments)" | Out-Default

try {
    $UninstallPathValid = Test-Path ( ( ( Get-Command ($UninstallPath.TrimStart("`"`' " ).TrimEnd("`"`' " )) -ErrorAction SilentlyContinue ) | Select-Object -First 1 ).Definition  ) -ErrorAction SilentlyContinue
} catch {
    Write-Warning "Failed to detect valid commmand.`n`nUninstall Path:`n$($UninstallPath)" | Out-Default
}

$ErrorActionPreference = 'SilentlyContinue'
if ( $UninstallArguments -and $UninstallPathValid ) {
    $Process = Start-Process $UninstallPath -ArgumentList $UninstallArguments -PassThru -Wait -NoNewWindow 
    $ProcessHandle = $Process.Handle
} else {
    Write-Warning "$($UninstallPath) not found!" | Out-Default
    Exit 1
}
$ErrorActionPreference = $OriginalErrorActionPreference
if ( $ProcessHandle ) {
    if ( $Process.ExitCode -ne 0 ) {
        $ProcessResult = ' McAfee Consumer programs might not have been removed. Check whether the program has uninstalled - you may need to remove manually.'
        if ( $Process.ExitCode -eq 3010 ) {
            $ProcessResult = ", Uninstalled. Reboot Required.`n"
        }
        if ( $Process.ExitCode -eq 1605 ) {
            $ProcessResult = ", This action is only valid for products that are currently installed. Program was already removed.`n"
        }
        Write-Warning "ExitCode: $($Process.ExitCode)$($ProcessResult)" | Out-Default
    } else {
        Write-Output 'Removed McAfee Consumer programs.' | Out-Default
    }
}


$InstalledPrograms = (Get-Package | Where-Object -Property 'Name' -Like '*McAfee*')
$InstalledPrograms | ForEach-Object {
    Write-Output "Attempting to uninstall: [$($_.Name)]..."
    $UninstallCommand = $_.String
    Try {
        if ($UninstallCommand -match '^msiexec*') {
            #Remove msiexec as we need to split for the uninstall
            $UninstallCommand = $UninstallCommand -replace "msiexec.exe", ""
            $UninstallCommand = $UninstallCommand + " /quiet /norestart"
            $UninstallCommand = $UninstallCommand -replace "/I", "/X "
            #Uninstall with string2 params
            Start-Process 'msiexec.exe' -ArgumentList $UninstallCommand -NoNewWindow -Wait
        } else {
            Start-Process $UninstallCommand -Wait
        }
        Write-Output "Successfully uninstalled: [$($_.Name)]"
    }
    Catch { Write-Warning -Message "Failed to uninstall: [$($_.Name)]" }
}

$SafeConnects = Get-ChildItem -Path @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall') | Get-ItemProperty | Where-Object { $_.DisplayName -match "McAfee Safe Connect" } | Select-Object -Property UninstallString
ForEach ($SafeConnect in $SafeConnects) {
    If ($SafeConnect.UninstallString) {
        Start-Process ('{0}/quiet /norestart' -f $SafeConnect.UninstallString)
    }
}
if (Test-Path -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\McAfee") {
    Remove-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\McAfee" -Recurse -Force
}
if (Test-Path -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS") {
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\McAfee.WPS" -Recurse -Force
}
Get-AppxProvisionedPackage -Online | Where-Object -Property 'DisplayName' -Eq "McAfeeWPSSparsePackage" | Remove-AppxProvisionedPackage -Online -AllUsers

Set-Location $ToolsDirectory
Remove-Item $MCPRDirectory -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
Remove-Item $MCPRZipFile -Force -ErrorAction SilentlyContinue | Out-Null

$InformationPreference = $OriginalInformationPreference
