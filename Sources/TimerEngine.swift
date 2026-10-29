import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class TimerEngine {
    private let settings: AppSettings
    private let stats: StatsStore
    private let calendar: CalendarService
    private let categories: CategoryStore

    private(set) var phase: Phase = .focus
    private(set) var isRunning = false
    private(set) var hasStarted = false
    private(set) var completedInCycle = 0
    private(set) var activeCategory: FocusCategory?
    private(set) var now = Date()

    private var endDate: Date?
    private var pausedRemaining: TimeInterval?
    private var sessionStart: Date?
    private var plannedDuration: TimeInterval?
    private var ticker: Task<Void, Never>?

    init(settings: AppSettings, stats: StatsStore, calendar: CalendarService, categories: CategoryStore) {
        self.settings = settings
        self.stats = stats
        self.calendar = calendar
        self.categories = categories
        startTicker()
    }

    // MARK: - 派生状态

    var sessionTitle: String {
        if phase == .focus, let activeCategory {
            return "\(activeCategory.emoji) \(activeCategory.name)"
        }
        return phase.title
    }

    var sessionEmoji: String {
        activeCategory?.emoji ?? phase.emoji
    }

    var totalSeconds: TimeInterval {
        Double(settings.durationMinutes(for: phase) * 60)
    }

    /// 当前这段会话计划的总时长（允许单次覆盖设置里的默认时长）。
    var sessionTotalSeconds: TimeInterval {
        plannedDuration ?? totalSeconds
    }

    var remainingSeconds: TimeInterval {
        if isRunning, let endDate {
            return max(0, endDate.timeIntervalSince(now))
        }
        if let pausedRemaining {
            return max(0, pausedRemaining)
        }
        if let plannedDuration {
            return max(0, plannedDuration)
        }
        return totalSeconds
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

    var cycleDots: Int {
        let every = max(1, settings.longBreakEvery)
        if phase == .longBreak { return every }
        return completedInCycle % every
    }

    var menuBarLabel: String {
        guard settings.showTimeInMenuBar, isRunning || hasStarted else {
            return sessionEmoji
        }
        return "\(sessionEmoji) \(timeString)"
    }

    // MARK: - 操作

    func toggle() {
        isRunning ? pause() : resume()
    }

    /// 从开始卡片进入一次专注。
    func startFocus(minutes: Int, category: FocusCategory?) {
        clearSessionState()
        phase = .focus
        activeCategory = category
        plannedDuration = TimeInterval(max(1, minutes) * 60)
        sessionStart = Date()
        begin()
    }

    /// 自动开始当前的休息阶段。
    func startBreak() {
        clearSessionState()
        if phase == .focus {
            phase = .shortBreak
        }
        plannedDuration = Double(settings.durationMinutes(for: phase) * 60)
        sessionStart = Date()
        begin()
    }

    func resume() {
        guard !isRunning else { return }

        if sessionStart == nil {
            sessionStart = Date()
            plannedDuration = totalSeconds
            if phase == .focus, activeCategory == nil {
                activeCategory = preferredCategory
            }
        }
        begin()
    }

    private func begin() {
        guard !isRunning else { return }
        let duration = pausedRemaining ?? plannedDuration ?? totalSeconds
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
        clearSessionState()
    }

    /// 跳过当前阶段：不记录、不计入番茄数。
    func skip() {
        let wasFocus = phase == .focus
        clearSessionState()
        phase = wasFocus ? .shortBreak : .focus
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

    private func clearSessionState() {
        NotificationScheduler.cancel(id: notificationID)
        isRunning = false
        hasStarted = false
        endDate = nil
        pausedRemaining = nil
        sessionStart = nil
        plannedDuration = nil
        activeCategory = nil
        now = Date()
    }

    private func complete() {
        let finished = phase
        let completedAt = Date()
        let duration = plannedDuration ?? totalSeconds
        let minutes = max(1, Int((duration / 60).rounded()))
        let category = activeCategory

        isRunning = false
        hasStarted = false
        endDate = nil
        pausedRemaining = nil
        now = completedAt

        if finished == .focus {
            completedInCycle += 1
            stats.recordFocus(minutes: minutes)

            if settings.writeToCalendar {
                let categoryName = category?.name ?? "专注"
                let title = settings.resolvedTitle(
                    minutes: minutes,
                    count: stats.count,
                    category: categoryName
                )
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "zh_CN")
                formatter.dateFormat = "HH:mm"
                let notes = "分类：\(categoryName) · 第 \(stats.count) 个番茄 · 完成于 \(formatter.string(from: completedAt))"
                calendar.writeFocus(
                    start: completedAt.addingTimeInterval(-duration),
                    end: completedAt,
                    title: title,
                    notes: notes,
                    calendarID: settings.calendarID
                )
            }

            phase = completedInCycle % max(1, settings.longBreakEvery) == 0 ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }

        activeCategory = nil
        sessionStart = nil
        plannedDuration = nil
        playChime()

        // 自动开始下一段。
        if finished == .focus {
            if settings.autoStartBreaks { startBreak() }
        } else if settings.autoStartFocus {
            startFocus(minutes: settings.lastFocusMinutes, category: preferredCategory)
        }
    }

    // MARK: - 通知与声音

    private var notificationID: String { "tomato.session" }

    private func scheduleNotification(after seconds: TimeInterval) {
        guard settings.notificationsEnabled else { return }

        let title: String
        let body: String
        if phase == .focus {
            title = "专注完成 🍅"
            body = "\(sessionTitle)结束，休息一下。"
        } else {
            title = "休息结束 ☕️"
            body = "准备好了就开始下一个番茄。"
        }
        NotificationScheduler.schedule(in: seconds, title: title, body: body, id: notificationID)
    }

    private func playChime() {
        guard settings.playSound else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
