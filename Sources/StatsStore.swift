import Foundation
import Observation

/// 只保留「今天」的统计，跨天自动归零。
@MainActor
@Observable
final class StatsStore {
    private enum Key {
        static let day = "stats.day"
        static let count = "stats.count"
        static let minutes = "stats.minutes"
    }

    private let defaults: UserDefaults

    private(set) var count: Int = 0
    private(set) var minutes: Int = 0
    private var dayKey: String = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func refresh() {
        rolloverIfNeeded()
    }

    func recordFocus(minutes newMinutes: Int) {
        rolloverIfNeeded()
        count += 1
        minutes += max(1, newMinutes)
        save()
    }

    func resetToday() {
        dayKey = Self.key(for: Date())
        count = 0
        minutes = 0
        save()
    }

    private func rolloverIfNeeded() {
        let today = Self.key(for: Date())
        if today != dayKey {
            dayKey = today
            count = 0
            minutes = 0
            save()
        }
    }

    private func load() {
        dayKey = defaults.string(forKey: Key.day) ?? ""
        count = defaults.integer(forKey: Key.count)
        minutes = defaults.integer(forKey: Key.minutes)
        rolloverIfNeeded()
    }

    private func save() {
        defaults.set(dayKey, forKey: Key.day)
        defaults.set(count, forKey: Key.count)
        defaults.set(minutes, forKey: Key.minutes)
    }

    private static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
