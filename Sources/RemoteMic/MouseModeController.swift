import AppKit
import CoreGraphics
import Foundation

struct MouseModeScheduledTask {
    private let cancellation: () -> Void

    init(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    func cancel() {
        cancellation()
    }

    static func repeatingOnMainRunLoop(
        interval: TimeInterval,
        operation: @escaping () -> Void
    ) -> MouseModeScheduledTask {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            operation()
        }
        RunLoop.main.add(timer, forMode: .common)
        return MouseModeScheduledTask { timer.invalidate() }
    }
}

final class MouseModeController {
    enum Phase: Equatable {
        case idle
        case active
    }

    static let tickInterval: TimeInterval = 1.0 / 60.0
    /// Caps the per-tick time delta so a stalled run loop reads as a pause
    /// instead of a multi-hundred-pixel jump.
    static let maximumTickDelta: TimeInterval = 0.05
    /// 标准档的双击窗口与长按时长。运行时用 `tuning()` 里的档位值，
    /// 这两个常量只给测试和默认实现当参照。
    static let doubleTapWindow: TimeInterval = MouseModeTuning.DoubleClickPreset.standard.duration
    static let okLongPressDuration: TimeInterval = MouseModeTuning.LongPressPreset.standard.duration
    static let returnKeyCode: CGKeyCode = 36

    static let directionButtons: Set<RemoteButton> = [.up, .down, .left, .right]
    /// Directions, OK and back are intercepted in mouse mode; menu, home,
    /// volume and every other key keep their normal bindings. Back and the
    /// toggle binding are the two ways out.
    static let managedButtons: Set<RemoteButton> = directionButtons.union([.ok, .back])

    typealias Scheduler = (TimeInterval, @escaping () -> Void) -> MouseModeScheduledTask
    typealias MovePoster = (CGPoint) -> Void
    typealias ClickPoster = (KeyboardInjector.MouseClickButton, CGPoint) -> Void
    typealias KeyPoster = (CGKeyCode, CGEventFlags) -> Void

    private let now: () -> TimeInterval
    private let schedule: Scheduler
    private let postMove: MovePoster
    private let postClick: ClickPoster
    private let keyPoster: KeyPoster
    private let cursorPosition: () -> CGPoint?
    private let screenBounds: () -> CGRect
    private let accessibilityTrusted: () -> Bool
    private let logger: (String) -> Void

    private(set) var phase: Phase = .idle
    private var pressedDirections = Set<RemoteButton>()
    private var movementStartedAt: TimeInterval?
    private var lastTickAt: TimeInterval?
    private var tickTask: MouseModeScheduledTask?
    /// 每个被按下的键的单击延迟任务：双击窗口内没有第二次按下时执行单击动作。
    private var pendingSingles: [RemoteButton: MouseModeScheduledTask] = [:]
    /// 每个被按下的键的长按任务。
    private var longPressTasks: [RemoteButton: MouseModeScheduledTask] = [:]
    /// 当前由本模式接管、正在按下的键。松开时只有这个集合里的键算数，
    /// 模式激活前就已经按下的键松开不触发任何动作。
    private var pressedButtons = Set<RemoteButton>()
    /// 双击窗口内第二次按下的键：松开时执行双击动作。
    private var secondPressButtons = Set<RemoteButton>()
    /// 长按已经触发的键：松开时不再补单击或双击。
    private var longFiredButtons = Set<RemoteButton>()

    /// 按鼠标模式的键位解析某个按键的某个触发；没有单独配置时回落到默认值。
    var actionResolver: (RemoteButton, ButtonTrigger) -> ConfiguredButtonAction = {
        AppSettings.defaultMouseModeAction(for: $0, trigger: $1)
    }
    /// 执行鼠标模式内部动作之外的动作（快捷键、组合动作、系统动作等）。
    var performAction: ((ConfiguredButtonAction) -> Void)?
    /// 鼠标模式的速度、加速时长、双击窗口与长按时长。每次取值都现读，
    /// 用户改完设置不用重进模式。
    var tuning: () -> MouseModeTuning = { .standard }

    var onStateChange: ((Bool) -> Void)?
    var isActive: Bool { phase == .active }

    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        schedule: @escaping Scheduler = MouseModeScheduledTask.repeatingOnMainRunLoop,
        postMove: @escaping MovePoster = { KeyboardInjector.postMouseMoved(to: $0) },
        postClick: @escaping ClickPoster = { KeyboardInjector.postMouseClick(button: $0, at: $1) },
        keyPoster: @escaping KeyPoster = { KeyboardInjector.postKey(code: $0, flags: $1) },
        cursorPosition: @escaping () -> CGPoint? = { CGEvent(source: nil)?.location },
        screenBounds: @escaping () -> CGRect = { MouseModeController.quartzScreenBounds() },
        accessibilityTrusted: @escaping () -> Bool = { KeyboardInjector.isAccessibilityTrusted },
        logger: @escaping (String) -> Void = AppLogger.shared.write
    ) {
        self.now = now
        self.schedule = schedule
        self.postMove = postMove
        self.postClick = postClick
        self.keyPoster = keyPoster
        self.cursorPosition = cursorPosition
        self.screenBounds = screenBounds
        self.accessibilityTrusted = accessibilityTrusted
        self.logger = logger
    }

    @discardableResult
    func activate() -> Bool {
        guard phase == .idle else { return true }
        guard accessibilityTrusted() else {
            logger("MOUSE MODE activate rejected reason=accessibility_untrusted")
            return false
        }
        phase = .active
        tickTask = schedule(Self.tickInterval) { [weak self] in
            self?.tick()
        }
        logger("MOUSE MODE activated")
        onStateChange?(true)
        return true
    }

    func deactivate(reason: String = "manual") {
        guard phase == .active else { return }
        tickTask?.cancel()
        tickTask = nil
        pendingSingles.values.forEach { $0.cancel() }
        pendingSingles.removeAll()
        longPressTasks.values.forEach { $0.cancel() }
        longPressTasks.removeAll()
        pressedButtons.removeAll()
        secondPressButtons.removeAll()
        longFiredButtons.removeAll()
        pressedDirections.removeAll()
        movementStartedAt = nil
        lastTickAt = nil
        phase = .idle
        logger("MOUSE MODE deactivated reason=\(reason)")
        onStateChange?(false)
    }

    @discardableResult
    func toggle() -> Bool {
        if phase == .active {
            deactivate(reason: "toggle_button")
            return true
        }
        return activate()
    }

    /// Returns true when the edge was consumed by mouse mode and must not reach
    /// gesture recognition or native passthrough.
    @discardableResult
    func handle(button: RemoteButton, edge: RemoteEventEdge) -> Bool {
        guard phase == .active, Self.managedButtons.contains(button) else { return false }
        switch edge {
        case .down:
            press(button)
        case .up:
            release(button)
        }
        return true
    }

    private func press(_ button: RemoteButton) {
        // 双击窗口内的第二次按下：取消待发的单击，改走双击动作。
        if let pending = pendingSingles.removeValue(forKey: button) {
            pending.cancel()
            secondPressButtons.insert(button)
        }
        pressedButtons.insert(button)
        longFiredButtons.remove(button)

        let action = actionResolver(button, .singleClick)
        if action.action == .mouseCursorMove, Self.directionButtons.contains(button) {
            directionPressed(button)
        }
        if action.action == .exitMouseMode {
            deactivate(reason: "back_button")
            return
        }

        let longAction = actionResolver(button, .longPress)
        guard longAction.action != .disabled else { return }
        longPressTasks[button] = schedule(tuning().longPress.duration) { [weak self] in
            guard let self, self.phase == .active else { return }
            self.longPressTasks.removeValue(forKey: button)?.cancel()
            self.longFiredButtons.insert(button)
            self.perform(longAction, button: button, trigger: .longPress)
        }
    }

    private func release(_ button: RemoteButton) {
        // 模式激活前就已经按下的键，松开不算数。
        guard pressedButtons.remove(button) != nil else { return }
        longPressTasks.removeValue(forKey: button)?.cancel()
        if Self.directionButtons.contains(button) {
            directionReleased(button)
        }
        if longFiredButtons.remove(button) != nil { return }

        if secondPressButtons.remove(button) != nil {
            let doubleAction = actionResolver(button, .doubleClick)
            if doubleAction.action != .disabled {
                perform(doubleAction, button: button, trigger: .doubleClick)
                return
            }
        }

        let singleAction = actionResolver(button, .singleClick)
        guard singleAction.action != .mouseCursorMove else { return }
        // 没有配双击动作时单击立即执行；配了才等双击窗口，避免单击和双击互相打断。
        guard actionResolver(button, .doubleClick).action != .disabled else {
            perform(singleAction, button: button, trigger: .singleClick)
            return
        }
        pendingSingles[button] = schedule(tuning().doubleClick.duration) { [weak self] in
            guard let self, self.phase == .active else { return }
            // 只有在窗口内没有第二次按下时才补发单击；被取消或已被双击消费时什么都不做。
            guard self.pendingSingles.removeValue(forKey: button) != nil else { return }
            self.perform(singleAction, button: button, trigger: .singleClick)
        }
    }

    /// 执行一个鼠标模式绑定：光标移动由按住状态驱动，退出模式、点击和回车
    /// 在本类内完成，其余动作交给注入的执行器。
    private func perform(_ configured: ConfiguredButtonAction,
                         button: RemoteButton,
                         trigger: ButtonTrigger) {
        switch configured.action {
        case .disabled:
            return
        case .mouseCursorMove:
            return
        case .exitMouseMode:
            deactivate(reason: "back_button")
        case .mouseLeftClick:
            click(.left, button: button, trigger: trigger)
        case .mouseRightClick:
            click(.right, button: button, trigger: trigger)
        case .mouseMiddleClick:
            click(.middle, button: button, trigger: trigger)
        case .returnKey:
            keyPoster(Self.returnKeyCode, [])
            logger("MOUSE MODE action button=\(button.rawValue) trigger=\(trigger.rawValue) action=returnKey")
        default:
            logger("MOUSE MODE action button=\(button.rawValue) trigger=\(trigger.rawValue) action=\(configured.action.rawValue)")
            performAction?(configured)
        }
    }

    private func click(_ which: KeyboardInjector.MouseClickButton,
                       button: RemoteButton,
                       trigger: ButtonTrigger) {
        guard let position = cursorPosition() else { return }
        postClick(which, position)
        logger("MOUSE MODE action button=\(button.rawValue) trigger=\(trigger.rawValue) action=mouseClick")
    }

    private func directionPressed(_ button: RemoteButton) {
        if pressedDirections.isEmpty {
            movementStartedAt = now()
            lastTickAt = nil
        }
        pressedDirections.insert(button)
    }

    private func directionReleased(_ button: RemoteButton) {
        pressedDirections.remove(button)
        if pressedDirections.isEmpty {
            movementStartedAt = nil
            lastTickAt = nil
        }
    }

    private func tick() {
        guard phase == .active else { return }
        guard !pressedDirections.isEmpty, let startedAt = movementStartedAt else {
            lastTickAt = nil
            return
        }
        let current = now()
        let elapsed = current - startedAt
        let delta = min(
            lastTickAt.map { current - $0 } ?? Self.tickInterval,
            Self.maximumTickDelta
        )
        lastTickAt = current
        guard delta > 0 else { return }

        let speed = Self.speed(afterHoldingFor: elapsed, tuning: tuning())
        var axisX = 0.0
        var axisY = 0.0
        if pressedDirections.contains(.left) { axisX -= 1 }
        if pressedDirections.contains(.right) { axisX += 1 }
        // CGEvent mouse locations use Quartz coordinates: +y moves down.
        if pressedDirections.contains(.up) { axisY -= 1 }
        if pressedDirections.contains(.down) { axisY += 1 }
        let length = (axisX * axisX + axisY * axisY).squareRoot()
        guard length > 0 else { return }

        let distance = speed * delta
        guard let origin = cursorPosition() else { return }
        let target = CGPoint(
            x: origin.x + axisX / length * distance,
            y: origin.y + axisY / length * distance
        )
        postMove(Self.clamped(target, to: screenBounds()))
    }

    /// Quadratic ease-in: 起步速度按档位给（标准档 161 px/s），爬到一个 `acceleration` 时长后
    /// 到达该档最快速度（标准档 1400 px/s）。
    static func speed(
        afterHoldingFor elapsed: TimeInterval,
        tuning: MouseModeTuning = .standard
    ) -> Double {
        let preset = tuning.speed
        let progress = min(max(elapsed / tuning.acceleration.duration, 0), 1)
        return preset.initialSpeed + (preset.maximumSpeed - preset.initialSpeed) * progress * progress
    }

    static func clamped(_ point: CGPoint, to bounds: CGRect) -> CGPoint {
        guard !bounds.isNull, !bounds.isEmpty else { return point }
        return CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX - 1),
            y: min(max(point.y, bounds.minY), bounds.maxY - 1)
        )
    }

    /// NSScreen frames use a bottom-left origin while CGEvent mouse locations
    /// use Quartz top-left display coordinates, so frames are flipped against
    /// the primary screen height before taking the union.
    static func quartzScreenBounds(
        screens: [NSScreen] = NSScreen.screens
    ) -> CGRect {
        guard let primaryHeight = screens.first?.frame.height else { return .null }
        return screens.reduce(CGRect.null) { partial, screen in
            let frame = screen.frame
            let quartz = CGRect(
                x: frame.origin.x,
                y: primaryHeight - frame.origin.y - frame.height,
                width: frame.width,
                height: frame.height
            )
            return partial.union(quartz)
        }
    }
}
