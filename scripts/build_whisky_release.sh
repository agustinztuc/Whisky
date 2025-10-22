#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA/Build/Products/Release"
APP_NAME="Whisky"
APP_BUNDLE="$PRODUCTS_DIR/${APP_NAME}.app"
DIST_DIR="$ROOT_DIR/dist"
ARCHIVE_NAME="${APP_NAME}.app.zip"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodebuild \
  -project "$ROOT_DIR/Whisky.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: expected app bundle at $APP_BUNDLE" >&2
  exit 1
fi

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$DIST_DIR/$ARCHIVE_NAME"

cat <<INFO > "$DIST_DIR/BUILD_INFO.txt"
Bundle: ${APP_NAME}
Configuration: Release
Toolkit Version: $(/usr/libexec/PlistBuddy -c 'Print :toolkit' "$ROOT_DIR/Libraries/WhiskyWineVersion.plist")
Toolkit Release Date: $(/usr/libexec/PlistBuddy -c 'Print :toolkitReleaseDate' "$ROOT_DIR/Libraries/WhiskyWineVersion.plist")
Runtime Version: $(/usr/libexec/PlistBuddy -c 'Print :version' "$ROOT_DIR/Libraries/WhiskyWineVersion.plist")
Built At: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
INFO

echo "Created artifact at $DIST_DIR/$ARCHIVE_NAME"
