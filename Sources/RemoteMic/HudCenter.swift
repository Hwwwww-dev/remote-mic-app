import AppKit
import Combine
import Foundation

/// HUD 是独立于具体功能的一层屏幕浮窗：它不认识动作反馈，只负责把一张卡片
/// 画在所有窗口之上、记住位置、处理拖动和悬停。任何功能都可以往它推卡片。
enum HudTone: Equatable, Sendable {
    case idle
    case success
    case failure
}

/// 遥控器当前处在哪种模式：只影响状态行那段文字的颜色，不参与任何动作判断。
enum HudMode: Equatable, Sendable {
    case keyboard
    case mouse
}

struct HudAction {
    let title: String
    let isProminent: Bool
    let perform: @MainActor () -> Void
}

/// 面板里的一行。列表按时间倒序，新的在最上面；每行只保留标题和耗时，
/// 详细文案交给 `HudCard`，这样历史行不会被撑高。
struct HudRow: Identifiable, Equatable, Sendable {
    let id: UUID
    let tone: HudTone
    let title: String
    let elapsedMilliseconds: Int?
}

struct HudCard: Identifiable {
    let id: UUID
    let tone: HudTone
    let title: String
    let context: String?
    let detail: String?
    let elapsedMilliseconds: Int?
    let primaryAction: HudAction?
    let secondaryAction: HudAction?
    /// 次要按钮复制成功后的标题（动作反馈的「已复制」），其它来源可以留空。
    let secondaryTitleWhenCopied: String?
    let closeLabel: String
    let announces: Bool
    let accessibilityAnnouncement: String?

    init(
        tone: HudTone,
        title: String,
        context: String? = nil,
        detail: String? = nil,
        elapsedMilliseconds: Int? = nil,
        primaryAction: HudAction? = nil,
        secondaryAction: HudAction? = nil,
        secondaryTitleWhenCopied: String? = nil,
        closeLabel: String = "",
        announces: Bool = false,
        accessibilityAnnouncement: String? = nil
    ) {
        id = UUID()
        self.tone = tone
        self.title = title
        self.context = context
        self.detail = detail
        self.elapsedMilliseconds = elapsedMilliseconds
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.secondaryTitleWhenCopied = secondaryTitleWhenCopied
        self.closeLabel = closeLabel
        self.announces = announces
        self.accessibilityAnnouncement = accessibilityAnnouncement
    }
}

/// HUD 自己的状态行文案，由 App 语言构建，业务方不需要关心。
struct HudStrings: Sendable {
    let locale: Locale
    let idleStatus: String
    let attentionStatus: String
    let sessionCountFormat: String
    let modeKeyboard: String
    let modeMouse: String

    init(localization: LocalizationStore) {
        locale = localization.locale
        idleStatus = localization.text("action_feedback.hud.status.idle")
        attentionStatus = localization.text("action_feedback.hud.status.attention")
        sessionCountFormat = localization.text("action_feedback.hud.session_count")
        modeKeyboard = localization.text("action_feedback.hud.mode.keyboard")
        modeMouse = localization.text("action_feedback.hud.mode.mouse")
    }

    /// 从已经构建好的动作反馈文案里取 HUD 需要的几条，避免重复读本地化表。
    init(
        locale: Locale,
        idleStatus: String,
        attentionStatus: String,
        sessionCountFormat: String,
        modeKeyboard: String,
        modeMouse: String
    ) {
        self.locale = locale
        self.idleStatus = idleStatus
        self.attentionStatus = attentionStatus
        self.sessionCountFormat = sessionCountFormat
        self.modeKeyboard = modeKeyboard
        self.modeMouse = modeMouse
    }

    func format(_ template: String, _ arguments: String...) -> String {
        String(format: template, locale: locale, arguments: arguments)
    }
}

/// HUD 的几何：默认落点、归一化记忆和夹边。只跟窗口几何有关，与内容无关。
enum HudLayout {
    static let width: CGFloat = 320
    static let edgeMargin: CGFloat = 8
    static let contentPadding: CGFloat = 16
    static let bottomInset: CGFloat = 56

    static func origin(
        visibleFrame: CGRect,
        panelSize: CGSize,
        bottomInset: CGFloat = HudLayout.bottomInset,
        contentPadding: CGFloat = HudLayout.contentPadding
    ) -> CGPoint {
        let preferredX = visibleFrame.midX - panelSize.width / 2
        let minimumX = visibleFrame.minX + edgeMargin
        let maximumX = visibleFrame.maxX - panelSize.width - edgeMargin
        let x = maximumX >= minimumX
            ? min(max(preferredX, minimumX), maximumX)
            : minimumX
        let preferredY = visibleFrame.minY + bottomInset - contentPadding
        let y = max(visibleFrame.minY + edgeMargin, preferredY)
        return CGPoint(x: x, y: y)
    }

    /// 把面板原点折成 0...1，便于换屏或改分辨率后按比例还原。
    static func normalizedOrigin(
        origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        func ratio(_ value: CGFloat, _ minimum: CGFloat, _ span: CGFloat) -> CGFloat {
            guard span > 0 else { return 0 }
            return min(max((value - minimum) / span, 0), 1)
        }
        return CGPoint(
            x: ratio(origin.x, visibleFrame.minX, visibleFrame.width - panelSize.width),
            y: ratio(origin.y, visibleFrame.minY, visibleFrame.height - panelSize.height)
        )
    }

    /// 拖动和还原时都夹回可见区域，避免面板被菜单栏、Dock 或屏幕边缘截掉。
    static func clampedOrigin(
        _ origin: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let minimumX = visibleFrame.minX + edgeMargin
        let maximumX = visibleFrame.maxX - panelSize.width - edgeMargin
        let minimumY = visibleFrame.minY + edgeMargin
        let maximumY = visibleFrame.maxY - panelSize.height - edgeMargin
        return CGPoint(
            x: maximumX >= minimumX ? min(max(origin.x, minimumX), maximumX) : minimumX,
            y: maximumY >= minimumY ? min(max(origin.y, minimumY), maximumY) : minimumY
        )
    }

    static func origin(
        normalizedX: CGFloat,
        normalizedY: CGFloat,
        panelSize: CGSize,
        visibleFrame: CGRect
    ) -> CGPoint {
        let x = visibleFrame.minX + normalizedX * max(0, visibleFrame.width - panelSize.width)
        let y = visibleFrame.minY + normalizedY * max(0, visibleFrame.height - panelSize.height)
        return clampedOrigin(
            CGPoint(x: x, y: y),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
    }
}

/// 独立 HUD 的状态源。窗口、位置记忆、拖动都在 `HudPanelCoordinator`；这里只管
/// 「现在显示什么」和「HUD 开没开」。
@MainActor
final class HudCenter: ObservableObject {
    static let shared = HudCenter()

    @Published private(set) var card: HudCard?
    /// 面板最多保留的历史行数（含正在显示的失败行）。
    static let maxRows = 3
    /// 历史行，按时间倒序：`rows[0]` 是最新一条。
    @Published private(set) var rows: [HudRow] = []
    @Published private(set) var sessionCount = 0
    @Published private(set) var isEnabled = true
    @Published private(set) var copiedCardID: UUID?
    @Published private(set) var strings: HudStrings?
    /// 遥控器当前模式，只用于状态行文字与配色。
    @Published private(set) var mode: HudMode = .keyboard
    /// 是否至少有一路遥控连接（遥控器本体 / 手机 / 手表），决定状态点的颜色。
    @Published private(set) var isRemoteConnected = false

    /// 悬停或拖动时回调，让推卡片的业务方暂停自己的计时。
    var onInteractionChange: (@MainActor (Bool) -> Void)?
    /// 用户点了失败卡片上的「复制诊断」或 ×；由推卡片的业务方决定怎么处理。
    var onCopyRequested: (@MainActor (HudCard) -> Void)?
    var onCloseRequested: (@MainActor (HudCard) -> Void)?

    func requestCopy(for card: HudCard?) {
        guard let card else { return }
        onCopyRequested?(card)
    }

    func requestClose(for card: HudCard?) {
        guard let card else { return }
        onCloseRequested?(card)
    }

    func configure(strings: HudStrings) {
        self.strings = strings
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if !enabled {
            reset()
        }
    }

    func setMode(_ mode: HudMode) {
        guard mode != self.mode else { return }
        self.mode = mode
    }

    func setRemoteConnected(_ connected: Bool) {
        guard connected != isRemoteConnected else { return }
        isRemoteConnected = connected
    }

    /// 推一张卡片。成功卡片只占一行历史；失败卡片额外成为「正在处理」的卡片，
    /// 带按钮和关闭按钮，并且永远排在历史行最上面。
    func present(_ card: HudCard) {
        let row = HudRow(
            id: card.id,
            tone: card.tone,
            title: card.title,
            elapsedMilliseconds: card.elapsedMilliseconds
        )
        if card.tone == .failure {
            // 多个失败只留最新一条：旧失败行被新失败顶掉，不做折叠翻页。
            rows.removeAll { $0.tone == .failure }
            self.card = card
        }
        // 有未处理的失败时，新的成功行插在失败行下面，失败一直占第一行。
        let index = (self.card != nil && card.tone != .failure) ? 1 : 0
        rows.insert(row, at: min(index, rows.count))
        if rows.count > Self.maxRows {
            rows.removeLast(rows.count - Self.maxRows)
        }
        sessionCount += 1
    }

    /// 收起正在显示的失败卡片；HUD 本身和其余历史行留在原处。
    func clearCard() {
        rows.removeAll { $0.id == card?.id }
        card = nil
        copiedCardID = nil
    }

    func reset() {
        card = nil
        rows.removeAll()
        sessionCount = 0
        copiedCardID = nil
    }

    func markCopied(_ cardID: UUID?) {
        copiedCardID = cardID
    }

    func setInteracting(_ interacting: Bool) {
        onInteractionChange?(interacting)
    }

    func resetForTesting() {
        reset()
    }
}
