#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/PDFShrinker"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="PDF Shrinker"
GS_BIN="$(which gs)"
GS_VERSION="$("$GS_BIN" --version)"
GS_SHARE="$(dirname "$(dirname "$GS_BIN")")/share/ghostscript/$GS_VERSION"

echo "==> Using Ghostscript $GS_VERSION at $GS_BIN"
if [ ! -d "$GS_SHARE" ]; then
    echo "ERROR: Ghostscript share directory not found at $GS_SHARE"
    exit 1
fi

echo "==> Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate

echo "==> Building app..."
xcodebuild -project PDFShrinker.xcodeproj \
    -scheme PDFShrinker \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/derived" \
    -quiet \
    ONLY_ACTIVE_ARCH=NO

APP_PATH="$BUILD_DIR/derived/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at $APP_PATH"
    exit 1
fi

echo "==> Bundling Ghostscript binary..."
HELPERS_DIR="$APP_PATH/Contents/Helpers"
FRAMEWORKS_DIR="$APP_PATH/Contents/Frameworks"
RESOURCES_DIR="$APP_PATH/Contents/Resources/ghostscript"

mkdir -p "$HELPERS_DIR" "$FRAMEWORKS_DIR" "$RESOURCES_DIR"

# Copy gs binary
cp "$GS_BIN" "$HELPERS_DIR/gs"
chmod +x "$HELPERS_DIR/gs"

# Copy ghostscript resources
cp -R "$GS_SHARE/lib" "$RESOURCES_DIR/"
cp -R "$GS_SHARE/Resource" "$RESOURCES_DIR/"
cp -R "$GS_SHARE/iccprofiles" "$RESOURCES_DIR/"
# Fonts are optional but nice to have
if [ -d "$GS_SHARE/fonts" ]; then
    cp -R "$GS_SHARE/fonts" "$RESOURCES_DIR/"
fi

echo "==> Bundling dylibs..."

# Find all dylib dependencies recursively (homebrew absolute paths + @rpath)
get_all_deps() {
    python3 -c "
import subprocess, re, os

def resolve_rpath_lib(libname):
    \"\"\"Try to find an @rpath library in homebrew\"\"\"
    # Search common homebrew lib locations
    for path in ['/opt/homebrew/lib', '/opt/homebrew/opt']:
        for root, dirs, files in os.walk(path):
            if libname in files:
                full = os.path.join(root, libname)
                if not full.endswith('.a'):
                    return full
    return None

def get_deps(binary):
    result = subprocess.run(['otool', '-L', binary], capture_output=True, text=True)
    libs = []
    for line in result.stdout.strip().split('\n')[1:]:
        line = line.strip()
        path = line.split(' (')[0].strip()
        if path.startswith('/opt/homebrew/'):
            libs.append(path)
        elif path.startswith('@rpath/'):
            libname = os.path.basename(path)
            resolved = resolve_rpath_lib(libname)
            if resolved:
                libs.append(resolved)
    return libs

seen = set()
queue = ['$GS_BIN']

while queue:
    current = queue.pop(0)
    for lib in get_deps(current):
        if lib not in seen:
            seen.add(lib)
            print(lib)
            queue.append(lib)
"
}

# Copy all dylibs (use install to set writable permissions)
while IFS= read -r lib; do
    libname=$(basename "$lib")
    # Skip if already copied (can happen with symlink/path variations)
    if [ ! -f "$FRAMEWORKS_DIR/$libname" ]; then
        install -m 755 "$lib" "$FRAMEWORKS_DIR/$libname"
        echo "  Copied $libname"
    fi
done < <(get_all_deps)

# Fix up dylib paths in the gs binary
echo "==> Fixing dylib paths..."

fix_dylib_refs() {
    local binary="$1"
    # Fix homebrew absolute paths
    for ref in $(otool -L "$binary" | awk 'NR>1{print $1}' | grep '/opt/homebrew/'); do
        libname=$(basename "$ref")
        install_name_tool -change "$ref" "@executable_path/../Frameworks/$libname" "$binary" 2>/dev/null || true
    done
    # Fix @rpath references
    for ref in $(otool -L "$binary" | awk 'NR>1{print $1}' | grep '@rpath/'); do
        libname=$(basename "$ref")
        install_name_tool -change "$ref" "@executable_path/../Frameworks/$libname" "$binary" 2>/dev/null || true
    done
}

# Fix gs binary
fix_dylib_refs "$HELPERS_DIR/gs"

# Fix each dylib's references to other dylibs, and set its own id
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    libname=$(basename "$dylib")
    install_name_tool -id "@executable_path/../Frameworks/$libname" "$dylib" 2>/dev/null || true
    fix_dylib_refs "$dylib"
done

# Ad-hoc sign everything
echo "==> Code signing..."
codesign --force --sign - "$HELPERS_DIR/gs"
for dylib in "$FRAMEWORKS_DIR"/*.dylib; do
    codesign --force --sign - "$dylib"
done
codesign --force --sign - "$APP_PATH"

# Copy to output
OUTPUT="$SCRIPT_DIR/${APP_NAME}.app"
rm -rf "$OUTPUT"
cp -R "$APP_PATH" "$OUTPUT"

echo ""
echo "==> Build complete!"
echo "    App: $OUTPUT"
du -sh "$OUTPUT"
echo ""
echo "    To run: open \"$OUTPUT\""
