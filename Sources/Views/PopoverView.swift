import AppKit
import SwiftUI

struct PopoverView: View {
    let model: AppModel

    @Environment(\.openSettings) private var openSettings

    @State private var selectedCategoryID: UUID?
    @State private var selectedMinutes = 25

    private var engine: TimerEngine { model.engine }
    private var settings: AppSettings { model.settings }
    private var stats: StatsStore { model.stats }
    private var calendar: CalendarService { model.calendar }
    private var categories: CategoryStore { model.categories }

    private var showingStartCard: Bool {
        engine.phase == .focus && !engine.hasStarted
    }

    private var tint: Color {
        if let active = engine.activeCategory { return active.tint }
        if showingStartCard, let selected = categories.category(id: selectedCategoryID) {
            return selected.tint
        }
        return engine.phase.tint
    }

    private var durationOptions: [Int] {
        var options = [15, 25, 45, 60]
        if !options.contains(settings.focusMinutes) {
            options.append(settings.focusMinutes)
        }
        if !options.contains(selectedMinutes) {
            options.append(selectedMinutes)
        }
        return options.sorted()
    }

    var body: some View {
        VStack(spacing: 16) {
            if showingStartCard {
                startCard
            } else {
                header
                ring
                controls
            }

            Divider()

            footer
        }
        .padding(18)
        .frame(width: 320)
        .onAppear {
            stats.refresh()
            calendar.refresh()

            if selectedCategoryID == nil {
                selectedCategoryID = categories.category(rawID: settings.lastCategoryID)?.id
                    ?? categories.items.first?.id
            }
            selectedMinutes = min(120, max(5, settings.lastFocusMinutes))
        }
    }

    // MARK: - 开始

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("开始专注")
                    .font(.title3.weight(.semibold))
                Text("今日已完成 \(stats.count) 个番茄")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("分类")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("分类", selection: $selectedCategoryID) {
                    ForEach(categories.items) { category in
                        Text("\(category.emoji)  \(category.name)")
                            .tag(Optional(category.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("时长（分钟）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("时长", selection: $selectedMinutes) {
                    ForEach(durationOptions, id: \.self) { minutes in
                        Text("\(minutes)")
                            .tag(minutes)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            Button {
                beginFocus()
            } label: {
                Label("开始专注", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(tint)
            .keyboardShortcut(.defaultAction)
            .disabled(categories.items.isEmpty)
        }
    }

    private func beginFocus() {
        guard let category = categories.category(id: selectedCategoryID) ?? categories.items.first else {
            return
        }
        settings.lastCategoryID = category.id.uuidString
        settings.lastFocusMinutes = selectedMinutes
        engine.startFocus(minutes: selectedMinutes, category: category)
    }

    // MARK: - 计时

    private var header: some View {
        HStack(spacing: 8) {
            Text(engine.sessionTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 4) {
                ForEach(0..<max(1, min(8, settings.longBreakEvery)), id: \.self) { index in
                    Circle()
                        .fill(index < engine.cycleDots ? tint : Color.primary.opacity(0.12))
                        .frame(width: 5, height: 5)
                }
            }
            .help("本轮已完成 \(engine.cycleDots) / \(settings.longBreakEvery) 个番茄")
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 10)

            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: engine.progress)

            VStack(spacing: 2) {
                Text(engine.timeString)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 180, height: 180)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(engine.sessionTitle)，剩余 \(engine.timeString)")
    }

    private var subtitle: String {
        if engine.isRunning {
            return engine.phase == .focus ? "专注中" : "休息中"
        }
        if engine.hasStarted {
            return "已暂停"
        }
        return engine.phase == .focus ? "准备开始" : "开始休息"
    }

    private var controls: some View {
        HStack(spacing: 32) {
            Button {
                engine.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .buttonStyle(.borderless)
            .help("重置")

            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            .tint(tint)
            .keyboardShortcut(.space, modifiers: [])
            .help(engine.isRunning ? "暂停" : "开始")

            Button {
                engine.skip()
            } label: {
                Image(systemName: "forward.end")
            }
            .buttonStyle(.borderless)
            .help("跳过，不计入统计")
        }
    }

    // MARK: - 底栏

    private var footer: some View {
        HStack(spacing: 10) {
            Text("今日 \(stats.count) 个 · \(stats.minutes) 分钟")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .help("今日完成的番茄数与专注分钟数")

            Spacer()

            if settings.writeToCalendar {
                Image(systemName: calendar.isAuthorized ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(calendar.isAuthorized ? Color.secondary : Color.orange)
                    .help(calendar.isAuthorized ? "完成的番茄会写入日历" : "日历未授权，请在设置里处理")
            }

            Button(action: openSettingsWindow) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("设置")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出番茄钟")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
