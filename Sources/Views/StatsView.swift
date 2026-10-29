import Charts
import SwiftUI

struct StatsView: View {
    @Bindable var settings: AppSettings
    var history: SessionHistory
    var categories: CategoryStore

    private var target: Int {
        max(1, settings.dailyTargetMinutes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                targetHeader

                GroupBox {
                    todaySection
                        .padding(.top, 4)
                } label: {
                    Label("今天", systemImage: "sun.max")
                        .font(.headline)
                }

                GroupBox {
                    weekSection
                        .padding(.top, 4)
                } label: {
                    Label("最近 7 天", systemImage: "calendar")
                        .font(.headline)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 每日目标

    private var targetHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("每日目标", systemImage: "target")
                    .font(.headline)
                Spacer()
                Stepper(
                    value: $settings.dailyTargetMinutes,
                    in: 30...720,
                    step: 30
                ) {
                    Text("\(settings.dailyTargetMinutes) 分钟")
                        .monospacedDigit()
                }
                .fixedSize()
            }

            HStack {
                Text("今日已专注 \(todayMinutes) 分钟")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(completionPercent)%")
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(todayMinutes >= target ? Color.green : Color.secondary)
            }

            ProgressView(
                value: Double(min(todayMinutes, target)),
                total: Double(target)
            )
            .tint(todayMinutes >= target ? .green : .accentColor)

            Text("每天固定目标 \(target) 分钟，所有分类的比例都按这个总量换算。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var completionPercent: Int {
        Int((Double(todayMinutes) / Double(target) * 100).rounded())
    }

    // MARK: - 今天

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                todayDonut

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("分类")
                        Spacer()
                        Text("实际 / 目标")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    ForEach(todayStats) { stat in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(stat.color)
                                .frame(width: 7, height: 7)

                            Text("\(stat.emoji) \(stat.name)")
                                .font(.callout)
                                .lineLimit(1)

                            Spacer(minLength: 8)

                            Text("\(stat.minutes) 分钟")
                                .font(.callout)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            Text("\(percent(stat.actualShare)) / \(percent(stat.targetShare))")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var todayDonut: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 16)

            if todayMinutes > 0 {
                Chart(todayStats.filter { $0.minutes > 0 }) { stat in
                    SectorMark(
                        angle: .value("分钟", stat.minutes),
                        innerRadius: .ratio(0.64),
                        angularInset: 2
                    )
                    .cornerRadius(3)
                    .foregroundStyle(stat.color)
                }
                .chartLegend(.hidden)
            }

            VStack(spacing: 1) {
                Text("\(todayMinutes)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("分钟")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150, height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天已专注 \(todayMinutes) 分钟，目标 \(target) 分钟")
    }

    // MARK: - 7 天

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("每天专注")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("7 天合计 \(weekMinutes) / \(target * 7) 分钟")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                dailyChart
                    .frame(height: 150)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("分类实际 vs 目标")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("彩色 = 实际 · 灰色 = 目标")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                categoryChart
                    .frame(height: max(110, Double(weekStats.count) * 30))
            }
        }
    }

    private var dailyChart: some View {
        Chart {
            ForEach(weekDays) { day in
                ForEach(day.points) { point in
                    BarMark(
                        x: .value("日期", day.label),
                        y: .value("分钟", point.minutes)
                    )
                    .foregroundStyle(point.color)
                    .cornerRadius(2)
                }
            }

            RuleMark(y: .value("每日目标", target))
                .foregroundStyle(.secondary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartXScale(domain: weekDays.map(\.label))
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartLegend(.hidden)
    }

    private var categoryChart: some View {
        Chart {
            ForEach(weekStats) { stat in
                BarMark(
                    x: .value("分钟", stat.minutes),
                    y: .value("分类", "\(stat.emoji) \(stat.name)")
                )
                .foregroundStyle(stat.color)
                .cornerRadius(2)
                .position(by: .value("类型", "实际"))

                BarMark(
                    x: .value("分钟", weekTarget(for: stat)),
                    y: .value("分类", "\(stat.emoji) \(stat.name)")
                )
                .foregroundStyle(Color.secondary.opacity(0.22))
                .cornerRadius(2)
                .position(by: .value("类型", "目标"))
            }
        }
        .chartXAxis {
            AxisMarks(position: .bottom)
        }
        .chartLegend(.hidden)
    }

    // MARK: - 数据

    private var todayStats: [CategoryStat] {
        stats(for: history.todayRecords)
    }

    private var todayMinutes: Int {
        todayStats.reduce(0) { $0 + $1.minutes }
    }

    private var weekRecords: [SessionRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return [] }
        return history.records.filter { $0.completedAt >= start }
    }

    private var weekStats: [CategoryStat] {
        stats(for: weekRecords)
    }

    private var weekMinutes: Int {
        weekStats.reduce(0) { $0 + $1.minutes }
    }

    private var weekDays: [DayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let stats = stats(for: history.records(on: day))
            let label = offset == 0 ? "今天" : Self.weekdayFormatter.string(from: day)
            let points = stats
                .filter { $0.minutes > 0 }
                .map {
                    DayPoint(
                        id: "\(day.timeIntervalSince1970)-\($0.id)",
                        category: $0.name,
                        color: $0.color,
                        minutes: $0.minutes
                    )
                }
            return DayStat(id: day, label: label, points: points)
        }
    }

    private func stats(for records: [SessionRecord]) -> [CategoryStat] {
        let totalRatio = categories.items.reduce(0) { $0 + max(0, $1.ratio) }
        let fallback = 1.0 / Double(max(1, categories.items.count))

        var buckets: [String: Bucket] = [:]
        for category in categories.items {
            let share = totalRatio > 0 ? max(0, category.ratio) / totalRatio : fallback
            buckets["cat-\(category.id)"] = Bucket(
                name: category.name,
                emoji: category.emoji,
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
                    emoji: record.emoji,
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
                    emoji: bucket.emoji,
                    color: bucket.color,
                    minutes: bucket.minutes,
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

    private func weekTarget(for stat: CategoryStat) -> Int {
        Int((Double(settings.dailyTargetMinutes) * 7 * stat.targetShare).rounded())
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
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
    let emoji: String
    let color: Color
    let minutes: Int
    let actualShare: Double
    let targetShare: Double
}

private struct DayStat: Identifiable {
    let id: Date
    let label: String
    let points: [DayPoint]
}

private struct DayPoint: Identifiable {
    let id: String
    let category: String
    let color: Color
    let minutes: Int
}

private struct Bucket {
    let name: String
    let emoji: String
    let color: Color
    var minutes: Int
    let targetShare: Double
}
