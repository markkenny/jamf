#!/bin/bash

# MK Jamf script to download and install MAXON apps using their own tool.
# They should be doing this!
# 2024 12 17 MAXON changed the app, only four apps now???

######### TO DO
# Policy to install MAXON app if mx1cli is missing. Check which Jamf is on and run IOM policy to install MAXON app
# Check for host app and fail; Premiere/AfterEffect, DaVinci, Avid, Cinema4D etc.


######### Jamf Variables
# Choose the app to install with a Jamf policy which overrides selectin in this script.
# Options: "Cinema 4D" "Red Giant" "RedShift" "zBrush"
selection="${4:-""}" 
#IOM Policy to install MAXON App. DSO: 6347 ROW: 9130
#maxonApp="${5:-""}" 


appSelect="${11:-"CLI"}" # Choose how to prompt user. Default is CLI. Or OSA if running from Jamf.

######### Variables
version="20241217a"
mx1cli="/Library/Application Support/Maxon/Tools/mx1"
currentUser=$( echo "show State:/Users/ConsoleUser" | scutil | awk '/Name :/ && ! /loginwindow/ { print $3 }' )
DLfolder="/Users/Shared/Maxon/Service/Downloads"
DEVid="4ZY22YGXQG"
SECONDS=0
LOG="/private/var/omc/logs/MAXON-INSTALLER.log"

appArray=( "Cinema 4D" "Red Giant" "RedShift" "zBrush" )


######### Functions

# Making command a function so as to be able to not have to worry about escaped spaces.
mx1cli() {
    sudo -u "$currentUser" /Library/Application\ Support/Maxon/Tools/mx1 "$@"
}

# Check log exists, user signed into MAXON app, clear any mounted DMGs from previous failed installs.
sanityCheck() {
    if [[ ! -f "$LOG" ]]; then
        sudo -u "$currentUser" touch $LOG || { echo "Failed to create log file."; exit 1; }
        echo "#######################################################################" | tee -a $LOG
        echo "$(date +%Y%m%d-%H%M%S) STARTING OneJamf MAXON Installer v$version" | tee -a $LOG
    else 
        echo "#######################################################################" | tee -a $LOG
        echo "$(date +%Y%m%d-%H%M%S) STARTING OneJamf MAXON Installer v$version" | tee -a $LOG
    fi

    if [[ ! -d "$DLfolder" ]]; then
        echo "ERROR: Maxon downloads folder not available at $DLfolder." | tee -a $LOG
        exitError
    fi

    if [[ ! -x "$mx1cli" ]]; then
        echo "ERROR: mx1cli not found or not executable at $mx1cli." | tee -a $LOG
        exitError
    fi
    # Check users signed into Maxon. Might need a mx1cli restart service if only just installed
    maxonUser=$( mx1cli user info | grep "user:" | awk '{print $2}' )
    if [[ "$maxonUser" != *@* ]]; then
        echo "ERROR: not signed into MAXON App" | tee -a $LOG
        exitError
    else
        echo "Maxon account ....: $maxonUser" | tee -a $LOG
    fi

    # Check for any DMGs previously mounted. WIP 
    # mounted_volumes=$(hdiutil info | awk '/image-path/ && /\/Users\/Shared\/Maxon\/Service\/Downloads/ { print $NF }')
    # if [[ -n "$mounted_volumes" ]]; then
    #     while IFS= read -r volume; do
    #         hdiutil detach "$volume" && echo "Unmounting DMG ...: $volume" || echo "Failed DMG .......: $volume"
    #     done <<< "$mounted_volumes"
    # fi
}

# Cleanup
clearDownloads() {
    if [[ "$(ls -A "$DLfolder")" ]]; then
        rm -rf "${DLfolder:?}/"*
    fi
}


# Read bundle info for application info
BundleInfo() {
    if [[ -d "$app" ]]; then
        plist="$app/Contents/Info.plist"
        if [[ -f "$plist" ]]; then
            # Read CFBundleName and CFBundleVersion from Info.plist
            bundle_id=$(/usr/bin/defaults read "$plist" CFBundleIdentifier 2>/dev/null)
            bundle_name=$(/usr/bin/defaults read "$plist" CFBundleName 2>/dev/null)
            bundle_version=$(/usr/bin/defaults read "$plist" CFBundleShortVersionString 2>/dev/null)
            bundle_appleID=$(/usr/bin/defaults read "$plist" | grep "$DEVid" 2>/dev/null)
        else
            echo "ERROR: info.plist not found in $app" | tee -a $LOG
            exitError
        fi
    else
        echo "ERROR: $app is not a valid directory" | tee -a $LOG
        exitError
    fi
    # Check bundle ID matches.
    if [[ "$bundle_id" != "$bundleID" ]]; then
        echo "ERROR: bundle ID does not match $bundleID" | tee -a $LOG
        exitError
    fi

}


# Check Apple DEV ID matches. Only for apps from DMGs
checkDevID() {
    if [[ "$bundle_appleID" = *$DEVid* ]]; then
        echo "ERROR: application bundle ID does not match $DEVid" | tee -a $LOG
        exitError
    else
        echo "Developer ID......: $DEVid" | tee -a $LOG
    fi
}

# All settings to insall each MAXON app. 
appSettings() {
	if [[ $selection == "Cinema 4D" ]]; then
        echo "Selection ........: Cinema 4D" | tee -a $LOG
        downloader="net.maxon.cinema4d-installer"
        bundleID="net.maxon.cinema4d.installer"
        installCommand="/Contents/MacOS/installbuilder.sh"
        installArguments="--mode unattended --unattendedmodeui none"
	elif [[ $selection == "Red Giant" ]]; then
        echo "Selection ........: Red Giant" | tee -a $LOG       
        downloader="net.maxon.redgiant-installer"
        bundleID="net.maxon.redgiant.installer"
        installCommand="/Contents/MacOS/installbuilder.sh"
        installArguments="--mode unattended --unattendedmodeui none"
	elif [[ $selection == "RedShift" ]]; then
        echo "Selection ........: RedShift" | tee -a $LOG
        downloader="com.redshift3d.redshift-installer"
        bundleID="Redshift PKG. No BundleID"
	elif [[ $selection == "zBrush" ]]; then
        echo "Selection ........: zBrush" | tee -a $LOG       
        downloader="net.maxon.zbrush-installer"
        bundleID="net.maxon.appinstaller"
        installCommand="/Contents/MacOS/installbuilder.sh"
        installArguments="--mode unattended --unattendedmodeui none"
    else
        selection=""
	fi   	
}

# Choose an app with AppleScript
selectAppOSA() {
    arrayString=$(IFS=, ; echo "${appArray[*]}")
    # Build the AppleScript command as a string
    osaCommand="choose from list {\"${arrayString//,/\",\"}\"} with title \"One Jamf | MAXON Installer\" with prompt \"Make a selection:\""
    selection=$( /usr/bin/osascript -e "$osaCommand" )

    if [[ $selection == "false" ]]; then
        echo "ERROR: Cancelled making a selection" | tee -a $LOG
        "/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action" -title "One Jamf | MAXON Installer" -message "Cancelled: Make a selection"
        exitERROR
    elif [[ $selection == "Cinema 4D" ]]; then
        echo "Selection OSA.....: Cinema 4D" | tee -a $LOG
    elif [[ $selection == "zBrush" ]]; then
        echo "Selection OSA.....: zBrush" | tee -a $LOG
    elif [[ $selection == "RedShift" ]]; then
        echo "Selection OSA.....: RedShift" | tee -a $LOG
    elif [[ $selection == "Red Giant" ]]; then
        echo "Selection OSA.....: Red Giant" | tee -a $LOG
    fi
appSettings
}

# Choose an app from the command line
selectAppCLI() {
    echo ""
    echo "Select the software to install"
    PS3="Enter the number for your choice: "
    select selection in "${appArray[@]}"; do
        case $selection in
            "Cinema 4D")
                echo "Selection CLI.....: Cinema 4D" | tee -a $LOG
                break  ;;
            "zBrush")
                echo "Selection CLI.....: zBrush" | tee -a $LOG       
                break  ;; 
            "RedShift")
                echo "Selection CLI.....: RedShift" | tee -a $LOG
                break  ;;
            "Red Giant")
                echo "Selection CLI.....: Red Giant" | tee -a $LOG
                break  ;;
            *) echo "Invalid option $REPLY";;  
        esac
    done
    appSettings
}


# Needs to run sudo as user, Delinea could cause issues 
download() {
    mx1cli package download $downloader | tee -a $LOG
    sleep 3
    if [[ -z "$(ls -A "$DLfolder/$installer")" ]]; then
        echo "ERROR: No contents to process in $DLfolder/$installer." | tee -a $LOG
        exitError
    else
        # To allow non-admins to remove
        chown -R $currentUser $DLfolder
    fi
}


installDMG() {
    echo "Mounting DMG .....: $file" | tee -a $LOG
    volume_path=$( hdiutil attach "$file" -nobrowse | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/"))}' )
    sleep 3
    if [[ -d "$volume_path" ]]; then
        echo "Mountpoint .......: $volume_path" | tee -a $LOG
        app_found=false
        for app in "$volume_path"/*.app; do
            if [[ -d "$app" ]]; then
                BundleInfo
                checkDevID
                echo "Found ............: $app" | tee -a $LOG
                app_found=true
                echo "Installing .......: $bundle_name $bundle_version" | tee -a $LOG
                install_executable="$app/$installCommand"
                sudo env bash -c "\"$install_executable\" $installArguments" > /dev/null 2>&1
                hdiutil unmount "$volume_path"
            fi
            "/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action" -title "One Jamf | MAXON Installer" -message "INSTALLED: $bundle_name $bundle_version"
        done

    if [[ ! $app_found ]]; then
        echo "ERROR: No matching installer found in DMG." | tee -a $LOG
        hdiutil unmount "$volume_path"
        exitError
    fi
    else
        echo "ERROR: Failed to mount DMG." | tee -a $LOG
        exitError
    fi
}


installZIP() {
    echo "Location .........: "$DLfolder/$downloader"" | tee -a $LOG
    echo "Unzipping ........: $file" | tee -a $LOG
    unzip -o "$file" -d "$DLfolder/$downloader" > /dev/null 2>&1
    sleep 2
    app_found=false
    for app in $DLfolder/$downloader/*.app; do
        echo "Found ............: $app" | tee -a $LOG
        if [[ -d "$app" ]]; then
            BundleInfo
            app_found=true
            echo "Installing .......: $bundle_name $bundle_version" | tee -a $LOG
            install_executable="$app/$installCommand"
            sudo env bash -c "\"$install_executable\" $installArguments" > /dev/null 2>&1
        fi
    "/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action" -title "One Jamf | MAXON Installer" -message "INSTALLED: $bundle_name $bundle_version"
    done
    if [[ ! $app_found ]]; then
        echo "ERROR: No matching installer found." | tee -a $LOG
        exitError
    fi
}


installPKG() {
    echo "Found ............: $file" | tee -a $LOG
    echo "Installing .......: $bundleID" | tee -a $LOG
    sudo installer -pkg "$file" -target /
    "/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action" -title "One Jamf | MAXON Installer" -message "INSTALLED: $file"
}

install() {
    for file in "$DLfolder/$downloader"/*; do
        # Install from DMG
        if [[ "$file" == *.dmg ]]; then
            installDMG
        # Install an App from a ZIP
        elif [[ "$file" == *.zip ]]; then
            installZIP
        # Install from a PKG
        elif [[ "$file" == *.pkg ]]; then
            installPKG
        else
            echo "ERROR: Unsupported file type: $file" | tee -a $LOG
            exitError
        fi
    done
}


exitError() {
    TIME_DURATION=$SECONDS
    echo "$(date +%Y%m%d-%H%M%S) EXITING HARD - Duration: $(($TIME_DURATION / 60)) minutes and $(($TIME_DURATION % 60 )) seconds" | tee -a $LOG
    clearDownloads
    exit 1
}

exitSuccess() {
    TIME_DURATION=$SECONDS
    echo "$(date +%Y%m%d-%H%M%S) FINISHED - Duration: $(($TIME_DURATION / 60)) minutes and $(($TIME_DURATION % 60 )) seconds" | tee -a $LOG
    clearDownloads
    exit 0
}


######### THE JOB

sanityCheck
clearDownloads

# If app not selected in Jamf policy run CLI or OSA to chose an app
if [[ $selection ]]; then 
    echo "Selection: $selection"
else
    if [[ "$appSelect" == "CLI" ]]; then
        selectAppCLI
    elif [[ "$appSelect" == "OSA" ]]; then
        selectAppOSA
    else
        echo "ERROR: No way of choosing what to install" | tee -a $LOG
        exitError
    fi
fi

download
install

exitSuccess

