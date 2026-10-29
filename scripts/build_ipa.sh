#!/usr/bin/env bash
# build_ipa.sh — round 3, no custom modulemap, let Xcode own the copy step
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCF="$ROOT/Frameworks/AirliftFFI.xcframework/ios-arm64"

# 1) Rip out the custom stage that was shadowing the real module
rm -rf "$ROOT/.axiom_stage"

# 2) Blow away any stray module.modulemap in the include folder that Xcode's
#    previous runs left behind — those are the shadowers now.
find "$ROOT/build" -type f -name 'module.modulemap' -path '*include*' -delete 2>/dev/null || true

# 3) Clear DerivedData shadow caches for this project only
DERIVED="/Users/runner/Library/Developer/Xcode/DerivedData"
if [ -d "$DERIVED" ]; then
  find "$DERIVED" -maxdepth 1 -type d -name 'lara-*' -exec rm -rf {} + 2>/dev/null || true
fi

# 4) Build. The big change: HEADER_SEARCH_PATHS is EMPTY. We do NOT pass any
#    custom -fmodule-map-file. ProcessXCFramework will drop the xcframework's
#    single canonical module.modulemap into BuildProductsPath/Debug-iphoneos/include
#    and Xcode adds that path automatically. ONE modulemap. No shadows.
xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64 \
  "OTHER_LDFLAGS=-force_load $XCF/libairlift_ffi.a -framework Security -framework SystemConfiguration -framework UIKit -framework Foundation -framework NetworkExtension -framework MobileCoreServices" \
  "SWIFT_OBJC_BRIDGING_HEADER=$ROOT/lara/lara-Bridging-Header.h" \
  "FRAMEWORK_SEARCH_PATHS=$XCF" \
  "HEADER_SEARCH_PATHS=" \
  "CODE_SIGNING_ALLOWED=NO" \
  "CODE_SIGNING_REQUIRED=NO" \
  "CODE_SIGN_IDENTITY=" \
  "CODE_SIGN_ENTITLEMENTS=Config/lara.entitlements" \
  archive -archivePath "$ROOT/build/lara.xcarchive"