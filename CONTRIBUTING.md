# 开发约定

本文件记录 PCL.Mac 中反复出现、且仅靠代码无法自证取舍的约定。新增代码请对齐；改老代码时不必
为了对齐而大改，但不要在同一个文件里再引入第三种写法。

## 错误处理

同一个关注点目前存在四种写法，按"信息会不会丢"排序，请从高到低使用：

| 写法 | 何时用 | 现状样例 |
|---|---|---|
| `throws(SomeError)` | 公开 API 需要调用方精确分支处理 | `PropertiesLoader.load(from:)`、`ModpackImportService.load()` |
| `throws` + 自定义 `Error` | 同上，但错误类型不足以收窄到 `throws(...)` | `ModrinthAPIClient.versions(ofProject:revalidate:)` |
| `throw SimpleError("...")` | 就地失败，文案即全部信息 | `JavaSettingsViewModel`、`ModParser` |
| `try?` | **仅限**确有降级路径、且失败可被容忍的场景 | `LauncherConfig` 备份失败、`FileDropHandler` 读取失败 |

硬规矩：

1. **不允许空 `catch {}`。** 要么记日志（`warn`/`err`），要么在注释里写明为什么可以忽略；
   两条都不满足时，说明这个失败不该被吞掉。
2. **`try?` 只用于"失败了也无所谓"的位置**，例如 `defer` 里的清理、缓存读取、
   探针式查询。用它吞掉业务写操作（保存配置、落盘元数据）需要在上层补一次日志。
3. **catch 到具体错误类型时，必须给出 default/兜底分支**，不要把未列出的错误静默丢弃；
   如果兜底只是"什么都不做"，也要写清原因。

## 主线程调度

同一件事目前也有四种写法：`@MainActor` 标注、`await MainActor.run { }`、
Combine 的 `.receive(on: DispatchQueue.main)`、`DispatchQueue.main.async { }`。

约定：**新代码一律用 `@MainActor` 标注类型或方法**；只有在无法使用并发标注的
回调边界（例如 `URLSession` 的 delegate、AppKit 的 target/action）才退回
`DispatchQueue.main.async`，并在注释里写明原因。

## 功能开关

`FeatureFlag` 的每个 case 都必须在 `FlagsManager.applyChange(_:enabled:)` 里
指名它改变了什么行为。只用来隐藏入口的开关不算实现——用户仍可通过路由抵达该页面，
这一点已经在 `AppRouter.isRouteAvailable(_:)` 里统一处理。
