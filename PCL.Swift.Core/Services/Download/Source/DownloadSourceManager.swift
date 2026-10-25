//
//  DownloadSourceManager.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/6/24.
//

import Foundation

public enum DownloadSourcePolicy: String, Codable {
    /// 优先使用官方源。
    case officialFirst
    /// 优先使用镜像源。
    case mirrorFirst
}

public class DownloadSourceManager {
    private static var _shared: DownloadSourceManager?

    /// 全局实例。必须在启动阶段由 `AppDelegate` 注入后才能访问：
    /// 早于注入访问会立刻在注入点给出可定位的失败，而不是在某个随机调用点崩溃。
    public static var shared: DownloadSourceManager {
        guard let instance = _shared else {
            fatalError("DownloadSourceManager.shared 在注入之前被访问，请检查 AppDelegate 的初始化顺序。")
        }
        return instance
    }

    public static func install(_ instance: DownloadSourceManager) {
        _shared = instance
    }

    public var officialSource: OfficialDownloadSource = .shared
    public let mirrorSource: MirrorDownloadSource = .shared

    public var policy: DownloadSourcePolicy

    private var isChinaRegion: Bool = LocaleUtils.isSystemLocaleChinese()

    public static let officialConcurrency: Int = 64
    public static let mirrorConcurrency: Int = 16
    /// 并发数的合法区间。上限比原版（255）保守：URLSession 在这个量级上
    /// 已经不会更快，再高只会触发对端限流。
    public static let concurrencyRange: ClosedRange<Int> = 1...128

    /// 用户显式设置的并发数。nil 表示跟随下载源推荐值。
    ///
    /// 单独存一份而不是直接覆盖推荐值：换下载源时推荐值会变，
    /// 但用户设过的数字不该被悄悄改掉。
    public var userConcurrency: Int?

    /// 用户设置的限速（字节/秒）。0 表示不限速。
    public var speedLimit: Int64 = 0

    public var recommendedConcurrency: Int {
        if !isChinaRegion && policy != .mirrorFirst {
            return Self.officialConcurrency
        }
        return Self.mirrorConcurrency
    }

    /// 设置用户并发数；传 nil 恢复为跟随下载源推荐值。
    public func setUserConcurrency(_ value: Int?) {
        guard let value else {
            userConcurrency = nil
            return
        }
        userConcurrency = min(max(value, Self.concurrencyRange.lowerBound), Self.concurrencyRange.upperBound)
    }

    public init(policy: DownloadSourcePolicy, curseforgeApiKey: String?) {
        self.policy = policy
        officialSource.curseforgeApiKey = curseforgeApiKey
    }

    /// 更新 CurseForge API Key。
    ///
    /// Key 只影响发往 edge.forgecdn.net 的请求头，用户在设置里改了之后
    /// 不需要重建整个管理器；但必须真的调到，否则下一次下载仍用旧 Key。
    public func updateCurseforgeAPIKey(_ key: String?) {
        officialSource.curseforgeApiKey = key
    }

    /// 版本列表专用策略。
    ///
    /// 未开启"分开设置"时跟随文件下载源，这样只有老字段的配置行为不变。
    public var versionListPolicy: DownloadSourcePolicy {
        separatesVersionList ? versionListSourcePolicy : policy
    }

    public var separatesVersionList: Bool = false
    public var versionListSourcePolicy: DownloadSourcePolicy = .officialFirst

    /// 从云端刷新地区判断（启动时调用一次）。
    public func refreshRegion() async {
        isChinaRegion = await LocaleUtils.isInChinaMainland()
    }

    /// 生成指定 `URL` 按策略排序的下载候选项列表。
    /// - Parameters:
    ///   - url: 原始 `URL`。
    ///   - preferMirror: 是否优先使用镜像源，为 `nil` 时由全局策略决定。
    /// - Returns: 按优先级排序的候选项列表。
    public func orderedCandidates(for url: URL, preferMirror: Bool? = nil) -> [DownloadCandidate] {
        let official = officialSource.candidate(for: url)
        let mirror = isChinaRegion || (policy == .mirrorFirst || preferMirror == true) ? mirrorSource.candidate(for: url) : nil
        
        let preferMirror = preferMirror ?? (policy == .mirrorFirst)

        let merged = (preferMirror ? [mirror, official] : [official, mirror]).compactMap(\.self)
        var seen = Set<URL>()
        return merged.filter { seen.insert($0.url).inserted }
    }

    /// 版本清单 URL。
    ///
    /// 版本列表可以单独选源：Mojang 的清单在境内偶尔抽风，而文件本身走官方源很快，
    /// 所以两者分开配置是有意义的。
    public func versionManifestURL() -> URL? {
        preferred(official: officialSource.versionManifestURL(),
                  mirror: mirrorSource.versionManifestURL(),
                  policy: versionListPolicy)
    }

    /// Forge 版本列表 URL。
    public func forgeVersionListURL(for mcVersion: String) -> URL? {
        preferred(official: officialSource.forgeVersionListURL(for: mcVersion),
                  mirror: mirrorSource.forgeVersionListURL(for: mcVersion))
    }

    /// NeoForge 版本列表 URL。
    public func neoforgeVersionListURL(for mcVersion: String) -> URL? {
        preferred(official: officialSource.neoforgeVersionListURL(for: mcVersion),
                  mirror: mirrorSource.neoforgeVersionListURL(for: mcVersion))
    }

    /// Fabric 版本列表 URL。
    public func fabricVersionListURL(for mcVersion: String) -> URL? {
        preferred(official: officialSource.fabricVersionListURL(for: mcVersion),
                  mirror: mirrorSource.fabricVersionListURL(for: mcVersion))
    }
    
    private func preferred(official: URL?, mirror: URL?, policy: DownloadSourcePolicy? = nil) -> URL? {
        let effectivePolicy: DownloadSourcePolicy = policy ?? self.policy
        let preferMirror = effectivePolicy == .mirrorFirst

        if !isChinaRegion && effectivePolicy != .mirrorFirst {
            return official ?? mirror
        }

        return preferMirror ? (mirror ?? official) : (official ?? mirror)
    }
}
