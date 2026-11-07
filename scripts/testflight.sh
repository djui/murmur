#!/bin/zsh
# Archives the iOS app (MurmurMobile) and uploads it to App Store Connect. Builds land in TestFlight;
# the "Internal" group gets every build automatically.
#
# Usage: scripts/testflight.sh   (make testflight)
# Env: DEVELOPMENT_TEAM (default 8DR8DB9W22).
# Signs and uploads with an App Store Connect API key when there is one, so Xcode needn't be signed in:
# ASC_KEY_ID (default: the only ~/.appstoreconnect/private_keys/AuthKey_<id>.p8) and ASC_ISSUER_ID
# (default: the contents of ~/.appstoreconnect/issuer_id). Otherwise Xcode's account for the team is used.
set -euo pipefail
cd "$(dirname "$0")/.."

team="${DEVELOPMENT_TEAM:-8DR8DB9W22}"
out=build/ios
archive=$out/Murmur.xcarchive
mkdir -p $out

keys=~/.appstoreconnect/private_keys
key_id="${ASC_KEY_ID:-}"
if [[ -z "$key_id" ]]; then
  found=($keys/AuthKey_*.p8(N))
  (( ${#found} == 1 )) && key_id="${${found[1]:t:r}#AuthKey_}"
fi
issuer="${ASC_ISSUER_ID:-$(cat ~/.appstoreconnect/issuer_id 2>/dev/null || true)}"
auth=()
if [[ -n "$key_id" && -n "$issuer" && -f $keys/AuthKey_$key_id.p8 ]]; then
  auth=(-authenticationKeyPath $keys/AuthKey_$key_id.p8 -authenticationKeyID $key_id -authenticationKeyIssuerID $issuer)
  echo "Signing with App Store Connect API key $key_id" >&2
fi
# A fresh archive and export each time (build output only).
rm -rf $archive $out/export

xcodegen generate --quiet
xcodebuild -project Murmur.xcodeproj -scheme MurmurMobile -configuration Release \
  -destination 'generic/platform=iOS' -archivePath $archive -derivedDataPath build/iOSRelease \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates $auth archive

cat > $out/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>$team</string>
	<key>signingStyle</key><string>automatic</string>
	<key>uploadSymbols</key><true/>
	<key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath $archive -exportOptionsPlist $out/ExportOptions.plist \
  -exportPath $out/export -allowProvisioningUpdates $auth
echo "Uploaded. It shows in TestFlight once App Store Connect has processed it (usually 5–15 minutes)."
