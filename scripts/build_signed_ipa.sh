#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/NuvioTV.xcodeproj"
SCHEME="NuvioTV"
CONFIGURATION="${CONFIGURATION:-Debug}"
TEAM_ID="${DEVELOPMENT_TEAM:-${1:-}}"
BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-com.anshumanbiswas.nuvio.tvos}"
DERIVED_DATA="$ROOT_DIR/build/DerivedDataSigned"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA/Build/Products/${CONFIGURATION}-appletvos/NuvioTV.app"
IPA_PATH="$DIST_DIR/NuvioTV-tvOS-signed.ipa"
DESTINATION="generic/platform=tvOS"

if [[ -n "${DEVICE_ID:-}" ]]; then
  DESTINATION="id=$DEVICE_ID"
fi

if [[ -z "$TEAM_ID" || "$TEAM_ID" == *"@"* ]]; then
  echo "Usage: DEVELOPMENT_TEAM=YOURTEAMID $0"
  echo "   or: $0 YOURTEAMID"
  echo
  echo "DEVELOPMENT_TEAM must be the 10-character Apple Developer Team ID, not your Apple ID email."
  echo "Find it in Xcode > Settings > Accounts after adding your Apple ID."
  exit 2
fi

cd "$ROOT_DIR"
rm -rf "$DERIVED_DATA" "$DIST_DIR/Payload" "$IPA_PATH"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_STYLE=Automatic \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app not found: $APP_PATH"
  exit 1
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/codesign -dv --verbose=2 "$APP_PATH" 2>&1 | sed -n '1,80p'

mkdir -p "$DIST_DIR/Payload"
cp -R "$APP_PATH" "$DIST_DIR/Payload/"
(
  cd "$DIST_DIR"
  /usr/bin/zip -qry "$IPA_PATH" Payload
)
rm -rf "$DIST_DIR/Payload"

echo "Signed IPA: $IPA_PATH"
shasum -a 256 "$IPA_PATH"
