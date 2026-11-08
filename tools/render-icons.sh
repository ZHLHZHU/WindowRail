#!/bin/zsh
set -eu
cd "${0:A:h}/.."
temporary=$(mktemp -d "${TMPDIR:-/tmp}/windowrail-icons.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
mkdir -p "$temporary/WindowRail.iconset" docs/images
cp tools/render-icons.swift "$temporary/main.swift"
swiftc -swift-version 5 Sources/WindowRail/Views/AppArtwork.swift "$temporary/main.swift" -o "$temporary/render"
"$temporary/render" "$temporary/WindowRail.iconset" "$PWD/docs/images/app-icon.png"
iconutil -c icns "$temporary/WindowRail.iconset" -o Sources/WindowRail/Resources/WindowRail.icns
print 'Rendered app icon in all macOS iconset sizes.'
