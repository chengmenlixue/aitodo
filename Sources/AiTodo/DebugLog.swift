import Foundation

/// 调试日志：仅在启动环境含 AITODO_DEBUG=1 时写入 /tmp/aitodo_debug.log
/// 默认关闭——避免拖拽热路径上的主线程文件 I/O
enum DebugLog {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["AITODO_DEBUG"] == "1"
    }

    private static let fileURL = URL(fileURLWithPath: "/tmp/aitodo_debug.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        guard enabled else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
