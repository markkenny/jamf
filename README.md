# My Jamf Tools
Scripts and things I've built. All company data removed, so that may have broken something. Let me know, so sorry in advance.


# _BASICs.sh
A really useful script to have load lots of variables and functions for use in other Jamf API scripts so as to keep the 'workers' shorter. 
Especially useful for creds and creating, refreshing API tokens.
Keep all your scripts in one folder and have a single _BASICS to set all you ever need.

You'll need set a local plist to store your Jamf creds in, it's really useful to use defaults!

Could have been a .env but I learnt _Basics.sh first and I don't keep any creds in here.

```
JAMFPREFS="$userHome/Library/Preferences/com.jamfcredentials.plist"
jssURL=$(defaults read "$JAMFPREFS" jssURL)
jssUSER=$(defaults read "$JAMFPREFS" jssUSER)
jssPASSWORD=$(defaults read "$JAMFPREFS" jssPASSWORD)
```

I've recently started using source, and adding .env to .gitignore
```
if [[ -e .env ]]; then
    source .env
    echo "Found local .env"
else
    echo "No local .env Using Jamf parameters"
fi
```

# NewAPI_SearchBySerial
When Jamf dropped 11.15.0, they've announced an deprecated API "${jssURL}/JSSResource/computers/serialnumber/$SERIAL" 
Most of my company API calls use this in one way or another, so this is start of my journey into converting to JSON and PLUTIL.
I haven't decided what I'm most comfortable with most yet.

# API Delete Duplicate Macs.sh
Pulls an advanced search of all Macs in two seperate Jamf servers. Compares matching serial numbers, checks for latest enrollment date and delete the old serial number.

Homebrew is needed to install xmlstarlet. Script checks for installation and fails if missing. But you do need xmlstarlet, I couldn't sort well enough without it. 


# Jamf Upload Logs
This script, in conjunction with secured API credentials, can be used in Jamf policy to pull a file or folder, or generate a log from a users Mac, then upload to Jamf.

It uploads a ZIP of the log or path into File Attachments.

I've used to to grab a user installed application so I coudld get the bundle ID or to pull a specific log from from a few Macs. 


# MAXON Installer
At my company, we remove almost all users admin privileges, and this can be awkward for creatives needing to run updates. Adobe Creative Cloud has an option to run as priviled to allow users to install, update and remove applications, but MAXON doesn't. We have asked many times.

They do offer a cli, but the [documentation is a little sparse](https://support.maxon.net/hc/en-us/articles/10140095856796-How-To-Use-The-mx1-Tool).

My script runs in Terminal or as a Jamf policy. Still tweaking.


