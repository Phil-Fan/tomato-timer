import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let notifications = "notificationsEnabled"
        static let showFloatingBall = "showFloatingBall"
        static let writeCalendar = "writeToCalendar"
        static let calendarID = "calendarID"
        static let lastCategoryID = "lastCategoryID"
        static let dailyTarget = "dailyTargetMinutes"
    }

    private let defaults: UserDefaults

    /// 提醒默认开启。
    var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notifications) } }
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

    /// 每天的目标专注总时长（分钟），在分类页里设置。
    var dailyTargetMinutes: Int { didSet { defaults.set(dailyTargetMinutes, forKey: Key.dailyTarget) } }

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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        notificationsEnabled = defaults.object(forKey: Key.notifications) as? Bool ?? true
        showFloatingBall = defaults.object(forKey: Key.showFloatingBall) as? Bool ?? true

        writeToCalendar = defaults.object(forKey: Key.writeCalendar) as? Bool ?? false
        calendarID = defaults.string(forKey: Key.calendarID)

        lastCategoryID = defaults.string(forKey: Key.lastCategoryID)
        dailyTargetMinutes = defaults.object(forKey: Key.dailyTarget) as? Int ?? 240
    }
}
