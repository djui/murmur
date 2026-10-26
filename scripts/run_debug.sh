#!/usr/bin/env bash
# Debug build and launch.
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -f Murmur/Assets.xcassets/AppIcon.appiconset/Contents.json ]] || swift scripts/make_icons.swift
xcodegen generate --quiet
xcodebuild -project Murmur.xcodeproj -scheme Murmur -configuration Debug \
  -derivedDataPath build/DerivedData -destination 'platform=macOS,arch=arm64' -quiet build
pkill -x Murmur 2>/dev/null || true
open build/DerivedData/Build/Products/Debug/Murmur.app
