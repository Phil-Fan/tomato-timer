import AppKit
import Observation
import SwiftUI

// MARK: - 尺寸

enum FloatingLayout {
    static let ballSize: CGFloat = 68
    static let cardWidth: CGFloat = 320
    static let cardHeight: CGFloat = 390
    static let margin: CGFloat = 12
    static let cornerRadius: CGFloat = 24

    static var collapsedSize: NSSize {
        NSSize(width: ballSize + margin * 2, height: ballSize + margin * 2)
    }

    static var expandedSize: NSSize {
        NSSize(width: cardWidth + margin * 2, height: cardHeight + margin * 2)
    }
}

// MARK: - 状态

@MainActor
@Observable
final class FloatingBallState {
    var isExpanded = false
    var isHovering = false
}

// MARK: - 面板

/// 无边框浮动面板：收起时整块面板就是一个可拖拽的球，展开时承载完整界面。
final class FloatingPanel: NSPanel {
    var isExpandedCheck: (() -> Bool)?
    var onCollapsedClick: (() -> Void)?

    private var pendingMouseDown: NSEvent?
    private var didDrag = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        guard isExpandedCheck?() != true else {
            pendingMouseDown = nil
            super.sendEvent(event)
            return
        }

        // 收起状态自己处理事件：轻点展开，拖动走系统的窗口拖拽。
        switch event.type {
        case .leftMouseDown:
            pendingMouseDown = event
            didDrag = false

        case .leftMouseDragged:
            guard let down = pendingMouseDown else {
                super.sendEvent(event)
                return
            }
            let distance = hypot(
                event.locationInWindow.x - down.locationInWindow.x,
                event.locationInWindow.y - down.locationInWindow.y
            )
            if distance > 3 {
                didDrag = true
                pendingMouseDown = nil
                performDrag(with: down)
            }

        case .leftMouseUp:
            let shouldExpand = pendingMouseDown != nil && !didDrag
            pendingMouseDown = nil
            if shouldExpand {
                onCollapsedClick?()
            }

        default:
            super.sendEvent(event)
        }
    }
}

// MARK: - 控制器

@MainActor
final class FloatingBallController: NSObject, NSWindowDelegate {
    private static let positionKey = "TomatoTimer.floatingBallCenter"

    private let model: AppModel
    private let state = FloatingBallState()
    private let panel: FloatingPanel
    private let hostingView: NSHostingView<AnyView>
    private var collapsedFrame: NSRect
    private var idleTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var animationID = 0
    private var isAnimating = false

    init(model: AppModel) {
        self.model = model

        let initialFrame = Self.restoredCollapsedFrame()
        self.collapsedFrame = initialFrame
        self.panel = FloatingPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.hostingView = NSHostingView(rootView: AnyView(EmptyView()))

        super.init()

        configurePanel()
        installRootView()
    }

    // MARK: 展示

    func setVisible(_ visible: Bool) {
        if visible {
            guard !panel.isVisible else { return }
            panel.setFrame(clamped(collapsedFrame, size: FloatingLayout.collapsedSize), display: false)
            panel.orderFrontRegardless()
        } else {
            if state.isExpanded {
                collapse(animated: false)
            }
            panel.orderOut(nil)
        }
    }

    func expand() {
        guard !state.isExpanded, model.settings.showFloatingBall else { return }

        state.isExpanded = true
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        animate(to: expandedFrame(anchoredTo: collapsedFrame))
        noteInteraction()
    }

    func collapse(animated: Bool = true) {
        idleTask?.cancel()
        guard state.isExpanded else { return }

        state.isExpanded = false
        let target = clamped(collapsedFrame, size: FloatingLayout.collapsedSize)
        collapsedFrame = target
        animate(to: target, animated: animated)
    }

    /// 面板内仍有鼠标活动时重新计时，长时间无操作就收回成球。
    func noteInteraction() {
        idleTask?.cancel()
        guard state.isExpanded else { return }

        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    /// 设置里的“显示桌面悬浮球”发生变化时实时生效。
    func observeVisibility() {
        withObservationTracking {
            _ = model.settings.showFloatingBall
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.setVisible(self.model.settings.showFloatingBall)
                self.observeVisibility()
            }
        }
    }

    // MARK: 配置

    private func configurePanel() {
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        panel.isExpandedCheck = { [weak self] in
            self?.state.isExpanded ?? true
        }
        panel.onCollapsedClick = { [weak self] in
            self?.expand()
        }
    }

    private func installRootView() {
        let state = state
        let root = FloatingRootView(
            model: model,
            state: state,
            onExpand: { [weak self] in self?.expand() },
            onCollapse: { [weak self] in self?.collapse() },
            onInteraction: { [weak self] in self?.noteInteraction() }
        )
        hostingView.rootView = AnyView(root)
        hostingView.frame = panel.contentLayoutRect
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    // MARK: 几何

    private func expandedFrame(anchoredTo collapsed: NSRect) -> NSRect {
        let size = FloatingLayout.expandedSize
        let frame = NSRect(
            x: collapsed.maxX - size.width,
            y: collapsed.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return clamped(frame, size: size, around: collapsed)
    }

    /// 保证面板完整落在球所在屏幕的可见区域里。
    private func clamped(_ frame: NSRect, size: NSSize, around anchor: NSRect? = nil) -> NSRect {
        let point = NSPoint(
            x: (anchor ?? frame).midX,
            y: (anchor ?? frame).midY
        )
        guard let visible = screen(containing: point)?.visibleFrame else { return frame }

        let inset: CGFloat = 6
        var result = frame
        let minX = visible.minX + inset
        let maxX = max(minX, visible.maxX - size.width - inset)
        let minY = visible.minY + inset
        let maxY = max(minY, visible.maxY - size.height - inset)

        result.origin.x = min(max(frame.origin.x, minX), maxX)
        result.origin.y = min(max(frame.origin.y, minY), maxY)
        return result
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func animate(to frame: NSRect, animated: Bool = true) {
        animationID += 1
        let currentAnimation = animationID
        isAnimating = true

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.26
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }

        Task { @MainActor [weak self] in
            if animated {
                try? await Task.sleep(for: .milliseconds(320))
            }
            guard let self, self.animationID == currentAnimation else { return }
            self.isAnimating = false
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAnimating, !state.isExpanded else { return }
        collapsedFrame = panel.frame
        schedulePositionSave()
    }

    private func schedulePositionSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.savePosition()
        }
    }

    private func savePosition() {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        UserDefaults.standard.set([Double(center.x), Double(center.y)], forKey: Self.positionKey)
    }

    private static func restoredCollapsedFrame() -> NSRect {
        let size = FloatingLayout.collapsedSize
        let stored = UserDefaults.standard.array(forKey: positionKey) as? [Double]

        var center: NSPoint
        if let stored, stored.count == 2 {
            center = NSPoint(x: stored[0], y: stored[1])
        } else if let visible = NSScreen.main?.visibleFrame {
            center = NSPoint(
                x: visible.maxX - 28 - size.width / 2,
                y: visible.maxY - 28 - size.height / 2
            )
        } else {
            center = NSPoint(x: 800, y: 700)
        }

        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let minX = visible.minX + 6 + size.width / 2
            let maxX = visible.maxX - 6 - size.width / 2
            let minY = visible.minY + 6 + size.height / 2
            let maxY = visible.maxY - 6 - size.height / 2
            center.x = min(max(center.x, minX), maxX)
            center.y = min(max(center.y, minY), maxY)
        }

        return NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}

// MARK: - 根视图

struct FloatingRootView: View {
    let model: AppModel
    let state: FloatingBallState
    let onExpand: () -> Void
    let onCollapse: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if state.isExpanded {
                expandedCard
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .topTrailing)))
            } else {
                FloatingBallView(model: model, isHovering: state.isHovering)
                    .onHover { hovering in
                        state.isHovering = hovering
                        if hovering { onInteraction() }
                    }
                    .padding(FloatingLayout.margin)
                    .transition(.opacity.combined(with: .scale(scale: 0.86, anchor: .topTrailing)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: state.isExpanded)
    }

    private var expandedCard: some View {
        PopoverView(model: model, onCollapse: onCollapse)
            .frame(width: FloatingLayout.cardWidth, height: FloatingLayout.cardHeight)
            .background {
                RoundedRectangle(cornerRadius: FloatingLayout.cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: FloatingLayout.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: FloatingLayout.cornerRadius, style: .continuous)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
            .padding(FloatingLayout.margin)
            .onContinuousHover { _ in
                onInteraction()
            }
            .onExitCommand {
                onCollapse()
            }
    }
}

// MARK: - 悬浮球

struct FloatingBallView: View {
    let model: AppModel
    let isHovering: Bool

    private var engine: TimerEngine { model.engine }

    private var tint: Color {
        engine.activeCategory?.tint ?? TomatoTheme.focus
    }

    private var statusText: String {
        return engine.isRunning ? "专注" : "暂停"
    }

    private var accessibilityLabel: String {
        if engine.isRunning || engine.hasStarted {
            return "番茄钟，\(statusText)，剩余 \(engine.timeString)"
        }
        return "番茄钟，点击展开"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.98), tint.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

            Circle()
                .trim(from: 0, to: engine.progress)
                .stroke(
                    Color.white.opacity(0.92),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(5)
                .animation(.easeOut(duration: 0.2), value: engine.progress)

            content
        }
        .frame(width: FloatingLayout.ballSize, height: FloatingLayout.ballSize)
        .shadow(color: tint.opacity(0.42), radius: isHovering ? 14 : 9, y: 4)
        .scaleEffect(isHovering ? 1.06 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
        .help("点击展开 · 拖动移动")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        if engine.isRunning || engine.hasStarted {
            VStack(spacing: 1) {
                Text(engine.timeString)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(statusText)
                    .font(.system(size: 8, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
        } else {
            Text(engine.sessionEmoji)
                .font(.system(size: 28))
        }
    }
}
