#!/bin/zsh
# Archives the iOS app (MurmurMobile) and uploads it to App Store Connect. Builds land in TestFlight;
# the "Internal" group gets every build automatically.
#
# Usage: scripts/testflight.sh   (make testflight)
# Env: DEVELOPMENT_TEAM (default 8DR8DB9W22). Xcode must be signed in to that team.
set -euo pipefail
cd "$(dirname "$0")/.."

team="${DEVELOPMENT_TEAM:-8DR8DB9W22}"
out=build/ios
archive=$out/Murmur.xcarchive
mkdir -p $out
# A fresh archive and export each time (build output only).
rm -rf $archive $out/export

xcodegen generate --quiet
xcodebuild -project Murmur.xcodeproj -scheme MurmurMobile -configuration Release \
  -destination 'generic/platform=iOS' -archivePath $archive -derivedDataPath build/iOSRelease \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates archive

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
  -exportPath $out/export -allowProvisioningUpdates
echo "Uploaded. It shows in TestFlight once App Store Connect has processed it (usually 5–15 minutes)."
