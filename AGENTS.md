# AGENTS.md

给在本仓库里工作的 AI 代理（以及第一次接触本仓库的人类贡献者）的说明。
**本文件只写"代码本身看不出来"的东西**：命令、目录归属、以及反复出现、必须统一取舍的约定。
具体规范细节见 [CONTRIBUTING.md](CONTRIBUTING.md)，用户文档见 [README.md](README.md)。

## 项目是什么

PCL.Swift 是 [Plain Craft Launcher](https://github.com/Meloong-Git/PCL)（Minecraft 启动器）的**非官方** macOS 重构版，
SwiftUI 实现，源自 Cylorine Studio 的 PCL.Mac.Refactor 1.1.1。许可证沿用上游 PCL 的条款；
`PCL.Swift.Core/` 单独采用 MIT，复用其代码必须保留 `PCL.Swift.Core/LICENSE` 与署名。

目录名（`PCL.Swift/` / `PCL.Swift.Core/` / `PCL.Swift.Tests/`）、Target 名与工程名都随 2.0 改成了
PCL.Swift；只有 **Swift 模块名仍是 `Core`**（`import Core`），改它要动几百处 import，收益为零。

数据目录在 2.0 由 `PCL.Mac.Refactor` 改名为 `PCL.Swift`，`URLConstants` 里带一次性迁移：
旧目录存在且新目录不存在时整体 move 过去，迁移失败则继续用旧目录，避免用户丢数据。

- 最低系统：App 与 Core 为 macOS 12.0，测试 Target 为 14.0（见 `Configs/*.xcconfig` 与 pbxproj）。
- 同时支持 Intel 与 Apple Silicon，不要引入只对单一架构成立的假设。
- 版本号唯一来源是 `Configs/Base.xcconfig` 的 `MARKETING_VERSION`；`CURRENT_PROJECT_VERSION` 由 CI 用
  `git rev-list --count HEAD` 覆盖，本地不要手改。

## 构建与测试

用 Xcode 工程，没有 SwiftPM 包清单（依赖走 Xcode 的 SPM 集成，锁定在
`PCL.Swift.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`）。

```bash
# 推荐：用 `Scripts/xcodebuild-swift.sh`，它会自动挑可用的 Swift 工具链
Scripts/xcodebuild-swift.sh build Debug
Scripts/xcodebuild-swift.sh build Release
Scripts/xcodebuild-swift.sh test
Scripts/xcodebuild-swift.sh clean          # 只清构建产物

# 第 4 个及之后的参数原样透传给 xcodebuild
Scripts/xcodebuild-swift.sh test Debug "" -resultBundlePath ./result.xcresult

# 等价的原始命令（Swift 6.4 工具链）
xcodebuild build -project PCL.Swift.xcodeproj -scheme PCL.Swift -configuration Debug \
  -destination 'platform=macOS' \
  SWIFT_EXEC=/Library/Developer/Toolchains/swift-latest.xctoolchain/usr/bin/swiftc

# 只跑单元测试 Target
xcodebuild test -project PCL.Swift.xcodeproj -scheme PCL.Swift -destination 'platform=macOS' \
  -only-testing:PCL.Swift.Tests
```

### 必须用 Swift 6.4，不能用 Xcode 自带的 6.0

源码里用了 **Swift 6.1+ 才支持的调用参数尾随逗号**（`f(a, b,)`），Xcode 16.0 自带的
Swift 6.0 会直接报 `unexpected ',' separator`；此外 `MinecraftRepository` 里不写 `of:`
的 `withTaskGroup` 也依赖新编译器的推断。两者都不是 bug，**不要为了迁就旧编译器去删它们**。

命令行下选工具链有三个坑（都实测过）：

| 写法 | 结果 |
|---|---|
| `TOOLCHAINS=swift-6.4.0-RELEASE` | 无效。目录名不是合法标识符，被静默忽略，仍用 6.0 |
| `TOOLCHAINS=swift-latest` / `xcodebuild -toolchain ...` | 同样无效 |
| `TOOLCHAINS=org.swift.640202609131a` | 标识符对了，但 SPM 解析阶段因 `-disallow-use-new-driver` 直接崩 |
| **`SWIFT_EXEC=<6.4 的 swiftc>`** | ✅ 唯一可靠；保留 Xcode 的 SDK/clang，SPM 正常 |

Xcode UI 里选工具链能起来，是因为 GUI 走的是另一条解析路径，与命令行不同。

### 警告基线：哪些该修，哪些是噪音

用 6.4 工具链构建时会比 Xcode 自带的 6.2.1 多出一批并发诊断（实测同一份代码 6.2.1 报 0 条、6.4 报 14 条）。
**这些不是 6.4 的 bug，是它在 Swift 5 语言模式下提前预演 Swift 6 的错误**，该修的要修，不该动的别动：

| 诊断 | 处理 |
|---|---|
| `ld: warning: building for macOS-12.0, but linking with dylib ... built for newer version 13.0` | **无视**。这是 6.4 工具链自带的运行时库本身标了 `minos 13.0`，与项目代码无关：空文件 `print(1)` 同样会报，换 Xcode 自带 swiftc 就不报。消除它只能把部署目标抬到 13.0，等于放弃 macOS 12 支持 |
| `reference to captured var 'self' in concurrently-executing code` | **修**。`[weak self]` 捕获出的是可变 optional，在 `@Sendable` 闭包里读它就是 Swift 6 的硬错误。把状态写入收进 `@MainActor` 方法，用 `await self?.方法()` |
| `'weak' ownership of capture 'self' differs from implicitly-captured strong reference` | **修**。外层闭包已隐式强捕获 `self`，内层再 `[weak self]` 是自相矛盾的写法。统一成外层 `[weak self] + guard let self` |
| `unstructured throwing task ... is not used` | **修**，这是真有 bug：`Task { try f() }` 的错误没人接会被静默丢弃。`_ = Task { ... }` 或 `try?` 只是把警告藏起来，正确做法是让被调函数返回 `Bool` 供 `guard` 判断，或在 Task 内显式 `do/catch` 并记日志 |
| `conformance of 'Model' to protocol 'TaskModel' may be isolated ...` | **暂不修**。`Model` 没有 `Sendable` 约束，而 `MyTask` 的子任务要并发跑。加 `Sendable` 得给所有 Model 挂 `@unchecked Sendable`（等于关掉检查），标 `@MainActor` 则废掉并发——两者都比留着警告更糟，等迁 Swift 6 时连同 `MyTask` 的并发模型一起重构 |

另外 `appintentsmetadataprocessor` 的 `Metadata extraction skipped` 也是噪音，项目没用 AppIntents。

**清缓存不会让警告重现**：警告只在真正重新编译某文件时出现，`xcodebuild` 命中缓存就什么都不报。要复核诊断得先
`find PCL.Swift PCL.Swift.Core -name '*.swift' -exec touch {} +` 再构建。

### 源码目录里不要留草稿文件

工程用 **FileSystemSynchronizedRootGroup**，目录里的任何文件都会自动入 Target。`.bak` / `.orig` 一类后缀不参与
编译，但**会被当成资源原样拷进 App 的 `Contents/Resources`**（实测过）。所以 `.gitignore` 里挡掉了它们；
删掉源码树里的这类文件后若构建仍报 `lstat(...): No such file or directory`，那是 DerivedData 里的陈旧快照，
清一次构建缓存即可，不是源码问题。

### 开发期专用能力只在 Debug 构建里

`Configs/Debug.xcconfig` 定义了 `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) PCL_DEV_TOOLS`，
`Release.xcconfig` 不定义。所以 `#if PCL_DEV_TOOLS` 包住的代码在正式版里**根本不参与编译**，
不是「编进去再在运行时藏起来」——没有可被误触发的入口，也没有多余符号。
实现在 `PCL.Swift/App/DevTools.swift`（整个文件在这个条件里）：

| 快捷键 | 作用 |
|---|---|
| ⌘R | 重播「开场动画 → 设置向导 → 启动器」整段流程（`StartupFlow.restartOnboarding()`）。不改 `hasCompletedOnboarding`：重播只是回看流程，中途退出下次仍直接进启动器，走完向导时 `finishWizard()` 会重新置 true |
| 1 / 2 / 3 / 4 | 切到顶栏的 启动 / 下载 / 设置 / 更多 |

约定：

- 新增开发期能力一律走这个条件，**不要**用 `FeatureFlag`、环境变量或启动参数做门控：那些会被正式版带上，
  还要额外维护「什么时候不该触发」的判断。
- 调用点也要包在 `#if PCL_DEV_TOOLS` 里（参考 `AppDelegate.addEscapeMonitor`），否则 Release 下会报找不到符号。
- 快捷键一律在 `NSEvent` 的本地监听里判断，副作用跳回主线程执行；弹窗打开时不拦截（对话框要用 Esc / 回车），
  文本框正在编辑时数字键属于输入内容，也不能拦截。
- 联机页不占数字键：它由功能开关控制，同一个键不该在不同开关状态下跳到不同页面。
- 验证剔除是否真的生效：Release 构建后 `grep -ac '开发工具' .../PCL.Swift.app/Contents/MacOS/PCL.Swift` 应为 0，
  `nm -U` 里不应出现 `DevShortcuts`；同一份检查在 Debug 产物上应分别得到 1 与若干符号。
- demo 分支的 `DemoState` 是另一回事（重播卡片进入动画 + 演示资源快照），不要和这里混用。

### 图标只有 Xcode 26 能编

- `PCL.Swift/AppIcon.icon` 是 Icon Composer 格式，只有 Xcode 26 的 `actool` 会把它编译成 `AppIcon.icns`，
  并写入 `CFBundleIconFile` / `CFBundleIconName`。用 Xcode 16 打包时它只会被当成普通资源拷进
  `Contents/Resources/AppIcon.icon`，产物**没有 icns**，Finder / Dock 显示空白图标（2.0.1、2.0.2 就是这样）。
- 所以**发版请走 CI**：`gh workflow run build.yml -f build_configuration=Release -f arch=arm64 -f sign_app=false`
  （`arch` 取 `arm64` 或 `x86_64`；2.0.4 起按架构分开出包，**不再打通用二进制**，两个架构各跑一次）
  （`sign_app=false` 跳过证书导入、改用 ad-hoc 签名，不需要 `MACOS_*` secret）。
- 取 CI 产物要用 `gh api repos/<owner>/<repo>/actions/artifacts/<id>/zip` 再 `ditto -x -k` 解压，
  **不要用 `gh run download`**：它用 Go 的 zip 解压，会把框架里的 `Versions/Current` 符号链接写成普通文件，
  框架签名随即失效（`codesign --verify --deep` 报 not signed at all），App 也起不来。

测试相关的事实：

- 测试框架是 **swift-testing**（`import Testing`、`@Test`、`#expect`），不是 XCTest。新增测试不要混入 XCTest。
- 测试 Target 会以 `PCL_MAC_TESTING=1` 启动宿主 App（见 `Configs/PCL.Swift.xctestplan`）。`AppDelegate.shouldInit`
  据此跳过窗口、字体、缓存等真实初始化；**新增启动期副作用时必须尊重这个开关**，否则测试会去碰用户的
  `~/Library/Application Support`。
- 依赖真实网络的测试用 `TestEnvironment.networkAvailable`（`@Test(.enabled(if:))`）门控，默认跳过；
  本地要跑全量时设 `PCL_MAC_NETWORK_TESTS=1`。
- CI：`pr-test.yml`（PR 上构建 + 测试）、`test.yml`（push 到 main 时测试）、`build.yml` / `release.yml`（归档、签名、
  公证、发 Release）。**不要在同一次提交上重复加触发条件**，PR 与 main 的分工已经在两个文件里写好。

## 目录归属

| 目录 | 内容 | 注意 |
|---|---|---|
| `PCL.Swift.Core/` | 与 UI 无关的核心逻辑：模型、下载、认证、Minecraft/Forge/NeoForge 安装、资源解析、任务系统 | 独立模块 `import Core`；**不得 import SwiftUI/AppKit 做 UI**；改动需保持 macOS 12.0 可用 |
| `PCL.Swift/` | App 本体：SwiftUI 视图、路由、AppDelegate、启动器配置 | 依赖 Core，反向依赖不允许 |
| `PCL.Swift.Tests/` | swift-testing 测试 | 只测可测的部分：纯逻辑、解析、编排；UI 不写快照测试 |
| `Configs/` | `Base/Debug/Release.xcconfig` 与 `PCL.Swift.xctestplan` | 版本号、`DEBUG_MODE` 在这里定义 |
| `Resources/` | `Localizable.xcstrings`、字体、`Secrets.properties`、第三方 LICENSE | 见下方"密钥" |
| `Packaging/` | DMG 背景图与 `.DS_Store` 布局 | 由 `release.yml` 使用 |
| `PCL.Swift.xcodeproj/` | 工程文件 | **用 FileSystemSynchronizedRootGroup**：新增 `.swift` 文件放进目录树即自动入 Target，不要再手工加 `PBXBuildFile` |

## 首次启动流程（开场动画 → 向导 → 启动器）

三段是**同一个 `AppWindow`**，靠 `StartupFlow.stage` 切换（`App/RootView.swift` 按 stage 分发）。
唯一变化的是窗口尺寸，由 `AppWindow.applyStartupStage(_:animated:)` 负责：

| 阶段 | 窗口 | 说明 |
|---|---|---|
| `.onboarding` | 370×450，不可缩放、隐藏三色按钮 | 移植自 XcodeNewBegining 的开场动画（`Views/Startup/StartupOnboardingView.swift`），主色取 `Theme` 的当前主题 |
| `.wizard` | 1000×550 起，放开缩放 | 设置向导（`Views/Startup/SetupWizardView.swift`）：欢迎 → 账号 → Java → 主题 → 完成，「跳过」只跳当前步 |
| `.launcher` | 同上 | `ContentView`，即原来的启动器主体 |

几条约定：

- 首启判定用 **`LauncherConfig.hasCompletedOnboarding`**（向导点「完成」时置 true），不要复用 `hasEnteredLauncher`：
  后者仍由旧的欢迎弹窗维护，两者语义不同（旧配置缺这个键会解码为 `false`，于是升级后首启会再播一次，属预期）。
- 窗口尺寸切换必须走 `StartupFlow`，不要在视图里直接改 `NSWindow`：动画阶段窗口是受尺寸锁的，
  视图侧改尺寸会被 `minSize == maxSize` 顶回去。
- 更新检查（`UpdateService.runInteractiveUpdateFlow`）依赖 `ContentView` 里的弹窗层，只在进入 `.launcher` 后发起；
  欢迎弹窗同理，只在 `.launcher` 阶段显示。
- **demo 与 main 只差演示功能**，其余（首启流程、DSH、窗口修复等）两边必须一致。demo 额外带的只有：
  `DemoState`（⌘R 重播开场 + 1–4 切顶栏页）、`DemoResourceCatalog`（资源列表读打包快照）、
  `Resources/demo/` 图标，以及它们依赖的三处改动（`ModrinthAPIClient.SearchResponse` 的公开 init、
  `ResourcesSearchViewModel` 换数据源、`NetworkImage` 支持 `file://`）。
  **同步时把这几处连同 demo 专用文件一起留在 demo，不要带进 main。**
- 开场动画里不能再用 13+ 才有的 API（`AnyLayout`、`.bouncy`、`.rect`）：App 的最低部署目标是 12.0，
  动画改成了 `.interpolatingSpring` + 手写分支布局。
- 品牌标识分两处，**不要互相挪用**：开场动画用 `iconAppIcon`（App 图标本体）；启动器标题栏用
  `iconTitleLogo` 的白色「PCL」字标（配右侧 `Swift` 标签读作 PCL.Swift）。
- 窗口外壳全由 `AppWindow` 管：三色按钮只保留关闭与最小化；缩放按钮在 `windowDidUpdate` 里持续隐藏
  （AppKit 会在尺寸动画 / 成为主窗口时把它写回来）。
- 三色按钮的位置由 `alignWindowButtons()` 统一修正：透明标题栏下 AppKit 按标准 28pt 摆放，而本 App 的
  标题栏是 48pt，需要整体下移居中。**每次窗口布局后都要重做**——`windowDidUpdate` 之外，
  `windowDidResize` / `windowDidEndLiveResize` 也要补一次（异步、且用标记合并高频通知），
  否则用户拖动改变窗口大小后按钮会错位。`TitleBarView.trafficLightReservedWidth` 与它配套。
- 消息框与提示条挂在 `RootView` 而不是 `ContentView`：向导阶段要弹正版账号的设备码，那时
  `ContentView` 还不存在。遮罩层要 `.ignoresSafeArea()`，否则顶部会缺一条（各阶段视图本身都忽略安全区）。
- 向导阶段的顶栏与启动器共用同一块 48pt 主色栏：栏内显示当前步骤的大标题（欢迎来到 PCL.Swift /
  登录账号 / 选择 Java / 选择主题 / 完成配置），页面内不再重复标题；标题左侧按
  `TitleBarView.trafficLightReservedWidth` 让开三色按钮。改标题文案时改
  `SetupWizardView.Step.pageTitle`，不要在两处各写一份。
- 完成页是独立的庆祝页：不显示步骤条、分隔线和配置摘要，只保留居中「设置完成」、左下角彩带和底部「完成」；
  彩带在 `Views/Startup/ConfettiView.swift`，用 Canvas + TimelineView 绘制，粒子种子固定，
  不要改成每帧随机（否则同一场动画会抖动）。
- 向导背景是固定 64pt 线距的无限纯网格（只有横竖线，没有对角线），实现在
  `Views/Startup/WizardGridBackground.swift`；不要改回 5×5 固定分割或对角线，否则窗口变大时会被拉稀。
- 导航栏背景有「纯色 / 线格」两种，存在 `LauncherConfig.navigationBarBackground`，由
  `Components/NavigationBarBackgroundView.swift` 统一绘制，向导顶栏与启动器顶栏共用；
  「线格」是主题色底 + 白色网格。
- 窗口的 `contentView` 是普通 `NSView` 包着 `NSHostingView`（`sizingOptions = []`）：直接把 hosting view
  当 contentView 时，SwiftUI 的理想尺寸会顶穿窗口（向导的 ScrollView 曾把窗口撑到 1361pt）。

## 启动设置的两层结构

启动参数分「全局默认值」与「实例覆盖值」两层，字段一一对应：

| 全局 | 实例 | 语义 |
|---|---|---|
| LauncherConfig.gameWindowType / Width / Height | 同名 | 实例为 nil 时跟随全局 |
| LauncherConfig.launcherVisibility | launcherVisibility | 同上 |
| LauncherConfig.processPriority | processPriority | 同上 |
| LauncherConfig.prelaunchCommand | prelaunchCommand | 同上 |
| LauncherConfig.gameArguments | gameArguments | 同上 |
| LauncherConfig.jvmArguments | jvmArguments | **例外**：实例非空即完全替换，不做拼接 |
| LauncherConfig.memoryMode / memory | memoryMode / jvmHeapSize | 实例 memoryMode 为 nil 跟随全局；automatic 按 Mod 量现算；custom 用 jvmHeapSize |
| LauncherConfig.garbageCollector | —— | 只有全局设置，实例不覆盖 |
| LauncherConfig.preferredJavaURL | javaURL | 实例选过 Java 就以实例为准，否则用全局默认；都没有时由 JavaSearcher 自动挑 |

合并规则只有一处实现：PCL.Swift/Managers/LaunchSettingsResolver.swift 的
ResolvedLaunchSettings.resolve(instance:global:)。**不要在别处再写一遍 if-let**，
否则会出现「界面显示跟随全局、启动却用了旧值」。

实例设置页**没有「保存设置」按钮**：绑定改动即生效，落盘由
InstanceConfigViewModel.scheduleAutoSave() 做 0.4s 防抖（拖滑杆、连续输入都是高频事件）。
新增可写字段时给 @Published 属性加 `didSet { scheduleAutoSave() }`，否则界面改了、重启就丢。

全局默认 Java 经 LauncherConfigDefaults 传给 Core（Core 读不到 App 层的 LauncherConfig）：
AppDelegate 启动时灌一次值，设置页改动时同时写 LauncherConfig 与那份副本，两处缺一不可。
启动时的解析顺序写在 MinecraftLaunchTask.checkJava：实例 javaURL → LauncherConfigDefaults.preferredJavaURL → JavaSearcher.pick。

进程优先级的实现分两步，缺一不可（MinecraftLauncher）：

- `applyQualityOfService` 在 `process.run()` **之前**设 `Process.qualityOfService`
  （高 userInteractive / 中 default / 低 utility）。这是不提权唯一能真正影响
  内核调度的手段，而且必须在启动前设：进程跑起来后 Java 自己创建的线程按默认
  QoS 生成，事后再改进程也没有追溯效果。
- `applyProcessPriority` 在 `run()` 之后按 pid 调 `setpriority`（高 -5 / 低 10 /
  中不调用）。**niceness 调负值需要 root**，普通用户一定拿 EPERM，所以「高」
  实际靠 QoS 生效，setpriority 只是尽力而为；失败只记日志，不影响启动。

原来那个「内存优化」开关已删除：它只是释放启动器自己的图标缓存，
对游戏进程没有任何作用，留着只会误导用户。

### 内存分配与垃圾回收器

设置 → 启动页按 PCL2 的 PageSetupLaunch 排版（启动选项 / 内存分配 / 高级选项），
数值与参数全部对齐原版：

- 「自动配置」的推荐值来自 Core 的 `MemoryAllocation.recommendedGigabytes`（PCL2 的
  四阶段算法），「自定义」的滑杆是 `0…49` 的分段线性映射，两者都**不要在视图里另算**。
  实例配置里的 `memoryMode`/`jvmHeapSize` 是三态：nil 跟随全局、automatic 按该实例的
  Mod 量现算、custom 用 `jvmHeapSize`。老配置没有 memoryMode，解码时按「有 jvmHeapSize
  就是 custom」处理，升级不会被改写。
- 垃圾回收器是 `GarbageCollectorMode`（rawValue 对齐 PCL2 的 LaunchAdvanceGC）。参数由
  `GarbageCollectorArguments` 按 Java 大版本派生，派生方式参考 Swift-Craft-Launcher：
  存枚举、启动时生成，**不要**把 GC 参数写进 `jvmArguments` 字符串再反解析。
- `MinecraftLauncher.applyGarbageCollector` 会**先剔除**清单与自定义参数里由本启动器
  托管的 GC 项（`-XX:+Use*GC`、G1 调参、`ZGenerational`、`UseCompactObjectHeaders`）再追加，
  否则清单自带的 `-XX:+UseG1GC` 会按「最后一次出现生效」覆盖用户选的 ZGC。
- 与 PCL2 的差异只有平台性的三处：离线皮肤整卡不做；Java Launch Wrapper / LWJGL Unsafe
  Agent / 高性能显卡是 Windows 补丁；「启动前内存优化」依赖 EmptyWorkingSet，macOS 无等价物。

LauncherVisibility.resolve(instance:) 在 Core 里，因为启动器窗口那一侧也要判断；
它读的是 LauncherConfigDefaults——Core 不能反向引用 App 层的 LauncherConfig，
所以由 AppDelegate.applicationWillFinishLaunching 把值灌进去。

窗口参数（--width / --height / --fullscreen）由 MinecraftLauncher.applyWindowArguments
统一接管：先剔除清单自带的那几个，再按设置补一套。清单自己就带窗口参数，
直接追加会得到两套同名参数，实测游戏两套都不认。

启动前命令**总是等待执行完成**（原来那个「等待命令完成」开关已删除）：命令的典型用途是
清理缓存、关软件，不等它结束就等于把后续步骤和它并发跑。

## 实例元数据的存放

displayName / customIconURL / customDescription / isFavorite / category
写在实例目录的 .clmetadata.json 里，与 uuid、version 同文件。

- **不改文件夹名**：name 同时是目录名、清单文件名与启动参数 version_name 的来源，
  改名要连带搬目录、改清单引用，失败会留下半截实例。所以显示名只影响界面。
- 解码全部用 decodeIfPresent + 默认值：老版本写出的文件没有这些键，
  不能因此让整份元数据解码失败。
- 自定义图标会**复制**进实例目录（.clicon.png），不记住外部路径——
  外部文件随时会被删，记住路径等于让图标在某个时刻静默消失。

## 主题系统

Theme 只给「基色」，其余 7 档由 ThemePaletteBuilder 按固定比例与白/黑混出。
新增主题只需加一个 case 和 baseHex，不要手写十几档色值（一定会漂移）。

- Color.colorN 全部读 ThemeManager.shared.palette，不直接读枚举。
- 设置页用五列圆形单选框切主题（MyRadioBox + Theme.allCases，与原版一致）；
  只有向导还在画候选色卡，画色卡时必须用 ThemeManager.palette(for:)，不能读"当前主题"。
- 自定义主题存 HSB 三值（themeHue / themeSaturation / themeBrightness），
  视图树的重建标识是 ThemeManager.revision（含三值），
  只拿主题名当 id 的话拖滑杆不会刷新。

## 背景图片

对齐 PCL2 的 FormMain.ImgBack + PageSetupUI 的「背景图片」卡片：

- 图片来源有两种，优先级从高到低：
  1. 用户在设置里**指定的单张图片**（`LauncherConfig.backgroundImageURL`，设置页的「选择图片」）；
  2. 数据目录 `Pictures/` 里随机一张（`URLConstants.picturesDirectoryURL`，对应原版 `PCL/Pictures/`）。
  `BackgroundImageManager.refresh` 先看指定图、再退回文件夹；指定图打不开时会自动解绑并退回随机图，
  不会让背景静默消失。设置页只有两个按钮：**选择图片**（指定一张）与**清除**
  （解绑 + 删除图片文件夹里的图 + 撤下背景，带确认框）。原来那个「刷新背景图片」（重新随机）
  已经删掉——背景既然由用户指定，「再随机换一张」没有意义。
  启动时由 `AppDelegate.applicationWillFinishLaunching` 触发一次 `refresh(random: true)`。
- 渲染在 `Components/BackgroundImageView.swift`，挂在 `ContentView` 里标题栏以下那层
  `HStack` 的 `.background`：卡片与侧边栏画在它上面。四个参数都存在 LauncherConfig
  （`backgroundImageSuit` / `backgroundImageOpacity` / `backgroundImageBlur` / `backgroundColorful`），
  rawValue 与顺序照搬原版的 UiBackgroundSuit / UiBackgroundOpacity / UiBackgroundBlur / UiBackgroundColorful。
- 模糊要**把整层按半径放大**（`scaleEffect`，倍率 = 1 + 4·半径 / 短边，封顶 1.5）：
  模糊的衰减范围约 2 倍半径，不放大就会在四边透出底下的页面底色，
  看起来像「四周掺了一圈糊掉的原背景」。
  **不要用负内边距做这件事**：`padding(-x)` 会让内容在自己的小盒子里居中、原点跑到 (-x, -x)，
  模糊一开整张图就明显往左上偏——这正是上一版的 bug。
- 有背景图片时侧边栏底板换成 94% 白（原版 `ColorBrushBackgroundTransparentSidebar`），
  否则图片会被纯白底板整块挡住。**不要改成完全透明**：卡片与文字会压不住花哨的图片。
- 「叠加彩色背景」关掉时页面底色退回 `colorGray8`（原版 `#f5f5f5`），在 `ContentView` 的
  `.background` 里按 `LauncherConfig.shared.backgroundColorful` 二选一。

## 页面入场动画

卡片（MyCard / StaticCard）的入场动画统一走 PCL.Swift/Components/PageEntrance.swift，
它是对 PCL2 `MyPageRight.TriggerEnterAnimation` 的移植，不是"看起来差不多"的 spring：

- 元素从 y = -16 起始，350ms 内滑到原位：前 250ms 用 easeOutQuad 补 5pt、
  350ms 用 `1 - (1-t)^1.5·cos(1.5πt)`（PCL 的 AniEaseOutBack）补剩下 11pt，
  两段叠加出末尾约 1.5pt 的过冲；同时 100ms 内 easeOutQuad 淡入。
- SwiftUI 同一个 offset 只能挂一条动画，所以位移/透明度是在一个
  `ViewModifier + Animatable` 里按公式逐帧算出来的，外部只驱动一条**线性**动画。
  **不要给它换成 .spring 或 .easeOut**：缓动会被施加两次。
- 相邻卡片的错峰来自 `.cardIndex(n)`（**25ms/步，封顶 8 步**）。新页面记得给卡片编号，
  否则整页会同时出现（全页 index 都是 0 = 同时入场）。
  注意 PCL2 的错峰单位是"页面级控件"（卡片 / 提示条 / 按钮各算一格，卡片内部不再遍历），
  不是卡片内部每个文字；所以 25ms 的步长就是原值。
- `disableCardAppearAnimation` 仍然有效：自定义主题拖滑杆会重建整棵树，
  那种情况下不该重播入场动画。

## 页面退场动画

PCL2 切页不是"新页面直接盖上来"：旧页面先播退场，110ms 后才换容器，140ms 新页面入场
（`FormMain.PageChangeAnim`）。SwiftUI 里视图移出视图树是瞬时的，所以这是一层**调度**问题，
不是修饰器问题：`App/PageTransition.swift` 多存一份 `presentation`（页面 + 是否正在退场），
路由变了只触发 `request()`，退场跑完才一次性换页面。页面与侧边栏都只认 `presentation.route`，
`AppRouter.path` 与标题栏仍即时更新（原版也是先改状态再播动画）。

- **页面内容**（`Components/ControlExit.swift` 的 `PageExit`）：每张卡片 70ms 线性淡出 + 上移 6pt，
  按 `.cardIndex` 错峰 15ms（封顶 4 步，整段 130ms）。PCL2 的 `TriggerExitAnimation` 里这两条 Aa
  都没给 Ease，**退场是线性的**——不要换成入场那套 AniEaseOutBack。
- **侧边栏**：分两套（PCL2 的 MyPageLeft 按 XAML 里有没有 AnimatedControl 分叉）。
  启动页 / 任务页整块 110ms 缩到 0.95（t²）+ 80ms 淡出（延迟 30ms）；
  其余侧边栏由 `MyNavigationList` 逐条目 50ms 淡出 + 左移 6pt，整列共用 70ms 错峰窗口。
- **标题栏**：主栏与子栏是两层叠在一起的视图（PCL2 的 PanTitleMain / PanTitleInner）。
  主→子：主栏 150ms 淡出并右移 12pt，子栏延迟 200ms 进场（150ms 淡入 + 350ms 从 -16 滑到 0）；
  子→主：子栏左移 18pt 退场，主栏同样延迟 200ms 回来。
- **左下角提示条**：200ms 左移 50pt + 150ms 线性淡出 + 100ms 高度收 0，跑完才从数组里删
  （PCL2 的 ModMain「Hint Hide」）。`HintModel.isDismissing` 就是为这段退场留的状态，
  `HintOverlay` 的容器动画只认 `hints.map(\.id)`，别让它把每条提示自己的曲线盖掉。
- **消息框**：80ms 淡出（延迟 20ms）+ 150ms 下移 20pt + 150ms 转到 6°。
- **右下角圆形按钮**：出现 500ms 的 AniEaseOutBack（延迟 60ms），消失 100ms 的 t² 缩放。
- **新增下载任务**：右下角任务按钮荡开一圈水波（PCL2 的 `MyExtraButton.Ribble`）——半透明圆
  1000ms 内放大到 13 倍并淡到 0，**不裁剪**（原版就是让它铺到窗口上）。
  只有任务**变多**时才播；任务完成被移除时不播。
- **任务卡片**：任务结束时淡出 + 缩到 0.92 后移除（PCL2 的 `MyCard.AniDispose`），
  靠 `TasksPage` 里 `ForEach` 上的 `.transition` + 只认 `tasks.map(\.id)` 的隐式动画驱动；
  插入不做过渡（卡片自己的入场动画已经管了那一段）。

`PageTransition` 的几条边界：退场途中又切页 → 沿用同一条退场、只换目标；切回原页面 → 撤销退场；
换页面与"退场结束"必须在同一帧提交（`Presentation` 是一个结构体），否则新页面会先带着
`isExiting = true` 挂上去闪一下。`PageAnimationDebug.factor` 对退场同样生效，
`PCL_ANIM_SLOW=6` 可以录慢动作对时序。


## 卡片折叠与悬停动画

数值全部取自 PCL2（Controls/MyCard.vb、MyRadioBox.xaml.vb、MyListItem.xaml.vb），改之前先看那边的源码：

- **折叠卡片的高度动画**：|Δ| ≤ 800 时 150ms 的 `1-(1-t)^5`（easeOutQuint）；更长的距离
  PCL2 会先匀速再减速（展开 300ms@5000px/s + 400ms 减速，收缩 100ms + 150ms）。
  SwiftUI 一个 `.animation` 只能挂一条曲线，所以**时长照 PCL2 算、曲线用起始斜率很高的
  cubic-bezier 近似**"先匀速后减速"。参数集中在 Components/CardFold.swift。
- **折叠箭头**：250ms easeOutQuint。
- **卡片悬停**：阴影过渡 90ms，静止不透明度 0.07、悬停 0.4，半径 3，标题颜色同时变。
- **顶栏页签**（PCL2 的 MyRadioButton）：悬停进入 100ms、离开 200ms。
- **侧边栏条目**（PCL2 的 MyListItem）：悬停进入 120ms、离开 180ms。
- **单选与复选是两种控件，不要混用**：单选组（主题、标题栏类型、主页类型、内存分配方式）
  用 `Components/MyRadioBox.swift`（PCL2 的 MyRadioBox，圆形外圈 + 内点），
  可多选的开关（自动设置中文、功能开关、导出选项、叠加彩色背景）用 `MyComboBox`（方形复选框）。
  两者都只认 `Binding<Bool>`，单选组的互斥由调用方的 Binding 完成。
- 可折叠卡片的初始折叠状态在 `init` 里就位，**不要挪回 onAppear**：晚一帧会让卡片先按
  展开布局画一次，进页面时看得到"内容弹开又收回"。
- 卡片底色是 PCL2 的 `Color.FromArgb(245,255,255,255)`（近白），不是 `colorGray8`；
  阴影静止用 `color1`(#343d4a) + 0.07，悬停换 `color4` + 0.4，半径 3。

## 侧边栏

- 不同页面的侧边栏宽度不同（140 / 150 / 220 / 285 / 300）。**只有白色底板做宽度动画**
  （`spring(response: 0.16, dampingFraction: 1)`），容器的布局宽度（`ZStack` 的 frame）
  一步到位：布局宽度跟着动画走的话，右侧页面会被一起拽着横移，卡片入场时看起来在漂。
  侧边栏在 `ContentView` 的 HStack 里带 `zIndex(1)`，底板变宽时盖在页面上方而不是露缝。
- 入场动画分两套，**不能同时挂**：
  - 启动页 / 任务页：整块侧边栏"淡入 + 放大 0.96 → 1"（原来的那一套，
    启动页账户面板自己还有一层 `insertTransition`）。
  - 其它页面：`MyNavigationList` 逐条目播放 `SidebarEntrance`
    （PCL2 `MyPageLeft` 的 25px 左移 + 两段 X 补位）。每行自己持有一个 `appeared`。
    错峰**照抄原版的累加式** `Delay += Math.Max(15 - Id, 7) * 2`（`SidebarEntrance.delay(for:)`）：
    0 / 30 / 58 / 84 / 108 / 130 / 150 / 168 / 184 / 198 ms…
    PCL2 的 `GetAllAnimControls` 把 MyListItem 整个算作一格（图标与文字不单独计数），
    所以序号直接对应，**不要**再乘一个放大系数。
- **点侧边栏条目切子页面时，侧边栏既不重播入场、也不播退场**（用户明确要求）：
  - 入场：行内 `appeared` 只在侧边栏被重建时从 false 开始，同一套侧边栏内部切换保持为 1。
    所以 `MyNavigationList` **不要**再按切页次数给行换 `.id`——那等于每次点击都重播一遍。
    换页面族（启动 → 版本选择、下载 → 资源详情…）时 `AppSidebarView` 会换成另一个
    侧边栏类型，新实例自然播一次入场。
  - 退场：点条目时 `PageTransition.noteSidebarNavigation()` 会置位 `isSidebarNavigation`，
    `AppSidebarView` 据此把 `isExiting` 算成 false。**必须这么写**：侧边栏的逐条目退场
    （50ms + 70ms 错峰）比换页窗口（130ms）短，播完之后 `pageExiting` 立刻回到 false，
    动画是 `nil`，条目会"啪"地弹回全不透明——看起来就是"动画播到一半被掐掉"。
    页面内容（卡片）的退场照旧。
  - 启动页 / 任务页的容器动画仍只跟着 `sidebarWidth` 变化走。
- **条目点击必须由条目自己的手势处理**：条目里挂着 `DragGesture(minimumDistance: 0)`
  （按下缩到 0.98），它会在按下瞬间认领事件，外层 `onTapGesture` 永远收不到——
  表现就是"点侧边栏没反应"。切换页面的动作和缩放放在同一个手势的 `onEnded` 里，
  条目内的刷新按钮用 `highPriorityGesture` 抢回点击。
- **条目几何对齐 PCL2 的 MyListItem**（Type=RadioBox、Height=36、IsScaleAnimationEnabled=False）：
  行高 36；左侧 6pt 的勾选条列里放 5pt 宽、圆角 2、上下各留 6pt 的主色条（未选中收成 0 高）；
  图标列 34pt（左 6 + 图标 20 + 右 8）；文字左边距 4、字号 14。
  悬停底色是 `ColorBrushBg1`（`color7` 的 74.5%），进入 120ms、离开 180ms；
  按下时整条缩到 0.98。**悬停底色不要换回 `color2.opacity(0.1)`**——那是自造色，
  在深色背景图片上会糊成一片。
- 纯列表页（设置 / 更多 / 联机 / 版本设置）的列表顶部留 12pt，对应原版
  `StackPanel Margin="0,12,0,0"`；带分节标题的下载页与版本选择页不加。

## 设置导入导出

PCL.Swift/Services/SettingsTransferService.swift 用**白名单结构**而不是
"编码后删键"：删键方案一旦 LauncherConfig 加了新字段，新字段就会默认被导出，
账号凭据正是这样漏出去的。

白名单里**不含** accounts / currentAccountId / hasMicrosoftAccount /
minecraftRepositories / currentRepositoryId——前者是凭据，后者是本机路径。

## 编码约定（代码里看不出的取舍）

完整版在 [CONTRIBUTING.md](CONTRIBUTING.md)，这里只列代理最容易违反的几条：

1. **错误处理分层**：公开 API 用 `throws(SomeError)` 或 `throws` + 自定义 `Error`；就地失败用
   `SimpleError("...")`；`try?` 仅限确有降级路径的场景。**禁止空 `catch {}`**——要么记日志，要么在注释里
   说明为什么可以忽略。catch 到具体类型必须给 default 分支。
2. **主线程**：新代码一律 `@MainActor`；只有并发标注够不着的回调边界（`URLSessionDelegate`、AppKit
   target/action）才退回 `DispatchQueue.main.async`，并写明原因。不要新引入第三种写法。
3. **功能开关**：`FeatureFlag` 新增 case 时，必须在 `FlagsManager.applyChange(_:enabled:)` 里指名它改变了
   什么行为；只隐藏入口不算实现——可达性由 `AppRouter.isRouteAvailable(_:)` 统一拦截。开关变化可能来自
   任意线程，跨到主线程请显式 `Task { @MainActor in ... }`。
4. **单例是显式注入的**：`JavaManager` / `DownloadSourceManager` / `ResourceCache` / `VersionManifest` /
   `FlagsManager` 都是 `install(_:)` 注入 + `shared` 读取，注入点集中在 `AppDelegate.applicationWillFinishLaunching`。
   **新增这类全局对象请照此办理**：`shared` 在未注入时给出可定位的 `fatalError`，而不是 `!` 隐式解包。
   `VersionManifest.shared` 是可选的（未拉到版本列表时为 `nil`），不要改回强制解包。
5. **日志**：用 Core 提供的全局 `log` / `warn` / `err` / `debug`，不要 `print`。用户可见的失败要有日志。
6. **文案**：面向用户的字符串走 `Resources/Localizable.xcstrings`；代码注释与提交信息用简体中文，
   标识符用英文。
7. **删代码**：没有调用点的声明直接删，不要为了"以后可能用"保留；死代码会拖累 `DEAD_CODE_STRIPPING` 的收益。

## 密钥与配置

- `Resources/Secrets.properties` 是**模板**，仓库里只有空占位，禁止提交真实凭据。
  CI 在构建前按 secrets 重写该文件；本地可用环境变量 `PCLMAC_<KEY>` 覆盖（见 `PCL.Swift/App/Secrets.swift`）。
- 本地开发更省事的做法是 `Resources/Secrets.local.properties`（写同名键即可，已在 `.gitignore` 里），
  它覆盖打包文件里的同键，模板保持干净。优先级：环境变量 → local 文件 → Secrets.properties。
- **CurseForge API Key 只有内置一层**：环境变量 / Secrets.local.properties / CI 注入的 Secrets.properties。
  用户侧不再提供手填入口（曾经的「自定义 Key」已删除），缺 Key 只能换一份带 Key 的构建。
  解析只有一处实现：Core 的 `CurseforgeAPIKeyResolver`（去空白、剥引号）。
  没有可用 Key 时 `Secrets.shared.curseforgeClient` 返回 `nil`，**不要**用空字符串造客户端——
  那样请求只会 401，报错还看不出原因（Issue #4）。
- `PropertiesLoader` 把 `KEY=`（值为空）当作合法的空值，不要改回"整行非法"：CI 没拿到 secret 时就会写出
  这种行，一行坏掉会让整份 Secrets 作废。
- 用户数据落在 `~/Library/Application Support/PCL.Swift/`（`config.json`、`Logs`、`Caches`、`Temp`），
  路径常量在 `PCL.Swift.Core/Utils/URLConstants.swift`，不要散落硬编码。

## 主页与社区资源命名

- **主页默认是空白**：原来的「启动器主页」（账号皮肤 / 更新公告 / Minecraft 新闻整页）已删除。
  HomepageType 只剩 empty / preset / local / remote / demo，默认 `.empty`；旧配置里的 dashboard
  解码失败后自动落到 `.empty`，不需要额外迁移代码。想要回那块主页就得重写视图并加回 case。
- **文件名格式**：只有 Core 的 ResourceFileName 一处实现（设置 → 其他 → 社区资源），
  下载落点（ResourceInstallViewModel）只调用它，不要各自拼字符串。
  取值与 PCL2 的 `ToolDownloadTranslateV2` 一一对应：`【译名】文件名` / `[译名] 文件名`（默认）/
  `译名-文件名` / `文件名-译名` / `只用文件名`。「译名」来自 `ResourceTranslation`（见下一条），
  查不到时退回项目标题；标题等于文件名主干时视为没有译名，直接沿用源站的原始文件名——
  与原版同一套判断。
  **不要再做成自由文本模板**：那会与设置界面对不上，且用户填错一个占位符就得到怪名字。
- **Mod 管理样式**：ResourceTitleStyle 决定实例资源列表的标题显示名称还是文件名，
  另一项降级成标题右侧的灰字（InstalledResourcesPage.ResourceListItem）。
- **译名**：实现在 `Services/ResourceTranslation.swift`，内置表 `Resources/Translations.json`，
  用户可在数据目录放同名的 `Translations.json` 覆盖/追加（改译名不用等发版）。
  查表 key 是归一化后的 slug / 标题（小写、空格换连字符），查不到就返回 nil——
  **不要接机翻**：翻错比不翻更难认。译名同时用于列表主标题（原名缩成灰字跟在后面）
  和落盘文件名（`ProjectListItemModel.fileNameTitle` 喂给 ResourceFileName）。
- **社区资源筛选**：搜索页（Mod / 整合包 / 资源包 / 光影 / 数据包共用 `ResourcesSearchPage`）的条件对齐
  PCL2 的 PageResource：**左半边是名称 / 版本 / Mod 加载器（只有 Mod 页显示），右半边是来源 / 类型**，
  底下是「搜索 / 重置条件」两个按钮。改完条件**点「搜索」才生效**，翻页沿用同一套条件——
  与原版一致，不要做成改一下就自动搜。
  - 来源 = 全部 / Modrinth / CurseForge。「全部」会并发查两边再拼起来，页数取两者较大值；
    没有内置 CurseForge API Key 时下拉里干脆不列 CurseForge，「全部」也只走 Modrinth。
  - 类型下拉显示中文（`ProjectListItemModel.localizeTag`，查 `category.modrinth.<slug>`），
    提交给接口的仍是 slug；CurseForge 那边按 slug 对一次 categoryId，对不上就不过滤。
  - 「Mod 加载器」单独占一行、铺满整张卡：它只在 Mod 页出现，塞进左半边会留一条空荡荡的右半边。
  - 版本列表取 `VersionManifest` 里最近的 12 个正式版（原版也是一份固定列表，不是全量）。
  - 类型列表来自 Modrinth 的 `/v2/tag/category`，按 `project_type` 过滤。**模型里 `projectType` 必须是
    String**：接口还会返回 `minecraft_java_server` 这类本启动器没有的类型，硬解成 `ResourceType`
    会让整份列表解码失败（表现是类型下拉框永远只有「全部」）。
  - Modrinth 的加载器与类型都走 facets 里的 `categories:`（它把加载器也算作 category facet）；
    CurseForge 那边分别是 `modLoaderType` 与 `categoryId`，classId 见 `CurseForgeMod.classId(for:)`。
  - CurseForge 的文件列表**带依赖但按 modId 逐个查**，所以只给「当前实例能装」的版本查依赖，
    且一次最多 8 个（`dependencyBudget`），否则打开页面就是几十个请求。
  - **刷新**：侧边栏条目悬停时出现刷新按钮（原版 PageDownloadLeft 的 6 个条目各有一个），
    侧边栏与页面不在同一棵视图树里，所以走 `Managers/ResourceRefreshCenter.swift` 的按类型令牌：
    侧边栏点刷新 → 计数 +1 → 对应页面 `onChange` 收到后用**当前界面上的条件**重搜并回到第一页，
    并且 `forceRefresh: true` 跳过缓存。
  - **缓存**（设置 → 其他 → 缓存）：实现在 `Managers/ResourceCacheCenter.swift`，两类规则不同：
    - **资源列表**（搜索结果 + 已安装模组列表）：只在内存里，按 `resourceListCacheMinutes`
      过期（界面只给 10 / 30 分钟）。搜索结果按「类型|来源|关键词|版本|加载器|类型标签|页码」做 key；
      已安装列表按「实例|类型|目录签名」做 key，目录签名 = 路径 + mtime + 文件数，
      **装/删/改文件会立刻失效**，不然刚装完 Mod 要等十分钟才看得到。
    - **图标**：开启即**落盘**到 `Caches/images/<key.sha1>`，内存里再留一层避免每帧读盘；
      关掉会同时清内存与磁盘（关了就没缓存）。key 是「URL + 裁剪区域」，同一张头像的
      原图与裁剪图不能共用一份。
    搜索结果**不要落盘**：换源或换筛选后，磁盘缓存很容易给出过期数据。

## 启动器更新渠道

- 检查更新读的是**本源仓库的 GitHub Release**（`LakelightLily-Studio/PCL.Swift`），不再读 Cylorine Studio 的
  `update.json`：那份元数据不跟随本仓库发版，等于永远检查不到新版本。实现在
  `PCL.Swift/Managers/UpdateManager.swift`，DTO 在 Core 的 `GitHubRelease`。
- 只认**已发布且非预发布**的 Release：草稿与 prerelease 不推给普通用户（未登录时草稿本来也不返回）。
- 版本比较用营销版本（tag 去掉 `v`），唯一实现在 Core 的 `LauncherVersion`。**不要**拿 `CFBundleVersion` 比——
  GitHub 没有构建号，那个值在 CI 里是提交数，两边量纲不同。
- **更新包按架构分开**（2.0.4 起）：`PCL.Swift-<版本>-arm64.zip` / `PCL.Swift-<版本>-x86_64.zip`。
  挑包逻辑在 Core 的 `GitHubRelease.updateArchive(for:)`：先按运行架构匹配 `-arm64` / `-x86_64`，
  再回退到 2.0.3 及更早那种无后缀的通用包；只有另一种架构的包时返回 nil（装上也跑不起来）。
  发布页还有 dmg，更新器按「前缀 + .zip」筛，资产改名会让更新被静默跳过。
- 更新包解开后要能找到 `PCL.Swift.app`（兼容旧的 `PCL.Mac.app`），缺失时报「更新包格式错误」。
- GitHub API 未登录限流 60 次/小时/IP，一次检查只发 1 个请求；不要在启动流程里重复轮询。

## 提交与 PR

- 提交信息用 Conventional Commits，scope 取模块名：`fix(core): ...`、`refactor(ui): ...`、`ci: ...`、
  `docs: ...`、`chore: ...`、`release: x.y.z`。主题行说清"改了什么行为"，不要写"update files"。
- 一个提交只做一件事；重构与行为变更分开提交（历史里 `refactor:` 与 `fix:` 是严格分开的）。
- PR 的 review comment 用简体中文，并指出拼写/用词问题（补充规则见 `.github/copilot-instructions.md`）。
- 允许 `internal` / `private` 类型里出现 `public` 成员，这是本仓库的既有风格，不必"修正"。
- 合并到 `main` 前确保 `xcodebuild test` 通过；`main` 的推送会触发 `test.yml`。

## 代理的工作方式

- 动手前先读相关文件，别凭文件名猜实现；改老代码不必为了对齐新约定而大改，但**不要在同一个文件里再引入
  第三种写法**。
- 不要顺手格式化无关文件、不要改 `Package.resolved`、不要动 `xcuserdata`（已 gitignore）。
- 未经明确要求，不要创建 git commit / 不要 push / 不要发 Release。
- 改动涉及用户可见行为时，同步更新 `CONTRIBUTING.md` 或本文件里对应的约定，而不是只在代码注释里留话。
