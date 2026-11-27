import AppKit
import Foundation
import Testing
@testable import RemoteMic

@Suite("Action feedback center", .serialized)
@MainActor
struct ActionFeedbackCenterTests {
    /// 每个用例一份独立 HUD，避免并行用例互相清掉对方的行。
    private let hud = HudCenter()

    private final class TestClock {
        var date = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func makeLocalization(
        _ language: AppLanguage = .english
    ) throws -> (LocalizationStore, UserDefaults, String) {
        let name = "ActionFeedbackTests.\(UUID().uuidString)"
        let defaults = try #require(TestUserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.applicationLanguage = language
        let localization = LocalizationStore(
            settings: settings,
            resourceBundle: RemoteMicResourceBundle.mainOrDevelopment
        )
        return (localization, defaults, name)
    }

    private func makeCenter(
        clock: TestClock = TestClock(),
        successDuration: TimeInterval = 60,
        mergeWindow: TimeInterval = 2,
        copiedDuration: TimeInterval = 2,
        logs: @escaping (String) -> Void = { _ in },
        pasteboard: @escaping (String) -> Void = { _ in }
    ) -> ActionFeedbackCenter {
        ActionFeedbackCenter(
            hud: hud,
            now: { clock.date },
            successDuration: successDuration,
            mergeWindow: mergeWindow,
            copiedDuration: copiedDuration,
            log: logs,
            pasteboardWriter: pasteboard
        )
    }

    private func event(
        actionID: String = "open_app",
        name: String = "打开微信",
        result: ActionFeedbackResult = .success,
        presentsSuccess: Bool = true,
        presentsFailure: Bool = true,
        elapsed: Int = 128,
        stepIndex: Int? = nil,
        stepCount: Int? = nil,
        at date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ActionFeedbackEvent {
        ActionFeedbackEvent(
            operationID: "operation-1",
            actionID: actionID,
            actionName: name,
            result: result,
            elapsedMilliseconds: elapsed,
            stepIndex: stepIndex,
            stepCount: stepCount,
            timestamp: date,
            presentsSuccess: presentsSuccess,
            presentsFailure: presentsFailure
        )
    }

    /// HudCenter 是单例：每个用例前后清一次历史行和开关，避免互相污染。
    private func resetHud() {
        hud.reset()
        hud.setEnabled(true)
    }

    @Test func successPushesOneHistoryRow() throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let center = makeCenter()
        center.record(event(), strings: ActionFeedbackStrings(localization: localization))

        // 成功不再占卡片，只往 HUD 历史里推一行。
        #expect(center.presentation == nil)
        #expect(center.lastPresentation?.kind == .success)
        #expect(center.lastPresentation?.title.contains("打开微信") == true)
        #expect(center.sessionCount == 1)
        let rows = hud.rows
        #expect(rows.count == 1)
        #expect(rows.first?.tone == .success)
        #expect(rows.first?.elapsedMilliseconds == 128)
    }

    @Test func successRowsDoNotAutoDismiss() async throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let center = makeCenter(successDuration: 0.04)
        center.record(event(), strings: ActionFeedbackStrings(localization: localization))
        #expect(hud.rows.count == 1)

        try await Task.sleep(nanoseconds: 1_000_000_000)
        // 成功行留在历史里，不再按 1.3 秒清掉。
        #expect(hud.rows.count == 1)
        #expect(hud.sessionCount == 1)
    }

    @Test func repeatedSuccessKeepsSeparateRows() throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let strings = ActionFeedbackStrings(localization: localization)
        let center = makeCenter()
        center.record(event(), strings: strings)
        center.record(event(), strings: strings)

        #expect(hud.rows.count == 2)
        #expect(hud.rows.allSatisfy { $0.title.contains("打开微信") })
        // 不再有「已执行「X」×2」这类合并计数。
        #expect(center.lastPresentation?.count == 1)
        #expect(center.lastPresentation?.title.contains("×") == false)
    }

    @Test func historyKeepsNewestThreeRows() throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let strings = ActionFeedbackStrings(localization: localization)
        let center = makeCenter()
        center.record(event(actionID: "open_wechat", name: "打开微信"), strings: strings)
        center.record(event(actionID: "open_wechat", name: "打开微信"), strings: strings)
        center.record(event(actionID: "open_safari", name: "打开 Safari"), strings: strings)

        let rows = hud.rows
        #expect(rows.count == 3)
        #expect(rows[0].title.contains("Safari"))
        #expect(rows[1].title.contains("打开微信"))
        #expect(rows[2].title.contains("打开微信"))

        // 第四行把最旧的一行挤掉，始终只有三行。
        center.record(event(actionID: "focus_input", name: "聚焦输入框"), strings: strings)
        let capped = hud.rows
        #expect(capped.count == 3)
        #expect(capped[0].title.contains("聚焦输入框"))
        #expect(capped[1].title.contains("Safari"))
        #expect(capped[2].title.contains("打开微信"))
    }

    @Test func failureStaysOnTopWhileSuccessAppendsBelow() throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let strings = ActionFeedbackStrings(localization: localization)
        let center = makeCenter()
        center.record(event(), strings: strings)
        #expect(center.presentation == nil)

        center.record(
            event(result: .failure(.shortcutNotDelivered)),
            strings: strings
        )
        #expect(center.presentation?.kind == .failure)
        #expect(hud.card != nil)
        #expect(hud.rows.first?.tone == .failure)
        // 失败不再显示「执行失败 / 动作没有完成」这类说明文字。
        #expect(center.presentation?.context == nil)
        #expect(center.presentation?.detail == nil)
        #expect(center.presentation?.title.contains("failed to run") == true)

        center.record(event(actionID: "open_safari", name: "打开 Safari"), strings: strings)
        // 成功不会顶掉未处理的失败：失败仍在第一行，成功排在下面。
        #expect(center.presentation?.kind == .failure)
        #expect(hud.card != nil)
        #expect(hud.rows[0].tone == .failure)
        #expect(hud.rows[1].tone == .success)
        #expect(hud.rows.count == 3)
    }

    @Test func onlyNewestFailureRowIsKept() throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let strings = ActionFeedbackStrings(localization: localization)
        let center = makeCenter()
        center.record(event(result: .failure(.shortcutNotDelivered)), strings: strings)
        center.record(event(result: .failure(.targetUnavailable)), strings: strings)

        // 多个失败只留最新一条，不做 ×N 合并，也不折叠。
        #expect(center.presentation?.count == 1)
        #expect(center.presentation?.title.contains("×") == false)
        #expect(hud.rows.filter { $0.tone == .failure }.count == 1)

        center.record(event(result: .timedOut), strings: strings)
        let failures = hud.rows.filter { $0.tone == .failure }
        #expect(failures.count == 1)
        #expect(failures.first?.title.contains("timed out") == true)
        #expect(center.presentation?.context == nil)
    }

    @Test func disabledSuccessOnlyLogs() throws {
        let (localization, defaults, name) = try makeLocalization()
        defer { defaults.removePersistentDomain(forName: name) }
        var logs: [String] = []
        let center = makeCenter(logs: { logs.append($0) })
        center.record(
            event(presentsSuccess: false),
            strings: ActionFeedbackStrings(localization: localization)
        )
        #expect(center.presentation == nil)
        #expect(logs.contains { $0.contains("presentation=disabled_success") })
    }

    @Test func failureStaysUntilDismissed() async throws {
        let (localization, defaults, name) = try makeLocalization()
        defer { defaults.removePersistentDomain(forName: name) }
        let center = makeCenter()
        let strings = ActionFeedbackStrings(localization: localization)
        center.record(
            event(result: .failure(.executionFailed)),
            strings: strings
        )
        #expect(center.presentation?.kind == .failure)

        try await Task.sleep(nanoseconds: 500_000_000)
        // 监控面板：失败不自动消失，停在失败态直到用户处理。
        #expect(center.presentation?.kind == .failure)

        center.dismiss()
        #expect(center.presentation == nil)
        // 面板常显，最近一条要继续留在空闲态里。
        #expect(center.lastPresentation?.kind == .failure)
        #expect(center.sessionCount == 1)
    }

    @Test func idleStateKeepsLastPresentationAndCount() async throws {
        let (localization, defaults, name) = try makeLocalization()
        defer { defaults.removePersistentDomain(forName: name) }
        let center = makeCenter(successDuration: 0.05)
        let strings = ActionFeedbackStrings(localization: localization)
        center.record(event(), strings: strings)
        #expect(center.sessionCount == 1)

        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(center.presentation == nil)
        #expect(center.lastPresentation?.kind == .success)
        #expect(center.sessionCount == 1)

        center.reset()
        #expect(center.lastPresentation == nil)
        #expect(center.sessionCount == 0)
    }

    @Test func hoverAndDragKeepSuccessRows() async throws {
        let (localization, defaults, name) = try makeLocalization()
        resetHud()
        defer {
            resetHud()
            defaults.removePersistentDomain(forName: name)
        }
        let center = makeCenter(successDuration: 0.04)
        center.record(event(), strings: ActionFeedbackStrings(localization: localization))
        #expect(hud.rows.count == 1)

        center.setHovering(true)
        center.setDragging(true)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(hud.rows.count == 1)

        center.setHovering(false)
        center.setDragging(false)
        try await Task.sleep(nanoseconds: 200_000_000)
        // 悬停和拖动都不影响历史行：成功行只按「最多三行」滚动。
        #expect(hud.rows.count == 1)
    }

    @Test func copyDiagnosticsIsSanitizedAndResetsCopiedState() async throws {
        let (localization, defaults, name) = try makeLocalization()
        defer { defaults.removePersistentDomain(forName: name) }
        var copied: String?
        let center = makeCenter(
            copiedDuration: 0.03,
            pasteboard: { copied = $0 }
        )
        let strings = ActionFeedbackStrings(localization: localization)
        center.record(
            event(
                actionID: "send",
                name: "Secret Action",
                result: .failure(.shortcutNotDelivered),
                elapsed: 128,
                stepIndex: 2,
                stepCount: 3
            ),
            strings: strings
        )
        #expect(center.presentation?.kind == .failure)
        center.copyDiagnostics()

        let text = try #require(copied)
        #expect(text.contains("operation-1"))
        #expect(text.contains("shortcut_not_delivered"))
        #expect(text.contains("128 ms"))
        #expect(text.contains("2 / 3"))
        #expect(!text.contains("Secret Action"))
        #expect(center.copiedPresentationID != nil)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        #expect(center.copiedPresentationID == nil)
        center.dismiss()
    }

    @Test func availableActionIsShownAndPerformed() throws {
        let (localization, defaults, name) = try makeLocalization()
        defer { defaults.removePersistentDomain(forName: name) }
        let center = makeCenter()
        var performed: ActionFeedbackAction?
        center.configureStandardActions(
            openSystemSettings: {},
            reselectAction: { performed = .reselectAction }
        )
        center.record(
            event(result: .failure(.targetMissing)),
            strings: ActionFeedbackStrings(localization: localization)
        )
        #expect(center.presentation?.action == .reselectAction)
        #expect(center.presentation?.actionTitle == "Choose Again")
        center.perform(.reselectAction)
        #expect(performed == .reselectAction)
        #expect(center.presentation == nil)
    }

    @Test func retryActionRequiresEventHandler() throws {
        let (localization, defaults, name) = try makeLocalization()
        defer { defaults.removePersistentDomain(forName: name) }
        let center = makeCenter()
        var retried = false
        center.record(
            event(result: .failure(.shortcutNotDelivered)),
            strings: ActionFeedbackStrings(localization: localization)
        )
        #expect(center.presentation?.action == nil)

        center.dismiss()
        center.record(
            event(result: .failure(.shortcutNotDelivered)),
            strings: ActionFeedbackStrings(localization: localization),
            handlers: ActionFeedbackActionHandlers(retry: { retried = true })
        )
        #expect(center.presentation?.action == .retry)
        #expect(center.presentation?.actionTitle == "Retry")
        center.perform(.retry)
        #expect(retried)
        center.dismiss()
    }
}

@Suite("Action feedback classification")
struct ActionFeedbackClassificationTests {
    @Test func macroTerminalMapsToStableCategories() {
        #expect(ActionFeedbackMacroClassifier.result(forTerminal: "completed") == .success)
        #expect(ActionFeedbackMacroClassifier.result(forTerminal: "cancelled") == .cancelled)
        #expect(ActionFeedbackMacroClassifier.result(forTerminal: "timedOut") == .timedOut)
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "permissionDenied")
                == .failure(.permissionDenied)
        )
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "missingDependency")
                == .failure(.configurationUnavailable)
        )
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "script_exit_nonzero")
                == .failure(.scriptFailed)
        )
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "script_launch_failed")
                == .failure(.scriptFailed)
        )
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "stepFailed")
                == .failure(.executionFailed)
        )
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "completedWithUnknownResult")
                == .failure(.unknownResult)
        )
        #expect(
            ActionFeedbackMacroClassifier.result(forTerminal: "something_new")
                == .failure(.unknownResult)
        )
    }

    @Test func repeatableActionsDoNotShowSuccessFeedback() {
        #expect(!ConfiguredButtonAction(action: .arrowUp, shortcut: nil).showsActionSuccessFeedback)
        #expect(!ConfiguredButtonAction(action: .scrollDown, shortcut: nil).showsActionSuccessFeedback)
        #expect(!ConfiguredButtonAction(action: .volumeUp, shortcut: nil).showsActionSuccessFeedback)
        #expect(!ConfiguredButtonAction(action: .appSwitcher, shortcut: nil).showsActionSuccessFeedback)
        #expect(!ConfiguredButtonAction(action: .pageDown, shortcut: nil).showsActionSuccessFeedback)
        #expect(ConfiguredButtonAction(action: .commandCopy, shortcut: nil).showsActionSuccessFeedback)
        #expect(ConfiguredButtonAction(action: .openWeChat, shortcut: nil).showsActionSuccessFeedback)
        #expect(ConfiguredButtonAction(action: .combinationAction, shortcut: nil).showsActionSuccessFeedback)
        let direction = CustomKeyboardShortcut(
            keyCode: 126,
            modifierFlags: [],
            keyLabel: "↑"
        )
        #expect(!ConfiguredButtonAction(
            action: .customShortcut,
            shortcut: direction
        ).showsActionSuccessFeedback)
    }
}

@Suite("Action feedback layout")
struct HudLayoutTests {
    @Test func bottomCenteredWithShadowPadding() {
        let origin = HudLayout.origin(
            visibleFrame: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            panelSize: CGSize(width: 400, height: 200)
        )
        #expect(origin.x == 300)
        #expect(origin.y == 40)
        #expect(origin.y + HudLayout.contentPadding == 56)
    }

    @Test func clampsToVisibleFrame() {
        let origin = HudLayout.origin(
            visibleFrame: CGRect(x: 10, y: 20, width: 200, height: 100),
            panelSize: CGSize(width: 400, height: 40)
        )
        #expect(origin.x == 18)
        #expect(origin.y == 60)
    }

    @Test func picksScreenWithLargestWindowIntersection() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1_000, height: 800),
            CGRect(x: 1_000, y: 0, width: 1_000, height: 800),
        ]
        #expect(HudScreenResolver.bestScreenIndex(
            windowFrame: CGRect(x: 1_200, y: 100, width: 400, height: 300),
            screenFrames: screens
        ) == 1)
        #expect(HudScreenResolver.bestScreenIndex(
            windowFrame: CGRect(x: 100, y: 100, width: 900, height: 300),
            screenFrames: screens
        ) == 0)
        #expect(HudScreenResolver.bestScreenIndex(
            windowFrame: CGRect(x: 2_500, y: 100, width: 100, height: 100),
            screenFrames: screens
        ) == nil)
    }

    @Test func normalizedOriginRoundTripsThroughRestore() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 850)
        let panelSize = CGSize(width: 400, height: 100)
        let origin = CGPoint(x: 700, y: 500)
        let normalized = HudLayout.normalizedOrigin(
            origin: origin,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        #expect(normalized.x > 0 && normalized.x < 1)
        #expect(normalized.y > 0 && normalized.y < 1)

        let restored = HudLayout.origin(
            normalizedX: normalized.x,
            normalizedY: normalized.y,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        #expect(abs(restored.x - origin.x) < 0.5)
        #expect(abs(restored.y - origin.y) < 0.5)
    }

    @Test func draggedOriginStaysInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 850)
        let panelSize = CGSize(width: 400, height: 100)
        let clamped = HudLayout.clampedOrigin(
            CGPoint(x: -500, y: 5_000),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        #expect(clamped.x == visibleFrame.minX + HudLayout.edgeMargin)
        #expect(clamped.y == visibleFrame.maxY - panelSize.height
            - HudLayout.edgeMargin)
    }

    @Test func storedCornerSurvivesDisplayChange() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 850)
        let panelSize = CGSize(width: 400, height: 100)
        let largeFrame = CGRect(x: 0, y: 0, width: 3_840, height: 2_160)
        let cornerOrigin = CGPoint(
            x: largeFrame.maxX - panelSize.width - HudLayout.edgeMargin,
            y: largeFrame.minY + HudLayout.edgeMargin
        )
        let normalized = HudLayout.normalizedOrigin(
            origin: cornerOrigin,
            panelSize: panelSize,
            visibleFrame: largeFrame
        )
        let restored = HudLayout.origin(
            normalizedX: normalized.x,
            normalizedY: normalized.y,
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )
        #expect(abs(restored.x - (visibleFrame.maxX - panelSize.width
            - HudLayout.edgeMargin)) < 0.5)
        #expect(abs(restored.y - (visibleFrame.minY
            + HudLayout.edgeMargin)) < 0.5)
    }

    @Test func placementIsRememberedPerDisplay() throws {
        let name = "HudPlacement.\(UUID().uuidString)"
        let defaults = try #require(TestUserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HudPlacementStore(defaults: defaults)
        let placement = HudPlacement(normalizedX: 0.25, normalizedY: 0.75)

        #expect(store.placement(displayID: 1) == nil)

        store.save(placement, displayID: 1)
        #expect(store.placement(displayID: 1) == placement)
        #expect(store.placement(displayID: 2) == nil)
    }
}

@Suite("Action feedback localization")
@MainActor
struct ActionFeedbackLocalizationTests {
    private func setup(_ language: AppLanguage) throws -> (LocalizationStore, UserDefaults, String) {
        let name = "ActionFeedbackLocalization.\(UUID().uuidString)"
        let defaults = try #require(TestUserDefaults(suiteName: name))
        let settings = AppSettings(defaults: defaults)
        settings.applicationLanguage = language
        return (
            LocalizationStore(
                settings: settings,
                resourceBundle: RemoteMicResourceBundle.mainOrDevelopment
            ),
            defaults,
            name
        )
    }

    @Test func everyFeedbackKeyExistsInBothLanguages() throws {
        let keys = [
            "action_feedback.success.title",
            "action_feedback.success.repeat",
            "action_feedback.success.multiple",
            "action_feedback.failure.title",
            "action_feedback.timeout.title",
            "action_feedback.timeout.context",
            "action_feedback.timeout.detail",
            "action_feedback.action.open_application",
            "action_feedback.action.reselect",
            "action_feedback.action.copy_diagnostics",
            "action_feedback.action.copied",
            "action_feedback.diagnostics.note",
            "action_feedback.open_application_name",
            "settings.general.action_feedback.title",
            "settings.general.action_feedback.help",
            "settings.general.hide_all_action_feedback",
            "settings.general.hide_action_success_feedback",
        ] + ActionFeedbackFailureKind.allCases.flatMap {
            [
                "action_feedback.failure.\($0.rawValue).context",
                "action_feedback.failure.\($0.rawValue).detail",
            ]
        }
        for language in [AppLanguage.simplifiedChinese, .english] {
            let (localization, defaults, name) = try setup(language)
            defer { defaults.removePersistentDomain(forName: name) }
            for key in keys {
                #expect(localization.text(key) != key, "缺少本地化 key: \(key) (\(language.rawValue))")
            }
        }
    }

    @Test func diagnosticsNeverContainActionName() throws {
        let (localization, defaults, name) = try setup(.english)
        defer { defaults.removePersistentDomain(forName: name) }
        let strings = ActionFeedbackStrings(localization: localization)
        let event = ActionFeedbackEvent(
            operationID: "op-123",
            actionID: "customShortcut",
            actionName: "Very Secret Shortcut",
            result: .failure(.shortcutNotDelivered),
            elapsedMilliseconds: 42,
            stepCount: 2,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let text = ActionFeedbackDiagnostics.text(
            event: event,
            strings: strings,
            bundle: Bundle.main,
            processInfo: .processInfo
        )
        #expect(text.contains("op-123"))
        #expect(text.contains("customShortcut"))
        #expect(text.contains("42 ms"))
        #expect(!text.contains("Very Secret Shortcut"))
        #expect(text.contains(strings.diagnosticsNote))
    }
}
