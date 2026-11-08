#!/bin/zsh
set -eu
cd "${0:A:h}/.."
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/windowrail-previews.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
ditto Sources/WindowRail/Resources "$TEMP_DIR/WindowRailResources.bundle"
cp tools/screenshots.swift "$TEMP_DIR/main.swift"
sources=(Sources/WindowRail/**/*.swift(.N))
sources=("${(@)sources:#Sources/WindowRail/main.swift}")
swiftc -swift-version 5 "${sources[@]}" "$TEMP_DIR/main.swift" -o "$TEMP_DIR/render"
mkdir -p docs/images/en docs/images/zh-CN
"$TEMP_DIR/render" "$PWD/docs/images/en" en -AppleLanguages '(en)'
"$TEMP_DIR/render" "$PWD/docs/images/zh-CN" zh-Hans -AppleLanguages '(zh-Hans)'
