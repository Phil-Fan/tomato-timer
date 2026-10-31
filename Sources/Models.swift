import Foundation

enum Pomodoro {
    /// 可选的专注时长（分钟）。
    static let durationOptions = [15, 30, 45]
    /// 默认专注时长。
    static let defaultMinutes = 45

    static var defaultSeconds: TimeInterval { Double(defaultMinutes * 60) }

    /// 把任意分钟数收敛到可选项里，避免旧偏好或外部输入出现未知时长。
    static func normalizedMinutes(_ minutes: Int) -> Int {
        durationOptions.contains(minutes) ? minutes : defaultMinutes
    }
}

/// 预设的专注分类。ratio 是这个分类在每日目标里占的比例（0...1）。
struct FocusCategory: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    /// SF Symbols 名称。
    var symbol: String
    var colorIndex: Int
    var ratio: Double

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String,
        colorIndex: Int,
        ratio: Double = 0
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorIndex = colorIndex
        self.ratio = ratio
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名" : trimmed
    }

    static let defaults: [FocusCategory] = [
        FocusCategory(name: "工作", symbol: "briefcase", colorIndex: 0, ratio: 0.40),
        FocusCategory(name: "学习", symbol: "graduationcap", colorIndex: 4, ratio: 0.30),
        FocusCategory(name: "写作", symbol: "square.and.pencil", colorIndex: 1, ratio: 0.20),
        FocusCategory(name: "阅读", symbol: "book", colorIndex: 3, ratio: 0.10),
    ]
}

struct IconChoice: Identifiable, Hashable {
    let name: String
    let symbol: String

    var id: String { symbol }

    static let all: [IconChoice] = [
        IconChoice(name: "工作", symbol: "briefcase"),
        IconChoice(name: "学习", symbol: "graduationcap"),
        IconChoice(name: "阅读", symbol: "book"),
        IconChoice(name: "写作", symbol: "square.and.pencil"),
        IconChoice(name: "编程", symbol: "keyboard"),
        IconChoice(name: "电脑", symbol: "laptopcomputer"),
        IconChoice(name: "思考", symbol: "brain.head.profile"),
        IconChoice(name: "灵感", symbol: "lightbulb"),
        IconChoice(name: "目标", symbol: "target"),
        IconChoice(name: "数据", symbol: "chart.bar"),
        IconChoice(name: "设计", symbol: "paintpalette"),
        IconChoice(name: "音乐", symbol: "music.note"),
        IconChoice(name: "运动", symbol: "figure.run"),
        IconChoice(name: "生活", symbol: "leaf"),
        IconChoice(name: "语言", symbol: "globe"),
        IconChoice(name: "邮件", symbol: "envelope"),
        IconChoice(name: "会议", symbol: "person.2"),
        IconChoice(name: "家庭", symbol: "house"),
        IconChoice(name: "清单", symbol: "checklist"),
        IconChoice(name: "收藏", symbol: "star"),
        IconChoice(name: "健康", symbol: "heart"),
        IconChoice(name: "其他", symbol: "sparkles"),
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
