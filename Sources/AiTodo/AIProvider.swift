import Foundation
import Security

// MARK: - 服务商

enum AIProviderKind: String, CaseIterable, Identifiable {
    case zhipu
    case minimax
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .zhipu: return "智谱"
        case .minimax: return "MiniMax"
        case .custom: return "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .zhipu: return "https://open.bigmodel.cn/api/paas/v4"
        case .minimax: return "https://api.minimax.chat/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .zhipu: return "GLM-5.3-flash"
        case .minimax: return "minimax-m3"
        case .custom: return ""
        }
    }

    var chatPath: String {
        switch self {
        case .minimax: return "/text/chatcompletion_v2"
        default: return "/chat/completions"
        }
    }
}

// MARK: - 设置存取（Key 存 Keychain，其余存 UserDefaults）

enum AISettings {
    static let keychainAccount = "ai-api-key"

    static var provider: AIProviderKind {
        get { AIProviderKind(rawValue: UserDefaults.standard.string(forKey: "aiProvider") ?? "") ?? .zhipu }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "aiProvider") }
    }

    static var baseURL: String {
        get { UserDefaults.standard.string(forKey: "aiBaseURL") ?? AIProviderKind.zhipu.defaultBaseURL }
        set { UserDefaults.standard.set(newValue, forKey: "aiBaseURL") }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: "aiModel") ?? AIProviderKind.zhipu.defaultModel }
        set { UserDefaults.standard.set(newValue, forKey: "aiModel") }
    }

    static var apiKey: String {
        get { KeychainStore.get(account: keychainAccount) ?? "" }
        set {
            if newValue.isEmpty {
                KeychainStore.delete(account: keychainAccount)
            } else {
                KeychainStore.set(newValue, account: keychainAccount)
            }
        }
    }

    static func applyProviderDefaults(for kind: AIProviderKind) {
        provider = kind
        baseURL = kind.defaultBaseURL
        model = kind.defaultModel
    }

    /// 识别提示词（设置中可编辑；空则用默认）
    static var prompt: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "aiPrompt") ?? ""
            let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? AITaskParser.defaultPrompt : saved
        }
        set { UserDefaults.standard.set(newValue, forKey: "aiPrompt") }
    }
}

// MARK: - Keychain

enum KeychainStore {
    private static let service = "com.aitodo.app"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 解析结果

struct ParsedTask: Identifiable {
    let id = UUID()
    var title: String
    var quadrant: Quadrant
    var selected = true
    /// 非空 = 该条将作为所选主任务的子任务添加
    var parentID: UUID?
    var parentTitle: String?
}

// MARK: - 错误

struct AIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// 模型输出不符合约定 JSON 格式（可附纠正提示重试一次；区别于 Key/HTTP 等不可重试错误）
struct AIFormatError: LocalizedError {
    var errorDescription: String? { "AI 未返回约定格式的 JSON" }
}

// MARK: - AI 解析器

enum AITaskParser {
    static let defaultPrompt = """
    你是待办任务解析助手。用户会提供一张屏幕截图，请从中识别出所有待办任务（TODO、日程、会议、需要完成的工作、别人交代的事项等）。
    只输出 JSON，不要输出任何其他文字，格式：
    {"tasks":[{"title":"简洁的中文任务标题，不超过30字","important":true,"urgent":false}]}
    important 表示是否重要，urgent 表示是否紧急，无法判断时填 false。截图中没有待办任务时输出 {"tasks":[]}
    """

    /// 智能提醒总结提示词（固定内置，与截图识别提示词相互独立）。
    /// 输出紧凑 Markdown：行内语法由 SwiftUI Text 原生渲染，列表由横幅自绘圆点
    static let summaryPrompt = """
    你是待办管理助手。用户会提供当前的未完成待办清单（括号内为所属象限与截止情况），请生成简短的中文总结提醒，使用紧凑的 Markdown 排版：
    1. 第一行用一句话概括整体任务负载；
    2. 换行后用「- 」开头的列表点出最需要注意的事项（最多 3 条），关键任务名用 **加粗**，逾期/临近截止的要标注；
    3. 总字数不超过 130 字；不要输出标题、代码块、表格或有序编号。
    """


    /// 调用视觉模型解析截图：输出不符合 JSON 约定时附纠正提示重试一次；
    /// 网络/Key/HTTP 错误直接抛出，不做盲目的二次等待
    static func parseTasks(imagePNG data: Data) async throws -> [ParsedTask] {
        do {
            return try await request(imagePNG: data)
        } catch is AIFormatError {
            return try await request(imagePNG: data, strict: true)
        }
    }

    /// 从模型返回文本中解析任务（供网络层与测试共用）
    static func parseContent(_ content: String) -> [ParsedTask] {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start < end,
              let data = String(content[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let array = object["tasks"] as? [[String: Any]] else {
            return []
        }
        return array.compactMap { dict in
            guard let title = dict["title"] as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let important = (dict["important"] as? Bool) ?? false
            let urgent = (dict["urgent"] as? Bool) ?? false
            let quadrant: Quadrant
            switch (important, urgent) {
            case (true, true): quadrant = .urgentImportant
            case (true, false): quadrant = .importantNotUrgent
            case (false, true): quadrant = .urgentNotImportant
            default: quadrant = .neither   // 无法解析象限时默认第四象限
            }
            return ParsedTask(title: title.trimmingCharacters(in: .whitespacesAndNewlines), quadrant: quadrant)
        }
    }

    private static func request(imagePNG data: Data, strict: Bool = false) async throws -> [ParsedTask] {
        guard !AISettings.apiKey.isEmpty else {
            throw AIError(message: "未配置 API Key，请在设置中填写")
        }
        guard !AISettings.model.isEmpty, !AISettings.baseURL.isEmpty,
              let url = URL(string: AISettings.baseURL + AISettings.provider.chatPath) else {
            throw AIError(message: "AI 服务地址无效，请检查设置")
        }
        let b64 = data.base64EncodedString()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(AISettings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let userText = strict ? "请只输出 JSON。" : "请识别截图中的待办任务。"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": AISettings.model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": AISettings.prompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(b64)"]],
                    ["type": "text", "text": userText]
                ]]
            ]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError(message: "网络响应异常")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIError(message: "API Key 无效或无权限（HTTP \(http.statusCode)）")
            }
            throw AIError(message: "AI 服务返回错误（HTTP \(http.statusCode)）：\(String(body.prefix(160)))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIFormatError()
        }
        let tasks = parseContent(content)
        if tasks.isEmpty && !content.contains("tasks") {
            // 区分「确实没有任务」与「输出不符合 JSON 约定」
            throw AIFormatError()
        }
        return tasks
    }

    /// 整体硬超时：与操作竞速，到点抛错并取消未完成的操作
    /// （timeoutInterval 是空闲超时，服务端慢速吐字节时不会触发；也兜底钥匙串授权弹窗阻塞等非网络挂起）
    static func withRequestTimeout<T>(seconds: TimeInterval = 40,
                                      _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AIError(message: "AI 请求超时，请稍后重试")
            }
            guard let result = try await group.next() else {
                throw AIError(message: "AI 请求失败")
            }
            group.cancelAll()
            return result
        }
    }

    /// 智能提醒：把未完成任务清单交给模型，返回一段总结文本
    static func summarizeTasks(_ lines: [String]) async throws -> String {
        guard !lines.isEmpty else { return "" }
        return try await requestText(system: summaryPrompt,
                                     user: "当前未完成待办：\n" + lines.joined(separator: "\n"))
    }

    /// 纯文本 chat completion（智能提醒总结用），复用现有服务商配置与错误文案
    private static func requestText(system: String, user: String) async throws -> String {
        guard !AISettings.apiKey.isEmpty else {
            throw AIError(message: "未配置 API Key，请在设置中填写")
        }
        guard !AISettings.model.isEmpty, !AISettings.baseURL.isEmpty,
              let url = URL(string: AISettings.baseURL + AISettings.provider.chatPath) else {
            throw AIError(message: "AI 服务地址无效，请检查设置")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // 空闲超时：服务端慢速吐字节时不会触发，仅作为兜底；整体硬超时见 withRequestTimeout
        request.timeoutInterval = 30
        request.setValue("Bearer \(AISettings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": AISettings.model,
            "temperature": 0.3,
            // 不设 max_tokens：推理模型（如 GLM-5.3-flash）的思考会占掉配额，导致 content 为空
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ])

        let (data, response): (Data, URLResponse) = try await withRequestTimeout {
            try await URLSession.shared.data(for: request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AIError(message: "网络响应异常")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 || http.statusCode == 403 {
                throw AIError(message: "API Key 无效或无权限（HTTP \(http.statusCode)）")
            }
            throw AIError(message: "AI 服务返回错误（HTTP \(http.statusCode)）：\(String(body.prefix(160)))")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError(message: "AI 未返回有效内容")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - 连接测试

enum AIProvider {
    static func testConnection() async throws -> String {
        guard !AISettings.apiKey.isEmpty else {
            throw AIError(message: "请先填写 API Key")
        }
        guard !AISettings.model.isEmpty, !AISettings.baseURL.isEmpty,
              let url = URL(string: AISettings.baseURL + AISettings.provider.chatPath) else {
            throw AIError(message: "服务地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(AISettings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": AISettings.model,
            "max_tokens": 8,
            "messages": [["role": "user", "content": "ping"]]
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError(message: "网络响应异常")
        }
        guard http.statusCode == 200 else {
            throw AIError(message: "连接失败（HTTP \(http.statusCode)）：请检查 Key 与模型名")
        }
        return "连接成功（模型：\(AISettings.model)）"
    }
}
