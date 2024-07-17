#!/bin/bash
# Make a directory to hold our installer(s).
mkdir -p "/Library/RMM/Installers"
# Change to that directory.
cd "/Library/RMM/Installers" || returngit c

# Download the Zoom installer. Use `-L` to follow redirects and `-s` to silence output.
curl -O -L -s "https://zoom.us/client/latest/ZoomInstallerIT.pkg"

# Install Zoom using the package installer
sudo installer -pkg "/Library/RMM/Installers/ZoomInstallerIT.pkg" -target /

# Clean up the downloaded installer
rm "/Library/RMM/Installers/ZoomInstallerIT.pkg"

# Setup our config for Zoom using plistbuddy.
## Disable Zoom onboarding on install.
/usr/libexec/PlistBuddy -c "Add :DisableZoomOnboarding bool true" "/Library/Preferences/us.zoom.config.plist"
## Disable the Discover What's New window.
/usr/libexec/PlistBuddy -c "Add :DisableDiscoverWhatsNew bool true" "/Library/Preferences/us.zoom.config.plist"
## Force-enable Auto Update
/usr/libexec/PlistBuddy -c "Add :AU2_EnableAutoUpdate bool true" "/Library/Preferences/us.zoom.config.plist"
## Set update channel to the Fast ring.
/usr/libexec/PlistBuddy -c "Add :AU2_SetUpdateChannel bool true" "/Library/Preferences/us.zoom.config.plist"
## Disable Google logins.
/usr/libexec/PlistBuddy -c "Add :NoGoogle bool true" "/Library/Preferences/us.zoom.config.plist"
## Disable Facebook logins.
/usr/libexec/PlistBuddy -c "Add :NoFacebook bool true" "/Library/Preferences/us.zoom.config.plist"
## Disable user signups from within the app.
/usr/libexec/PlistBuddy -c "Add :DisableUserSignUp bool true" "/Library/Preferences/us.zoom.config.plist"

# Print success message
echo "Zoom installed and configuration applied successfully!"