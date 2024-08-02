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

Homebrew is used to install xmlstarlet. Script checks for installation and fails if missing. But you do need xmlstarlet, I couldn't sort well enough without it. 