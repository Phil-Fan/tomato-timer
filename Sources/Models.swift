import Foundation

enum Pomodoro {
    /// 固定的专注时长。
    static let focusMinutes = 45
    static var focusSeconds: TimeInterval { Double(focusMinutes * 60) }
}

/// 预设的专注分类。ratio 是这个分类的目标占比（0...1）。
struct FocusCategory: Identifiable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    var colorIndex: Int
    var ratio: Double

    init(id: UUID = UUID(), name: String, emoji: String, colorIndex: Int, ratio: Double = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.colorIndex = colorIndex
        self.ratio = ratio
    }

    static let defaults: [FocusCategory] = [
        FocusCategory(name: "工作", emoji: "💼", colorIndex: 0, ratio: 0.40),
        FocusCategory(name: "学习", emoji: "📚", colorIndex: 4, ratio: 0.30),
        FocusCategory(name: "写作", emoji: "✍️", colorIndex: 1, ratio: 0.20),
        FocusCategory(name: "阅读", emoji: "📖", colorIndex: 3, ratio: 0.10),
    ]
}

extension FocusCategory: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, emoji, colorIndex, ratio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        emoji = try container.decode(String.self, forKey: .emoji)
        colorIndex = try container.decode(Int.self, forKey: .colorIndex)
        // 兼容没有 ratio 字段的旧数据。
        ratio = try container.decodeIfPresent(Double.self, forKey: .ratio) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(emoji, forKey: .emoji)
        try container.encode(colorIndex, forKey: .colorIndex)
        try container.encode(ratio, forKey: .ratio)
    }
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
