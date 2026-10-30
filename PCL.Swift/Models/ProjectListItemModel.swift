//
//  ProjectListItemModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/18.
//

import Foundation
import Core

struct ProjectListItemModel: Identifiable, Equatable, Hashable {
    /// 结果来自哪个站点。
    ///
    /// 合并搜索时两个站点的 id 是两套东西（Modrinth 是 slug，CurseForge 是数字），
    /// 安装页要靠它决定去哪拉版本列表、点「查看项目页」时开哪个网址。
    enum Source: Hashable {
        case modrinth(id: String)
        case curseforge(id: Int)
        
        /// 项目页所在站点的名字，用在安装页的按钮上。
        var siteName: String {
            switch self {
            case .modrinth: "Modrinth"
            case .curseforge: "CurseForge"
            }
        }
    }
    
    public let id: String
    public let source: Source
    public let title: String
    /// 译名。查不到就是 nil，界面与文件名都退回 `title`。
    public let translatedTitle: String?
    public let description: String
    public let type: ResourceType
    public let iconURL: URL?
    public let projectURL: URL?
    public let tags: [String]
    public let supportDescription: String
    public let onlySupportsSnapshot: Bool
    public let downloads: String
    public let lastUpdate: String
    
    public init(id: String, source: Source, title: String, translatedTitle: String?, description: String, type: ResourceType, iconURL: URL?, projectURL: URL?, tags: [String], supportDescription: String, onlySupportsSnapshot: Bool, downloads: String, lastUpdate: String) {
        self.id = id
        self.source = source
        self.title = title
        self.translatedTitle = translatedTitle
        self.description = description
        self.type = type
        self.iconURL = iconURL
        self.projectURL = projectURL
        self.tags = tags
        self.supportDescription = supportDescription
        self.onlySupportsSnapshot = onlySupportsSnapshot
        self.downloads = downloads
        self.lastUpdate = lastUpdate
    }
    
    public init(_ project: ModrinthProject) {
        let (supportDescription, onlySupportsSnapshot) = Self.generateSupportDescription(for: project)
        
        self.init(
            id: project.id,
            source: .modrinth(id: project.id),
            title: project.title,
            translatedTitle: ResourceTranslation.shared.name(slug: project.slug, title: project.title),
            description: project.description,
            type: project.type,
            iconURL: project.iconURL,
            projectURL: URL(string: "https://modrinth.com/project/\(project.id)"),
            tags: project.categories.compactMap(Self.localizeTag(_:)),
            supportDescription: supportDescription,
            onlySupportsSnapshot: onlySupportsSnapshot,
            downloads: Self.formatDownloads(project.downloads),
            lastUpdate: Self.formatLastUpdate(project.lastUpdate)
        )
    }
    
    /// 用 CurseForge 的搜索结果构造列表项。
    ///
    /// 搜索结果里没有完整的版本清单，只有 `latestFilesIndexes`（游戏版本 + 加载器），
    /// 所以「支持情况」只能给个大概——点进去看到的版本列表才是准的。
    public init(_ mod: CurseForgeMod, type: ResourceType) {
        var support: String = mod.loaders.map(\.description).joined(separator: " / ")
        if let latest = mod.gameVersions.first {
            if !support.isEmpty { support += " " }
            support += "\(latest)+"
        }
        
        self.init(
            id: "curseforge-\(mod.id)",
            source: .curseforge(id: Int(mod.id)),
            title: mod.name,
            translatedTitle: ResourceTranslation.shared.name(slug: nil, title: mod.name),
            description: mod.summary,
            type: mod.projectType ?? type,
            iconURL: mod.logo.thumbnailURL ?? mod.logo.url,
            projectURL: mod.links?.websiteURL,
            tags: (mod.categories ?? []).compactMap { Self.localizeTag($0.name) },
            supportDescription: support,
            onlySupportsSnapshot: false,
            downloads: Self.formatDownloads(mod.downloads?.total ?? 0),
            lastUpdate: Self.parseDate(mod.dateModified).map(Self.formatLastUpdate) ?? ""
        )
    }
    
    /// 界面上显示的名字：有译名就用译名。
    public var displayTitle: String { translatedTitle ?? title }

    /// 落盘文件名里用的名字：有译名就用译名，否则交给 ResourceFileName 的「无译名」分支。
    public var fileNameTitle: String { translatedTitle ?? title }

    public static func formatLastUpdate(_ lastUpdate: Date) -> String {
        let formatter: RelativeDateTimeFormatter = .init()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: lastUpdate, relativeTo: Date())
            .replacingOccurrences(of: "(\\d+)", with: " $1 ", options: .regularExpression)
    }
    
    public static func formatDownloads(_ downloads: Int) -> String {
        if downloads > 10000 * 10000 {
            return String(format: "%.2f 亿", Double(downloads) / 10000 / 10000)
        } else if downloads > 10000 {
            return "\(downloads / 10000) 万"
        } else {
            return downloads.description
        }
    }
    
    /// 把站点给的分类名翻成中文。
    ///
    /// Modrinth 的分类是 slug（`game-mechanics`），CurseForge 的是标题（`API and Library`），
    /// 所以先统一成 slug 再查同一张本地化表；查不到就原样显示。
    public static func localizeTag(_ key: String) -> String? {
        let slug: String = key
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        let localizationKey = "category.modrinth.\(slug)"
        let localized = NSLocalizedString(localizationKey, comment: "")
        if localized != localizationKey { return localized }
        return key.isEmpty ? nil : key
    }
    
    /// CurseForge 的时间是 ISO8601 字符串，小数位不固定，这里按几种格式依次试。
    public static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let withFraction: ISO8601DateFormatter = .init()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain: ISO8601DateFormatter = .init()
        if let date = plain.date(from: raw) { return date }
        let fallback: DateFormatter = .init()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(identifier: "UTC")
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return fallback.date(from: raw)
    }
    
    private static func generateSupportDescription(for project: ModrinthProject) -> (String, Bool) {
        guard let versionManifest = VersionManifest.shared else { return ("", false) }
        
        var description: String = ""
        
        let modLoaders: [ModLoader] = project.categories.compactMap(ModLoader.init(rawValue:))
        if modLoaders.count == 1 {
            description += "仅 \(modLoaders.first!.description)"
        } else if modLoaders.count < 3 {
            description += modLoaders.map(\.description).joined(separator: " / ")
        }
        if !description.isEmpty { description += " " }
        
        guard let gameVersions = project.gameVersions else {
            return (description + "未知", false)
        }
        let releaseVersions: [String] = gameVersions.filter { versionManifest.version(for: $0)?.type == .release }
        guard !releaseVersions.isEmpty else {
            return (description + (modLoaders.count == 1 ? "" : "仅") + "快照版本", true)
        }
        description += generateGameVersionDescription(releaseVersions, latestVersion: versionManifest.latestRelease)
        
        return (description, false)
    }
    
    private static func generateGameVersionDescription(_ gameVersions: [String], latestVersion: String) -> String {
        guard gameVersions.count > 1 else {
            return gameVersions.isEmpty ? "" : gameVersions[0]
        }
        guard let latestPair: VersionPair = .init(latestVersion) else {
            return "错误"
        }
        
        func rangeDescription(start: VersionPair, end: VersionPair) -> String {
            if start == end {
                return start.description
            } else if end == latestPair {
                return "\(start)+"
            } else {
                return "\(start)~\(end)"
            }
        }
        
        let versionPairs: [VersionPair] = Array(Set(gameVersions.compactMap(VersionPair.init))).sorted()
        
        var ranges: [String] = []
        var start: VersionPair = versionPairs[0]
        var end: VersionPair = start
        for pair in versionPairs.dropFirst() {
            if pair.isNext(to: end) {
                end = pair
            } else {
                ranges.append(rangeDescription(start: start, end: end))
                start = pair
                end = pair
            }
        }
        ranges.append(rangeDescription(start: start, end: end))
        return ranges.reversed().joined(separator: ", ")
    }
    
    private struct VersionPair: Hashable, Equatable, Comparable, CustomStringConvertible {
        public let major: Int
        public let minor: Int
        private let rawVersion: String
        
        public init?(_ version: String) {
            let parts: [Int] = version.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 2 else { return nil }
            self.major = parts[0]
            self.minor = parts[1]
            self.rawVersion = version
        }
        
        public func isNext(to another: VersionPair) -> Bool {
            if self == another { return false }
            // 确保版本号格式相同
            if (self.major == 1 && another.major != 1) || (another.major == 1 && self.major != 1) {
                let boundaryVersions: [String] = ["1.21", "26.1"]
                return boundaryVersions.contains(self.rawVersion) && boundaryVersions.contains(another.rawVersion)
            }
            
            if self.major == another.major {
                return abs(self.minor - another.minor) == 1
            } else {
                if self.minor == 1 {
                    return another.major == self.major - 1 && another.isYearlyLatest()
                } else if another.minor == 1 {
                    return self.major == another.major - 1 && self.isYearlyLatest()
                } else {
                    return false
                }
            }
        }
        
        /// 检查当前版本是不是该年份（26）的最后一个版本（正式更新，例如 26.4）。
        /// 在该版本号的格式为旧版格式时，此函数一定会返回 `false`。
        public func isYearlyLatest() -> Bool {
            guard let manifest = VersionManifest.shared else { return false }
            if major == 1 { return false }
            let yearlyLatest: VersionPair? = manifest.versions
                .filter { $0.type == .release && $0.id.starts(with: "\(major).") }
                .first.flatMap { VersionPair($0.id) }
            return self == yearlyLatest
            
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(major)
            hasher.combine(minor)
            // 忽略 rawVersion
        }
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.major == rhs.major && lhs.minor == rhs.minor // 忽略 rawVersion
        }
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < rhs.major
            }
            return lhs.minor < rhs.minor
        }
        
        public var description: String {
            "\(major).\(minor)"
        }
    }
}
