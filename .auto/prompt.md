# Autoresearch: Screen Remote macOS 原生 UI 质量迭代

## Objective
持续改进 `Screen-Remote-macOS` 的原生 SwiftUI 设计一致性、可访问性与诚实状态表达。每轮只选择一个有真实用户价值、边界明确的缺口；完成后可为下一目标重新调用 `init_experiment`。

当前工作树从原 macOS 会话完整复制，已经包含此前保留的 UI/无障碍改进。不要重新实现已完成项。

## Metrics
- **Primary**: 每个有界实验自己的 `*_gaps`（count，lower is better）
- 每次目标变化时重新调用 `init_experiment`，并同步更新 `.auto/measure.sh`
- 测量器只能检查真实产品缺口，不得通过弱化规则或只迎合字符串计数使指标变好

## How to Run
`./.auto/measure.sh`

## Files in Scope
- `Screen-Remote/**`：macOS Swift / SwiftUI 产品源码
- `Screen-Remote/Resources/Localizable.xcstrings`：新增用户可见或无障碍文案时维护英中配对
- `.auto/**`：本 macOS 会话自己的实验状态

## Off Limits
- `../Screen-Remote/**`：Android 项目
- 聚合仓库根 `.auto/**`
- `../external/**`、Wiki、dadb 与其他子模块
- 不更新聚合仓库 gitlink，不安装或操作设备

## Constraints
1. 遵守 `AGENTS.md` 与 `.agents/skills/screen-remote-macos-engineering/SKILL.md`。
2. 保持 macOS 11 最低版本；新 API 必须走现有兼容层。
3. 用户可见和无障碍文案必须同时提供 English / Simplified Chinese。
4. 复用 `AppTypography`、`AppSpacing`、`AppRadius`、`AppTheme` 与现有共享组件。
5. 保持 ADB、scrcpy、下载、删除、导航、选择和窗口生命周期行为不变，除非当轮目标明确要求。
6. 每轮先运行最窄检查；需要编译时使用 `Screen-Remote` scheme / My Mac，不因普通小改动反复构建。
7. 只在当前 `Screen-Remote-macOS` 子仓库工作；不得修改 Android 子仓库、聚合根或其它 worktree。

## What's Been Tried
已保留的近期改进包括：
- `ContentUnavailableViewCompat` 标题支持 VoiceOver header 导航。
- 通知卡片标题支持 VoiceOver header 导航。
- Photos 刷新按钮朗读加载值，并隐藏重复的进度环语义。
- Photos 卡片提供下载与删除命名无障碍动作，删除仍走确认。
- Photos 区分搜索无结果与真实空图库，并提供清除搜索操作与英中资源。
- Management / Utilities 已完成多轮字体、间距、图标、字段标签、badge、sheet 标题和加载语义收敛。

下一轮先从 `.auto/ideas.md` 选择未完成方向；若现有实现已覆盖，不重复修改，改选更有证据的缺口。
