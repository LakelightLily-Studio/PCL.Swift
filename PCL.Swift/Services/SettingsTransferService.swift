//
//  SettingsTransferService.swift
//  PCL.Swift
//
//  启动器设置的导入与导出。
//
//  为什么不直接序列化整个 LauncherConfig：
//  - 里面混着账号凭据（accounts / currentAccountId / hasMicrosoftAccount），
//    导出成文件就等于把令牌写到磁盘上，用户随手一分享就泄露了。
//  - minecraftRepositories 与 currentRepositoryId 描述的是本机的目录结构，
//    换台机器导入这些路径基本都不存在。
//  所以这里用一份"可迁移设置"的白名单结构，只带真正跨机器有意义的部分。
//

import Foundation
import Core

public enum SettingsTransferService {
    /// 导出文件里出现的字段白名单。
    ///
    /// 用显式结构而不是"编码后删键"：删键方案一旦 LauncherConfig 加了新字段，
    /// 新字段就会默认被导出，敏感字段正是这样漏出去的。
    struct TransferableSettings: Codable {
        var downloadSourcePolicy: DownloadSourcePolicy?
        var separatesVersionListSource: Bool?
        var versionListSourcePolicy: DownloadSourcePolicy?
        var downloadMaxThreads: Int?
        var downloadSpeedLimit: Int?
        var theme: String?
        var themeHue: Double?
        var themeSaturation: Double?
        var themeBrightness: Double?
        var backgroundOpacity: Double?
        var backgroundBlur: Double?
        var backgroundTinted: Bool?
        var backgroundFills: Bool?
        var titleBarLogoType: String?
        var titleBarText: String?
        var gameWindowTitle: String?
        var gameWindowType: String?
        var gameWindowWidth: Int?
        var gameWindowHeight: Int?
        var launcherVisibility: String?
        var processPriority: String?
        var prelaunchCommand: String?
        var prelaunchWaitForCompletion: Bool?
        var gameArguments: String?
        var jvmArguments: String?
        var memory: UInt64?
        var memoryOptimize: Bool?
        var enabledFlags: [String]?
    }

    /// 导出设置的 JSON 数据。
    ///
    /// - Parameters:
    ///   - config: 源配置。
    /// - Returns: 可直接写盘的 JSON 数据。
    static func exportData(from config: LauncherConfig) throws -> Data {
        let settings: TransferableSettings = .init(
            downloadSourcePolicy: config.downloadSourcePolicy,
            separatesVersionListSource: config.separatesVersionListSource,
            versionListSourcePolicy: config.versionListSourcePolicy,
            downloadMaxThreads: config.downloadMaxThreads,
            downloadSpeedLimit: config.downloadSpeedLimit,
            theme: config.theme.rawValue,
            themeHue: config.themeHue,
            themeSaturation: config.themeSaturation,
            themeBrightness: config.themeBrightness,
            backgroundOpacity: config.backgroundOpacity,
            backgroundBlur: config.backgroundBlur,
            backgroundTinted: config.backgroundTinted,
            backgroundFills: config.backgroundFills,
            titleBarLogoType: config.titleBarLogoType.rawValue,
            titleBarText: config.titleBarText,
            gameWindowTitle: config.gameWindowTitle,
            gameWindowType: config.gameWindowType.rawValue,
            gameWindowWidth: config.gameWindowWidth,
            gameWindowHeight: config.gameWindowHeight,
            launcherVisibility: config.launcherVisibility.rawValue,
            processPriority: config.processPriority.rawValue,
            prelaunchCommand: config.prelaunchCommand,
            prelaunchWaitForCompletion: config.prelaunchWaitForCompletion,
            gameArguments: config.gameArguments,
            jvmArguments: config.jvmArguments,
            memory: config.memory,
            memoryOptimize: config.memoryOptimize,
            enabledFlags: config.enabledFlags.map { $0.map(\.rawValue) }
        )

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(settings)
    }

    /// 从 JSON 数据导入设置，覆盖到目标配置。
    ///
    /// 只覆盖白名单里的字段，其余（账号、目录、首启标记）保持不动。
    /// - Parameters:
    ///   - data: 导出时产生的 JSON 数据。
    ///   - config: 目标配置。
    /// - Returns: 实际被覆盖的字段数量，用于给用户一个"确实导入了"的反馈。
    @discardableResult
    static func importData(_ data: Data, into config: LauncherConfig) throws -> Int {
        let settings: TransferableSettings = try JSONDecoder().decode(TransferableSettings.self, from: data)
        var applied: Int = 0

        func apply<T>(_ value: T?, _ assign: (T) -> Void) {
            guard let value else { return }
            assign(value)
            applied += 1
        }

        apply(settings.downloadSourcePolicy) { config.downloadSourcePolicy = $0 }
        apply(settings.separatesVersionListSource) { config.separatesVersionListSource = $0 }
        apply(settings.versionListSourcePolicy) { config.versionListSourcePolicy = $0 }
        apply(settings.downloadMaxThreads) { config.downloadMaxThreads = $0 }
        apply(settings.downloadSpeedLimit) { config.downloadSpeedLimit = $0 }

        // 枚举按 rawValue 还原：导入的文件可能来自旧版本或手改过，
        // 认不出的值直接跳过而不是让整次导入失败。
        if let raw = settings.theme, let theme = Theme(rawValue: raw) { config.theme = theme; applied += 1 }
        apply(settings.themeHue) { config.themeHue = $0 }
        apply(settings.themeSaturation) { config.themeSaturation = $0 }
        apply(settings.themeBrightness) { config.themeBrightness = $0 }

        apply(settings.backgroundOpacity) { config.backgroundOpacity = $0 }
        apply(settings.backgroundBlur) { config.backgroundBlur = $0 }
        apply(settings.backgroundTinted) { config.backgroundTinted = $0 }
        apply(settings.backgroundFills) { config.backgroundFills = $0 }

        if let raw = settings.titleBarLogoType, let type = TitleBarLogoType(rawValue: raw) { config.titleBarLogoType = type; applied += 1 }
        apply(settings.titleBarText) { config.titleBarText = $0 }

        apply(settings.gameWindowTitle) { config.gameWindowTitle = $0 }
        if let raw = settings.gameWindowType, let type = GameWindowType(rawValue: raw) { config.gameWindowType = type; applied += 1 }
        apply(settings.gameWindowWidth) { config.gameWindowWidth = $0 }
        apply(settings.gameWindowHeight) { config.gameWindowHeight = $0 }
        if let raw = settings.launcherVisibility, let value = LauncherVisibility(rawValue: raw) { config.launcherVisibility = value; applied += 1 }
        if let raw = settings.processPriority, let value = ProcessPriority(rawValue: raw) { config.processPriority = value; applied += 1 }
        apply(settings.prelaunchCommand) { config.prelaunchCommand = $0 }
        apply(settings.prelaunchWaitForCompletion) { config.prelaunchWaitForCompletion = $0 }
        apply(settings.gameArguments) { config.gameArguments = $0 }
        apply(settings.jvmArguments) { config.jvmArguments = $0 }
        apply(settings.memory) { config.memory = $0 }
        apply(settings.memoryOptimize) { config.memoryOptimize = $0 }

        if let raw = settings.enabledFlags {
            config.enabledFlags = Set(raw.compactMap { FeatureFlag(rawValue: $0) })
            applied += 1
        }

        return applied
    }

    public enum TransferError: LocalizedError {
        case decodeFailed(underlying: Error)
        case encodeFailed(underlying: Error)
        case nothingApplied

        public var errorDescription: String? {
            switch self {
            case .decodeFailed(let underlying):
                "解析设置文件失败：\(underlying.localizedDescription)"
            case .encodeFailed(let underlying):
                "生成设置文件失败：\(underlying.localizedDescription)"
            case .nothingApplied:
                "这个文件里没有任何可导入的设置项。"
            }
        }
    }
}
