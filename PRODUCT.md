# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

- **主目标用户**：Android 研发工程师、自动化测试与 QA 工程师、ROM 开发者与极客玩家。
- **典型使用场景**：
  - 桌面端多设备并发连接与 ADB 调试。
  - APK 拖拽安装、提取、停用与包管理。
  - 毫秒级低延迟 Scrcpy 画面实时投屏与键鼠反向触控。
  - 无线调试（mDNS / TCP/IP）直连、端口转发规则管理、即时 Logcat 终端捕获。
  - 免 Root 动态修改屏幕分辨率、DPI、动画缩放及快速重启（Bootloader / Recovery）。

## Product Purpose

Screen Remote 桌面端是一款为开发者与极客打造的专业级 Android 投屏控制与调试工作台。它打破了传统投屏工具功能单一、以及传统命令行工具缺乏可视化交互的痛点，将底层的 ADB 通信协议与原生 Scrcpy 超低延迟视频流能力整合成高度一体化、开箱即用的集成式桌面控制驾驶舱。

## Positioning

相较于纯命令行 Scrcpy 或臃肿的手机助手，Screen Remote 桌面端立足于轻量透明的底层管道（Dadb / 原生 Scrcpy / WebCodecs 硬件加速），提供直接暴露真实底层状态、零多余包装、开箱即用的**集成式设备控制驾驶舱**，兼具极致的流媒体交互手感与深度系统调试能力。

## Operating Context

- **运行环境**：macOS / Windows / Linux 跨平台桌面客户端（基于 Tauri 2 + React + WebCodecs）。
- **设备连接通道**：物理 USB 数据线、Wi-Fi 局域网 TCP/IP 端口直连、mDNS 局域网服务自动发现。
- **底层依赖服务**：本地 ADB Daemon（默认端口 5037）、Scrcpy Server v3.1/v4.1、AVD 本地模拟器管理器。

## Capabilities and Constraints

- **核心能力**：
  - **实时高清投屏**：Scrcpy 原生视频流 WebCodecs 硬件级低延迟解码，支持键鼠触控、滚轮真实滑动、右键返回、快捷截屏与独立多窗口分离。
  - **集成控制驾驶舱**：主屏直接集合投屏预览与核心控制中心（电池健康、连接传输、存储/内存状态、高频快捷操作网格）。
  - **应用与文件管理**：用户/系统应用冻结卸载与 APK 侧载，内置两栏文件浏览器与高速双向拉取。
  - **调试与网络工具**：实时端口转发、Logcat / ADB Shell 交互终端、进程查看器、系统诊断。
- **设计约束**：
  - 严禁假装是手机硬件的厚重拟物外壳（Bezel）与生硬底部黑下巴（Chin）。
  - 严禁在无设备在线时呈现虚假的“连接就绪”欺骗性文案；状态必须 100% 诚实映射底层 ADB 真实连接事实。
  - 首屏核心以“集成式设备驾驶舱”为主，投屏画面与高频控制触手可及。

## Brand Commitments

- **视觉基准**：严格遵循 **Claude Design System (open-claude-ui)** 质感体系。
  - 色彩层级：低对比温润暗色与炭黑阶梯（`--cds-surface-0` ~ `--cds-surface-3`）。
  - 强调色：标志性克制陶土红（`--cds-clay`）与状态翡翠绿（`--accent-emerald`）。
  - 结构体系：双环微阴影与高分屏发丝细线补偿（Retina hairline 0.5px）。
  - 排版与动效：等宽数字锁定（`tabular-nums`），无多余浮夸弹跳。

## Evidence on Hand

- 真实可运行的代码仓库：`Screen-Remote-desktop/`（Tauri 2 + Vite + React + TailwindCSS）。
- 真实设备通讯：Dadb 驱动模块与系统 adb 自动探针。
- 实测运行窗口：通过 `cua-driver` 实时捕获与交互验证。

## Product Principles

1. **真实坦诚，杜绝欺骗**：界面指示灯与连接状态与底层 ADB / Scrcpy 进程严格原子对齐，不在线绝不伪造在线。
2. **重心明确，拒绝空洞**：核心交互立足于操作手机与执行命令，首屏即为高信息密度的集成驾驶舱，不留无用的大黑洞空屏。
3. **极速顺滑，即开即用**：设备连上自动识别并提供一键投屏链路，快捷键与鼠标映射零障碍。
4. **克制温润，工具之美**：遵循 Claude 经典双环与低对比表面质感，把视觉让位给设备内容与调试数据本身。
