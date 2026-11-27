import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// HUD 的视图。只认 `HudCard`，不认任何业务类型：换一个功能推卡片，外观不变。
struct HudPanelView: View {
    let card: HudCard?
    let lastCard: HudCard?
    let sessionCount: Int
    let mode: HudMode
    let isRemoteConnected: Bool
    let strings: HudStrings?
    let isCopied: Bool
    let onAction: (HudAction) -> Void
    let onCopy: () -> Void
    let onClose: () -> Void
    let onHover: (Bool) -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }

    private var isFailure: Bool { card?.tone == .failure }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusRow
            if let active = card {
                divider
                if active.tone == .failure {
                    failureBody(active)
                } else {
                    detailRow(
                        title: active.title,
                        elapsed: active.elapsedMilliseconds ?? 0,
                        live: true
                    )
                }
            } else if let last = lastCard {
                divider
                detailRow(
                    title: last.title,
                    elapsed: last.elapsedMilliseconds ?? 0,
                    live: false
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: HudLayout.width, alignment: .leading)
        // 用纯色半透明而不是 .ultraThinMaterial：材质每帧都要重算背板模糊，
        // 拖动时窗口跟着指针走就会掉帧；纯色填充由窗口服务器直接合成。
        .background(shape.fill(Color.black.opacity(0.62)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .contentShape(shape)
        // 整块可拖：点击（<2pt）仍交给下面的按钮。
        // 位移必须用 .global：面板本身跟着指针移动，.local 的 translation 会跟着
        // 窗口原点一起漂移，每帧互相抵消，拖动就像被橡皮筋拽住。
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { onDrag($0.translation) }
                .onEnded { _ in onDragEnd() }
        )
        .onHover(perform: onHover)
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 8)
            if let modeText {
                Text(modeText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(modeColor)
                    .lineLimit(1)
            }
            if let countText {
                Text(countText)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private func detailRow(title: String, elapsed: Int, live: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: live ? .medium : .regular))
                .foregroundStyle(live ? Color.white.opacity(0.95) : Color.white.opacity(0.62))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(elapsedText(elapsed))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private func failureBody(_ active: HudCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(active.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(elapsedText(active.elapsedMilliseconds ?? 0))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(active.closeLabel)
            }
            if let context = active.context {
                Text(context)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = active.detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if active.primaryAction != nil || active.secondaryAction != nil {
                HStack(spacing: 8) {
                    if let action = active.primaryAction {
                        hudButton(action.title, prominent: action.isProminent) {
                            onAction(action)
                        }
                    }
                    if let action = active.secondaryAction {
                        hudButton(
                            isCopied ? (active.secondaryTitleWhenCopied ?? action.title) : action.title,
                            prominent: false,
                            action: onCopy
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func hudButton(
        _ title: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.white.opacity(0.88))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        prominent
                            ? Color.accentColor.opacity(0.9)
                            : Color.white.opacity(0.16)
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        let template = isFailure ? strings?.attentionStatus : strings?.idleStatus
        return template ?? "—"
    }

    private var statusColor: Color {
        if isFailure { return .red }
        return isRemoteConnected ? .green : Color.white.opacity(0.42)
    }

    private var modeText: String? {
        guard let strings else { return nil }
        return mode == .mouse ? strings.modeMouse : strings.modeKeyboard
    }

    /// 模式用颜色区分：键盘模式蓝、鼠标模式橙。
    private var modeColor: Color {
        mode == .mouse
            ? Color(red: 1.0, green: 0.62, blue: 0.29)
            : Color(red: 0.45, green: 0.69, blue: 1.0)
    }

    private var countText: String? {
        guard sessionCount > 0, let strings else { return nil }
        return strings.format(strings.sessionCountFormat, String(sessionCount))
    }

    private func elapsedText(_ milliseconds: Int) -> String {
        guard milliseconds >= 1000 else { return "\(max(milliseconds, 0))ms" }
        return String(format: "%.1fs", Double(milliseconds) / 1000)
    }
}

/// 只观察 `HudCenter` 并维护真实浮层；不持有业务状态，也不认识动作反馈。
@MainActor
final class HudPanelCoordinator {
    private let center: HudCenter
    private let placementStore: HudPlacementStore
    private var panel: HudPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellable: AnyCancellable?
    private var loggedRenderKey: String?
    private var dragOrigin: CGPoint?
    private var usedStoredPlacement = false
    private var isHovering = false
    private var isDragging = false
    /// 上次真正重建内容的输入指纹：相同就跳过重建，拖动时尤其需要。
    private var renderedSignature: String?
    /// 拖动期间到达的状态变化，松手后再统一渲染。
    private var pendingRender: RenderInput?
    /// 拖动时顶替 SwiftUI 内容的位图快照。
    private var dragSnapshot: NSImageView?
    /// 拖动期间自己接管鼠标事件，不再依赖 SwiftUI 手势回调。
    private var dragMonitor: Any?
    private var dragStartMouse: CGPoint?

    private struct RenderInput {
        let card: HudCard?
        let lastCard: HudCard?
        let sessionCount: Int
        let isEnabled: Bool
        let copiedID: UUID?
        let mode: HudMode
        let isRemoteConnected: Bool
    }

    /// 内容指纹：只看会影响渲染的标识，相同就不重建 SwiftUI 树。
    private static func signature(
        card: HudCard?,
        lastCard: HudCard?,
        sessionCount: Int,
        copiedID: UUID?,
        mode: HudMode,
        isRemoteConnected: Bool
    ) -> String {
        [
            String(sessionCount),
            card?.id.uuidString ?? "idle",
            lastCard?.id.uuidString ?? "none",
            copiedID?.uuidString ?? "",
            mode == .mouse ? "mouse" : "keyboard",
            isRemoteConnected ? "connected" : "offline",
        ].joined(separator: "|")
    }

    init(
        center: HudCenter? = nil,
        placementStore: HudPlacementStore = HudPlacementStore()
    ) {
        self.center = center ?? .shared
        self.placementStore = placementStore
    }

    func start() {
        guard cancellable == nil else { return }
        cancellable = Publishers.CombineLatest4(
            center.$card,
            center.$lastCard,
            center.$sessionCount,
            center.$isEnabled
        )
        .combineLatest(center.$copiedCardID, center.$mode, center.$isRemoteConnected)
        .receive(on: RunLoop.main)
        .sink { [weak self] state, copiedID, mode, isRemoteConnected in
            self?.render(
                state.0,
                lastCard: state.1,
                sessionCount: state.2,
                isEnabled: state.3,
                copiedID: copiedID,
                mode: mode,
                isRemoteConnected: isRemoteConnected
            )
        }
    }

    func stop() {
        cancellable?.cancel()
        cancellable = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        hostingView = nil
    }

    /// HUD 常显：开关打开就一直挂着；没有卡片时只显示状态行和最近一条。
    private func render(
        _ card: HudCard?,
        lastCard: HudCard?,
        sessionCount: Int,
        isEnabled: Bool,
        copiedID: UUID?,
        mode: HudMode,
        isRemoteConnected: Bool
    ) {
        guard isEnabled else {
            hidePanel()
            return
        }
        guard let screen = HudScreenResolver.preferredScreen() else { return }
        // 拖动期间内容冻结成位图：只移动窗口，松手后再补一次正式渲染。
        if dragSnapshot != nil {
            pendingRender = RenderInput(
                card: card,
                lastCard: lastCard,
                sessionCount: sessionCount,
                isEnabled: isEnabled,
                copiedID: copiedID,
                mode: mode,
                isRemoteConnected: isRemoteConnected
            )
            return
        }
        let signature = Self.signature(
            card: card,
            lastCard: lastCard,
            sessionCount: sessionCount,
            copiedID: copiedID,
            mode: mode,
            isRemoteConnected: isRemoteConnected
        )
        // 指纹没变就什么都不做，避免重复重建 SwiftUI 树和重新测尺寸。
        if signature == renderedSignature, panel?.isVisible == true {
            return
        }
        let host = ensureHostingView()
        let view = HudPanelView(
            card: card,
            lastCard: lastCard,
            sessionCount: sessionCount,
            mode: mode,
            isRemoteConnected: isRemoteConnected,
            strings: center.strings,
            isCopied: card != nil && copiedID == card?.id,
            onAction: { action in action.perform() },
            onCopy: { [weak self] in self?.center.requestCopy(for: card) },
            onClose: { [weak self] in self?.center.requestClose(for: card) },
            onHover: { [weak self] hovering in self?.setHovering(hovering) },
            onDrag: { [weak self] translation in self?.handleDrag(translation) },
            onDragEnd: { [weak self] in self?.finishDrag() }
        )
        host.rootView = AnyView(view)
        host.layoutSubtreeIfNeeded()
        var size = host.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: HudLayout.width, height: 64)
        }
        // 固定宽度，空闲态和失败态之间左右不跳动。
        size.width = HudLayout.width
        size.height = max(size.height, 1)
        let panel = ensurePanel()
        panel.setContentSize(size)
        let origin = placementOrigin(panelSize: size, screen: screen)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
        host.frame = NSRect(origin: .zero, size: size)
        renderedSignature = signature
        panel.orderFrontRegardless()
        let renderKey = "\(sessionCount)-\(card?.id.uuidString ?? "idle")-\(copiedID?.uuidString ?? "")"
        if loggedRenderKey != renderKey {
            loggedRenderKey = renderKey
            let toneName = card.map { "\($0.tone)" } ?? "idle"
            AppLogger.shared.write(
                "HUD panel phase=shown tone=\(toneName) cards=\(sessionCount) " +
                    "width=\(Int(size.width)) height=\(Int(size.height)) " +
                    "x=\(Int(origin.x)) y=\(Int(origin.y)) " +
                    "placement=\(usedStoredPlacement ? "stored" : "default") " +
                    "window_number=\(panel.windowNumber) " +
                    "screen_width=\(Int(screen.visibleFrame.width)) " +
                    "screen_height=\(Int(screen.visibleFrame.height)) " +
                    "ignores_mouse=false"
            )
        }
        if let card,
           card.announces,
           let announcement = card.accessibilityAnnouncement,
           let contentView = panel.contentView {
            let userInfo: [NSAccessibility.NotificationUserInfoKey: Any] = [
                .announcement: announcement,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
            NSAccessibility.post(
                element: contentView,
                notification: .announcementRequested,
                userInfo: userInfo
            )
        }
    }

    private func hidePanel() {
        endDragSession()
        setHovering(false)
        panel?.orderOut(nil)
        renderedSignature = nil
        if loggedRenderKey != nil {
            loggedRenderKey = nil
            AppLogger.shared.write("HUD panel phase=hidden")
        }
    }

    private func ensureHostingView() -> NSHostingView<AnyView> {
        if let hostingView { return hostingView }
        let host = NSHostingView(rootView: AnyView(EmptyView()))
        host.autoresizingMask = [.width, .height]
        // 材质与阴影走图层合成，拖动时窗口只需移动图层，不必重绘内容。
        host.wantsLayer = true
        hostingView = host
        return host
    }

    private func ensurePanel() -> HudPanel {
        if let panel { return panel }
        let panel = HudPanel(
            contentRect: NSRect(x: 0, y: 0, width: HudLayout.width, height: 70),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // .floating 低于 Dock（20）和菜单栏（24），面板会被压住；HUD 需要盖住
        // Dock、菜单栏和其他 App 的全屏窗口，因此固定在 .screenSaver。
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        // 拖动由 SwiftUI 手势驱动，不用系统的窗口背景拖动，避免和按钮点击抢事件。
        panel.isMovable = false
        panel.contentView = ensureHostingView()
        self.panel = panel
        return panel
    }

    /// 记住过就按记忆位置还原，没记住过就用默认落点。
    private func placementOrigin(panelSize: CGSize, screen: NSScreen) -> CGPoint {
        if let displayID = screen.hudDisplayID,
           let saved = placementStore.placement(displayID: displayID) {
            usedStoredPlacement = true
            return HudLayout.origin(
                normalizedX: saved.normalizedX,
                normalizedY: saved.normalizedY,
                panelSize: panelSize,
                visibleFrame: screen.visibleFrame
            )
        }
        usedStoredPlacement = false
        return HudLayout.origin(visibleFrame: screen.visibleFrame, panelSize: panelSize)
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        center.setInteracting(isHovering || isDragging)
    }

    private func setDragging(_ dragging: Bool) {
        guard dragging != isDragging else { return }
        isDragging = dragging
        center.setInteracting(isHovering || isDragging)
    }

    /// 第一次位移回调把内容换成位图快照，之后由本地事件监视器接管。
    /// 拖动期间应用侧只做一件事：移动窗口，不再重建 SwiftUI 内容。
    private func handleDrag(_ translation: CGSize) {
        guard let panel else { return }
        beginDragSession(panel: panel)
    }

    private func beginDragSession(panel: HudPanel) {
        guard dragOrigin == nil else { return }
        dragOrigin = panel.frame.origin
        dragStartMouse = NSEvent.mouseLocation
        setDragging(true)
        installDragSnapshot(panel: panel)
        // 快照顶替内容后 SwiftUI 的手势会被拆掉，后续位移改由事件监视器提供。
        dragMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseUp {
                self.endDragSession()
                return event
            }
            self.moveDraggedPanel()
            return nil
        }
    }

    private func moveDraggedPanel() {
        guard let panel,
              let start = dragOrigin,
              let startMouse = dragStartMouse,
              let visibleFrame = panel.screen?.visibleFrame
        else { return }
        let current = NSEvent.mouseLocation
        let target = HudLayout.clampedOrigin(
            CGPoint(
                x: start.x + current.x - startMouse.x,
                y: start.y + current.y - startMouse.y
            ),
            panelSize: panel.frame.size,
            visibleFrame: visibleFrame
        )
        guard target != panel.frame.origin else { return }
        panel.setFrameOrigin(target)
    }

    private func installDragSnapshot(panel: HudPanel) {
        let host = ensureHostingView()
        let bounds = host.bounds
        guard bounds.width >= 1, bounds.height >= 1,
              let rep = host.bitmapImageRepForCachingDisplay(in: bounds)
        else { return }
        host.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        let view = NSImageView(frame: NSRect(origin: .zero, size: bounds.size))
        view.image = image
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        panel.contentView = view
        dragSnapshot = view
    }

    /// 松手：恢复 SwiftUI 内容、写回位置，再把拖动期间攒下的状态渲染一次。
    private func endDragSession() {
        guard dragOrigin != nil || dragSnapshot != nil else { return }
        if let monitor = dragMonitor {
            NSEvent.removeMonitor(monitor)
            dragMonitor = nil
        }
        dragStartMouse = nil
        dragOrigin = nil
        if dragSnapshot != nil {
            dragSnapshot = nil
            let host = ensureHostingView()
            panel?.contentView = host
            if let panel {
                host.frame = NSRect(origin: .zero, size: panel.frame.size)
            }
        }
        setDragging(false)
        renderedSignature = nil
        if let panel, panel.isVisible {
            savePlacement(panel: panel)
        }
        if let pending = pendingRender {
            pendingRender = nil
            render(
                pending.card,
                lastCard: pending.lastCard,
                sessionCount: pending.sessionCount,
                isEnabled: pending.isEnabled,
                copiedID: pending.copiedID,
                mode: pending.mode,
                isRemoteConnected: pending.isRemoteConnected
            )
        }
    }

    private func finishDrag() {
        endDragSession()
    }

    private func savePlacement(panel: HudPanel) {
        guard let screen = panel.screen,
              let displayID = screen.hudDisplayID
        else { return }
        let normalized = HudLayout.normalizedOrigin(
            origin: panel.frame.origin,
            panelSize: panel.frame.size,
            visibleFrame: screen.visibleFrame
        )
        placementStore.save(
            HudPlacement(
                normalizedX: Double(normalized.x),
                normalizedY: Double(normalized.y)
            ),
            displayID: displayID
        )
        AppLogger.shared.write(
            "HUD placement phase=saved " +
                "x=\(Int(panel.frame.origin.x)) y=\(Int(panel.frame.origin.y)) " +
                "width=\(Int(panel.frame.width)) height=\(Int(panel.frame.height))"
        )
    }
}

/// 不接受键盘焦点的无边框面板。按钮仍能接收鼠标点击，但不会把前台 App 的
/// 输入焦点抢走。
private final class HudPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 只使用公开的窗口几何信息选择屏幕，不读取窗口标题、内容或第三方 App 状态。
enum HudScreenResolver {
    static func preferredScreen(
        frontmostPID: pid_t? = NSWorkspace.shared.frontmostApplication?.processIdentifier,
        windowInfo: [[String: Any]]? = nil,
        screens: [NSScreen] = NSScreen.screens,
        mainScreen: NSScreen? = NSScreen.main
    ) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        let info = windowInfo ?? CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        let frames = screens.map(\.frame)
        let target: CGPoint?
        if let frontmostPID {
            target = largestWindowCenter(
                windowInfo: info,
                ownerPID: frontmostPID,
                screens: screens
            )
        } else {
            target = nil
        }
        guard let target,
              let index = bestScreenIndex(windowFrame: CGRect(origin: target, size: .zero), screenFrames: frames)
        else {
            return mainScreen ?? screens.first
        }
        return screens[index]
    }

    private static func largestWindowCenter(
        windowInfo: [[String: Any]],
        ownerPID: pid_t,
        screens: [NSScreen]
    ) -> CGPoint? {
        var bestArea: CGFloat = 0
        var bestCenter: CGPoint?
        for window in windowInfo {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == ownerPID,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? CGFloat,
                  let y = bounds["Y"] as? CGFloat,
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  width > 80, height > 80
            else { continue }
            let area = width * height
            guard area > bestArea else { continue }
            bestArea = area
            let quartzCenter = CGPoint(x: x + width / 2, y: y + height / 2)
            let screenHeight = screens.map(\.frame.maxY).max() ?? 0
            bestCenter = CGPoint(x: quartzCenter.x, y: screenHeight - quartzCenter.y)
        }
        return bestCenter
    }

    static func bestScreenIndex(
        windowFrame: CGRect,
        screenFrames: [CGRect]
    ) -> Int? {
        guard !screenFrames.isEmpty else { return nil }
        var bestIndex = 0
        var bestArea: CGFloat = 0
        for (index, frame) in screenFrames.enumerated() {
            let intersection = frame.intersection(windowFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestIndex = index
            }
        }
        // 完全不与任何屏幕相交时返回 nil，由调用方回退主屏。
        return bestArea > 0 ? bestIndex : nil
    }
}
