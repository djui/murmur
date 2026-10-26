#!/usr/bin/env bash
# Tests, bumps the version, builds a notarized DMG, updates the Sparkle appcast, tags, pushes and
# publishes a GitHub Release.
#
#   scripts/release.sh [patch|minor|major] ["release notes summary"]
#
# Needs: a Developer ID Application certificate, NOTARY_PROFILE (xcrun notarytool store-credentials),
# gh logged in, and the Sparkle signing key (run Sparkle's generate_keys once; put the public key in
# Murmur/Info.plist as SUPublicEDKey). The first release ships the version already in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."

PART="${1:-patch}"
SUMMARY="${2:-}"
case "$PART" in patch | minor | major) ;; *) echo "usage: $0 [patch|minor|major] [summary]" >&2; exit 2 ;; esac

command -v gh >/dev/null || { echo "gh is required (brew install gh)" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated; run: gh auth login" >&2; exit 1; }
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' Murmur/Info.plist >/dev/null 2>&1 \
  || { echo "Add SUPublicEDKey to Murmur/Info.plist first (see Sparkle's generate_keys)" >&2; exit 1; }

echo "Running tests…" >&2
swift test --package-path Packages/MurmurCore

current="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' project.yml | head -1)"
build="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: *\([0-9]*\).*/\1/p' project.yml | head -1)"
previous_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"

if [[ -z "$previous_tag" ]]; then
  version="$current"
else
  IFS=. read -r major minor patch <<<"$current"
  case "$PART" in
    major) version="$((major + 1)).0.0" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    patch) version="$major.$minor.$((patch + 1))" ;;
  esac
  build=$((build + 1))
fi
tag="v$version"
git rev-parse "$tag" >/dev/null 2>&1 && { echo "Tag $tag already exists" >&2; exit 1; }

sed -i '' -E "s/^( *MARKETING_VERSION: *)\"?[0-9.]+\"?/\1\"$version\"/" project.yml
sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *)[0-9]+/\1$build/" project.yml

echo "Building $tag…" >&2
scripts/build_release.sh --notarize
scripts/make_dmg.sh

mkdir -p dist
dmg="dist/Murmur-$version.dmg"
cp "build/Murmur-$version.dmg" "$dmg"

generate_appcast="$(find build/DerivedData/SourcePackages/artifacts -path '*Sparkle*/bin/generate_appcast' -type f | head -1)"
[[ -x "$generate_appcast" ]] || { echo "generate_appcast not found; build once so SwiftPM fetches Sparkle" >&2; exit 1; }
"$generate_appcast" \
  --download-url-prefix "https://github.com/djui/murmur/releases/download/$tag/" \
  -o dist/appcast.xml dist

git add -A
git commit -m "Release $tag${SUMMARY:+: $SUMMARY}" || true
git tag -a "$tag" -m "Murmur $version"
git push origin HEAD --tags

notes="${SUMMARY:-Murmur $version}"
if [[ -n "$previous_tag" ]]; then
  log="$(git log "$previous_tag..HEAD" --pretty='- %s' --no-merges | grep -v '^- Release v' || true)"
  notes="$notes"$'\n\n'"$log"
fi
gh release create "$tag" "$dmg" dist/appcast.xml --title "Murmur $version" --notes "$notes"
echo "Released $tag"
