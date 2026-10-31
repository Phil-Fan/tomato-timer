import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let history: SessionHistory
    let calendar: CalendarService
    let categories: CategoryStore
    let engine: TimerEngine
    let updates: UpdateService

    init() {
        let settings = AppSettings()
        let history = SessionHistory()
        let calendar = CalendarService()
        let categories = CategoryStore()

        self.settings = settings
        self.history = history
        self.calendar = calendar
        self.categories = categories
        self.updates = UpdateService(settings: settings)
        self.engine = TimerEngine(
            settings: settings,
            history: history,
            calendar: calendar,
            categories: categories
        )

        #if DEBUG
        // 开发期冒烟测试：TOMATO_AUTOSTART=1 时直接开始一个番茄。
        if ProcessInfo.processInfo.environment["TOMATO_AUTOSTART"] == "1" {
            let minutes = max(1, Int(ProcessInfo.processInfo.environment["TOMATO_AUTOSTART_MINUTES"] ?? "1") ?? 1)
            engine.startFocus(category: categories.items.first, durationMinutes: minutes)
        }
        #endif
    }
}
