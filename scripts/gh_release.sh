#!/bin/bash
# 创建 GitHub Release 并上传应用包
# 前置：gh auth login -h github.com   （登录一次 GitHub CLI）
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:-v1.0.0}"
ZIP="build/AiTodo-${TAG}-macOS-AppleSilicon.zip"

if [ ! -f "$ZIP" ]; then
    echo ">> 未找到 $ZIP，请先运行 scripts/build_app.sh 并压缩"
    exit 1
fi

gh release create "$TAG" "$ZIP" \
    --title "待办 AiTodo ${TAG}" \
    --notes "macOS 四象限待办应用（SwiftUI 原生，Apple Silicon）

**功能**
- 艾森豪威尔四象限：重要·紧急 / 重要·不紧急 / 紧急·不重要 / 不重要·不紧急
- 拖拽排序与跨象限移动（实时腾位 + 墨滴迸溅动效）
- 三套皮肤：经典深色 / 纯白 / 毛玻璃
- 任务提醒（系统通知）、归档、纯本地 JSON 存储

**安装**
1. 下载 zip 并解压
2. 将「待办」拖入「应用程序」文件夹（或直接双击运行）
3. 首次启动若被 Gatekeeper 拦截：右键点击应用 → 选「打开」

**要求**：macOS 13+，Apple Silicon（M 系列）
**说明**：应用为 ad-hoc 签名（未公证），首次打开需右键→打开；数据保存在本机 ~/Library/Application Support/AiTodo/"

echo ">> Release 已发布: https://github.com/chengmenlixue/aitodo/releases/tag/${TAG}"
