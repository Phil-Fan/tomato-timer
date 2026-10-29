import AppKit
import SwiftUI

struct PopoverView: View {
    let model: AppModel
    /// 在悬浮球面板里展开时传入，用于一键收成球。
    var onCollapse: (() -> Void)?

    @Environment(\.openSettings) private var openSettings

    @State private var selectedCategoryID: UUID?

    private var engine: TimerEngine { model.engine }
    private var settings: AppSettings { model.settings }
    private var calendar: CalendarService { model.calendar }
    private var categories: CategoryStore { model.categories }

    private var showingStartCard: Bool {
        !engine.hasStarted
    }

    private var tint: Color {
        if let active = engine.activeCategory { return active.tint }
        if showingStartCard, let selected = categories.category(id: selectedCategoryID) {
            return selected.tint
        }
        return TomatoTheme.focus
    }

    /// 默认选中占比最大的分类。
    private var defaultCategoryID: UUID? {
        categories.items
            .max { $0.ratio < $1.ratio }?
            .id
    }

    var body: some View {
        VStack(spacing: 16) {
            if showingStartCard {
                Spacer(minLength: 0)
                startCard
                Spacer(minLength: 0)
            } else {
                header
                Spacer(minLength: 8)
                ring
                Spacer(minLength: 8)
                controls
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .onExitCommand {
            onCollapse?()
        }
        .onAppear {
            calendar.refresh()
            selectedCategoryID = defaultCategoryID
        }
    }

    // MARK: - 开始

    private let chipSpacing: CGFloat = 8
    private let chipMinWidth: CGFloat = 46
    private let chipHeight: CGFloat = 58

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                settingsButton
            }
            .frame(height: 16)

            GeometryReader { proxy in
                let widths = chipWidths(totalWidth: proxy.size.width)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: chipSpacing) {
                        ForEach(Array(categories.items.enumerated()), id: \.element.id) { index, category in
                            categoryChip(category)
                                .frame(width: widths[index])
                        }
                    }
                }
                .defaultScrollAnchor(.center)
            }
            .frame(height: chipHeight)
            .padding(.top, 10)

            Button {
                beginFocus()
            } label: {
                Label("开始专注", systemImage: "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .tint(.red)
            .keyboardShortcut(.defaultAction)
            .disabled(categories.items.isEmpty)
            .padding(.top, 16)
        }
    }

    private var settingsButton: some View {
        Button(action: openSettingsWindow) {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("设置")
        .accessibilityLabel("设置")
    }

    /// 每张分类卡的宽度按目标占比分配。
    private func chipWidths(totalWidth: CGFloat) -> [CGFloat] {
        let items = categories.items
        guard !items.isEmpty else { return [] }

        let usable = max(0, totalWidth - chipSpacing * CGFloat(items.count - 1))
        let weights = items.map { CGFloat(max(0, $0.ratio)) }
        let totalWeight = weights.reduce(0, +)

        var widths: [CGFloat]
        if totalWeight > 0 {
            widths = weights.map { max(chipMinWidth, usable * $0 / totalWeight) }
        } else {
            widths = Array(repeating: max(chipMinWidth, usable / CGFloat(items.count)), count: items.count)
        }

        // 保底宽度会让总和超出可用空间，把多出的部分按各卡超出保底的份额收回。
        let overflow = widths.reduce(0, +) - usable
        if overflow > 0 {
            let excess = widths.map { max(0, $0 - chipMinWidth) }
            let totalExcess = excess.reduce(0, +)
            if totalExcess > 0 {
                widths = zip(widths, excess).map { width, extra in
                    max(chipMinWidth, width - overflow * extra / totalExcess)
                }
            }
        }

        return widths
    }

    private func categoryChip(_ category: FocusCategory) -> some View {
        let selected = category.id == selectedCategoryID

        return Button {
            selectedCategoryID = category.id
        } label: {
            VStack(spacing: 5) {
                Image(systemName: category.symbol)
                    .font(.system(size: 16, weight: .semibold))

                Text(category.displayName)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(selected ? category.tint : Color.secondary)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? category.tint.opacity(0.16) : Color.primary.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? category.tint.opacity(0.9) : Color.primary.opacity(0.06),
                        lineWidth: selected ? 1.5 : 1
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(category.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: selected)
    }

    private func beginFocus() {
        guard let category = categories.category(id: selectedCategoryID) ?? categories.items.first else {
            return
        }
        settings.lastCategoryID = category.id.uuidString
        engine.startFocus(category: category)
        // 开始后立即收成悬浮球，让球上的进度环接管展示。
        onCollapse?()
    }

    // MARK: - 计时

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: engine.menuBarSymbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)

            Text(engine.sessionTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer()

            Text("45 分钟")
                .font(.caption)
                .foregroundStyle(.tertiary)

            settingsButton
                .padding(.leading, 2)
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
                    .font(.system(size: 52, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 196, height: 196)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(engine.sessionTitle)，剩余 \(engine.timeString)")
    }

    private var subtitle: String {
        if engine.isRunning {
            return "专注中"
        }
        if engine.hasStarted {
            return "已暂停"
        }
        return "准备开始"
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
        }
    }

    // MARK: - 设置

    private func openSettingsWindow() {
        onCollapse?()
        NSApp.activate()
        openSettings()
    }
}
