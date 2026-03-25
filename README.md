# PDF Shrinker

A simple macOS app to reduce PDF file sizes. Drop a PDF onto the window and get a compressed version.

Uses [Ghostscript](https://www.ghostscript.com/) under the hood, bundled inside the app so no dependencies are needed.

## Features

- Drag-and-drop or click to choose a PDF
- Four compression levels: Low (72 dpi), Medium (150 dpi), High (300 dpi), Maximum (300 dpi, color preserving)
- Shows original vs compressed size with percentage savings
- Output saved as `<original>-compressed.pdf` alongside the input file

## Requirements

- macOS 13.0+
- Apple Silicon (arm64)
- [Ghostscript](https://formulae.brew.sh/formula/ghostscript) installed via Homebrew (for building)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for building)

## Building

```bash
brew install ghostscript xcodegen
./build.sh
open "PDF Shrinker.app"
```

The build script will:
1. Generate the Xcode project via XcodeGen
2. Build the app
3. Bundle Ghostscript and all its dylib dependencies into the app
4. Rewrite dylib paths so the app is fully self-contained

## Distribution

To sign, notarize, and package for distribution:

```bash
# First, store notarization credentials (one-time setup):
xcrun notarytool store-credentials "notarytool" --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID

# Then build and distribute:
./build.sh
./distribute.sh
```

## License

MIT
