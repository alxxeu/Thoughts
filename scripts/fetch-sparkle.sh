#!/bin/bash
# Sparkle для Direct-сборки (GitHub, Homebrew, сайт) — в Vendor/Sparkle, вне git.
# Версия и SHA-256 закреплены: обновлять обе строки вместе.
set -euo pipefail
VERSION=2.9.6
SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/Vendor/Sparkle"
[ -f "$dest/.version" ] && [ "$(cat "$dest/.version")" = "$VERSION" ] && exit 0
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/sparkle.tar.xz" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"
echo "$SHA256  $tmp/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null
rm -rf "$dest" && mkdir -p "$dest"
tar -xJf "$tmp/sparkle.tar.xz" -C "$dest"
echo "$VERSION" > "$dest/.version"
rm -rf "$tmp"
