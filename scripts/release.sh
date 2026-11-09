#!/bin/bash
# Builds, signs, notarizes and zips FolderServe for distribution outside the Mac App Store.
#
#   scripts/release.sh             build, sign, notarize, staple and zip into build/release/
#   scripts/release.sh --publish   the same, then create a GitHub release with the zip (public!)
#   NOTARIZE=0 scripts/release.sh  build and sign only (to test the signing half); never publishes
#
# One-time setup (see README "Releasing"): a "Developer ID Application" certificate for the team below in your login
# keychain, and a notarytool profile created with `xcrun notarytool store-credentials`.
set -euo pipefail

TEAM_ID="${TEAM_ID:-XC7ZHWDHCA}"
NOTARY_PROFILE="${NOTARY_PROFILE:-folderserve-notary}"
PUBLISH=false
NOTARIZE="${NOTARIZE:-1}"
[ "${1:-}" = "--publish" ] && PUBLISH=true
[ "$NOTARIZE" = "0" ] && PUBLISH=false

cd "$(dirname "$0")/.."
VERSION=$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
# Build outside the repo: folders synced by iCloud (Desktop, Documents) get Finder metadata (com.apple.FinderInfo) on
# their files, and codesign refuses an app that carries it. Only the finished zip is copied into the repo.
BUILD_DIR="${RELEASE_WORK_DIR:-${TMPDIR:-/tmp}/folderserve-release}"
OUT_DIR="build/release"
ARCHIVE="$BUILD_DIR/FolderServe.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/FolderServe.app"
ZIP="$OUT_DIR/FolderServe-$VERSION.zip"

fail() { echo "error: $*" >&2; exit 1; }

echo "== Checking prerequisites"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)
[ -n "$IDENTITY" ] || fail "no 'Developer ID Application' certificate for team $TEAM_ID in your keychain.
  Create it as the Account Holder (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application)."
[ "$NOTARIZE" = "0" ] || xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "notarytool profile '$NOTARY_PROFILE' not found or not working. Create it with:
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <your Apple ID> --team-id $TEAM_ID"
command -v xcodegen >/dev/null || fail "xcodegen is not installed (brew install xcodegen)"
if $PUBLISH; then
  command -v gh >/dev/null || fail "gh is not installed (brew install gh)"
  gh auth status >/dev/null 2>&1 || fail "gh is not signed in (gh auth login)"
fi
echo "   identity: $IDENTITY"
echo "   version:  $VERSION"

echo "== Generating the project"
xcodegen generate >/dev/null

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR" "$OUT_DIR"

echo "== Archiving (Release)"
# The project is named so a stray duplicate (iCloud leaves "FolderServe 2.xcodeproj" now and then) cannot stop the build.
xcodebuild archive -project FolderServe.xcodeproj -scheme FolderServe -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" ENABLE_HARDENED_RUNTIME=YES \
  2>&1 | grep -E "error:|warning: .*sign|ARCHIVE" || true
[ -d "$ARCHIVE" ] || fail "the archive was not created (run the xcodebuild command above without the grep to see why)"

echo "== Exporting a Developer ID build"
cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" 2>&1 | grep -E "error:|EXPORT" || true
[ -d "$APP" ] || fail "the export failed"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID Application|TeamIdentifier|flags=.*runtime" || true

if [ "$NOTARIZE" = "0" ]; then
  echo "== Skipping notarization (NOTARIZE=0): the app is signed but not notarized, so do not distribute it"
  echo "Signed app: $APP"
  codesign --verify --deep --strict "$APP" && echo "   signature verifies"
  exit 0
fi

echo "== Notarizing (this can take a few minutes)"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$BUILD_DIR/notarize.zip"
xcrun notarytool submit "$BUILD_DIR/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

echo "== Packaging"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "$SHA  $(basename "$ZIP")" > "$ZIP.sha256"
echo "   $ZIP"
echo "   sha256 $SHA"

if $PUBLISH; then
  echo "== Publishing GitHub release v$VERSION"
  gh release create "v$VERSION" "$ZIP" "$ZIP.sha256" --title "FolderServe $VERSION" \
    --notes "Signed and notarized build. Unzip and drag FolderServe.app to Applications.

SHA-256: \`$SHA\`"
else
  echo "Done. Add --publish to create the GitHub release."
fi
