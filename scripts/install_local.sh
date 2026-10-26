#!/usr/bin/env bash
# Builds a Release app, replaces /Applications/Murmur.app and restarts it.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build_release.sh "$@"

if pgrep -x Murmur >/dev/null; then
  osascript -e 'quit app "Murmur"' >/dev/null 2>&1 || true
  for _ in {1..50}; do
    pgrep -x Murmur >/dev/null || break
    sleep 0.1
  done
  pkill -x Murmur 2>/dev/null || true
fi

rm -rf /Applications/Murmur.app
ditto build/Murmur.app /Applications/Murmur.app
open /Applications/Murmur.app
echo "Installed /Applications/Murmur.app"
