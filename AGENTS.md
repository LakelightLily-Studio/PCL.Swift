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
- 用户数据落在 `~/Library/Application Support/PCL.Swift/`（`config.json`、`Logs`、`Caches`、`Temp`），
  路径常量在 `PCL.Swift.Core/Utils/URLConstants.swift`，不要散落硬编码。

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
