#!/usr/bin/env bash
# Runs on a Mac with Xcode. Tests PinblockCore, generates the Xcode project,
# and packages an ad-hoc (or fully unsigned) IPA that Sideloadly can re-sign.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

if [ -d /Applications ]; then
  latest="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "${latest}" ]; then
    sudo xcode-select -s "${latest}" || true
  fi
fi

echo "== Xcode =="
xcodebuild -version
swift --version

echo "== Unit tests =="
swift test --package-path PinblockCore 2>&1 | tee build/test-log.txt

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

echo "== Xcode project =="
xcodegen generate

archive() {
  xcodebuild \
    -project Pinblock.xcodeproj \
    -scheme Pinblock \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$PWD/build/Pinblock.xcarchive" \
    archive \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    CODE_SIGNING_REQUIRED=NO \
    "$@"
}

echo "== Archive =="
rm -rf build/Pinblock.xcarchive
if ! archive CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY="-"; then
  echo "Ad-hoc signature failed. Retrying with code signing disabled."
  rm -rf build/Pinblock.xcarchive
  archive CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""
fi

APP="$(find build/Pinblock.xcarchive/Products -name '*.app' -type d | head -n 1)"
if [ -z "${APP}" ]; then
  echo "The archive did not contain an .app bundle." >&2
  exit 1
fi

rm -rf build/Payload
mkdir -p build/Payload
cp -R "${APP}" build/Payload/
rm -rf build/Payload/*.app/_CodeSignature
rm -f build/Pinblock-unsigned.ipa
(
  cd build
  zip -r -y Pinblock-unsigned.ipa Payload
)
echo "IPA ready: build/Pinblock-unsigned.ipa"
