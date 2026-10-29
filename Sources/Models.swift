import Foundation

/// 一个番茄周期里的三种阶段。
enum Phase: String, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "专注"
        case .shortBreak: "短休息"
        case .longBreak: "长休息"
        }
    }

    var emoji: String {
        switch self {
        case .focus: "🍅"
        case .shortBreak: "☕️"
        case .longBreak: "🌿"
        }
    }

    var isBreak: Bool { self != .focus }
}

/// 预设的专注分类。分类决定卡片上的颜色，也会写进日历标题。
struct FocusCategory: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    var colorIndex: Int

    init(id: UUID = UUID(), name: String, emoji: String, colorIndex: Int) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorIndex = colorIndex
    }

    static let defaults: [FocusCategory] = [
        FocusCategory(name: "工作", emoji: "💼", colorIndex: 0),
        FocusCategory(name: "学习", emoji: "📚", colorIndex: 4),
        FocusCategory(name: "写作", emoji: "✍️", colorIndex: 1),
        FocusCategory(name: "阅读", emoji: "📖", colorIndex: 3),
    ]
}

enum CategoryPalette {
    static let hexes = ["#E5484D", "#F76B15", "#E2B203", "#2FA36B", "#2B7FFF", "#8E4EC6"]

    static func colorIndex(for raw: Int) -> Int {
        let count = hexes.count
        return ((raw % count) + count) % count
    }
}

struct CalendarOption: Identifiable, Hashable {
    let id: String
    let title: String
    let source: String
}
