//
//  LauncherConfig.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/26.
//

import Foundation
import Core

class LauncherConfig: Codable {
    /// shared 构造期间为 false：解码过程会依次给各属性赋值，
    /// 此时触发写盘会递归访问尚未构造完成的 shared。
    private static var isLoaded: Bool = false

    public static let shared: LauncherConfig = {
        defer { isLoaded = true }
        let url = URLConstants.configURL

        if !FileManager.default.fileExists(atPath: url.path) {
            let config: LauncherConfig = .init()
            log("配置文件不存在，正在创建")
            do {
                try save(config, to: url)
            } catch {
                err("保存配置文件失败：\(error.localizedDescription)")
            }
            return config
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder.shared.decode(LauncherConfig.self, from: data)
        } catch {
            err("加载配置文件失败：\(error.localizedDescription)")
            do {
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
                try FileManager.default.copyItem(at: url, to: backupURL)
                log("备份配置文件成功：\(backupURL.path)")
            } catch {
                err("备份配置文件失败：\(error.localizedDescription)")
            }
            loadError = error
            let config = LauncherConfig()
            try? save(config, to: url)
            return config
        }
    }()

    public static let backupURL: URL = URLConstants.applicationSupportURL.appending(path: "config.bak.json")
    public static private(set) var loadError: Error?

    public var minecraftRepositories: [MinecraftRepository] = [] {
        didSet { LauncherConfig.markDirty() }
    }
    public var currentRepositoryId: UUID? {
        didSet { LauncherConfig.markDirty() }
    }
    public var accounts: [Account] = [] {
        didSet { LauncherConfig.markDirty() }
    }
    public var currentAccountId: UUID? {
        didSet { LauncherConfig.markDirty() }
    }
    public var multiplayerDisclaimerAgreed: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    public var hasMicrosoftAccount: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    public var launchCount: Int = 0 {
        didSet { LauncherConfig.markDirty() }
    }
    public var hasEnteredLauncher: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    /// 是否已完成首次启动的开场动画与设置向导。
    ///
    /// 与 hasEnteredLauncher 分开：后者记录"进过主界面"，这里记录"走完了
    /// 开场流程"。旧配置里没有这个键时会解码为 false，于是升级后的第一次
    /// 启动仍会播一遍开场动画，这正是期望的行为。
    public var hasCompletedOnboarding: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    public var multiplayerCustomPeer: String? {
        didSet { LauncherConfig.markDirty() }
    }
    public var ignoreLauncherUpdates: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    public var downloadSourcePolicy: DownloadSourcePolicy = .officialFirst {
        didSet { LauncherConfig.markDirty() }
    }
    public var homepageType: HomepageType = .empty {
        didSet { LauncherConfig.markDirty() }
    }
    public var enabledFlags: Set<FeatureFlag>? {
        didSet { LauncherConfig.markDirty() }
    }
    public var customJavaRuntimes: [URL] = [] {
        didSet { LauncherConfig.markDirty() }
    }
    public var theme: Theme = .themeOrange {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 主题自定义

    /// 自定义主题的色相（0…1）。只在 theme 为 custom 时生效。
    public var themeHue: Double = 0.04 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 自定义主题的饱和度（0…1）。
    public var themeSaturation: Double = 0.93 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 自定义主题的明度（0…1）。
    public var themeBrightness: Double = 0.95 {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 下载

    /// 下载使用的最大并发数。nil 表示跟随下载源推荐值。
    ///
    /// 与推荐值分开存：用户显式设过就按用户的来，换下载源不再悄悄改掉它。
    public var downloadMaxThreads: Int? {
        didSet { LauncherConfig.markDirty() }
    }
    /// 下载限速（KB/s）。0 表示不限速。
    public var downloadSpeedLimit: Int = 0 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 版本列表源是否与文件下载源分开设置。
    ///
    /// 关掉时 versionListSourcePolicy 跟随 downloadSourcePolicy，
    /// 这样老配置（只有 downloadSourcePolicy）的行为与升级前完全一致。
    public var separatesVersionListSource: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    /// 版本列表专用下载源策略。
    public var versionListSourcePolicy: DownloadSourcePolicy = .officialFirst {
        didSet { LauncherConfig.markDirty() }
    }
    /// 自定义缓存目录。nil 表示使用数据目录下的 Caches。
    public var customCacheDirectory: URL? {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 外观

    /// 背景图片路径。nil 表示不显示背景图。
    public var backgroundImageURL: URL? {
        didSet { LauncherConfig.markDirty() }
    }
    /// 背景图不透明度（0…1）。
    public var backgroundOpacity: Double = 0.35 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 背景图模糊半径（pt）。
    public var backgroundBlur: Double = 12 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 是否在背景图上叠加主题色。
    public var backgroundTinted: Bool = true {
        didSet { LauncherConfig.markDirty() }
    }
    /// 背景图填充方式：true 为填充（裁切），false 为适应（留白）。
    public var backgroundFills: Bool = true {
        didSet { LauncherConfig.markDirty() }
    }
    /// 标题栏 Logo 类型。
    public var titleBarLogoType: TitleBarLogoType = .logo {
        didSet { LauncherConfig.markDirty() }
    }
    /// 标题栏自定义文本，仅在 titleBarLogoType 为 text 时使用。
    public var titleBarText: String = "PCL.Swift" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 标题栏自定义图片路径，仅在 titleBarLogoType 为 image 时使用。
    public var titleBarImageURL: URL? {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 启动默认值

    /// 全局默认游戏窗口标题。空串表示使用游戏自身标题。
    public var gameWindowTitle: String = "" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认游戏窗口模式。
    public var gameWindowType: GameWindowType = .standard {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认游戏窗口宽度。
    public var gameWindowWidth: Int = 854 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认游戏窗口高度。
    public var gameWindowHeight: Int = 480 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认启动器可见性。
    public var launcherVisibility: LauncherVisibility = .keepVisible {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认进程优先级。
    public var processPriority: ProcessPriority = .normal {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认启动前执行命令。
    public var prelaunchCommand: String = "" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认是否等待启动前命令执行完成。
    public var prelaunchWaitForCompletion: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认附加游戏参数。
    public var gameArguments: String = "" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认额外 JVM 参数。
    public var jvmArguments: String = "" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认内存分配（MB）。
    public var memory: UInt64 = 4096 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 是否启用启动前内存优化。
    public var memoryOptimize: Bool = false {
        didSet { LauncherConfig.markDirty() }
    }


    public init() {}

    public required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.minecraftRepositories = try container.decodeIfPresent([MinecraftRepository].self, forKey: .minecraftRepositories) ?? []
        self.currentRepositoryId = try container.decodeIfPresent(UUID.self, forKey: .currentRepositoryId)

        self.accounts = (try container.decodeIfPresent([AccountWrapper].self, forKey: .accounts) ?? []).map(\.account)
        if !accounts.isEmpty {
            if let currentAccountId = try container.decodeIfPresent(UUID.self, forKey: .currentAccountId),
               accounts.contains(where: { $0.id == currentAccountId }) {
                self.currentAccountId = currentAccountId
            } else {
                self.currentAccountId = accounts[0].id
            }
        }
        self.multiplayerDisclaimerAgreed = try container.decodeIfPresent(Bool.self, forKey: .multiplayerDisclaimerAgreed) ?? false
        self.hasMicrosoftAccount = try container.decodeIfPresent(Bool.self, forKey: .hasMicrosoftAccount) ?? false
        self.launchCount = try container.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        self.hasEnteredLauncher = try container.decodeIfPresent(Bool.self, forKey: .hasEnteredLauncher) ?? false
        self.hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        self.multiplayerCustomPeer = try container.decodeIfPresent(String.self, forKey: .multiplayerCustomPeer)
        self.ignoreLauncherUpdates = try container.decodeIfPresent(Bool.self, forKey: .ignoreLauncherUpdates) ?? false
        self.downloadSourcePolicy = try container.decodeIfPresent(DownloadSourcePolicy.self, forKey: .downloadSourcePolicy) ?? .officialFirst
        self.homepageType = try container.decodeIfPresent(HomepageType.self, forKey: .homepageType) ?? .empty
        self.enabledFlags = try container.decodeIfPresent(Set<FeatureFlag>.self, forKey: .enabledFlags)
        self.customJavaRuntimes = try container.decodeIfPresent([URL].self, forKey: .customJavaRuntimes) ?? []
        // 主题名改过一次（default/swiftOrange → themeBlue/themeOrange），
        // 旧值解码失败时退回默认主题，而不是让整份配置解码失败。
        self.theme = (try? container.decodeIfPresent(Theme.self, forKey: .theme)) ?? .themeOrange

        self.themeHue = try container.decodeIfPresent(Double.self, forKey: .themeHue) ?? 0.04
        self.themeSaturation = try container.decodeIfPresent(Double.self, forKey: .themeSaturation) ?? 0.93
        self.themeBrightness = try container.decodeIfPresent(Double.self, forKey: .themeBrightness) ?? 0.95

        self.downloadMaxThreads = try container.decodeIfPresent(Int.self, forKey: .downloadMaxThreads)
        self.downloadSpeedLimit = try container.decodeIfPresent(Int.self, forKey: .downloadSpeedLimit) ?? 0
        self.separatesVersionListSource = try container.decodeIfPresent(Bool.self, forKey: .separatesVersionListSource) ?? false
        self.versionListSourcePolicy = try container.decodeIfPresent(DownloadSourcePolicy.self, forKey: .versionListSourcePolicy) ?? .officialFirst
        self.customCacheDirectory = try container.decodeIfPresent(URL.self, forKey: .customCacheDirectory)

        self.backgroundImageURL = try container.decodeIfPresent(URL.self, forKey: .backgroundImageURL)
        self.backgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? 0.35
        self.backgroundBlur = try container.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 12
        self.backgroundTinted = try container.decodeIfPresent(Bool.self, forKey: .backgroundTinted) ?? true
        self.backgroundFills = try container.decodeIfPresent(Bool.self, forKey: .backgroundFills) ?? true
        self.titleBarLogoType = (try? container.decodeIfPresent(TitleBarLogoType.self, forKey: .titleBarLogoType)) ?? .logo
        self.titleBarText = try container.decodeIfPresent(String.self, forKey: .titleBarText) ?? "PCL.Swift"
        self.titleBarImageURL = try container.decodeIfPresent(URL.self, forKey: .titleBarImageURL)

        self.gameWindowTitle = try container.decodeIfPresent(String.self, forKey: .gameWindowTitle) ?? ""
        self.gameWindowType = (try? container.decodeIfPresent(GameWindowType.self, forKey: .gameWindowType)) ?? .standard
        self.gameWindowWidth = try container.decodeIfPresent(Int.self, forKey: .gameWindowWidth) ?? 854
        self.gameWindowHeight = try container.decodeIfPresent(Int.self, forKey: .gameWindowHeight) ?? 480
        self.launcherVisibility = (try? container.decodeIfPresent(LauncherVisibility.self, forKey: .launcherVisibility)) ?? .keepVisible
        self.processPriority = (try? container.decodeIfPresent(ProcessPriority.self, forKey: .processPriority)) ?? .normal
        self.prelaunchCommand = try container.decodeIfPresent(String.self, forKey: .prelaunchCommand) ?? ""
        self.prelaunchWaitForCompletion = try container.decodeIfPresent(Bool.self, forKey: .prelaunchWaitForCompletion) ?? false
        self.gameArguments = try container.decodeIfPresent(String.self, forKey: .gameArguments) ?? ""
        self.jvmArguments = try container.decodeIfPresent(String.self, forKey: .jvmArguments) ?? ""
        self.memory = try container.decodeIfPresent(UInt64.self, forKey: .memory) ?? 4096
        self.memoryOptimize = try container.decodeIfPresent(Bool.self, forKey: .memoryOptimize) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(minecraftRepositories, forKey: .minecraftRepositories)
        try container.encode(currentRepositoryId, forKey: .currentRepositoryId)
        try container.encode(accounts.map(AccountWrapper.init(_:)), forKey: .accounts)
        try container.encode(currentAccountId, forKey: .currentAccountId)
        try container.encode(multiplayerDisclaimerAgreed, forKey: .multiplayerDisclaimerAgreed)
        try container.encode(hasMicrosoftAccount, forKey: .hasMicrosoftAccount)
        try container.encode(launchCount, forKey: .launchCount)
        try container.encode(hasEnteredLauncher, forKey: .hasEnteredLauncher)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(multiplayerCustomPeer, forKey: .multiplayerCustomPeer)
        try container.encode(ignoreLauncherUpdates, forKey: .ignoreLauncherUpdates)
        try container.encode(downloadSourcePolicy, forKey: .downloadSourcePolicy)
        try container.encode(homepageType, forKey: .homepageType)
        try container.encodeIfPresent(enabledFlags, forKey: .enabledFlags)
        try container.encode(customJavaRuntimes, forKey: .customJavaRuntimes)
        try container.encode(theme, forKey: .theme)

        try container.encode(themeHue, forKey: .themeHue)
        try container.encode(themeSaturation, forKey: .themeSaturation)
        try container.encode(themeBrightness, forKey: .themeBrightness)

        try container.encodeIfPresent(downloadMaxThreads, forKey: .downloadMaxThreads)
        try container.encode(downloadSpeedLimit, forKey: .downloadSpeedLimit)
        try container.encode(separatesVersionListSource, forKey: .separatesVersionListSource)
        try container.encode(versionListSourcePolicy, forKey: .versionListSourcePolicy)
        try container.encodeIfPresent(customCacheDirectory, forKey: .customCacheDirectory)

        try container.encodeIfPresent(backgroundImageURL, forKey: .backgroundImageURL)
        try container.encode(backgroundOpacity, forKey: .backgroundOpacity)
        try container.encode(backgroundBlur, forKey: .backgroundBlur)
        try container.encode(backgroundTinted, forKey: .backgroundTinted)
        try container.encode(backgroundFills, forKey: .backgroundFills)
        try container.encode(titleBarLogoType, forKey: .titleBarLogoType)
        try container.encode(titleBarText, forKey: .titleBarText)
        try container.encodeIfPresent(titleBarImageURL, forKey: .titleBarImageURL)

        try container.encode(gameWindowTitle, forKey: .gameWindowTitle)
        try container.encode(gameWindowType, forKey: .gameWindowType)
        try container.encode(gameWindowWidth, forKey: .gameWindowWidth)
        try container.encode(gameWindowHeight, forKey: .gameWindowHeight)
        try container.encode(launcherVisibility, forKey: .launcherVisibility)
        try container.encode(processPriority, forKey: .processPriority)
        try container.encode(prelaunchCommand, forKey: .prelaunchCommand)
        try container.encode(prelaunchWaitForCompletion, forKey: .prelaunchWaitForCompletion)
        try container.encode(gameArguments, forKey: .gameArguments)
        try container.encode(jvmArguments, forKey: .jvmArguments)
        try container.encode(memory, forKey: .memory)
        try container.encode(memoryOptimize, forKey: .memoryOptimize)
    }

    /// 合并短时间内的多次变更，避免每个字段改动都触发一次写盘。
    private static var pendingSave: DispatchWorkItem?
    /// 写盘前至少等待的静默时间。
    private static let saveDebounceInterval: TimeInterval = 0.5

    /// 声明配置已被修改，稍后落盘。
    ///
    /// 此前只有退出时（applicationWillTerminate）才写盘，崩溃或强退会丢掉
    /// 本次运行里的全部设置。
    public static func markDirty() {
        guard isLoaded else { return }
        pendingSave?.cancel()
        let workItem = DispatchWorkItem {
            pendingSave = nil
            do {
                try save()
            } catch {
                err("保存配置文件失败：\(error.localizedDescription)")
            }
        }
        pendingSave = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDebounceInterval, execute: workItem)
    }

    /// 立即落盘；退出流程与崩溃路径使用（不等待 debounce）。
    public static func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        do {
            try save()
        } catch {
            err("保存配置文件失败：\(error.localizedDescription)")
        }
    }

    public static func save(_ config: LauncherConfig = .shared, to url: URL = URLConstants.configURL) throws {
        let data = try JSONEncoder.shared.encode(config)
        try data.write(to: url)
    }

    private enum CodingKeys: String, CodingKey {
        case minecraftRepositories
        case currentRepositoryId
        case accounts
        case currentAccountId
        case multiplayerDisclaimerAgreed
        case hasMicrosoftAccount
        case launchCount
        case hasEnteredLauncher
        case hasCompletedOnboarding
        case multiplayerCustomPeer
        case ignoreLauncherUpdates
        case downloadSourcePolicy
        case homepageType
        case enabledFlags
        case customJavaRuntimes
        case theme
        case themeHue
        case themeSaturation
        case themeBrightness
        case downloadMaxThreads
        case downloadSpeedLimit
        case separatesVersionListSource
        case versionListSourcePolicy
        case customCacheDirectory
        case backgroundImageURL
        case backgroundOpacity
        case backgroundBlur
        case backgroundTinted
        case backgroundFills
        case titleBarLogoType
        case titleBarText
        case titleBarImageURL
        case gameWindowTitle
        case gameWindowType
        case gameWindowWidth
        case gameWindowHeight
        case launcherVisibility
        case processPriority
        case prelaunchCommand
        case prelaunchWaitForCompletion
        case gameArguments
        case jvmArguments
        case memory
        case memoryOptimize
    }

    enum HomepageType: String, Codable, CaseIterable, CustomStringConvertible {
        case empty, demo

        var description: String {
            switch self {
            case .empty: "空白"
            case .demo: "[内置] 控件预览"
            }
        }
    }
}

/// 标题栏 Logo 的显示类型。
public enum TitleBarLogoType: String, Codable, CaseIterable, CustomStringConvertible {
    case logo, text, image

    public var description: String {
        switch self {
        case .logo: "默认 Logo"
        case .text: "文本"
        case .image: "图片"
        }
    }
}
