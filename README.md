# 待办 · AiTodo

一个遵循「艾森豪威尔四象限法则」的 macOS 原生待办应用。把事情放进四个格子：**立刻做 · 计划做 · 委托做 · 减少做**。

- 纯 SwiftUI 原生实现，零第三方依赖
- 深色主题、无边框窗口，按设计稿 1:1 还原
- 数据本地存储，离线可用

## 快速开始

```bash
# 编译并打包成 build/AiTodo.app（待办）
./scripts/build_app.sh

# 启动
open build/AiTodo.app
```

数据文件：`~/Library/Application Support/AiTodo/tasks.json`（删除该文件可重置，下次启动会重新生成示例数据）。

## 使用说明

| 操作 | 方式 |
| --- | --- |
| 记一件事 | 顶部输入框输入 → 选一个颜色（目标象限）→ 回车 |
| 快速带提醒时间 | 输入 `18:30 买菜` 或 `明天 9:00 周报`，时间自动识别 |
| 完成 / 取消完成 | 点击行首圆圈 |
| 编辑 | 双击任务文字，回车保存、Esc 取消 |
| 删除 | 悬停任务行，点行尾「×」；或右键 → 删除 |
| 移动象限 | 直接把任务行拖到另一张卡片（不会带动窗口；落点卡片描边高亮）；或右键 → 移动到 |
| 归档 | 悬停任务行点归档按钮（或右键 → 归档）；已完成任务默认在当天结束后自动归档（设置中可关） |
| 查看归档 | 右上角归档按钮进入归档页：按日期分组，可恢复到原象限、删除或清空 |
| 切换皮肤 | 右上角齿轮打开设置：经典深色 / 毛玻璃（实时模糊桌面） |
| 设置提醒 | 悬停任务行点时钟图标（或点时间胶囊），弹窗里选时间 |
| 切换宫格 / 列表 | 右上角胶囊开关，或 `⌘L` |
| 隐藏 / 退出 | 点窗口关闭（`⌘W`）只是隐藏窗口：应用驻留为悬浮球 + 菜单栏，点悬浮球底衬或 Dock 图标唤回；退出在悬浮球右键或菜单栏菜单选「退出待办」（或 `⌘Q`） |
| 快捷键 | `⌘1~4` 或 `↑/↓` 切换输入目标象限（文字颜色随之变化）；`Esc` 清空输入框 |
| 清空已完成 | 底部右下角 |

## 工程结构

```
ai_todo/
├── Sources/AiTodo/        # 全部 Swift 源码
│   ├── AiTodoApp.swift    # App 入口、菜单、通知回调、窗口自截图（调试）
│   ├── Models.swift       # 任务与四象限模型（含归档字段，向后兼容解码）
│   ├── TaskStore.swift    # 状态管理 + JSON 持久化 + 自动归档
│   ├── ReminderCenter.swift # UNUserNotificationCenter 提醒
│   ├── DueParser.swift    # “18:30 买菜” 快捷语法解析
│   ├── RootView.swift     # 主界面骨架、页面切换、头部控件、毛玻璃底衬
│   ├── InputBar.swift     # 顶部输入栏（颜色点 + 按钮）
│   ├── QuadrantViews.swift# 四象限卡片、宫格/列表布局、拖拽落点
│   ├── TaskRow.swift      # 任务行（勾选/编辑/提醒/归档/删除）
│   ├── ArchiveView.swift  # 归档页（按日分组、恢复/删除/清空）
│   ├── SettingsView.swift # 设置弹窗（皮肤、自动归档开关）
│   └── Theme.swift        # 色板、皮肤（经典深色/毛玻璃）
├── scripts/build_app.sh   # swiftc 编译 + .app 打包脚本
├── scripts/render_preview.sh # 离屏渲染界面 PNG（快速视觉检查）
├── scripts/make_icon.swift # 应用图标合成（裁白边 + macOS 圆角方形）
├── Resources/             # 图标源图与 AppIcon.icns
├── docs/产品计划表.md      # 里程碑与风险
├── docs/功能表.md          # 功能清单与快捷键
└── Package.swift          # SPM 清单（可选，见下）
```

## 技术要点

- **架构**：`TaskStore`（ObservableObject）单一数据源 + SwiftUI 声明式视图；任务模型含象限、完成态、提醒时间。
- **提醒**：`UNCalendarNotificationTrigger` 到点推送；完成/删除/清空会同步取消对应待发通知。
- **拖拽**：`onDrag` 携带任务 UUID（纯文本），象限卡片 `onDrop` 接收并迁移。
- **持久化**：`Codable` + 原子写入，任何变更即时保存。

## 本机构建说明（重要）

本机 CommandLineTools 安装已损坏（`usr/include/swift` 下新旧两份 modulemap 重复定义 `SwiftBridging`，且 SPM 的 ManifestAPI 缺少旧版符号），`swift build` 与直接 `swiftc` 均无法编译；另外系统 SDK 为 26.2，只能配对 Swift 6.2.x 编译器。`scripts/build_app.sh` 的处理方式：

1. 若存在 `build/toolchain/`（官方工具链解压目录），优先用它编译，并自动配对 `MacOSX15.4.sdk`（Swift 6.1.2 无法解析 26.x SDK 的 swiftinterface）；
2. 否则退回系统 `swiftc`（在 CLT 修复后可直接工作）。

重新获取工具链（已验证可行，全程无需 sudo）：

```bash
curl -L -o /tmp/swift.pkg https://download.swift.org/swift-6.1.2-release/xcode/swift-6.1.2-RELEASE/swift-6.1.2-RELEASE-osx.pkg
pkgutil --expand-full /tmp/swift.pkg /tmp/expanded
mv /tmp/expanded/swift-6.1.2-RELEASE-osx-package.pkg/Payload build/toolchain
rm -rf /tmp/expanded /tmp/swift.pkg
```

也可择机重装 CommandLineTools（`softwareupdate --install` 或官网 pkg），一劳永逸；修复后系统 `swiftc` 可直接构建，`build/toolchain` 可删。

## 路线图

见 [docs/产品计划表.md](docs/产品计划表.md) 与 [docs/功能表.md](docs/功能表.md)：v1.1 打磨提醒与效率细节，v1.2 统计/备份/菜单栏速记，v2.0 iCloud 同步与小组件。
