import Foundation
import Testing
@testable import RemoteMic

@Suite("Bridge app model action regression", .serialized)
@MainActor
struct BridgeAppModelActionRegressionTests {
    private static func profile() -> CustomApplicationProfile {
        CustomApplicationProfile(
            displayName: "Example Agent",
            bundleIdentifier: "com.example.agent",
            applicationPath: "/Applications/Example Agent.app",
            focusStrategy: .recordedAccessibility
        )
    }

    private func makeSettings() throws -> (AppSettings, UserDefaults, String) {
        let suiteName = "BridgeAppModelActionRegression.\(UUID().uuidString)"
        let defaults = try #require(TestUserDefaults(suiteName: suiteName))
        let settings = AppSettings(defaults: defaults)
        settings.applicationLanguage = .english
        return (settings, defaults, suiteName)
    }

    private func waitForFeedback() async throws {
        try await Task.sleep(nanoseconds: 30_000_000)
    }

    @Test func pendingApplicationOpensThroughBridgeAndSkipsFocus() async throws {
        let (settings, defaults, suiteName) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = Self.profile()
        settings.addCustomApplicationProfile(profile)
        defaults.set([profile.id.uuidString], forKey: "portableTransferPendingApplications")
        var sent: [(ButtonAction, UUID?, Bool)] = []
        let model = BridgeAppModel(
            settings: settings,
            externalActionSender: { action, _, applicationProfile, focusAllowed, completion in
                sent.append((action, applicationProfile?.id, focusAllowed))
                completion(true)
                return true
            },
            customApplicationURLResolver: { _ in
                URL(fileURLWithPath: "/Applications/Example Agent.app")
            }
        )
        ActionFeedbackCenter.shared.resetMergeStateForTesting()

        let handled = model.performExternalConfiguredAction(ConfiguredButtonAction(
            action: .openCustomApplication,
            shortcut: nil,
            applicationProfileID: profile.id
        ))

        #expect(handled)
        #expect(sent.count == 1)
        #expect(sent.first?.0 == .openCustomApplication)
        #expect(sent.first?.1 == profile.id)
        #expect(sent.first?.2 == false)
        try await waitForFeedback()
        // 成功不再占卡片，只往 HUD 历史里推一行。
        #expect(ActionFeedbackCenter.shared.presentation == nil)
        #expect(ActionFeedbackCenter.shared.lastPresentation?.kind == .success)
        #expect(HudCenter.shared.rows.first?.title.contains("Example Agent") == true)
        ActionFeedbackCenter.shared.dismiss()
    }

    @Test func missingApplicationThroughBridgeReturnsFailureAndShowsNotice() async throws {
        let (settings, defaults, suiteName) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = Self.profile()
        settings.addCustomApplicationProfile(profile)
        var sentCount = 0
        let model = BridgeAppModel(
            settings: settings,
            externalActionSender: { _, _, _, _, completion in
                sentCount += 1
                completion(true)
                return true
            },
            customApplicationURLResolver: { _ in nil }
        )
        ActionFeedbackCenter.shared.resetMergeStateForTesting()

        let handled = model.performExternalConfiguredAction(ConfiguredButtonAction(
            action: .openCustomApplication,
            shortcut: nil,
            applicationProfileID: profile.id
        ))

        #expect(!handled)
        #expect(sentCount == 0)
        try await waitForFeedback()
        #expect(ActionFeedbackCenter.shared.presentation?.kind == .failure)
        // 失败行只保留标题：上下文不再进面板，失败原因仍在诊断与播报文本里。
        #expect(ActionFeedbackCenter.shared.presentation?.context == nil)
        #expect(ActionFeedbackCenter.shared.presentation?.title.contains("Example Agent") == true)
        ActionFeedbackCenter.shared.dismiss()
    }

    @Test func actionSenderFailureThroughBridgeShowsNotice() async throws {
        let (settings, defaults, suiteName) = try makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let profile = Self.profile()
        settings.addCustomApplicationProfile(profile)
        let model = BridgeAppModel(
            settings: settings,
            externalActionSender: { _, _, _, _, completion in
                completion(false)
                return false
            },
            customApplicationURLResolver: { _ in
                URL(fileURLWithPath: "/Applications/Example Agent.app")
            }
        )
        ActionFeedbackCenter.shared.resetMergeStateForTesting()

        let handled = model.performExternalConfiguredAction(ConfiguredButtonAction(
            action: .openCustomApplication,
            shortcut: nil,
            applicationProfileID: profile.id
        ))

        #expect(!handled)
        try await waitForFeedback()
        #expect(ActionFeedbackCenter.shared.presentation?.kind == .failure)
        #expect(ActionFeedbackCenter.shared.presentation?.context == nil)
        ActionFeedbackCenter.shared.dismiss()
    }
}
