//
//  ResourcesSearchViewModel.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/16.
//

import Foundation
import Core

/// 搜索来源。与原版 PageResource 的「来源」下拉一致。
enum ResourceSource: String, CaseIterable, CustomStringConvertible {
    case all, modrinth, curseforge

    var description: String {
        switch self {
        case .all: "全部"
        case .modrinth: "Modrinth"
        case .curseforge: "CurseForge"
        }
    }
}

class ResourcesSearchViewModel: ObservableObject {
    @Published public var searchResults: [ProjectListItemModel]?
    @Published public var query: String = ""
    /// 筛选条件。与原版一致：改完点「搜索」才生效，翻页沿用同一套条件。
    @Published public var filterVersion: String?
    @Published public var filterLoader: ModLoader?
    @Published public var filterCategory: String?
    /// 搜索来源。
    @Published public var source: ResourceSource = .all
    /// 当前类型可用的类别标签（Modrinth 的 slug），界面上显示成中文。
    @Published public private(set) var categories: [String] = []
    /// 本次搜索里 CurseForge 是不是被跳过了（请求失败），页面据此给个提示。
    @Published public private(set) var curseforgeSkipped: Bool = false
    /// 当前构建有没有内置 CurseForge API Key。没有时「来源」里不出现 CurseForge，
    /// 「全部」也只用 Modrinth——不然每次搜索都会弹一条「被跳过」的提示。
    public var curseforgeAvailable: Bool { Secrets.shared.curseforgeClient != nil }
    /// 总页数。合并搜索时取两个来源里较大的那个。
    @Published public private(set) var totalPages: Int = 0
    public let type: ResourceType
    public let loadingVM: MyLoadingViewModel = .init(text: "加载中")
    /// CurseForge 的分类（slug → id），只在需要按类型筛 CurseForge 时才拉。
    private var curseforgeCategories: [CurseForgeCategory]?
    
    public init(type: ResourceType) {
        self.type = type
    }
    
    /// 搜索一页结果。
    /// - Parameter forceRefresh: 跳过缓存重新请求（侧边栏的「刷新」用）。
    public func search(_ query: String, pageIndex: Int = 0, forceRefresh: Bool = false) async throws {
        let version: String? = filterVersion
        let loader: ModLoader? = filterLoader
        let category: String? = filterCategory
        let source: ResourceSource = self.source

        // 缓存键覆盖所有影响结果的参数，少一个都会串数据。
        let cacheKey: String = [
            type.rawValue, source.rawValue, query,
            version ?? "-", loader?.rawValue ?? "-", category ?? "-",
            String(pageIndex)
        ].joined(separator: "|")
        if !forceRefresh, let cached = await ResourceCacheCenter.shared.page(for: cacheKey) {
            await MainActor.run {
                self.query = query
                self.totalPages = cached.totalPages
                self.curseforgeSkipped = cached.curseforgeSkipped
                self.searchResults = cached.results
            }
            return
        }

        await MainActor.run {
            self.query = query
            loadingVM.reset()
            searchResults = nil
            curseforgeSkipped = false
        }
        
        var results: [ProjectListItemModel] = []
        var pages: Int = 0
        var curseforgeSkipped: Bool = false
        
        switch source {
        case .modrinth:
            let page = try await modrinthPage(query, version: version, loader: loader, category: category, pageIndex: pageIndex)
            results = page.results
            pages = page.pages
        case .curseforge:
            guard Secrets.shared.curseforgeClient != nil else {
                throw SimpleError("当前构建没有内置 CurseForge API Key，无法搜索 CurseForge。")
            }
            let page = try await curseforgePage(query, version: version, loader: loader, category: category, pageIndex: pageIndex)
            results = page.results
            pages = page.pages
        case .all:
            // 两边并发。CurseForge 请求失败时只用 Modrinth，
            // 与原版「一边挂了就只显示另一边」的降级思路一致。
            async let modrinthTask = modrinthPage(query, version: version, loader: loader, category: category, pageIndex: pageIndex)
            let curseforge: Page? = curseforgeAvailable
                ? try? await curseforgePage(query, version: version, loader: loader, category: category, pageIndex: pageIndex)
                : nil
            let modrinth = try await modrinthTask
            curseforgeSkipped = curseforgeAvailable && curseforge == nil
            results = modrinth.results + (curseforge?.results ?? [])
            pages = max(modrinth.pages, curseforge?.pages ?? 0)
        }
        
        await ResourceCacheCenter.shared.store(
            .init(results: results, totalPages: pages, curseforgeSkipped: curseforgeSkipped),
            for: cacheKey
        )
        await MainActor.run {
            self.totalPages = pages
            self.curseforgeSkipped = curseforgeSkipped
            self.searchResults = results
        }
    }
    
    public func changePage(_ page: Int) async throws {
        try await search(query, pageIndex: page)
    }
    
    /// 拉取该类型的类别标签。失败只记日志：筛选项空着不影响搜索本身。
    public func loadCategories() async {
        guard categories.isEmpty else { return }
        do {
            let all: [ModrinthAPIClient.Category] = try await ModrinthAPIClient.shared.categories()
            let names: [String] = all.filter { $0.projectType == type.rawValue }.map(\.name)
            await MainActor.run {
                self.categories = names
            }
        } catch let error where error.isCancellationError {
            // 页面在请求完成前就被切走了，属于正常情况，不值得报 warn。
            debug("获取\(type.localizedName)类别已取消")
        } catch {
            warn("获取\(type.localizedName)类别失败：\(error.localizedDescription)")
        }
    }
    
    /// 清空筛选条件（搜索关键词由页面自己管）。
    @MainActor
    public func resetFilters() {
        filterVersion = nil
        filterLoader = nil
        filterCategory = nil
    }
    
    // MARK: - 单个来源的查询
    
    private struct Page {
        let results: [ProjectListItemModel]
        let pages: Int
    }
    
    private func modrinthPage(
        _ query: String,
        version: String?,
        loader: ModLoader?,
        category: String?,
        pageIndex: Int
    ) async throws -> Page {
        let limit: Int = 40
        let response: ModrinthAPIClient.SearchResponse = try await ModrinthAPIClient.shared.search(
            type: type,
            query,
            forVersion: version,
            loader: loader,
            category: category,
            pageIndex: pageIndex,
            limit: limit
        )
        let results: [ProjectListItemModel] = response.hits
            .filter { $0.clientCompatibility != .unsupported }
            .map(ProjectListItemModel.init(_:))
        return .init(results: results, pages: Int(ceil(Double(response.totalHits) / Double(response.limit))))
    }
    
    private func curseforgePage(
        _ query: String,
        version: String?,
        loader: ModLoader?,
        category: String?,
        pageIndex: Int
    ) async throws -> Page {
        guard let client: CurseForgeAPIClient = Secrets.shared.curseforgeClient else {
            throw SimpleError("当前构建没有内置 CurseForge API Key。")
        }
        let pageSize: Int = 40
        let classId: Int = CurseForgeMod.classId(for: type)
        let result: CurseForgeAPIClient.PagedResult<CurseForgeMod> = try await client.search(
            classId: classId,
            query: query,
            gameVersion: version,
            loader: type == .mod ? loader : nil,
            categoryId: await curseforgeCategoryId(for: category),
            index: pageIndex * pageSize,
            pageSize: pageSize
        )
        let results: [ProjectListItemModel] = result.data.map { .init($0, type: type) }
        let pages: Int = Int(ceil(Double(result.pagination.totalCount) / Double(pageSize)))
        return .init(results: results, pages: pages)
    }
    
    /// Modrinth 的类别是 slug，CurseForge 的是数字 id。
    /// 两边的 slug 大体一致（adventure / magic / technology…），按 slug 对一次即可；
    /// 对不上就不过滤，总比筛错好。
    private func curseforgeCategoryId(for slug: String?) async -> Int? {
        guard let slug else { return nil }
        if curseforgeCategories == nil {
            curseforgeCategories = try? await Secrets.shared.curseforgeClient?
                .categories(classId: CurseForgeMod.classId(for: type))
        }
        return curseforgeCategories?.first { $0.slug == slug }?.id
    }
}
