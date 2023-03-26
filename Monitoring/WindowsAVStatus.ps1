<#
    .SYNOPSIS
        Monitoring - Windows - Security Center - AV Status
    .DESCRIPTION
        This script will monitor the status of Windows Security Center integrated antivirus products and report back to NinjaOne.
    .NOTES
        2022-10-05: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/10/05/Monitoring-AV-PowerShell/
#>
[CmdletBinding()]
param()
function ConvertTo-Hex ([Int]$StatusCode) {
    '0x{0:x}' -f $StatusCode
}
function Get-WindowsAVStatus {
    $CIMParameters = @{
        Namespace = 'root/SecurityCenter2'
        ClassName = 'AntivirusProduct'
        ErrorAction = 'Stop'
    }
    $AVProducts = Get-CimInstance @CIMParameters
    $Results = foreach ($AVProduct in $AVProducts) {
        Write-Verbose ('Found {0}' -f $AVProduct.DisplayName)
        $StatusHex = ConvertTo-Hex -StatusCode $AVProduct.ProductState
        $EnabledHex = $StatusHex.Substring(3, 2)
        if ($EnabledHex -match '00|01') {
            Write-Verbose ('{0} is not enabled' -f $AVProduct.DisplayName)
            $Enabled = $False
        } else {
            Write-Verbose ('{0} is enabled' -f $AVProduct.DisplayName)
            $Enabled = $True
        }
        $UpToDateHex = $StatusHex.Substring(5)
        if ($UpToDateHex -eq '00') {
            Write-Verbose ('{0} is up-to-date' -f $AVProduct.DisplayName)
            $UpToDate = $True
        } else {
            Write-Verbose ('{0} is not up-to-date' -f $AVProduct.DisplayName)
            $UpToDate = $False
        }
        @{
            Product = $AVProduct.DisplayName
            Enabled = $Enabled
            UpToDate = $UpToDate
            Path = $AVProduct.PathToSignedProductExe
        }
    }
    # This part is somewhat specific to NinjaOne - feel free to reach out to @homotechsual on MSPs R Us or MSP Geek if you want a hand getting this going for your RMM.
    Ninja-Property-Set detailedAVStatus ($Results | ConvertTo-Json)
    if (@($Results.Enabled -eq $False).Count) {
        Exit 1
    } elseif (@($Results.UpToDate -eq $False).Count) {
        Exit 2
    } else {
        Exit 0
    }
}
Get-WindowsAVStatus