#!/bin/bash
# SYNOPSIS
## Utilities - MacOS - Uptime Reboot Prompt
# DESCRIPTION
## This script will force restart the Mac if it has been online for more than a specified number of days. This defaults to 14 days. This script will also prompt the user to restart their Mac if it has been online for more than half the specified number of days but less than the full number of days.
# NOTES
## 2024-02-04: Initial version
# LINK
## Not blogged yet.
# Define the currently logged in user
getLoggedInUser() {
	echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }'
}
# Get the currently logged in user
loggedInUser=$(getLoggedInUser)
if [[ $loggedInUser != "" ]]; then
    loggedInUserId=$(id -u "$loggedInUser")
    echo "User $loggedInUser is logged in with ID $loggedInUserId."
fi

# Define max uptime in days, pull from Ninja Script Variable if set (maxUptime), otherwise use $1 if set, otherwise default to 14 days
if [ -n "$maxUptime" ]; then
    maxAllowedUptime=$maxUptime
elif [ -n "$1" ]; then
	maxAllowedUptime=$1
else
	maxAllowedUptime=14
fi
# Delay in seconds before forcing a restart
preRebootTimeout=60
# Get the Mac OS build number
macOSBuild=$(/usr/bin/sw_vers -buildVersion)
# Get the first two characters of the build number to determine the major version
macOSMajor=$(echo "$macOSBuild" | cut -c 1-2)

# Set the AppName based on the running applications - prefer the NinjaOne Dialog app (njdialog) if it's running, then NinjaOne agent (ninjarmm-macagent), otherwise Finder.
if pgrep "njdialog"
then
	notificationAppName="njdialog"
elif pgrep -fa "ninjarmm-macagent"
then
	notificationAppName="ninjarmm-macagent"
else
	notificationAppName="Finder"
fi

echo "Using $notificationAppName for notifications."

# Function to trigger a graceful restart
gracefulRestart(){
	echo "Triggering graceful system restart."
	osascript <<EOF
tell application "System Events"
    set appsToQuit to name of every application process whose visible is true and name is not "Finder"
end tell
repeat with appToQuit in appsToQuit
	try
		with timeout of ${preRebootTimeout} seconds
			quit application appToQuit
		end timeout
	end try
end repeat
with timeout of ${preRebootTimeout} seconds
	tell application "Finder" to restart
end timeout
EOF
 	shutdown -r now
}

# Function to prompt the user to restart their Mac for uptime
warningUserPrompt(){
	userResponse=$( launchctl asuser $loggedInUserId /usr/bin/osascript <<EOF
set buttonResponse to button returned of (display alert "Uptime Warning" message "Your Mac has been online for $currentUptime days without rebooting. Please restart soon!" buttons {"Restart Now", "Restart Later"} default button "Restart Later")
return buttonResponse
EOF
)
	if [[ "$userResponse" = "Restart Now" ]]
	then
		echo "Attempting \"graceful\" restart."
        gracefulRestart
	fi	
}

# Function to inform the user that their Mac will be restarted
forcefulUserPrompt(){
    launchctl asuser $loggedInUserId /usr/bin/osascript <<EOF
display alert "Restarting Your Mac" message "Your Mac has been online for more than the permitted $maxAllowedUptime days without rebooting. A restart will occur in $preRebootTimeout seconds." buttons {"Restart Now"} default button "Restart Now" giving up after $preRebootTimeout
EOF
	gracefulRestart
}

# Function to prompt the user to restart their Mac for pending updates
installUpdatesUserPrompt(){
	userResponse=$( launchctl asuser $loggedInUserId /usr/bin/osascript <<EOF
set buttonResponse to button returned of (display alert "Update Warning" message "Your Mac has installed updates which require a restart to complete." buttons {"Restart Now", "Restart Later"} default button "Restart Later")
return buttonResponse
EOF
)
	if [[ "$userResponse" = "Restart Now" ]]
	then
		echo "Attempting a \"graceful\" restart."
		gracefulRestart
	fi	
}

# Check for pending updates.
# A build prefix of 19 equates to macOS 10.15 Catalina
if [[ $macOSMajor -lt 19 ]]
then
	# Check for pending updates using the updates index plist - required for macOS 10.15 and earlier.
	updatesPendingReboot=$(defaults read /Library/Updates/index.plist InstallAtLogout | grep -c "[A-Za-z0-9]")
else 
	# Check for pending updates using the MobileAsset directory - required for macOS 11 and later. This is basically counting downloaded update assets.
	updatesPendingReboot=$(find /System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate/ -type d -d 1 | grep -c -i asset)
fi

# Get the current uptime in days
rawMacUptime="$(uptime | grep day)"
if [[ -n "$rawMacUptime" ]]; then
    currentUptime=$(echo "$rawMacUptime" | awk '{print $3}')
else
    currentUptime=0
fi

echo "Mac uptime: $currentUptime days."
echo "Warning days: $((maxUptime/2))"
echo "Force days: $maxUptime"

# If no user is logged in and the uptime is greater than half the max allowed uptime, force a restart now.
if [[ $loggedInUser == "" ]] && [[ $currentUptime -ge $(($maxAllowedUptime/2)) ]]; then
    echo "No user logged in, forcing restart."
    shutdown -r now
fi

if [ $currentUptime -ge $maxAllowedUptime ]; then
    # Force the restart if the uptime is greater than the max allowed uptime
    forcefulUserPrompt
elif [ $currentUptime -ge $(($maxAllowedUptime/2)) ]; then 
	warningUserPrompt		# give a warning
elif [ $updatesPendingReboot -gt 0 ]; then
	installUpdatesUserPrompt		# offer to reboot for pending updates
fi
