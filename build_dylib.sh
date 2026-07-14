#!/bin/bash
# Build script for LicenseManager dylib (iOS)
# Run this on macOS with Xcode installed

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
LIBRARY_NAME="libLicenseManager"

# iOS device (arm64)
xcodebuild -create-xcframework \
  -library "$BUILD_DIR/Release-iphoneos/$LIBRARY_NAME.a" \
  -library "$BUILD_DIR/Release-iphonesimulator/$LIBRARY_NAME.a" \
  -output "$BUILD_DIR/$LIBRARY_NAME.xcframework"

echo "Build complete. Find the library at: $BUILD_DIR/$LIBRARY_NAME.xcframework"
