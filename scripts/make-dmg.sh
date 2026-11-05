#!/bin/bash
# Собирает DMG-установщик: звёздный фон, приложение слева, Applications справа, стрелка «Drag to install».
#   scripts/make-dmg.sh <Thoughts.app> <выход.dmg>
# Раскладку окна задаёт Finder через AppleScript (нужен вошедший пользователь; при первом запуске
# macOS может спросить разрешение на управление Finder).
set -euo pipefail
app=$1; dmg=$2
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR%/}/thoughts-dmg.XXXXXX")
vol="Thoughts"

# Фон: PNG 1320×800 с 144 dpi — окно 660×400 pt, чёткое на Retina (многоразмерный TIFF Finder показывал вдвое крупнее).
swift "$here/dmg/background.swift" "$work/bg" >/dev/null

stage="$work/stage"
mkdir -p "$stage/.background"
ditto "$app" "$stage/Thoughts.app"
ln -s /Applications "$stage/Applications"
cp "$work/bg/background.png" "$stage/.background/background.png"

# Если с таким же именем уже смонтирован установщик (например, прошлый DMG) — отключаем, иначе том получит имя «Thoughts 1».
[ -d "/Volumes/$vol" ] && hdiutil detach "/Volumes/$vol" -quiet -force || true

rw="$work/rw.dmg"
hdiutil create -volname "$vol" -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw" >/dev/null
hdiutil attach "$rw" -mountpoint "/Volumes/$vol" -noverify -noautoopen >/dev/null

# Окно 660×400 (под размер фона): приложение слева, Applications справа, обе иконки по центру высоты.
osascript <<OSA
tell application "Finder"
  tell disk "$vol"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 542}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Thoughts.app" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 2
    -- Границы ещё раз в конце: после раскладки иконок Finder иногда возвращает прежний размер окна.
    set the bounds of container window to {200, 120, 860, 542}
    delay 2
    close
  end tell
end tell
OSA
sync; sleep 3
# Папка с фоном не должна светиться в окне.
SetFile -a V "/Volumes/$vol/.background" 2>/dev/null || true
hdiutil detach "/Volumes/$vol" -quiet
rm -f "$dmg"
hdiutil convert "$rw" -format UDZO -imagekey zlib-level=9 -o "$dmg" >/dev/null
rm -rf "$work"
echo "DMG: $dmg"
