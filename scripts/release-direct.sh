#!/bin/bash
# Сборка Thoughts вне App Store (GitHub, Homebrew, сайт): Direct-конфигурация
# со Sparkle, подпись Developer ID, нотаризация, DMG, appcast.xml и загрузка
# в релиз GitHub v<версия>.
#
#   scripts/release-direct.sh            — собрать и подготовить всё в build/direct
#   scripts/release-direct.sh --upload   — то же и загрузить в релиз (спросит)
#
# Один раз нужно: сертификат Developer ID Application в связке ключей,
# профиль нотаризации "notary" (xcrun notarytool store-credentials) и ключ
# Sparkle (Vendor/Sparkle/bin/generate_keys) — закрытый ключ в связке ключей.
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(pwd)
# Сборка — вне ~/Documents: синхронизация iCloud Drive вешает на файлы
# com.apple.FinderInfo, и подпись перестаёт проходить проверку.
out="${TMPDIR%/}/thoughts-direct"
final="$root/build/direct"
repo=alxxeu/Thoughts

scripts/fetch-sparkle.sh
rm -rf "$out" && mkdir -p "$out"

echo "→ Архив (Direct)"
xcodebuild archive -scheme Thoughts -configuration Direct \
  -archivePath "$out/Thoughts.xcarchive" -allowProvisioningUpdates -quiet

cat > "$out/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>QHST33HHWS</string>
</dict></plist>
EOF

echo "→ Экспорт с подписью Developer ID"
xcodebuild -exportArchive -archivePath "$out/Thoughts.xcarchive" \
  -exportOptionsPlist "$out/export.plist" -exportPath "$out/export" -allowProvisioningUpdates -quiet
app="$out/export/Thoughts.app"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
codesign --verify --deep --strict "$app"

echo "→ Нотаризация приложения $version"
ditto -c -k --keepParent "$app" "$out/Thoughts.zip"
xcrun notarytool submit "$out/Thoughts.zip" --keychain-profile notary --wait
xcrun stapler staple "$app"

echo "→ DMG"
stage="$out/dmg"
mkdir -p "$stage"
ditto "$app" "$stage/Thoughts.app"
ln -s /Applications "$stage/Applications"
dmg="$out/Thoughts-$version.dmg"
hdiutil create -volname "Thoughts" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
codesign -s "Developer ID Application" --timestamp "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile notary --wait
xcrun stapler staple "$dmg"
spctl -a -t open --context context:primary-signature -v "$dmg"
spctl -a -t exec -v "$app"

echo "→ appcast.xml"
updates="$out/updates"
mkdir -p "$updates"
cp "$dmg" "$updates/"
# Прежние версии остаются в ленте: берём appcast.xml из последнего релиза.
curl -fsSL -o "$updates/appcast.xml" "https://github.com/$repo/releases/latest/download/appcast.xml" || rm -f "$updates/appcast.xml"
Vendor/Sparkle/bin/generate_appcast "$updates" \
  --download-url-prefix "https://github.com/$repo/releases/download/v$version/" \
  --full-release-notes-url "https://github.com/$repo/releases/tag/v$version"
cp "$updates/appcast.xml" "$out/appcast.xml"
cp "$dmg" "$out/Thoughts.dmg"   # постоянная ссылка: releases/latest/download/Thoughts.dmg

rm -rf "$final" && mkdir -p "$final"
cp "$dmg" "$out/Thoughts.dmg" "$out/appcast.xml" "$final/"
echo "Готово: $final/Thoughts-$version.dmg"
echo "SHA-256: $(shasum -a 256 "$dmg" | cut -d' ' -f1)"

if [ "${1:-}" = "--upload" ]; then
  read -r -p "Загрузить Thoughts-$version.dmg, Thoughts.dmg и appcast.xml в релиз v$version на GitHub? [y/N] " answer
  [ "$answer" = y ] || exit 0
  gh release upload "v$version" "$final/Thoughts-$version.dmg" "$final/Thoughts.dmg" "$final/appcast.xml" --repo "$repo" --clobber
fi
