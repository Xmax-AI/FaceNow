#!/bin/sh
set -eu
driver='/Library/Audio/Plug-Ins/HAL/FaceNowMicrophone.driver'
if [ -e "$driver" ]; then
    identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$driver/Contents/Info.plist")
    [ "$identifier" = 'com.xmax.facenow.microphone.driver' ] || exit 1
    /bin/rm -rf "$driver"
fi
# Never restart system audio or interrupt calls. Removal completes after restart.
exit 0
