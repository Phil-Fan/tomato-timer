import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let notifications = "notificationsEnabled"
        static let showTime = "showTimeInMenuBar"
        static let showFloatingBall = "showFloatingBall"
        static let writeCalendar = "writeToCalendar"
        static let calendarID = "calendarID"
        static let lastCategoryID = "lastCategoryID"
        static let dailyTarget = "dailyTargetMinutes"
    }

    private let defaults: UserDefaults

    /// 提醒默认开启。
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notifications) } }
    var showTimeInMenuBar: Bool { didSet { defaults.set(showTimeInMenuBar, forKey: Key.showTime) } }
    var showFloatingBall: Bool { didSet { defaults.set(showFloatingBall, forKey: Key.showFloatingBall) } }

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

    /// 开始卡片上一次选择的分类。
    var lastCategoryID: String? {
        didSet {
            if let lastCategoryID {
                defaults.set(lastCategoryID, forKey: Key.lastCategoryID)
            } else {
                defaults.removeObject(forKey: Key.lastCategoryID)
            }
        }
    }

    /// 每天固定的预计专注时长（分钟）。
    var dailyTargetMinutes: Int { didSet { defaults.set(dailyTargetMinutes, forKey: Key.dailyTarget) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        notificationsEnabled = defaults.object(forKey: Key.notifications) as? Bool ?? true
        showTimeInMenuBar = defaults.object(forKey: Key.showTime) as? Bool ?? true
        showFloatingBall = defaults.object(forKey: Key.showFloatingBall) as? Bool ?? true

        writeToCalendar = defaults.object(forKey: Key.writeCalendar) as? Bool ?? false
        calendarID = defaults.string(forKey: Key.calendarID)

        lastCategoryID = defaults.string(forKey: Key.lastCategoryID)
        dailyTargetMinutes = defaults.object(forKey: Key.dailyTarget) as? Int ?? 240
    }
}
