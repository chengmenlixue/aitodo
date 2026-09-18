import SwiftUI

enum ViewMode: String {
    case grid
    case list
}

/// 顶层页面：主界面 / 归档
enum Page {
    case main
    case archive
}

/// 艾森豪威尔四象限
enum Quadrant: Int, CaseIterable, Codable, Identifiable {
    case urgentImportant = 0     // 重要 · 紧急
    case importantNotUrgent = 1  // 重要 · 不紧急
    case urgentNotImportant = 2  // 紧急 · 不重要
    case neither = 3             // 不重要 · 不紧急

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .urgentImportant: return "重要 · 紧急"
        case .importantNotUrgent: return "重要 · 不紧急"
        case .urgentNotImportant: return "紧急 · 不重要"
        case .neither: return "不重要 · 不紧急"
        }
    }

    var actionHint: String {
        switch self {
        case .urgentImportant: return "立刻做"
        case .importantNotUrgent: return "计划做"
        case .urgentNotImportant: return "委托做"
        case .neither: return "减少做"
        }
    }

    var accentHex: UInt32 {
        switch self {
        case .urgentImportant: return 0xEF6A5A
        case .importantNotUrgent: return 0x4CAF7E
        case .urgentNotImportant: return 0xE5A63C
        case .neither: return 0x6E96C8
        }
    }

    var accent: Color { Color(hex: accentHex) }
}

struct TaskItem: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var quadrant: Quadrant
    var isDone = false
    var createdAt = Date()
    var dueDate: Date?
    var completedAt: Date?
    var isArchived = false
    var archivedAt: Date?

    init(id: UUID = UUID(),
         title: String,
         quadrant: Quadrant,
         isDone: Bool = false,
         createdAt: Date = Date(),
         dueDate: Date? = nil,
         completedAt: Date? = nil,
         isArchived: Bool = false,
         archivedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.quadrant = quadrant
        self.isDone = isDone
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }
}

// 手动解码：兼容旧版本数据文件（缺少新增字段时取默认值，避免整库解析失败）
extension TaskItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id, title, quadrant, isDone, createdAt, dueDate
        case completedAt, isArchived, archivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        quadrant = try container.decode(Quadrant.self, forKey: .quadrant)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)
    }
}
