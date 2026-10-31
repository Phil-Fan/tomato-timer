import EventKit
import Foundation
import Observation

/// 从日历补充的专注时段：标题以分类名开头的日程按分类计入统计。
struct CalendarFocusEntry: Identifiable, Hashable {
    let id: String
    let startDate: Date
    let endDate: Date
    let minutes: Int
    let categoryID: UUID
    let categoryName: String
}

extension CalendarFocusEntry {
    /// 把日历时段裁剪到某个专注日，跨 4:00 的日程会分别计入相邻两天。
    func clipped(to interval: DateInterval) -> CalendarFocusEntry? {
        let start = max(startDate, interval.start)
        let end = min(endDate, interval.end)
        guard end > start else { return nil }

        let clippedMinutes = Int((end.timeIntervalSince(start) / 60).rounded())
        guard clippedMinutes > 0 else { return nil }
        guard start != startDate || end != endDate else { return self }

        return CalendarFocusEntry(
            id: id,
            startDate: start,
            endDate: end,
            minutes: clippedMinutes,
            categoryID: categoryID,
            categoryName: categoryName
        )
    }
}

/// 某天某个分类的专注合计。
struct CategoryFocusTotal: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let minutes: Int
    let targetMinutes: Int
}

/// 某天的专注合计：App 内完成的记录 + 从日历补充的时段。
struct FocusTotals: Equatable, Sendable {
    var count: Int
    var minutes: Int
    var calendarCount: Int
    var calendarMinutes: Int
    var categories: [CategoryFocusTotal] = []

    static let zero = FocusTotals(count: 0, minutes: 0, calendarCount: 0, calendarMinutes: 0)
}

@MainActor
@Observable
final class CalendarService {
    private let store = EKEventStore()

    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var calendars: [CalendarOption] = []
    var lastError: String?

    var isAuthorized: Bool {
        switch status {
        case .fullAccess, .writeOnly, .authorized: true
        default: false
        }
    }

    var canListCalendars: Bool {
        switch status {
        case .fullAccess, .authorized: true
        default: false
        }
    }

    var statusText: String {
        switch status {
        case .notDetermined: "尚未授权"
        case .restricted: "系统限制了日历访问"
        case .denied: "日历访问被拒绝"
        case .fullAccess: "已获得完整日历权限"
        case .writeOnly: "仅有写入权限（无法选择日历）"
        case .authorized: "已获得日历权限"
        @unknown default: "未知状态"
        }
    }

    func refresh() {
        status = EKEventStore.authorizationStatus(for: .event)
        if canListCalendars {
            loadCalendars()
        }
    }

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            lastError = nil
            if canListCalendars { loadCalendars() }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadCalendars() {
        guard canListCalendars else {
            calendars = []
            return
        }

        calendars = store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .map { CalendarOption(id: $0.calendarIdentifier, title: $0.title, source: $0.source.title) }
            .sorted {
                if $0.source == $1.source { return $0.title < $1.title }
                return $0.source < $1.source
            }
    }

    /// 读取一段时间内的日程，把标题以分类名开头的项目折算成专注时长。
    ///
    /// - 只统计非全天、已完成或正在进行中的日程，进行中的日程只算到当前时刻。
    /// - App 自己写入的专注记录已经在 `SessionHistory` 里，跳过避免重复。
    /// - 标题以分类名开头即计入：`工作`、`工作 · 会议`、`工作：写方案` 都算；
    ///   多个分类都能匹配时取名字最长的那个。
    func focusEntries(
        from start: Date,
        to end: Date,
        categories: [FocusCategory]
    ) -> [CalendarFocusEntry] {
        guard canListCalendars, end > start, !categories.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var seen = Set<String>()
        var entries: [CalendarFocusEntry] = []

        for event in store.events(matching: predicate) {
            guard !event.isAllDay,
                  !isAppGenerated(event),
                  let title = event.title,
                  let category = matchingCategory(for: title, in: categories)
            else { continue }

            let effectiveStart = max(event.startDate, start)
            let effectiveEnd = min(event.endDate, end)
            let minutes = Int((effectiveEnd.timeIntervalSince(effectiveStart) / 60).rounded())
            guard minutes > 0 else { continue }

            // 同一日程可能出现在多个同步日历里，按内容去重。
            let key = [
                event.eventIdentifier ?? "",
                title,
                String(event.startDate.timeIntervalSinceReferenceDate),
                String(event.endDate.timeIntervalSinceReferenceDate),
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { continue }

            entries.append(
                CalendarFocusEntry(
                    id: event.eventIdentifier ?? key,
                    startDate: effectiveStart,
                    endDate: effectiveEnd,
                    minutes: minutes,
                    categoryID: category.id,
                    categoryName: category.displayName
                )
            )
        }

        return entries
    }

    /// 汇总某天的专注：App 内完成的记录 + 日历里以分类名开头的日程。
    ///
    /// 飞书卡片等地方需要和统计页保持一致，所以统一从这里取「今日完成度」。
    /// 专注日以 4:00 为界，跨界的日历时长会按落在当天内的部分计算。
    func focusTotals(
        on date: Date = Date(),
        history: SessionHistory,
        categories: [FocusCategory],
        dailyTargetMinutes: Int,
        now: Date = Date()
    ) -> FocusTotals {
        let interval = FocusDay.interval(containing: date)

        // 多取一天，保证跨 4:00 的日程能按当天区间正确裁剪。
        let fetchStart = FocusDay.start(offsetBy: -1, from: date)
        let entries = focusEntries(
            from: fetchStart,
            to: min(now, interval.end),
            categories: categories
        ).compactMap { $0.clipped(to: interval) }

        let calendarMinutes = entries.reduce(0) { $0 + $1.minutes }
        let appRecords = history.records(on: date)

        return FocusTotals(
            count: appRecords.count + entries.count,
            minutes: appRecords.reduce(0) { $0 + $1.minutes } + calendarMinutes,
            calendarCount: entries.count,
            calendarMinutes: calendarMinutes,
            categories: categoryTotals(
                appRecords: appRecords,
                entries: entries,
                categories: categories,
                dailyTargetMinutes: dailyTargetMinutes
            )
        )
    }

    /// 按分类汇总当天的分钟数，目标分钟数沿用统计页的比例分配规则。
    private func categoryTotals(
        appRecords: [SessionRecord],
        entries: [CalendarFocusEntry],
        categories: [FocusCategory],
        dailyTargetMinutes: Int
    ) -> [CategoryFocusTotal] {
        let totalRatio = categories.reduce(0) { $0 + max(0, $1.ratio) }
        let fallbackShare = 1.0 / Double(max(1, categories.count))

        var buckets: [String: (name: String, minutes: Int, share: Double)] = [:]
        for category in categories {
            let share = totalRatio > 0 ? max(0, category.ratio) / totalRatio : fallbackShare
            buckets["cat-\(category.id)"] = (category.displayName, 0, share)
        }

        func add(categoryID: UUID?, name: String, minutes: Int) {
            let key = categoryID.map { "cat-\($0)" } ?? "other-\(name)"
            if var bucket = buckets[key] {
                bucket.minutes += minutes
                buckets[key] = bucket
            } else {
                buckets[key] = (name, minutes, 0)
            }
        }

        for record in appRecords {
            add(categoryID: record.categoryID, name: record.categoryName, minutes: record.minutes)
        }
        for entry in entries {
            add(categoryID: entry.categoryID, name: entry.categoryName, minutes: entry.minutes)
        }

        return buckets
            .map { key, bucket in
                CategoryFocusTotal(
                    id: key,
                    name: bucket.name,
                    minutes: bucket.minutes,
                    targetMinutes: Int((Double(max(0, dailyTargetMinutes)) * bucket.share).rounded())
                )
            }
            .sorted { lhs, rhs in
                if lhs.targetMinutes == rhs.targetMinutes {
                    return lhs.minutes > rhs.minutes
                }
                return lhs.targetMinutes > rhs.targetMinutes
            }
    }

    /// App 自己写入的日程标题形如「专注 · 分类 · 45 分钟」，备注里有「第 N 个专注」。
    private func isAppGenerated(_ event: EKEvent) -> Bool {
        if let notes = event.notes, notes.contains("个专注 · 完成于") {
            return true
        }
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.hasPrefix("专注 · ")
    }

    private func matchingCategory(for title: String, in categories: [FocusCategory]) -> FocusCategory? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        // 名字长的优先，避免「工作」抢走「工作台」这类更具体的分类。
        for category in categories.sorted(by: { $0.displayName.count > $1.displayName.count }) {
            let name = category.displayName
            if title.range(of: name, options: [.anchored, .caseInsensitive]) != nil {
                return category
            }
        }

        return nil
    }

    @discardableResult
    func writeFocus(start: Date, end: Date, title: String, notes: String, calendarID: String?) -> Bool {
        guard isAuthorized else {
            lastError = "没有日历权限，无法写入。"
            return false
        }

        let target = calendarID.flatMap { store.calendar(withIdentifier: $0) } ?? store.defaultCalendarForNewEvents
        guard let target else {
            lastError = "找不到可写入的日历。"
            return false
        }
        guard target.allowsContentModifications else {
            lastError = "「\(target.title)」是只读日历，请换一个日历。"
            return false
        }

        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = title
        event.startDate = start
        event.endDate = max(end, start.addingTimeInterval(60))
        event.notes = notes
        event.isAllDay = false

        do {
            try store.save(event, span: .thisEvent, commit: true)
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}
