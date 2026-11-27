# 鼠标控制：移动 / 点击动作与鼠标模式

## 为什么开发

用户需要把遥控器变成简易鼠标：一是把"鼠标左键/右键/中键点击"作为预设动作绑定到任意按键；二是通过"鼠标模式"用方向键直接移动光标、OK 键点击，覆盖不便摸鼠标（演示、客厅、躺姿）的场景。

## 用户功能

- 按键映射的“系统与媒体”分组新增七个动作：鼠标左键、鼠标右键、鼠标中键、鼠标上移、鼠标下移、鼠标左移、鼠标右移。点击动作在光标当前位置点击一次；移动动作沿对应方向把光标移动 `KeyboardInjector.mouseMoveStep`（60 点），到屏幕边缘停住。都支持单击/双击/长按绑定，按住时沿用该按键原有的连发设置，不需要进入鼠标模式。
- 新增内部动作“切换鼠标模式”（不改变其他配置，绑定方式与其他动作相同）：
  - 进入后方向键按住即移动光标，速度按二次缓入曲线加速（160px/s 起步、约 1.2 秒达到 1400px/s，前 0.3 秒为精调区），支持斜向，屏幕边缘自动停止。
  - OK 键三手势（默认值，可在“按键 → 鼠标模式”里改成别的动作）：单击（快速松开后 300ms 内无第二击）= 松开时刻光标位置的左键点击；双击（第二次也快速松开）= 右键点击；任何一次按下按住 ≥550ms = 注入 Return（微信等聊天工具的发送消息），长按优先、触发后不再产生点击。只有在本模式内按下过的 OK，松开时才会产生点击。菜单键 = 正常绑定（不再拦截为右键）；返回键单击默认退出鼠标模式，它在模式内按鼠标模式配置执行；再次按切换键同样退出。切换键建议绑在非受管键（菜单 / TV / 主页 / 音量等）上。
  - 模式内方向键只移动光标：连续轻点、或轻点后立即按住，都不注入按键，也不把光标弹回（2026-11-27 起移除了按前台 App 分上下文的双击手势，见“验证状态”）。
  - 模式激活期间音量、主页等其他键保持原功能；菜单栏图标切换高亮样式提示当前处于鼠标模式，语音时长警告 / 严重状态比它更紧急，不被盖住。
  - 模式不持久化：遥控器断开、HID 监视器停止、App 退出时一律回到关闭。
- 鼠标模式只作用于实体遥控器 HID 链路；手机、Apple Watch、网页遥控不受模式影响，但其按键仍可绑定鼠标点击动作。

## 范围与非目标

- 不做屏幕浮窗 HUD；不实现拖拽（按住 OK 拖动）；不改变手机/手表/网页协议。
- 鼠标模式不持久化"激活状态"：App 重启、遥控器断开时一律回到关闭。

## 关键设计与涉及文件

- `Sources/RemoteMic/RemoteButtons.swift`：`ButtonAction` 新增 `mouseLeftClick`、`mouseRightClick`、`mouseMiddleClick`、`mouseMoveUp`、`mouseMoveDown`、`mouseMoveLeft`、`mouseMoveRight`、`toggleMouseMode`；点击与移动动作归入 `systemAndMedia`，最后一个为 `isAppInternal` 内部动作。
- `Sources/RemoteMic/KeyboardInjector.swift`：新增 `postMouseClick` 与 `postMouseMove(by:)`（每次移动 `mouseMoveStep` = 60 点，终点钳制到屏幕范围），复用 `.cghidEventTap` 注入与 `syntheticEventMarker` 标记、辅助功能权限检查；点击与移动都经 `send(..., mouseClickPoster:, mouseMovePoster:)` 分派。
- `Sources/RemoteMic/MouseModeController.swift`：新状态机（`idle`/`active`），60Hz 移动引擎（二次缓入：160px/s 起步，约 1.2 秒达到 1400px/s），坐标钳制到屏幕边界；受管键 = 方向键 + OK + 返回键。动作不再硬编码：`actionResolver` 按 `按键 + 单击/双击/长按` 取鼠标模式绑定（默认值见 `AppSettings.defaultMouseModeAction`），单击待决窗口复用 `HIDRemoteTiming.doubleClickMilliseconds`（300ms），长按判定复用 `HIDRemoteTiming.longPressMilliseconds`（550ms），未识别的动作交给 `performAction` 走常规执行链路。
- `Sources/RemoteMic/HIDRemoteMonitor.swift`：模式激活时在 `process(usages:)` 入口拦截方向 / OK / 返回键（菜单等其他键走正常绑定路径），不透传、不进入手势识别；原生键抑制与普通按键同一个判据（`shouldArmNativeEvent(for:)`）；监视器停止（`hid_monitor_stopped`）与设备断开（`remote_disconnected`）经 `onMonitoringEnded` 分别通知上层退出鼠标模式。
- `Sources/RemoteMic/BridgeAppModel.swift`：`toggleMouseMode` 经 `onInternalAction` 接线到控制器，驱动菜单栏图标状态。
- `Resources/*/Localizable.strings`：八个新动作的中英文案。
- `Tests/RemoteMicTests/MouseModeControllerTests.swift`：状态机、加速数学（注入时钟与事件 poster）、边界钳制、编解码。
- `Testing/MouseControlMode.md`：真实遥控器测试手册。

## 兼容边界

- `ButtonAction` 为字符串 raw 枚举 JSON 持久化：包含新动作的配置被旧版 App 读取时，本地绑定与设备 profile 会整体回退默认；旧版导入新版导出的配置会整体失败并报错（既有前向不兼容行为）。不配置新动作的用户不受任何影响。八个新动作的 raw 值在官方版里都不存在：只要在本地包里绑定过其中任何一个（包括“切换鼠标模式”），再装回官方版时全部自定义键位都会回退默认。
- 鼠标事件注入与键盘注入同样需要辅助功能权限；权限缺失时复用现有提示链路。
- 多遥控器共用同一个鼠标模式：任一遥控器断开都会立即退出模式（fail-safe）。方向键按住状态无法归属到具体设备，断开即清空是安全选择，避免设备切换后幻影移动。

## 验证状态

- 2026-08-22 单元测试（PR 原始实现，针对当时的行为，含后来移除的方向键双击手势）：`Tests/RemoteMicTests/MouseModeControllerTests.swift` 共 34 个用例（状态机进出、辅助功能权限缺失拒绝、方向 down/up 驱动移动、二次缓入加速锚点（t=0→160、t=0.6s→470、t=1.2s→1400、饱和 1400）、斜向归一化、屏幕边界钳制（钳到 maxX-1）、OK 三手势（单击待决 300ms 后左键/双击右键且不误触左键/第二击长按发送/窗口外第二击为再次单击/长按优先/deactivate 清待决）、菜单与返回键穿透且只有切换键退出、非管理键穿透、停用后取消 tick、点击注入与权限 guard、`toggleMouseMode` 内部动作边界、displayName/category/Codable 往返、tick delta 0.05s 上限、光标位置缺失时不移动不点击、HID 监视器 flush 清除幻影长按/双击/连发/非连发锁存、方向键双击分上下文（浏览器四方向、Safari/Helium 同表抽查、微信上下翻页、微信左右无动作、非目标 App 无动作且正常移动）、300ms 窗口内/外边界、第一次长按不构成轻点、单击超时无动作、模式外不响应），已通过。
- 2026-08-22 回归：ShortcutCaptureMonitorTests、VoiceFnTapSessionControllerTests、RemoteButtonGestureRecognizerTests、LocalizationTests（含中英文键一致性）以及 Self Test（42 项）均通过；合并运行共 61 项 swift-testing 用例全过。
- 2026-08-22 键位重设计：受管键从 {方向×4, OK, 菜单, 返回} 缩减为 {方向×4, OK}；菜单/返回键在模式内恢复正常绑定（HIDRemoteMonitor 拦截分支不变，仅 controller 的 managedButtons 与 handle 调整）；退出鼠标模式只剩切换键；OK 改为三手势状态机（单击待决左键 / 双击右键 / 长按 Return 发送，详见用户功能一节）。
- 2026-08-22 移动手感：速度曲线从线性（240→1200px/s，1s）改为二次缓入（160→1400px/s，1.2s，`speed = initial + (max-initial) × progress²`），前 0.3 秒为精调区；tick 积分、delta 上限、斜向归一化与边界钳制不变。此前的系统级 harness 位移实测值基于旧线性曲线，曲线常量的真机手感需重新验收。
- 2026-08-22 双击手势分上下文：方向键双击映射从全局（Page Up/Down、Command-[、Command-W）改为按实时前台 App 分派——浏览器集合（Chrome/Safari/Helium）用回顶部/回底部/后退/关闭标签页，微信用 Page Up/Page Down 且左右无动作，其他 App 双击完全无动作（不弹回不注入、第二次按下正常移动）；新增可注入 `frontmostBundleIdentifier`（默认读取 NSWorkspace 前台 App），弹回只在有动作时发生。
- 2026-08-22 复审修复：模式激活/退出两个时机冲刷 HID 在途输入状态（`flushInFlightInputState`，保留 activeUsages）；`HIDRemoteMonitor.stop()` 与 `disconnectSimulatedDevice()` 现在也会退出鼠标模式（覆盖权限回收/动作失败路径）；菜单栏图标在鼠标模式下使用独立无障碍文案与 `cursorarrow` 回退符号；坐标钳制到 maxX-1；光标位置取不到时跳过移动与点击。
- 本机工具链限制：当前机器只有 Swift 6.1（Xcode 16.4），仓库 Package 要求 6.2，因此 `xcrun swift build` / `swift test` 未在本机直接执行；上述测试是用手工链接的等效测试可执行文件（同一源码、同一 swift-testing 框架）跑过的，且整个 `RemoteMic` 模块（含 `BridgeAppModel` / `RemoteMicApp` 改动）已通过 `swiftc -typecheck`；仅 `SettingsView.swift` 因使用 macOS 26 SDK API 无法被本机 SDK 编译（既有现象，与本次改动无关）。CI（Swift 6.2）上的完整 `swift test` 仍待执行。
- 2026-08-22 真实系统级 harness（真实 CGEvent 注入、真实 60Hz 计时器、真实 NSScreen 边界）：左移 0.5s 实测 244px（理论 240px），右移 1.5s 实测 900px 并真实观察到屏幕右边界钳制，斜向两轴等距归一（244/√2≈172），OK 键真实左键注入、back 退出后 tick 停止且光标零位移，测试后光标恢复原位，全部断言通过。注意：该 harness 跑的是钳制改为 maxX-1 之前的构建，差异仅 1px，不影响其结论。
- 真机验收：未执行。真实遥控器 HID 边沿输入、移动手感、点击落点、模式拦截、图标切换、多显示器与稳定功能回归需按 `Testing/MouseControlMode.md` 完成人工验收。
- 2026-11-26 移植记录（PR #150 → main `dd19060e`，仅本地工作区，未提交）：HID 在途状态冲刷改用 main 已有的 `HIDRemoteMonitor.cancelPendingButtonActions()`，原 `flushInFlightInputState()` 未移植；鼠标点击经 main 的 `KeyboardInjector.send(..., mouseClickPoster:)` 分派；菜单栏图标经 `StatusItemPresentation.mouseMode` 呈现（`RemoteMicApp.refreshStatusItemPresentation()`），回退符号沿用状态栏现有的 `mic.fill`，未使用 `cursorarrow`。公开模式 debug 构建（`xcrun swift build --disable-keychain`）通过；测试结果见 `Testing/MouseControlMode.md` 末尾的本地验证记录。
- 2026-11-27 稳定性复审后的改动（仅本地工作区，未提交；上游已在 2026-11-26 以“改为动作级的鼠标移动 / 点击动作、不再引入鼠标模式”为由把 PR #150 关闭为 superseded）：
  - 移除方向键双击分上下文手势。它在第二次按下的瞬间就注入 Command-W / Command-[，“轻点后按住”会误关标签页、误后退，并把光标弹回。OK 三手势保留。
  - OK 增加按下状态跟踪：不是在本模式内按下过的 OK，松开不再补一个左键。
  - 返回键按下即退出鼠标模式（`back_button`）。退出键绑在双击上时，双击稍慢就是两次普通动作，多一个单击就能退出的键更稳；代价是模式内返回键不再执行自己的绑定。
  - 鼠标分支的原生键抑制改用与普通按键相同的判据 `shouldArmNativeEvent(for:)`。映射已生效时不再为每个边沿多开 0.5 秒抑制窗口，避免吞掉实体键盘的同码按键。
  - 日志原因写准：监视器停止记 `hid_monitor_stopped`，设备断开记 `remote_disconnected`；进出模式时结束 App 切换器的原因记 `mouse_mode_entered` / `mouse_mode_exited`（原来固定记 `common_phrases_opened`）。
  - 菜单栏图标：鼠标模式不再盖住语音时长警告 / 严重状态（`StatusItemPresentation.resolvingMouseMode(base:isMouseModeActive:)`）。
  - 按维护者的动作级方向新增四个“鼠标移动”动作 `mouseMoveUp` / `mouseMoveDown` / `mouseMoveLeft` / `mouseMoveRight`（raw 值自定，上游尚无对应 PR）：每次沿该方向移动 60 点，到屏幕边缘停住，按住沿用按键原有的连发设置，不需要进入鼠标模式。
  - 未采纳 PR 评论里的另外两条：光标光环（纯界面功能，多显示器风险大）和“两份按键数据会被覆盖”（本机未复现）。
  - 本轮验证：Debug `xcrun swift build --disable-keychain` 通过；`MouseModeControllerTests` 28 项、`StatusItemPresentationTests` 通过；全量 `xcrun swift test --disable-keychain` 1730 项，只有依赖测试进程辅助功能授权的 `RemoteButtonsTests.reportsFinalResultThroughCompletion` 未通过（与鼠标功能无关）。随后按用户要求打包安装为构建号 444（公开模式、ad-hoc 签名，`~/Applications/SayAll.app`）。实体遥控器已观察到 TV 键双击进入鼠标模式和再次双击退出，其余真实遥控器验收未做，见 [`Testing/MouseControlMode.md`](../../Testing/MouseControlMode.md) 的本地验证记录。

## 键盘模式 / 鼠标模式分模式键位（2026-11-27）

用户反馈：同一颗键在两种模式下做的事不同（确定键在键盘模式是回车、在鼠标模式是左键），界面只有一套键位，既看不出也改不了，还分不清当前处于哪种模式。改为把“模式”做成键位的一维，并显式展示。

- 按键页在页头下方新增模式横带：左侧两段开关切换**正在编辑**的模式，右侧胶囊实时显示**正在运行**的模式。编辑态和运行态可以不同，所以两者分开显示。
- 鼠标模式用橙色作为模式色（`SettingsView.mappingModeAccent`）：选中段填充、运行态胶囊、鼠标模式下的动作文字、六个可配卡片的淡底与描边，以及选中态卡片自己的底色与描边；键盘模式沿用系统主题色，共用键位的卡片保持中性，按键名图标不随模式变色。
- 只有 6 个键分模式：上、下、左、右、确定、返回（`AppSettings.mouseModeButtons`）。其余 6 个键在鼠标模式里继续用键盘键位，卡片上显示“两种模式共用”。
- 鼠标模式的默认值等于引入分模式之前硬编码的行为：方向键单击 = 光标移动，确定单击 = 鼠标左键、双击 = 鼠标右键、长按 = 回车，返回单击 = 退出鼠标模式，其余触发 = 无动作。鼠标模式额外提供两个只在该模式可选的动作：`mouseCursorMove`（按住按加速曲线移动）与 `exitMouseMode`（退出）。改过的键位在编辑器里有“恢复默认”。
- 鼠标模式没有“按住时”入口：方向键按住就是连续移动，不给按键单独配按住；按住面板、按住筛选胶囊在该模式下不出现。
- 鼠标模式不进键位方案作用域（`editingMappingProfileID` 在切换模式时清空），只写基础键位；`mouseCursorMove` / `exitMouseMode` 不下发给手机端与键位方案。
- 存储：`UnifiedButtonBinding` 增加 `mode` 字段（`keyboard` / `mouse`），旧数据与旧导出 JSON 缺该字段时按 `keyboard` 解码。键盘键位的全部读写路径都加了 `mode == .keyboard` 过滤，鼠标绑定不会漏进键盘键位、不算显式键盘配置、也不参与键位方案迁移的冲突判断。
- 涉及文件：`Sources/RemoteMic/ButtonBindingConfiguration.swift`（`MappingMode`、`UnifiedButtonBinding.mode`）、`Sources/RemoteMic/AppSettings.swift`（`mouseModeButtons`、`defaultMouseModeAction`、`configuredMouseModeAction`、`setMouseModeBinding`、`resetMouseModeBinding`、各键盘路径的 `mode` 过滤）、`Sources/RemoteMic/MouseModeController.swift`（`actionResolver` / `performAction`）、`Sources/RemoteMic/BridgeAppModel.swift`（接线到 `performExternalConfiguredAction`）、`Sources/RemoteMic/SettingsView.swift`（`mappingMode`、模式横带、按模式解析与写入、编辑器恢复默认）、`Sources/RemoteMic/RemoteMappingCanvas.swift`（`showsHoldChip`、`modeBadge`）、`Resources/*/Localizable.strings`。
- 兼容边界：新增的 `mode` 字段对旧版 App 是未知字段，旧版读到的鼠标绑定会被当成键盘绑定（升级回旧版时鼠标模式绑定会污染键盘键位），这是既有前向不兼容行为的一部分；两个新模式动作的 raw 值在官方版不存在，装回官方版仍会整体回退全部自定义键位。

### 鼠标模式参数（2026-11-27 追加）

用户接着问“为什么鼠标模式没有单独的按住时，比如光标移动速度什么的”。方向键按住本来就是连续移动，按住面板会和它抢语义，所以不补按住入口；真正的缺口是速度写死在 `MouseModeController` 里。改为模式级三档预设：

- `Sources/RemoteMic/MouseModeTuning.swift`：最高速度（慢 600 / 标准 1400 / 快 2200 点每秒，起步 80 / 160 / 250）、加速时长（0.4 / 1.2 / 2.4 秒）、双击间隔（0.2 / 0.3 / 0.45 秒）、长按时长（0.4 / 0.55 / 0.8 秒），默认全标准，`static let standard` 就是引入设置前的固定参数。
- `MouseModeController` 删掉硬编码的 `maximumSpeed` / `initialSpeed` / `accelerationDuration`，改为读 `tuning()`；`speed(afterHoldingFor:tuning:)` 保留二次缓入曲线，两处窗口（待发单击、长按）也从 `tuning()` 取。`static let doubleTapWindow` / `okLongPressDuration` 保留为“标准档”常量供单测引用。
- `AppSettings.mouseModeTuning`（`UserDefaults` 键 `mouseModeTuning`）持久化，`BridgeAppModel` 在创建控制器时注入。不进键位绑定，也不进便携配置。
- 界面：鼠标模式下模式切换右侧出现“鼠标设置”，弹出四行分段控件加“恢复默认”；键盘模式不出现。
- 本轮验证：Debug `xcrun swift build --disable-keychain` 通过；`MouseModeControllerTests` + `ButtonBindingConfigurationTests` 57 项、含按键页回归在内 195 项通过；全量连跑两次都在已执行用例全部通过后被测试进程 SIGSEGV 终止（故障线程 `SayAll.EventTap`，同一签名在本次改动之前的两份崩溃报告里已出现，判断为测试进程残留事件 tap 收到真实键盘输入，与本次改动无关），两次日志合并覆盖 1739 / 1743 个用例函数，剩余 4 个 `SupplementalSettingsIntegrationTests` 用例单跑全部通过，合计 1743 项无失败行。已安装构建号 446，并在真实窗口（1213 × 856）核对模式横带、鼠标模式卡片内容与“两种模式共用”标记；生产最小窗口 `1067 × 760` 的真实窗口核对与实体遥控器验收未做。
