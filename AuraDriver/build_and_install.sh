#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "Building Audio Server Plug-In Driver (Release arm64)..."
xcodebuild -project "$DIR/BGMDriver.xcodeproj" \
    -scheme "Background Music Device" \
    -configuration Release \
    build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    ARCHS="arm64" \
    ONLY_ACTIVE_ARCH=YES \
    RUN_CLANG_STATIC_ANALYZER=NO \
    GCC_TREAT_WARNINGS_AS_ERRORS=NO

BUILD_DIR=$(xcodebuild -project "$DIR/BGMDriver.xcodeproj" -scheme "Background Music Device" -configuration Release -showBuildSettings | grep " TARGET_BUILD_DIR =" | head -n 1 | awk '{print $3}')
DRIVER_SRC="${BUILD_DIR}/Background Music Device.driver"

if [ ! -d "$DRIVER_SRC" ]; then
    echo "Error: Driver bundle not found at $DRIVER_SRC"
    exit 1
fi

echo "Signing driver bundle..."
codesign -s - --force --deep "$DRIVER_SRC"

echo "Installing driver to /Library/Audio/Plug-Ins/HAL/..."
# Request root permission via osascript
osascript -e "do shell script \"mkdir -p '/Library/Audio/Plug-Ins/HAL' && rm -rf '/Library/Audio/Plug-Ins/HAL/Background Music Device.driver' && cp -R '$DRIVER_SRC' '/Library/Audio/Plug-Ins/HAL/' && chown -R root:wheel '/Library/Audio/Plug-Ins/HAL/Background Music Device.driver' && chmod -R 755 '/Library/Audio/Plug-Ins/HAL/Background Music Device.driver' && killall coreaudiod\" with administrator privileges"

echo "Driver installed successfully and coreaudiod restarted."
