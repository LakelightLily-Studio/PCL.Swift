//
//  DSHRuntime.swift
//  PCL.Swift
//
// DSH（DeepSeek Harness）的本地探测与启动。
//
// 只看本机：版本号读已安装 App 的 Info.plist，列表就一项，不做联网下载。
// 两种安装形态对应两种启动方式：
//   - 装了 CLI（PATH 里能解析到 dsh）→ 直接起 `dsh web` 子进程，本地 Web UI
//   - 只有 App → `open -a` 打开桌面端，并按 bundle id 记录，退出时结束它
//
// 子进程由本类持有：PCL.Swift 退出时会统一 terminate，不留孤儿进程。
//

import Foundation
import AppKit
import Core

/// 本机安装的 DSH。
struct DSHInstance: Identifiable, Hashable {
    public let id: String
    /// 显示名，通常是版本号。
    public let name: String
    public let form: InstallForm

    public enum InstallForm: Hashable {
        case application(bundleURL: URL)
        case commandLine(executableURL: URL, profile: String)
    }

    public var version: String { name }

    /// 列表里的副标题。
    public var detail: String {
        switch form {
        case .application: "桌面端 · 当前已安装"
        case .commandLine(_, let profile): "Web UI · dsh --profile \(profile)"
        }
    }
}

enum DSHRuntime {
    /// 探测本机的 DSH 安装。找不到时返回 nil。
    static func detect() -> DSHInstance? {
        if let cli = findCLI() {
            return .init(
                id: "dsh-cli",
                name: versionOfApplication() ?? "DSH",
                form: .commandLine(executableURL: cli, profile: existingWebProfile() ?? "web")
            )
        }
        if let app = applicationURL() {
            return .init(
                id: "dsh-app",
                name: versionOfApplication() ?? "DSH",
                form: .application(bundleURL: app)
            )
        }
        return nil
    }

    static func applicationURL() -> URL? {
        let url = URL(fileURLWithPath: "/Applications/DeepSeek Harness.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// 在常见目录里找 `dsh`。
    ///
    /// 从 Finder 启动的 App 只有 launchd 的最小环境，拿不到用户在 shell 里配的 PATH，
    /// 所以除了 `PATH` 还要兜底几个固定位置。
    static func findCLI() -> URL? {
        var paths = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        for extra in ["/usr/local/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"]
        where !paths.contains(extra) {
            paths.append(extra)
        }
        for directory in paths {
            let candidate = URL(fileURLWithPath: directory).appending(path: "dsh")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func versionOfApplication() -> String? {
        guard let app = applicationURL(), let bundle = Bundle(url: app) else { return nil }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static func existingWebProfile() -> String? {
        let profiles = dshHome().appending(path: "profiles")
        return FileManager.default.fileExists(atPath: profiles.appending(path: "web").path) ? "web" : nil
    }

    static func dshHome() -> URL {
        ProcessInfo.processInfo.environment["DSH_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".dsh")
    }
}

/// DSH 进程管理。整个 App 共用一个实例，`AppDelegate` 退出时调用 `terminateAll`。
@MainActor
final class DSHLaunchManager: ObservableObject {
    public static let shared: DSHLaunchManager = .init()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isLaunching: Bool = false
    /// 启动成功后展示给用户的地址。
    @Published public private(set) var webURL: URL?

    /// 由本启动器起的 `dsh web` 子进程。
    private var process: Process?
    /// 由本启动器通过 `open -a` 拉起的桌面端，按 bundle id 记录以便退出时结束。
    private var launchedApplicationBundleId: String?
    private var outputPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    /// 启动 DSH。
    @MainActor
    public func launch(_ instance: DSHInstance) {
        guard !isLaunching else { return }
        isLaunching = true

        switch instance.form {
        case .commandLine(let executable, let profile):
            launchWebUI(executable: executable, profile: profile)
        case .application(let bundleURL):
            launchApplication(at: bundleURL)
        }
    }

    /// 结束由本启动器起的 DSH。
    @MainActor
    public func terminateAll() {
        if let process, process.isRunning {
            log("正在结束由本启动器启动的 DSH 进程（pid \(process.processIdentifier)）")
            process.terminate()
        }
        process = nil
        outputPipe = nil

        if let bundleId = launchedApplicationBundleId {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            for application in running where application.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                log("正在结束由本启动器打开的 DSH 桌面端（pid \(application.processIdentifier)）")
                application.terminate()
            }
            launchedApplicationBundleId = nil
        }

        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        isRunning = false
        webURL = nil
    }

    // MARK: - 两种启动方式

    @MainActor
    private func launchWebUI(executable: URL, profile: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--profile", profile]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        process.terminationHandler = { [weak self] finished in
            Task { @MainActor in
                guard let self else { return }
                log("DSH 进程已退出，退出码 \(finished.terminationStatus)")
                self.isRunning = false
                self.process = nil
            }
        }

        do {
            try process.run()
        } catch {
            err("启动 DSH 失败：\(error.localizedDescription)")
            hint("启动 DSH 失败：\(error.localizedDescription)", type: .critical)
            isLaunching = false
            return
        }

        self.process = process
        self.outputPipe = pipe
        isRunning = true
        log("已启动 DSH Web UI（pid \(process.processIdentifier)）")

        // 从输出里读监听地址；读不到就按默认 3080 兜底。
        watchForListeningAddress(pipe: pipe)
    }

    /// 解析 `dsh web` 打印的地址。
    private func watchForListeningAddress(pipe: Pipe) {
        Task.detached { [weak self] in
            let handle = pipe.fileHandleForReading
            var buffer = Data()
            for _ in 0..<200 {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                guard let text = String(data: buffer, encoding: .utf8) else { continue }
                if let url = Self.parseURL(from: text) {
                    await MainActor.run {
                        self?.webURL = url
                        self?.isLaunching = false
                        hint("WebUI 已打开：\(url.absoluteString)", type: .finish)
                    }
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            await MainActor.run {
                self?.isLaunching = false
                hint("WebUI 已打开", type: .finish)
            }
        }
    }

    /// 从日志文本里找 `http://127.0.0.1:端口` 形式的地址。
    nonisolated private static func parseURL(from text: String) -> URL? {
        guard let range = text.range(of: #"http://[0-9a-zA-Z.:\[\]]+/?"#, options: .regularExpression) else {
            return nil
        }
        return URL(string: String(text[range]))
    }

    @MainActor
    private func launchApplication(at bundleURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let bundleId = Bundle(url: bundleURL)?.bundleIdentifier

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] application, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    err("启动 DSH 失败：\(error.localizedDescription)")
                    hint("启动 DSH 失败：\(error.localizedDescription)", type: .critical)
                    self.isLaunching = false
                    return
                }
                self.isLaunching = false
                self.isRunning = true
                self.launchedApplicationBundleId = application?.bundleIdentifier ?? bundleId
                log("已启动 DSH 桌面端（bundle id：\(self.launchedApplicationBundleId ?? "未知")）")
                hint("DSH 已打开", type: .finish)
            }
        }
    }
}
