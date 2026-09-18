// 端到端拖拽验证：合成鼠标事件，把红卡第一行任务拖到绿卡
// 用法：build/drag_test（窗口坐标从 /tmp/aitodo_frame.txt 读取，需先带 AITODO_SNAPSHOT 启动应用）
import CoreGraphics
import Foundation

func windowBounds() -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)? {
    guard let text = try? String(contentsOfFile: "/tmp/aitodo_frame.txt", encoding: .utf8) else {
        return nil
    }
    let parts = text.split(separator: " ").compactMap { Double($0) }
    guard parts.count == 4 else { return nil }
    return (x: CGFloat(parts[0]), y: CGFloat(parts[1]), w: CGFloat(parts[2]), h: CGFloat(parts[3]))
}

func send(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: .left) else { return }
    event.post(tap: .cghidEventTap)
}

guard let win = windowBounds() else {
    print("未找到 AiTodo 窗口")
    exit(1)
}
print("窗口: \(win.x),\(win.y) \(win.w)x\(win.h)")

let source = CGPoint(x: win.x + win.w * 0.118, y: win.y + win.h * 0.332)  // 红卡第一行
let target = CGPoint(x: source.x, y: source.y + 87)                        // 同象限向下拖过一行

send(.mouseMoved, source)
usleep(200_000)
send(.leftMouseDown, source)
usleep(250_000)

let steps = 24
for step in 1...steps {
    let t = Double(step) / Double(steps)
    let point = CGPoint(x: source.x + (target.x - source.x) * t,
                        y: source.y + (target.y - source.y) * t)
    send(.leftMouseDragged, point)
    usleep(35_000)
}
usleep(350_000)
send(.leftMouseUp, target)
print("拖拽事件已发送: \(source) -> \(target)")
