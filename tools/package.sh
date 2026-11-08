#!/bin/zsh
set -eu
cd "${0:A:h}/.."
app="${WINDOWRAIL_OUTPUT_APP:-$PWD/WindowRail.app}"
mkdir -p dist
archs=$(lipo -archs "$app/Contents/MacOS/WindowRail")
if [[ "$archs" == *arm64* && "$archs" == *x86_64* ]]; then suffix=universal2; else suffix="$archs"; fi
name="WindowRail-${WINDOWRAIL_VERSION:-dev}-$suffix.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$name"
(cd dist && shasum -a 256 "$name" > "$name.sha256")
echo "Packaged: dist/$name"
