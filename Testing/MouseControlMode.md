# 鼠标控制（移动 / 点击动作与鼠标模式）测试手册

## 适用范围

- 功能分支：含鼠标控制功能的候选构建（对应功能设计见 `feature/mouse-control/README.md`）。
- 功能状态：已实现并通过单元测试；**真实遥控器人工验收尚未执行**，本手册全部用例在真机通过前不得标记为完成。
- 测试目标：验证“鼠标左键 / 右键 / 中键”三个预设动作、“鼠标上移 / 下移 / 左移 / 右移”四个移动动作和“切换鼠标模式”内部动作在真实小米遥控器（RC001/RC003）上的行为。
- 本手册不把单元测试、构建成功或模拟按键等同于真机验收。

## 测试前准备

1. 退出其他已安装的无线麦版本，运行本次提供的测试包。
2. 在“系统设置 → 隐私与安全性”中确认无线麦已获得：
   - 辅助功能权限（鼠标事件注入必需；缺失时动作不执行并在日志中留下失败记录）。
   - 输入监控权限。
3. 打开无线麦“按键映射”页面，开启“自定义按键映射”，连接真实遥控器。
4. 准备一个可随时关闭的测试窗口（如 TextEdit 空白文档）用于观察点击效果。
5. 多显示器环境（如有）留到用例 6 再接入；先用单显示器完成用例 1～5。

## 用例 1：鼠标点击预设动作

1. 把“主页键双击”绑定为“鼠标左键”（“系统与媒体”分组内直接选择，无长下拉列表）。
2. 把光标移动到 TextEdit 文档中部，用遥控器双击主页键。
3. 依次改绑“鼠标右键”“鼠标中键”，重复触发。
4. 把某按键的“单击”绑定为“鼠标左键”，按住不放观察连发。

预期结果：

- 每次触发都在光标当前位置产生一次对应点击：左键产生普通点击，右键弹出上下文菜单，中键在支持的 App 中产生中键行为。
- 光标位置本身不移动。
- 按住绑定了单击鼠标动作的按键会产生连续点击（与方向键连发策略一致）。
- 音量、主页等其他未改绑按键行为不变。

失败判定：点击发生在错误位置、按键类型错误（如左键绑定点出右键菜单）、触发后无线麦 HID 监控停止，或触发一次后按键不再响应。

## 用例 1B：鼠标移动预设动作（2026-11-27 新增）

1. 把某按键的“单击”绑定为“鼠标右移”（“系统与媒体”分组），按一下，再按住不放。
2. 依次改绑“鼠标上移”“鼠标下移”“鼠标左移”，各按一下。
3. 把光标移到屏幕最右边缘后继续触发“鼠标右移”。
4. 给一个关闭了“按住重复”的按键绑定“鼠标左移”，按住不放。

预期结果：

- 每按一下，光标沿对应方向移动 60 点（“上移”朝屏幕上方），不产生点击，其他方向不位移。
- 按住时按该按键原有的连发设置连续移动；关闭了“按住重复”的按键只移动一次。
- 到屏幕边缘后停住，不越出屏幕。
- 不需要进入鼠标模式；在鼠标模式内绑到非受管键（如菜单键）上同样生效。

失败判定：方向相反、“上移 / 下移”颠倒、一次移动的距离明显不是 60 点、产生了点击、按住时不连发，或光标越出屏幕。

## 用例 2：进入与退出鼠标模式

1. 把“菜单键双击”绑定为“切换鼠标模式”（“系统与媒体”分组，与鼠标点击、鼠标移动动作同组）。
2. 双击菜单键进入鼠标模式。
3. 观察菜单栏图标。
4. 再双击菜单键（切换键）退出。
5. 重新进入鼠标模式，按一下返回键。
6. 菜单栏图标出现语音时长警告 / 严重样式时进入鼠标模式（可借用 RC003 的 60 秒会话，在第 53 秒后操作）。

预期结果：

- 进入模式后菜单栏图标切换为高亮样式（与语音激活时相同的高亮图标），退出后恢复普通样式。
- 退出鼠标模式有两种方式：再次按切换键，或按一下返回键。返回键在模式内被鼠标模式接管，不执行它自己的绑定（例如“退格”不删字符）；菜单键在模式内执行自己的绑定，不被拦截。
- 语音时长警告 / 严重样式优先于鼠标模式高亮，不被鼠标模式盖住；会话结束后回到鼠标模式高亮。

失败判定：模式无法进入、既不能用切换键也不能用返回键退出、图标不切换、退出后图标仍保持高亮、模式内返回键执行了原绑定（例如删掉了一个字符）、菜单键在模式内被鼠标模式吞掉、警告 / 严重样式被鼠标模式盖住。

## 用例 3：鼠标模式内移动与点击

1. 进入鼠标模式。
2. 短按一下方向右键立即松开；再按住方向右键约 3 秒不松。
3. 同时按住“右 + 下”观察斜向移动。
4. 把光标移动到屏幕最右边缘后继续按住右键。
5. 把光标移到 TextEdit 文档上：短按 OK（快速松开，0.3 秒内不再按）应产生左键点击；快速双击 OK 应产生右键点击（弹出上下文菜单）；长按 OK 超过 0.55 秒应注入 Return（在聊天窗口中等于发送消息）。在桌面图标上按菜单键（菜单键已恢复正常绑定）。
6. 连续快速轻点方向右键两三次；再轻点一下方向右键后立即按住。
7. 在 Safari 或 Chrome 里重复第 6 步。
8. 按住 OK 不放，保持按住时用切换键进入鼠标模式，然后松开 OK。

预期结果：

- 短按只产生很小的位移；按住时移动按二次缓入曲线加速（约 1.2 秒内从 160px/s 加速到 1400px/s，前 0.3 秒为精调区，起步更慢更稳），松手立即停止。
- 斜向移动为 45° 方向，速度与单方向相当（不会因为两个方向叠加而翻倍）。
- 光标到达屏幕边缘后停止，不会越出屏幕或跳到异常位置。
- OK 键三手势：单击 = 松开时刻光标位置的左键点击（延迟约 0.3 秒待决窗口后触发）；双击（第二次也快速松开）= 右键点击，且不会先触发左键；任何一次按下按住到 0.55 秒 = 注入 Return，长按优先生效，触发后该次松开不再产生点击；第二次按下落入 0.3 秒窗口但按住到 0.55 秒 = 发送而非右键。
- 菜单键在模式内执行自己的绑定（与其他未受管键一致），不产生鼠标点击；返回键按一下即退出（见用例 2）。
- 连续轻点、轻点后按住都只移动光标：不注入任何按键，光标不弹回；在浏览器里不会关闭标签页（Command-W）、后退（Command-[）或跳到页面顶部 / 底部。
- 进入模式前就已按住的 OK，松开时不产生点击；之后正常的按下 / 松开才是左键单击。
- 模式激活期间方向键与 OK 键不再执行它们原本绑定的动作，也不会把方向键透传给前台 App（前台文本光标不应移动）。

失败判定：移动抖动、反向、加速突兀或停止后仍漂移；边缘越过屏幕；模式内方向键同时触发了原绑定动作或前台 App 收到方向键；OK 单击误发送 Return、长按误点击、双击先出左键再出右键、第二击窗口外误判为双击；菜单键被鼠标模式吞掉；快速连按方向键导致前台 App 收到按键（如标签页被关闭、页面后退）或光标弹回；进入模式前按住的 OK 在松开时产生了点击。

## 用例 4：模式内其他键保持原功能

1. 进入鼠标模式。
2. 按音量 + / −、主页键、TV 键。

预期结果：音量键、主页键、TV 键按各自绑定正常执行，不受鼠标模式影响。

失败判定：这些键被鼠标模式吞掉，或它们触发了鼠标移动 / 点击。

## 用例 5：断开与重启自动退出

1. 进入鼠标模式后关闭遥控器电源（或令其蓝牙断开）。
2. 重新连接遥控器，直接按方向键。
3. 进入鼠标模式后彻底退出无线麦 App，再重新启动。

预期结果：

- 遥控器断开后鼠标模式自动退出，菜单栏图标恢复普通样式；日志中出现 `MOUSE MODE deactivated reason=remote_disconnected`。改动设置或权限回收导致 HID 监视器停止时，日志里是 `reason=hid_monitor_stopped`，同样退出。
- 重连后方向键立即恢复执行原绑定动作，不会继续移动鼠标。
- App 重启后鼠标模式为关闭状态（激活状态不持久化）。

失败判定：断开后模式残留、重连后方向键仍驱动鼠标、重启后图标错误保持高亮。

## 用例 6：多显示器（有条件时执行）

1. 接入第二台显示器（任意排列方式），进入鼠标模式。
2. 用方向键把光标从主屏移动到副屏，再移回。

预期结果：光标可以进入副屏并在副屏边界停止；不会卡在两屏之间或跳到错误坐标。

失败判定：光标无法进入副屏、进入副屏后消失，或坐标错乱。

## 用例 7：键盘模式 / 鼠标模式分模式键位（2026-11-27 新增）

准备：已安装含分模式键位的测试包；实体遥控器已连接；辅助功能与输入监控已授权。

步骤：

1. 打开“按键”页。页头下方出现模式横带：左侧两段开关为“键盘模式 / 鼠标模式”（选中的一段填充颜色：键盘模式是系统主题色，鼠标模式是橙色），右侧胶囊显示“当前：键盘模式”。
2. 切到“鼠标模式”。右侧胶囊不变（运行态仍是键盘模式）；画布仍显示 12 个按键卡片，筛选胶囊里没有“按住”；上、下、左、右、确定、返回六张卡片的动作文字、淡底和描边变橙色，按键名图标不变。
3. 看“确定”卡片：三格分别是“鼠标左键 / 鼠标右键 / 回车”，且不是“两种模式共用”。
4. 看“菜单”卡片：卡片右上显示“两种模式共用”，三格是键盘键位。
5. 点“确定”的单击格，在动作编辑器里改成一个别的动作（例如“回车”），保存后卡片显示新动作，编辑器出现“恢复默认”。
6. 切回“键盘模式”。确定卡片恢复为键盘键位（回车），菜单卡片不再显示“两种模式共用”。
7. 按切换鼠标模式的按键进入鼠标模式。右侧胶囊变成“当前：鼠标模式”并变橙色。
8. 用鼠标模式里改过的那个动作验证：确定键执行第 5 步设置的动作，而不是左键。
9. 点“恢复默认”，退出再进入鼠标模式，确定单击回到左键点击。

预期结果：编辑态（两段开关）和运行态（胶囊）分开显示，鼠标模式用橙色给动作文字、淡底、描边以及选中态上色；六个受管键（上、下、左、右、确定、返回）在两个模式下各自保存；其余六键标“两种模式共用”；鼠标模式没有“按住”入口；改过的鼠标模式动作在模式内生效，且不影响键盘模式的键位。

失败判定：切换模式后仍看到同一套键位；鼠标模式显示“按住”筛选或按住面板；改了鼠标模式动作后键盘键位一起变；恢复默认无效；胶囊显示的运行态与实际不符。

日志与配置：动作执行仍走 `HID BUTTON button=<raw> trigger=<trigger> action=<rawValue>`；`action=mouseCursorMove` / `exitMouseMode` 只应出现在鼠标模式内。绑定存于 `defaults read com.hd838a.RemoteMic unifiedBaseBindings`，鼠标模式条目的 `mode` 为 `mouse`，键盘键位条目 `mode` 为 `keyboard` 或缺省。

## 用例 8：鼠标模式参数三档预设（2026-11-27 新增）

准备：同用例 7；当前停在“按键”页的鼠标模式。

步骤：

1. 键位模式右侧出现“鼠标设置”，点开弹出四行分段控件：最高速度（慢 / 标准 / 快）、加速时长（短 / 标准 / 长）、双击间隔（短 / 标准 / 长）、长按时长（短 / 标准 / 长），底部是“恢复默认”。默认全部“标准”时“恢复默认”不可点。
2. 切回“键盘模式”，“鼠标设置”入口消失。
3. 回到鼠标模式，把最高速度改成“快”、加速时长改成“短”，进入鼠标模式按住下键 2 秒：光标应比标准档更快、且 0.4 秒内就到最快速度。
4. 把长按时长改成“长”（0.8 秒），在鼠标模式里按住确定键 0.6 秒后松开：不应触发回车；按满 1 秒再松开应触发回车。
5. 点“恢复默认”，四项回到“标准”；再重复第 3 步，速度回到改之前的观感。
6. 退出并重开 App，重新打开“鼠标设置”：档位仍在。

预期结果：四项只在鼠标模式内出现；改动立即影响光标移动与确定键手势；换档案、换设备都不改变它们；重开 App 后保留。

失败判定：键盘模式下也出现“鼠标设置”；改档后速度/窗口无变化；改动在重开 App 后丢失；恢复默认无效。

日志与配置：档位存于 `defaults read com.hd838a.RemoteMic mouseModeTuning`（JSON，四个键 `speed` / `acceleration` / `doubleClick` / `longPress`）；不进 `unifiedBaseBindings`，也不出现在导出的便携配置里。

## 稳定功能回归项

以下用例必须在同一测试包上重新通过（可参照各自既有手册）：

- 普通语音链路：按住语音键 → 说话 → 松开，第三方语音工具收到完整音频（`STREAM_START → AUDIO → STREAM_STOP`）。
- 自定义快捷键录入与执行（含 Command + Space 唤起 Spotlight）。
- 打开具体 APP 与自定义 APP 聚焦。
- 持续录音开关（如已启用实验开关）。
- 左右键原生透传：把左 / 右键绑定为方向左 / 右且无双击长按辅助动作时，在前台 App 按住可连续移动光标。
- 手机 / 网页遥控：手机端绑定“鼠标左键”后触发，应在 Mac 光标处点击（切换鼠标模式不影响手机按键的原有解析）。

## 日志收集

- 菜单栏菜单 → “打开日志所在文件夹”，收集测试时间段的日志文件。
- 关键日志标记：`MOUSE MODE activated`、`MOUSE MODE deactivated reason=toggle_button|back_button|remote_disconnected|hid_monitor_stopped`、`MOUSE MODE double_tap_ok`（OK 双击注入右键）、`MOUSE MODE long_press_send`（长按 OK 注入 Return）、`HID APP SWITCHER ended reason=mouse_mode_entered|mouse_mode_exited`（进出模式时结束 App 切换器）、`HID BUTTON ... action=mouseLeftClick/mouseRightClick/mouseMiddleClick/mouseMoveUp/mouseMoveDown/mouseMoveLeft/mouseMoveRight/toggleMouseMode`、`INTERNAL ACTION ignored_by_keyboard`（手机 / 网页来源触发内部动作时不应出现 mouse 模式误拦截）。
- 日志不包含语音内容；提交反馈前无需额外脱敏，但不要公开发布含本机路径的完整日志。
- 真机验收时若 TV 键仍有 § 泄漏到焦点输入框，先确认当前测试包包含 TV 键码修复（nativeEvent keyCode=10，`fix/tv-native-keycode` 分支，本地测试包已叠加该修复）。

## 验证边界

- 已完成的自动化验证：`MouseModeControllerTests`（状态机、方向边沿驱动、加速数学、斜向归一化、边界钳制、按模式绑定解析与执行、OK 三手势与按下状态跟踪、菜单穿透、返回键默认退出、快速连按方向键只移动不注入、模式外不响应、HID 监视器把受管键交给鼠标模式、点击与移动注入及权限缺失拒绝、八个新动作的 displayName / category / Codable 往返）、`ButtonBindingConfigurationTests`（鼠标模式键位与键盘键位互不影响、`mode` 缺省按键盘模式解码）、`SettingsPageRegressionTests`（按键页模式横带位置与页头紧凑布局）、`StatusItemPresentationTests`（鼠标模式不盖住警告 / 严重状态）、本地化键一致性、既有 ShortcutCaptureMonitor / 手势识别 / Fn 会话回归。
- 自动化不能覆盖的部分：真实遥控器的 HID 边沿拦截、事件抑制器对方向键原生事件的抑制、真实光标移动手感、鼠标移动动作每次 60 点的位移手感、菜单栏图标真实渲染、多显示器坐标。
- **真机验收状态：全部用例均未经真实遥控器与真实用户环境验证。** 在完成用例 1、1B、2～7 和回归项前，本功能不得出现在正式版发布说明中。

## 本地验证记录（2026-11-26，移植到 `main` `dd19060e`，公开构建）

本轮是个人自用的本地移植，改动只在本地工作区，未提交、未推送。运行环境：Apple Silicon（arm64），macOS 27.0.1，Swift 6.4.2，公开模式（`SAYALL_BUILD_CHANNEL=public`，没有私有组件）。与原 PR 的差异见 [`feature/mouse-control/README.md`](../feature/mouse-control/README.md) 的移植记录。

自动化结果：

- `xcrun swift build --disable-keychain`（Debug、Release）：通过。
- `MouseModeControllerTests`：35 项通过，含移植时新增的 `hidMonitorHandsManagedEdgesToMouseModeAndSkipsConfiguredActions`，以及改用 `cancelPendingButtonActions()` 的 `hidMonitorFlushClearsPhantomGestureRepeatAndNonRepeatableState`。
- 全量 `xcrun swift test --disable-keychain`：1736 项，只有 `RemoteButtonsTests.reportsFinalResultThroughCompletion` 未通过。该项依赖测试进程的辅助功能授权，本机 `AXIsProcessTrusted=false`；同一条在 `main` 的 CI 运行 45801604312 通过，与鼠标功能无关。
- 用例 1 的界面部分：用已安装包的离屏设置渲染（`REMOTE_MIC_SETTINGS_SCREENSHOT_*`，`1067 × 732`，中文浅色）确认动作编辑器“系统与媒体”分组列出“鼠标左键 / 鼠标右键 / 鼠标中键 / 切换鼠标模式”。
- 用例 1 的界面部分另在真实窗口复核（已安装包，构建号 443，窗口 `1067 × 772`）：“按键”页动作编辑器点“系统与媒体”分类后该组共 19 项，末尾依次为“鼠标左键 / 鼠标右键 / 鼠标中键 / 切换鼠标模式”。只切换了分类，没有点选动作，绑定未改动。
- 真实注入函数发出的事件序列：用临时探针执行真实的 `KeyboardInjector.postMouseClick`、`postMouseMoved` 和 `MouseModeController` 的默认注入闭包，由 `DYLD_INSERT_LIBRARIES` 插入库的 `__interpose` 段拦截 `CGEventPost` 并记录事件字段，不向系统转发。结果：左键、右键、中键各发出一对按下 / 抬起，中键的 `mouseEventButtonNumber` 为 2；全部事件发到 `kCGHIDEventTap`（`tap=0`）并带 `syntheticEventMarker`（`0x5849414F`）；鼠标模式下 OK 单击发出左键一对，OK 双击发出右键一对，按住方向键发出 `mouseMoved`。4 项探针断言全部通过。探针文件只放在仓库之外的临时目录，运行后删除，不入库。
- 复现上一条的方法：`swift test` 启动的测试进程环境里没有 `DYLD_INSERT_LIBRARIES`（`ps eww` 只看到 `DYLD_LIBRARY_PATH` 与 `DYLD_FRAMEWORK_PATH`），所以要带上这两个变量，直接运行 `swiftpm-testing-helper --test-bundle-path <测试包内可执行文件> --disable-keychain --testing-library swift-testing --filter <探针用例名>`。
- 屏幕上的真实点击（2026-11-27 补充；用户在远程，无法按实体遥控器）。用同一个已安装包、同一个签名（辅助功能和输入监控均已授权），只在启动时通过 `DYLD_INSERT_LIBRARIES` 加载一个临时库。该库用 `__interpose` 段接管 `IOHIDDeviceRegisterInputReportWithTimeStampCallback` 和 `IOHIDManagerRegisterInputReportWithTimeStampCallback`，只记录 App 登记的回调，不向 IOHID 转发，再按命令把遥控器报告（report ID 1，7 字节，小端 usage）直接送进 App 登记的设备级回调。报告回调之后的整条链路因此都在真实 App 里执行：报告路由、权限检查、手势识别、绑定查找，以及 `KeyboardInjector.postMouseClick` / `postMouseMoved` 的真实系统注入。临时绑定：菜单键长按 = 鼠标左键，电源键长按 = 鼠标右键（两格原来都是“无动作”，验证后已恢复）；TV 键双击 = 切换鼠标模式是用户已有的绑定。
- 上一条的结果（`runtime.log`，UTC 16:04–16:08）：菜单键长按 → `HID BUTTON button=menu trigger=longPress action=mouseLeftClick`，光标停在侧边栏“连接”行上，设置窗口从“按键”页切到“连接”页；电源键长按 → `HID BUTTON button=power trigger=longPress action=mouseRightClick`，光标停在桌面空处，出现访达的右键菜单窗口（`CGWindowList` 里 layer 101、owner 访达、锚在光标处）；电源键单击 → `action=escape`，右键菜单消失；TV 键双击 → `MOUSE MODE activated`，菜单栏图标 `from=connected to=mouse_mode`；按住上键 0.4 秒 → 真实光标从 (300,1100) 移到 (300,1060)；鼠标模式下 OK 单击 → 设置窗口从“连接”页切到“回眸”页，OK 按下没有产生 `HID BUTTON … action=returnKey` 行，即被鼠标模式接管（单击本身不写日志行）；OK 双击 → `MOUSE MODE double_tap_ok`，桌面再次出现访达右键菜单窗口；TV 键双击 → `MOUSE MODE deactivated reason=toggle_button`，菜单栏图标 `from=mouse_mode to=connected`。全程 `HID ACTION failed` 0 条。

安装包：`~/Applications/SayAll.app`，构建号 443，版本 2.0.10，arm64，ad-hoc 签名。启动正常；启动日志 `UI STATUS_ITEM operation_id=1 phase=completed result=applied from=none to=disconnected rendering=image` 走的是加入鼠标模式后的呈现路径。验证期间加载临时库的两次异常退出（23:50:31、23:59:33，崩溃报告 `RemoteMic-2026-11-26-235031.ips`、`RemoteMic-2026-11-26-235937.ips`）是临时库自身的问题（按名字取原函数导致递归、C 函数原型写错），不是 App 代码；正常启动不加载该库。验证结束后已恢复正常启动（`HID PERMISSIONS input=true accessibility=true`，进程里没有该库），临时目录已删除。

未验证：

- 实体遥控器的真实按键。上面的屏幕内点击由注入的遥控器报告触发，不是手按遥控器；手按遥控器后仍需按用例 1～6 验收。做验证用的会话进程本身没有授权（向系统发 `mouseMoved` 事件后光标位置不变），所以注入只在已授权的 App 进程内进行。未授权时 `CGEvent` 注入不生效，鼠标模式记录 `MOUSE MODE activate rejected reason=accessibility_untrusted` 并拒绝进入。
- 真实遥控器的原生透传抑制（注入期间临时库不转发真实报告）、断开自动退出、多显示器。
- “稳定功能回归项”里的手机 / 网页遥控一条不适用于公开构建：公开兼容层没有手机 / 网页遥控。
- 用例 2 步骤 1 的分组名以移植后为准：“切换鼠标模式”在“系统与媒体”分组（`main` 把 `.custom` 分组显示为“输入框”）。

### 2026-11-27 稳定性复审后的改动

复审发现一个会误伤的隐患和几处小问题，经用户确认后修改。改动清单见 [`feature/mouse-control/README.md`](../feature/mouse-control/README.md) 的“2026-11-27 稳定性复审后的改动”。修改后先只构建和跑测试，随后按用户要求打包安装（构建号 444）。

自动化结果：

- Debug `xcrun swift build --disable-keychain`：通过。
- `MouseModeControllerTests`：28 项通过。针对方向键双击手势的用例随该手势一起移除；新增用例覆盖：连续轻点方向键只移动光标、不注入按键也不弹回；模式外忽略方向键边沿；菜单键不被拦截；返回键按下即退出、它的松开走普通路径；模式内没有按下过的 OK 松开时不点击；四个鼠标移动动作每次发出固定的一步位移。
- `StatusItemPresentationTests` 新增 `mouseModeOnlyCoversOrdinaryStates`：鼠标模式只盖住未连接、已连接、语音中三种状态，不盖住语音时长警告和严重状态。通过。
- 全量 `xcrun swift test --disable-keychain`：1730 项，只有 `RemoteButtonsTests.reportsFinalResultThroughCompletion` 未通过，原因同上（测试进程没有辅助功能授权），与鼠标功能无关。
- `git diff --check`、`./scripts/verify-repository-governance.sh origin/main`：通过。

未验证：

- 安装包：`~/Applications/SayAll.app`，构建号 444，版本 2.0.10，arm64，ad-hoc 签名，由 `scripts/package-local-test-app.sh` 打包安装并启动。启动约 13 秒后 `HID PERMISSIONS input=true accessibility=true`，`HID FILTER phase=started result=active`。
- 实体遥控器（截至 UTC 03:44）：TV 键双击 → `HID BUTTON button=tv trigger=doubleClick action=toggleMouseMode`、`MOUSE MODE activated`（03:41:55）；再次双击 → `MOUSE MODE deactivated reason=toggle_button`（03:44:02）；模式外的方向键单击走普通绑定（`action=arrowLeft` / `arrowUp` / `arrowDown`）；之后再次进入鼠标模式（03:44:08）。模式内的点击不写日志行，所以点击落点、OK 手势、返回键退出和四个移动动作在真实遥控器上是否正确，仍需按用例人工验收。
- 四个移动动作每次 60 点的实际位移和手感、到屏幕边缘停住、按住连发；鼠标模式下语音时长警告 / 严重状态的图标显示。都需要按用例 1B、用例 2 步骤 6 用真实遥控器验收。

### 2026-11-27 分模式键位

用户要求键盘模式与鼠标模式分别配置同一颗键，并能看出当前在哪种模式。改动清单见 [`feature/mouse-control/README.md`](../feature/mouse-control/README.md) 的“键盘模式 / 鼠标模式分模式键位”，验证步骤见本手册用例 7。

自动化结果：

- Debug `xcrun swift build --disable-keychain`：通过。
- `xcrun swift test --disable-keychain --filter 'MouseModeControllerTests|ButtonBindingConfigurationTests'`：57 项通过。新增用例覆盖：鼠标模式绑定覆盖默认动作、退出动作可换到别的键、非内建动作转交执行器、只鼠标模式可选的动作在键盘模式候选里隐藏、已选中的鼠标模式动作在键盘模式仍可见、两套键位互不影响、旧 JSON 缺 `mode` 按键盘模式解码。
- `xcrun swift test --disable-keychain --filter 'SettingsPageRegressionTests|Mapping|MouseModeControllerTests|ButtonBindingConfigurationTests'`：195 项通过。
- 全量 `xcrun swift test --disable-keychain` 连跑两次（第二次带 `--skip-build`）：两次都在已执行用例全部通过后被测试进程 SIGSEGV 终止，没有 `✘` 失败行。崩溃报告 `swiftpm-testing-helper-2026-11-27-153046.ips`、`-153134.ips` 的故障线程都是 `SayAll.EventTap`，落点在 `KeyboardEventSuppressor.handle` 的 `uptime()`；同一签名在 14:35:56、14:40:01 两份报告里已经出现，那两次发生在本轮改动之前。判断为测试进程残留的真实事件 tap 收到真实键盘输入，属既有测试环境问题，本轮未修。
- 覆盖核对：`--list-tests` 列出 1743 个用例函数，两次日志按用例名合并覆盖 1739 个；剩余 4 个属于 `SupplementalSettingsIntegrationTests`，`--filter SupplementalSettingsIntegrationTests` 单跑 4 项全部通过。合计 1743 个用例函数全部执行且无失败。
- `git diff --check`：通过。

装包与界面核对：

- `scripts/package-local-test-app.sh` 安装构建号 446（公开模式、ad-hoc 签名，`~/Applications/SayAll.app`）。启动后 `HID PERMISSIONS input=true accessibility=true`，`HID FILTER phase=started result=active`：这次重建后授权没有丢。
- 真实窗口核对（构建号 446，窗口 1213 × 856，未缩到最小尺寸）：按键页出现「键位模式」分段（键盘模式 / 鼠标模式）和「当前：键盘模式」胶囊。切到鼠标模式后，确定键为「单击 鼠标左键 / 双击 鼠标右键 / 长按 回车」，四个方向键为「单击 光标移动」，返回键为「单击 退出鼠标模式」，卡片上没有「按住时」；电源键、主页键、菜单键、音量 +/−、TV 键显示「两种模式共用」。切回键盘模式后确定键恢复「按住时 + 单击 回车 / 双击 无动作 / 长按 无动作」。鼠标模式点开确定键单击的编辑器，「系统与媒体」分组里有「光标移动」「退出鼠标模式」，因为该键还没单独设置过，没有出现「恢复默认」。连接页正常渲染。

未验证：

- 生产最小窗口 `1067 × 760` 下的真实窗口核对（离屏渲染已按 `1067 × 732` 内容尺寸核对；窗口尺寸无法用脚本调整）。
- 用例 7 的真机步骤：实体遥控器进鼠标模式、改一个键的鼠标模式动作、恢复默认。
