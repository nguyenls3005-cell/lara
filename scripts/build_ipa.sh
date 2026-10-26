#!/bin/bash
set -euo pipefail

CURRENT_DIR="$(pwd)"
FRAMEWORK_PATH="${CURRENT_DIR}/Frameworks/AirliftFFI.xcframework/ios-arm64"
BRIDGING_HEADER_PATH="${CURRENT_DIR}/lara/lara-Bridging-Header.h"
HEADER_PATH="${CURRENT_DIR}/Frameworks/AirliftFFI.xcframework/ios-arm64/Headers"

rm -rf build/
mkdir -p build

echo "Build Started!"
echo

xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64 \
  FRAMEWORK_SEARCH_PATHS="${FRAMEWORK_PATH}" \
  HEADER_SEARCH_PATHS="${HEADER_PATH}" \
  OTHER_LDFLAGS="-force_load ${FRAMEWORK_PATH}/libairlift_ffi.a -framework Security -framework SystemConfiguration -framework UIKit -framework Foundation -framework NetworkExtension" \
  SWIFT_OBJC_BRIDGING_HEADER="${BRIDGING_HEADER_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Config/lara.entitlements" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive"

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app at $APP_PATH"
  exit 1
fi
rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"

plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/lara.app/Info.plist"

if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi
ldid -SConfig/lara.entitlements "$PWD/build/Payload/lara.app/lara"
(cd "$PWD/build" && /usr/bin/zip -qry lara.ipa Payload)

echo
echo "build successful!"
echo "ipa at: build/lara.ipa"
exit 0