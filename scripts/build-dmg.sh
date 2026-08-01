#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/release-config.sh"

APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
DMG_PATH="$PROJECT_DIR/dist/$APP_NAME-$APP_VERSION.dmg"
WORK_DIR="$(mktemp -d "$PROJECT_DIR/.build/dmg.XXXXXX")"
STAGING_DIR="$WORK_DIR/staging"
TEMP_DMG_PATH="$WORK_DIR/$APP_NAME-$APP_VERSION.dmg"

trap 'rm -rf "$WORK_DIR"' EXIT

"$PROJECT_DIR/scripts/build-app.sh"

mkdir -p "$STAGING_DIR"
ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    "$TEMP_DMG_PATH"
hdiutil verify "$TEMP_DMG_PATH"
mv -f "$TEMP_DMG_PATH" "$DMG_PATH"

echo "$DMG_PATH"
