import Charts
import SwiftUI

struct StatsView: View {
    var settings: AppSettings
    var history: SessionHistory
    var categories: CategoryStore

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
    }

    // MARK: - 今天

    private var todayCard: some View {
        HStack(spacing: 24) {
            todayRing

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
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
    }

    private var todayRing: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.12), lineWidth: 16)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.55), accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(0.25), radius: 4)
                .animation(.easeOut(duration: 0.35), value: ringProgress)

            VStack(spacing: 0) {
                Text("\(completionPercent)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 132, height: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天已专注 \(todayMinutes) 分钟，完成 \(completionPercent)%")
    }

    private var ringProgress: Double {
        min(1, Double(todayMinutes) / Double(target))
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

                Text("实际 / 目标")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            VStack(spacing: 10) {
                ForEach(todayStats) { stat in
                    categoryRow(stat)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private func categoryRow(_ stat: CategoryStat) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stat.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(stat.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stat.name)
                        .font(.callout)

                    Spacer(minLength: 4)

                    Text(stat.targetMinutes > 0 ? "\(stat.minutes) / \(stat.targetMinutes) 分钟" : "\(stat.minutes) 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Text("\(percent(stat.actualShare)) / \(percent(stat.targetShare))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .frame(width: 68, alignment: .trailing)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.07))

                        Capsule()
                            .fill(stat.color)
                            .frame(width: max(0, geometry.size.width * stat.actualShare))

                        Rectangle()
                            .fill(Color.primary.opacity(0.5))
                            .frame(width: 1.5, height: 6)
                            .offset(x: geometry.size.width * stat.targetShare - 0.75)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    // MARK: - 数据

    private var todayStats: [CategoryStat] {
        stats(for: history.todayRecords)
    }

    private var weekRecords: [SessionRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        return history.records.filter { $0.completedAt >= start }
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
            let minutes = history.records(on: day).reduce(0) { $0 + $1.minutes }
            let label = offset == 0 ? "今天" : Self.weekdayFormatter.string(from: day)
            return DayStat(id: day, label: label, minutes: minutes, isToday: offset == 0)
        }
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

        let totalMinutes = max(1, buckets.values.reduce(0) { $0 + $1.minutes })

        return buckets
            .map { key, bucket in
                CategoryStat(
                    id: key,
                    name: bucket.name,
                    symbol: bucket.symbol,
                    color: bucket.color,
                    minutes: bucket.minutes,
                    targetMinutes: Int((Double(target) * bucket.targetShare).rounded()),
                    actualShare: Double(bucket.minutes) / Double(totalMinutes),
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
    let actualShare: Double
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
