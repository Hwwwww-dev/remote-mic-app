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
                            rows: state.rows,
                            sessionCount: state.sessionCount,
                            mode: state.mode,
                            isRemoteConnected: state.isRemoteConnected,
                            strings: HudStrings(
                                locale: strings.locale,
                                idleStatus: strings.hudIdleStatus,
                                attentionStatus: strings.hudAttentionStatus,
                                sessionCountFormat: strings.hudSessionCountFormat,
                                modeKeyboard: strings.hudModeKeyboard,
                                modeMouse: strings.hudModeMouse
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
        let names = language == .simplifiedChinese
            ? ["打开微信", "聚焦输入框", "向下翻半页"]
            : ["Open WeChat", "Focus field", "Page down"]
        let failureName = language == .simplifiedChinese ? "发送到微信" : "Send to WeChat"

        func successRow(_ index: Int, elapsed: Int) -> HudRow {
            HudRow(
                id: UUID(),
                tone: .success,
                title: strings.format(strings.successTitleFormat, names[index]),
                elapsedMilliseconds: elapsed
            )
        }

        let failureCard = HudCard(
            tone: .failure,
            title: strings.format(strings.failureTitleFormat, failureName),
            elapsedMilliseconds: 128,
            primaryAction: HudAction(
                title: strings.actionTitles[.retry] ?? "Retry",
                isProminent: true
            ) {},
            secondaryAction: HudAction(
                title: strings.copyDiagnosticsTitle,
                isProminent: false
            ) {},
            secondaryTitleWhenCopied: strings.copiedTitle,
            closeLabel: strings.closeLabel
        )

        return [
            RenderState(
                name: "idle",
                card: nil,
                rows: [successRow(0, elapsed: 96), successRow(1, elapsed: 88), successRow(2, elapsed: 41)],
                sessionCount: 4,
                mode: .keyboard,
                isRemoteConnected: true
            ),
            RenderState(
                name: "success",
                card: nil,
                rows: [successRow(1, elapsed: 88), successRow(0, elapsed: 96)],
                sessionCount: 2,
                mode: .keyboard,
                isRemoteConnected: true
            ),
            RenderState(
                name: "failure",
                card: failureCard,
                rows: [
                    HudRow(
                        id: failureCard.id,
                        tone: .failure,
                        title: failureCard.title,
                        elapsedMilliseconds: 128
                    ),
                    successRow(0, elapsed: 96),
                    successRow(1, elapsed: 88),
                ],
                sessionCount: 12,
                mode: .mouse,
                isRemoteConnected: false
            ),
        ]
    }

    /// HUD 的一种状态：空闲（card 为 nil）、成功、失败。
    private struct RenderState {
        let name: String
        let card: HudCard?
        let rows: [HudRow]
        let sessionCount: Int
        let mode: HudMode
        let isRemoteConnected: Bool
    }

}
