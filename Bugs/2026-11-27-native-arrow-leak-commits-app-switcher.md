# 映射回读通过后原生方向键仍泄漏，App 切换器一格就被提交、上下文菜单一按方向键就关

- 版本：2.0.10（本地构建 444，公开模式），macOS 27.0.1（26A434），Apple Silicon
- 影响范围：小米 RC003 monitored 会话下的所有映射键；表现集中在 App 切换器与上下文菜单，语音链路不受影响

## 现象和证据

用方向键在 App 切换器里移动时，高亮只走一格，切换器立刻消失并直接切到那一格的 App，无法停下来继续选；菜单键打开的上下文菜单同样一按方向键就关闭。用户描述为「移动方向键的时候切换 APP 就直接进行了点击」。

当次会话日志（`~/Library/Logs/RemoteMic/runtime.log`，UTC）里的关键行：

```text
HID NATIVE MAPPING phase=prepare result=verified reason=mapping_readback written=1 native_delivery=unobserved family=xiaomi
HID FILTER directional_fallback=false
HID EDGE pressed=left ...
HID FILTER miss type=10 event=key123 edge=down armed=false pending=1
```

- 泄漏共 5 条，全部是方向键：`key123`（左）4 次、`key125`（下）1 次，与对应的 `HID EDGE` 只差 1–8 ms，每次按下泄漏一次，按下与松开各来一条。
- 同一份日志里 `type=14 event=sys4` 的 32 条 miss 是用户自己键盘的系统定义事件，与本次无关。
- App 切换器每次会话的形态一致：`phase=navigate success=true` 之后 0.1–0.5 秒出现 `switcher_state ax=absent`，前台 App 直接变成高亮项；那一刻没有任何 SayAll 动作日志，也没有 ⌘ 松开记录，真正结束会话的 `HID APP SWITCHER ended reason=mouse_click` 是用户后来自己点鼠标时才写的。
- 上下文菜单：`HID BUTTON button=menu trigger=singleClick action=contextMenu` 后紧跟 `ACTION FEEDBACK … result=success presentation=disabled_success`，中间没有方向键按下记录，也没有鼠标点击，菜单仍然关闭。

## 根因

`Sources/RemoteMic/HIDRemoteMonitor.swift` 的事件级拦截判据只信任 `nativeKeysNeutralized`，也就是 `RemoteNativeKeyMapper` 的**写入回读**。回读只证明字节写进了设备，不证明 macOS 停止投递原生事件；本机就是后者没成立：

- `shouldArmNativeEvent(for:)` 的方向键分支要求 `directionalNativeFallback`，而这个开关只在 `#if arch(x86_64)` 时为真（`directionalNativeFallbackEnabled`），Apple Silicon 上一律不登记拦截。
- 于是遥控器方向键既执行了 App 合成的动作，又放行了同码的原生方向键。切换器里系统自己按 ⌘+方向键时，多出来的那一条原生方向键被系统当成「确认并切换」，高亮第一格就被提交；菜单键的 `keyCode 110` 同理，方向键一到菜单就关。
- 这段逻辑来自上游 2026-11-07 的 `fix(hid): suppress leaked native arrow keys in monitored sessions`：当时只在 Intel 上拿到泄漏证据，就按架构收窄了登记范围。本机说明泄漏与架构无关，回读成功也不能当作投递已阻断。
- 与鼠标功能无关：`git diff v2.0.10 HEAD -- Sources/RemoteMic/HIDRemoteMonitor.swift` 在拦截路径上只有鼠标模式的边沿处理和日志改动，`shouldArmNativeEvent`、`prearmsNativeEvent`、App 切换器路径都没有变化。

## 修复

- 新增 `HIDRemoteMonitor.assumeNativeKeyLeak`（本地开关，**默认 true**）：映射回读通过后仍按「原生事件会泄漏」处理。关掉用 `defaults write com.hd838a.RemoteMic assumeNativeKeyLeak -bool false`。
- 新增 `nativeDeliveryBlocked`（= 回读生效 **且** 不假设泄漏），`shouldArmNativeEvent(for:)` 的三个分支改用它：泄漏假设下方向键与普通键走同一条登记路径，`directionalNativeFallback` 只保留给「不假设泄漏」的机型。
- `prearmsNativeEvent(for:seized:neutralized:directionalFallback:assumeNativeKeyLeak:)` 增加泄漏分支：非独占且回读生效时为**所有带原生事件的映射键**在报告线程提前登记。泄漏事件只比主线程登记早 1–8 ms，晚一步就漏。独占会话收不到原生事件、映射未生效时要靠原生透传，两种情况都不登记。新增 `nativeEvents` 为空的提前返回（返回键由 App 独占解释，没有原生事件可拦）。
- 鼠标模式的边沿拦截恢复为无条件登记：这些边沿完全由鼠标模式解释，泄漏一次就会同时触发原生方向键或回车。
- `HID FILTER` 启动日志补 `native_leak_assumed=true|false`，现场不用再靠一次性探针判断这台机器走了哪条判据。

代价：每次按下映射键会开出 0.5 秒拦截窗口（`KeyboardEventSuppressor.nativeDeliveryWindow`），窗口内同码的实体键盘按键会被吞掉一次。这与 Intel 上已有的行为一致，也是让切换器可用的必要代价。

## 验证

| 范围 | 命令或证据 | 结果 |
| --- | --- | --- |
| 泄漏方向键被拦 | `--filter 'leakedNativeDirectionalIsSuppressedWhenTheBuildAssumesALeak'` | 4 个按键用例通过 |
| 提前登记范围 | `--filter 'leakedNativeBuildPrearmsEveryMappedButton'`、`directionalPrearmOnlyCoversSessionsWhereTheAppOwnsTheMove` | 通过 |
| 会话结束后不残留拦截 | `--filter 'leakedNativeKeysReleaseTheirCreditsWhenTheSessionEnds'` | 3 个按键用例通过 |
| 拦截相关整套 | `--filter 'KeyboardEventSuppressorTests'` | 52 项通过 |
| 判据一致性源码守卫 | `--filter 'prearmAndMainThreadShareOneEventLevelArmDecision\|powerSuppressionIsArmedBeforeButtonCallbacksAndMonitoring\|monitorStopEndsThePrearmSessionBeforeReleasingSharedResources'` | 3 项通过 |
| 全量公开测试 | `xcrun swift test --disable-keychain` | 见下方「全量结果」 |
| 真机（构建号 445，pid 459） | 启动日志 `HID FILTER directional_fallback=false native_leak_assumed=true`；06:45:09.455 起的切换器会话 | 连续 4 次 navigate 之间 `switcher_state ax=visible`，2.3 秒后 `ended reason=confirmed confirmed=true`；期间 `HID FILTER miss` 0 行、`arm` 98 行。444 上同样动作是一次 navigate 后 0.1–0.5 秒 `ax=absent` |
| 治理检查 | `scripts/verify-repository-governance.sh origin/main` | 见交付记录 |

全量结果：两次全量运行都是 1730 项全部通过（`reportsFinalResultThroughCompletion` 两次也通过），随后测试进程收到 SIGSEGV 崩溃（`swiftpm-testing-helper`，两次栈相同：故障线程 `SayAll.EventTap`，空函数指针，落在 `KeyboardEventSuppressor.handle` 的 `uptime()`）。崩溃发生在全部用例通过之后、进程收尾阶段，本次改动没有触碰 `handle`、拦截器生命周期或事件 tap 的创建与释放，单独运行 `EventTapPortTests`（含「不累积 tap」用例）10 项通过、无崩溃。推测是测试进程持有已启用的事件 tap 时收到真实键盘输入、而对应拦截器对象已释放；根因未证实，与鼠标模式修复无关。

## 未覆盖

- 仍未观察：鼠标模式内的方向键移动、上下文菜单打开后按方向键（需要实体遥控器再试一次）。这两项各自看一条日志：`HID FILTER miss` 不出现，`HID APP SWITCHER ended` 不紧跟第一次方向键。
- 0.5 秒窗口对实体键盘同码按键的影响没有自动化用例覆盖（与 Intel 上既有行为同源）。
- 泄漏本身没有消除：这是事件层兜底，根因仍在 macOS 对 `UserKeyMapping` 的处理上。若将来某台机器回读通过后确实不再投递原生事件，可用 `assumeNativeKeyLeak` 关掉这层兜底。
