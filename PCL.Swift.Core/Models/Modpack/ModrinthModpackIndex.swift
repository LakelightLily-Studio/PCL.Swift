//
//  ModrinthModpackIndex.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/22.
//

import Foundation

public struct ModrinthModpackIndex: Codable {
    public struct File: Codable {
        public let path: String
        public let hashes: [String: String]
        public let env: [Side: ModrinthCompatibility]?
        public let downloads: [URL]
        
        private enum CodingKeys: CodingKey {
            case path, hashes, env, downloads
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.path = try container.decode(String.self, forKey: .path)
            self.hashes = try container.decode([String: String].self, forKey: .hashes)
            if let rawEnv: [String: ModrinthCompatibility] = try container.decodeIfPresent([String: ModrinthCompatibility].self, forKey: .env) {
                self.env = Dictionary(
                    uniqueKeysWithValues: rawEnv.compactMap { key, value in
                        guard let side = Side(rawValue: key) else { return nil }
                        return (side, value)
                    }
                )
            } else {
                self.env = nil
            }
            self.downloads = try container.decode([URL].self, forKey: .downloads)
        }
    }
    
    public struct Dependencies: Codable, CustomStringConvertible {
        public let minecraft: String
        public let forge: String?
        public let neoforge: String?
        public let fabricLoader: String?
        public let quiltLoader: String?
        
        private enum CodingKeys: String, CodingKey {
            case minecraft, forge, neoforge
            case fabricLoader = "fabric-loader", quiltLoader = "quilt-loader"
        }
        
        public var description: String {
            var description: String = "Minecraft \(minecraft)"
            if let forge {
                description += ", Forge \(forge)"
            } else if let neoforge {
                description += ", NeoForge \(neoforge)"
            } else if let fabricLoader {
                description += ", Fabric \(fabricLoader)"
            } else if let quiltLoader {
                description += ", Quilt \(quiltLoader)"
            }
            return description
        }
        
        /// 返回本整合包声明的模组加载器与版本号；未声明加载器时返回 `nil`。
        /// - Throws: `ModpackLoaderError.unsupportedDeclaredLoader`，当声明的是本启动器
        ///   尚未支持的加载器。
        ///
        /// 此前该方法对 `quilt` 只做透传，返回值到 `ModpackImportService.parseModLoader(_:)`
        /// 的 `ModLoader(rawValue:)` 必然失败，最终以 `unsupportedModLoader` 兜底；
        /// 现在由声明处直接把「不支持」说出来，调用方不必再从兜底错误里反推原因。
        public func modLoader() throws(ModpackLoaderError) -> (ModLoader, String)? {
            if let forge { return (.forge, forge) }
            if let neoforge { return (.neoforge, neoforge) }
            if let fabricLoader { return (.fabric, fabricLoader) }
            if quiltLoader != nil { throw .unsupportedDeclaredLoader(name: "Quilt") }
            return nil
        }
    }
    
    /// 整合包声明的加载器不能被本启动器处理时的原因。
    public enum ModpackLoaderError: Error {
        case unsupportedDeclaredLoader(name: String)
    }
    
    public let formatVersion: Int
    public let name: String
    public let summary: String?
    public let game: String
    public let versionId: String
    public let files: [File]
    public let dependencies: Dependencies

    public init(
        formatVersion: Int,
        name: String,
        summary: String?,
        game: String,
        versionId: String,
        files: [File],
        dependencies: Dependencies
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.summary = summary
        self.game = game
        self.versionId = versionId
        self.files = files
        self.dependencies = dependencies
    }
}

// MARK: - 导出用

extension ModrinthModpackIndex.File {
    /// 构造一条导出条目。导出时只有 path、sha1 与下载地址是已知的。
    public init(path: String, hashes: [String: String], downloads: [URL]) {
        self.path = path
        self.hashes = hashes
        self.env = nil
        self.downloads = downloads
    }
}

extension ModrinthModpackIndex.Dependencies {
    /// 按"加载器类型 + 版本"构造依赖声明。
    ///
    /// 导出时只有加载器类型是可靠的（版本号常常反查不到），
    /// 所以这里允许 modLoaderVersion 为 nil，写空串会让 Modrinth 认为是
    /// 明确指定了版本，反而导入不了。
    public init(minecraft: String, modLoaderType: ModLoader?, modLoaderVersion: String?) {
        let version: String? = modLoaderVersion.flatMap { $0.isEmpty ? nil : $0 }
        self.minecraft = minecraft
        switch modLoaderType {
        case .forge:
            self.forge = version
            self.neoforge = nil
            self.fabricLoader = nil
            self.quiltLoader = nil
        case .neoforge:
            self.forge = nil
            self.neoforge = version
            self.fabricLoader = nil
            self.quiltLoader = nil
        case .fabric:
            self.forge = nil
            self.neoforge = nil
            self.fabricLoader = version
            self.quiltLoader = nil
        case nil:
            self.forge = nil
            self.neoforge = nil
            self.fabricLoader = nil
            self.quiltLoader = nil
        }
    }
}
