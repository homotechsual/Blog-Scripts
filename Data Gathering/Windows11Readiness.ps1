<#
    .SYNOPSIS
        Data Gathering - Windows - Windows 11 Readiness Check
    .DESCRIPTION
        This script will check the current system for Windows 11 readiness. It will check the following: OS Disk Size, Memory Capacity, CPU Clock Speed, CPU Logical Processors, CPU Address Width, CPU Family Type, TPM Version, Secure Boot, and UEFI Firmware.
    .NOTES
        2023-03-26: Fix incorrect variable comparison bugs. Reformat.
        2022-02-16: Fix bug with Secure Boot suitability check, add i7-7820hq on Surface Studio 2 or Precision 5520 as supported CPU outside of CPU family check.
        2022-02-15: Initial version
    .LINK
        Original Source: https://techcommunity.microsoft.com/t5/microsoft-endpoint-manager-blog/understanding-readiness-for-windows-11-with-microsoft-endpoint/ba-p/2770866
    .LINK
        Blog post: https://homotechsual.dev/2022/12/22/NinjaOne-custom-fields-endless-possibilities/
#>
try {
    [int]$MinOSDiskSizeGB = 64
    [int]$MinMemoryGB = 4
    [Uint32]$MinClockSpeedMHz = 1000
    [Uint32]$MinLogicalProcessors = 2
    [Uint16]$MinAddressWidth = 64
    $CPUFamilyType = @'
using Microsoft.Win32;
using System;
using System.Runtime.InteropServices;
public class CpuFamilyResult
{
    public bool IsValid { get; set; }
    public string Message { get; set; }
}
public class CpuFamily
{
    [StructLayout(LayoutKind.Sequential)]
    public struct SYSTEM_INFO
    {
        public ushort ProcessorArchitecture;
        ushort Reserved;
        public uint PageSize;
        public IntPtr MinimumApplicationAddress;
        public IntPtr MaximumApplicationAddress;
        public IntPtr ActiveProcessorMask;
        public uint NumberOfProcessors;
        public uint ProcessorType;
        public uint AllocationGranularity;
        public ushort ProcessorLevel;
        public ushort ProcessorRevision;
    }
    [DllImport("kernel32.dll")]
    internal static extern void GetNativeSystemInfo(ref SYSTEM_INFO lpSystemInfo);
    public enum ProcessorFeature : uint
    {
        ARM_SUPPORTED_INSTRUCTIONS = 34
    }
    [DllImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool IsProcessorFeaturePresent(ProcessorFeature processorFeature);
    private const ushort PROCESSOR_ARCHITECTURE_X86 = 0;
    private const ushort PROCESSOR_ARCHITECTURE_ARM64 = 12;
    private const ushort PROCESSOR_ARCHITECTURE_X64 = 9;
    private const string INTEL_MANUFACTURER = "GenuineIntel";
    private const string AMD_MANUFACTURER = "AuthenticAMD";
    private const string QUALCOMM_MANUFACTURER = "Qualcomm Technologies Inc";
    public static CpuFamilyResult Validate(string manufacturer, ushort processorArchitecture)
    {
        CpuFamilyResult cpuFamilyResult = new CpuFamilyResult();
        if (string.IsNullOrWhiteSpace(manufacturer))
        {
            cpuFamilyResult.IsValid = false;
            cpuFamilyResult.Message = "Manufacturer is null or empty";
            return cpuFamilyResult;
        }
        string registryPath = "HKEY_LOCAL_MACHINE\\Hardware\\Description\\System\\CentralProcessor\\0";
        SYSTEM_INFO sysInfo = new SYSTEM_INFO();
        GetNativeSystemInfo(ref sysInfo);
        switch (processorArchitecture)
        {
            case PROCESSOR_ARCHITECTURE_ARM64:
                if (manufacturer.Equals(QUALCOMM_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                {
                    bool isArmv81Supported = IsProcessorFeaturePresent(ProcessorFeature.ARM_SUPPORTED_INSTRUCTIONS);
                    if (!isArmv81Supported)
                    {
                        string registryName = "CP 4030";
                        long registryValue = (long)Registry.GetValue(registryPath, registryName, -1);
                        long atomicResult = (registryValue >> 20) & 0xF;

                        if (atomicResult >= 2)
                        {
                            isArmv81Supported = true;
                        }
                    }
                    cpuFamilyResult.IsValid = isArmv81Supported;
                    cpuFamilyResult.Message = isArmv81Supported ? "" : "Processor does not implement ARM v8.1 atomic instruction";
                }
                else
                {
                    cpuFamilyResult.IsValid = false;
                    cpuFamilyResult.Message = "The processor isn't currently supported for Windows 11";
                }
                break;
            case PROCESSOR_ARCHITECTURE_X64:
            case PROCESSOR_ARCHITECTURE_X86:
                int cpuFamily = sysInfo.ProcessorLevel;
                int cpuModel = (sysInfo.ProcessorRevision >> 8) & 0xFF;
                int cpuStepping = sysInfo.ProcessorRevision & 0xFF;
                if (manufacturer.Equals(INTEL_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                {
                    try
                    {
                        cpuFamilyResult.IsValid = true;
                        cpuFamilyResult.Message = "";
                        if (cpuFamily >= 6 && cpuModel <= 95 && !(cpuFamily == 6 && cpuModel == 85))
                        {
                            cpuFamilyResult.IsValid = false;
                            cpuFamilyResult.Message = "";
                        }
                        else if (cpuFamily == 6 && (cpuModel == 142 || cpuModel == 158) && cpuStepping == 9)
                        {
                            string registryName = "Platform Specific Field 1";
                            int registryValue = (int)Registry.GetValue(registryPath, registryName, -1);

                            if ((cpuModel == 142 && registryValue != 16) || (cpuModel == 158 && registryValue != 8))
                            {
                                cpuFamilyResult.IsValid = false;
                            }
                            cpuFamilyResult.Message = "PlatformId " + registryValue;
                        }
                    }
                    catch (Exception ex)
                    {
                        cpuFamilyResult.IsValid = false;
                        cpuFamilyResult.Message = "Exception:" + ex.GetType().Name;
                    }
                }
                else if (manufacturer.Equals(AMD_MANUFACTURER, StringComparison.OrdinalIgnoreCase))
                {
                    cpuFamilyResult.IsValid = true;
                    cpuFamilyResult.Message = "";

                    if (cpuFamily < 23 || (cpuFamily == 23 && (cpuModel == 1 || cpuModel == 17)))
                    {
                        cpuFamilyResult.IsValid = false;
                    }
                }
                else
                {
                    cpuFamilyResult.IsValid = false;
                    cpuFamilyResult.Message = "Unsupported Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                }
                break;
            default:
                cpuFamilyResult.IsValid = false;
                cpuFamilyResult.Message = "Unsupported CPU category. Manufacturer: " + manufacturer + ", Architecture: " + processorArchitecture + ", CPUFamily: " + sysInfo.ProcessorLevel + ", ProcessorRevision: " + sysInfo.ProcessorRevision;
                break;
        }
        return cpuFamilyResult;
    }
}
'@
    $OSDriveSize = Get-CimInstance -Class Win32_LogicalDisk -Filter "DeviceID='$($ENV:SystemDrive)'" | Select-Object @{ 
        Name = 'SizeGB'
        Expression = { $_.Size / 1GB -as [int] }
    }
    if ($OSDriveSize.SizeGB -ge $MinOSDiskSizeGB) {
        $OSDriveSizeSuitable = 'Yes'
    } else {
        $OSDriveSizeSuitable = 'No'
    }
    $MemorySize = Get-CimInstance -Class Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum | Select-Object @{
        Name = 'SizeGB'
        Expression = { $_.Sum / 1GB -as [int] }
    }
    if ($MemorySize.SizeGB -ge $MinMemoryGB) {
        $MemorySizeSuitable = 'Yes'
    } else {
        $MemorySizeSuitable = 'No'
    }
    $TPM = Get-Tpm
    if ($TPM.TpmPresent) {
        $TPMVersion = Get-CimInstance -Class Win32_Tpm -Namespace 'root\CIMV2\Security\MicrosoftTpm' | Select-Object -Property SpecVersion
        $TPMMajorVersion = $TPMVersion.SpecVersion.Split(',')[0]
        if ($TPMMajorVersion -ge 2) {
            $TPMSuitable = 'Yes'
        } else {
            $TPMSuitable = 'No'
        }
    } else {
        $TPMSuitable = 'No'
    }
    $ProcessorInformation = Get-CimInstance -ClassName Win32_Processor | Select-Object -Property [a-z]*
    $ProcessorAddressWidth = $ProcessorInformation.AddressWidth
    $ProcessorMaxClockSpeed = $ProcessorInformation.MaxClockSpeed
    $ProcessorNumberOfLogicalProcessors = $ProcessorInformation.NumberOfLogicalProcessors
    $ProcessorManufacturer = $ProcessorInformation.Manufacturer
    $ProcessorArchitecture = $ProcessorInformation.Architecture
    $ProcessorFamily = $ProcessorInformation.Caption
    Add-Type -TypeDefinition $CPUFamilyType
    $CPUFamilyResult = [CpuFamily]::Validate([String]$ProcessorManufacturer, [String]$ProcessorArchitecture)
    $CPUIsSuitable = $CPUFamilyResult.IsValid -and ($ProcessorAddressWidth -ge $MinAddressWidth) -and ($ProcessorMaxClockSpeed -ge $MinClockSpeedMHz) -and ($ProcessorNumberOfLogicalProcessors -ge $MinLogicalProcessors)
    if (-not($CPUIsSuitable)) {
        $SupportedDevices = @('Surface Studio 2', 'Precision 5520')
        $SystemInfo = @(Get-CimInstance -Class Win32_ComputerSystem)[0]
        if ($null -ne $ProcessorInformation) {
            if ($cpuDetails.Name -match 'i7-7820hq cpu @ 2.90ghz') {
                $modelOrSKUCheckLog = $systemInfo.Model.Trim()
                if ($supportedDevices -contains $modelOrSKUCheckLog) {
                    $CPUIsSuitable = $true
                }
            }
        }
    }
    if ($CPUIsSuitable) {
        $CPUSuitable = 'Yes'
    } else {
        $CPUSuitable = 'No'
    }
    try {
        $SecureBootEnabled = Confirm-SecureBootUEFI
    } catch [System.PlatformNotSupportedException] {
        $SecureBootEnabled = $False
    } catch [System.UnauthorizedAccessException] {
        $SecureBootEnabled = $False
    } catch {
        $SecureBootEnabled = $False
    }
    if ($SecureBootEnabled) {
        $SecureBootSuitable = 'Yes'
    } else {
        $SecureBootSuitable = 'No'
    }
    if ($OSDriveSizeSuitable -eq 'Yes' -and $MemorySizeSuitable -eq 'Yes' -and $CPUSuitable -eq 'Yes' -and $TPMSuitable -eq 'Yes' -and $SecureBootSuitable -eq 'Yes') {
        Ninja-Property-Set windows11Capable 'Yes' | Out-Null
    } else {
        Ninja-Property-Set windows11Capable 'No' | Out-Null
    }
    $Windows11CheckDetails = @{
        'OSDriveSizeSuitable' = $OSDriveSizeSuitable
        'OSDriveSize' = $OSDriveSize.SizeGB
        'MemorySizeSuitable' = $MemorySizeSuitable
        'MemorySize' = $MemorySize.SizeGB
        'CPUSuitable' = $CPUSuitable
        'CPUFamily' = $ProcessorFamily
        'TPMSuitable' = $TPMSuitable
        'SecureBootSuitable' = $SecureBootSuitable
    }
    $DetailJson = $Windows11CheckDetails | ConvertTo-Json
    Ninja-Property-Set windows11CheckDetails $DetailJson | Out-Null
} catch {
    Write-Error $_
}