#!/bin/bash
# 编译 AiTodo 并打包成 build/AiTodo.app（显示名：待办）
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="$(xcrun --show-sdk-path 2>/dev/null || echo "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk")"

# 架构：ARCH=arm64（默认，Apple Silicon）| ARCH=intel（x86_64 交叉编译，Intel 芯片）
ARCH="${ARCH:-arm64}"
TARGET_ARGS=()
if [ "$ARCH" = "intel" ]; then
    TARGET_ARGS=(-target x86_64-apple-macos13.0)
    echo ">> 目标架构：Intel (x86_64)"
fi

# 优先使用随项目解压的官方工具链（规避本机 CLT modulemap 损坏问题）
SWIFTC=(swiftc)
if [ -x "build/toolchain/usr/bin/swiftc" ]; then
    SWIFTC=("$PWD/build/toolchain/usr/bin/swiftc")
    # Swift 6.1.2 工具链无法解析 26.x SDK 的 swiftinterface，配对使用 15.4 SDK
    if [ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]; then
        SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
    fi
fi

echo ">> 编译：${SWIFTC[*]}"
"${SWIFTC[@]}" -O -parse-as-library \
    "${TARGET_ARGS[@]}" \
    -sdk "$SDK" \
    -o build/AiTodo \
    Sources/AiTodo/*.swift

APP="build/AiTodo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/AiTodo "$APP/Contents/MacOS/AiTodo"
if [ -f "Resources/AppIcon.icns" ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>AiTodo</string>
    <key>CFBundleIdentifier</key><string>com.aitodo.app</string>
    <key>CFBundleName</key><string>待办</string>
    <key>CFBundleDisplayName</key><string>待办</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.4.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 AiTodo</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo ">> 完成：$APP （open $APP 启动）"
