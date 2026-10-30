//
//  InstalledResourcesViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/6/7.
//

import Foundation
import Core
import Combine

@MainActor
class InstalledResourcesViewModel: ObservableObject {
    @Published public var resources: [ResourceDisplayModel]?
    @Published public var supportMods: Bool = true
    @Published public var currentRepositoryId: UUID
    @Published public var currentPage: Int = 0
    @Published public var pageCount: Int = 0

    /// 批量操作选中的资源。用文件名（url）做标识而不是 id：
    /// 启用/禁用会改变 url，但"哪些被选中"在操作前后应当保持。
    @Published public var selectedIds: Set<UUID> = []
    /// 有可用更新的资源。用 url 做标识：检测与展示读的是同一时刻的路径，
    /// 用 UUID 的话每次重建模型都会拿到新 id，筛选就永远对不上。
    @Published public private(set) var updatableURLs: Set<URL> = []
    /// 是否正在检测更新。
    @Published public private(set) var checkingUpdates: Bool = false
    /// 当前筛选条件。
    @Published public var filter: Filter = .all {
        didSet { updateResources() }
    }

    public let type: ResourceType
    public var hasSearchKeyword: Bool { !searchKeyword.isEmpty }
    private var cancellables: Set<AnyCancellable> = []
    private var loadResult: [(URL, Resource)]?
    private var convertTask: Task<Void, Never>?
    private var searchKeyword: String = ""
    private let instance: MinecraftInstance?
    private let id: String
    private let entriesPerPage: Int = 20

    private let service: ResourceLoadService

    init(instanceManager: InstanceManager, id: String, type: ResourceType) {
        self.instance = instanceManager.currentRepository.instance(named: id)
        self.id = id
        self.type = type
        self.currentRepositoryId = instanceManager.currentRepositoryId
        self.service = .init(
            preferredType: type,
            remoteLookupService: .init(curseforgeClient: Secrets.shared.curseforgeClient),
            cache: .shared
        )

        instanceManager.$currentRepositoryId
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentRepositoryId, on: self)
            .store(in: &cancellables)
    }

    // MARK: - 筛选

    enum Filter: String, CaseIterable, CustomStringConvertible {
        case all, enabled, disabled, updatable

        var description: String {
            switch self {
            case .all: "全部"
            case .enabled: "已启用"
            case .disabled: "已禁用"
            case .updatable: "可更新"
            }
        }
    }

    // MARK: - 加载

    func load(resetPage: Bool = true) async throws {
        guard let instance else { throw SimpleError("实例不存在。") }

        if type == .mod && instance.modLoader == nil {
            supportMods = false
            return
        }

        // 列表缓存：扫描 + 逐个算 SHA-1 是这一页最慢的部分，装了几百个 Mod 时尤其明显。
        // key 里带目录签名（mtime + 文件数），装/删/改文件会立刻失效，
        // 不会出现「刚装完 Mod 却要等缓存过期才看到」。
        let cacheKey: String = listCacheKey()
        var loaded: [(URL, Resource)]? = ResourceCacheCenter.shared.installedList(for: cacheKey)
        let hitCache: Bool = loaded != nil
        if loaded == nil {
            loaded = try await loadAllResources()
        }
        let result: [(URL, Resource)] = (loaded ?? [])
            .sorted { $0.1.name.compare($1.1.name, options: .literal) == .orderedAscending }
        if !hitCache {
            ResourceCacheCenter.shared.storeInstalled(result, for: cacheKey)
        }

        self.loadResult = result
        if resetPage {
            self.currentPage = 0
        }
        self.updateResources()
    }

    /// 收集该类型的所有资源文件。
    ///
    /// 数据包按存档分散在 saves/<存档>/datapacks/ 下，所以要多目录扫描；
    /// 其余类型只有一个固定目录。
    private func loadAllResources() async throws -> [(URL, Resource)] {
        var result: [(URL, Resource)] = []
        if type == .datapack {
            for save in saveNames() {
                let directory: URL = instance!.url.appending(path: "saves/\(save)/datapacks")
                guard FileManager.default.fileExists(atPath: directory.path) else { continue }
                let resources: [URL: Resource] = try await service.loadResources(in: directory)
                result.append(contentsOf: resources.map { ($0.key, $0.value) })
            }
            return result
        }
        guard let directory = directory() else { throw SimpleError("实例不存在。") }
        let resources: [URL: Resource] = try await service.loadResources(in: directory)
        return resources.map { ($0.key, $0.value) }
    }

    /// 已安装列表缓存的 key。
    private func listCacheKey() -> String {
        "installed|\(id)|\(type.rawValue)|\(directorySignature())"
    }

    /// 目录签名：路径 + 修改时间 + 文件数。
    ///
    /// 只按时间过期不够——刚装完一个 Mod 也得等 10 分钟才显示就太蠢了。
    /// 目录的 mtime 在增删文件时会变，文件数则兜住「同秒内替换同名文件」。
    private func directorySignature() -> String {
        guard let instance else { return "missing" }
        let directories: [URL]
        if type == .datapack {
            directories = saveNames().map { instance.url.appending(path: "saves/\($0)/datapacks") }
        } else {
            directories = [directory()].compactMap { $0 }
        }
        return directories.map { url in
            let modification: TimeInterval = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970 ?? 0
            let count: Int = (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
            return "\(url.path)#\(Int(modification))#\(count)"
        }
        .joined(separator: ";")
    }

    /// 实例里所有存档的名字。
    private func saveNames() -> [String] {
        guard let instance else { return [] }
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

    func updateResources() {
        if let convertTask {
            convertTask.cancel()
            self.convertTask = nil
        }
        guard let loadResult else { return }

        let validResources: [(URL, Resource)] = loadResult.filter { [unowned self] entry in
            let url: URL = entry.0
            let resource: Resource = entry.1
            let matchesKeyword: Bool = searchKeyword.isEmpty
                || resource.name.localizedCaseInsensitiveContains(searchKeyword)
                || (resource.description?.localizedCaseInsensitiveContains(searchKeyword) ?? false)
                || resource.tags.contains { $0.localizedCaseInsensitiveContains(searchKeyword) }
            guard matchesKeyword else { return false }
            switch filter {
            case .all: return true
            case .enabled: return url.pathExtension != "disabled"
            case .disabled: return url.pathExtension == "disabled"
            case .updatable: return updatableURLs.contains(url)
            }
        }

        applyFiltered(validResources)
    }

    /// 把过滤后的结果分页并转成展示模型。
    private func applyFiltered(_ validResources: [(URL, Resource)]) {
        self.pageCount = validResources.isEmpty ? 0 : Int(ceil(Double(validResources.count) / Double(entriesPerPage)))
        if pageCount == 0 {
            self.resources = []
            return
        } else {
            currentPage = min(pageCount - 1, currentPage)
        }

        let start = currentPage * entriesPerPage
        let end = min(start + entriesPerPage, validResources.count)
        self.resources = nil
        convertTask = .detached {
            do {
                let resources = try validResources[start..<end]
                    .map {
                        try Task.checkCancellation()
                        return ResourceDisplayModel($0.0, $0.1)
                    }
                await MainActor.run {
                    self.resources = resources
                }
            } catch let error where error.isCancellationError {
            } catch {
                err("刷新资源列表失败：\(error.localizedDescription)")
            }
            await MainActor.run {
                self.convertTask = nil
            }
        }
    }

    func setSearchKeyword(_ keyword: String) {
        searchKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        updateResources()
    }

    // MARK: - 选中

    func toggleSelection(_ resource: ResourceDisplayModel) {
        if selectedIds.contains(resource.id) {
            selectedIds.remove(resource.id)
        } else {
            selectedIds.insert(resource.id)
        }
    }

    func selectAll() {
        selectedIds = Set((resources ?? []).map(\.id))
    }

    func clearSelection() {
        selectedIds.removeAll()
    }

    var selectedResources: [ResourceDisplayModel] {
        (resources ?? []).filter { selectedIds.contains($0.id) }
    }

    // MARK: - 启用 / 禁用

    func toggleDisabled(_ resource: ResourceDisplayModel) throws {
        let newURL: URL
        if resource.disabled {
            newURL = resource.url.deletingPathExtension()
            log("正在启用资源 \(resource.fileName)")
        } else {
            newURL = resource.url.appendingPathExtension("disabled")
            log("正在禁用资源 \(resource.fileName)")
        }
        try FileManager.default.moveItem(at: resource.url, to: newURL)
        resource.disabled.toggle()
        resource.url = newURL
    }

    /// 批量启用或禁用。
    /// - Returns: 成功处理的条目数。
    func setEnabled(_ enabled: Bool, for resources: [ResourceDisplayModel]) -> Int {
        var succeeded: Int = 0
        for resource in resources where resource.disabled == enabled {
            do {
                try toggleDisabled(resource)
                succeeded += 1
            } catch {
                err("切换 \(resource.fileName) 状态失败：\(error.localizedDescription)")
            }
        }
        return succeeded
    }

    // MARK: - 删除

    /// 删除资源文件。只删文件本身，不碰缓存里的记录——
    /// 缓存按内容哈希索引，文件删了自然不再命中。
    func delete(_ resources: [ResourceDisplayModel]) -> Int {
        var succeeded: Int = 0
        for resource in resources {
            do {
                try FileManager.default.removeItem(at: resource.url)
                log("已删除资源 \(resource.fileName)")
                succeeded += 1
            } catch {
                err("删除 \(resource.fileName) 失败：\(error.localizedDescription)")
            }
        }
        selectedIds.subtract(resources.map(\.id))
        return succeeded
    }

    // MARK: - 更新检测

    /// 检测可更新的资源。
    ///
    /// 只查 Modrinth：本地文件的 SHA-1 能直接反查出版本，
    /// 而 CurseForge 没有"按哈希查文件"的公开接口。
    func checkUpdates() async {
        guard let resources, !resources.isEmpty else { return }
        checkingUpdates = true
        defer { checkingUpdates = false }

        var hashes: [String: ResourceDisplayModel] = [:]
        for resource in resources {
            guard let hash = try? FileUtils.sha1(of: resource.url) else { continue }
            hashes[hash] = resource
        }
        guard !hashes.isEmpty else { return }

        do {
            let versions: [String: ModrinthVersion] = try await ModrinthAPIClient.shared.versions(ofHashes: Array(hashes.keys))
            var updatable: Set<URL> = []
            for (hash, version) in versions {
                guard let resource = hashes[hash] else { continue }
                // 版本号字符串不同即提示更新：本地版本来自 jar 元数据，
                // 与远端 versionNumber 的格式未必一致，做语义化比较只会误判。
                if let localVersion = resource.version, localVersion != version.versionNumber {
                    updatable.insert(resource.url)
                }
            }
            updatableURLs = updatable
            if filter == .updatable { updateResources() }
            log("更新检测完成，\(updatable.count) 个资源可更新")
            hint(updatable.isEmpty ? "所有资源都是最新的！" : "发现 \(updatable.count) 个可更新的资源！", type: .finish)
        } catch {
            err("检测资源更新失败：\(error.localizedDescription)")
            hint("检测更新失败：\(error.localizedDescription)", type: .critical)
        }
    }

    // MARK: - 从文件安装

    func install(from url: URL, saveName: String? = nil) throws {
        guard let instance else { throw SimpleError("实例不存在。") }
        let directoryName: String
        if type == .datapack {
            guard let saveName, !saveName.isEmpty else {
                throw SimpleError("安装数据包前必须先选择一个存档。")
            }
            directoryName = "saves/\(saveName)/datapacks"
        } else {
            guard let name = type.saveDirectory else {
                throw SimpleError("这类资源不能直接安装到实例目录。")
            }
            directoryName = name
        }
        let destination: URL = instance.url.appending(path: "\(directoryName)/\(url.lastPathComponent)")
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            throw SimpleError("目标目录里已经有同名文件了。")
        }
        try FileManager.default.copyItem(at: url, to: destination)
        log("已从文件安装 \(url.lastPathComponent)")
    }

    // MARK: - 远端信息

    func loadInfo(for resource: ResourceDisplayModel) async throws -> ProjectListItemModel? {
        for source in resource.sources {
            if case .modrinth(let projectId) = source {
                do {
                    guard let project = try await ModrinthAPIClient.shared.project(projectId) else {
                        warn("记录了 \(resource.fileName) 对应的 Modrinth projectId（\(projectId)），但它在 Modrinth 上已不存在")
                        return nil
                    }
                    return .init(project)
                } catch {
                    throw SimpleError("查询 Modrinth Project 失败：\(error.localizedDescription)")
                }
            }
        }
        return nil
    }

    func directory() -> URL? {
        guard let instance else { return nil }
        // 数据包没有统一的目录可开，返回 saves/ 让用户自己进存档。
        let directoryName: String = type == .datapack ? "saves" : (type.saveDirectory ?? "")
        let url: URL = instance.url.appending(path: directoryName)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 数据包安装时可选的存档列表。
    var availableSaves: [String] { saveNames() }
}
