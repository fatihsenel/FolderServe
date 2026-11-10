#!/bin/bash
# Builds the Mac App Store version of FolderServe and exports it for App Store Connect.
#
#   scripts/appstore.sh            archive and export a signed .pkg into build/appstore/ (upload it with Transporter)
#   scripts/appstore.sh --upload   the same, then upload it straight to App Store Connect (needs an Apple ID signed in to Xcode)
#
# The App Store build is the same source compiled with `-D APPSTORE`, which removes the update checker (the Mac App Store
# forbids another update path). Setup and listing text are in docs/APP_STORE.md.
set -euo pipefail

TEAM_ID="${TEAM_ID:-XC7ZHWDHCA}"
UPLOAD=false
[ "${1:-}" = "--upload" ] && UPLOAD=true

cd "$(dirname "$0")/.."
VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -E '^\s*CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
# Outside the repo for the same reason as release.sh: iCloud-synced folders add Finder metadata that codesign refuses.
BUILD_DIR="${APPSTORE_WORK_DIR:-${TMPDIR:-/tmp}/folderserve-appstore}"
OUT_DIR="build/appstore"
ARCHIVE="$BUILD_DIR/FolderServe.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

fail() { echo "error: $*" >&2; exit 1; }

command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"
security find-identity -v -p codesigning | grep -q "Apple Distribution.*($TEAM_ID)" \
  || fail "no 'Apple Distribution' certificate for team $TEAM_ID in your keychain.
  Create it as the Account Holder (Xcode > Settings > Accounts > Manage Certificates > + > Apple Distribution),
  and the same for 'Mac Installer Distribution'."
echo "== FolderServe $VERSION ($BUILD), App Store build"

xcodegen generate >/dev/null
rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" "$OUT_DIR"

echo "== Archiving (Release, APPSTORE)"
xcodebuild archive -project FolderServe.xcodeproj -scheme FolderServe -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
  ENABLE_HARDENED_RUNTIME=YES SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) APPSTORE' \
  2>&1 | grep -E "error:|ARCHIVE" || true
[ -d "$ARCHIVE" ] || fail "the archive was not created (run the xcodebuild command above without the grep to see why)"

DEST=export; $UPLOAD && DEST=upload
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>$DEST</string>
</dict></plist>
PLIST
echo "== Exporting ($DEST)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" -allowProvisioningUpdates \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" 2>&1 | grep -E "error:|EXPORT|Upload" || true

if $UPLOAD; then
  echo "Uploaded. Finish the listing in App Store Connect (docs/APP_STORE.md) and press Submit for Review there."
else
  PKG=$(ls "$EXPORT_DIR"/*.pkg 2>/dev/null | head -1 || true)
  [ -n "$PKG" ] || fail "the export failed"
  cp "$PKG" "$OUT_DIR/FolderServe-$VERSION-appstore.pkg"
  echo "Exported: $OUT_DIR/FolderServe-$VERSION-appstore.pkg (open it with Transporter to upload)"
fi
