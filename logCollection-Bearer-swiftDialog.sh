#!/bin/bash

# User Variables
jamfProURL="$4"
jamfProUser="$5"
jamfProPass="$6"
logFiles="$7"

# Display start notification using swiftDialog
/usr/local/bin/dialog --notification --title "COMPANY" --message "Submitting logs to COMPANY..."

# Request Bearer Token
bearerTokenResponse=$(curl -s -u "$jamfProUser":"$jamfProPass" "$jamfProURL/api/v1/auth/token" -X POST -H "Content-Type: application/json" --data '{"grant_type":"client_credentials"}')
bearerToken=$(echo "$bearerTokenResponse" | python3 -c "import sys, json; print(json.load(sys.stdin)['token'])")

if [[ -z "$bearerToken" ]]; then
    echo "Authentication failed. Check credentials or endpoint."
    echo "Response: $bearerTokenResponse"
    exit 1
fi

echo "Bearer token obtained successfully."

# System Variables
mySerial=$(system_profiler SPHardwareDataType | grep Serial | awk '{print $NF}')
currentUser=$(stat -f%Su /dev/console)
compHostName=$(scutil --get LocalHostName)
timeStamp=$(date '+%Y-%m-%d-%H-%M-%S')
osMajor=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $1}')
osMinor=$(/usr/bin/sw_vers -productVersion | awk -F . '{print $2}')

# Log Collection
fileName="${compHostName}-${currentUser}-${timeStamp}"
tempDir="/private/tmp/${fileName}"
mkdir -p "$tempDir"
cp $logFiles "$tempDir"

# Change to /private/tmp directory to avoid including the full path
cd /private/tmp
zip -r "${fileName}.zip" "${fileName}"

# Retrieve Jamf Pro ID
if [[ "$osMajor" -ge 11 ]]; then
    jamfProID=$(curl -ks -H "Authorization: Bearer ${bearerToken}" "$jamfProURL/JSSResource/computers/serialnumber/$mySerial/subset/general" | xmllint --xpath "//computer/general/id/text()" -)
elif [[ "$osMajor" -eq 10 && "$osMinor" -gt 12 ]]; then
    jamfProID=$(curl -ks -H "Authorization: Bearer ${bearerToken}" "$jamfProURL/JSSResource/computers/serialnumber/$mySerial/subset/general" | xmllint --xpath "//computer/general/id/text()" -)
fi

if [[ -z "$jamfProID" ]]; then
    echo "Unable to obtain Jamf Pro ID."
    exit 1
fi

echo "Jamf Pro ID: $jamfProID"

# Upload Log File
uploadResponse=$(curl -ks -H "Authorization: Bearer ${bearerToken}" "$jamfProURL/JSSResource/fileuploads/computers/id/$jamfProID" -F name=@"/private/tmp/${fileName}.zip" -X POST)

if [[ $? -eq 0 ]]; then
    echo "Log file uploaded successfully."
else
    echo "Failed to upload log file. Response: $uploadResponse"
fi

# Cleanup
rm -rf "/private/tmp/${fileName}"
rm "/private/tmp/${fileName}.zip"

# Invalidate the Bearer Token
invalidateResponse=$(curl -s -u "$jamfProUser":"$jamfProPass" "$jamfProURL/api/v1/auth/invalidateToken" -X POST -H "Authorization: Bearer $bearerToken")

if [[ $? -eq 0 ]]; then
    echo "Bearer token invalidated successfully."
else
    echo "Failed to invalidate bearer token. Response: $invalidateResponse"
fi

# Display completion notification using swiftDialog
/usr/local/bin/dialog --notification --title "COMPANY" --message "Done! Please let IT know that your logs have been submitted."

exit 0
