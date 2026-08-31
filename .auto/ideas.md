# Ideas Backlog

> 选择任务前必须先读取 `.auto/SUPERVISION.md`。当前阶段以 UI 性能为唯一主线，暂停微型无障碍、文案和 token 扫尾。

## P0：可感知 UI 卡顿

- [ ] Photos：测量网格预览的远程传输字节、原图/缩略图尺寸、重复请求和解码线程；确认瓶颈后，通过现有 dadb helper 生成受控尺寸缩略图。
- [ ] Apps / Photos / Notifications / Messages：建立可重复的大数据量过滤、排序和摘要生成基线，定位 `body` 重算或重复遍历热点。
- [ ] Root / Sidebar / ScreenTile：测量高频 session、电量、FPS、码率状态是否导致过宽 SwiftUI invalidation，确认后缩小观察或节流纯展示状态。
- [ ] 图片与图标：审计缓存、in-flight 去重、取消和后台解码，优先处理滚动/刷新中重复工作。

## P1：已保留提交的性能回归审计

- [ ] Apps 搜索高亮：在大应用列表和持续输入场景测量多范围搜索、排序与分段 `Text` 的成本；没有显著回归则不修改。
- [ ] Photos / Messages / Notifications 搜索：确认统一查询后是否仍为标题、空状态、列表和选择同步重复计算相同过滤结果。
- [ ] ScreenTile / Sidebar：检查新增状态摘要、overlay 和本地化格式化是否位于高频刷新路径。
- [ ] DeviceUtilities：仅在测量证明有价值时优化 section 内动作筛选；避免针对 8 个静态动作过度优化。

## 暂停池：需监督明确批准

- [ ] Apps 分类 Chip 的纯样式调整。
- [ ] Notifications / Messages 的单点引导或配对文案调整。
- [ ] TopBar / Sidebar 的零散 typography、radius、spacing token 替换。
- [ ] Management / Utilities 的进一步纯装饰性分类或卡片调整。
- [ ] ScreenTile 的纯视觉“原生感”强化。
- [ ] 任意单个 VoiceOver label/value/header/action、单复数或空状态文案实验。
