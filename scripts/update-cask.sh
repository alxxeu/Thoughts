#!/bin/bash
# Обновляет cask в alxxeu/homebrew-tap под новую версию DMG и пушит (спросит).
#   scripts/update-cask.sh build/direct/Thoughts-1.4.dmg [путь к клону tap]
set -euo pipefail
dmg=$1
tap=${2:-"$(cd "$(dirname "$0")/../.." && pwd)/homebrew-tap"}
version=$(basename "$dmg" .dmg); version=${version#Thoughts-}
sha=$(shasum -a 256 "$dmg" | cut -d' ' -f1)
cask="$tap/Casks/thoughts.rb"
sed -i '' -E "s/^  version \".*\"/  version \"$version\"/; s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$cask"
git -C "$tap" diff --stat
read -r -p "Закоммитить и запушить cask $version в alxxeu/homebrew-tap? [y/N] " answer
[ "$answer" = y ] || exit 0
git -C "$tap" add Casks/thoughts.rb
git -C "$tap" commit -qm "thoughts $version"
git -C "$tap" push -q
