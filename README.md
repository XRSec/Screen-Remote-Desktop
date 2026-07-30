# Screen Remote for macOS

一个使用 SwiftUI 构建的 macOS 原生 Android 设备协同界面原型，信息架构参考 Phone Link。

## 当前范围

- 可折叠的多设备侧栏
- 应用、通知、信息和相册四个页面
- ADB 与 scrcpy 路径配置和本地可执行文件检测
- 浅色/深色模式适配

当前页面使用示例数据。后续建议用独立 service 封装 `Process` 调用 ADB 与 scrcpy，UI 只依赖协议化的数据源。

## 运行

用 Xcode 打开 `ScreenRemote.xcodeproj`，选择 **ScreenRemote** scheme 后运行。支持 macOS 11 及更新版本。

## 第三方能力建议

- 屏幕镜像：调用官方 scrcpy 可执行文件
- 设备与应用：调用 Google platform-tools 中的 adb
- 通知与短信：需要 Android companion 或 KDE Connect 协议，普通 ADB 不足以稳定提供完整能力
