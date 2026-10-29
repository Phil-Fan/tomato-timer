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

        normalizeRatios()
        save()
    }

    var totalPercent: Int {
        Int((items.reduce(0) { $0 + max(0, $1.ratio) } * 100).rounded())
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
                symbol: "sparkles",
                colorIndex: items.count % CategoryPalette.hexes.count,
                ratio: share
            )
        )
        normalizeRatios()
    }

    func remove(id: UUID) {
        guard items.count > 1 else { return }
        items.removeAll { $0.id == id }
        normalizeRatios()
    }

    // 修改都按 ID 查找，行视图被删除后不会越界访问数组。
    func updateName(id: UUID, name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = name
    }

    func updateSymbol(id: UUID, symbol: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].symbol = symbol
    }

    func updateRatio(id: UUID, percent: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].ratio = Double(min(100, max(0, percent))) / 100
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
