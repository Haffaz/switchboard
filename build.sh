#!/usr/bin/env bash
# Build Switchboard.app (menu bar app with the cprof CLI inside).
#   ./build.sh             dev build, ad-hoc signed       -> build/Switchboard.app
#   ./build.sh --sign      signed with your Developer ID (needs release.local.env)
#   ./build.sh --install   also copy to /Applications and open it (combine with --sign)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=release.env
source "$ROOT/release.env"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
ENTITLEMENTS="$ROOT/packaging/Switchboard.entitlements"
SIGNED=false; INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --sign) SIGNED=true ;;
    --install) INSTALL=true ;;
    *) echo "unknown option: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\033[1m==> %s\033[0m\n' "$*"; }

if $SIGNED; then
  [[ -f "$ROOT/release.local.env" ]] ||
    { echo "build: --sign needs release.local.env (copy release.local.env.example)" >&2; exit 1; }
  # shellcheck source=release.local.env.example
  source "$ROOT/release.local.env"
fi

make_icon() {
  local icns="$BUILD/AppIcon.icns"
  [[ -f "$icns" && "$icns" -nt "$ROOT/tools/make-icon.swift" ]] && return
  step "Drawing icon"
  swiftc -o "$BUILD/make-icon" "$ROOT/tools/make-icon.swift"
  rm -rf "$BUILD/AppIcon.iconset"
  "$BUILD/make-icon" "$BUILD/AppIcon.iconset"
  iconutil -c icns -o "$icns" "$BUILD/AppIcon.iconset"
}

write_plist() {
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Not affiliated with Anthropic.</string>
  <key>NSAppleEventsUsageDescription</key><string>Switchboard passes sign-in links to the Claude window that is signing in.</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Claude sign-in relay</string>
    <key>CFBundleURLSchemes</key><array><string>claude</string></array>
    <key>LSHandlerRank</key><string>None</string>
  </dict></array>
</dict></plist>
PLIST
}

sign() {
  if $SIGNED; then
    step "Signing with $SIGN_IDENTITY"
    codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
  else
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP" >/dev/null
  fi
}

mkdir -p "$BUILD"
make_icon

step "Compiling $APP_NAME $VERSION (Apple silicon + Intel)"
swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64
BIN="$(swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/cprof"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp -R "$ROOT/bin" "$ROOT/lib" "$APP/Contents/Resources/cprof/"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
write_plist
sign
echo "Built $APP"

if $INSTALL; then
  osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$APP_NAME.app"
  echo "Installed. Look for the icon in your menu bar."
fi
