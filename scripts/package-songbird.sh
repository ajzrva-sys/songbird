#!/bin/zsh
# Package the native Songbird executable and resources.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX=0
BUNDLE_IDENTIFIER="com.songbird.player"
DISPLAY_NAME="Songbird"
UI_TEST_ROOT=""
UI_TEST_FIRST_RUN=0
APP=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --sandbox)
      SANDBOX=1
      shift
      ;;
    --bundle-identifier)
      [[ "$#" -ge 2 ]] || { echo "--bundle-identifier needs a value" >&2; exit 2; }
      BUNDLE_IDENTIFIER="$2"
      shift 2
      ;;
    --display-name)
      [[ "$#" -ge 2 ]] || { echo "--display-name needs a value" >&2; exit 2; }
      DISPLAY_NAME="$2"
      shift 2
      ;;
    --ui-test-root)
      [[ "$#" -ge 2 ]] || { echo "--ui-test-root needs a value" >&2; exit 2; }
      UI_TEST_ROOT="$2"
      shift 2
      ;;
    --ui-test-first-run)
      UI_TEST_FIRST_RUN=1
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--sandbox] [--bundle-identifier ID] [--display-name NAME] [--ui-test-root PATH] [--ui-test-first-run] [APP]"
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
    *)
      [[ -z "$APP" ]] || { echo "Only one app output path is allowed." >&2; exit 2; }
      APP="$1"
      shift
      ;;
  esac
done

APP="${APP:-$ROOT/Songbird.app}"
[[ -n "$BUNDLE_IDENTIFIER" ]] || { echo "Bundle identifier cannot be empty." >&2; exit 2; }
[[ "$BUNDLE_IDENTIFIER" != *[[:space:]/:]* ]] || { echo "Invalid bundle identifier: $BUNDLE_IDENTIFIER" >&2; exit 2; }
[[ -n "$DISPLAY_NAME" ]] || { echo "Display name cannot be empty." >&2; exit 2; }
if [[ -n "$UI_TEST_ROOT" ]]; then
  [[ "$UI_TEST_ROOT" == /* && "$UI_TEST_ROOT" != "/" ]] || {
    echo "--ui-test-root must be a safe absolute path, not $UI_TEST_ROOT" >&2
    exit 2
  }
  [[ "$BUNDLE_IDENTIFIER" != "com.songbird.player" ]] || {
    echo "--ui-test-root requires an alternate bundle identifier." >&2
    exit 2
  }
fi
if [[ "$UI_TEST_FIRST_RUN" -eq 1 && -z "$UI_TEST_ROOT" ]]; then
  echo "--ui-test-first-run requires --ui-test-root." >&2
  exit 2
fi
BIN="$ROOT/.build/arm64-apple-macosx/release/Songbird"
PLUGIN_BIN="$ROOT/.build/arm64-apple-macosx/release/libSongbirdDockTilePlugin.dylib"

if [[ ! -x "$BIN" ]]; then
  BIN="$ROOT/.build/release/Songbird"
fi
if [[ ! -f "$PLUGIN_BIN" ]]; then
  PLUGIN_BIN="$ROOT/.build/release/libSongbirdDockTilePlugin.dylib"
fi

if [[ ! -x "$BIN" || ! -f "$PLUGIN_BIN" ]]; then
  echo "Building release…"
  (cd "$ROOT" && swift build -c release)
  BIN="$ROOT/.build/arm64-apple-macosx/release/Songbird"
  [[ -x "$BIN" ]] || BIN="$ROOT/.build/release/Songbird"
  PLUGIN_BIN="$ROOT/.build/arm64-apple-macosx/release/libSongbirdDockTilePlugin.dylib"
  [[ -f "$PLUGIN_BIN" ]] || PLUGIN_BIN="$ROOT/.build/release/libSongbirdDockTilePlugin.dylib"
fi
[[ -x "$BIN" ]] || { echo "Missing release Songbird executable." >&2; exit 1; }
[[ -f "$PLUGIN_BIN" ]] || { echo "Missing release Dock tile plug-in library." >&2; exit 1; }

echo "Packaging into $APP"
rm -rf "$APP"
PLUGIN="$APP/Contents/PlugIns/SongbirdDockTilePlugin.docktileplugin"
mkdir -p \
  "$APP/Contents/MacOS" \
  "$APP/Contents/Frameworks" \
  "$APP/Contents/Resources" \
  "$PLUGIN/Contents/MacOS"

cp -f "$BIN" "$APP/Contents/MacOS/Songbird"
chmod +x "$APP/Contents/MacOS/Songbird"
cp -f "$ROOT/Vendor/FLAC/libFLAC.14.dylib" "$ROOT/Vendor/FLAC/libogg.0.dylib" \
  "$APP/Contents/Frameworks/"
cp -f "$ROOT/Vendor/FLAC/NOTICE.txt" "$APP/Contents/Resources/FLAC-NOTICE.txt"
cp -f "$ROOT/Vendor/aubio/libaubio.5.dylib" "$APP/Contents/Frameworks/"
cp -f "$ROOT/Vendor/aubio/NOTICE.txt" "$APP/Contents/Resources/aubio-NOTICE.txt"
cp -f "$PLUGIN_BIN" "$PLUGIN/Contents/MacOS/SongbirdDockTilePlugin"
chmod +x "$PLUGIN/Contents/MacOS/SongbirdDockTilePlugin"

# Development builds carry a local vendor rpath; packaged builds resolve only
# from their own Frameworks directory.
install_name_tool -delete_rpath "$ROOT/Vendor/FLAC" \
  "$APP/Contents/MacOS/Songbird" 2>/dev/null || true
install_name_tool -delete_rpath "$ROOT/Vendor/aubio" \
  "$APP/Contents/MacOS/Songbird" 2>/dev/null || true

ICON_SRC=""
for candidate in \
  "$ROOT/Sources/Resources/dock-icon.png" \
  "$ROOT/Sources/Resources/transparent.png" \
  "$ROOT/Sources/Resources/logo.png" \
  "$ROOT/Resources/Assets.xcassets/songbird-logo.imageset/songbird-logo.png"
do
  if [[ -f "$candidate" ]]; then
    ICON_SRC="$candidate"
    break
  fi
done

if [[ -n "$ICON_SRC" ]]; then
  cp -f "$ICON_SRC" "$APP/Contents/Resources/AppIcon.png"
fi

for app_resource in "$ROOT"/Sources/Resources/*; do
  if [[ -f "$app_resource" ]]; then
    cp -f "$app_resource" "$APP/Contents/Resources/"
  fi
done

python3 "$ROOT/scripts/legal_resources.py" stage \
  "$ROOT" "$APP/Contents/Resources/Legal"

for required_resource in songbird-logo.png missing-album-artwork.png; do
  [[ -f "$APP/Contents/Resources/$required_resource" ]] || {
    echo "Missing packaged resource: $required_resource" >&2
    exit 1
  }
done

cat > "$PLUGIN/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>SongbirdDockTilePlugin</string>
  <key>CFBundleIdentifier</key>
  <string>com.songbird.player.docktileplugin</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>SongbirdDockTilePlugin</string>
  <key>CFBundlePackageType</key>
  <string>BNDL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>NSPrincipalClass</key>
  <string>SongbirdDockTilePlugin</string>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Songbird</string>
  <key>CFBundleExecutable</key>
  <string>Songbird</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.songbird.player</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Songbird</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.music</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSDockTilePlugIn</key>
  <string>SongbirdDockTilePlugin.docktileplugin</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © Songbird</string>
  <key>SongbirdMetadataContactURL</key>
  <string>ajzrva@gmail.com</string>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeDescription</key>
      <string>Songbird Track IDs</string>
      <key>UTTypeIdentifier</key>
      <string>com.songbird.track-ids</string>
    </dict>
  </array>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Audio</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Default</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.mp3</string>
        <string>public.mpeg-4-audio</string>
        <string>public.aac-audio</string>
        <string>org.xiph.flac</string>
        <string>com.microsoft.waveform-audio</string>
        <string>public.aifc-audio</string>
        <string>public.aiff-audio</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

PLIST_PATH="$APP/Contents/Info.plist"
PLUGIN_PLIST_PATH="$PLUGIN/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER" "$PLIST_PATH"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$PLIST_PATH"
plutil -replace CFBundleIdentifier -string "$BUNDLE_IDENTIFIER.docktileplugin" "$PLUGIN_PLIST_PATH"
python3 "$ROOT/scripts/lastfm_build_config.py" "$PLIST_PATH"
if [[ -n "$UI_TEST_ROOT" ]]; then
  plutil -insert SongbirdUITesting -bool true "$PLIST_PATH"
  plutil -insert SongbirdUITestRoot -string "$UI_TEST_ROOT" "$PLIST_PATH"
  plutil -insert SongbirdImportSetupCompleted -bool \
    "$([[ "$UI_TEST_FIRST_RUN" -eq 1 ]] && echo false || echo true)" "$PLIST_PATH"
fi

echo "Signing (nested ad-hoc)…"
sign_item() {
  if [[ "$#" -eq 2 ]]; then
    codesign --force --sign - --timestamp=none --identifier "$2" "$1"
  else
    codesign --force --sign - --timestamp=none "$1"
  fi
}

for dylib in "$APP"/Contents/Frameworks/*.dylib; do
  [[ -f "$dylib" ]] && sign_item "$dylib"
done
sign_item \
  "$PLUGIN/Contents/MacOS/SongbirdDockTilePlugin" \
  "$BUNDLE_IDENTIFIER.docktileplugin"
sign_item "$PLUGIN" "$BUNDLE_IDENTIFIER.docktileplugin"

ENTITLEMENTS="$ROOT/config/Songbird.Direct.entitlements"
if [[ "$SANDBOX" -eq 1 ]]; then
  ENTITLEMENTS="$ROOT/config/Songbird.AppStore.entitlements"
fi
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier "$BUNDLE_IDENTIFIER" \
  --entitlements "$ENTITLEMENTS" \
  "$APP/Contents/MacOS/Songbird"
codesign \
  --force \
  --sign - \
  --timestamp=none \
  --identifier "$BUNDLE_IDENTIFIER" \
  --entitlements "$ENTITLEMENTS" \
  "$APP"

echo "Verifying…"
codesign --verify --deep --strict "$APP"
echo "codesign OK"

echo "Done. Launch with: open \"$APP\""
