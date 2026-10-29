import Foundation
import Observation

struct SessionRecord: Identifiable, Codable, Hashable {
    var id: UUID
    var completedAt: Date
    var minutes: Int
    var categoryID: UUID?
    var categoryName: String
    var emoji: String

    init(
        id: UUID = UUID(),
        completedAt: Date = Date(),
        minutes: Int,
        categoryID: UUID?,
        categoryName: String,
        emoji: String
    ) {
        self.id = id
        self.completedAt = completedAt
        self.minutes = minutes
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.emoji = emoji
    }
}

/// 完成记录，统计页面和「今日」数字都从这里派生。
@MainActor
@Observable
final class SessionHistory {
    private enum Key {
        static let records = "sessionHistory"
        static let keepDays = 400
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private(set) var records: [SessionRecord] = []

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar

        if let data = defaults.data(forKey: Key.records),
           let decoded = try? JSONDecoder().decode([SessionRecord].self, from: data) {
            records = decoded
        }
        prune()
    }

    func record(category: FocusCategory?, minutes: Int, at date: Date = Date()) {
        records.append(
            SessionRecord(
                completedAt: date,
                minutes: max(1, minutes),
                categoryID: category?.id,
                categoryName: category?.name ?? "专注",
                emoji: category?.emoji ?? "🍅"
            )
        )
        prune()
        save()
    }

    var todayRecords: [SessionRecord] {
        records(on: Date())
    }

    var todayCount: Int {
        todayRecords.count
    }

    var todayMinutes: Int {
        todayRecords.reduce(0) { $0 + $1.minutes }
    }

    func records(on date: Date) -> [SessionRecord] {
        guard let interval = calendar.dateInterval(of: .day, for: date) else { return [] }
        return records.filter { interval.contains($0.completedAt) }
    }

    func resetToday() {
        let today = Set(records(on: Date()).map(\.id))
        records.removeAll { today.contains($0.id) }
        save()
    }

    func clearAll() {
        records.removeAll()
        save()
    }

    private func prune() {
        guard let cutoff = calendar.date(byAdding: .day, value: -Key.keepDays, to: Date()) else { return }
        records.removeAll { $0.completedAt < cutoff }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Key.records)
    }
}
