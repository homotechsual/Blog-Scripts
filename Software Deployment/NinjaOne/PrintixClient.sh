#!/bin/bash
# SYNOPSIS
## Software Deployment - NinjaOne - Printix Client
# DESCRIPTION
## Uses documentation fields to pull client specific Printix information to download that client's installer from Printix and install it on the endpoint.
# NOTES
## 2025-01-14: Skip installation if the skipPrintixInstall Ninja Custom Field is set.
## 2025-01-10: Initial version
# LINK
## Blog post: https://homotechsual.dev/2024/01/10/Deploy-Printix-NinjaOne/

# Define initial variables
softwareName="Printix Client"
logMetaDir="/Library/Logs/MJCO/RMM/$softwareName"
log="$logMetaDir/$softwareName.log"
# Ninja Custom Fields
ninjaCLI="$NINJA_DATA_PATH/ninjarmm-cli"
# Skip installation with a 0 exit code if the skipPrintixInstall Ninja Custom Field is set to 1.
skipPrintixInstall=$("$ninjaCLI" "get" "skipPrintixInstall")
if [ "$skipPrintixInstall" == "1" ]; then
    echo "$(date) | INFO: Printix install skipped due to presence of custom field on device."
    exit 0
fi
# Get the document template name, if passed as an argument or environment variable. Environment variable takes precedence if both are set.
if [ -n "$1" ]; then
    documentTemplateName="$1"
elif [ -n "$NINJA_DOCUMENT_TEMPLATE_NAME" ]; then
    documentTemplateName="$NINJA_DOCUMENT_TEMPLATE_NAME"
else
    documentTemplateName="Integration Identifiers"
fi
printixTenantId=$("$ninjaCLI" "get" "$documentTemplateName" "printixTenantId")
printixTenantDomain=$("$ninjaCLI" "get" "$documentTemplateName" "printixTenantDomain")
# Short circuit if the Ninja Custom Fields are not set
if [ -z "$printixTenantId" ] || [ -z "$printixTenantDomain" ]; then
    echo "$(date) | WARN: Ninja Custom Fields not set. Exiting."
    exit 0
fi
# Define variables using Ninja Custom Field values
echo "$(date) | Found Printix Tenant: $printixTenantId ($printixTenantDomain)"
softwarePKGDownloadURL="https://api.printix.net/v1/software/tenants/$printixTenantId/appl/CLIENT/os/MAC/type/DMG"
pkgOutputPath="/Users/Shared/Printix Client_{$printixTenantDomain}_{$printixTenantId}.pkg"
# Check if the log directory has been created
if [ -d "$logMetaDir" ]; then
    ## Already created
    echo "$(date) | Log directory already exists at: $logMetaDir"
else
    ## Create the log directory
    echo "$(date) | Creating log directory at: $logMetaDir"
    mkdir -p "$logMetaDir"
fi
# Start logging
exec &> >(tee -a "$log")
# Function to extract a PKG from a DMG
extract_pkg_from_dmg() {
    local dmgPath="$1"
    local pkgPath="$2"
    # Mount the DMG and capture the resulting mount point using grep and awk
    local dmgMountPoint
    dmgMountPoint=$(hdiutil attach "$dmgPath" | grep "/Volumes/" | awk '{for (i=3; i<=NF; i++) printf $i " "; print ""}')
    # Strip any leading or trailing whitespace
    dmgMountPoint=$(echo "$dmgMountPoint" | xargs)
    # Find the PKG in the mounted DMG
    local pkgPathDmg
    pkgPathDmg=$(find "$dmgMountPoint" -name "*.pkg" -type f)
    # Copy the PKG to the specified location
    cp "$pkgPathDmg" "$pkgPath"
    # Unmount the DMG
    hdiutil detach "$dmgMountPoint" -quiet
    # Return the path to the PKG
    echo "$pkgPath"
}
# Begin Script Body
echo ""
echo "#####################################################################"
echo "# $(date) | Starting install of $softwareName"
echo "#####################################################################"
echo ""
# Download the software
curl -L -o "/Users/Shared/$softwareName.dmg" "$softwarePKGDownloadURL" -H "Accept: application/octet-stream" -sS
pkgFile=$(extract_pkg_from_dmg "/Users/Shared/$softwareName.dmg" "$pkgOutputPath")
sudo installer -pkg "$pkgFile" -target /