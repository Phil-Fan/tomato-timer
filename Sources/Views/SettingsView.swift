import AppKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            TimerSettingsView(settings: model.settings)
                .tabItem { Label("计时", systemImage: "timer") }

            CategorySettingsView(categories: model.categories)
                .tabItem { Label("分类", systemImage: "square.grid.2x2") }

            CalendarSettingsView(settings: model.settings, calendar: model.calendar)
                .tabItem { Label("日历", systemImage: "calendar") }

            GeneralSettingsView(settings: model.settings, stats: model.stats)
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 560, height: 470)
    }
}

// MARK: - 计时

private struct TimerSettingsView: View {
    @Bindable var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Stepper("专注时长：\(settings.focusMinutes) 分钟", value: $settings.focusMinutes, in: 1...120)
                Stepper("短休息：\(settings.shortBreakMinutes) 分钟", value: $settings.shortBreakMinutes, in: 1...60)
                Stepper("长休息：\(settings.longBreakMinutes) 分钟", value: $settings.longBreakMinutes, in: 1...90)
                Stepper("每 \(settings.longBreakEvery) 个番茄后长休息", value: $settings.longBreakEvery, in: 2...12)
            } header: {
                Text("时长")
            } footer: {
                Text("修改时长后，尚未开始的阶段会立即使用新时长。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("自动开始") {
                Toggle("专注结束后自动开始休息", isOn: $settings.autoStartBreaks)
                Toggle("休息结束后自动开始专注", isOn: $settings.autoStartFocus)
            }

            Section("菜单栏") {
                Toggle("在菜单栏显示剩余时间", isOn: $settings.showTimeInMenuBar)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 分类

private struct CategorySettingsView: View {
    @Bindable var categories: CategoryStore

    var body: some View {
        Form {
            Section {
                ForEach($categories.items) { $category in
                    CategoryRow(
                        category: $category,
                        canDelete: categories.items.count > 1,
                        onDelete: { categories.remove(id: category.id) }
                    )
                }

                Button {
                    categories.add()
                } label: {
                    Label("添加分类", systemImage: "plus")
                }
                .disabled(categories.items.count >= 8)
            } header: {
                Text("专注分类")
            } footer: {
                Text("开始番茄时可以从这些分类里选一个，分类名称会写进日历标题。最多 8 个。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CategoryRow: View {
    @Binding var category: FocusCategory
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("", text: $category.emoji)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .frame(width: 30)

            TextField("分类名称", text: $category.name)
                .textFieldStyle(.plain)

            Spacer(minLength: 4)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(canDelete ? Color.secondary : Color.secondary.opacity(0.3))
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .help(canDelete ? "删除这个分类" : "至少保留一个分类")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 日历

private struct CalendarSettingsView: View {
    @Bindable var settings: AppSettings
    var calendar: CalendarService

    var body: some View {
        Form {
            Section {
                Toggle("把完成的专注写入日历", isOn: $settings.writeToCalendar)

                Picker("目标日历", selection: $settings.calendarID) {
                    Text("系统默认日历").tag(String?.none)
                    ForEach(calendar.calendars) { option in
                        Text("\(option.source) · \(option.title)")
                            .tag(Optional(option.id))
                    }
                }
                .disabled(!settings.writeToCalendar || calendar.calendars.isEmpty)

                TextField("日程标题", text: $settings.eventTitleTemplate)
                    .disabled(!settings.writeToCalendar)

                Text("占位符：{category} = 分类，{minutes} = 本次分钟数，{count} = 今日第几个番茄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("写入")
            } footer: {
                Text("只记录完整结束的番茄；重置或跳过的阶段不会写入。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                HStack(spacing: 8) {
                    Image(systemName: calendar.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(calendar.isAuthorized ? Color.green : Color.orange)
                    Text(calendar.statusText)
                    Spacer()
                    Button("刷新") { calendar.refresh() }
                    if calendar.status == .notDetermined {
                        Button("请求访问") {
                            Task { await calendar.requestAccess() }
                        }
                    }
                }

                if calendar.isAuthorized && calendar.calendars.isEmpty {
                    Text("没有找到可写入的日历。请在系统「日历」App 中添加一个账户。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = calendar.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("怎么接上 Google / 飞书") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Google：系统设置 → 互联网账户 → 添加 Google 账户，勾选「日历」。之后这里会出现该账户下的日历。")
                    Text("飞书：飞书 → 日历 → 添加日历 → 添加第三方日历 → 谷歌日历，登录同一个 Google 账号即可看到这些专注记录。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            calendar.refresh()
            if let id = settings.calendarID,
               !calendar.calendars.isEmpty,
               !calendar.calendars.contains(where: { $0.id == id }) {
                settings.calendarID = nil
            }
            if settings.writeToCalendar, calendar.status == .notDetermined {
                Task { await calendar.requestAccess() }
            }
        }
        .onChange(of: settings.writeToCalendar) { _, enabled in
            if enabled, calendar.status == .notDetermined {
                Task { await calendar.requestAccess() }
            }
        }
    }
}

// MARK: - 通用

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    var stats: StatsStore

    var body: some View {
        Form {
            Section("提醒") {
                Toggle("结束时发送系统通知", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await NotificationScheduler.requestAuthorization() }
                        }
                    }
                Toggle("结束时播放提示音", isOn: $settings.playSound)
            }

            Section("今日") {
                LabeledContent("完成番茄") {
                    Text("\(stats.count) 个")
                        .monospacedDigit()
                }
                LabeledContent("专注时长") {
                    Text("\(stats.minutes) 分钟")
                        .monospacedDigit()
                }
                Button("重置今日统计") {
                    stats.resetToday()
                }
            }

            Section {
                Button("退出番茄钟") {
                    NSApp.terminate(nil)
                }
            }
        }
        .formStyle(.grouped)
    }
}
