import CoreGraphics
import Foundation
import Testing
@testable import RemoteMic

@Suite("Mouse mode controller")
struct MouseModeControllerTests {
    @Test func idleControllerIgnoresEdgesUntilActivated() {
        let harness = Harness()

        #expect(!harness.controller.isActive)
        #expect(!harness.controller.handle(button: .right, edge: .down))
        #expect(!harness.controller.handle(button: .ok, edge: .down))
        #expect(harness.moves.isEmpty)
        #expect(harness.clicks.isEmpty)

        #expect(harness.controller.toggle())
        #expect(harness.controller.isActive)
        #expect(harness.states == [true])

        #expect(harness.controller.toggle())
        #expect(!harness.controller.isActive)
        #expect(harness.states == [true, false])
    }

    @Test func activationRequiresAccessibilityPermission() {
        let harness = Harness(trusted: false)

        #expect(!harness.controller.activate())
        #expect(!harness.controller.isActive)
        #expect(harness.states.isEmpty)
        #expect(harness.tickHandler == nil)
    }

    @Test func directionDownStartsMovementAndDirectionUpStopsIt() {
        let harness = Harness(cursor: CGPoint(x: 500, y: 400))
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .right, edge: .down))
        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        let firstMove = harness.moves.last
        #expect(firstMove != nil)
        // speed(1/60) ≈ 160.24 px/s, one tick of 1/60 s moves about 2.6707 px.
        #expect(abs((firstMove?.x ?? 0) - 502.67) < 0.01)
        #expect(firstMove?.y == 400)

        #expect(harness.controller.handle(button: .right, edge: .up))
        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        #expect(harness.moves.count == 1)
    }

    @Test func tuningPresetReplacesTheBakedInSpeedCurve() {
        var fast = MouseModeTuning.standard
        fast.speed = .fast
        fast.acceleration = .short
        #expect(MouseModeController.speed(afterHoldingFor: 0, tuning: fast) == 250)
        #expect(MouseModeController.speed(afterHoldingFor: 0.4, tuning: fast) == 2200)
        #expect(MouseModeController.speed(afterHoldingFor: 1.2, tuning: fast) == 2200)

        var slow = MouseModeTuning.standard
        slow.speed = .slow
        #expect(MouseModeController.speed(afterHoldingFor: 1.2, tuning: slow) == 600)
        #expect(MouseModeController.speed(afterHoldingFor: 0, tuning: .standard) == 160)
    }

    @Test func tuningPresetsDefaultToThePreSettingsBehaviour() {
        #expect(MouseModeTuning.standard.speed == .standard)
        #expect(MouseModeTuning.standard.acceleration == .standard)
        #expect(MouseModeTuning.standard.doubleClick == .standard)
        #expect(MouseModeTuning.standard.longPress == .standard)
        #expect(MouseModeTuning.DoubleClickPreset.standard.duration
                == MouseModeController.doubleTapWindow)
        #expect(MouseModeTuning.LongPressPreset.standard.duration
                == MouseModeController.okLongPressDuration)
    }

    @Test func movementAcceleratesWithQuadraticEaseIn() {
        #expect(MouseModeController.speed(afterHoldingFor: 0) == 160)
        #expect(MouseModeController.speed(afterHoldingFor: 0.6) == 470)
        #expect(MouseModeController.speed(afterHoldingFor: 1.2) == 1400)
        #expect(MouseModeController.speed(afterHoldingFor: 5) == 1400)

        let harness = Harness(
            cursor: CGPoint(x: 500, y: 400),
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 4000)
        )
        #expect(harness.controller.activate())
        #expect(harness.controller.handle(button: .down, edge: .down))

        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        let slow = harness.moves.last
        #expect(slow != nil)
        // speed(1/60) ≈ 160.24 px/s, one tick of 1/60 s moves about 2.6707 px.
        #expect(abs((slow?.y ?? 0) - 402.67) < 0.01)

        for _ in 0 ..< 59 {
            harness.advance(by: MouseModeController.tickInterval)
            harness.tick()
        }
        #expect(harness.moves.count == 60)
        // At t = 1 s: progress = 1/1.2, speed ≈ 1021.1 px/s, ≈ 17.02 px per tick.
        let fast = harness.moves.last
        let previous = harness.moves.dropLast().last
        #expect(abs(((fast?.y ?? 0) - (previous?.y ?? 0)) - 17.02) < 0.01)
    }

    @Test func diagonalMovementNormalizesTheDirectionVector() {
        let harness = Harness(cursor: CGPoint(x: 500, y: 400))
        #expect(harness.controller.activate())
        #expect(harness.controller.handle(button: .right, edge: .down))
        #expect(harness.controller.handle(button: .down, edge: .down))

        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        let move = harness.moves.last
        #expect(move != nil)
        // One tick at ≈160.24 px/s travels about 2.6707 px split across both axes.
        let axis = 2.6707 / 2.squareRoot()
        #expect(abs((move?.x ?? 0) - (500 + axis)) < 0.01)
        #expect(abs((move?.y ?? 0) - (400 + axis)) < 0.01)
    }

    @Test func movementClampsToTheScreenBounds() {
        let harness = Harness(
            cursor: CGPoint(x: 1439, y: 450),
            bounds: CGRect(x: 0, y: 0, width: 1440, height: 900)
        )
        #expect(harness.controller.activate())
        #expect(harness.controller.handle(button: .right, edge: .down))

        harness.advance(by: 1)
        harness.tick()
        #expect(harness.moves.last == CGPoint(x: 1439, y: 450))

        #expect(MouseModeController.clamped(
            CGPoint(x: -50, y: 1000),
            to: CGRect(x: 0, y: 0, width: 1440, height: 900)
        ) == CGPoint(x: 0, y: 899))
        #expect(MouseModeController.clamped(
            CGPoint(x: 10, y: 10),
            to: .null
        ) == CGPoint(x: 10, y: 10))
    }

    @Test func tickDeltaIsCappedSoRunLoopStallsPauseMovement() {
        let harness = Harness(cursor: CGPoint(x: 500, y: 400))
        #expect(harness.controller.activate())
        #expect(harness.controller.handle(button: .right, edge: .down))

        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        #expect(harness.moves.count == 1)

        // One second passes without a tick (stalled run loop).
        harness.advance(by: 1)
        harness.tick()
        #expect(harness.moves.count == 2)
        // At t ≈ 1.017 s the quadratic curve gives ≈ 1050.1 px/s, but the
        // delta is capped at 0.05 s: the cursor pauses (≈52.5 px) instead of
        // jumping a full second's worth.
        let jump = (harness.moves.last?.x ?? 0) - (harness.moves.first?.x ?? 0)
        #expect(abs(jump - 52.5) < 0.01)
    }

    @Test func missingCursorPositionSkipsMovementAndClicks() {
        let harness = Harness(cursor: nil)
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .right, edge: .down))
        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        #expect(harness.moves.isEmpty)

        #expect(harness.controller.handle(button: .ok, edge: .down))
        #expect(harness.controller.handle(button: .ok, edge: .up))
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.isEmpty)
    }

    @Test func hidMonitorFlushClearsPhantomGestureRepeatAndNonRepeatableState() throws {
        let suiteName = "MouseModeControllerTests.flush.\(UUID().uuidString)"
        let defaults = try #require(TestUserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        let profileID = UUID()
        settings.setAction(.escape, for: .home, trigger: .longPress)

        let scheduler = FakeHIDScheduler()
        var performed: [ButtonAction] = []
        let monitor = HIDRemoteMonitor(
            settings: settings,
            profileID: profileID,
            ownsEventSuppressor: false,
            scheduler: scheduler,
            runtimePermissions: { true },
            actionPerformer: { _, _, configured in
                performed.append(configured.action)
                return true
            },
            frontmostBundleIdentifier: { "com.example.other" },
            diagnosticLogger: { _ in }
        )
        monitor.connectSimulatedDevice(fingerprint: "sim", profileID: profileID)

        // Holding .home starts long-press tracking; holding .up (arrowUp)
        // performs immediately and starts a repeat timer.
        monitor.handleSimulatedReport(
            reportID: 1,
            data: Data([0x4A, 0x00, 0x52, 0x00, 0, 0])
        )
        #expect(performed == [.arrowUp])
        #expect(!scheduler.tasks.isEmpty)

        // Mouse mode activates: in-flight state is flushed.
        monitor.cancelPendingButtonActions()

        // Firing everything the fake scheduler ever captured must not produce
        // phantom long-press, double-click or repeat actions.
        scheduler.fireAll()
        #expect(performed == [.arrowUp])

        // The release after the flush must not trigger any phantom click.
        monitor.handleSimulatedReport(reportID: 1, data: Data([0, 0, 0, 0, 0, 0]))
        scheduler.fireAll()
        #expect(performed == [.arrowUp])

        // Non-repeatable latches are cleared as well.
        #expect(monitor.shouldAcceptRawPress(
            button: .menu,
            action: .customShortcut,
            frontmostBundleIdentifier: "com.example.other"
        ))
        #expect(!monitor.shouldAcceptRawPress(
            button: .menu,
            action: .customShortcut,
            frontmostBundleIdentifier: "com.example.other"
        ))
        monitor.cancelPendingButtonActions()
        #expect(monitor.shouldAcceptRawPress(
            button: .menu,
            action: .customShortcut,
            frontmostBundleIdentifier: "com.example.other"
        ))
    }

    @Test func hidMonitorHandsManagedEdgesToMouseModeAndSkipsConfiguredActions() throws {
        let suiteName = "MouseModeControllerTests.edges.\(UUID().uuidString)"
        let defaults = try #require(TestUserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.customMappingEnabled = true
        let profileID = UUID()
        settings.setAction(.arrowUp, for: .ok)
        settings.setAction(.arrowDown, for: .menu)

        var performed: [ButtonAction] = []
        var handledEdges: [RemoteButton] = []
        let managedButtons: Set<RemoteButton> = [.up, .down, .left, .right, .ok, .back]
        let monitor = HIDRemoteMonitor(
            settings: settings,
            profileID: profileID,
            ownsEventSuppressor: false,
            runtimePermissions: { true },
            actionPerformer: { _, _, configured in
                performed.append(configured.action)
                return true
            },
            frontmostBundleIdentifier: { "com.example.other" },
            diagnosticLogger: { _ in }
        )
        monitor.connectSimulatedDevice(fingerprint: "sim", profileID: profileID)
        monitor.mouseModeEdgeHandler = { button, _ in
            guard managedButtons.contains(button) else { return false }
            handledEdges.append(button)
            return true
        }

        // OK is managed by mouse mode: its configured action must not fire.
        monitor.handleSimulatedReport(reportID: 1, data: Data([0x28, 0, 0, 0, 0, 0]))
        monitor.handleSimulatedReport(reportID: 1, data: Data([0, 0, 0, 0, 0, 0]))
        #expect(handledEdges == [.ok, .ok])
        #expect(performed.isEmpty)

        // Menu keeps its configured binding while mouse mode is active.
        monitor.handleSimulatedReport(reportID: 1, data: Data([0x65, 0, 0, 0, 0, 0]))
        monitor.handleSimulatedReport(reportID: 1, data: Data([0, 0, 0, 0, 0, 0]))
        #expect(handledEdges == [.ok, .ok])
        #expect(performed == [.arrowDown])

        // Back is managed as well: its configured binding must not fire either.
        monitor.handleSimulatedReport(reportID: 1, data: Data([0xF1, 0, 0, 0, 0, 0]))
        monitor.handleSimulatedReport(reportID: 1, data: Data([0, 0, 0, 0, 0, 0]))
        #expect(handledEdges == [.ok, .ok, .back, .back])
        #expect(performed == [.arrowDown])
    }

    @Test func quickRepeatedDirectionTapsOnlyMoveTheCursor() {
        let harness = Harness(cursor: CGPoint(x: 500, y: 400))
        #expect(harness.controller.activate())

        // Two quick taps and then a tap followed by a hold on the same
        // direction: nothing is ever injected and the cursor never jumps back.
        for _ in 0 ..< 2 {
            #expect(harness.controller.handle(button: .right, edge: .down))
            harness.advance(by: 0.05)
            harness.tick()
            #expect(harness.controller.handle(button: .right, edge: .up))
            harness.advance(by: 0.06)
        }
        #expect(harness.controller.handle(button: .right, edge: .down))
        harness.advance(by: 0.2)
        harness.tick()
        #expect(harness.controller.handle(button: .right, edge: .up))

        #expect(harness.keys.isEmpty)
        #expect(harness.clicks.isEmpty)
        #expect(harness.moves.count == 3)
        let xs = harness.moves.map(\.x)
        #expect(xs == xs.sorted())
        #expect(xs.last.map { $0 > 500 } ?? false)
    }

    @Test func directionEdgesAreIgnoredOutsideMouseMode() {
        let harness = Harness(cursor: CGPoint(x: 500, y: 400))
        #expect(!harness.controller.handle(button: .left, edge: .down))
        #expect(!harness.controller.handle(button: .left, edge: .up))
        #expect(!harness.controller.handle(button: .left, edge: .down))
        #expect(harness.keys.isEmpty)
        #expect(harness.moves.isEmpty)
    }

    @Test func menuFallsThroughAndOnlyTheToggleExits() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        // Menu keeps its normal binding: not consumed, no clicks.
        #expect(!harness.controller.handle(button: .menu, edge: .down))
        #expect(!harness.controller.handle(button: .menu, edge: .up))
        #expect(harness.clicks.isEmpty)
        #expect(harness.controller.isActive)

        // Only the toggle binding exits the mode.
        #expect(harness.controller.toggle())
        #expect(!harness.controller.isActive)
        #expect(harness.states == [true, false])
        #expect(harness.tickCancelled)
    }

    @Test func backPressExitsTheModeAndItsReleaseFallsThrough() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        // One press of back leaves the mode and is consumed.
        #expect(harness.controller.handle(button: .back, edge: .down))
        #expect(!harness.controller.isActive)
        #expect(harness.states == [true, false])
        #expect(harness.tickCancelled)

        // The release arrives after the mode is gone: not consumed, nothing fired.
        #expect(!harness.controller.handle(button: .back, edge: .up))
        #expect(harness.clicks.isEmpty)
        #expect(harness.keys.isEmpty)
    }

    @Test func releaseWithoutAPressInsideTheModeDoesNotClick() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        // OK is already held when the mode is activated; its release arrives
        // inside the mode.
        #expect(harness.controller.activate())
        #expect(harness.controller.handle(button: .ok, edge: .up))
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.isEmpty)
        #expect(harness.keys.isEmpty)

        // The next real press and release is an ordinary single click.
        #expect(harness.controller.handle(button: .ok, edge: .down))
        #expect(harness.controller.handle(button: .ok, edge: .up))
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.map(\.0) == [.left])
    }

    @Test func shortPressOkClicksOnReleaseAtTheReleasePosition() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .ok, edge: .down))
        // Pressing OK alone never clicks immediately.
        #expect(harness.clicks.isEmpty)

        // The cursor may move while OK is held; the pending click remembers
        // where the cursor was at release time.
        harness.cursor = CGPoint(x: 700, y: 500)
        harness.advance(by: 0.125) // well below the 550 ms long-press duration
        #expect(harness.controller.handle(button: .ok, edge: .up))
        // The click stays pending for the double-tap window.
        #expect(harness.clicks.isEmpty)

        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.map(\.0) == [.left])
        #expect(harness.clicks.map(\.1) == [CGPoint(x: 700, y: 500)])
        #expect(harness.keys.isEmpty)
    }

    @Test func doubleTapOkPostsRightClickWithoutLeftClick() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        // First quick tap arms the pending left click.
        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .up))
        #expect(harness.clicks.isEmpty)

        // Second press inside the window cancels the left click.
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .up))
        #expect(harness.clicks.map(\.0) == [.right])
        #expect(harness.keys.isEmpty)

        // Nothing else fires later (no leftover pending left click).
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.map(\.0) == [.right])
    }

    @Test func secondPressHeldToLongPressSendsWithoutRightClick() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        // First quick tap.
        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .up))

        // Second press inside the window, held to the long-press duration.
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: MouseModeController.okLongPressDuration)
        harness.firePendingOperations()
        #expect(harness.keys.map(\.0) == [MouseModeController.returnKeyCode])
        #expect(harness.clicks.isEmpty)

        // Release after send: no right click, no further keys.
        #expect(harness.controller.handle(button: .ok, edge: .up))
        #expect(harness.clicks.isEmpty)
        #expect(harness.keys.count == 1)
    }

    @Test func secondPressOutsideTheWindowIsAnotherSingleClick() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .up))
        // Let the window expire: the pending left click fires.
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.map(\.0) == [.left])

        // A later quick tap is a fresh single click, not a double-tap.
        harness.advance(by: 0.5)
        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .up))
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.map(\.0) == [.left, .left])
        #expect(harness.keys.isEmpty)
    }

    @Test func deactivateCancelsAPendingOkClick() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        #expect(harness.controller.handle(button: .ok, edge: .up))
        harness.controller.deactivate(reason: "toggle_button")
        harness.advance(by: MouseModeController.doubleTapWindow)
        harness.firePendingOperations()
        #expect(harness.clicks.isEmpty)
        #expect(harness.keys.isEmpty)
    }

    @Test func longPressOkPostsReturnAndSuppressesClick() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: MouseModeController.okLongPressDuration)
        harness.firePendingOperations()
        #expect(harness.keys.map(\.0) == [MouseModeController.returnKeyCode])
        #expect(harness.keys.first?.1 == [])
        #expect(harness.clicks.isEmpty)

        // Releasing after the long press fired must not produce a click.
        #expect(harness.controller.handle(button: .ok, edge: .up))
        #expect(harness.clicks.isEmpty)
        #expect(harness.keys.count == 1)
    }

    @Test func deactivateCancelsAPendingOkLongPress() {
        let harness = Harness(cursor: CGPoint(x: 640, y: 360))
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .ok, edge: .down))
        harness.advance(by: 0.125)
        harness.controller.deactivate(reason: "back_button")
        harness.advance(by: MouseModeController.okLongPressDuration)
        harness.firePendingOperations()
        #expect(harness.keys.isEmpty)
        #expect(harness.clicks.isEmpty)
    }

    @Test func unmanagedButtonsFallThroughWhileActive() {
        let harness = Harness()
        #expect(harness.controller.activate())

        #expect(!harness.controller.handle(button: .home, edge: .down))
        #expect(!harness.controller.handle(button: .volumeUp, edge: .down))
        #expect(!harness.controller.handle(button: .tv, edge: .up))
        #expect(harness.moves.isEmpty)
        #expect(harness.clicks.isEmpty)
    }

    @Test func deactivateCancelsMovementAndTicking() {
        let harness = Harness()
        #expect(harness.controller.activate())
        #expect(harness.controller.handle(button: .left, edge: .down))

        harness.controller.deactivate(reason: "remote_disconnected")
        #expect(!harness.controller.isActive)
        #expect(harness.tickCancelled)

        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        #expect(harness.moves.isEmpty)
    }

    @Test func keyboardInjectorPostsMouseClicksAtTheCurrentPosition() {
        var posted: [KeyboardInjector.MouseClickButton] = []
        let poster: KeyboardInjector.MouseClickPoster = { posted.append($0) }

        #expect(KeyboardInjector.send(
            .mouseLeftClick,
            accessibilityTrusted: { true },
            keyPoster: { _, _ in },
            mouseClickPoster: poster
        ))
        #expect(KeyboardInjector.send(
            .mouseRightClick,
            accessibilityTrusted: { true },
            keyPoster: { _, _ in },
            mouseClickPoster: poster
        ))
        #expect(KeyboardInjector.send(
            .mouseMiddleClick,
            accessibilityTrusted: { true },
            keyPoster: { _, _ in },
            mouseClickPoster: poster
        ))
        #expect(posted == [.left, .right, .middle])

        #expect(!KeyboardInjector.send(
            .mouseLeftClick,
            accessibilityTrusted: { false },
            keyPoster: { _, _ in },
            mouseClickPoster: poster
        ))
        #expect(posted.count == 3)
    }

    @Test func mouseMoveActionsPostOneFixedStepPerPress() {
        var posted: [CGPoint] = []
        let poster: KeyboardInjector.MouseMovePoster = { posted.append(CGPoint(x: $0, y: $1)) }
        let actions: [ButtonAction] = [.mouseMoveUp, .mouseMoveDown, .mouseMoveLeft, .mouseMoveRight]
        for action in actions {
            #expect(KeyboardInjector.send(
                action,
                accessibilityTrusted: { true },
                keyPoster: { _, _ in },
                mouseMovePoster: poster
            ))
            // The move actions rely on hold-repeat to keep moving, so they
            // must allow repeat.
            #expect(action.allowsRepeat)
        }
        let step = KeyboardInjector.mouseMoveStep
        #expect(posted == [
            CGPoint(x: 0, y: -step),
            CGPoint(x: 0, y: step),
            CGPoint(x: -step, y: 0),
            CGPoint(x: step, y: 0),
        ])

        #expect(!KeyboardInjector.send(
            .mouseMoveUp,
            accessibilityTrusted: { false },
            keyPoster: { _, _ in },
            mouseMovePoster: poster
        ))
        #expect(posted.count == 4)
    }

    @Test func mouseModeToggleStaysAnAppInternalAction() {
        var posted: [KeyboardInjector.MouseClickButton] = []
        #expect(KeyboardInjector.send(
            .toggleMouseMode,
            accessibilityTrusted: { false },
            keyPoster: { _, _ in },
            mouseClickPoster: { posted.append($0) }
        ))
        #expect(posted.isEmpty)
        #expect(ButtonAction.toggleMouseMode.isAppInternal)
        #expect(!ButtonAction.toggleMouseMode.allowsRepeat)
    }

    @Test func newActionsHaveCategoriesDisplayNamesAndCodableRoundTrips() throws {
        #expect(ButtonAction.mouseLeftClick.category == .systemAndMedia)
        #expect(ButtonAction.mouseRightClick.category == .systemAndMedia)
        #expect(ButtonAction.mouseMiddleClick.category == .systemAndMedia)
        #expect(ButtonAction.toggleMouseMode.category == .systemAndMedia)
        #expect(ButtonAction.mouseMoveUp.category == .systemAndMedia)
        #expect(ButtonAction.mouseMoveDown.category == .systemAndMedia)
        #expect(ButtonAction.mouseMoveLeft.category == .systemAndMedia)
        #expect(ButtonAction.mouseMoveRight.category == .systemAndMedia)

        let localization = LocalizationStore(settings: AppSettings())
        for action in [
            ButtonAction.mouseLeftClick,
            .mouseRightClick,
            .mouseMiddleClick,
            .toggleMouseMode,
            .mouseMoveUp,
            .mouseMoveDown,
            .mouseMoveLeft,
            .mouseMoveRight,
        ] {
            #expect(!action.displayName(using: localization).isEmpty)
        }

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for action in [
            ButtonAction.mouseLeftClick,
            .mouseRightClick,
            .mouseMiddleClick,
            .toggleMouseMode,
            .mouseMoveUp,
            .mouseMoveDown,
            .mouseMoveLeft,
            .mouseMoveRight,
        ] {
            let data = try encoder.encode(action)
            #expect(try decoder.decode(ButtonAction.self, from: data) == action)
        }
    }

    // MARK: - 分模式键位（鼠标模式单独配置）

    @Test func configuredMouseModeBindingReplacesTheDefaultActionForAButton() {
        // 上键在鼠标模式里改成回车：按住不再移动光标，松开发回车。
        let harness = Harness(
            cursor: CGPoint(x: 500, y: 400),
            bindings: [.up: [.singleClick: .returnKey]]
        )
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .up, edge: .down))
        harness.advance(by: MouseModeController.tickInterval)
        harness.tick()
        #expect(harness.moves.isEmpty)

        #expect(harness.controller.handle(button: .up, edge: .up))
        #expect(harness.keys.map(\.0) == [MouseModeController.returnKeyCode])
    }

    @Test func mouseModeExitCanMoveToAnotherButton() {
        // 退出鼠标模式从返回键改到确定键单击；返回键停用后不再退出。
        let harness = Harness(
            cursor: CGPoint(x: 500, y: 400),
            bindings: [
                .ok: [.singleClick: .exitMouseMode],
                .back: [.singleClick: .disabled]
            ]
        )
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .back, edge: .down))
        #expect(harness.controller.handle(button: .back, edge: .up))
        #expect(harness.controller.isActive)
        #expect(harness.performedActions.isEmpty)

        #expect(harness.controller.handle(button: .ok, edge: .down))
        #expect(!harness.controller.isActive)
    }

    @Test func mouseModeBindingForwardsOtherActionsToTheExecutor() {
        // 鼠标模式里可以绑任意动作：非鼠标动作交给注入的执行器，模式保持激活。
        let harness = Harness(
            cursor: CGPoint(x: 500, y: 400),
            bindings: [.back: [.singleClick: .escape]]
        )
        #expect(harness.controller.activate())

        #expect(harness.controller.handle(button: .back, edge: .down))
        #expect(harness.controller.handle(button: .back, edge: .up))
        #expect(harness.performedActions.map(\.action) == [.escape])
        #expect(harness.controller.isActive)
    }

    @Test func mouseModeOnlyActionsAreOfferedOnlyInMouseMode() {
        let keyboard = ButtonAction.pickerActions(
            installedBundleIdentifiers: [],
            current: .disabled,
            experimentalContinuousRecordingEnabled: false
        )
        #expect(!keyboard.contains(.mouseCursorMove))
        #expect(!keyboard.contains(.exitMouseMode))

        let mouse = ButtonAction.pickerActions(
            installedBundleIdentifiers: [],
            current: .disabled,
            experimentalContinuousRecordingEnabled: false,
            mode: .mouse
        )
        #expect(mouse.contains(.mouseCursorMove))
        #expect(mouse.contains(.exitMouseMode))
    }

    @Test func selectedMouseModeOnlyActionStaysVisibleInKeyboardMode() {
        // 用户已经在鼠标模式里选过的内部动作，切到键盘模式时不能变成不可见的空选项。
        let actions = ButtonAction.pickerActions(
            installedBundleIdentifiers: [],
            current: .mouseCursorMove,
            experimentalContinuousRecordingEnabled: false
        )
        #expect(actions.contains(.mouseCursorMove))
    }

    private final class PendingOperation {
        var cancelled = false
        let operation: () -> Void

        init(_ operation: @escaping () -> Void) {
            self.operation = operation
        }

        func fire() {
            guard !cancelled else { return }
            operation()
        }
    }

    private final class Harness {
        var time: TimeInterval = 0
        var cursor: CGPoint?
        var bounds: CGRect
        var trusted: Bool
        var tickHandler: (() -> Void)?
        var tickCancelled = false
        var pendingOperations: [PendingOperation] = []
        var moves: [CGPoint] = []
        var clicks: [(KeyboardInjector.MouseClickButton, CGPoint)] = []
        var keys: [(CGKeyCode, CGEventFlags)] = []
        var states: [Bool] = []
        var performedActions: [ConfiguredButtonAction] = []
        var controller: MouseModeController!

        init(
            cursor: CGPoint? = CGPoint(x: 500, y: 400),
            bounds: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900),
            trusted: Bool = true,
            bindings: [RemoteButton: [ButtonTrigger: ButtonAction]] = [:]
        ) {
            self.cursor = cursor
            self.bounds = bounds
            self.trusted = trusted
            controller = MouseModeController(
                now: { [unowned self] in self.time },
                schedule: { [unowned self] _, operation in
                    // The first scheduled task is the 60Hz movement tick;
                    // later ones (e.g. the OK long-press timer) are pending ops.
                    if self.tickHandler == nil {
                        self.tickHandler = operation
                        self.tickCancelled = false
                        return MouseModeScheduledTask { [unowned self] in
                            self.tickCancelled = true
                        }
                    }
                    let pending = PendingOperation(operation)
                    self.pendingOperations.append(pending)
                    return MouseModeScheduledTask { pending.cancelled = true }
                },
                postMove: { [unowned self] point in
                    self.moves.append(point)
                    self.cursor = point
                },
                postClick: { [unowned self] button, point in
                    self.clicks.append((button, point))
                },
                keyPoster: { [unowned self] code, flags in
                    self.keys.append((code, flags))
                },
                cursorPosition: { [unowned self] in self.cursor },
                screenBounds: { [unowned self] in self.bounds },
                accessibilityTrusted: { [unowned self] in self.trusted },
                logger: { _ in }
            )
            controller.onStateChange = { [unowned self] in
                self.states.append($0)
            }
            // 分模式键位：默认值等于旧硬编码行为，这里可以把某个键改成用户配置的动作。
            if !bindings.isEmpty {
                controller.actionResolver = { button, trigger in
                    if let action = bindings[button]?[trigger] {
                        return ConfiguredButtonAction(action: action, shortcut: nil)
                    }
                    return AppSettings.defaultMouseModeAction(for: button, trigger: trigger)
                }
            }
            controller.performAction = { [unowned self] in
                self.performedActions.append($0)
            }
        }

        func advance(by delta: TimeInterval) {
            time += delta
        }

        func tick() {
            tickHandler?()
        }

        func firePendingOperations() {
            pendingOperations.forEach { $0.fire() }
        }
    }

    private final class FakeHIDTask: HIDRemoteScheduledTask {
        private(set) var isCancelled = false
        private let action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
        }

        func fire() {
            guard !isCancelled else { return }
            action()
        }
    }

    private final class FakeHIDScheduler: HIDRemoteScheduling {
        private(set) var tasks: [FakeHIDTask] = []

        func schedule(
            afterMilliseconds: UInt64,
            repeatingEveryMilliseconds: UInt64?,
            _ action: @escaping () -> Void
        ) -> HIDRemoteScheduledTask {
            let task = FakeHIDTask(action: action)
            tasks.append(task)
            return task
        }

        func fireAll() {
            tasks.forEach { $0.fire() }
        }
    }
}
