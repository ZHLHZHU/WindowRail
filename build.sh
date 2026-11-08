#!/bin/zsh
set -eu
cd "${0:A:h}"
APP="${WINDOWRAIL_OUTPUT_APP:-$PWD/WindowRail.app}"
ARCHS="${WINDOWRAIL_ARCHS:-$(uname -m)}"
SIGNING_MODE="${WINDOWRAIL_SIGNING_MODE:-persistent}"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/windowrail-build.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
STAGED_APP="$BUILD_DIR/WindowRail.app"
mkdir -p "$STAGED_APP/Contents/MacOS"
sources=(Sources/WindowRail/**/*.swift(.N))
binaries=()
for arch in ${=ARCHS}; do
    if [[ "$arch" != arm64 && "$arch" != x86_64 ]]; then
        print -u2 "Unsupported architecture: $arch"; exit 1
    fi
    swiftc -target "$arch-apple-macosx13.0" -swift-version 5 -O -module-name WindowRail "${sources[@]}" -o "$BUILD_DIR/WindowRail-$arch"
    binaries+=("$BUILD_DIR/WindowRail-$arch")
done
lipo -create "${binaries[@]}" -output "$STAGED_APP/Contents/MacOS/WindowRail"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
mkdir -p "$STAGED_APP/Contents/Resources"
ditto Sources/WindowRail/Resources "$STAGED_APP/Contents/Resources"
ICON_FILE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$STAGED_APP/Contents/Info.plist")
if [[ ! -f "$STAGED_APP/Contents/Resources/$ICON_FILE" ]]; then
    print -u2 "Missing application icon: $ICON_FILE"; exit 1
fi
if [[ -n "${WINDOWRAIL_VERSION:-}" ]]; then
    if [[ ! "$WINDOWRAIL_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then print -u2 "Expected a numeric x.y.z version"; exit 1; fi
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $WINDOWRAIL_VERSION" "$STAGED_APP/Contents/Info.plist"
fi
case "$SIGNING_MODE" in
    persistent) python3 tools/signing.py sign "$STAGED_APP" ;;
    adhoc) codesign --force --sign - "$STAGED_APP" ;;
    pinned)
        : "${WINDOWRAIL_SIGNING_IDENTITY:?Set WINDOWRAIL_SIGNING_IDENTITY}"
        if [[ ! "$WINDOWRAIL_SIGNING_IDENTITY" =~ '^[0-9a-fA-F]{40}$' ]]; then print -u2 "Expected certificate SHA-1 fingerprint"; exit 1; fi
        requirement="identifier \"local.windowrail.app\" and certificate leaf = H\"$WINDOWRAIL_SIGNING_IDENTITY\""
        sign_args=(--force --sign "$WINDOWRAIL_SIGNING_IDENTITY" --timestamp=none --requirements "=designated => $requirement")
        if [[ -n "${WINDOWRAIL_KEYCHAIN:-}" ]]; then sign_args+=(--keychain "$WINDOWRAIL_KEYCHAIN"); fi
        codesign "${sign_args[@]}" "$STAGED_APP"
        codesign --verify --strict -R "= $requirement" "$STAGED_APP"
        ;;
    identity)
        : "${WINDOWRAIL_SIGNING_IDENTITY:?Set WINDOWRAIL_SIGNING_IDENTITY}"
        sign_args=(--force --sign "$WINDOWRAIL_SIGNING_IDENTITY" --options runtime --timestamp)
        if [[ -n "${WINDOWRAIL_KEYCHAIN:-}" ]]; then sign_args+=(--keychain "$WINDOWRAIL_KEYCHAIN"); fi
        codesign "${sign_args[@]}" "$STAGED_APP"
        ;;
    *) print -u2 "Unknown signing mode: $SIGNING_MODE"; exit 1 ;;
esac
codesign --verify --strict "$STAGED_APP"
mkdir -p "${APP:h}"
ditto "$STAGED_APP" "$APP"
codesign --verify --strict "$APP"
echo "Built: $APP"
