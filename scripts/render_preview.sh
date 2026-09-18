#!/bin/bash
# 离屏渲染主界面 PNG（无需屏幕录制权限），用于快速视觉检查
# 用法：./scripts/render_preview.sh [输出路径]
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
SWIFTC=(swiftc)
if [ -x "build/toolchain/usr/bin/swiftc" ]; then
    SWIFTC=("$PWD/build/toolchain/usr/bin/swiftc")
fi

mkdir -p build
"${SWIFTC[@]}" -O -parse-as-library -sdk "$SDK" -o build/preview \
    scripts/preview/PreviewMain.swift \
    Sources/AiTodo/Models.swift \
    Sources/AiTodo/Theme.swift \
    Sources/AiTodo/TaskStore.swift \
    Sources/AiTodo/ReminderCenter.swift \
    Sources/AiTodo/DueParser.swift \
    Sources/AiTodo/RootView.swift \
    Sources/AiTodo/InputBar.swift \
    Sources/AiTodo/QuadrantViews.swift \
    Sources/AiTodo/TaskRow.swift \
    Sources/AiTodo/ArchiveView.swift \
    Sources/AiTodo/AIProvider.swift \
    Sources/AiTodo/InkEffects.swift \
    Sources/AiTodo/SettingsView.swift

OUT="${1:-/tmp/aitodo_render.png}"
./build/preview "$OUT"
echo "提示：ImageRenderer 对 TextField/拖拽行有渲染缺陷，仅看布局；精确验证请用 AITODO_SNAPSHOT 环境变量让 App 自截图。"
