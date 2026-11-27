import Foundation

/// 鼠标模式的运行参数。四组都用三档预设：滑杆能调出任何手感，却调不出可复现的一套，
/// 而这几项只在“按住方向键移光标”和“确定键手势”上起作用，档位够用。
struct MouseModeTuning: Codable, Equatable {
    /// 光标最快速度。起步速度按最快速度的固定比例给，慢档也不会起步就飞。
    enum SpeedPreset: String, Codable, CaseIterable, Identifiable {
        case slow
        case standard
        case fast

        var id: String { rawValue }
        var localizationKey: String { "mouse_tuning.speed.\(rawValue)" }

        /// 点 / 秒。
        var maximumSpeed: Double {
            switch self {
            case .slow: return 600
            case .standard: return 1400
            case .fast: return 2200
            }
        }

        /// 起步速度，点 / 秒。慢档也不会一按就飞。
        var initialSpeed: Double {
            switch self {
            case .slow: return 80
            case .standard: return 160
            case .fast: return 250
            }
        }
    }

    enum DurationPreset: String, Codable, CaseIterable, Identifiable {
        case short
        case standard
        case long

        var id: String { rawValue }
        var localizationKey: String { "mouse_tuning.duration.\(rawValue)" }
    }

    /// 加速时长：从起步速度爬到最快速度要多久。
    enum AccelerationPreset: String, Codable, CaseIterable, Identifiable {
        case short
        case standard
        case long

        var id: String { rawValue }
        var localizationKey: String { DurationPreset(rawValue: rawValue)?.localizationKey ?? rawValue }

        var duration: TimeInterval {
            switch self {
            case .short: return 0.4
            case .standard: return 1.2
            case .long: return 2.4
            }
        }
    }

    /// 确定键两次按下合成右键的窗口。
    enum DoubleClickPreset: String, Codable, CaseIterable, Identifiable {
        case short
        case standard
        case long

        var id: String { rawValue }
        var localizationKey: String { DurationPreset(rawValue: rawValue)?.localizationKey ?? rawValue }

        var duration: TimeInterval {
            switch self {
            case .short: return 0.2
            case .standard: return Double(HIDRemoteTiming.doubleClickMilliseconds) / 1000
            case .long: return 0.45
            }
        }
    }

    /// 按住多久算长按（默认动作是发送回车）。默认值与键盘手势的长按一致。
    enum LongPressPreset: String, Codable, CaseIterable, Identifiable {
        case short
        case standard
        case long

        var id: String { rawValue }
        var localizationKey: String { DurationPreset(rawValue: rawValue)?.localizationKey ?? rawValue }

        var duration: TimeInterval {
            switch self {
            case .short: return 0.4
            case .standard: return Double(HIDRemoteTiming.longPressMilliseconds) / 1000
            case .long: return 0.8
            }
        }
    }

    var speed: SpeedPreset = .standard
    var acceleration: AccelerationPreset = .standard
    var doubleClick: DoubleClickPreset = .standard
    var longPress: LongPressPreset = .standard

    /// 引入设置之前的固定参数，也是“恢复默认”的目标值。
    static let standard = MouseModeTuning()
}
