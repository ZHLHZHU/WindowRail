#!/bin/zsh
set -eu
cd "${0:A:h}/.."
TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/windowrail-tests.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
ditto Sources/WindowRail/Resources "$TEMP_DIR/WindowRailResources.bundle"
sources=(Sources/WindowRail/**/*.swift(.N))
sources=("${(@)sources:#Sources/WindowRail/main.swift}")
swiftc -swift-version 5 -module-name WindowRailChecks "${sources[@]}" Tests/WindowRailChecks/main.swift -o "$TEMP_DIR/check"
"$TEMP_DIR/check"
