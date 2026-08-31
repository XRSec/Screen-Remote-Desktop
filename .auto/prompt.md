# Autoresearch: Screen Remote macOS 原生 UI 质量迭代

## Objective
当前首要目标是降低 `Screen-Remote-macOS` 用户可感知的 UI 卡顿，并控制 autoresearch 产出的范围与质量。每轮只选择一个有真实用户价值、边界明确、能够用运行时证据验证的性能缺口；完成后可为下一目标重新调用 `init_experiment`。

当前工作树已累计大量 UI/无障碍改进。除非监督会话明确批准，暂停继续添加单个 `accessibilityLabel`、`accessibilityValue`、header trait、单复数文案、静态 token 替换等微型实验；不要为了持续出提交而寻找新的字符串或正则缺口。

## Metrics
- **Primary**: 优先使用可重复的运行时指标，例如主线程耗时、列表/网格数据处理耗时、缩略图传输字节数、解码尺寸、刷新次数或明确的 UI 延迟代理；方向按指标定义。
- 静态 `*_gaps` 字符串/正则计数不能作为性能优化的 keep 依据；最多只能充当结构守卫或次要指标。
- 每次目标变化时重新调用 `init_experiment`，并同步更新 `.auto/measure.sh`。
- 测量器必须同时验证行为正确性和性能改善，不得通过删除功能、减少数据、弱化规则或只迎合源码字符串使指标变好。
- 性能测量必须直接执行产品 Swift 代码或从产品中提取的同一纯函数；禁止用 Python/JavaScript 重写近似算法，再根据源码字符串选择循环次数来声称产品提速。
- 至少覆盖一个现实数据规模和一个压力规模；有效基线与候选各需两次完整测量，不能只各运行一次脚本。
- crash 的 `metric=0` 若污染 baseline/current best，必须开启干净 segment；出现 `Infinity%` 的比较不得 keep。
- 没有可复现基线、候选数据和至少一次最窄运行时验证时，必须 discard，不得 keep。

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
8. 每轮开始先读取 `.auto/SUPERVISION.md`；其中的暂停项、优先级和验收门槛高于 ideas backlog。
9. 当前模型没有可靠图片理解能力。任何截图、视觉回归、缩略图质量或 UI 图片验收必须暂停当前轮次，并新开使用 `CPA/gemini-3.6-flash-high` 的独立只读会话；不得由当前模型猜测图片内容。具体交接格式遵守 `.auto/SUPERVISION.md`。
10. 禁止继续以“一处无障碍修饰符 + 正则计数归零”的模式产生提交；共享且高影响的无障碍缺陷也必须先由监督会话确认。
11. 性能轮次只改与已测瓶颈直接相关的最少文件；不要顺手美化、改文案或扩大重构。
12. 不要每轮都运行完整 Xcode build。候选通过性能测量后再做一次最窄编译验证；纯基线不构建。
13. 当前未完成候选若没有运行时性能证据，应完成记录后 discard，不要仅凭静态文案指标 keep。

## What's Been Tried
已保留的近期改进包括：
- `ContentUnavailableViewCompat` 标题支持 VoiceOver header 导航。
- 通知卡片标题支持 VoiceOver header 导航。
- Photos 刷新按钮朗读加载值，并隐藏重复的进度环语义。
- Photos 卡片提供下载与删除命名无障碍动作，删除仍走确认。
- Photos 区分搜索无结果与真实空图库，并提供清除搜索操作与英中资源。
- Management / Utilities 已完成多轮字体、间距、图标、字段标签、badge、sheet 标题和加载语义收敛。

下一轮先读取 `.auto/SUPERVISION.md`，再从 `.auto/ideas.md` 的性能优先队列选择方向；若无法建立运行时基线，先做有界测量基础设施实验，不得退回微型无障碍/文案扫尾。
