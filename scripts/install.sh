#!/bin/bash
# Updates Consigliere on this Mac in one go:
#   1. gets the newest code from GitHub
#   2. builds the app (a Release build, so it runs fast)
#   3. signs it the same way every time, so macOS keeps its permissions
#   4. puts it in /Applications and starts it
#
# Run it from anywhere:   ~/Code/consigliere/scripts/install.sh
# It needs Xcode. It does not need Homebrew or xcodegen: the Xcode project is kept in the repo.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

if [ "${SKIP_PULL:-0}" != "1" ]; then
  say "1/4  Getting the newest code"
  # Xcode rewrites the project file whenever a setting is touched, which would block the update.
  # That file is generated anyway, so local changes to it are thrown away.
  git checkout -- App/Consigliere.xcodeproj 2>/dev/null || true
  git pull --ff-only
fi

say "2/4  Building (the first time takes a few minutes)"
BUILD="$REPO/App/build"
xcodebuild -project App/Consigliere.xcodeproj -scheme Consigliere -configuration Release \
  -derivedDataPath "$BUILD" -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build > "$BUILD.log" 2>&1 || {
    grep -E "error:" "$BUILD.log" | head -20
    echo "The build failed. The full log is in App/build.log. Paste the lines above to Claude."
    exit 1
  }
APP="$BUILD/Build/Products/Release/Consigliere.app"

say "3/4  Signing"
# macOS remembers permissions (microphone, Reminders, controlling Brave) per signature. Signing with the
# same Apple Development certificate every time keeps them. That certificate appears once you add your
# Apple ID in Xcode > Settings > Accounts. Without one, the app is signed "ad hoc", which also works but
# macOS may ask for the permissions again after each update.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
  codesign --force --deep --sign "$IDENTITY" "$APP"
  echo "Signed as: $IDENTITY"
else
  codesign --force --deep --sign - "$APP"
  echo "Signed ad hoc. To stop macOS asking for permissions after every update, add your Apple ID in Xcode > Settings > Accounts once."
fi

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
  say "Built and signed at $APP (not installed, SKIP_INSTALL=1)"
  exit 0
fi

say "4/4  Installing"
pkill -x Consigliere 2>/dev/null || true
# The app was called Brochacho until 26 October 2026. Stop and remove that copy too, so only one lives in the notch.
pkill -x Brochacho 2>/dev/null || true
sleep 0.5
rm -rf /Applications/Consigliere.app /Applications/Brochacho.app
cp -R "$APP" /Applications/
open /Applications/Consigliere.app
say "Done. Consigliere is running from /Applications."
