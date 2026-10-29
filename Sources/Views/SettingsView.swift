import AppKit
import SwiftUI

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            StatsView(
                settings: model.settings,
                history: model.history,
                categories: model.categories
            )
            .tabItem { Label("统计", systemImage: "chart.pie") }

            CategorySettingsView(categories: model.categories)
                .tabItem { Label("分类", systemImage: "square.grid.2x2") }

            CalendarSettingsView(settings: model.settings, calendar: model.calendar)
                .tabItem { Label("日历", systemImage: "calendar") }

            GeneralSettingsView(settings: model.settings, history: model.history)
                .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 660, height: 620)
    }
}

// MARK: - 通用（计时 + 提醒 + 显示 + 数据）

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    var history: SessionHistory

    @State private var showClearHistory = false

    var body: some View {
        Form {
            Section {
                Toggle("结束时发送通知并播放提示音", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task { _ = await NotificationScheduler.requestAuthorization() }
                        }
                    }
            } header: {
                Text("提醒")
            } footer: {
                Text("关闭后不再发送系统通知，也不会播放提示音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("显示") {
                Toggle("在菜单栏显示剩余时间", isOn: $settings.showTimeInMenuBar)
                Toggle("显示桌面悬浮球", isOn: $settings.showFloatingBall)
            }

            Section("数据") {
                Button("重置今日统计") {
                    history.resetToday()
                }

                Button("清空全部历史", role: .destructive) {
                    showClearHistory = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "清空全部历史？",
            isPresented: $showClearHistory
        ) {
            Button("清空", role: .destructive) {
                history.clearAll()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有完成记录都会被删除，无法恢复。")
        }
    }
}

// MARK: - 分类

private struct CategorySettingsView: View {
    @Bindable var categories: CategoryStore

    private var totalPercent: Int {
        categories.items.reduce(0) { $0 + Int(($1.ratio * 100).rounded()) }
    }

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

                HStack {
                    Text("目标合计")
                    Spacer()
                    Text("\(totalPercent)%")
                        .monospacedDigit()
                        .foregroundStyle(totalPercent == 100 ? Color.secondary : Color.orange)
                    Button("平均分配") {
                        categories.averageRatios()
                    }
                    .controlSize(.small)
                }
            } header: {
                Text("专注分类")
            } footer: {
                Text("分类名称会写进日历标题；右边的百分比是每天的目标占比。合计不是 100% 时，图表会按相对比例换算。")
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

    private var percentBinding: Binding<Int> {
        Binding(
            get: { Int((category.ratio * 100).rounded()) },
            set: { category.ratio = Double($0) / 100 }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            TextField("", text: $category.emoji)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .multilineTextAlignment(.center)
                .frame(width: 30)

            TextField("分类名称", text: $category.name)
                .textFieldStyle(.plain)

            Spacer(minLength: 8)

            Stepper(value: percentBinding, in: 0...100, step: 5) {
                Text("\(Int((category.ratio * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            .controlSize(.small)
            .fixedSize()

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
            } header: {
                Text("写入")
            } footer: {
                Text("只记录完整结束的番茄，标题会自动带上分类和时长。")
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

            Section("提示") {
                Text("在系统设置 → 互联网账户中添加 Google 账号后，这里会出现该账户下的日历。飞书可以在「添加第三方日历 → 谷歌日历」中查看这些专注记录。")
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
