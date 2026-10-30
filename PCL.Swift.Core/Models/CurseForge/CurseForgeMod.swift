//
//  CurseForgeMod.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/5/4.
//

import Foundation

public struct CurseForgeMod: Codable {
    public struct Category: Codable, Hashable {
        public let id: Int
        public let name: String
    }
    
    public struct Downloads: Codable {
        public let total: Int
    }
    
    public struct Links: Codable {
        public let websiteURL: URL?
        
        private enum CodingKeys: String, CodingKey {
            case websiteURL = "websiteUrl"
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.websiteURL = try? container.decode(URL.self, forKey: .websiteURL)
        }
    }
    
    /// 搜索结果里的「最新文件索引」：只有版本号与加载器，没有文件本身。
    public struct LatestFileIndex: Codable {
        public let gameVersion: String?
        public let modLoader: Int?
    }
    
    public let id: Int32
    public let name: String
    public let summary: String
    public let logo: CurseForgeModAsset
    public let classId: Int?
    public let downloads: Downloads?
    /// ISO8601 字符串，用的时候再解析（见 ProjectListItemModel）。
    public let dateModified: String?
    public let categories: [Category]?
    public let links: Links?
    public let latestFilesIndexes: [LatestFileIndex]?
    
    public var projectType: ResourceType? {
        switch classId {
        case 12: .resourcepack
        case 6: .mod
        case 4471: .modpack
        case 6552: .shader
        case 6945: .datapack
        default: nil
        }
    }
    
    /// CurseForge 的 classId（搜索时必须带上，否则会混进别的类型）。
    public static func classId(for type: ResourceType) -> Int {
        switch type {
        case .mod: 6
        case .resourcepack: 12
        case .modpack: 4471
        case .shader: 6552
        case .datapack: 6945
        }
    }
    
    /// 游戏版本 → 界面上的支持情况。搜索结果里只有 latestFilesIndexes，够用了。
    public var gameVersions: [String] {
        Array(Set(latestFilesIndexes?.compactMap(\.gameVersion) ?? [])).sorted()
    }
    
    public var loaders: [ModLoader] {
        let types: Set<Int> = Set(latestFilesIndexes?.compactMap(\.modLoader) ?? [])
        return types.compactMap(ModLoader.init(curseforgeType:)).sorted { $0.index < $1.index }
    }
}

extension ModLoader {
    /// CurseForge 的 ModLoaderType 枚举。
    public init?(curseforgeType: Int) {
        switch curseforgeType {
        case 1: self = .forge
        case 4: self = .fabric
        case 6: self = .neoforge
        default: return nil
        }
    }
    
    public var curseforgeType: Int {
        switch self {
        case .forge: 1
        case .fabric: 4
        case .neoforge: 6
        }
    }
}

public struct CurseForgeModAsset: Codable {
    public let id: Int32
    public let title: String
    public let url: URL?
    public let thumbnailURL: URL?
    
    private enum CodingKeys: String, CodingKey {
        case id, title, url, thumbnailURL = "thumbnailUrl"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int32.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.url = try? container.decode(URL.self, forKey: .url)
        self.thumbnailURL = try? container.decode(URL.self, forKey: .thumbnailURL)
    }
}

public struct CurseForgeModFile: Codable {
    public struct FileHash: Codable {
        public let value: String
        public let algo: Int
    }
    
    /// 文件的前置依赖（relationType = 3 是必需）。
    public struct Dependency: Codable {
        public let modId: Int32
        public let relationType: Int
    }
    
    public let id: Int32
    public let modId: Int32
    public let available: Bool
    public let fileName: String
    public let hashes: [FileHash]
    public let downloadURL: URL
    public let displayName: String?
    public let fileDate: String?
    public let releaseType: Int?
    public let gameVersions: [String]
    public let modLoader: Int?
    public let dependencies: [Dependency]?
    
    public var checksums: [String: String] {
        return hashes.reduce(into: [:]) { result, hash in
            switch hash.algo {
            case 1: result["sha1"] = hash.value
            case 2: result["md5"] = hash.value
            default: break
            }
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, modId, fileName, hashes, displayName, fileDate, releaseType, gameVersions, modLoader, dependencies
        case available = "isAvailable", downloadURL = "downloadUrl"
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int32.self, forKey: .id)
        self.modId = try container.decode(Int32.self, forKey: .modId)
        self.fileName = try container.decode(String.self, forKey: .fileName)
        self.hashes = try container.decode([CurseForgeModFile.FileHash].self, forKey: .hashes)
        self.available = try container.decode(Bool.self, forKey: .available)
        self.downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL) ?? .init(string: "https://edge.forgecdn.net/files/\(id / 1000)/\(id % 1000)/\(fileName)")!
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        self.fileDate = try container.decodeIfPresent(String.self, forKey: .fileDate)
        self.releaseType = try container.decodeIfPresent(Int.self, forKey: .releaseType)
        self.gameVersions = try container.decodeIfPresent([String].self, forKey: .gameVersions) ?? []
        self.modLoader = try container.decodeIfPresent(Int.self, forKey: .modLoader)
        self.dependencies = try container.decodeIfPresent([Dependency].self, forKey: .dependencies)
    }
}

/// CurseForge 的分类（用于「类型」下拉框）。
public struct CurseForgeCategory: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let slug: String?
    public let classId: Int?
    public let parentCategoryId: Int?
}
