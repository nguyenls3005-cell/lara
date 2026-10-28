#!/bin/bash
set -euo pipefail

# ============================================================
# lara IPA build script (unsigned, sideload-ready)
# ============================================================
# Notes:
#   - AirliftFFI.xcframework is linked via project.pbxproj, so
#     Xcode auto-resolves its headers + static lib. Do NOT
#     override HEADER_SEARCH_PATHS or FRAMEWORK_SEARCH_PATHS to
#     point at the xcframework's Headers/ folder — that causes a
#     duplicate module.modulemap and cascading "unable to resolve
#     module dependency" errors (redefinition of module 'AirliftFFI').
#   - The bridging header imports "airlift.h", which Xcode finds
#     via its auto-copied BuildProductsPath/.../include/ directory.
# ============================================================

set -x

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$WORKSPACE_DIR"

BUILD_DIR="$WORKSPACE_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/lara.xcarchive"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE_PATH"

echo "Build Started!"
echo "Workspace: $WORKSPACE_DIR"

# ------------------------------------------------------------
# Sanity: confirm the xcframework is present and contains
# both a static lib and a headers directory.
# ------------------------------------------------------------
XCFRAMEWORK_DIR="$WORKSPACE_DIR/Frameworks/AirliftFFI.xcframework"
if [ ! -d "$XCFRAMEWORK_DIR" ]; then
    echo "[!] AirliftFFI.xcframework not found at $XCFRAMEWORK_DIR"
    exit 1
fi

if [ ! -f "$XCFRAMEWORK_DIR/ios-arm64/libairlift_ffi.a" ]; then
    echo "[!] AirliftFFI.xcframework missing static lib slice for ios-arm64"
    exit 1
fi

if [ ! -f "$XCFRAMEWORK_DIR/ios-arm64/Headers/airlift.h" ]; then
    echo "[!] AirliftFFI.xcframework missing airlift.h"
    exit 1
fi

# ------------------------------------------------------------
# xcodebuild archive
# ------------------------------------------------------------
xcodebuild \
    -project lara.xcodeproj \
    -scheme lara \
    -configuration Debug \
    -sdk iphoneos \
    -arch arm64 \
    SWIFT_OBJC_BRIDGING_HEADER="$WORKSPACE_DIR/lara/lara-Bridging-Header.h" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="$WORKSPACE_DIR/Config/lara.entitlements" \
    archive \
    -archivePath "$ARCHIVE_PATH"

echo "Archive complete: $ARCHIVE_PATH"

# ------------------------------------------------------------
# Package unsigned IPA
# ------------------------------------------------------------
APP_PATH="$ARCHIVE_PATH/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
    echo "[!] Expected app not found at $APP_PATH"
    exit 1
fi

PAYLOAD_DIR="$BUILD_DIR/Payload"
IPA_PATH="$BUILD_DIR/lara.ipa"

rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
cp -R "$APP_PATH" "$PAYLOAD_DIR/"

rm -f "$IPA_PATH"
( cd "$BUILD_DIR" && zip -r lara.ipa Payload )

echo "IPA ready: $IPA_PATH"