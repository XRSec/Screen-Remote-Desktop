# Ideas Backlog

> 选择任务前必须先读取 `.auto/SUPERVISION.md`。当前阶段以 UI 性能为唯一主线，暂停微型无障碍、文案和 token 扫尾。

## P0：可感知 UI 卡顿

- [x] Photos P0 审计(2026-09-01):网格**不拉取、不解码任何图片**,卡片仅渲染 systemName 图标 + find/stat 元数据;原图拉取假设不成立,不实现 helper 缩略图。
  - 真实替代热点:parsePhotoList 在 MainActor 同步解析数千行 find/stat 输出,每行新建 ByteCountFormatter/DateFormatter/URL×2 + 全量 sorted。探测:500 张≈5.5ms、2000 张≈13.8ms、10000 张≈70ms。
  - 候选方向:解析逻辑提取为纯函数并在后台 Task.detached 执行,主线程仅赋值;把 imageExtensions/videoExtensions 改为 static let。待 harness 证实后再改产品。
- [ ] Apps / Photos / Notifications / Messages：建立可重复的大数据量过滤、排序和摘要生成基线，定位 `body` 重算或重复遍历热点。
- [ ] Root / Sidebar / ScreenTile：测量高频 session、电量、FPS、码率状态是否导致过宽 SwiftUI invalidation，确认后缩小观察或节流纯展示状态。
- [ ] 图片与图标：审计缓存、in-flight 去重、取消和后台解码，优先处理滚动/刷新中重复工作。

## P1：已保留提交的性能回归审计

- [x] Apps 搜索高亮审计(2026-09-01):2000 个 app 名×2 terms 全量高亮约 13.4ms,但 LazyVGrid 只渲染可见卡片(20-50 个),每 keystroke 可见卡片高亮 <1ms。非瓶颈,不修改。
- [x] Photos 搜索过滤修复(2026-09-01,keep 072949c):filteredPhotos 单 body 5 次访问→body 顶层 let 复用,搜索 5000 张 15ms→3ms(-78.5%)。Messages/Notifications 为占位数据(规模 0)。
- [ ] ScreenTile / Sidebar：检查新增状态摘要、overlay 和本地化格式化是否位于高频刷新路径。
- [ ] DeviceUtilities：仅在测量证明有价值时优化 section 内动作筛选；避免针对 8 个静态动作过度优化。

- [x] Messages 重复过滤审计(2026-09-01):filteredConversations 单 body 访问 6 次,但 conversations 是占位模型(无生产数据,规模 0),不值得优化。
- [x] Processes 重复过滤审计(2026-09-01):filtered 单 body 2 次(ForEach+count),800 进程搜索过滤约 0.5ms/次。收益边缘,SUPERVISION 反对为小收益优化,不做。
- [x] ScrcpyVideoSurface 高频发布审计(2026-09-01):每帧 @Published image+pixelSize,观察者重算是视频渲染本质需求,SwiftUI diff 已最小化重绘;拆分观察粒度属 scrcpy 核心改动,风险高收益不明,不做。
- [x] DeviceInformation/DeviceFiles/DeviceUtilities 审计(2026-09-01):过滤/排序依赖低频 snapshot 变化;DeviceUtilities 8 静态动作禁止过度优化。
- [x] Processes 解析主线程审计(2026-09-01):parseProcesses 在 MainActor 同步执行,但现实 600 进程仅约 1.4ms;后台化后主线程仍等 ~1.4ms 才显示,感知收益≈0。3000 进程压力档 7ms 为极端情况。不值得优化。
- [x] Processes/DeviceFiles 过滤复用审计(2026-09-01):单 body 2 次过滤(ForEach+count),现实规模 0.5-1.5ms/keystroke,收益边缘,不做。
- [x] ScreenSessionSnapshot/FPS/码率审计(2026-09-01):snapshot 无 FPS/码率高频字段;battery 60s 刷新;唯一每帧发布是 ScrcpyVideoSurface(image,渲染必需)。无未处理的过宽 invalidation。
## 暂停池：需监督明确批准

- [ ] Apps 分类 Chip 的纯样式调整。
- [ ] Notifications / Messages 的单点引导或配对文案调整。
- [ ] TopBar / Sidebar 的零散 typography、radius、spacing token 替换。
- [ ] Management / Utilities 的进一步纯装饰性分类或卡片调整。
- [ ] ScreenTile 的纯视觉“原生感”强化。
- [ ] 任意单个 VoiceOver label/value/header/action、单复数或空状态文案实验。
