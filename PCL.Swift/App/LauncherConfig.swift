//
//  LauncherConfig.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2025/12/26.
//

import Foundation
import Core

class LauncherConfig: Codable {
    /// `shared` 构造期间为 `false`：解码过程会依次给各属性赋值，
    /// 此时触发写盘会递归访问尚未构造完成的 `shared`。
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
    public private(set) static var loadError: Error?
    
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
    /// 与 `hasEnteredLauncher` 分开：后者记录"进过主界面"，这里记录"走完了
    /// 开场流程"。旧配置里没有这个键时会解码为 `false`，于是升级后的第一次
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
    }
    
    /// 合并短时间内的多次变更，避免每个字段改动都触发一次写盘。
    private static var pendingSave: DispatchWorkItem?
    /// 写盘前至少等待的静默时间。
    private static let saveDebounceInterval: TimeInterval = 0.5
    
    /// 声明配置已被修改，稍后落盘。
    ///
    /// 此前只有退出时（`applicationWillTerminate`）才写盘，崩溃或强退会丢掉
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
    }
    
    enum HomepageType: String, Codable, CustomStringConvertible {
        case empty, demo
        
        var description: String {
            switch self {
            case .empty: "空白"
            case .demo: "[内置] 控件预览"
            }
        }
    }
}
