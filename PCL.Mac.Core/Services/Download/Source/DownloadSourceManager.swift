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

    public var recommendedConcurrency: Int {
        if !isChinaRegion && policy != .mirrorFirst {
            return Self.officialConcurrency
        }
        return Self.mirrorConcurrency
    }

    public init(policy: DownloadSourcePolicy, curseforgeApiKey: String?) {
        self.policy = policy
        officialSource.curseforgeApiKey = curseforgeApiKey
    }

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
    public func versionManifestURL() -> URL? {
        preferred(official: officialSource.versionManifestURL(),
                  mirror: mirrorSource.versionManifestURL())
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
    
    private func preferred(official: URL?, mirror: URL?) -> URL? {
        let preferMirror = policy == .mirrorFirst

        if !isChinaRegion && policy != .mirrorFirst {
            return official ?? mirror
        }

        return preferMirror ? (mirror ?? official) : (official ?? mirror)
    }
}
