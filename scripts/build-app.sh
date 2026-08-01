#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/release-config.sh"

BUILD_ROOT="$PROJECT_DIR/.build/universal"
UNIVERSAL_BINARY="$BUILD_ROOT/$EXECUTABLE_NAME"
ARM64_SCRATCH="$BUILD_ROOT/arm64"
X86_64_SCRATCH="$BUILD_ROOT/x86_64"
ARM64_BINARY="$ARM64_SCRATCH/arm64-apple-macosx/release/$EXECUTABLE_NAME"
X86_64_BINARY="$X86_64_SCRATCH/x86_64-apple-macosx/release/$EXECUTABLE_NAME"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cd "$PROJECT_DIR"
swift build \
    -c release \
    --triple arm64-apple-macosx14.0 \
    --scratch-path "$ARM64_SCRATCH"
swift build \
    -c release \
    --triple x86_64-apple-macosx14.0 \
    --scratch-path "$X86_64_SCRATCH"

mkdir -p "$BUILD_ROOT"
lipo -create \
    "$ARM64_BINARY" \
    "$X86_64_BINARY" \
    -output "$UNIVERSAL_BINARY"

"$PROJECT_DIR/scripts/build-icon.sh"

rm -rf "$APP_DIR"
mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
cp "$UNIVERSAL_BINARY" "$CONTENTS_DIR/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" \
    -c "Add :CFBundleDisplayName string '$APP_NAME'" \
    -c "Add :CFBundleExecutable string '$EXECUTABLE_NAME'" \
    -c "Add :CFBundleIdentifier string '$BUNDLE_ID'" \
    -c "Add :CFBundleIconFile string AppIcon" \
    -c "Add :CFBundleInfoDictionaryVersion string 6.0" \
    -c "Add :CFBundleName string '$APP_NAME'" \
    -c "Add :CFBundlePackageType string APPL" \
    -c "Add :CFBundleShortVersionString string '$APP_VERSION'" \
    -c "Add :CFBundleVersion string '$BUILD_NUMBER'" \
    -c "Add :LSApplicationCategoryType string public.app-category.utilities" \
    -c "Add :LSMinimumSystemVersion string 14.0" \
    -c "Add :NSHighResolutionCapable bool true" \
    -c "Add :NSSupportsAutomaticGraphicsSwitching bool true" \
    "$CONTENTS_DIR/Info.plist"

if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign - "$APP_DIR"
else
    codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

echo "$APP_DIR"
