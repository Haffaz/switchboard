#!/usr/bin/env bash
# Make a signed, notarized, stapled Switchboard-<version>.dmg ready to share.
# One-time setup: copy release.local.env.example to release.local.env, then
# store your app-specific password in Keychain:
#   xcrun notarytool store-credentials switchboard-notary \
#     --apple-id you@example.com --team-id YOURTEAMID
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release.env
source "$ROOT/release.env"
[[ -f "$ROOT/release.local.env" ]] ||
  { echo "release: copy release.local.env.example to release.local.env first" >&2; exit 1; }
# shellcheck source=release.local.env.example
source "$ROOT/release.local.env"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }
die()  { printf 'release: %s\n' "$*" >&2; exit 1; }

preflight() {
  security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY" ||
    die "signing certificate not found in Keychain: $SIGN_IDENTITY"
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 ||
    die "notary profile '$NOTARY_PROFILE' missing. Run the store-credentials command at the top of this file."
  swift test --package-path "$ROOT" >/dev/null 2>&1 || die "tests failed"
}

notarize() { # notarize <file>
  step "Notarizing $(basename "$1") (usually 1-5 minutes)"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist \
    > "$BUILD/notary.plist" || true
  local status; status="$(plutil -extract status raw -o - "$BUILD/notary.plist" 2>/dev/null || echo unknown)"
  if [[ "$status" != "Accepted" ]]; then
    local id; id="$(plutil -extract id raw -o - "$BUILD/notary.plist" 2>/dev/null || true)"
    [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
    die "notarization status: $status"
  fi
}

make_dmg() {
  step "Making $(basename "$DMG")"
  local stage="$BUILD/dmg-stage"
  rm -rf "$stage" "$DMG"; mkdir -p "$stage"
  ditto "$APP" "$stage/$APP_NAME.app"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$stage" -ov -format UDZO "$DMG" >/dev/null
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
}

preflight
"$ROOT/build.sh" --sign

# Notarize and staple the app itself, so it also opens offline once copied out.
ditto -c -k --keepParent "$APP" "$BUILD/$APP_NAME.zip"
notarize "$BUILD/$APP_NAME.zip"
xcrun stapler staple "$APP"

make_dmg
notarize "$DMG"
xcrun stapler staple "$DMG"

step "Checking with Gatekeeper"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "Ready to share: $DMG"
