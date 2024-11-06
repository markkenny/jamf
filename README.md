# My Jamf Tools
Scripts and things I've built. All company data removed, so that may have broken something. Let me know, so sorry in advance.

I also set a local plist to store creds in, it's really useful to use default

```
JAMFPREFS="$userHome/Library/Preferences/com.company.jss.plist"
jssURL=$(defaults read "$JAMFPREFS" jssURL)
jssUSER=$(defaults read "$JAMFPREFS" jssUSER)
jssPASSWORD=$(defaults read "$JAMFPREFS" jssPASSWORD)
```

But recently started using source, and adding .env to .gitignore
```
if [[ -e .env ]]; then
    source .env
    echo "Found local .env"
else
    echo "No local .env Using Jamf parameters"
fi
```

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

