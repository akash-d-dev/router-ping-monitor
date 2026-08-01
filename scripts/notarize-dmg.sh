#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/release-config.sh"

DMG_PATH="$PROJECT_DIR/dist/$APP_NAME-$APP_VERSION.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application identity}"

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Missing $DMG_PATH. Build it with CODESIGN_IDENTITY set before notarizing."
    exit 1
fi

codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "$DMG_PATH"
