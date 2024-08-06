#!/bin/bash

## Upload a log or folder to Jamf server as an attachment
#########################################################################################

# 20240806 : MK initial public commit

echo "UPLOADING LOG FILES TO JAMF"
echo "Version 1.0"

## NOTES and TODO
#########################################################################################
# 
# Run as root when using locally as many logs are owned by root.

# use a .env file to store parameters locally. 
# If they don't exist, they will be pulled from the Jamf Policy.

# selectLog / $4      : Path to log, file or folder.
# selectMaxSize / $5  : Default is 5MB. Size is in bytes. It's hardcoded with override to stop uploaded a 1GB, (or bigger) file straight to Jamf!
# logCommand / $8     : Command to create log file. Some applications have this.
# logFile / $9        : The logCommand outputs to a file. Stick it in /tmp with no spaces to make life easy.

# userSalt / ${10}    : To upload to Jamf you need a api user with upload attachment privileges. 
# passSalt / ${11}    : To secure, you can salt the password and put the salt in the policy, and the hashes in the scriupt.

# Jamf policy should be scoped and set to one once.

## Parameters
#########################################################################################

if [[ -e .env ]]; then
    source .env
    echo "UploadLog: running locally using .env details"
    echo "selectLog: $selectLog"
    echo "selectMaxSize: $selectMaxSize"
    echo "logFile: $logFile"
    echo "logCommand: $logCommand" 
else
    echo "UploadLog: running Jamf script using policy parameters"
    selectLog="$4"   ## File or folder
    selectMaxSize="$5"   ## User defined max upload size 
    logFile="$8"
    logCommand="$9" 
    userSalt="${10}"
    passSalt="${11}"
fi

## Variables
#########################################################################################

timeStamp=$(date +%Y%m%d-%H%M)   ## To be used to the upload file
jssURL=$( defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url | sed 's/.$//' )
serialNumber=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F'"' '/IOPlatformSerialNumber/{print $4}')
megabytes="1048576"  ## Divide size in bytes by this for Mb size
maxUploadSize="5242880"  ##In bytes. 5 megabytes
computer_cache="/tmp/jss_computer.xml"
authToken=""  ## Reset API tokens
token=""  ## Reset API tokens
tokenExpiration=""  ## Reset API tokens
checkToken=""  ## Reset API tokens


## Decryption and Tokens
#########################################################################################
# Find your way to secure your API user and password
function DecryptString() {
    echo "${1}" | /usr/bin/openssl enc -aes256 -md md5 -d -a -A -S "${2}" -k "${3}"
}

apiUser=$(DecryptString "$userSalt" 'USER_HASH_PART_1' 'USEWR_HASH_PART_2')
apiPass=$(DecryptString "$passSalt" 'PASSWORD_HASH_PART_1' 'PASSWORD_HASH_PART_2')


####################################################################
# API Bearer Tokens used by most scripts

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


## FUNCTIONS
#########################################################################################

createLog () {
    if [ -n "$logCommand" ]; then
        echo "Creating log: $logCommand"
        $logCommand > $logFile
    fi
}


zipLogs () {
if [ -n "$selectLog" ]; then
    # Check for directory
    if [ -d "$selectLog" ]; then
        echo "LOG: Directory provided: $selectLog"
    fi
    # Check for file
    if [ -f "$selectLog" ]; then
        echo "LOG: File provided: $selectLog"
    fi

    logTag=$( basename "$selectLog" )    
    logName="$serialNumber-$timeStamp-$logTag.zip"
    # Remove spaces from log name
    logName="${logName// /}"
    zip -rq /private/tmp/"$logName" "$selectLog"
    uploadFile="/private/tmp/$logName"

    # CHECK SIZE OF ZIP
    uploadFileSize=$(stat -f '%z' "$uploadFile")
    uploadFileSizeMB=$(($uploadFileSize / $megabytes))

    echo "LOG: File: $uploadFile is $uploadFileSizeMB Mb"

        if [ -n "$selectMaxSize" ]; then
            maxUploadSize=$selectMaxSize
            sizeCal=$(($maxUploadSize / $megabytes))
            echo "LOG: User manually selected $sizeCal Mb as max upload"
        fi

        if [ "$uploadFileSize" -gt "$maxUploadSize" ]; then
            echo "FAIL: $logName too large at $uploadFileSizeMB Mb to upload, exiting"
            echo "FAIL: This file is to way large to upload to Jamf. Find another solution."
            error_exit
        fi

        if [ "$uploadFileSize" -lt "$maxUploadSize" ]; then
            uploadZip
        else
            echo "FAIL: This file is too large to upload to Jamf. Increase upload size in the policy."
            error_exit
        fi

    echo "LOG: $logName is compressed to $uploadFileSizeMB Mb"
    echo "LOG: OK to upload"
else
    echo "ERROR: No logs specified in policy."
    error 1
fi
}


uploadZip () {
    requestAuthToken
    verifyToken
    if [[ ${tokenStatus} == 200 ]]; then
        /usr/bin/curl -sf "$jssURL/JSSResource/computers/serialnumber/${serialNumber}" -H "Accept: application/xml" -H "Authorization: Bearer $token" > $computer_cache 2> /dev/null
        JSS_ID=$( cat $computer_cache | xmllint --xpath '//computer/general/id/text()' - 2> /dev/null )
        /usr/bin/curl -sk -X POST  "$jssURL"/JSSResource/fileuploads/computers/id/$JSS_ID -F name=@"$uploadFile;filename=$logName" -H "Authorization: Bearer $token"
        echo "SUCCESS: $logName Uploaded"
        success_exit
    else
        echo "FAIL: API Authentication Error"
        error_exit
    fi
}

success_exit() {
    echo "SUCCESS: Remove temp files and token"
    rm $uploadFile
    rm $computer_cache
    expireAuthToken
    exit 0
}

error_exit() {
    echo "FAIL: Removing temp files"
    rm $uploadFile
    exit 1
}


## THE JOB
#########################################################################################

createLog
zipLogs
uploadZip
