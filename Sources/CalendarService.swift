import EventKit
import Foundation
import Observation

/// 从日历补充的专注时段：标题以分类名开头的日程按分类计入统计。
struct CalendarFocusEntry: Identifiable, Hashable {
    let id: String
    let startDate: Date
    let minutes: Int
    let categoryID: UUID
    let categoryName: String
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
                    minutes: minutes,
                    categoryID: category.id,
                    categoryName: category.displayName
                )
            )
        }

        return entries
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
