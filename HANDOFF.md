# Screen Remote macOS 开发交接

更新时间：2026-08-09

本文供下一位开发者接手当前 macOS 子项目。它记录当前工作区状态、已验证内容、尚未完成的功能，以及推荐的后续实现顺序。不要把本文当作已提交版本说明；当前工作区包含多组未提交改动。

## 当前工作区

- 子项目：`Screen-Remote-macOS/`
- 分支：`main`
- 当前基线提交：`a202fdd`
- 与 `origin/main` 的关系：本地 `main` ahead 11
- Xcode scheme：`Screen-Remote`
- 运行目标：`My Mac`
- 最近一次记录的实机验收设备：Z5，ADB endpoint 曾为 `z5.local:30610` / `net.xrsec.fun:30610`

本轮开始时工作树只有 `.github/workflows/architecture-guard.yml` 的 checkout action 版本修改，属于已有改动，必须保留。本轮在同一 workflow 中只追加了参数分类检查。当前工作树另外包含参数分类、arm64 发布约束、Xcode project 同步、native session 拆分、实机修复和文档同步改动：

- `.github/workflows/architecture-guard.yml`
- `Makefile`
- `README.md`
- `HANDOFF.md`
- `Screen-Remote.xcodeproj/project.pbxproj`
- `Screen-Remote/Core/Models/SDLLogModels.swift`
- `Screen-Remote/Core/State/AppState.swift`
- `Screen-Remote/Features/Devices/AddDevice/Services/ConnectionLatencyTester.swift`
- `Screen-Remote/Features/Devices/AddDevice/Views/CodecSelectors.swift`
- `Screen-Remote/Features/Devices/AddDevice/Views/ConnectionLatencyTestView.swift`
- `Screen-Remote/Features/Devices/AddDevice/Views/RemoteEncoderSelector.swift`
- `Screen-Remote/Features/Devices/Discovery/ADBCommandRunner.swift`
- `Screen-Remote/Features/Devices/Discovery/DeviceDiscoveryView.swift`
- `Screen-Remote/Features/Management/Utilities/DeviceUtilitiesView.swift`
- `Screen-Remote/Features/Management/Utilities/DeviceUtilityComponents.swift`
- `Screen-Remote/Features/Screens/Services/ScreenSessionLaunch.swift`
- `Screen-Remote/Features/Screens/Views/ScreenComponents.swift`
- `Screen-Remote/Features/Screens/Views/ScrcpySessionParametersMenu.swift`
- `Screen-Remote/Features/Screens/Views/ScrcpySurfaceInput.swift`
- `Screen-Remote/Features/Screens/Views/ScreenWindowComponents.swift`
- `Screen-Remote/Features/Tooling/Models/ToolDownloadModels.swift`
- `Screen-Remote/Features/Tooling/Services/ToolLocator.swift`
- `Screen-Remote/Features/Tooling/Views/ToolDownloadView.swift`
- `Screen-Remote/Resources/Localizable.xcstrings`
- `Screen-Remote/Services/Scrcpy/Session/NativeScrcpySession.swift`
- `Screen-Remote/Services/Scrcpy/Session/NativeScrcpySession+Codec.swift`
- `Screen-Remote/Services/Scrcpy/Session/NativeScrcpySession+Control.swift`
- `Screen-Remote/Services/Scrcpy/Session/NativeScrcpySession+Socket.swift`
- `Screen-Remote/Services/Scrcpy/Session/NativeScrcpyTypes.swift`
- `Screen-Remote/Services/Scrcpy/Session/ScrcpyAudioRenderer.swift`
- `Screen-Remote/Services/Scrcpy/Session/ScrcpyServerAsset.swift`
- `Screen-Remote/Services/Scrcpy/Session/SessionParameterController.swift`
- `scripts/check-project-structure.sh`
- `scripts/check-session-parameters.swift`
- `scripts/verify-localization.sh`

接手时禁止 reset、checkout 或覆盖未辨认的修改；先逐个查看 diff。

## 本轮已经完成并验证的内容

### 2026-08-09：最近提交审计、session 收口与实机验收

已核对 `64a44bd` 至 `a202fdd` 的 11 个提交。当前进度不再是“固定 H.264、参数切换未开始、滚动未开始”：代码已经包含 bundled-server codec 能力发现与缓存校验、H.264/H.265 runtime fallback、参数 replacement controller，以及滚动精度、归一化和 phase/momentum 保留。

本轮补充：

- `SessionParameterController` 已覆盖 `ScrcpyDeviceOptions` 的全部 28 个当前字段，避免选项已经持久化但 active session 无动作且无日志的空计划。
- server/decoder 参数归类为 replacement restart；兼容模式、游戏模式和悬浮球归类为本地即时状态；尚无运行时消费者的 controller-awake 明确归类为 unsupported。
- 新增 `make check-session-parameters`，逐字段验证分类且通过，并接入 architecture guard。
- 明确项目仅支持 Apple Silicon：Xcode project 保持 `ARCHS = arm64`，`make release` 默认只构建 arm64，不提供 x86_64 产物；最低系统版本仍为 macOS 11，scrcpy server 与许可证均需打入 bundle。
- String Catalog 校验脚本不再错误地把 JSON String Catalog 当作 plist 预检，并完成 4 条简体中文 `needs_review` 状态收口。
- 使用既有稳定生成器规范化重写 PBX source/group/build phase；`scripts/sync-xcode-project.py --check` 现已通过，新拆分文件也由物理目录自动纳入工程。
- `NativeScrcpySession.swift` 从 1485 行降至约 650 行；codec、control、socket、基础类型和 Core Audio renderer 分文件维护，socket/forward/stop 锁序与 AudioConverter 生命周期保持不变。
- 修复 scrcpy server 部署真值：不再把“本进程曾部署”误当成远端 JAR 仍存在，而是每次启动检查远端 SHA-256。`cleanup=false` 会直接复用；`cleanup=true` 删除 JAR 后会重新 push。
- Z5（SM-F731B / Android 14）已通过 exact `ScreenSessionManager` H.264 → H.265 replacement：两种 cleanup 配置均收到 H.264/H.265 首帧，replacement 依次进入 `VideoReady`、`Switching`、`Completed`，旧 forward 在切换后移除。
- Z5 上已发送 precise `-0.25 × 24` 与 mouse-scale `-8 × 6` 滚动控制消息，两组设备截图均发生变化；设备当时处于锁屏，因此方向、距离及真实触控板 phase/momentum 的内容级验收仍需在解锁后的可滚动页面完成。
- 右键输入采用确定性双绑定：普通右键发送 Android `BACK`，Shift+右键透传 secondary click，保留短信选中态“多功能”等上下文操作。scrcpy control 协议不返回事件是否被应用消费，不能可靠实现自动“未触发多功能时再返回”；两条绑定仍需在解锁短信页实机确认。
- arm64 Release 构建成功；`project.pbxproj` 通过 `plutil -lint`，`git diff --check` 通过。

Architecture guard 现已完整通过：project source references 已同步；连接延迟、ADB discovery 和工具定位的进程执行已移出 View；`ManagedProcess(` 不再被正则误报；`AppState` 日志模型、Device Utilities 组件、remote encoder selector、screen 参数菜单、surface/input 与 window components 均按职责拆分。所有非 allowlist Swift 文件都已低于 700 行，没有用 allowlist 掩盖问题。

### 设备信息页（2026-07-31 接手补完）

设备信息 P0 的代码实现已经完成：

- 新增 `DADBHelperRuntime.swift`，统一 helper bundle 查找、版本检查、部署、shell quote、超时进程与 `app_process` 调用。
- `DeviceAppsManager` 已改用共享 runtime；应用列表分页只准备一次 helper，图标调用独立确保 helper 可用。
- 新增 `DeviceInformationView.swift`，通过 `ManagementSnapshotMain device` 解析结构化协议，不再拼接长 shell。
- helper 协议新增 `sdk` 字段，版本从 `1.5.0` 统一升级至 `1.6.0`；`data_filesystem` 改为读取 `df -k /data` 的实际数据行。
- 页面按系统硬件、显示与电源、存储与内存、网络、系统标识五组展示，空字段隐藏；单字段 helper error 只写英文诊断，不让整页失败。
- 已覆盖刷新率、物理 PPI/屏幕尺寸、电池回退、存储/内存百分比、NR/LTE 信号、Wi-Fi、IPv4 接口、默认路由、连接 endpoint 和无线调试端口格式化。
- 连续刷新、切换设备和断开时使用请求 ID 与当前 serial 双重校验，旧请求不会覆盖新设备。
- 英文和简体中文文案已加入 String Catalog。

已验证：

- 全部 Swift 源码通过 macOS 11 arm64 `swiftc -typecheck`。
- String Catalog 通过 `xcstringstool compile` 的英文和简体中文编译。
- `project.pbxproj` 通过 `plutil -lint`，`git diff --check` 通过。
- dadb `RemoteManagementHelperTest` 共 7 项通过。
- 已通过 Xcode 的 `Screen-Remote` scheme 在 `My Mac` 构建并运行。
- Z5 五组真实数据加载成功；当时 Wi‑Fi 与默认网关为空，页面未产生错误卡片。
- 已检查简体中文、英文即时切换，验收后恢复“跟随系统”。
- 已检查浅色、深色、双列宽窗口和单列紧凑窗口，验收后恢复系统外观与原窗口宽度。
- 验收结束后已停止 Z5 会话和 Xcode 调试运行。

### 实用工具页

`DeviceUtilitiesView` 已从简单的一键命令集合扩展为与 Android 端语义一致的八个入口：

1. 固定无线调试端口。
2. 设备截图、预览、打开和另存。
3. 高级重启：普通重启、关机、Recovery、Fastboot。
4. 激活应用：检测 Shizuku、Brevent、Ice Box，只允许执行已安装目标。
5. 修改或重置 DPI。
6. 修改或重置分辨率。
7. 分别设置 window、transition、animator 三项动画倍率。
8. 熄屏与唤醒。

对应英文和简体中文文案已加入 `Localizable.xcstrings`。新增应用日志均为英文。

已通过 Xcode 运行指定 macOS 开发产物，并在 Z5 上验证：

- 工具页能读取端口 `30610`、DPI `480` 和当前分辨率 `1080 × 2400`。
- Shizuku 显示为已安装，Brevent 与 Ice Box 显示为未安装且禁用。
- 截图最初因 `screencap` 的多显示器警告混入 stdout 而无法解码；现已改为在设备临时目录生成 PNG、通过 `adb pull` 拉取、清理远端文件，再在 macOS 中预览，复测成功。
- 高级重启、DPI 等对话框的内容、禁用状态和浅色/深色外观已检查。
- 没有在验收中执行重启、关机、改端口、改 DPI/分辨率等设备写操作。

### 注意事项

- 工具页的设备写操作只完成了 UI、命令与静态逻辑验证，仍需要后续针对成功、权限不足、连接因重启而中断、超时和取消路径做专门测试。
- `DeviceManagementViews.swift` 同时包含其他未提交的文件管理改动，继续编辑时要保留这些现有变化。

## P0：设备信息页已完成

### macOS 当前状态

原先位于 `DeviceManagementViews.swift` 的长 shell 和 `KEY=value` 解析已经移除，当前实现位于 `DeviceInformationView.swift`，并使用共享 `DADBHelperRuntime` 调用内置 dadb helper。

### Android 对照目标

Android 端的权威模型和格式化逻辑：

- `../Screen-Remote/app/src/main/java/com/screen/remote/android/feature/session/ui/SessionManagementModels.kt`
- `../Screen-Remote/app/src/main/java/com/screen/remote/android/feature/session/ui/SessionManagementDeviceInfoSupport.kt`
- `../external/dadb/dadb-helper/src/main/java/dadb/helper/ManagementSnapshotMain.java`
- `../external/dadb/dadb/src/main/kotlin/dadb/helper/RemoteManagementHelper.kt`

目标页面按以下五组组织，并隐藏无值字段：

| 分组 | 应展示字段 |
|---|---|
| 系统硬件 | 品牌/型号、SoC、Android 版本、SDK、运行时间、基带、产品代号、安全补丁、序列号、连接类型/endpoint、CPU 核心与最高频率、ABI、Board |
| 显示与电源 | 当前分辨率/刷新率、DPI/PPI/屏幕尺寸、支持刷新率、电池健康/电压/电流、电池状态/电量/温度、循环次数 |
| 存储与内存 | 可用/总存储与可用百分比、可用/总内存与可用百分比 |
| 网络 | 蜂窝制式/频段、运营商、PCI、EARFCN/NR ARFCN、RSRP、RSRQ、SINR、Wi‑Fi SSID/BSSID、频率/链路速度、各接口 IPv4、默认网关、无线调试端口 |
| 系统标识 | Build fingerprint；有值时才显示该组 |

无 SIM、Wi‑Fi 关闭、无默认路由或厂商不公开 sysfs 字段都属于正常情况。单个字段为空时不要显示“错误”或让整页失败。

### 推荐的 dadb helper 接入方式

macOS 工程已经有完整的 helper 构建和部署基础，不需要新增另一份 JAR：

- Xcode build phase 会构建 `:dadb-helper:dexJar`，并把 `dadb-helper.jar` 和许可证复制进 app resources。
- `DeviceAppsManager.swift` 中的私有 `DeviceAppADB` 已实现：查找内置 JAR、检查 helper 版本、必要时部署到 `/data/local/tmp/dadb-helper.jar`、通过 `app_process` 调用 helper。

下一步应先抽取共享运行时，例如新增 `DADBHelperRuntime.swift`：

1. 从 `DeviceAppADB` 提取 helper version、远端路径、bundle 查找、版本检查、部署、shell quote、进程超时和通用 invoke。
2. 保持应用列表/图标现有行为不变，让 `DeviceAppsManager` 改为调用共享运行时。
3. 设备信息调用：

   ```text
   CLASSPATH=/data/local/tmp/dadb-helper.jar \
   exec app_process / dadb.helper.ManagementSnapshotMain device
   ```

4. Swift 解析器必须接受以下协议：

   ```text
   DADB_MANAGEMENT<TAB>DEVICE
   D<TAB><wireName><TAB><base64 value or -><TAB><base64 error or ->
   ```

5. `wireName` 集合以 dadb 的 `RemoteDeviceField` 为准。未知字段应作为协议版本错误明确记录；已知字段的单项 error 应保留用于英文诊断日志，但 UI 只隐藏该空字段。
6. 不要让 UI 直接依赖 raw helper 字典。增加 Swift snapshot/presentation 层，语义化格式化后再交给 SwiftUI。

helper 已并行采集以下字段：model、manufacturer、soc_model、android_version、uptime、baseband、product_code_name、security_patch、serial、resolution、density、display_metrics、display_info、network_interfaces、default_route、mobile_network_type、carrier_names、signal_strength、cell_identity、wifi_info、memory、data_filesystem、battery_cycle、battery、voltage/current fallbacks、abi、board、fingerprint、wireless_port、cpu_count 和 cpu_max_frequency。

不要在 Swift 再发 30 次独立 shell，也不要复制另一份查询列表。

### 格式化要求

- 语义对齐 Android，不要求逐行翻译 Kotlin。
- uptime 转成天/小时/分钟的本地化格式。
- CPU 频率由 kHz 转 GHz。
- display info 提取当前刷新率和全部支持刷新率。
- 使用物理 x/y DPI 计算平均 PPI 和屏幕对角线；无可靠物理 DPI 时隐藏 PPI/尺寸。
- 电池温度除以 10；电压按 mV/µV 量级归一化；电流依次使用 dumpsys、`cmd battery` 和 sysfs fallback。
- 存储与内存显示“可用 / 总量（可用百分比）”。
- 信号优先 NR 的 ssRsrp/ssRsrq/ssSinr，否则使用 LTE rsrp/rsrq/rssnr，并过滤 `2147483647`。
- 网络接口过滤 loopback/127.*；根据 wlan、softap、rndis 等名称给出可理解标签。
- 所有页面文案进入 String Catalog，支持英文和简体中文；所有日志和 helper 错误只能使用英文。

### Z5 只读采样结果

本轮通过只读 ADB 观察到：

- model：`SM-F731B`
- SoC：`SM8550`
- physical size：`1080x2640`
- override size：`1080x2400`
- density：`480`
- current refresh rate：约 `60 Hz`
- supported modes：`10/24/30/48/60/96/120 Hz`
- physical DPI：约 `428.625 × 424.405`
- battery：79%，not charging，health good，4159 mV，34.7 °C
- LTE：band 3，PCI 252，EARFCN 1650，RSRP -82 dBm，RSRQ -9 dB
- IPv4：`rmnet_data0 10.7.166.216`、`rndis0 192.168.255.154`
- Wi‑Fi 与默认路由当时为空，这是正常状态，不能视为页面加载失败。

### 设备信息验收清单

- Z5 实机五个分组有真实数据，空 Wi‑Fi/网关不产生错误卡片。
- helper 不存在或版本不符时由应用自己的运行时部署，不手工 adb push。
- 一个 helper 字段失败时其他字段仍展示。
- 连续刷新、切换设备和断开重连不会把旧设备数据显示到新设备。
- 英文、简体中文和跟随系统模式均正确。
- 浅色、深色、单列紧凑宽度和双列宽度均检查。
- Xcode 运行验证只在实现完成后进行一次；不要为每个小改动反复编译。

## 其他未完成项目

### P0 / 正在进行：native scrcpy 会话

#### 本轮目标与边界

本轮开始把主屏幕会话从外部 scrcpy/SDL 窗口迁移到 macOS 应用自己拥有的官方 scrcpy 4.1 pipeline。实现只使用官方 `com.genymobile.scrcpy.Server`、官方参数和官方媒体包格式；`external/scrcpy-mask/` 仅用于理解客户端媒体处理结构，没有引入 `scrcpy-mask-server` 扩展，也没有修改 scrcpy server 逻辑。

Android 项目只用于核对现有 4.1 版本、SHA-256、server 命令语义和 socket 生命周期。macOS 不读取、不复制运行时 Android assets，拥有自己的 server 与许可证资产。

#### macOS 独立资产与缺失处理

macOS 自有资产：

- `assets/scrcpy-server.jar`
- `assets/scrcpy-LICENSE.txt`

固定版本与校验值：

- scrcpy server：`4.1`
- server SHA-256：`deacb991ed2509715160ffdc7907e47b4160eb30d1566217e9047fd5b8850cae`
- license SHA-256：`01c12035bf35af37241298dc7ad538eb2a07e5c940437bc6876feeaa9d1951d0`

`scripts/prepare-scrcpy-server.sh` 是唯一准备入口：

1. 资产存在时计算 SHA-256，匹配才继续。
2. server 不存在时，从官方 GitHub `Genymobile/scrcpy` 的 `v4.1` release 下载。
3. license 不存在时，从官方 `v4.1` tag 下载。
4. 下载后再次校验；失败立即退出，不能把未知文件打进应用。
5. `--copy-to <resources>` 会把 server 和 license 一起复制到 app resources。

该脚本已经接入：

- `make prepare-assets`
- `make build` 的前置依赖
- `make release` 的前置依赖
- Xcode target 的 `Prepare scrcpy-server` build phase

应用运行时只从自身 `Bundle.main` 查找 `scrcpy-server.jar`，并再次校验 SHA-256。Bundle 缺失或校验失败时会明确终止 native session，提示运行准备脚本后重新构建；应用运行时不会临时读取 Android 工程资产，也不会静默使用 scrcpy executable 旁边的不明 server。

#### 已实现的主链路

核心文件为 `Screen-Remote/NativeScrcpySession.swift`，当前已经实现：

1. 从 macOS app bundle 获取并验证官方 server。
2. 使用现有 ADB target 将 server 部署到 `/data/local/tmp/scrcpy-server.jar`。
3. 为每次会话生成 31-bit SCID 和 `scrcpy_%08x` localabstract 名称。
4. 建立 `adb forward tcp:0 localabstract:<socketName>`，读取 ADB 分配的本地端口。
5. 通过 `app_process` 启动官方 `com.genymobile.scrcpy.Server 4.1`。
6. 严格按协议顺序建立 `video -> optional audio -> control` socket；禁止并发建链。
7. 只在第一条 video socket 上读取并验证 dummy byte `0x00`。
8. 等全部 socket 建立后，从第一条 socket 读取固定 64-byte device metadata。
9. socket 就绪后移除临时 ADB forward，保留已经建立的 TCP 连接。
10. 读取 video codec ID、初始 session metadata 和连续的 12-byte frame metadata。
11. 识别 config/key-frame/PTS/session 标志，并限制异常包大小。
12. 将 H.264 Annex-B NAL 单元转换为 VideoToolbox 使用的 length-prefixed 格式。
13. 从 SPS/PPS 建立 `CMVideoFormatDescription` 和 `VTDecompressionSession`。
14. 把解码后的 `CVPixelBuffer` 转换为 app-owned `CGImage`，发布到 `ScrcpyVideoSurface`。
15. **Screens** 工作区中的小窗与放大后的大窗都可以显示同一会话的原生画面。
16. stop/异常/应用退出时关闭 socket、终止 server shell process、移除残留 forward、销毁 decoder 并清空画面。

native video 已从最初固定 H.264 的闭环扩展为 H.264/H.265 VideoToolbox 选择，使用内置 server 探测远端 encoder，校验本地/远端 capability cache metadata，并在自动策略下按失败原因执行受控 codec fallback。媒体包解析参考官方 scrcpy 4.1 `app/src/demuxer.c`，客户端组织方式参考 scrcpy-mask，但没有复制其 FFmpeg/Rust 解码实现。

`ScreenSessionManager` 的主屏幕 `start()` 已切换到 `NativeScrcpySession`。原来的外部 scrcpy process 路径仍保留给 app-specific virtual display，不能在后续清理时误删，除非该路径也已迁移到 native session model。

#### 当前验证结果

已完成：

- `scripts/prepare-scrcpy-server.sh` 首次下载成功。
- server 与 license 的 SHA-256 均匹配固定值。
- 已验证资产存在时脚本只校验，不重复下载。
- 已验证 `--copy-to` 同时复制 server 与 license。
- `Screen-Remote.xcodeproj/project.pbxproj` 通过 `plutil -lint`。
- 全部 Swift 源码以 macOS 11 arm64 target 通过 `swiftc -typecheck`。
- `git diff --check` 通过。

本轮没有运行或安装应用，也没有使用 ADB 安装、替换或清理应用数据。

此前阻断完整构建的 `Localizable.xcstrings` 已可通过 `xcstringstool compile` 分别编译英文和简体中文，并已通过 Xcode 在 `My Mac` 完成构建与运行验收。

#### 已知限制与下一步

按以下顺序继续，避免同时扩张多个协议面：

1. **完成实机会话与 replacement 验收**：确认 server push、ordered sockets、metadata、H.264/H.265 首帧、fallback、replacement timeout/cancel 和快速连续参数变更。
2. **完成滚动输入验收**：分别使用鼠标与触控板核对方向、精度、phase/momentum、边界值和 Android 端实际滚动距离。
3. **验收右键双绑定**：普通右键应返回，Shift+右键应在短信选中态触发“多功能”等 secondary-click 上下文操作。
4. **修复帧呈现性能**：当前每帧由 `CIContext` 转为 `CGImage` 并通过 `@Published` 更新，闭环简单但成本高。建议改为 `CVPixelBuffer` + Metal/Core Image-backed `NSView`，避免 CPU 图像复制和 SwiftUI 全量刷新。
5. **动态尺寸与旋转**：收到 session packet 时更新 surface 尺寸和窗口比例；确认 encoder 重新发 config 时安全重建 VideoToolbox session。
6. **补齐控制协议**：继续完成剪贴板、device-message reader 和尚缺的输入行为。所有坐标必须基于实际视频尺寸、旋转和窗口 content rect 变换。
7. **音频播放**：当前 audio socket 会读取 codec ID 并持续消费媒体包，防止 server 背压，但不解码、不播放。下一步选择原生 AudioToolbox/AVAudioEngine 路径，处理 Opus/AAC 能力与同步。
8. **虚拟显示统一**：app-specific virtual display 目前仍调用外部 scrcpy executable；迁移后应复用同一 native session，不要复制第二套 socket/decoder 生命周期。
9. **失败恢复与多屏压力**：覆盖 server/forward/socket/格式变更/断线/取消，并验证多设备 decoder、audio focus、窗口拖出/拖回和清理互不串线。

特别注意：当前 socket 有 10 秒 receive timeout；这是初始保护值，不等于最终恢复策略。第二或第三 socket 建链失败后，官方 server 已经按 accept 顺序分配角色，不能针对同一 server/SCID 随意重开一组 socket；应销毁整次 session，使用新 SCID 重启。

### P1：ADB 管理页完整性

- 文件管理：检查当前未提交的多列浏览、批量选择、上传/下载/删除、详情列改动；补统一进度、取消、覆盖确认和错误恢复。
- 应用管理：继续验证大列表、helper 部署失败、图标缓存、批量操作和虚拟显示启动。
- 进程管理：补刷新状态、筛选、结束进程确认、权限失败提示。
- 端口转发：补冲突校验、断线恢复、失败详情和规则状态同步。
- 实用工具：补所有设备写操作的成功、权限拒绝、超时、连接中断测试；当前只完成 UI 和只读路径实测。
- 诊断：统一结构化状态摘要、可复制信息、敏感信息处理和英文日志。

### P1：设置与依赖引导

- 增加 About 页面：版本、项目链接、许可证、致谢、更新状态和诊断入口。
- 重组 Settings：外观/语言、连接、屏幕与输入、Android SDK/Emulator、下载、存储、隐私、诊断。
- 在具体功能入口展示依赖健康状态，减少只提供裸路径字段的情况。
- 完善 ADB、scrcpy、Android CLI、Emulator、skins 缺失时的引导和恢复。

### P2：companion 能力

Notifications、Messages、Photos 仍只有产品 UI 和空状态。需要先定义 companion/protocol 数据通道，再实现通知、短信、照片、剪贴板、电池事件和后台协调。不要用示例数据伪装为已支持能力。

### P2：屏幕工作区与键位映射

- 将 app-specific virtual display 和 emulator screen 纳入统一 session model。
- 完成多屏 drag-out/drag-in、窗口恢复、解码负载和音频焦点协调。
- 增加按设备/应用的键位映射配置与可视化编辑器。
- 正确处理缩放、旋转、窗口大小、虚拟显示和失焦时的坐标与触点释放。

## 建议接手顺序

1. 先阅读根目录 `AGENTS.md`，涉及 UI 时再读取 UI 设计系统。
2. 查看并保护当前 dirty worktree，保留已有 workflow 修改和本轮参数/多架构改动。
3. 先完成 native scrcpy replacement、codec fallback 与滚动输入的实机验收。
4. 再处理帧呈现性能、动态尺寸/旋转和 native virtual-display 统一。
5. 最后进入其他管理页和 Settings/companion 等后续工作。
