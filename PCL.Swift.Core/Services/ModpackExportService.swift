//
//  ModpackExportService.swift
//  PCL.Swift.Core
//
//  把已安装的实例导出为 Modrinth 格式（.mrpack）。
//
//  设计取舍：
//  - 只导出 Modrinth 上能按哈希认出来的文件，认不出的放进 overrides/
//    （这与原版 PCL 的「仅从 Modrinth 下载资源文件」选项对应）。
//  - 不导出存档、日志、截图：整合包是"可复现的实例配置"，不是备份。
//  - 索引里的 files 只写 path + hashes + downloads，env 留空由 Modrinth 推断。
//

import Foundation
import ZIPFoundation

public class ModpackExportService {
    /// 整合包导出配置。
    public struct Options {
        /// 整合包名称。
        public var name: String
        /// 整合包版本号。
        public var version: String
        /// 是否把认不出哈希的文件打进 overrides。关掉时这些文件会被丢弃。
        public var includeUnrecognizedFiles: Bool
        /// 是否包含启动器自身的配置（.clconfig.json 等）。
        public var includeLauncherConfig: Bool

        public init(
            name: String,
            version: String = "1.0.0",
            includeUnrecognizedFiles: Bool = true,
            includeLauncherConfig: Bool = false
        ) {
            self.name = name
            self.version = version
            self.includeUnrecognizedFiles = includeUnrecognizedFiles
            self.includeLauncherConfig = includeLauncherConfig
        }
    }

    private let instance: MinecraftInstance
    private let modrinthClient: ModrinthAPIClient

    /// 会被扫进整合包的资源目录。
    private static let resourceDirectories: [String] = ["mods", "resourcepacks", "shaderpacks"]
    /// 会被整体放进 overrides 的目录（配置文件与本地资源）。
    private static let overrideDirectories: [String] = ["config", "defaultconfigs", "kubejs", "scripts"]
    /// 绝不导出的目录。
    private static let excludedDirectories: Set<String> = [
        "saves", "logs", "crash-reports", "screenshots", "natives", "versions", "libraries", "assets", ".git"
    ]

    public init(instance: MinecraftInstance, modrinthClient: ModrinthAPIClient = .shared) {
        self.instance = instance
        self.modrinthClient = modrinthClient
    }

    /// 导出整合包。
    /// - Parameters:
    ///   - options: 导出配置。
    ///   - destination: 目标 .mrpack 路径。
    ///   - progressHandler: 进度回调（0…1）。
    public func export(
        options: Options,
        to destination: URL,
        progressHandler: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        let fileManager: FileManager = .default
        let staging: URL = URLConstants.tempURL.appending(path: "modpack-export-\(UUID().uuidString.lowercased())")
        defer { try? fileManager.removeItem(at: staging) }

        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        await progressHandler?(0.02)

        let index: ModrinthModpackIndex = try await buildIndex(
            options: options,
            staging: staging,
            progressHandler: progressHandler
        )
        await progressHandler?(0.6)

        let encoder: JSONEncoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let indexData: Data = try encoder.encode(index)
        try indexData.write(to: staging.appending(path: "modrinth.index.json"))
        await progressHandler?(0.65)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.zipItem(at: staging, to: destination, shouldKeepParent: false)
        await progressHandler?(1)
        log("整合包导出完成：\(destination.path)")
    }

    // MARK: - 索引

    private func buildIndex(
        options: Options,
        staging: URL,
        progressHandler: (@MainActor (Double) -> Void)?
    ) async throws -> ModrinthModpackIndex {
        let fileManager: FileManager = .default
        let overrides: URL = staging.appending(path: "overrides")
        try fileManager.createDirectory(at: overrides, withIntermediateDirectories: true)

        // 1. 收集资源文件并批量查 Modrinth。
        var candidates: [(url: URL, relativePath: String, sha1: String)] = []
        for directory in Self.resourceDirectories {
            let root: URL = instance.url.appending(path: directory)
            guard fileManager.fileExists(atPath: root.path) else { continue }
            let files: [URL] = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey])) ?? []
            for file in files where !file.lastPathComponent.hasPrefix(".") {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                guard let sha1 = try? FileUtils.sha1(of: file) else { continue }
                candidates.append((file, "\(directory)/\(file.lastPathComponent)", sha1))
            }
        }
        await progressHandler?(0.15)

        let hashes: [String] = candidates.map(\.sha1)
        var lookup: [String: ModrinthVersion] = [:]
        if !hashes.isEmpty {
            do {
                lookup = try await modrinthClient.versions(ofHashes: hashes)
            } catch {
                // 查不到就全部当作本地文件放进 overrides：导出仍然可用，
                // 只是包会变大。不要因为网络问题让整个导出失败。
                warn("查询 Modrinth 版本信息失败，将全部文件放入 overrides：\(error.localizedDescription)")
            }
        }
        await progressHandler?(0.3)

        // 2. 分流：认得出的写进 files，认不出的复制进 overrides。
        var entries: [ModrinthModpackIndex.File] = []
        var unrecognizedCount: Int = 0
        for (index, candidate) in candidates.enumerated() {
            if let version = lookup[candidate.sha1],
               let file = version.files.first(where: { $0.sha1 == candidate.sha1 }) ?? version.files.first {
                entries.append(.init(
                    path: candidate.relativePath,
                    hashes: ["sha1": candidate.sha1, "sha512": ""].filter { !$0.value.isEmpty },
                    downloads: [file.url]
                ))
            } else if options.includeUnrecognizedFiles {
                unrecognizedCount += 1
                let destination: URL = overrides.appending(path: candidate.relativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: candidate.url, to: destination)
            }
            if index % 8 == 0 {
                await progressHandler?(0.3 + 0.25 * (Double(index) / Double(max(candidates.count, 1))))
            }
        }

        // 3. 配置文件整体拷进 overrides。
        for directory in Self.overrideDirectories {
            let source: URL = instance.url.appending(path: directory)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination: URL = overrides.appending(path: directory)
            try? fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.copyItem(at: source, to: destination)
        }
        if options.includeLauncherConfig {
            for name in [".clconfig.json", ".clmetadata.json"] {
                let source: URL = instance.url.appending(path: name)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.copyItem(at: source, to: overrides.appending(path: name))
                }
            }
        }
        await progressHandler?(0.55)

        // 4. 组装索引。加载器版本从实例清单里反查不到可靠值，
        //    所以这里只声明"哪种加载器"，版本留空由导入方决定。
        let dependencies: ModrinthModpackIndex.Dependencies = .init(
            minecraft: instance.version.id,
            modLoaderType: instance.modLoader,
            modLoaderVersion: Self.detectedLoaderVersion(instance: instance)
        )

        log("整合包索引：\(entries.count) 个远端文件，\(unrecognizedCount) 个本地文件")

        return ModrinthModpackIndex(
            formatVersion: 1,
            name: options.name,
            summary: instance.customDescription ?? "由 PCL.Swift 导出的整合包",
            game: "minecraft",
            versionId: options.version,
            files: entries,
            dependencies: dependencies
        )
    }

    /// 从实例清单里找加载器版本号。
    ///
    /// 清单的 id 形如 `1.20.1-forge-47.2.0`，从中取最后一段；
    /// 取不到就返回 nil，导入方会退化为"让用户选版本"。
    private static func detectedLoaderVersion(instance: MinecraftInstance) -> String? {
        guard instance.modLoader != nil else { return nil }
        let id: String = instance.manifest.id
        let parts: [String] = id.split(separator: "-").map(String.init)
        guard parts.count >= 3 else { return nil }
        return parts.last
    }
}
