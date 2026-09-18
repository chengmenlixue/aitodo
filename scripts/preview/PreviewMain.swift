// 离屏渲染主界面为 PNG，用于无屏幕权限时的视觉验证。
// 用法：./build/preview [输出路径]
import AppKit
import SwiftUI

@main
struct PreviewBoot {
    static func main() {
        if ProcessInfo.processInfo.environment["AITODO_TEST_MOVE"] != nil {
            testMove()
            return
        }
        if ProcessInfo.processInfo.environment["AITODO_TEST_PARSE"] == "1" {
            testParse()
            return
        }
        MainActor.assumeIsolated { run() }
    }

    /// AI 解析：JSON 容错 + 象限映射 + 默认第四象限
    static func testParse() {
        let cases = AITaskParser.parseContent(#"{"tasks":[{"title":"A","important":true,"urgent":true},{"title":"B"},{"title":"C","important":false,"urgent":true}]}"#)
        let q = cases.map(\.quadrant.rawValue)
        print(q == [0, 3, 2] ? "PASS parse 象限映射与默认第四象限" : "FAIL parse \(q)")

        let invalid = AITaskParser.parseContent("抱歉，我无法解析这张截图")
        print(invalid.isEmpty ? "PASS parse 非JSON输出兜底" : "FAIL parse 非JSON输出")

        let empty = AITaskParser.parseContent("{\"tasks\":[]}")
        print(empty.isEmpty ? "PASS parse 空任务列表" : "FAIL parse 空任务列表")

        let fenced = AITaskParser.parseContent("结果如下：\n```json\n{\"tasks\":[{\"title\":\"带代码围栏的任务\",\"important\":true,\"urgent\":false}]}\n```")
        print(fenced.count == 1 && fenced[0].quadrant == .importantNotUrgent ? "PASS parse markdown围栏剥离" : "FAIL parse markdown围栏")
    }

    /// 拖拽排序/跨象限移动逻辑的确定性测试
    static func testMove() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aitodo-test-\(UUID().uuidString)", isDirectory: true)
        let store = TaskStore(directory: dir, seedOnEmpty: false)
        let a = store.add(title: "A", quadrant: .urgentImportant)!
        let b = store.add(title: "B", quadrant: .urgentImportant)!
        let c = store.add(title: "C", quadrant: .urgentImportant)!
        let d = store.add(title: "D", quadrant: .urgentNotImportant)!

        func order(_ q: Quadrant) -> [String] {
            store.tasks(in: q).map(\.title)
        }

        // 象限内排序：把 A 拖到插入位 1（B 之后）
        store.move(id: a.id, to: .urgentImportant, insertionIndex: 1)
        print(order(.urgentImportant) == ["B", "A", "C"] ? "PASS 1.1 同象限中间插入" : "FAIL 1.1 \(order(.urgentImportant))")

        // 象限内排序：把 A 拖到末尾
        store.move(id: a.id, to: .urgentImportant, insertionIndex: 3)
        print(order(.urgentImportant) == ["B", "C", "A"] ? "PASS 1.2 移到末尾" : "FAIL 1.2 \(order(.urgentImportant))")

        // 象限内排序：拖回原位，顺序稳定
        store.move(id: a.id, to: .urgentImportant, insertionIndex: 2)
        print(order(.urgentImportant) == ["B", "C", "A"] ? "PASS 1.3 拖回原位顺序稳定" : "FAIL 1.3 \(order(.urgentImportant))")

        // 跨象限：把 C 插到黄象限最前
        store.move(id: c.id, to: .urgentNotImportant, insertionIndex: 0)
        print(order(.urgentNotImportant) == ["C", "D"] ? "PASS 2.1 跨象限插到最前" : "FAIL 2.1 \(order(.urgentNotImportant))")

        // 跨象限：nil = 追加末尾
        store.move(id: a.id, to: .urgentNotImportant, insertionIndex: nil)
        print(order(.urgentNotImportant) == ["C", "D", "A"] ? "PASS 2.2 跨象限追加末尾" : "FAIL 2.2 \(order(.urgentNotImportant))")

        // 越界下标收敛
        store.move(id: b.id, to: .urgentNotImportant, insertionIndex: 99)
        print(order(.urgentNotImportant) == ["C", "D", "A", "B"] ? "PASS 3.1 越界下标收敛为追加" : "FAIL 3.1 \(order(.urgentNotImportant))")

        // 自身拖到自己所处缝隙：顺序不变
        store.move(id: b.id, to: .urgentNotImportant, insertionIndex: 3)
        print(order(.urgentNotImportant) == ["C", "D", "A", "B"] ? "PASS 3.2 拖回原位顺序稳定" : "FAIL 3.2 \(order(.urgentNotImportant))")

        try? FileManager.default.removeItem(at: dir)
    }

    @MainActor
    static func run() {
        _ = NSApplication.shared  // 初始化 AppKit 上下文

        // AITODO_SKIN=glass 可在无 App bundle 的渲染器中预览毛玻璃皮肤
        if let skinEnv = ProcessInfo.processInfo.environment["AITODO_SKIN"] {
            UserDefaults.standard.set(skinEnv, forKey: "skin")
        }

        let output = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "/tmp/aitodo_render.png"

        let store = TaskStore()

        let view = RootView()
            .environmentObject(store)
            .frame(width: 1240, height: 820)
            .background(Theme.appBackground)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            fputs("渲染失败\n", stderr)
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            fputs("PNG 编码失败\n", stderr)
            exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: output))
        print("已渲染：\(output)")
    }
}
