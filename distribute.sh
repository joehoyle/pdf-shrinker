#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="PDF Shrinker"
APP_PATH="$SCRIPT_DIR/${APP_NAME}.app"
SIGN_IDENTITY="Developer ID Application: Human Made Limited (ZLF8FFAD7U)"
NOTARY_PROFILE="notarytool"

if [ ! -d "$APP_PATH" ]; then
    echo "App not found. Running build first..."
    "$SCRIPT_DIR/build.sh"
fi

echo "==> Signing with Developer ID..."

# Sign dylibs first (inside out)
for dylib in "$APP_PATH/Contents/Frameworks/"*.dylib; do
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$dylib"
done

# Sign the gs helper binary
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH/Contents/Helpers/gs"

# Sign the app bundle
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"

echo "==> Verifying signature..."
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true

echo "==> Creating zip for notarization..."
ZIP_PATH="$SCRIPT_DIR/${APP_NAME}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo "==> Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling ticket..."
xcrun stapler staple "$APP_PATH"

echo "==> Re-creating final zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "==> Done! Ready to distribute:"
echo "    $ZIP_PATH"
ls -lh "$ZIP_PATH"
