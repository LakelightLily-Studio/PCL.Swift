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
import Combine
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
///
/// 启动流程做成 `MyTask`，与 Minecraft 共用同一套进度界面（阶段名 + 百分比 +
/// 取消按钮）；进程起来后 `isRunning` 为真，右下角会出现停止按钮。
@MainActor
final class DSHLaunchManager: ObservableObject {
    public static let shared: DSHLaunchManager = .init()

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var isLaunching: Bool = false
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var currentStage: String?
    @Published public private(set) var instanceName: String?
    /// 启动成功后展示给用户的地址。
    @Published public private(set) var webURL: URL?
    public let loadingViewModel: MyLoadingViewModel = .init(text: "正在启动 DSH")

    private var task: MyTask<DSHLaunchModel>? {
        didSet {
            isLaunching = task != nil
            subscribeToTask()
        }
    }
    private var cancellables: Set<AnyCancellable> = []

    /// 由本启动器起的 `dsh web` 子进程。
    private var process: Process?
    /// 由本启动器通过 `open -a` 拉起的桌面端，按 bundle id 记录以便退出时结束。
    private var launchedApplicationBundleId: String?
    private var outputPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    private init() {}

    /// 启动 DSH。
    ///
    /// 三个阶段与 Minecraft 的启动流程对齐：检查安装 → 拉起进程 → 等 WebUI 就绪。
    /// 界面复用 `launchingBody`，因此同样有阶段名、进度与取消按钮。
    @MainActor
    public func launch(_ instance: DSHInstance) {
        guard !isLaunching, !isRunning else { return }
        loadingViewModel.text = "正在启动 DSH"
        instanceName = instance.version

        let model = DSHLaunchModel(instance: instance, manager: self)
        let task: MyTask<DSHLaunchModel> = .init(
            name: "启动 DSH",
            model: model,
            .init(0, "检查安装形态") { subtask, model in
                await subtask.setProgressAsync(1)
                switch model.instance.form {
                case .commandLine(let executable, _):
                    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                        throw SimpleError("找不到 dsh 可执行文件：\(executable.path)")
                    }
                case .application(let bundleURL):
                    guard FileManager.default.fileExists(atPath: bundleURL.path) else {
                        throw SimpleError("找不到 DeepSeek Harness.app：\(bundleURL.path)")
                    }
                }
            },
            .init(1, "启动 DSH 进程") { subtask, model in
                await subtask.setProgressAsync(0.4)
                guard let manager = model.manager else {
                    throw SimpleError("启动管理器已失效。")
                }
                try await manager.startProcess(for: model.instance)
                await subtask.setProgressAsync(1)
            },
            .init(2, "等待 WebUI 就绪") { subtask, _ in
                // `dsh web` 起进程后要加载依赖，这里给一个可见的等待窗口。
                for step in 1...10 {
                    try await Task.sleep(seconds: 0.15)
                    await subtask.setProgressAsync(Double(step) / 10)
                }
            }
        )

        TaskManager.shared.execute(task: task, display: false) { [weak self] error in
            guard let self else { return }
            self.task = nil
            self.currentStage = nil
            self.instanceName = nil
            self.progress = 0
            if let error, !error.isCancellationError {
                self.isLaunching = false
                hint("启动 DSH 失败：\(error.localizedDescription)", type: .critical)
            }
        }

        self.task = task
    }

    /// 取消正在进行的启动任务。
    @MainActor
    public func cancel() {
        if let task {
            TaskManager.shared.cancel(task.id)
        }
        isLaunching = false
    }

    /// 结束由本启动器起的 DSH（用户点右下角停止按钮时调用）。
    @MainActor
    public func stop() {
        terminateAll()
        hint("已关闭 DSH", type: .finish)
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

    // MARK: - 进度订阅

    private func subscribeToTask() {
        cancellables.removeAll()
        guard let task else { return }
        task.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.progress = value }
            .store(in: &cancellables)
        task.$currentTaskOrdinal
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ordinal in
                guard let self, let ordinal else { return }
                self.currentStage = ordinal < self.stageNames.count
                    ? self.stageNames[ordinal]
                    : nil
                if self.loadingViewModel.text == "正在启动 DSH" {
                    self.loadingViewModel.text = "正在启动 DSH"
                }
            }
            .store(in: &cancellables)
    }

    private let stageNames = ["检查安装形态", "启动 DSH 进程", "等待 WebUI 就绪"]

    // MARK: - 实际启动

    /// 由启动任务调用：按安装形态拉起进程。
    @MainActor
    func startProcess(for instance: DSHInstance) async throws {
        switch instance.form {
        case .commandLine(let executable, let profile):
            try launchWebUI(executable: executable, profile: profile)
        case .application(let bundleURL):
            try await launchApplication(at: bundleURL)
        }
    }

    @MainActor
    private func launchWebUI(executable: URL, profile: String) throws {
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

        try process.run()

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
    private func launchApplication(at bundleURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let bundleId = Bundle(url: bundleURL)?.bundleIdentifier

        let application = try await NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration
        )
        isRunning = true
        launchedApplicationBundleId = application.bundleIdentifier ?? bundleId
        log("已启动 DSH 桌面端（bundle id：\(launchedApplicationBundleId ?? "未知")）")
        hint("DSH 已打开", type: .finish)
    }
}

/// DSH 启动任务的模型。持有 manager 引用，便于子任务直接驱动进程。
final class DSHLaunchModel: TaskModel {
    let instance: DSHInstance
    weak var manager: DSHLaunchManager?

    init(instance: DSHInstance, manager: DSHLaunchManager) {
        self.instance = instance
        self.manager = manager
    }
}

