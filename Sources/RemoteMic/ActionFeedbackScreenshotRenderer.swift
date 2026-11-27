import AppKit
import SwiftUI

/// 生产 HUD 视图的离屏证据渲染。
///
/// 与设置/Onboarding 截图工具一致：只用于生成 PR 证据，不参与普通启动。
/// 画面是生产 `HudPanelView`，背后使用中性底色；真实浮层编号、非激活
/// 行为和屏幕位置由单测与真机流程验证，不能用这张图替代。
@MainActor
enum ActionFeedbackScreenshotRenderer {
    private enum RenderingError: Error, LocalizedError {
        case bitmapCreationFailed
        case pngCreationFailed

        var errorDescription: String? {
            switch self {
            case .bitmapCreationFailed:
                return "The action feedback screenshot bitmap could not be created."
            case .pngCreationFailed:
                return "The action feedback screenshot could not be encoded as PNG."
            }
        }
    }

    private static let canvasSize = CGSize(width: 560, height: 260)

    static func renderAll(to outputDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        _ = NSApplication.shared
        let languages: [(AppLanguage, String)] = [
            (.simplifiedChinese, "zh-Hans"),
            (.english, "en"),
        ]
        for (language, languageSuffix) in languages {
            let suiteName = "RemoteMic.ActionFeedbackScreenshot.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                throw RenderingError.bitmapCreationFailed
            }
            defer {
                defaults.removePersistentDomain(forName: suiteName)
                _ = defaults.synchronize()
                TemporaryUserDefaults.removeSuite(suiteName)
            }
            let settings = AppSettings(defaults: defaults)
            settings.applicationLanguage = language
            let localization = LocalizationStore(
                settings: settings,
                resourceBundle: RemoteMicResourceBundle.mainOrDevelopment
            )
            let strings = ActionFeedbackStrings(localization: localization)
            for (appearanceName, appearanceSuffix) in [
                (NSAppearance.Name.aqua, "light"),
                (NSAppearance.Name.darkAqua, "dark"),
            ] {
                for state in try states(language: language, strings: strings) {
                    let view = ZStack {
                        appearanceSuffix == "light"
                            ? Color(hex: 0xF2F2F4)
                            : Color(hex: 0x1C1C1E)
                        HudPanelView(
                            card: state.card,
                            lastCard: state.lastCard,
                            sessionCount: state.sessionCount,
                            strings: HudStrings(
                                locale: strings.locale,
                                idleStatus: strings.hudIdleStatus,
                                attentionStatus: strings.hudAttentionStatus,
                                sessionCountFormat: strings.hudSessionCountFormat
                            ),
                            isCopied: false,
                            onAction: { _ in },
                            onCopy: {},
                            onClose: {},
                            onHover: { _ in },
                            onDrag: { _ in },
                            onDragEnd: {}
                        )
                    }
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    let host = NSHostingView(rootView: view)
                    host.appearance = NSAppearance(named: appearanceName)
                    host.frame = NSRect(origin: .zero, size: canvasSize)
                    let window = NSWindow(
                        contentRect: NSRect(origin: .zero, size: canvasSize),
                        styleMask: [.borderless],
                        backing: .buffered,
                        defer: false
                    )
                    window.contentView = host
                    window.setContentSize(canvasSize)
                    window.orderFront(nil)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    window.contentView?.layoutSubtreeIfNeeded()
                    window.contentView?.displayIfNeeded()

                    guard let contentView = window.contentView,
                          let representation = contentView.bitmapImageRepForCachingDisplay(
                              in: contentView.bounds
                          )
                    else {
                        throw RenderingError.bitmapCreationFailed
                    }
                    contentView.cacheDisplay(in: contentView.bounds, to: representation)
                    guard let png = representation.representation(
                        using: .png,
                        properties: [:]
                    ) else {
                        throw RenderingError.pngCreationFailed
                    }
                    let filename = "action-feedback-\(languageSuffix)-\(appearanceSuffix)-\(state.name).png"
                    try png.write(to: outputDirectory.appendingPathComponent(filename))
                    window.orderOut(nil)
                    window.contentView = nil
                }
            }
        }
    }

    private static func states(
        language: AppLanguage,
        strings: ActionFeedbackStrings
    ) throws -> [RenderState] {
        let successName = language == .simplifiedChinese ? "打开微信" : "Open WeChat"
        let failureName = language == .simplifiedChinese ? "发送到微信" : "Send to WeChat"
        let success = try presentation(
            event: ActionFeedbackEvent(
                operationID: "demo-success",
                actionID: "openWeChat",
                actionName: successName,
                result: .success,
                elapsedMilliseconds: 96
            ),
            strings: strings,
            handlers: ActionFeedbackActionHandlers()
        )
        let failure = try presentation(
            event: ActionFeedbackEvent(
                operationID: "demo-failure",
                actionID: "combinationAction",
                actionName: failureName,
                result: .failure(.shortcutNotDelivered),
                elapsedMilliseconds: 128,
                stepCount: 3
            ),
            strings: strings,
            handlers: ActionFeedbackActionHandlers(retry: {})
        )
        func card(_ presentation: ActionFeedbackPresentation) -> HudCard {
            ActionFeedbackCenter.hudCard(for: presentation, strings: strings) { _ in }
        }
        return [
            RenderState(
                name: "idle",
                card: nil,
                lastCard: card(success),
                sessionCount: 4
            ),
            RenderState(
                name: "success",
                card: card(success),
                lastCard: card(success),
                sessionCount: 1
            ),
            RenderState(
                name: "failure",
                card: card(failure),
                lastCard: card(failure),
                sessionCount: 2
            ),
        ]
    }

    /// HUD 的一种状态：空闲（card 为 nil）、成功、失败。
    private struct RenderState {
        let name: String
        let card: HudCard?
        let lastCard: HudCard?
        let sessionCount: Int
    }

    private static func presentation(
        event: ActionFeedbackEvent,
        strings: ActionFeedbackStrings,
        handlers: ActionFeedbackActionHandlers
    ) throws -> ActionFeedbackPresentation {
        let center = ActionFeedbackCenter(
            successDuration: 3_600,
            log: { _ in },
            pasteboardWriter: { _ in }
        )
        center.configureStandardActions(
            openSystemSettings: {},
            reselectAction: {}
        )
        center.record(event, strings: strings, handlers: handlers)
        guard let presentation = center.presentation else {
            throw RenderingError.bitmapCreationFailed
        }
        return presentation
    }
}
