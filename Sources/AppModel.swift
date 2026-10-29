import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let stats: StatsStore
    let calendar: CalendarService
    let categories: CategoryStore
    let engine: TimerEngine

    init() {
        let settings = AppSettings()
        let stats = StatsStore()
        let calendar = CalendarService()
        let categories = CategoryStore()

        self.settings = settings
        self.stats = stats
        self.calendar = calendar
        self.categories = categories
        self.engine = TimerEngine(
            settings: settings,
            stats: stats,
            calendar: calendar,
            categories: categories
        )
    }
}
