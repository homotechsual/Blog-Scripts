<#
    .SYNOPSIS
        Windows 10 Feature Update installer.
    .DESCRIPTION
        This script downloads and silently executes the Windows 10 Upgrade Assistant to install the latest Windows 10 Feature Update.
        You can use your RMM or other environment to populate the variables 'featureUpgradeDir' and/or 'featureUpgradeFile' or use the defaults.
    .LINK
        Blog: Not blogged yet.
#>
Begin {
    if (![String]::IsNullOrWhiteSpace($ENV:FeatureUpgradeDir)) {
        $FeatureUpgradeDir = $ENV:FeatureUpgradeDir
    } else {
        $FeatureUpgradeDir = 'C:\RMM\FeatureUpdates'
    }
    if (![String]::IsNullOrWhiteSpace($ENV:FeatureUpgradeFile)) {
        $FeatureUpgradeFile = $ENV:featureUpgradeFile
    }
    if (!(Test-Path $FeatureUpgradeDir)) {
        New-Item $FeatureUpgradeDir -Force -ErrorAction SilentlyContinue -ItemType Directory | Out-Null
    }
    if (-Not (Test-Path $FeatureUpgradeFile)) {
        $FeatureUpgradeFile = Join-Path -Path $FeatureUpgradeDir -ChildPath 'Windows11InstallationAssistant.exe'
    }
    $LoggingDir = Join-Path -Path $FeatureUpgradeDir -ChildPath 'Logs'
    if (!(Test-Path $LoggingDir)) {
        New-Item $LoggingDir -Force -ErrorAction SilentlyContinue -ItemType Directory | Out-Null
    }
    $DownloadURI = 'https://go.microsoft.com/fwlink/?LinkID=799445'  
    Try {
        Invoke-WebRequest -Uri $DownloadURI -OutFile $FeatureUpgradeFile
    } Catch {
        Write-Error 'Could not download the Update Assistant.'
        Exit 1
    }
}
Process {
    Try {
        
        Start-Process -FilePath $featureUpgradeFile -ArgumentList @('/quietinstall', '/skipeula', '/auto', 'upgrade', '/copylogs', $LoggingDir) -Wait -NoNewWindow
    } Catch {
        Write-Host "The Windows 11 Installation Assistant failed."
        Exit 1
    }
}