#!/bin/bash
export PATH=/opt/homebrew/bin:$PATH

#####################################################################
# HISTORY
# 2024 08 02  Initial public commit

##################################################################################################################
# MAIN VARIABLES
SECONDS=0
OLDIFS=$IFS
IFS=','
STAMP=$(date +%Y%m%d-%H%M)
duplicatesFile="/var/log/OMC-JAMF-DUPLICATES-CLEANUP-$STAMP.csv"
working="/tmp/JAMF_DUPES"
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )


# SET TO NO FOR LIVE RUNS. This can be set in Jamf policy.
#DRYRUN="YES"
DRYRUN="${4:-"YES"}"

# API user and password UN-HASH FOR JAMF. This can be set in Jamf policy.
cryptedUser="${10}"
cryptedPass="${11}"

function DecryptString() {
    echo "${1}" | /usr/bin/openssl enc -aes256 -md md5 -d -a -A -S "${2}" -k "${3}"
}
apiUser=$(DecryptString "${cryptedUser}" 'PASSWORD TO BE SALTED' 'PASSWORD TO BE SALTED' )
apiPass=$(DecryptString "${cryptedPass}" 'PASSWORD TO BE SALTED' 'PASSWORD TO BE SALTED' )

# Or just put creds in plain text. They're needed to create api tokens.
# For this we are using the same user and password on both servers.

apiUser="robert_redford"
apiPass="seTecaStronoMy"

# Email address for reporting. This is me. Hello!
reportEMAIL="markkenny@gmail.com"

#####################################################################
# Functions

function setUp () {
    echo ""
    echo "Jamf Duplicates Delete"
    echo "Dryrun: $DRYRUN on $STAMP"
    echo ""

    if [[ -d "$working" ]]; then
        rm -rf $working/*
    else
        mkdir -p $working
    fi
    cd $working
    if [[ -f "$duplicatesFile" ]]; then
        rm $duplicatesFile
    else
        echo "Create Duplicates CSV log file: $duplicatesFile"
        echo "Serial_Number,Computer_Name,OLD_JSSID,OLD_Last_Enrollment,OLD_JAMF_SERVER,NEW_JSSID,NEW_Last_Enrollment,NEW_JAMF_SERVER" > $duplicatesFile
    fi

    requiredBinaries=("xmlstarlet")
    for binary in "${requiredBinaries[@]}"; do
        if command -v "$binary" > /dev/null; then
            version=$( "$binary" --version | head -n 1)
            echo "$binary is installed. Version: $version"
        else
            echo "$binary is not installed." 
            exit 1
        fi
    done
}

# Report ID on each server is an advanced search that has no criteria, this will report all Macs, managed and unmanged.
# Display Last Enrollment, Serial Number. (I have OS version, Username, cannot remember why, I thought it would be useful.) 

function selectONE() {
    echo "Setting ONE Server"
    jssURL="https://one.jamf.company.com"
    reportID="123"
    server="ONE"
}

function selectTWO() {
    echo "Setting TWO Server"
    jssURL="https://TWO.jamf.company.com"
    reportID="456"
    server="TWO"
}

function downloadXML () {
    echo "Download $server Advanced Search"
    curl -H "Accept: text/xml" -sfk -H "Authorization: Bearer $token" ${jssURL}/JSSResource/advancedcomputersearches/id/${reportID} -X GET > $working/tmp_$server.xml
    xmllint --format $working/tmp_$server.xml > $working/$server.xml
}


function reportEmail () {
    reportFile=$( cat $duplicatesFile | cut -d ',' -f 1,5 | tail -n+2 | sort -k2 -t, > $working/EMAIL_DUPLICATES_REPORT.csv )
    reportFile="$working/EMAIL_DUPLICATES_REPORT.csv"
    dupeCount=$(($(wc -l < "$reportFile") ))
    MESSAGE=$( cat ${reportFile} )
    if [ $DRYRUN == "YES" ]; then
        emailSubject="DRY-RUN Jamf Duplicates Deleted: $dupeCount"
        sudo -u "$currentUser" echo "$MESSAGE" | mail -s "${emailSubject}" "${reportEMAIL}"
    else
        emailSubject="Jamf Duplicates Deleted: $dupeCount"
        sudo -u "$currentUser" echo "$MESSAGE" | mail -s "${emailSubject}" "${reportEMAIL}"
    fi
}


findOldestSN() {
    local serial=$1
    echo "Checking Duplicate serial number: $serial"
    local TWO_entry=$(/opt/homebrew/bin/xmlstarlet sel -T -t -m "/advanced_computer_search/computers/computer[Serial_Number='$serial']" \
        -v "Serial_Number" -o "," \
        -v "Computer_Name" -o "," \
        -v "id" -o "," \
        -v "Last_Enrollment" -o ",TWO" -n TWO.xml | sort -t',' -k4,4 | head -n 1)
        echo $TWO_entry
    local ONE_entry=$(/opt/homebrew/bin/xmlstarlet sel -T -t -m "/advanced_computer_search/computers/computer[Serial_Number='$serial']" \
        -v "Serial_Number" -o "," \
        -v "Computer_Name" -o "," \
        -v "id" -o "," \
        -v "Last_Enrollment" -o ",ONE" -n ONE.xml | sort -t',' -k4,4 | head -n 1)
        echo $ONE_entry
    
    if [[ -n "$TWO_entry" && -n "$ONE_entry" ]]; then
        local newer_jss_id_TWO=$(cut -d',' -f3 <<<"$TWO_entry")
        local newer_last_enrollment_TWO=$(cut -d',' -f4 <<<"$TWO_entry")
        local newer_file_TWO="TWO"
        local newer_jss_id_ONE=$(cut -d',' -f3 <<<"$ONE_entry")
        local newer_last_enrollment_ONE=$(cut -d',' -f4 <<<"$ONE_entry")
        local newer_file_ONE="ONE"

        local timestamp_TWO=$(date -jf "%Y-%m-%d %H:%M:%S" "$newer_last_enrollment_TWO" "+%s")
        local timestamp_ONE=$(date -jf "%Y-%m-%d %H:%M:%S" "$newer_last_enrollment_ONE" "+%s")
        
        if [[ "$timestamp_TWO" -lt "$timestamp_ONE" ]]; then
            echo "$TWO_entry,$newer_jss_id_ONE,$newer_last_enrollment_ONE,$newer_file_ONE" >> "$duplicatesFile"
        else
            echo "$ONE_entry,$newer_jss_id_TWO,$newer_last_enrollment_TWO,$newer_file_TWO" >> "$duplicatesFile"
        fi
    elif [ -n "$TWO_entry" ]; then
        echo "$TWO_entry,,,,," >> "$duplicatesFile"
    elif [ -n "$ONE_entry" ]; then
        echo "$ONE_entry,,,,," >> "$duplicatesFile"
    fi
}


processSN() {
    echo "Process Duplicate serial numbers"
    unique_serial_numbers=$(comm -12 <(/opt/homebrew/bin/xmlstarlet sel -T -t -m "/advanced_computer_search/computers/computer" -v "Serial_Number" -n TWO.xml | sort -u) \
        <(/opt/homebrew/bin/xmlstarlet sel -T -t -m "/advanced_computer_search/computers/computer" -v "Serial_Number" -n ONE.xml | sort -u) | paste -sd "," -)
    echo "$unique_serial_numbers," | tr ',' '\n' | while read -r serial; do
        findOldestSN "$serial"
        done

    awk -F',' 'BEGIN {
        print "OLD_JSSID,Serial_Number,Computer_Name" > "TWO_DELETE.csv"
        print "OLD_JSSID,Serial_Number,Computer_Name" > "ONE_DELETE.csv"
    }
    NR > 1 {
        if ($5 == "TWO" || $5 == "\"TWO\"" || $5 == "ONE" || $5 == "\"ONE\"") {
            print $3 "," $1 "," $2 >> ($5 == "TWO" || $5 == "\"TWO\"" ? "TWO_DELETE.csv" : "ONE_DELETE.csv")
        }
    }' "${duplicatesFile}"
}


deleteTWOids() {
    TWO_IDs=$(cut -d',' -f1 TWO_DELETE.csv | sed '1d' | paste -sd ',' -)
    if [ "$TWO_IDs" ]; then
        echo "IDs of duplicate Macs in TWO to Delete..."
        echo "$TWO_IDs"
        jamfproIDURL="${jssURL}/JSSResource/computers/id"
        for ID in $TWO_IDs; do
            if [[ "$ID" =~ ^[0-9]+$ ]]; then
                if [ $DRYRUN == "YES" ]; then
                    echo "DRY-RUN Delete ${jamfproIDURL}/$ID"
                else
                    echo "DELETING ${jamfproIDURL}/$ID"
                    curl -sk -H "Authorization: Bearer $token" "${jamfproIDURL}/$ID" -X DELETE
                fi
            else
                echo "The following input is not a number: $ID"
            fi
        done
    else
        echo "No duplicate Macs in TWO to Delete"
        echo ""
    fi
}


deleteONEids() {
ONE_IDs=$(cut -d',' -f1 ONE_DELETE.csv | sed '1d' | paste -sd ',' -)
if [ "$ONE_IDs" ]; then
    echo "IDs of duplicate Macs in ONE to Delete..."
    echo "$ONE_IDs"
    jamfproIDURL="${jssURL}/JSSResource/computers/id"
    for ID in $ONE_IDs; do
        if [[ "$ID" =~ ^[0-9]+$ ]]; then
            if [ $DRYRUN == "YES" ]; then
                echo "DRY-RUN Delete ${jamfproIDURL}/$ID"
            else
                echo "DELETING ${jamfproIDURL}/$ID"
                curl -sk -H "Authorization: Bearer $token" "${jamfproIDURL}/$ID" -X DELETE
            fi
        else
            echo "The following input is not a number: $ID"
        fi
    done
else
    echo "No duplicate Macs in ONE to Delete"
fi
}


# # Tokens # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
requestAuthToken() {
	authToken=$( /usr/bin/curl -X POST -s "$jssURL/api/v1/auth/token" -u "$apiUser:$apiPass" )
	token=$( /usr/bin/plutil -extract token raw - <<< "$authToken" )
	tokenExpiration=$( /usr/bin/plutil -extract expires raw - <<< "$authToken" )
	localTokenExpirationEpoch=$( TZ=GMT /bin/date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s" 2> /dev/null )
}
verifyToken() {
	checkToken=$( /usr/bin/curl -s "$jssURL/api/v1/auth" -H "Authorization: Bearer $token" --write-out "%{http_code}" )
	tokenStatus=${checkToken: -3}
}
renewToken() {
	authToken=$( /usr/bin/curl -X POST -s "$jssURL/api/v1/auth/keep-alive" -H "Accept: application/json" -H "Authorization: Bearer $token" )
	token=$( /usr/bin/plutil -extract token raw - <<< "$authToken" )
	tokenExpiration=$( /usr/bin/plutil -extract expires raw - <<< "$authToken" )
	localTokenExpirationEpoch=$( TZ=GMT /bin/date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s" 2> /dev/null )
	renewalTime=$(( $localTokenExpirationEpoch - 300 ))
}
expireAuthToken() {
	/usr/bin/curl -X POST -s "$jssURL/api/v1/auth/invalidate-token" -H "Authorization: Bearer $token"
    token=""
}


#####################################################################
## Run the job!


setUp

selectONE
requestAuthToken
verifyToken
downloadXML
expireAuthToken

selectTWO
requestAuthToken
verifyToken
downloadXML
expireAuthToken

processSN

selectTWO
requestAuthToken
verifyToken
deleteTWOids
expireAuthToken

selectONE
requestAuthToken
verifyToken
deleteONEids
expireAuthToken

duration=$SECONDS

reportEmail

IFS=$OLDIFS
exit 0
