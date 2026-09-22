import Foundation

/// 调试日志：仅在启动环境含 AITODO_DEBUG=1 时写入 /tmp/aitodo_debug.log
/// 默认关闭——避免拖拽热路径上的主线程文件 I/O；超上限时清空重来，避免无限增长
enum DebugLog {
    private static let fileURL = URL(fileURLWithPath: "/tmp/aitodo_debug.log")
    private static let maxBytes = 256 * 1024
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        guard ProcessInfo.processInfo.environment["AITODO_DEBUG"] == "1" else { return }
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let size = attrs[.size] as? UInt64, size > maxBytes {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: fileURL)
        }
    }
}
