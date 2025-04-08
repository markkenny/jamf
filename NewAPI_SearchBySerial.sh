#!/bin/bash

#####################################################################
# ABOUT

# 2025 03 22 Using old faithful Search_Macs_from_SN.sh
# But since Jamf dropped 11.15.0, they've announced an deprecated API
# ${jssURL}/JSSResource/computers/serialnumber/$SERIAL" 

# https://derflounder.wordpress.com/2025/03/21/jamf-pro-classic-api-computer-inventory-endpoint-deprecated-as-of-jamf-pro-11-15-0/
# jamfproSerialURL="${jssURL}/api/v1/computers-inventory?filter=hardware.serialNumber=="
# ID=$(/usr/bin/curl -sf –header "Authorization: Bearer ${api_token}" "${jamfproSerialURL}${SerialNumber}" -H "Accept: application/json" | /usr/bin/plutil -extract results.0.id raw – 2>/dev/null)
# jamfproIDURL="${jssURL}/api/v1/computers-inventory-detail"
# ComputerRecord=$(/usr/bin/curl -sf –header "Authorization: Bearer ${api_token}" "${jamfproIDURL}/$ID" -H "Accept: application/json" 2>/dev/null)

#####################################################################
# TO DO
# Yup! THIS SCRIPT WILL NOT RUN! 
# At least not successfully. The SearchSN function has the old method hashed out.
# The new API called that checks Jamf for a serial to get a JSS ID,
# and at time of writing, pulls most data to JSON, which is too much,
# the extracts data to variables using plitul and jq, so over-writes itself.
# 

#####################################################################
# DEBUG
# Set default exit code
#exitCode=0
#Show running line by line
#set -x

#####################################################################
# BASICS - Read all same settings needed from a single script
# Then all my API scripts can be much shorter
. _BASICS.sh


#####################################################################
# FUNCTIONS

function jobINFO() {
  # What is this script doing
  echo ""
  echo "#####################################################################"
  echo ""
  echo "                        SEARCH JAMF FOR SN"
  echo "       You will need to provide a text file of Serial numbers,"
  echo "             one SN per line, that you wish to search for."
  echo ""
  echo "#####################################################################"
  echo ""
}

function getLIST() {
  # Get list of IDs
  echo ""
  echo "You will need to submit a CSV file with one serial number per line!"
  echo "A simple path, with no spaces is best"
  echo ""
  read -r -p "Drag and drop a text file here: " THE_LIST
  THE_LIST="${THE_LIST#?}"
  THE_LIST="${THE_LIST%?}"
  echo ""
  echo "File to process: $THE_LIST "
  if [[ "$THE_LIST" == "" ]]; then
    echo "Unable to read the file path specified"
    echo "Ensure there are no spaces and that the path is correct"
    exit 1
  fi
}

# POP UP PROMPT
prompt_for_File() {
    THE_LIST=$( /usr/bin/osascript -e 'set theFile to choose file with prompt "Select the CSV file" of type {"public.comma-separated-values-text"} without invisibles' -e 'POSIX path of theFile' )
	echo "File to process: $THE_LIST"
	fileName=$( echo $THE_LIST | sed -n 's/^\(.*\/\)*\(.*\)/\2/p' | sed 's/\..*$//' )
}


# For CSVs exported from Excel with BOM and CRLF
function processLIST () {
  SERIALS=($(cat "$THE_LIST"))
}


function createLOG () {
  LOG_NAME="Macs_Search"
  LOG="$userHome/Desktop/$STAMP-$jamfLOG-$LOG_NAME.csv"
  touch $LOG
}

function SearchSN () {

  if [[ ${tokenStatus} == 200 ]]; then 
	renewalTime=$(( $localTokenExpirationEpoch - 300 ))

  # Setting log file HEADERS
  echo "Searching $jssURL" >> "$LOG"
  echo "SEARCH_SN,macID,macUDID,macNAME,userUSERNAME,userPHONE,userROOM,macCheckIn,macInventory,macSite,macEnrollDate,macMDMcapable,macEnrollType,macADE,macMDMuserApprove,NOTES1,NOTES2,NOTES3" >> "$LOG"

  for SERIAL in ${SERIALS[@]}; do
    now=$( /bin/date +"%s" )
    if [[ "$renewalTime" -lt "$now" ]]; then renewToken; fi
    echo "Obtaining Details of Mac with SN: $SERIAL"


    #####################################################################
    # The olden-day method. I liked this! 
    # COMPUTER_INFO=$( curl -X GET -s -k --fail "${jssURL}/JSSResource/computers/serialnumber/$SERIAL" -H "Accept: application/xml" -H "Authorization: Bearer $token" )


    #####################################################################
    # New API URLS using v1/computers-inventory-detail after pulling ID from serial number
    # Curl the serial
		jssSerialURL="${jssURL}/api/v1/computers-inventory?filter=hardware.serialNumber=="
		ID=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssSerialURL}${SERIAL}" -H "Accept: application/json" | /usr/bin/plutil -extract results.0.id raw - 2>/dev/null )
    # Check if serial number can be curled 
    CURL_RESULT=$?
    if [[ $CURL_RESULT -eq 22 ]]; then
      echo "Fail computer $SERIAL not found"
      # Needs as many commas as HEADERS
      echo "$SERIAL,,,,,,,,,,,,,,,NOT IN JAMF,," >> "$LOG"
      continue
    fi


    #####################################################################
    # PULL THE DATA USING JSS ID - PICK ONE OR TWO
    # bigInfo 4000+ lines of data, biggest pull so takes longest
    bigInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory-detail/$ID" -H "Accept: application/json" 2>/dev/null )
    # generalInfo 400+ lines. Really basic info.
    generalInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory/$ID?section=GENERAL" -H "Accept: application/json" 2>/dev/null )
    # User info
    userInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory/$ID?section=USER_AND_LOCATION" -H "Accept: application/json" 2>/dev/null )
    # Hardware info ±120 lines, model (has commas), serial , CPU, MAC addresses.
    hardwareInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory/$ID?section=HARDWARE" -H "Accept: application/json" 2>/dev/null )
    # Storage info ±120 lines. Drive size in MBs
    storageInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory/$ID?section=STORAGE" -H "Accept: application/json" 2>/dev/null )
    # macOS info. ±300 lines. macOS version, filevault status and EAs
    osInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory/$ID?section=OPERATING_SYSTEM" -H "Accept: application/json" 2>/dev/null )
    # EA info. ±450 lines. All EA= findo
    eaInfo=$( /usr/bin/curl -sf --header "Authorization: Bearer ${token}" "${jssURL}/api/v1/computers-inventory/$ID?section=EXTENSION_ATTRIBUTES" -H "Accept: application/json" 2>/dev/null )


    #####################################################################
    # LOG DATA FOR TESTING
    echo "$bigInfo" | jq '.' > $SERIAL-BIG.json
    echo "$generalInfo" | jq '.' > $SERIAL-GENERAL.json
    echo "$userInfo" | jq '.' > $SERIAL-USER.json

    echo "$hardwareInfo" | jq '.' > $SERIAL-HARDWARE.json
    echo "$storageInfo" | jq '.' > $SERIAL-STORAGE.json
    echo "$osInfo" | jq '.' > $SERIAL-OS.json
    echo "$eaInfo" | jq '.' > $SERIAL-EA.json


    #####################################################################
    # EXTRACT DATA TO VARIABLES WITH PLUTIL
    macID=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract id raw - 2>/dev/null )
    macUDID=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract udid raw - 2>/dev/null )
    macNAME=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.name raw - 2>/dev/null )
    macCheckIn=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.lastContactTime raw - 2>/dev/null | sed 's/Z//' | awk -F'[T.]' '{print $1, $2}' )
    macInventory=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.reportDate raw - 2>/dev/null | sed 's/Z//' | awk -F'[T.]' '{print $1, $2}' )
    macEnrollDate=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.lastEnrolledDate raw - 2>/dev/null | sed 's/Z//' | awk -F'[T.]' '{print $1, $2}' )
    macSite=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.site.name raw - 2>/dev/null )
    macMDMcapable=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.mdmCapable.capable raw - 2>/dev/null )
    macMDMuserApproved=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.userApprovedMdm raw - 2>/dev/null )
    macEnrollType=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.enrollmentMethod.objectName raw - 2>/dev/null )
    macADE=$( printf '%s' "$generalInfo" | /usr/bin/plutil -extract general.enrolledViaAutomatedDeviceEnrollment raw - 2>/dev/null )
    userUSERNAME=$( printf '%s' "$userInfo" | /usr/bin/plutil -extract userAndLocation.username raw - 2>/dev/null )
    userPHONE=$( printf '%s' "$userInfo" | /usr/bin/plutil -extract userAndLocation.phone raw - 2>/dev/null )
    userROOM=$( printf '%s' "$userInfo" | /usr/bin/plutil -extract userAndLocation.room raw - 2>/dev/null )

    # Writing plutuil variables to the log
    echo "Success; found computer with SN: $SERIAL"
    echo "$SERIAL,$macID,$macUDID,$macNAME,$userUSERNAME,$userPHONE,$userROOM,$macCheckIn,$macInventory,$macSite,$macEnrollDate,$macMDMcapable,$macEnrollType,$macADE,$macMDMuserApproved" >> "$LOG"


    #####################################################################
    # EXTRACT DATA TO VARIABLES WITH jq
    # Reading all in one go. Not very legible
    read -r jssID jssNAME jssMANAGE jssMDM icloudUser < <(jq -r '
    "\(.id) \(.general.name) \(.general.remoteManagement.managed) \(.general.mdmCapable.capable) \(
    (.general.extensionAttributes[]? | select(.name == "iCloud Signed In User") | .values[0]) // "N/A" )"' "$JSON")
    printf "TESTING JSON\n"
    printf "ID     : %s\nName   : %s\nManaged: %s\nMDM    : %s\niCloud : %s\n" "$jssID" "$jssNAME" "$jssMANAGE" "$jssMDM" "$icloudUser"
    # Much easier to read individually...
    macID=$(jq -r '.id' <<< "$generalInfo")
    macUDID=$(jq -r '.udid' <<< "$generalInfo")
    macNAME=$(jq -r '.general.name' <<< "$generalInfo")
    macCheckIn=$(jq -r '.general.lastContactTime' <<< "$generalInfo" | sed 's/Z//' | awk -F'[T.]' '{print $1, $2}')
    macInventory=$(jq -r '.general.reportDate' <<< "$generalInfo" | sed 's/Z//' | awk -F'[T.]' '{print $1, $2}')
    macEnrollDate=$(jq -r '.general.lastEnrolledDate' <<< "$generalInfo" | sed 's/Z//' | awk -F'[T.]' '{print $1, $2}')
    macSite=$(jq -r '.general.site.name' <<< "$generalInfo")
    macMDMcapable=$(jq -r '.general.mdmCapable.capable' <<< "$generalInfo")
    macMDMuserApproved=$(jq -r '.general.userApprovedMdm' <<< "$generalInfo")
    macEnrollType=$(jq -r '.general.enrollmentMethod.objectName' <<< "$generalInfo")
    macADE=$(jq -r '.general.enrolledViaAutomatedDeviceEnrollment' <<< "$generalInfo")
    userUSERNAME=$(jq -r '.userAndLocation.username' <<< "$userInfo")
    userPHONE=$(jq -r '.userAndLocation.phone' <<< "$userInfo")
    userROOM=$(jq -r '.userAndLocation.room' <<< "$userInfo")

    # Reading a named EA
    icloudUser=$(jq -r ' (.general.extensionAttributes[]? | select(.name == "iCloud Signed In User") | .values[0]) // "N/A" ' "$generalInfo")

    # Nothing written
  done
fi
}


#####################################################################
# Let's do it!

jobINFO
BasicSanityCheck
BasicSelectJamf
BasicSetCredentials
getLIST
createLOG
processLIST
requestAuthToken
verifyToken

SearchSN

expireAuthToken

exit

