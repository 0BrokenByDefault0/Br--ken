#!/usr/bin/env bash
# Builds an unsigned Broken.ipa (for sideloading) in the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."
rm -rf Payload Broken.ipa
xcodebuild -project Broken.xcodeproj -scheme Broken -configuration Release \
  -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/Broken.app Payload/
zip -qry Broken.ipa Payload
echo "Built $(pwd)/Broken.ipa"
