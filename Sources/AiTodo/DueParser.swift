import Foundation

/// 输入快捷语法解析：`18:30 买菜`、`明天 9:00 周报`
enum DueParser {
    struct Parsed {
        let title: String
        let due: Date?
    }

    static func parse(_ raw: String) -> Parsed {
        let pattern = "^\\s*(今天|明天)?\\s*(\\d{1,2}):(\\d{2})\\s+(.+)$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return Parsed(title: raw, due: nil)
        }
        let range = NSRange(raw.startIndex..., in: raw)
        guard let match = regex.firstMatch(in: raw, range: range),
              match.range(at: 4).location != NSNotFound,
              let titleRange = Range(match.range(at: 4), in: raw) else {
            return Parsed(title: raw, due: nil)
        }

        let dayPrefix = match.range(at: 1).location != NSNotFound
            ? String(raw[Range(match.range(at: 1), in: raw)!]) : ""
        let hour = Int(String(raw[Range(match.range(at: 2), in: raw)!])) ?? -1
        let minute = Int(String(raw[Range(match.range(at: 3), in: raw)!])) ?? -1
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return Parsed(title: raw, due: nil)
        }

        let calendar = Calendar.current
        var day = calendar.startOfDay(for: Date())
        if dayPrefix == "明天" {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        var due = calendar.date(from: components) ?? Date()
        // 未写“今天/明天”且时间已过 → 顺延到明天
        if dayPrefix.isEmpty && due <= Date() {
            due = calendar.date(byAdding: .day, value: 1, to: due) ?? due
        }
        let title = String(raw[titleRange]).trimmingCharacters(in: .whitespaces)
        return Parsed(title: title, due: due)
    }
}

enum DueChipText {
    static func text(for date: Date) -> String {
        let calendar = Calendar.current
        let time = timeFormatter.string(from: date)
        if calendar.isDateInToday(date) { return "今天 " + time }
        if calendar.isDateInTomorrow(date) { return "明天 " + time }
        if calendar.isDateInYesterday(date) { return "昨天 " + time }
        return dayFormatter.string(from: date) + " " + time
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()
}
