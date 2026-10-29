#!/usr/bin/env bash
# build_ipa.sh — round 4, bypass xcframework, feed raw .a + headers
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SRC="$ROOT/Frameworks/AirliftFFI.xcframework/ios-arm64"
STAGE="$ROOT/build/airlift"
rm -rf "$STAGE"
mkdir -p "$STAGE/headers"

# 1) Copy the raw static lib + headers out of the wrapper
cp "$SRC/libairlift_ffi.a"      "$STAGE/libairlift_ffi.a"
cp "$SRC/Headers/"*.h           "$STAGE/headers/"

# 2) Delete the modulemap from the staged headers — the bridging header does
#    the importing, so we do NOT want any module here competing with it.
rm -f "$STAGE/headers/module.modulemap"

# 3) Nuke any old shadowing modulemap / stale derived data for this project
find "$ROOT/build" -name 'module.modulemap' -delete 2>/dev/null || true
rm -rf "$ROOT/build/lara.xcarchive" 2>/dev/null || true
find /Users/runner/Library/Developer/Xcode/DerivedData -maxdepth 1 \
     -type d -name 'lara-*' -exec rm -rf {} + 2>/dev/null || true

# 4) Build. No xcframework, no ProcessXCFramework, no modulemap, no shadow.
#    We point FRAMEWORK_SEARCH_PATHS at the staging dir (so the .a is found)
#    and HEADER_SEARCH_PATHS at the header copy. Bridging header imports work.
xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64 \
  "OTHER_LDFLAGS=-force_load $STAGE/libairlift_ffi.a -framework Security -framework SystemConfiguration -framework UIKit -framework Foundation -framework NetworkExtension -framework MobileCoreServices" \
  "SWIFT_OBJC_BRIDGING_HEADER=$ROOT/lara/lara-Bridging-Header.h" \
  "FRAMEWORK_SEARCH_PATHS=$STAGE" \
  "HEADER_SEARCH_PATHS=$STAGE/headers" \
  "CLANG_ENABLE_MODULES=YES" \
  "CLANG_MODULES_AUTOLINK=YES" \
  "CODE_SIGNING_ALLOWED=NO" \
  "CODE_SIGNING_REQUIRED=NO" \
  "CODE_SIGN_IDENTITY=" \
  "CODE_SIGN_ENTITLEMENTS=Config/lara.entitlements" \
  archive -archivePath "$ROOT/build/lara.xcarchive"