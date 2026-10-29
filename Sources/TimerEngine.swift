import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TimerEngine {
    private let settings: AppSettings
    private let history: SessionHistory
    private let calendar: CalendarService
    private let categories: CategoryStore

    private(set) var isRunning = false
    private(set) var hasStarted = false
    private(set) var activeCategory: FocusCategory?
    private(set) var now = Date()

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var sessionStart: Date?
    private var plannedDuration: TimeInterval = Pomodoro.focusSeconds
    private var ticker: Task<Void, Never>?

    init(settings: AppSettings, history: SessionHistory, calendar: CalendarService, categories: CategoryStore) {
        self.settings = settings
        self.history = history
        self.calendar = calendar
        self.categories = categories
        startTicker()
    }

    // MARK: - 派生状态

    var sessionTitle: String {
        activeCategory?.displayName ?? "专注"
    }

    var menuBarSymbol: String {
        activeCategory?.symbol ?? "timer"
    }

    var menuBarText: String {
        guard isRunning || hasStarted else { return "" }
        return timeString
    }

    var sessionTotalSeconds: TimeInterval {
        max(1, plannedDuration)
    }

    var remainingSeconds: TimeInterval {
        if isRunning, let endDate {
            return max(0, endDate.timeIntervalSince(now))
        }
        if let pausedRemaining {
            return max(0, pausedRemaining)
        }
        if hasStarted {
            return plannedDuration
        }
        return Pomodoro.focusSeconds
    }

    var progress: Double {
        let total = sessionTotalSeconds
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - remainingSeconds / total))
    }

    var timeString: String {
        let total = Int(remainingSeconds.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - 操作

    func toggle() {
        isRunning ? pause() : resume()
    }

    func startFocus(category: FocusCategory?, durationMinutes: Int = Pomodoro.focusMinutes) {
        clearSession()
        activeCategory = category
        plannedDuration = TimeInterval(max(1, durationMinutes) * 60)
        sessionStart = Date()
        begin()
    }

    func resume() {
        guard !isRunning else { return }

        if !hasStarted {
            startFocus(category: preferredCategory)
            return
        }
        begin()
    }

    private func begin() {
        guard !isRunning else { return }
        let duration = pausedRemaining ?? plannedDuration
        guard duration > 0 else { return }

        if sessionStart == nil { sessionStart = Date() }

        endDate = Date().addingTimeInterval(duration)
        pausedRemaining = nil
        hasStarted = true
        isRunning = true
        now = Date()

        scheduleNotification(after: duration)
    }

    func pause() {
        guard isRunning, let endDate else { return }

        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        isRunning = false
        hasStarted = true
        now = Date()
        NotificationScheduler.cancel(id: notificationID)
    }

    func reset() {
        clearSession()
    }

    // MARK: - 计时

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                guard self.isRunning else { continue }

                self.now = Date()
                if let end = self.endDate, self.now >= end {
                    self.complete()
                }
            }
        }
    }

    private var preferredCategory: FocusCategory? {
        categories.category(rawID: settings.lastCategoryID) ?? categories.items.first
    }

    private func clearSession() {
        NotificationScheduler.cancel(id: notificationID)
        isRunning = false
        hasStarted = false
        endDate = nil
        pausedRemaining = nil
        sessionStart = nil
        activeCategory = nil
        plannedDuration = Pomodoro.focusSeconds
        now = Date()
    }

    private func complete() {
        let completedAt = Date()
        let duration = plannedDuration
        let minutes = max(1, Int((duration / 60).rounded()))
        let category = activeCategory

        isRunning = false
        hasStarted = false
        endDate = nil
        pausedRemaining = nil
        now = completedAt

        history.record(category: category, minutes: minutes, at: completedAt)
        sendFeishuCard(category: category, minutes: minutes, completedAt: completedAt)

        if settings.writeToCalendar {
            let categoryName = category?.displayName ?? "专注"
            let title = "专注 · \(categoryName) · \(minutes) 分钟"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = "HH:mm"
            let notes = "分类：\(categoryName) · 第 \(history.todayCount) 个专注 · 完成于 \(formatter.string(from: completedAt))"
            calendar.writeFocus(
                start: completedAt.addingTimeInterval(-duration),
                end: completedAt,
                title: title,
                notes: notes,
                calendarID: settings.calendarID
            )
        }

        activeCategory = nil
        sessionStart = nil
        plannedDuration = Pomodoro.focusSeconds
        playChime()
    }

    // MARK: - 通知与声音

    private func sendFeishuCard(category: FocusCategory?, minutes: Int, completedAt: Date) {
        guard settings.feishuWebhookEnabled else { return }
        let url = settings.feishuWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        let config = FeishuWebhook.Config(
            webhookURL: url,
            secret: settings.feishuWebhookSecret
        )
        let summary = FeishuWebhook.Summary(
            categoryName: category?.displayName ?? "专注",
            minutes: minutes,
            todayCount: history.todayCount,
            todayMinutes: history.todayMinutes,
            dailyTargetMinutes: settings.dailyTargetMinutes,
            completedAt: completedAt
        )

        Task {
            try? await FeishuWebhook.send(config: config, summary: summary)
        }
    }

    private var notificationID: String { "tomato.session" }

    private func scheduleNotification(after seconds: TimeInterval) {
        guard settings.notificationsEnabled else { return }

        let minutes = max(1, Int((plannedDuration / 60).rounded()))
        NotificationScheduler.schedule(
            in: seconds,
            title: "专注完成",
            body: "\(sessionTitle) \(minutes) 分钟已完成，已记入统计。",
            id: notificationID
        )
    }

    private func playChime() {
        guard settings.notificationsEnabled else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
