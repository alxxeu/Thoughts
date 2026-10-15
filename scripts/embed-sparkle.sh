#!/bin/bash
# Фаза сборки "Embed Sparkle (Direct)": кладёт Sparkle.framework в приложение,
# подписывает его части (как велит документация Sparkle для песочницы).
# Адрес ленты и открытый ключ EdDSA — в Thoughts-Direct-Info.plist.
set -euo pipefail
"$SRCROOT/scripts/fetch-sparkle.sh"

fw="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"
mkdir -p "$(dirname "$fw")"
rm -rf "$fw"
ditto --noextattr --noqtn "$SRCROOT/Vendor/Sparkle/Sparkle.framework" "$fw"
xattr -cr "$fw"

id="${EXPANDED_CODE_SIGN_IDENTITY:--}"
v="$fw/Versions/B"
codesign -f -s "$id" -o runtime --timestamp=none "$v/XPCServices/Installer.xpc"
codesign -f -s "$id" -o runtime --timestamp=none --preserve-metadata=entitlements "$v/XPCServices/Downloader.xpc"
codesign -f -s "$id" -o runtime --timestamp=none "$v/Autoupdate"
codesign -f -s "$id" -o runtime --timestamp=none "$v/Updater.app"
codesign -f -s "$id" -o runtime --timestamp=none "$fw"

