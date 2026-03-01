#!/bin/bash
# Build script for RAML to ISA macOS app
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== RAML to ISA -- Build Script ==="
echo ""

# Check for xcodegen
if ! command -v xcodegen &> /dev/null; then
    echo "XcodeGen not found. Installing via Homebrew..."
    brew install xcodegen
fi

# Ensure signing config exists
if [ ! -f signing.xcconfig ]; then
    echo "No signing.xcconfig found -- creating from example (ad-hoc signing)."
    cp signing.xcconfig.example signing.xcconfig
fi

# Generate Xcode project
echo "[1/3] Generating Xcode project..."
xcodegen generate --spec project.yml
echo "  -> RAMLtoISA.xcodeproj created"

# Resolve SPM packages
echo "[2/3] Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies -project RAMLtoISA.xcodeproj -scheme RAMLtoISA 2>&1 | tail -5

# Build the app
echo "[3/3] Building app..."
xcodebuild -project RAMLtoISA.xcodeproj \
           -scheme RAMLtoISA \
           -configuration Release \
           -derivedDataPath build \
           CODE_SIGN_IDENTITY="-" \
           2>&1 | tail -20

# Find the built app
APP_PATH=$(find build -name "RAMLtoISA.app" -type d | head -1)

if [ -n "$APP_PATH" ]; then
    echo ""
    echo "=== Build successful ==="
    echo "App: $APP_PATH"
    echo ""
    echo "To run:  open \"$APP_PATH\""
    echo "To install: cp -R \"$APP_PATH\" /Applications/"
else
    echo ""
    echo "Build may have failed. Check output above."
    exit 1
fi
