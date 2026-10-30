//
//  ResourcesSearchPage.swift
//  PCL.Mac
//
//  Created by AnemoFlower on 2026/3/16.
//

import SwiftUI
import Core

/// 社区资源搜索页（Mod / 整合包 / 资源包 / 光影 / 数据包共用）。
///
/// 筛选条件与排版对齐 PCL2 的 PageResource：**左半边是名称与版本，右半边是来源与类型**，
/// 底下是「搜索 / 重置条件」两个按钮。改完条件要点「搜索」才生效，翻页沿用同一套条件。
struct ResourcesSearchPage: View {
    /// 下拉框里的「不限」选项。
    private static let allOption: String = "全部"
    private static let anyLoaderOption: String = "任意 Mod 加载器"

    @StateObject private var viewModel: ResourcesSearchViewModel
    /// 侧边栏条目上的「刷新」信号。
    @ObservedObject private var refreshCenter: ResourceRefreshCenter = .shared
    @State private var currentPage: Int = 0
    /// 已经发起过搜索的页码。用它挡住「点搜索 → currentPage 归零 → onChange 又搜一次」。
    @State private var lastRequestedPage: Int?
    /// 名称输入框与各个筛选下拉框的当前选择，点「搜索」时才写回 viewModel。
    @State private var nameInput: String = ""
    @State private var versionSelection: String = ResourcesSearchPage.allOption
    @State private var loaderSelection: String = ResourcesSearchPage.anyLoaderOption
    @State private var categorySelection: CategoryOption = .all
    @State private var source: ResourceSource = .all
    
    init(type: ResourceType) {
        self._viewModel = StateObject(wrappedValue: .init(type: type))
    }
    
    var body: some View {
        CardContainer {
            if viewModel.type == .shader {
                MyTip(text: "光影包需要搭配光影加载器使用。\n详细教程：https://cylorine.studio/helps/shader", theme: .blue)
                    .onTapGesture {
                        NSWorkspace.shared.open(URL(string: "https://cylorine.studio/helps/shader")!)
                    }
            }
            filterCard
                .cardIndex(1)
            
            if let searchResults = viewModel.searchResults {
                if viewModel.curseforgeSkipped {
                    MyTip(text: "CurseForge 这次没有返回结果（可能是没有内置 API Key 或网络问题），下面只有 Modrinth 的内容。", theme: .yellow)
                        .cardIndex(2)
                }
                PaginatedContainer(currentPage: $currentPage, pageCount: viewModel.totalPages) { _ in
                    MyCard(nil) {
                        LazyVStack(spacing: 0) {
                            ForEach(searchResults) { project in
                                ProjectListItemView(project: project)
                                    .onTapGesture {
                                        AppRouter.shared.append(.projectInstall(project: project))
                                    }
                            }
                        }
                    }
                }
                .cardIndex(3)
                .onChange(of: currentPage) { newValue in
                    // 已经搜过的页码不重复请求。
                    guard newValue != lastRequestedPage else { return }
                    requestSearch(page: newValue)
                }
            } else {
                MyLoading(viewModel: viewModel.loadingVM)
                    .cardIndex(3)
            }
        }
        .task {
            await viewModel.loadCategories()
            if lastRequestedPage == nil {
                requestSearch(page: 0)
            }
        }
        // 侧边栏条目的「刷新」：用当前界面上的条件重新搜一次，并回到第一页
        // （原版 PageDownloadLeft 的 Refresh 就是这个行为）。
        .onChange(of: refreshCenter.token(for: viewModel.type)) { _ in
            applyFilters()
            requestSearch(page: 0, forceRefresh: true)
        }
    }
    
    // MARK: - 筛选
    
    /// 左半边：名称 / 版本 / Mod 加载器；右半边：来源 / 类型（与原版同一套分组）。
    private var filterCard: some View {
        MyCard("搜索" + viewModel.type.localizedName, foldable: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingRow("名称", labelWidth: 80) {
                            MyTextField(text: $nameInput, placeholder: "搜索" + viewModel.type.localizedName)
                        }
                        SettingRow("版本", labelWidth: 80) {
                            MySelect($versionSelection, entries: versionOptions)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        SettingRow("来源", labelWidth: 50) {
                            MySelect($source, entries: sourceOptions)
                                .frame(maxWidth: .infinity)
                        }
                        SettingRow("类型", labelWidth: 50) {
                            MySelect($categorySelection, entries: categoryOptions)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 加载器单独占一行、铺满整张卡：它只在 Mod 页出现，
                // 塞在左半边会留下一条空荡荡的右半边。
                if viewModel.type == .mod {
                    SettingRow("Mod 加载器", labelWidth: 80) {
                        MySelect($loaderSelection, entries: loaderOptions)
                            .frame(maxWidth: .infinity)
                    }
                }
                
                HStack(spacing: 20) {
                    MyButton("搜索", type: .highlight) {
                        applyFilters()
                        requestSearch(page: 0)
                    }
                    .frame(width: 120)
                    MyButton("重置条件") {
                        resetFilters()
                    }
                    .frame(width: 120)
                    Spacer()
                }
                .frame(height: 35)
                .padding(.top, 2)
            }
        }
    }
    
    /// 版本下拉：全部 + 版本清单里最近的若干个正式版（原版也是一份固定列表）。
    private var versionOptions: [String] {
        let releases: [String] = VersionManifest.shared?.versions
            .filter { $0.type == .release }
            .prefix(12)
            .map(\.id) ?? []
        return [Self.allOption] + releases
    }
    
    private var loaderOptions: [String] {
        [Self.anyLoaderOption] + ModLoader.allCases.map(\.description)
    }
    
    /// 没有内置 CurseForge API Key 时不列出 CurseForge，免得选了只能看到报错。
    private var sourceOptions: [ResourceSource] {
        viewModel.curseforgeAvailable ? ResourceSource.allCases : [.all, .modrinth]
    }
    
    /// 类型下拉：全部 + Modrinth 该类型的类别标签（显示中文，提交 slug）。
    private var categoryOptions: [CategoryOption] {
        [.all] + viewModel.categories.map { .init(slug: $0) }
    }
    
    private func applyFilters() {
        viewModel.filterVersion = versionSelection == Self.allOption ? nil : versionSelection
        viewModel.filterLoader = ModLoader.allCases.first { $0.description == loaderSelection }
        viewModel.filterCategory = categorySelection.slug.isEmpty ? nil : categorySelection.slug
        viewModel.source = source
    }
    
    private func resetFilters() {
        nameInput = ""
        versionSelection = Self.allOption
        loaderSelection = Self.anyLoaderOption
        categorySelection = .all
        source = .all
        viewModel.resetFilters()
        applyFilters()
        requestSearch(page: 0)
    }
    
    /// 发起一次搜索。`lastRequestedPage` 先写，避免 currentPage 归零时被 onChange 再搜一遍。
    private func requestSearch(page: Int, forceRefresh: Bool = false) {
        lastRequestedPage = page
        if currentPage != page {
            currentPage = page
        }
        Task {
            do {
                try await viewModel.search(nameInput, pageIndex: page, forceRefresh: forceRefresh)
            } catch let error where error.isCancellationError {
            } catch {
                err("搜索\(viewModel.type.localizedName)失败：\(error.localizedDescription)")
                await MainActor.run {
                    viewModel.loadingVM.fail(with: "搜索\(viewModel.type.localizedName)失败：\(error.localizedDescription)")
                }
            }
        }
    }
    
    /// 「类型」下拉里的一项。
    ///
    /// 提交给接口的是 Modrinth 的 slug（`game-mechanics`），界面上显示它的中文名；
    /// 查不到译名就退回原文，绝不留空。
    struct CategoryOption: Hashable, CustomStringConvertible {
        let slug: String
        
        static let all: CategoryOption = .init(slug: "")
        
        var description: String {
            slug.isEmpty ? "全部" : (ProjectListItemModel.localizeTag(slug) ?? slug)
        }
    }
}

struct ProjectListItemView: View {
    private let project: ProjectListItemModel
    private let isTagRowSeparated: Bool
    
    init(project: ProjectListItemModel, primary: Bool = false) {
        self.project = project
        self.isTagRowSeparated = primary && project.tags.count > 3
    }
    
    var body: some View {
        MyListItem {
            HStack {
                Group {
                    if let iconURL: URL = project.iconURL {
                        NetworkImage(url: iconURL)
                    } else {
                        Image(.iconModLogo)
                            .resizable()
                            .scaledToFit()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(width: 48, height: 48)
                .padding(.leading, 4)
                
                VStack(alignment: .leading, spacing: 2) {
                    // 有译名时主标题显示译名，原名缩成灰字跟在后面（与原版一致）。
                    HStack(spacing: 6) {
                        MyText(project.displayTitle, size: 16)
                            .lineLimit(1)
                        if let translated = project.translatedTitle, translated != project.title {
                            MyText(project.title, size: 12, color: .colorGray3)
                                .lineLimit(1)
                        }
                    }
                    
                    if isTagRowSeparated {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(project.tags, id: \.self) { tag in
                                    MyTag(tag, labelColor: .colorGray2, backgroundColor: .init(0x000000, alpha: 17 / 255), size: 12)
                                }
                            }
                        }
                        
                        MyText(project.description, color: .colorGray3)
                    } else {
                        HStack {
                            ForEach(project.tags.prefix(3), id: \.self) { tag in
                                MyTag(tag, labelColor: .colorGray2, backgroundColor: .init(0x000000, alpha: 17 / 255), size: 12)
                            }
                            MyText(project.description, color: .colorGray3)
                                .lineLimit(1)
                        }
                    }
                    
                    HStack {
                        InformationView(icon: .iconSettingsPage, text: project.supportDescription, width: 200)
                        InformationView(icon: .iconDownloadPage, text: project.downloads, width: 150)
                        InformationView(icon: .iconUpload, text: project.lastUpdate, width: 150)
                        Spacer()
                    }
                    
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
        }
    }
    
    private struct InformationView: View {
        private let icon: ImageResource
        private let text: String
        private let width: CGFloat
        
        init(icon: ImageResource, text: String, width: CGFloat) {
            self.icon = icon
            self.text = text
            self.width = width
        }
        
        var body: some View {
            HStack(spacing: 6) {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14)
                    .foregroundStyle(Color.colorGray3)
                MyText(text, size: 12, color: .colorGray3)
            }
            .frame(width: width, alignment: .leading)
        }
    }
}
