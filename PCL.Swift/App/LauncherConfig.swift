//
//  LauncherConfig.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/26.
//

import Foundation
import SwiftUI
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
    /// 主页类型。默认走「预设」：预设里的第一项是 PCL.Swift 更新日志，
    /// 主页打开就能看到这一版改了什么，这也是当初删掉旧启动器主页后重新给主页内容的原因。
    public var homepageType: HomepageType = .preset {
        didSet { LauncherConfig.markDirty() }
    }
    /// 预设主页的选项。默认是第一项「PCL.Swift 更新日志」。
    public var homepagePreset: HomepagePreset = .changelog {
        didSet { LauncherConfig.markDirty() }
    }
    /// 「联网更新」的下载地址（Custom.xaml）。空字符串表示未填写。
    public var homepageURL: String = "" {
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
    /// 启动前把游戏语言自动设成中文（设置 → 其他 → 辅助功能）。
    ///
    /// 只在玩家没手动选过语言或还没有存档时生效，见 GameOptions.setLanguage。
    public var autoSetGameLanguage: Bool = true {
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
    /// 是否缓存资源列表（搜索结果 / 已安装模组列表，设置 → 其他 → 缓存）。
    ///
    /// 只在内存里，按下面的时间限制过期。关掉之后每次翻页 / 回到同一页都会重新加载。
    public var enableResourceListCache: Bool = true {
        didSet { LauncherConfig.markDirty() }
    }
    /// 资源列表缓存的时间限制（分钟）。界面上只给 10 / 30 两档。
    public var resourceListCacheMinutes: Int = 10 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 是否缓存资源图标。开启后会落盘到缓存目录，关掉就完全不走缓存。
    public var enableImageCache: Bool = true {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 社区资源

    /// 下载资源时使用的文件名格式。
    ///
    /// 与 PCL2 的 ToolDownloadTranslateV2 一一对应：五种「译名前缀 / 后缀」样式；
    /// 没有译名（项目名与原始文件名相同）时直接沿用原始文件名。
    /// 格式化逻辑只有一处实现：Core 的 ResourceFileName，改规则请改那里，
    /// 不要在下载点各自拼字符串。
    public var resourceFileNameFormat: ResourceFileName.Format = .bracketSquare {
        didSet { LauncherConfig.markDirty() }
    }
    /// 已安装资源列表的标题样式（标题显示名称还是文件名）。
    public var resourceTitleStyle: ResourceTitleStyle = .nameFirst {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 外观

    /// 导航栏（标题栏）背景样式：纯色或主题色 + 线格。
    public var navigationBarBackground: NavigationBarBackground = .theme {
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

    // MARK: - 背景图片

    /// 用户指定的背景图片。设置后优先于图片文件夹里的随机图；
    /// nil 表示「用文件夹里随机一张」。
    public var backgroundImageURL: URL? {
        didSet { LauncherConfig.markDirty() }
    }
    /// 背景图片的自适应方式（PCL2 的 UiBackgroundSuit）。
    public var backgroundImageSuit: BackgroundImageSuit = .automatic {
        didSet { LauncherConfig.markDirty() }
    }
    /// 背景图片不透明度，取值 0…1000（PCL2 的 UiBackgroundOpacity，界面上除以 10 显示成百分比）。
    public var backgroundImageOpacity: Int = 1000 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 背景图片模糊半径（PCL2 的 UiBackgroundBlur），0 表示不模糊。
    public var backgroundImageBlur: Int = 0 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 页面底色是否叠加主题彩色背景（PCL2 的 UiBackgroundColorful）。
    ///
    /// 关掉时整块页面底色退回中性灰 #f5f5f5——原版就是给低配机器留的开关。
    public var backgroundColorful: Bool = true {
        didSet { LauncherConfig.markDirty() }
    }

    // MARK: - 启动默认值

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
        didSet {
            LauncherConfig.markDirty()
            // Core 的启动流程读的是 LauncherConfigDefaults 那份副本：不同步的话，
            // 改完设置要等下次启动才生效，表现就是「这个选项没用」。
            LauncherConfigDefaults.launcherVisibility = launcherVisibility
        }
    }
    /// 全局默认进程优先级。
    public var processPriority: ProcessPriority = .normal {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认启动前执行命令。
    public var prelaunchCommand: String = "" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认附加游戏参数。
    public var gameArguments: String = "" {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认额外 JVM 参数。
    public var jvmArguments: String = LauncherConfig.defaultJVMArguments {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局默认内存分配（MB），只在 memoryMode 为 custom 时使用。
    public var memory: UInt64 = 4096 {
        didSet { LauncherConfig.markDirty() }
    }
    /// 内存分配方式：自动配置按当前可用内存现算，自定义用上面的 memory。
    public var memoryMode: MemoryAllocationMode = .automatic {
        didSet { LauncherConfig.markDirty() }
    }
    /// 全局优先使用的 Java。nil 表示自动选择（交给 JavaSearcher 按版本挑）。
    ///
    /// 只在实例自己没有指定 Java 时生效：实例设置里选过的 Java 优先，
    /// 否则「自动选择」的用户会被全局值悄悄改掉。
    public var preferredJavaURL: URL? {
        didSet { LauncherConfig.markDirty() }
    }
    /// 垃圾回收器策略（设置 → 启动 → 高级选项 → 内存管理）。
    public var garbageCollector: GarbageCollectorMode = .tunedG1 {
        didSet { LauncherConfig.markDirty() }
    }

    /// PCL2 的默认 JVM 参数。
    ///
    /// 只作为「新配置的起点」与「高级选项里的还原按钮」的落点：
    /// 老配置里存的是它自己的值（大多为空串），升级不会替用户改写。
    public static let defaultJVMArguments: String =
        "-XX:-OmitStackTraceInFastThrow -Djdk.lang.Process.allowAmbiguousCommands=True "
        + "-Dfml.ignoreInvalidMinecraftCertificates=True -Dfml.ignorePatchDiscrepancies=True"

    /// 全局「内存分配」最终生效的值（MB）。
    ///
    /// 自动配置按当前可用内存现算，所以每次打开设置页、每次启动都可能不同——
    /// 这正是它的设计意图（PCL2 的自动配置也是现算的）。
    public var resolvedMemoryMB: UInt64 {
        resolvedMemoryMB()
    }

    /// 同上，但按具体实例的 Mod 量计算自动配置值。
    ///
    /// 设置页只能按「普通版本」的档位估算（那里没有实例上下文）；真正启动时
    /// 要把实例的 mods 目录数一遍，装了 300 个 Mod 的整合包与纯净版不该拿到同样的内存。
    public func resolvedMemoryMB(modCount: Int = 0, modable: Bool = false) -> UInt64 {
        switch memoryMode {
        case .custom:
            return memory
        case .automatic:
            let gigabytes: Double = MemoryAllocation.recommendedGigabytes(modCount: modCount, modable: modable)
            return UInt64((gigabytes * 1024).rounded())
        }
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
        // 缺这个键的配置按默认主页处理（预设 → PCL.Swift 更新日志）。
        // 用户自己选过的值照旧：旧配置里存着 "empty"（空白主页）就是空白，不会被这次改动改写。
        // 旧的 dashboard（启动器主页）已删除：解码失败时落到默认预设，升级不会被卡在未知枚举值上。
        self.homepageType = (try? container.decodeIfPresent(HomepageType.self, forKey: .homepageType)) ?? .preset
        self.homepagePreset = (try? container.decodeIfPresent(HomepagePreset.self, forKey: .homepagePreset)) ?? .changelog
        self.homepageURL = try container.decodeIfPresent(String.self, forKey: .homepageURL) ?? ""
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
        self.autoSetGameLanguage = try container.decodeIfPresent(Bool.self, forKey: .autoSetGameLanguage) ?? true
        self.separatesVersionListSource = try container.decodeIfPresent(Bool.self, forKey: .separatesVersionListSource) ?? false
        self.versionListSourcePolicy = try container.decodeIfPresent(DownloadSourcePolicy.self, forKey: .versionListSourcePolicy) ?? .officialFirst
        self.customCacheDirectory = try container.decodeIfPresent(URL.self, forKey: .customCacheDirectory)
        self.enableResourceListCache = try container.decodeIfPresent(Bool.self, forKey: .enableResourceListCache) ?? true
        self.resourceListCacheMinutes = try container.decodeIfPresent(Int.self, forKey: .resourceListCacheMinutes) ?? 10
        self.enableImageCache = try container.decodeIfPresent(Bool.self, forKey: .enableImageCache) ?? true
        // 旧配置里存的是自由模板（如 "{name}-{version}"），解不出枚举就退回原版默认值。
        self.resourceFileNameFormat = (try? container.decodeIfPresent(ResourceFileName.Format.self, forKey: .resourceFileNameFormat)) ?? .bracketSquare
        self.resourceTitleStyle = (try? container.decodeIfPresent(ResourceTitleStyle.self, forKey: .resourceTitleStyle)) ?? .nameFirst

        self.navigationBarBackground = (try? container.decodeIfPresent(NavigationBarBackground.self, forKey: .navigationBarBackground)) ?? .theme
        self.titleBarLogoType = (try? container.decodeIfPresent(TitleBarLogoType.self, forKey: .titleBarLogoType)) ?? .logo
        self.titleBarText = try container.decodeIfPresent(String.self, forKey: .titleBarText) ?? "PCL.Swift"
        self.titleBarImageURL = try container.decodeIfPresent(URL.self, forKey: .titleBarImageURL)

        self.backgroundImageURL = try container.decodeIfPresent(URL.self, forKey: .backgroundImageURL)
        self.backgroundImageSuit = (try? container.decodeIfPresent(BackgroundImageSuit.self, forKey: .backgroundImageSuit)) ?? .automatic
        self.backgroundImageOpacity = try container.decodeIfPresent(Int.self, forKey: .backgroundImageOpacity) ?? 1000
        self.backgroundImageBlur = try container.decodeIfPresent(Int.self, forKey: .backgroundImageBlur) ?? 0
        self.backgroundColorful = try container.decodeIfPresent(Bool.self, forKey: .backgroundColorful) ?? true

        self.gameWindowType = (try? container.decodeIfPresent(GameWindowType.self, forKey: .gameWindowType)) ?? .standard
        self.gameWindowWidth = try container.decodeIfPresent(Int.self, forKey: .gameWindowWidth) ?? 854
        self.gameWindowHeight = try container.decodeIfPresent(Int.self, forKey: .gameWindowHeight) ?? 480
        self.launcherVisibility = (try? container.decodeIfPresent(LauncherVisibility.self, forKey: .launcherVisibility)) ?? .keepVisible
        self.processPriority = (try? container.decodeIfPresent(ProcessPriority.self, forKey: .processPriority)) ?? .normal
        self.prelaunchCommand = try container.decodeIfPresent(String.self, forKey: .prelaunchCommand) ?? ""
        self.gameArguments = try container.decodeIfPresent(String.self, forKey: .gameArguments) ?? ""
        self.jvmArguments = try container.decodeIfPresent(String.self, forKey: .jvmArguments) ?? LauncherConfig.defaultJVMArguments
        self.memory = try container.decodeIfPresent(UInt64.self, forKey: .memory) ?? 4096
        // 旧配置没有这两个键：内存沿用原来的自定义值，GC 用 PCL2 的默认（调优 G1GC），
        // 与升级前的实际启动参数一致。
        self.memoryMode = (try? container.decodeIfPresent(MemoryAllocationMode.self, forKey: .memoryMode)) ?? .custom
        self.garbageCollector = (try? container.decodeIfPresent(GarbageCollectorMode.self, forKey: .garbageCollector)) ?? .tunedG1
        self.preferredJavaURL = try container.decodeIfPresent(URL.self, forKey: .preferredJavaURL)
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
        try container.encode(homepagePreset, forKey: .homepagePreset)
        try container.encode(homepageURL, forKey: .homepageURL)
        try container.encodeIfPresent(enabledFlags, forKey: .enabledFlags)
        try container.encode(customJavaRuntimes, forKey: .customJavaRuntimes)
        try container.encode(theme, forKey: .theme)

        try container.encode(themeHue, forKey: .themeHue)
        try container.encode(themeSaturation, forKey: .themeSaturation)
        try container.encode(themeBrightness, forKey: .themeBrightness)

        try container.encodeIfPresent(downloadMaxThreads, forKey: .downloadMaxThreads)
        try container.encode(downloadSpeedLimit, forKey: .downloadSpeedLimit)
        try container.encode(autoSetGameLanguage, forKey: .autoSetGameLanguage)
        try container.encode(separatesVersionListSource, forKey: .separatesVersionListSource)
        try container.encode(versionListSourcePolicy, forKey: .versionListSourcePolicy)
        try container.encodeIfPresent(customCacheDirectory, forKey: .customCacheDirectory)
        try container.encode(enableResourceListCache, forKey: .enableResourceListCache)
        try container.encode(resourceListCacheMinutes, forKey: .resourceListCacheMinutes)
        try container.encode(enableImageCache, forKey: .enableImageCache)
        try container.encode(resourceFileNameFormat, forKey: .resourceFileNameFormat)
        try container.encode(resourceTitleStyle, forKey: .resourceTitleStyle)

        try container.encode(navigationBarBackground, forKey: .navigationBarBackground)
        try container.encode(titleBarLogoType, forKey: .titleBarLogoType)
        try container.encode(titleBarText, forKey: .titleBarText)
        try container.encodeIfPresent(titleBarImageURL, forKey: .titleBarImageURL)

        try container.encodeIfPresent(backgroundImageURL, forKey: .backgroundImageURL)
        try container.encode(backgroundImageSuit, forKey: .backgroundImageSuit)
        try container.encode(backgroundImageOpacity, forKey: .backgroundImageOpacity)
        try container.encode(backgroundImageBlur, forKey: .backgroundImageBlur)
        try container.encode(backgroundColorful, forKey: .backgroundColorful)

        try container.encode(gameWindowType, forKey: .gameWindowType)
        try container.encode(gameWindowWidth, forKey: .gameWindowWidth)
        try container.encode(gameWindowHeight, forKey: .gameWindowHeight)
        try container.encode(launcherVisibility, forKey: .launcherVisibility)
        try container.encode(processPriority, forKey: .processPriority)
        try container.encode(prelaunchCommand, forKey: .prelaunchCommand)
        try container.encode(gameArguments, forKey: .gameArguments)
        try container.encode(jvmArguments, forKey: .jvmArguments)
        try container.encode(memory, forKey: .memory)
        try container.encode(memoryMode, forKey: .memoryMode)
        try container.encode(garbageCollector, forKey: .garbageCollector)
        try container.encodeIfPresent(preferredJavaURL, forKey: .preferredJavaURL)
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
        case homepagePreset
        case homepageURL
        case enabledFlags
        case customJavaRuntimes
        case theme
        case themeHue
        case themeSaturation
        case themeBrightness
        case downloadMaxThreads
        case downloadSpeedLimit
        case autoSetGameLanguage
        case separatesVersionListSource
        case versionListSourcePolicy
        case customCacheDirectory
        case enableResourceListCache
        case resourceListCacheMinutes
        case enableImageCache
        case resourceFileNameFormat
        case resourceTitleStyle
        case navigationBarBackground
        case titleBarLogoType
        case titleBarText
        case titleBarImageURL
        case backgroundImageURL
        case backgroundImageSuit
        case backgroundImageOpacity
        case backgroundImageBlur
        case backgroundColorful
        case gameWindowType
        case gameWindowWidth
        case gameWindowHeight
        case launcherVisibility
        case processPriority
        case prelaunchCommand
        case gameArguments
        case jvmArguments
        case memory
        case memoryMode
        case garbageCollector
        case preferredJavaURL
    }

    enum HomepageType: String, Codable, CaseIterable, CustomStringConvertible {
        /// 空白主页：右侧不渲染任何内容（原来的「启动器主页」整页已删除）。
        case empty
        /// 预设主页（PCL.Swift 更新日志 / Minecraft 新闻）。
        case preset
        /// 读取本地 Custom.xaml（与 PCL2 相同的主页文件）。
        case local
        /// 联网下载 Custom.xaml。
        case remote
        /// 控件预览（开发用）。
        case demo

        var description: String {
            switch self {
            case .empty: "空白"
            case .preset: "预设"
            case .local: "读取本地文件"
            case .remote: "联网更新"
            case .demo: "[内置] 控件预览"
            }
        }
    }

    /// 「Mod 管理样式」：已安装资源列表的标题显示哪一项。
    enum ResourceTitleStyle: String, Codable, CaseIterable, CustomStringConvertible {
        /// 标题显示名称，详情显示文件名（PCL2 的默认）。
        case nameFirst
        /// 标题显示文件名，详情显示名称。
        case fileFirst

        var description: String {
            switch self {
            case .nameFirst: "标题显示名称，详情显示文件名"
            case .fileFirst: "标题显示文件名，详情显示名称"
            }
        }
    }

    /// 预设主页。
    ///
    /// 顺序即设置页下拉框的顺序，第一项是默认值：更新日志放最前面。
    enum HomepagePreset: String, Codable, CaseIterable, CustomStringConvertible {
        /// 把每次发版的 CHANGELOG 当卡片铺在主页上（内容来自国内分发仓库）。
        case changelog
        case minecraftNews

        var description: String {
            switch self {
            case .changelog: "PCL.Swift 更新日志"
            case .minecraftNews: "Minecraft 新闻"
            }
        }
    }
}

/// 导航栏（标题栏）背景样式。
public enum NavigationBarBackground: String, Codable, CaseIterable, CustomStringConvertible {
    /// 纯主题色。
    case theme
    /// 主题色 + 白色线格。
    case lines

    public var description: String {
        switch self {
        case .theme: "纯色"
        case .lines: "线格"
        }
    }
}

/// 标题栏 Logo 的显示类型。
public enum TitleBarLogoType: String, Codable, CaseIterable, CustomStringConvertible {
    /// 不显示任何标识（PCL2 的「无」）。
    case none
    case logo, text, image

    public var description: String {
        switch self {
        case .none: "无"
        case .logo: "默认"
        case .text: "文本"
        case .image: "图片"
        }
    }
}

/// 背景图片的自适应方式。
///
/// 名称与顺序照 PCL2 的 PageSetupUI 里那个下拉框（UiBackgroundSuit 的 0…12），
/// 语义同样是 WPF 的 ImageBrush：Stretch 决定是否保持长宽比，
/// Alignment 决定图片对齐到哪一边。
public enum BackgroundImageSuit: String, Codable, CaseIterable, CustomStringConvertible {
    /// 图片比窗口小就平铺，否则按长宽比铺满（原版默认）。
    case automatic
    /// 按原始尺寸平铺。
    case tile
    /// 原始尺寸居中，超出部分裁掉。
    case center
    /// 拉伸填满整个窗口，会改变长宽比。
    case stretch
    case topLeft, centerLeft, bottomLeft
    case topCenter
    /// 保持长宽比铺满窗口（默认的「适应」）。
    case aspectFit
    case bottomCenter
    case topRight, centerRight, bottomRight

    public var description: String {
        switch self {
        case .automatic: "自动"
        case .tile: "平铺"
        case .center: "居中"
        case .stretch: "拉伸"
        case .topLeft: "左上 (保持长宽比)"
        case .centerLeft: "左中 (保持长宽比)"
        case .bottomLeft: "左下 (保持长宽比)"
        case .topCenter: "中上 (保持长宽比)"
        case .aspectFit: "居中 (保持长宽比)"
        case .bottomCenter: "中下 (保持长宽比)"
        case .topRight: "右上 (保持长宽比)"
        case .centerRight: "右中 (保持长宽比)"
        case .bottomRight: "右下 (保持长宽比)"
        }
    }

    /// 对应 WPF 的对齐方式，SwiftUI 侧换算成 Alignment 与填充模式。
    public var alignment: Alignment {
        switch self {
        case .topLeft: .topLeading
        case .centerLeft: .leading
        case .bottomLeft: .bottomLeading
        case .topCenter: .top
        case .bottomCenter: .bottom
        case .topRight: .topTrailing
        case .centerRight: .trailing
        case .bottomRight: .bottomTrailing
        case .automatic, .tile, .center, .stretch, .aspectFit: .center
        }
    }
}
