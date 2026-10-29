import AppKit
import Combine
import SwiftUI
import UserNotifications

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

            CategorySettingsView(
                settings: model.settings,
                categories: model.categories
            )
            .tabItem { Label("分类", systemImage: "square.grid.2x2") }

            CalendarSettingsView(settings: model.settings, calendar: model.calendar)
                .tabItem { Label("日历", systemImage: "calendar") }

            GeneralSettingsView(
                settings: model.settings,
                history: model.history
            )
            .tabItem { Label("通用", systemImage: "gearshape") }
        }
        .frame(width: 640, height: 560)
        .onAppear {
            NSApp.activate()
            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - 通用

private struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings
    var history: SessionHistory

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isTestingWebhook = false
    @State private var webhookMessage: String?
    @State private var webhookFailed = false

    var body: some View {
        Form {
            Section("提醒") {
                Toggle("结束时发送通知并播放提示音", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            Task {
                                _ = await NotificationScheduler.requestAuthorization()
                                await refreshNotificationStatus()
                            }
                        }
                    }

                if settings.notificationsEnabled, notificationStatus != .authorized {
                    HStack {
                        Text(notificationStatus == .denied ? "通知权限已关闭" : "尚未获取通知权限")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("获取权限") {
                            handleNotificationPermission()
                        }
                        .accessibilityLabel("获取通知权限")
                    }
                }
            }

            Section("显示") {
                Toggle("显示桌面悬浮球", isOn: $settings.showFloatingBall)
            }

            Section {
                Toggle("完成后发送飞书卡片", isOn: $settings.feishuWebhookEnabled)

                TextField(
                    "Webhook 地址",
                    text: $settings.feishuWebhookURL,
                    prompt: Text("https://open.feishu.cn/open-apis/bot/v2/hook/...")
                )
                .textFieldStyle(.roundedBorder)
                .disabled(!settings.feishuWebhookEnabled)

                SecureField("签名密钥（可选）", text: $settings.feishuWebhookSecret)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.feishuWebhookEnabled)

                HStack(spacing: 10) {
                    Button("发送测试卡片") {
                        sendTestWebhook()
                    }
                    .disabled(!canTestWebhook)

                    if isTestingWebhook {
                        ProgressView()
                            .controlSize(.small)
                    }

                    if let webhookMessage {
                        Text(webhookMessage)
                            .font(.caption)
                            .foregroundStyle(webhookFailed ? Color.red : Color.secondary)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("飞书")
            } footer: {
                Text("飞书群 → 设置 → 群机器人 → 添加自定义机器人，复制 Webhook 地址；如果机器人开启了签名校验，再填密钥。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await refreshNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshNotificationStatus() }
        }
    }

    private var canTestWebhook: Bool {
        settings.feishuWebhookEnabled
            && !settings.feishuWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isTestingWebhook
    }

    private func sendTestWebhook() {
        let url = settings.feishuWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }

        isTestingWebhook = true
        webhookMessage = nil

        let config = FeishuWebhook.Config(
            webhookURL: url,
            secret: settings.feishuWebhookSecret
        )
        let summary = FeishuWebhook.Summary(
            categoryName: "测试分类",
            minutes: 45,
            todayCount: history.todayCount,
            todayMinutes: history.todayMinutes,
            dailyTargetMinutes: settings.dailyTargetMinutes,
            completedAt: Date(),
            isTest: true
        )

        Task {
            do {
                try await FeishuWebhook.send(config: config, summary: summary)
                webhookMessage = "测试卡片已发送"
                webhookFailed = false
            } catch {
                webhookMessage = error.localizedDescription
                webhookFailed = true
            }
            isTestingWebhook = false
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func handleNotificationPermission() {
        if notificationStatus == .notDetermined {
            Task {
                _ = await NotificationScheduler.requestAuthorization()
                await refreshNotificationStatus()
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 分类

private struct CategorySettingsView: View {
    @Bindable var settings: AppSettings
    @Bindable var categories: CategoryStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text("每天目标")
                    Spacer()
                    TextField("", value: $settings.dailyTargetMinutes, format: .number)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Text("分钟")
                    Stepper("", value: $settings.dailyTargetMinutes, in: 30...720, step: 30)
                        .labelsHidden()
                }
                Text("按下面的百分比分配给各分类，分类右边的分钟数会自动算出来。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("每日目标")
            }

            Section {
                ForEach(categories.items) { category in
                    CategoryRow(
                        categoryID: category.id,
                        store: categories,
                        dailyTargetMinutes: settings.dailyTargetMinutes
                    )
                }

                HStack {
                    Button {
                        categories.add()
                    } label: {
                        Label("添加分类", systemImage: "plus")
                    }
                    .disabled(categories.items.count >= 8)

                    Spacer()

                    if categories.totalPercent != 100 {
                        Button("平均分配") {
                            categories.averageRatios()
                        }
                    }
                }
            } header: {
                Text("目标占比")
            } footer: {
                if categories.totalPercent == 100 {
                    Text("占比合计 100%，每天 \(settings.dailyTargetMinutes) 分钟。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("占比合计 \(categories.totalPercent)%，统计页会按相对比例换算。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CategoryRow: View {
    let categoryID: UUID
    var store: CategoryStore
    let dailyTargetMinutes: Int

    /// 本地草稿：中文输入法拼写过程中不写回模型，避免候选词被重绘打断。
    @State private var draftName = ""
    @FocusState private var isNameFocused: Bool

    private var category: FocusCategory? {
        store.category(id: categoryID)
    }

    private var canDelete: Bool {
        store.items.count > 1
    }

    private var percentBinding: Binding<Int> {
        Binding(
            get: { Int(((store.category(id: categoryID)?.ratio ?? 0) * 100).rounded()) },
            set: { store.updateRatio(id: categoryID, percent: $0) }
        )
    }

    private var targetMinutes: Int {
        Int((Double(max(0, dailyTargetMinutes)) * max(0, category?.ratio ?? 0)).rounded())
    }

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(IconChoice.all) { choice in
                    Button {
                        store.updateSymbol(id: categoryID, symbol: choice.symbol)
                    } label: {
                        Label(choice.name, systemImage: choice.symbol)
                    }
                }
            } label: {
                Image(systemName: category?.symbol ?? "circle.dashed")
                    .font(.system(size: 15))
                    .foregroundStyle(category?.tint ?? .gray)
                    .frame(width: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("选择图标")

            TextField("分类名称", text: $draftName)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit(commitName)
                .onChange(of: isNameFocused) { _, focused in
                    if !focused { commitName() }
                }
                .onChange(of: category?.name) { _, newName in
                    if !isNameFocused { draftName = newName ?? "" }
                }
                .onAppear { draftName = category?.name ?? "" }
                .onDisappear(perform: commitName)

            Spacer(minLength: 12)

            TextField("", value: percentBinding, format: .number)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 52)

            Text("%")
                .foregroundStyle(.secondary)

            Text("≈ \(targetMinutes) 分钟")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)

            Stepper("", value: percentBinding, in: 0...100, step: 5)
                .labelsHidden()
                .controlSize(.small)

            Button(role: .destructive) {
                store.remove(id: categoryID)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(canDelete ? Color.secondary : Color.secondary.opacity(0.3))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .help(canDelete ? "删除这个分类" : "至少保留一个分类")
        }
        .frame(height: 32)
    }

    private func commitName() {
        // 行可能已经被删除：按 ID 查找，找不到就安全返回。
        guard let current = store.category(id: categoryID) else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = current.name
            return
        }
        if trimmed != current.name {
            store.updateName(id: categoryID, name: trimmed)
        }
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
                Text("只记录完整结束的番茄。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("权限") {
                HStack(spacing: 8) {
                    Image(systemName: calendar.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(calendar.isAuthorized ? Color.green : Color.orange)
                    Text(calendar.statusText)
                    Spacer()

                    if !calendar.isAuthorized {
                        Button("获取权限") {
                            handleCalendarPermission()
                        }
                        .accessibilityLabel("获取日历权限")
                    }
                }

                if calendar.isAuthorized && calendar.calendars.isEmpty {
                    Text("没有找到可写入的日历，请先在系统「日历」里添加账户。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = calendar.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendar.refresh()
        }
    }

    private func handleCalendarPermission() {
        switch calendar.status {
        case .notDetermined:
            Task { await calendar.requestAccess() }
        default:
            openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        }
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
