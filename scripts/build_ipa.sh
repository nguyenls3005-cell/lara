#!/usr/bin/env bash
# build_ipa.sh — patch edition, boss man
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCF="$ROOT/Frameworks/AirliftFFI.xcframework/ios-arm64"
HEADERS="$XCF/Headers"

# 1) Nuke the duplicated modulemap that Xcode copy-steps into BuildProducts/include.
#    We keep ONE authoritative map (the one inside the xcframework) and feed it
#    through the bridging header path instead of a raw HEADER_SEARCH_PATHS.
STAGE="$ROOT/.axiom_stage/headers"
rm -rf "$STAGE"
mkdir -p "$STAGE"

# Copy headers WITHOUT module.modulemap so no duplicate module gets discovered
find "$HEADERS" -maxdepth 1 -type f ! -name 'module.modulemap' -exec cp {} "$STAGE/" \;

# Single canonical modulemap lives here
cat > "$ROOT/.axiom_stage/AirliftFFI.modulemap" <<'EOF'
module AirliftFFI {
    header "airlift_ffi.h"
    export *
}
EOF

# 2) Wipe stale derived-data include caches that hold the duplicated map
DERIVED="/Users/runner/Library/Developer/Xcode/DerivedData"
find "$DERIVED" -type f -path '*ArchiveIntermediates*/*/BuildProductsPath/*/include/module.modulemap' -delete 2>/dev/null || true

# 3) Clean build w/o the double modulemap. Notice: HEADER_SEARCH_PATHS no longer
#    points at the xcframework Headers dir. We only pass a fmodule-map-file ONCE.
xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64 \
  "OTHER_LDFLAGS=-force_load $XCF/libairlift_ffi.a \
     -framework Security -framework SystemConfiguration \
     -framework UIKit -framework Foundation \
     -framework NetworkExtension -framework MobileCoreServices" \
  "SWIFT_OBJC_BRIDGING_HEADER=$ROOT/lara/lara-Bridging-Header.h" \
  "FRAMEWORK_SEARCH_PATHS=$XCF" \
  "HEADER_SEARCH_PATHS=$STAGE" \
  "SWIFT_INCLUDE_PATHS=$ROOT/.axiom_stage" \
  "OTHER_SWIFT_FLAGS=-Xcc -fmodule-map-file=$ROOT/.axiom_stage/AirliftFFI.modulemap" \
  "CLANG_MODULES_AUTOLINK=YES" \
  "CODE_SIGNING_ALLOWED=NO" \
  "CODE_SIGNING_REQUIRED=NO" \
  "CODE_SIGN_IDENTITY=" \
  "CODE_SIGN_ENTITLEMENTS=Config/lara.entitlements" \
  archive -archivePath "$ROOT/build/lara.xcarchive"