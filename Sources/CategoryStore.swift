import Foundation
import Observation

/// 分类列表，持久化到 UserDefaults。
@MainActor
@Observable
final class CategoryStore {
    private enum Key {
        static let categories = "focusCategories"
    }

    var items: [FocusCategory] {
        didSet { save() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.categories),
           let decoded = try? JSONDecoder().decode([FocusCategory].self, from: data),
           !decoded.isEmpty {
            items = decoded
        } else {
            items = FocusCategory.defaults
        }

        // 旧版本没有目标比例，按分类名补默认值；再不行就平均分。
        if items.reduce(0, { $0 + max(0, $1.ratio) }) <= 0 {
            let equalShare = 1.0 / Double(max(1, items.count))
            for index in items.indices {
                items[index].ratio = FocusCategory.defaults
                    .first { $0.name == items[index].name }?.ratio ?? equalShare
            }
        }

        // 让分类从第一次启动起就有稳定的 UUID，方便记住上次选择。
        save()
    }

    func category(id: UUID?) -> FocusCategory? {
        guard let id else { return nil }
        return items.first { $0.id == id }
    }

    func category(rawID: String?) -> FocusCategory? {
        guard let rawID, let id = UUID(uuidString: rawID) else { return nil }
        return category(id: id)
    }

    func add() {
        guard items.count < 8 else { return }

        let share = 1.0 / Double(items.count + 1)
        let remaining = 1 - share
        let total = items.reduce(0) { $0 + max(0, $1.ratio) }

        if total > 0 {
            for index in items.indices {
                items[index].ratio = max(0, items[index].ratio) / total * remaining
            }
        }

        items.append(
            FocusCategory(
                name: "新分类",
                emoji: "✨",
                colorIndex: items.count % CategoryPalette.hexes.count,
                ratio: share
            )
        )
    }

    func remove(id: UUID) {
        guard items.count > 1 else { return }
        items.removeAll { $0.id == id }
        normalizeRatios()
    }

    /// 按现有比例缩放到合计 100%。
    func normalizeRatios() {
        let positives = items.map { max(0, $0.ratio) }
        let total = positives.reduce(0, +)

        if total <= 0 {
            averageRatios()
        } else {
            for index in items.indices {
                items[index].ratio = positives[index] / total
            }
        }
    }

    func averageRatios() {
        let share = 1.0 / Double(max(1, items.count))
        for index in items.indices {
            items[index].ratio = share
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.categories)
    }
}
