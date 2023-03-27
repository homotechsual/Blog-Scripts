<#
    .SYNOPSIS
        Monitoring - Windows - Security Center - AV Status
    .DESCRIPTION
        This script will monitor the status of Windows Security Center integrated antivirus products and report back to NinjaOne.
    .NOTES
        2023-03-27: More accurate interpretation of ProductState
        2022-10-05: Initial version
    .LINK
        Blog post: https://homotechsual.dev/2022/10/05/Monitoring-AV-PowerShell/
#>
[CmdletBinding()]
param()
[Flags()] enum ProductState {
    Inactive = 0x0000
    Active = 0x1000
    Snoozed = 0x2000
    Expired = 0x3000
}
[Flags()] enum SignatureStatus {
    UpToDate = 0x00
    OutOfDate = 0x10
}
[Flags()] enum ProductOwner {
    NonMicrosoft = 0x000
    Microsoft = 0x100
}
[Flags()] enum ProductFlags {
    SignatureStatus = 0x000000F0
    ProductOwner = 0x00000F00
    ProductState = 0x0000F000
}
function Get-WindowsAVStatus {
    $CIMParameters = @{
        Namespace = 'root/SecurityCenter2'
        ClassName = 'AntivirusProduct'
        ErrorAction = 'Stop'
    }
    $AVProducts = Get-CimInstance @CIMParameters
    [UInt32]$ProductState = $AVProduct.productState
    $Results = foreach ($AVProduct in $AVProducts) {
        $AVProductJson = $AVProduct | ConvertTo-Json
        Write-Verbose ('Found {0}' -f $AVProduct.DisplayName)
        Write-Debug ('ProductState: {0}' -f $ProductState)
        Write-Debug ('Evaluated signature status: {0}' -f $([SignatureStatus]([UInt32]$ProductState -band [ProductFlags]::SignatureStatus)))
        Write-Debug ('Evaluated product owner: {0}' -f $([ProductOwner]([UInt32]$ProductState -band [ProductFlags]::ProductOwner)))
        Write-Debug ('Evaluated product state: {0}' -f $([ProductState]([UInt32]$ProductState -band [ProductFlags]::ProductState)))
        if ($([UInt32]$ProductState -band [ProductFlags]::ProductState) -eq [ProductState]::Active) {
            Write-Verbose ('{0} is active' -f $AVProduct.DisplayName)
            $Enabled = $True
        } else {
            Write-Verbose ('{0} is inactive' -f $AVProduct.DisplayName)
            $Enabled = $False
        }
        if ( $([UInt32]$ProductState -band [ProductFlags]::SignatureStatus) -eq [SignatureStatus]::UpToDate) {
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
    Write-Output $Results
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