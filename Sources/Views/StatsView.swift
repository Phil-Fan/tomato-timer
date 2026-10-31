import AppKit
import Charts
import Combine
import SwiftUI

struct StatsView: View {
    var settings: AppSettings
    var history: SessionHistory
    var categories: CategoryStore
    var calendar: CalendarService
    /// 每次切回统计页时递增，触发重新读取日历。
    var refreshToken: Int = 0

    @State private var calendarEntries: [CalendarFocusEntry] = []

    private var accent: Color {
        TomatoTheme.focus
    }

    private var target: Int {
        max(1, settings.dailyTargetMinutes)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                todayCard
                weekCard
                categoryCard
            }
            .padding(16)
        }
        .task(id: refreshToken) {
            reloadCalendarEntries()
        }
        .onChange(of: categories.items) { _, _ in
            reloadCalendarEntries()
        }
        .onChange(of: calendar.status) { _, _ in
            reloadCalendarEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadCalendarEntries()
        }
    }

    // MARK: - 今天

    private var todayCard: some View {
        HStack(spacing: 22) {
            ActivityRingsView(rings: rings, size: 176) {
                VStack(spacing: 1) {
                    Text("\(completionPercent)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.numericText())

                    Text("\(todayMinutes)/\(target)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("今天已专注 \(todayMinutes) 分钟，目标 \(target) 分钟，完成 \(completionPercent)%")

            VStack(alignment: .leading, spacing: 5) {
                Text("今天")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(todayMinutes)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("分钟")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text("目标 \(target) 分钟")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if calendarTodayMinutes > 0 {
                    Text("含日历 \(calendarTodayMinutes) 分钟")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                HStack(spacing: 8) {
                    Text("完成 \(completionPercent)%")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(accent)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text("\(history.todayCount) 个专注")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)

                if !rings.isEmpty {
                    ringsBadge
                        .padding(.top, 1)
                }

                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
    }

    /// 每个分类一圈：颜色跟随分类，各自按自己的目标闭合。
    private var rings: [ActivityRing] {
        todayStats.compactMap { stat in
            guard stat.targetMinutes > 0 else { return nil }
            return ActivityRing(
                id: stat.id,
                color: stat.color,
                progress: Double(stat.minutes) / Double(stat.targetMinutes)
            )
        }
    }

    private var closedRingCount: Int {
        rings.filter(\.isClosed).count
    }

    private var ringsBadge: some View {
        let total = rings.count
        let allClosed = total > 0 && closedRingCount == total

        return HStack(spacing: 5) {
            Image(systemName: allClosed ? "checkmark.circle.fill" : "circle.circle")
                .font(.system(size: 10, weight: .bold))

            Text(allClosed ? "全部 \(total) 圈闭合" : "\(closedRingCount)/\(total) 圈闭合")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(allClosed ? accent : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(allClosed ? accent.opacity(0.14) : Color.primary.opacity(0.06))
        )
        .animation(.easeOut(duration: 0.25), value: closedRingCount)
    }

    private var completionPercent: Int {
        Int((Double(todayMinutes) / Double(target) * 100).rounded())
    }

    private var todayMinutes: Int {
        todayStats.reduce(0) { $0 + $1.minutes }
    }

    // MARK: - 7 天

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("最近 7 天")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("合计 \(weekMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Chart(weekDays) { day in
                BarMark(
                    x: .value("日期", day.label),
                    y: .value("分钟", day.minutes)
                )
                .foregroundStyle(day.isToday ? accent : accent.opacity(0.35))
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .font(.caption2)
                                .foregroundStyle(label == "今天" ? accent : Color.secondary)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXScale(domain: weekDays.map(\.label))
            .frame(height: 112)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - 分类

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("今天 · 分类")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("完成度")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 12) {
                ForEach(todayStats) { stat in
                    categoryRow(stat)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func categoryRow(_ stat: CategoryStat) -> some View {
        let progress = goalProgress(stat)
        let closed = stat.targetMinutes > 0 && stat.minutes >= stat.targetMinutes

        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: stat.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(stat.color)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(stat.color.opacity(0.13)))

                Text(stat.name)
                    .font(.callout)

                Spacer(minLength: 6)

                Text(stat.targetMinutes > 0 ? "\(stat.minutes) / \(stat.targetMinutes) 分钟" : "\(stat.minutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(closed ? Color.primary : .secondary)
                    .monospacedDigit()

                Text(stat.targetMinutes > 0 ? percent(progress) : "—")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(closed ? stat.color : .secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)

                Group {
                    if closed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(stat.color)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [stat.color.opacity(0.7), stat.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * progress))
                        .shadow(color: stat.color.opacity(closed ? 0.35 : 0), radius: 3)
                }
            }
            .frame(height: 7)
            .animation(.easeOut(duration: 0.35), value: progress)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            stat.targetMinutes > 0
                ? "\(stat.name) \(stat.minutes) 分钟，目标 \(stat.targetMinutes) 分钟\(closed ? "，已闭合" : "")"
                : "\(stat.name) \(stat.minutes) 分钟，无目标"
        )
    }

    private func goalProgress(_ stat: CategoryStat) -> Double {
        guard stat.targetMinutes > 0 else { return 0 }
        return min(1, Double(stat.minutes) / Double(stat.targetMinutes))
    }

    // MARK: - 数据

    private var todayStats: [CategoryStat] {
        stats(for: records(on: Date()))
    }

    /// App 记录 + 日历补充，7 天趋势和今日统计共用。
    private var combinedRecords: [SessionRecord] {
        history.records + calendarSessionRecords
    }

    private var calendarSessionRecords: [SessionRecord] {
        calendarEntries.map { entry in
            SessionRecord(
                completedAt: entry.startDate,
                minutes: entry.minutes,
                categoryID: entry.categoryID,
                categoryName: entry.categoryName
            )
        }
    }

    private var calendarTodayMinutes: Int {
        calendarEntries.reduce(0) { partial, entry in
            Calendar.current.isDate(entry.startDate, inSameDayAs: Date())
                ? partial + entry.minutes
                : partial
        }
    }

    private func records(on date: Date) -> [SessionRecord] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: date) else { return [] }
        return combinedRecords.filter { interval.contains($0.completedAt) }
    }

    private var weekRecords: [SessionRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        return combinedRecords.filter { $0.completedAt >= start }
    }

    private var weekMinutes: Int {
        weekRecords.reduce(0) { $0 + $1.minutes }
    }

    private var weekDays: [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let minutes = records(on: day).reduce(0) { $0 + $1.minutes }
            let label = offset == 0 ? "今天" : Self.weekdayFormatter.string(from: day)
            return DayStat(id: day, label: label, minutes: minutes, isToday: offset == 0)
        }
    }

    private func reloadCalendarEntries() {
        calendar.refresh()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else {
            calendarEntries = []
            return
        }
        calendarEntries = self.calendar.focusEntries(
            from: start,
            to: Date(),
            categories: categories.items
        )
    }

    private func stats(for records: [SessionRecord]) -> [CategoryStat] {
        let totalRatio = categories.items.reduce(0) { $0 + max(0, $1.ratio) }
        let fallback = 1.0 / Double(max(1, categories.items.count))

        var buckets: [String: Bucket] = [:]
        for category in categories.items {
            let share = totalRatio > 0 ? max(0, category.ratio) / totalRatio : fallback
            buckets["cat-\(category.id)"] = Bucket(
                name: category.displayName,
                symbol: category.symbol,
                color: category.tint,
                minutes: 0,
                targetShare: share
            )
        }

        for record in records {
            let key = record.categoryID.map { "cat-\($0)" } ?? "other-\(record.categoryName)"
            if var bucket = buckets[key] {
                bucket.minutes += record.minutes
                buckets[key] = bucket
            } else {
                buckets[key] = Bucket(
                    name: record.categoryName,
                    symbol: "circle.dashed",
                    color: .gray,
                    minutes: record.minutes,
                    targetShare: 0
                )
            }
        }

        return buckets
            .map { key, bucket in
                CategoryStat(
                    id: key,
                    name: bucket.name,
                    symbol: bucket.symbol,
                    color: bucket.color,
                    minutes: bucket.minutes,
                    targetMinutes: Int((Double(target) * bucket.targetShare).rounded()),
                    targetShare: bucket.targetShare
                )
            }
            .sorted { lhs, rhs in
                if lhs.targetShare == rhs.targetShare {
                    return lhs.minutes > rhs.minutes
                }
                return lhs.targetShare > rhs.targetShare
            }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

// MARK: - 数据类型

private struct CategoryStat: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let color: Color
    let minutes: Int
    let targetMinutes: Int
    let targetShare: Double
}

private struct DayStat: Identifiable {
    let id: Date
    let label: String
    let minutes: Int
    let isToday: Bool
}

private struct Bucket {
    let name: String
    let symbol: String
    let color: Color
    var minutes: Int
    let targetShare: Double
}
