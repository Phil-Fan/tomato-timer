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
           let decoded = try? JSONDecoder().decode([FocusCategory].self, from: data) {
            items = decoded
        } else {
            items = FocusCategory.defaults
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
        let nextColor = items.count % CategoryPalette.hexes.count
        items.append(FocusCategory(name: "新分类", emoji: "✨", colorIndex: nextColor))
    }

    func remove(id: UUID) {
        guard items.count > 1 else { return }
        items.removeAll { $0.id == id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: Key.categories)
    }
}
