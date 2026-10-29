import EventKit
import Foundation
import Observation

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
