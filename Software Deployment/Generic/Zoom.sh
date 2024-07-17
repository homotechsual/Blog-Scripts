#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Make a directory to hold our installer(s).
mkdir -p "/Library/RMM/Installers"

# Change to that directory.
cd "/Library/RMM/Installers" || { echo "Failed to change directory to /Library/RMM/Installers"; exit 1; }

# Download the Zoom installer. Use `-L` to follow redirects and `-s` to silence output.
curl -O -L -s "https://zoom.us/client/latest/ZoomInstallerIT.pkg"

# Verify the installer was downloaded
if [ ! -f "ZoomInstallerIT.pkg" ]; then
    echo "Zoom installer download failed."
    exit 1
fi

# Install Zoom using the package installer
sudo installer -pkg "ZoomInstallerIT.pkg" -target /

# Clean up the downloaded installer
rm "ZoomInstallerIT.pkg"

# Setup our config for Zoom using plistbuddy.
# Use `/usr/libexec/PlistBuddy` to avoid potential path issues.

# Define the plist file path
PLIST="/Library/Preferences/us.zoom.config.plist"

# Function to add or update plist key
update_plist() {
    /usr/libexec/PlistBuddy -c "Set $1 $2" "$PLIST" || /usr/libexec/PlistBuddy -c "Add $1 $3 $2" "$PLIST"
}

## Disable Zoom onboarding on install.
update_plist ":DisableZoomOnboarding" "true" "bool"
## Disable the Discover What's New window.
update_plist ":DisableDiscoverWhatsNew" "true" "bool"
## Force-enable Auto Update
update_plist ":AU2_EnableAutoUpdate" "true" "bool"
## Set update channel to the Fast ring.
update_plist ":AU2_SetUpdateChannel" "true" "bool"
## Disable Google logins.
update_plist ":NoGoogle" "true" "bool"
## Disable Facebook logins.
update_plist ":NoFacebook" "true" "bool"
## Disable user signups from within the app.
update_plist ":DisableUserSignUp" "true" "bool"

# Print success message
echo "Zoom installed and configuration applied successfully!"
