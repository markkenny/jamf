#!/bin/bash

#####################################################################
# ABOUT
 
# 2025 04 08 Public commit removing company details, 
# so some variables may fail. Add yours.


#####################################################################
# BASICS

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
userHome=$( dscl . read /Users/$currentUser NFSHomeDirectory | awk '{print $2}' )
REPO_ROOT="$SCRIPT_DIR/../"
STAMP=$(date +%Y%m%d-%H%M)
dateStamp=$( date +%Y%m%d )
timeStamp=$( date +%H%M )
error=0
exitCode=0
SECONDS=0
NoBearerToken=""
token=""
apiToken=""
token_expiration=""
exportLogFolder="/Users/$currentUser/Desktop"


#####################################################################
# BASICS

# check REPO_ROOT and local creds exists
function BasicSanityCheck() {
    echo ""
    echo "JAMF API SCRIPTS BEING RUN"
    echo "By $currentUser at $STAMP"
    echo ""

    if [ -f "$JAMFPREFS" ]; then
        echo "Jamf credentials present"
        jssUSER=$(defaults read "$JAMFPREFS" jssUSER)
        # Check for users that are read only
        if [[ $jssUSER == "api-read" ]]; then
            echo "JAMF User: $jssUSER"
            echo "NOTE: This is a read-only Jamf account"
            echo "You cannot delete anything with this api user."
        fi
    else
        echo "The local jamf credentials plist does not exist"
        echo "Run defaults write to create plist for jssURL, jssUSER, jssPASSWORD here..."
        echo "$JAMFPREFS"
        echo "Keep the same user/password for both ROW, DSO and DEV"
        exit 1
    fi
    
    # Add binaries to check as need. 
    # jq now built in to macOS 15
    echo "Checking all required binaries are installed..."
    requiredBinaries=("jq" "xmlstarlet" "xml")
    for binary in "${requiredBinaries[@]}"; do
        if command -v "$binary" > /dev/null; then
            version=$( "$binary" --version | head -n 1)
            echo "$binary is installed. Version: $version"
        else
            echo "$binary is not installed." 
            exit 1
        fi
    done
    echo ""
}


# Use a local plist for creds....
# echo "Setting Jamf Creds"
function BasicSetCredentials () {
  if [[ -f "$JAMFPREFS" ]]; then
      if [[ -z "$jssURL" ]]; then
          jssURL=$(defaults read "$JAMFPREFS" jssURL)
          echo "JAMF server: $jssURL"
      fi
      if [[ -z "$jssUSER" ]]; then
          jssUSER=$(defaults read "$JAMFPREFS" jssUSER)
          echo "JAMF User: $jssUSER"
      fi
      if [[ -z "$jssPASSWORD" ]]; then
          jssPASSWORD=$(defaults read "$JAMFPREFS" jssPASSWORD)
          echo "JAMF API Password: BIG_SECRET"
      fi
  fi
}


# Which Jamf Server
# PUT YOUR OWN IN HERE
function BasicSelectJamf() {
  PS3='Which Jamf server do you want to work against: '
  echo ""
  options=("A" "B" "C" "DEV" "EXIT")
  select opt in "${options[@]}"
  do
      echo "Selection is $opt"
      case $opt in
        "A")
            echo "A Selected"
            echo ""
            defaults write "$JAMFPREFS" jssURL "https://a.jamf.com"
            jssURL=https://a.jamf.com
            jamfLOG=A
            Cloudfront="https://A.cloudfront.net"
            break ;;
        "B")
            echo "B Selected"
            echo ""
            defaults write "$JAMFPREFS" jssURL "https://b.jamf.com"
            jssURL=https://b.jamf.com
            jamfLOG=B
            Cloudfront="https://b.cloudfront.net"
            break ;;
        "C")
            echo "C Selected"
            echo ""
            defaults write "$JAMFPREFS" jssURL "https://c.jamf.com"
            jssURL=https://c.jamf.com
            jamfLOG=C
            Cloudfront="https://c.cloudfront.net"
            break ;;
        "DEV")
            echo "DEV Selected"
            echo ""
            defaults write "$JAMFPREFS" jssURL "https://dev.jamf.com"
            jssURL=https://dev.jamf.com
            jamfLOG=DEV
            break ;;
        "EXIT")
            echo "Exiting safely."
            exit
            ;;
        *) echo "invalid option $REPLY";;
      esac
  done
}


# Manaually Select A Jamf Server
function BasicSelectA() {
    echo "Setting A Server"
 	defaults write "$JAMFPREFS" jssURL "https://a.jamf.com"
    jssURL=https://a.jamf.com
    jamfLOG=A
    Cloudfront="https://a.cloudfront.net"
}

# Manaually Select B Jamf Server
function BasicSelectA() {
    echo "Setting B Server"
 	defaults write "$JAMFPREFS" jssURL "https://b.jamf.com"
    jssURL=https://b.jamf.com
    jamfLOG=B
    Cloudfront="https://b.cloudfront.net"
}

# Manaually Select C Jamf Server
function BasicSelectC() {
    echo "Setting C Server"
 	defaults write "$JAMFPREFS" jssURL "https://c.jamf.com"
    jssURL=https://c.jamf.com
    jamfLOG=C
    Cloudfront="https://c.cloudfront.net"
}

# Manaually Select DEV Jamf Server
function BasicSelectDEV() {
    echo "Setting DEV Server"
    echo ""
    defaults write "$JAMFPREFS" jssURL "https://dev.jamf.com"
    jssURL=https://dev.jamf.com
    jamfLOG=DEV
}


# Request DRYRUN, or not
function BasicDRYRUN () {
  echo ""
  echo "Please select if this is a dry run or not."
  echo "Dry run will not run the process, only echo the commands"
  echo ""
  read -r -p "Is this a dry-run? Please enter Y/N  " response
    if [[ "$response" =~ ^([nN][oO]|[nN])$ ]]; then
        read -r -p "ARE YOU REALLY SURE? Please enter YES  " response
        if [[ "$response" = YES ]]; then
            echo "Dry run mode disabled."
            echo "DANGEROUS POLICY"
            DRYRUN="NO"
            if [[ $jssUSER = "api-read" ]]; then
                echo "JAMF User: $jssUSER"
                echo "NOTE: This is a read-only Jamf account"
                echo "You cannot delete anything with this api user."
            fi
        fi
      else
        echo "Dry run mode enabled."
        echo 
        DRYRUN="YES"
    fi
}

#####################################################################
# API Bearer Tokens used by most scripts

GetJamfProAPIToken() {
   api_token=$(/usr/bin/curl -X POST --silent -u "${jssUSER}:${jssPASSWORD}" "${jssURL}/api/v1/auth/token" | plutil -extract token raw -)
}

APITokenValidCheck() {
     api_authentication_check=$(/usr/bin/curl --write-out %{http_code} --silent --output /dev/null "${jssURL}/api/v1/auth" --request GET --header "Authorization: Bearer ${api_token}")
}

CheckAndRenewAPIToken() {
APITokenValidCheck
if [[ ${api_authentication_check} == 200 ]]; then
         api_token=$(/usr/bin/curl "${jssURL}/api/v1/auth/keep-alive" --silent --request POST --header "Authorization: Bearer ${api_token}" | plutil -extract token raw -)
else
   GetJamfProAPIToken
fi
}

InvalidateToken() {
APITokenValidCheck
if [[ ${api_authentication_check} == 200 ]]; then
      authToken=$(/usr/bin/curl "${jssURL}/api/v1/auth/invalidate-token" --silent  --header "Authorization: Bearer ${api_token}" -X POST)
      api_token=""
fi
}


# # Tokens # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# Used by Redeploy_Jamf_Framework_SmartGroup.sh THIS MIGHT JUST BE THE PREFERRED METHOD
requestAuthToken() {
	authToken=$( /usr/bin/curl -X POST -s "$jssURL/api/v1/auth/token" -u "$jssUSER:$jssPASSWORD" )
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

#requestAuthToken
#verifyToken
#renewToken
#expireAuthToken