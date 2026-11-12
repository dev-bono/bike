#!/usr/bin/env bash
# Archive the app and upload it to App Store Connect (TestFlight).
# Run from the ios/ directory after `xcodegen generate`.
# Required env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (contents of AuthKey_XXXX.p8), TEAM_ID
# Optional env: BUNDLE_ID, BUILD_NUMBER
set -euo pipefail

missing=()
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 TEAM_ID; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
if [ ${#missing[@]} -gt 0 ]; then
  echo "::error::GitHub Secrets가 없습니다: ${missing[*]}  (Settings > Secrets and variables > Actions)"
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.devbono.bikeride}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
WORK="${RUNNER_TEMP:-$(mktemp -d)}"
KEY_PATH="$WORK/AuthKey_${ASC_KEY_ID}.p8"
ARCHIVE="$WORK/BikeRide.xcarchive"
EXPORT_DIR="$WORK/export"

printf '%s\n' "$ASC_KEY_P8" > "$KEY_PATH"

AUTH=(-allowProvisioningUpdates
      -authenticationKeyPath "$KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "▶ Archive (bundle=$BUNDLE_ID build=$BUILD_NUMBER)"
xcodebuild archive \
  -project BikeRide.xcodeproj \
  -scheme BikeRide \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  "${AUTH[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Automatic

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
EOF

echo "▶ Export & upload to App Store Connect"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -exportPath "$EXPORT_DIR" \
  "${AUTH[@]}"

rm -f "$KEY_PATH"
echo "✅ 업로드 완료. App Store Connect > TestFlight에서 처리(약 5~15분) 후 설치할 수 있습니다."
