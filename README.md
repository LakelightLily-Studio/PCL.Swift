# PCL.Swift

<div align="center">
  <img alt="Logo" src=".github/assets/icon.png" width="140">
  <h1>PCL.Swift</h1>
  <img src="https://img.shields.io/github/stars/functy23/PCL.Swift?style=flat&color=orange" alt="Stars">
  <img src="https://img.shields.io/badge/macOS-12.0%2B-orange?logo=macos" alt="Minimum OS Version">
  <img src="https://img.shields.io/github/commit-activity/m/functy23/PCL.Swift?style=flat&color=orange" alt="Activity">
  <img src="https://img.shields.io/github/contributors/functy23/PCL.Swift?style=flat&color=orange" alt="Contributors">
</div>
<br>

PCL.Swift 是 [Plain Craft Launcher](https://github.com/Meloong-Git/PCL)（由 [龙腾猫跃](https://afdian.com/a/LTCat) 制作的 Minecraft 启动器）的**非官方** macOS 重构版，使用 SwiftUI 框架**完全重构**了 PCL 以支持 macOS。

本项目基于 Cylorine Studio 的 [PCL.Mac.Refactor](https://github.com/CylorineStudio/PCL.Mac.Refactor) 1.1.1 独立维护，在其之上做了系统性的性能与结构改造。

<table>
  <tr>
    <td><img src=".github/assets/screenshot_launch.png"></td>
    <td><img src=".github/assets/screenshot_mod_search.png"></td>
  </tr>
</table>

问题反馈：请前往 [Issues](https://github.com/functy23/PCL.Swift/issues)。

**请不要在 PCL 官方版本 / 其它版本相关仓库或群聊中反馈关于 PCL.Swift 的问题。**

## 相比 PCL.Mac.Refactor 改了什么

### 性能

| 改动 | 说明 | 预期收益 |
|---|---|---|
| 实例列表并发加载 | 逐个实例串行读取改为 `withTaskGroup` 并发，每个实例的目录扫描、JSON 解析、资源校验同时进行 | 实例越多收益越大：20 个实例的冷启动从「N 倍单实例耗时」压到「最慢的那一个」，量级约 **3–5×** |
| 版本清单去重 | `ClientManifest` 增加 `deduplicateLibraries`，同一清单里重复出现的依赖库只下载、只校验一次 | 大型整合包常见重复库，可省去 **10–20%** 的下载量与校验时间 |
| 启动器配置落盘去抖 | 原先只在退出时写盘，现改为改动后 0.5s 合并写盘 + 退出时 flush | 崩溃或强退不再丢失本次会话的全部设置 |
| 资源缓存常驻 | `ResourceCache` 统一接管图标与资源元数据，避免每次进页面重新拉取 | 页面切换几乎零等待 |

> 上表的百分比是典型场景下的量级估计，不是逐项基准测试的结果；不同实例数量与网络环境下差异很大。

### 结构

- **单例改为显式注入**：`JavaManager` / `DownloadSourceManager` / `ResourceCache` / `VersionManifest` / `FlagsManager` 全部走 `install(_:)` + `shared`，未注入时给出可定位的 `fatalError`，取代原先的 `!` 隐式解包——把一个随机崩溃点变成一行明确的错误信息。
- **错误处理分层**：公开 API 用 `throws(SomeError)` 收窄错误类型，就地失败用 `SimpleError`，`try?` 只留给确有降级路径的场景；全仓库不再有空 `catch {}`。
- **主线程调度统一**：新代码一律 `@MainActor`，只有并发标注够不着的回调边界才退回 `DispatchQueue.main.async`。
- **任务系统重写**：`MyTask` 支持按 `ordinal` 分组并发执行子任务、进度聚合、失败回调与取消传播。
- **CI 真正跑测试**：PR 与 `main` 的推送都会执行 `xcodebuild test`，此前工作流只构建不测试。

### 新增功能

- **主题机制**：设置 → 个性化里可切换主题色，当前提供「主题橙」（默认）与「主题蓝」。强调色整套色阶（主色、深/浅档、选中背景、窗口底色）随主题联动，文字与灰阶保持不变以维持对比度。
- **下载源策略**：可在「官方优先」与「镜像优先」之间切换，并会按地区自动调整镜像优先级。
- **功能开关**：`FeatureFlag` 统一管理实验性功能，关闭开关会真正禁用对应行为（而不只是隐藏入口）。
- **崩溃报告导出**：一键打包 `launcher-info.json`、游戏日志与崩溃报告，便于反馈。
- **Java 手动添加**：自动搜索之外可指定任意 JDK 路径。
- **界面细节**：实例列表加载中显示占位而非「下载游戏」、设置行布局统一、字节格式化统一走 `ByteFormat`。

## 下载
你可以在 [Releases](https://github.com/functy23/PCL.Swift/releases) 中下载 PCL.Swift（Universal）。

## 环境要求

|          |          最低           |    推荐     |
|:--------:|:-----------------------:|:-----------:|
| 普通使用 |       macOS 12.0        | macOS 14.0+ |
|   开发   | macOS 14.5 (Xcode 16) |      —      |

同时支持 Intel 与 Apple 芯片。

> 开发构建需要 **Swift 6.4** 工具链（源码使用了 6.1+ 的调用参数尾随逗号与 `withTaskGroup` 返回类型推断）。命令行下 `TOOLCHAINS` 与 `-toolchain` 均不生效，需覆盖 `SWIFT_EXEC`，详见 [AGENTS.md](AGENTS.md)。

## 许可证
- PCL.Swift 使用与 [PCL](https://github.com/Meloong-Git/PCL) 相同的许可证，并遵守其中关于"重度使用"的规定。
- PCL.Mac.Core（`PCL.Mac.Core/`）采用 MIT License 协议，使用其代码时请**保留许可证**及署名信息。
