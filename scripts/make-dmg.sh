#!/usr/bin/env bash
# Build a Release Tempo.app and wrap it in a drag-to-Applications DMG.
# The Finder window is laid out like a typical Mac installer: app on the left,
# Applications on the right. That layout is stored in .DS_Store on a writable
# intermediate image; a folder dump into UDZO cannot do it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

PROJECT="$ROOT/Tempo.xcodeproj"
SCHEME="Tempo"
CONFIGURATION="Release"
DERIVED="$ROOT/build/DerivedData"
STAGE="$ROOT/build/dmg/stage"
APP_NAME="Tempo.app"
VOLUME_NAME="Tempo"
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/make-dmg.sh [--skip-build]

  --skip-build   Reuse an existing Release Tempo.app under build/DerivedData
EOF
}

for arg in "$@"; do
  case "$arg" in
    --skip-build) SKIP_BUILD=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage; exit 1 ;;
  esac
done

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  # Icon Composer .icon JSON-only edits are often skipped by incremental actool.
  find "$ROOT/App/AppIcon.icon" -exec touch {} \; 2>/dev/null || true
  rm -f "$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME/Contents/Resources/AppIcon.icns"
  rm -f "$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME/Contents/Resources/Assets.car"

  # Ad-hoc sign only. Do not inject get-task-allow (a debug entitlement).
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    build
fi

APP="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME"
if [[ ! -d "$APP" ]]; then
  echo "missing $APP — build Release first" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$VERSION" ]]; then
  VERSION="$(awk -F'= |;' '/MARKETING_VERSION/{print $2; exit}' "$PROJECT/project.pbxproj" | tr -d ' ')"
fi
if [[ -z "$BUILD" ]]; then
  BUILD="0"
fi

OUT_DIR="$ROOT/build/dmg"
DMG="$OUT_DIR/Tempo-${VERSION}.dmg"
RW_DMG="$OUT_DIR/Tempo-rw.dmg"
BG_PNG="$OUT_DIR/dmg-background.png"

detach_volume() {
  if [[ -d "/Volumes/$VOLUME_NAME" ]]; then
    hdiutil detach "/Volumes/$VOLUME_NAME" -quiet || hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet || true
    sleep 1
  fi
}

rm -rf "$STAGE"
mkdir -p "$STAGE" "$OUT_DIR"
ditto --norsrc --noextattr --noacl "$APP" "$STAGE/$APP_NAME"
xattr -cr "$STAGE/$APP_NAME" 2>/dev/null || true
ln -s /Applications "$STAGE/Applications"

swift "$ROOT/scripts/make-dmg-background.swift" "$BG_PNG"

detach_volume
rm -f "$RW_DMG" "$DMG"

# Writable HFS+ image so Finder can store window bounds and icon positions.
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -fs HFS+ \
  -format UDRW \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen >/dev/null
MOUNT="/Volumes/$VOLUME_NAME"
for _ in $(seq 1 20); do
  [[ -d "$MOUNT" ]] && break
  sleep 0.25
done
if [[ ! -d "$MOUNT" ]]; then
  echo "failed to mount $RW_DMG" >&2
  exit 1
fi

mkdir -p "$MOUNT/.background"
cp "$BG_PNG" "$MOUNT/.background/background.png"
chflags hidden "$MOUNT/.background" || true

# Finder writes .DS_Store only while the volume is mounted read-write.
osascript <<EOF
tell application "Finder"
  tell disk "$VOLUME_NAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set sidebar width of container window to 0
    end try
    set the bounds of container window to {360, 180, 980, 580}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "$APP_NAME" of container window to {140, 190}
    set position of item "Applications" of container window to {460, 190}
    update without registering applications
    delay 1
    close
    open
    delay 1
    close
  end tell
end tell
EOF

sync
detach_volume

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW_DMG"
rm -f "$BG_PNG"

echo "Tempo $VERSION ($BUILD)"
echo "$DMG"
echo
echo "Ad-hoc signed: no Apple ID, Team ID, or developer name in the signature."
echo "Gatekeeper will show an unidentified-developer warning; right-click → Open."
