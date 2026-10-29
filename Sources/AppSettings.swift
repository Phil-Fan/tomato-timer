import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let focus = "focusMinutes"
        static let shortBreak = "shortBreakMinutes"
        static let longBreak = "longBreakMinutes"
        static let longEvery = "longBreakEvery"
        static let autoBreaks = "autoStartBreaks"
        static let autoFocus = "autoStartFocus"
        static let notifications = "notificationsEnabled"
        static let sound = "playSound"
        static let showTime = "showTimeInMenuBar"
        static let writeCalendar = "writeToCalendar"
        static let calendarID = "calendarID"
        static let titleTemplate = "eventTitleTemplate"
        static let lastFocusMinutes = "lastFocusMinutes"
        static let lastCategoryID = "lastCategoryID"
    }

    private let defaults: UserDefaults

    var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Key.focus) } }
    var shortBreakMinutes: Int { didSet { defaults.set(shortBreakMinutes, forKey: Key.shortBreak) } }
    var longBreakMinutes: Int { didSet { defaults.set(longBreakMinutes, forKey: Key.longBreak) } }
    var longBreakEvery: Int { didSet { defaults.set(longBreakEvery, forKey: Key.longEvery) } }

    var autoStartBreaks: Bool { didSet { defaults.set(autoStartBreaks, forKey: Key.autoBreaks) } }
    var autoStartFocus: Bool { didSet { defaults.set(autoStartFocus, forKey: Key.autoFocus) } }

    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notifications) } }
    var playSound: Bool { didSet { defaults.set(playSound, forKey: Key.sound) } }
    var showTimeInMenuBar: Bool { didSet { defaults.set(showTimeInMenuBar, forKey: Key.showTime) } }

    var writeToCalendar: Bool { didSet { defaults.set(writeToCalendar, forKey: Key.writeCalendar) } }
    var calendarID: String? {
        didSet {
            if let calendarID {
                defaults.set(calendarID, forKey: Key.calendarID)
            } else {
                defaults.removeObject(forKey: Key.calendarID)
            }
        }
    }

    /// 支持 {category}、{minutes}、{count} 三个占位符。
    var eventTitleTemplate: String { didSet { defaults.set(eventTitleTemplate, forKey: Key.titleTemplate) } }

    /// 开始卡片上一次选择的时长与分类。
    var lastFocusMinutes: Int { didSet { defaults.set(lastFocusMinutes, forKey: Key.lastFocusMinutes) } }
    var lastCategoryID: String? {
        didSet {
            if let lastCategoryID {
                defaults.set(lastCategoryID, forKey: Key.lastCategoryID)
            } else {
                defaults.removeObject(forKey: Key.lastCategoryID)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedFocus = defaults.object(forKey: Key.focus) as? Int ?? 25
        focusMinutes = storedFocus
        shortBreakMinutes = defaults.object(forKey: Key.shortBreak) as? Int ?? 5
        longBreakMinutes = defaults.object(forKey: Key.longBreak) as? Int ?? 15
        longBreakEvery = defaults.object(forKey: Key.longEvery) as? Int ?? 4

        autoStartBreaks = defaults.object(forKey: Key.autoBreaks) as? Bool ?? true
        autoStartFocus = defaults.object(forKey: Key.autoFocus) as? Bool ?? false

        notificationsEnabled = defaults.object(forKey: Key.notifications) as? Bool ?? true
        playSound = defaults.object(forKey: Key.sound) as? Bool ?? true
        showTimeInMenuBar = defaults.object(forKey: Key.showTime) as? Bool ?? true

        writeToCalendar = defaults.object(forKey: Key.writeCalendar) as? Bool ?? false
        calendarID = defaults.string(forKey: Key.calendarID)
        eventTitleTemplate = defaults.string(forKey: Key.titleTemplate) ?? "🍅 {category} · {minutes} 分钟"

        lastFocusMinutes = defaults.object(forKey: Key.lastFocusMinutes) as? Int ?? storedFocus
        lastCategoryID = defaults.string(forKey: Key.lastCategoryID)
    }

    func durationMinutes(for phase: Phase) -> Int {
        switch phase {
        case .focus: max(1, focusMinutes)
        case .shortBreak: max(1, shortBreakMinutes)
        case .longBreak: max(1, longBreakMinutes)
        }
    }

    func resolvedTitle(minutes: Int, count: Int, category: String) -> String {
        let template = eventTitleTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = template.isEmpty ? "🍅 {category} · {minutes} 分钟" : template
        return base
            .replacingOccurrences(of: "{category}", with: category)
            .replacingOccurrences(of: "{minutes}", with: "\(minutes)")
            .replacingOccurrences(of: "{count}", with: "\(count)")
    }
}
