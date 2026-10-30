//
//  ResourceInstallViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/19.
//

import Foundation
import Core
import ZIPFoundation

class ResourceInstallViewModel: ObservableObject {
    public typealias VersionGroup = (VersionMapKey, [ProjectVersionModel])
    public typealias VersionList = [VersionGroup]
    
    @Published public var versionList: VersionList?
    @Published public var selectedVersionGroup: VersionGroup?
    @Published public var loaded: Bool = false
    
    public let project: ProjectListItemModel
    public let loadingVM: MyLoadingViewModel = .init(text: "加载中")
    
    public init(project: ProjectListItemModel) {
        self.project = project
    }
    
    public func load(selectedInstance: MinecraftInstance? = nil) async throws {
        let selectedInstanceKey: VersionMapKey? = project.type == .modpack ? nil : selectedInstance.map { .init(loader: $0.modLoader, version: $0.version) }
        let selectedVersionType: MinecraftVersion.VersionType? = (selectedInstance?.version).flatMap { VersionManifest.shared?.version(for: $0.id) }?.type
        var selectedVersionGroup: VersionGroup? = selectedInstanceKey.map { ($0, []) }
        
        if let selected = selectedVersionGroup, project.type != .mod {
            selectedVersionGroup?.0 = .init(loader: nil, version: selected.0.version)
        }
        
        var versionMap: [VersionMapKey: [ProjectVersionModel]] = [:]
        switch project.source {
        case .modrinth:
            try await collectModrinthVersions(
                selectedVersionType: selectedVersionType,
                selectedInstanceKey: selectedInstanceKey,
                versionMap: &versionMap,
                selectedVersionGroup: &selectedVersionGroup
            )
        case .curseforge(let modId):
            try await collectCurseForgeVersions(
                modId: modId,
                selectedVersionType: selectedVersionType,
                selectedInstanceKey: selectedInstanceKey,
                versionMap: &versionMap,
                selectedVersionGroup: &selectedVersionGroup
            )
        }
        
        let versionList: VersionList = versionMap.map { ($0, $1) }.sorted(by: { $0.0 > $1.0 })
        let finalSelectedGroup: VersionGroup? = selectedVersionGroup?.1.isEmpty == true ? nil : selectedVersionGroup
        await MainActor.run {
            self.versionList = versionList
            self.selectedVersionGroup = finalSelectedGroup
            self.loaded = true
        }
    }
    
    /// Modrinth 的版本列表。
    private func collectModrinthVersions(
        selectedVersionType: MinecraftVersion.VersionType?,
        selectedInstanceKey: VersionMapKey?,
        versionMap: inout [VersionMapKey: [ProjectVersionModel]],
        selectedVersionGroup: inout VersionGroup?
    ) async throws {
        guard case .modrinth(let projectId) = project.source else { return }
        let versions: [ModrinthVersion] = try await ModrinthAPIClient.shared.versions(ofProject: projectId, revalidate: true)
        
        for version in versions {
            var dependencies: [ProjectVersionModel.Dependency] = []
            for dependency in version.dependencies {
                guard let dependencyProjectId: String = dependency.projectId,
                      dependency.isRequired else {
                    continue
                }
                if let dependencyProject = try await ModrinthAPIClient.shared.project(dependencyProjectId) {
                    dependencies.append(.init(versionId: dependency.id, projectId: dependencyProjectId, project: .init(dependencyProject)))
                } else {
                    warn("依赖 \(dependencyProjectId) 在 Modrinth 上已不存在")
                    debug(version)
                }
            }
            
            var keys: [VersionMapKey] = []
            for gameVersion in version.gameVersions {
                if let type = VersionManifest.shared?.version(for: gameVersion)?.type,
                   !(type == .release || project.onlySupportsSnapshot || selectedVersionType.map { $0 != .release } ?? false) {
                    continue
                }
                if version.loaders.isEmpty && project.type != .mod {
                    keys.append(.init(loader: nil, version: .init(gameVersion)))
                    continue
                }
                for loader in version.loaders {
                    keys.append(.init(loader: loader, version: .init(gameVersion)))
                }
            }
            let file: ModrinthVersion.File? = version.files.filter(\.primary).first ?? version.files.first
            for key in keys {
                let value: ProjectVersionModel = .init(
                    id: version.id,
                    name: version.name,
                    version: version.versionNumber,
                    downloads: ProjectListItemModel.formatDownloads(version.downloads),
                    datePublished: ProjectListItemModel.formatLastUpdate(version.datePublished),
                    requiredDependencies: dependencies,
                    type: version.type,
                    primaryFile: file.map { .init(name: $0.name, url: $0.url, sha1: $0.sha1) },
                    gameVersion: key.version.id,
                    loader: key.loader
                )
                
                if let selectedInstanceKey, selectedInstanceKey.compatible(with: key) {
                    selectedVersionGroup?.1.append(value)
                } else {
                    versionMap[key, default: []].append(value)
                }
            }
        }
    }
    
    /// CurseForge 的版本列表。
    ///
    /// 与 Modrinth 的差别：文件自带游戏版本与加载器，不用再查一遍；
    /// 但依赖要按 modId 逐个查，**有配额**，所以只给「当前实例能装」的版本查，
    /// 且一次最多查 `dependencyBudget` 个，避免打开页面就打几十个请求。
    private func collectCurseForgeVersions(
        modId: Int,
        selectedVersionType: MinecraftVersion.VersionType?,
        selectedInstanceKey: VersionMapKey?,
        versionMap: inout [VersionMapKey: [ProjectVersionModel]],
        selectedVersionGroup: inout VersionGroup?
    ) async throws {
        guard let client: CurseForgeAPIClient = Secrets.shared.curseforgeClient else {
            throw SimpleError("没有可用的 CurseForge API Key，无法获取该项目的版本列表。")
        }
        let result: CurseForgeAPIClient.PagedResult<CurseForgeModFile> = try await client.files(modId: modId, pageSize: 50)
        var dependencyBudget: Int = 8
        
        for file in result.data {
            guard file.available else { continue }
            
            var keys: [VersionMapKey] = []
            for gameVersion in file.gameVersions {
                if let type = VersionManifest.shared?.version(for: gameVersion)?.type,
                   !(type == .release || project.onlySupportsSnapshot || selectedVersionType.map { $0 != .release } ?? false) {
                    continue
                }
                if project.type == .mod, let loader = file.modLoader.flatMap(ModLoader.init(curseforgeType:)) {
                    keys.append(.init(loader: loader, version: .init(gameVersion)))
                } else {
                    keys.append(.init(loader: nil, version: .init(gameVersion)))
                }
            }
            guard !keys.isEmpty else { continue }
            
            let matchesInstance: Bool = selectedInstanceKey.map { instanceKey in
                keys.contains { $0.compatible(with: instanceKey) }
            } ?? false
            var dependencies: [ProjectVersionModel.Dependency] = []
            if matchesInstance {
                for dependency in (file.dependencies ?? []) where dependency.relationType == 3 {
                    guard dependencyBudget > 0 else { break }
                    dependencyBudget -= 1
                    if let mod = try? await client.mod(id: Int(dependency.modId)) {
                        dependencies.append(.init(
                            versionId: nil,
                            projectId: "curseforge-\(mod.id)",
                            project: .init(mod, type: project.type)
                        ))
                    }
                }
            }
            
            let published: String = ProjectListItemModel.parseDate(file.fileDate)
                .map(ProjectListItemModel.formatLastUpdate) ?? ""
            for key in keys {
                let value: ProjectVersionModel = .init(
                    id: "curseforge-\(file.id)",
                    name: file.displayName ?? file.fileName,
                    version: file.displayName ?? file.fileName,
                    downloads: "",
                    datePublished: published,
                    requiredDependencies: dependencies,
                    type: Self.versionType(curseforgeReleaseType: file.releaseType),
                    primaryFile: .init(name: file.fileName, url: file.downloadURL, sha1: file.checksums["sha1"]),
                    gameVersion: key.version.id,
                    loader: key.loader
                )
                
                if let selectedInstanceKey, selectedInstanceKey.compatible(with: key) {
                    selectedVersionGroup?.1.append(value)
                } else {
                    versionMap[key, default: []].append(value)
                }
            }
        }
    }
    
    /// CurseForge 的 releaseType：1 正式、2 测试、3 早期。
    private static func versionType(curseforgeReleaseType: Int?) -> ModrinthVersion.VersionType {
        switch curseforgeReleaseType {
        case 2: .beta
        case 3: .alpha
        default: .release
        }
    }
    
    /// 检查实例是否可以安装某个版本。
    /// - Parameters:
    ///   - instance: 当前实例。
    ///   - version: 选择的版本。
    /// - Throws: 如果不能安装，抛出 `InstanceCheckError`。
    public func checkInstance(_ instance: MinecraftInstance, withVersion version: ProjectVersionModel) throws {
        if project.type == .mod, let requiredLoader: ModLoader = version.loader {
            guard let loader: ModLoader = instance.modLoader else {
                throw InstanceCheckError.modLoaderMissing(name: requiredLoader)
            }
            if loader != requiredLoader {
                throw InstanceCheckError.modLoaderMismatch(required: requiredLoader, found: loader)
            }
        }
        if version.gameVersion != instance.version.id {
            throw InstanceCheckError.versionUnsupported(supported: version.gameVersion, found: instance.version.id)
        }
    }
    
    /// 列出实例里已有的存档名。
    ///
    /// 数据包的作用域是单个存档（saves/<存档>/datapacks/），所以安装前必须先选存档。
    public static func saves(of instance: MinecraftInstance) -> [String] {
        let savesURL: URL = instance.url.appending(path: "saves")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: savesURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted()
    }

    public func createInstallTask(
        forVersion version: ProjectVersionModel,
        to instance: MinecraftInstance,
        saveName: String? = nil
    ) async throws -> MyTask<EmptyModel> {
        guard let primaryFile = version.primaryFile else {
            throw SimpleError("这个版本中没有主要文件！")
        }

        let saveDirectoryURL: URL
        if project.type == .datapack {
            guard let saveName, !saveName.isEmpty else {
                throw SimpleError("安装数据包前必须先选择一个存档。")
            }
            saveDirectoryURL = instance.url.appending(path: "saves/\(saveName)/datapacks")
        } else {
            let saveDirectoryName = project.type.saveDirectory ?? ""
            saveDirectoryURL = instance.url.appending(path: saveDirectoryName)
        }
        
        // 落盘文件名走「文件名格式」（设置 → 其他 → 社区资源）。
        // 规则集中在 Core 的 ResourceFileName，这里只负责把项目信息喂进去；
        // 没有译名时直接沿用源站的原始文件名，绝不产生空文件名。
        let fileName: String = ResourceFileName.format(
            format: LauncherConfig.shared.resourceFileNameFormat,
            name: project.fileNameTitle,
            originalName: primaryFile.name,
            type: project.type
        )
        let destination: URL = saveDirectoryURL.appending(path: fileName)

        return .init(
            name: "资源下载 - \(project.title) \(version.version)",
            .init(0, "下载文件") { task, model in
                try await FileDownloader.shared.download(
                    url: primaryFile.url,
                    destination: destination,
                    sha1: primaryFile.sha1,
                    progressHandler: task.setProgress(_:)
                )
            }
        )
    }
    
    public struct VersionMapKey: Hashable, Equatable, Comparable, Identifiable, CustomStringConvertible {
        public let id: UUID = .init()
        public let loader: ModLoader?
        public let version: MinecraftVersion
        
        public func compatible(with another: VersionMapKey) -> Bool {
            if another.loader != nil {
                return self.loader == another.loader && self.version == another.version
            }
            return self.version == another.version
        }
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.version != rhs.version {
                return lhs.version < rhs.version
            } else {
                return (lhs.loader?.index ?? 0) < (rhs.loader?.index ?? 0)
            }
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(loader)
            hasher.combine(version)
        }
        
        public static func == (lhs: Self, rhs: Self) -> Bool {
            return lhs.loader == rhs.loader && lhs.version == rhs.version
        }
        
        public var description: String {
            if let loader {
                return "\(loader) \(version)"
            }
            return version.description
        }
    }
    
    public enum InstanceCheckError: LocalizedError {
        case modLoaderMissing(name: ModLoader)
        case modLoaderMismatch(required: ModLoader, found: ModLoader)
        case versionUnsupported(supported: String, found: String)
        
        public var errorDescription: String? {
            switch self {
            case .modLoaderMissing(let needed):
                "这个版本需要 \(needed) 加载器，但当前选择的实例没有安装！"
            case .modLoaderMismatch(let needed, let found):
                "这个版本需要 \(needed) 加载器，但当前选择的实例安装的是 \(found)！"
            case .versionUnsupported(let supported, let found):
                "这个版本只支持 Minecraft \(supported)，但当前选择的实例版本是 \(found)！"
            }
        }
    }
}


// MARK: - 整合包相关
extension ResourceInstallViewModel {
    public func createModpackDownloadTask(_ version: ProjectVersionModel) throws -> (MyTask<EmptyModel>, URL) {
        guard let primaryFile = version.primaryFile else {
            throw SimpleError("这个版本中没有主要文件！")
        }
        
        let destination: URL = URLConstants.tempURL.appending(path: "modpack-download-\(version.id)")
        let task: MyTask<EmptyModel> = .init(
            name: "下载整合包 - \(project.title) \(version.version)",
            .init(0, "下载文件") { task, _ in
                try await FileDownloader.shared.download(
                    url: primaryFile.url,
                    destination: destination,
                    sha1: primaryFile.sha1,
                    progressHandler: task.setProgress(_:)
                )
            }
        )
        return (task, destination)
    }
    
    public func loadIndex(_ url: URL) throws -> ModrinthModpackIndex {
        do {
            let archive: Archive = try .init(url: url, accessMode: .read)
            guard let entry: Entry = archive["modrinth.index.json"] else {
                throw SimpleError("未找到整合包索引文件。")
            }
            var data: Data = .init()
            _ = try archive.extract(entry, consumer: { data += $0 })
            let index: ModrinthModpackIndex = try JSONDecoder.shared.decode(ModrinthModpackIndex.self, from: data)
            return index
        } catch let error as Archive.ArchiveError where error == .unreadableArchive {
            throw ModpackInstallError.invalidModpackFormat(underlying: SimpleError("压缩文件格式错误。"))
        } catch {
            throw ModpackInstallError.invalidModpackFormat(underlying: error)
        }
    }
    
    public enum ModpackInstallError: LocalizedError {
        case invalidModpackFormat(underlying: Error)
        
        public var errorDescription: String? {
            switch self {
            case .invalidModpackFormat(let underlying):
                "整合包格式错误：\(underlying.localizedDescription)"
            }
        }
    }
}
